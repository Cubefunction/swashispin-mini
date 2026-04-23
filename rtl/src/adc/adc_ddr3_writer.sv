`timescale 1ns/1ps

//==============================================================================
// adc_ddr3_writer
//------------------------------------------------------------------------------
//
// Parameters (defaults line up with the driver's defaults):
//   DATA_W         = 16    ADC sample width
//   DDR_W          = 128   DDR3 user-interface data width
//   ADDR_W         = 28    DDR3 byte-address width (matches mig_axi4_driver)
//   P_WR_BURST_LEN = 8     same as driver's P_WR_BURST_LEN
//   P_WR_BURST_NUM = 1     same as driver's P_WR_BURST_NUM
//   BASE_ADDR      = 0     first DDR3 address written in a session
//==============================================================================
module adc_ddr3_writer #(
    parameter int                    DATA_W         = 16,
    parameter int                    DDR_W          = 128,
    parameter int                    ADDR_W         = 28,
    parameter int                    P_WR_BURST_LEN = 8,
    parameter int                    P_WR_BURST_NUM = 1,
    parameter logic [ADDR_W-1:0]     BASE_ADDR      = '0
)(
    input  logic                     i_clk,
    input  logic                     i_rst,

    // control from adc_core
    input  logic                     i_active,

    // ADC sample stream
    input  logic signed [DATA_W-1:0] i_adc_data,
    input  logic                     i_adc_data_valid,

    // DDR3 driver user-side write port - connect to ddr3_top.i_user_wr_*
    output logic                     o_user_wr_valid,
    output logic [ADDR_W-1:0]        o_user_wr_addr_base,
    output logic [DDR_W-1:0]         o_user_wr_data,
    output logic                     o_user_wr_data_valid,

    output logic [ADDR_W-1:0]        o_bytes_written
);

    //--------------------------------------------------------------------------
    // Derived constants
    //--------------------------------------------------------------------------
    localparam int RATIO        = DDR_W / DATA_W;                  // samples per word  (8)
    localparam int WORDS_PER_TX = P_WR_BURST_LEN * P_WR_BURST_NUM; // words per tx      (8)
    localparam int BYTES_PER_TX = WORDS_PER_TX * (DDR_W/8);        // bytes per tx      (128)
    localparam int SAMP_CNT_W   = (RATIO        <= 1) ? 1 : $clog2(RATIO        + 1);
    localparam int WORD_CNT_W   = (WORDS_PER_TX <= 1) ? 1 : $clog2(WORDS_PER_TX + 1);

    // Elaboration-time parameter check - evaluated by the synthesis tool
    // at compile time, emits no hardware.
    if (DDR_W % DATA_W != 0) begin : gen_bad_ratio
        $error("adc_ddr3_writer: DDR_W (%0d) must be an integer multiple of DATA_W (%0d)",
               DDR_W, DATA_W);
    end

    //--------------------------------------------------------------------------
    // Internal state
    //--------------------------------------------------------------------------
    logic [DDR_W-1:0]      buf_data;         // work-in-progress word
    logic [SAMP_CNT_W-1:0] sample_cnt;       // next sample slot in buf_data (0..RATIO-1)
    logic [WORD_CNT_W-1:0] word_cnt;         // words already pushed in the current tx
    logic [ADDR_W-1:0]     tx_addr;          // base address of the current tx
    logic                  active_d;
    wire                   active_rise = i_active & ~active_d;
    wire                   active_fall = ~i_active & active_d;

    // flush FSM state
    logic                  flush_active;     // pushing zero (or last-partial) words
    logic                  flush_first_word; // first flush cycle uses buf_data, later cycles use '0


    logic [ADDR_W-1:0]     r_bytes_written;
    assign o_bytes_written = r_bytes_written;

    //--------------------------------------------------------------------------
    // Combinational buf_data after current sample is merged in
    //--------------------------------------------------------------------------
    logic [DDR_W-1:0] buf_next;
    always_comb begin
        buf_next = buf_data;
        if (i_adc_data_valid && i_active)
            buf_next[sample_cnt*DATA_W +: DATA_W] = i_adc_data;
    end

    //--------------------------------------------------------------------------
    // Main sequential logic
    //--------------------------------------------------------------------------
    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            buf_data             <= '0;
            sample_cnt           <= '0;
            word_cnt             <= '0;
            tx_addr              <= BASE_ADDR;
            active_d             <= 1'b0;
            flush_active         <= 1'b0;
            flush_first_word     <= 1'b0;
            r_bytes_written      <= '0;

            o_user_wr_valid      <= 1'b0;
            o_user_wr_addr_base  <= BASE_ADDR;
            o_user_wr_data       <= '0;
            o_user_wr_data_valid <= 1'b0;
        end
        else begin
            active_d             <= i_active;
            // pulse outputs default low every cycle
            o_user_wr_valid      <= 1'b0;
            o_user_wr_data_valid <= 1'b0;

            //------------------------------------------------------------------
            // priority 1: re-arm for a new sampling session
            //------------------------------------------------------------------
            if (active_rise) begin
                buf_data         <= '0;
                sample_cnt       <= '0;
                word_cnt         <= '0;
                tx_addr          <= BASE_ADDR;
                flush_active     <= 1'b0;
                flush_first_word <= 1'b0;
                r_bytes_written  <= '0;       // new session -> counter resets
            end
            //------------------------------------------------------------------
            // priority 2: ingest a sample (only while active and not flushing)
            //------------------------------------------------------------------
            else if (i_adc_data_valid && i_active && !flush_active) begin
                if (sample_cnt == SAMP_CNT_W'(RATIO-1)) begin
 
                    o_user_wr_data       <= buf_next;
                    o_user_wr_data_valid <= 1'b1;
                    sample_cnt           <= '0;
                    buf_data             <= '0;

                    // First word of a transaction also launches it
                    if (word_cnt == '0) begin
                        o_user_wr_valid     <= 1'b1;
                        o_user_wr_addr_base <= tx_addr;
                    end

                    // advance word counter + tx base address
                    if (word_cnt == WORD_CNT_W'(WORDS_PER_TX-1)) begin
                        word_cnt        <= '0;
                        tx_addr         <= tx_addr + ADDR_W'(BYTES_PER_TX);
                        r_bytes_written <= r_bytes_written + ADDR_W'(BYTES_PER_TX);
                    end
                    else begin
                        word_cnt <= word_cnt + 1'b1;
                    end
                end
                else begin
                    // still filling the word
                    buf_data   <= buf_next;
                    sample_cnt <= sample_cnt + 1'b1;
                end
            end
            //------------------------------------------------------------------
            // priority 3: detect end-of-session and arm the flush FSM
            //------------------------------------------------------------------
            else if (active_fall && ((sample_cnt != '0) || (word_cnt != '0))) begin
                flush_active     <= 1'b1;
                flush_first_word <= (sample_cnt != '0);
            end
            //------------------------------------------------------------------
            // priority 4: flush FSM - push one 128-bit word per cycle until
            //------------------------------------------------------------------
            else if (flush_active) begin
                o_user_wr_data_valid <= 1'b1;
                o_user_wr_data       <= flush_first_word ? buf_data : '0;
                flush_first_word     <= 1'b0;

                // first word of a transaction also launches it
                if (word_cnt == '0) begin
                    o_user_wr_valid     <= 1'b1;
                    o_user_wr_addr_base <= tx_addr;
                end

                // advance word counter + tx base address, decide if done
                if (word_cnt == WORD_CNT_W'(WORDS_PER_TX-1)) begin
                    word_cnt        <= '0;
                    tx_addr         <= tx_addr + ADDR_W'(BYTES_PER_TX);
                    r_bytes_written <= r_bytes_written + ADDR_W'(BYTES_PER_TX);
                    flush_active    <= 1'b0;               // flush complete
                    buf_data        <= '0;
                    sample_cnt      <= '0;
                end
                else begin
                    word_cnt <= word_cnt + 1'b1;
                end
            end
        end
    end

endmodule