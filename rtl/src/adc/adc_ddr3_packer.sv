`timescale 1ns/1ps


module adc_ddr3_packer #(
    parameter int                 DATA_W    = 16,           // ADC sample width (must divide DDR_W)
    parameter int                 DDR_W     = 128,          // DDR3 user data width
    parameter int                 ADDR_W    = 28,           // DDR3 byte-address width
    parameter int                 ADDR_STEP = DDR_W/8,      // bytes per DDR word
    parameter logic [ADDR_W-1:0]  BASE_ADDR = '0            // first DDR3 address of a session
)(
    input  logic                      i_clk,
    input  logic                      i_rst,

    // control
    input  logic                      i_active,          // from adc_core.o_active
    input  logic                      i_flush,           // optional: force flush partial word

    // ADC sample stream
    input  logic signed [DATA_W-1:0]  i_adc_data,
    input  logic                      i_adc_data_valid,

    // DDR3 write port (simple valid-only, add FIFO + ready handshake externally)
    output logic [DDR_W-1:0]          o_ddr_wdata,
    output logic [ADDR_W-1:0]         o_ddr_waddr,
    output logic                      o_ddr_wvalid,
    output logic [DDR_W/8-1:0]        o_ddr_wstrb,       // per-byte write strobe
    output logic                      o_ddr_wlast        // pulses with the final (possibly partial) word of a session
);

    //==============================================================================
    // Derived constants
    //==============================================================================
    localparam int RATIO            = DDR_W / DATA_W;                   // samples per word
    localparam int CNT_W            = (RATIO <= 1) ? 1 : $clog2(RATIO+1);
    localparam int BYTES_PER_SAMPLE = (DATA_W + 7) / 8;                 // ceil(DATA_W/8)
    localparam int TOTAL_STRB_W     = DDR_W / 8;

    // static check
    initial begin
        if (DDR_W % DATA_W != 0) begin
            $error("adc_ddr3_packer: DDR_W (%0d) must be a multiple of DATA_W (%0d)",
                   DDR_W, DATA_W);
        end
    end

    //==============================================================================
    // Internal state
    //==============================================================================
    logic [DDR_W-1:0]  buf_data;        // staging buffer
    logic [CNT_W-1:0]  sample_cnt;      // how many samples are already latched (0..RATIO-1)
    logic [ADDR_W-1:0] next_addr;       // address that will be used for next emitted word
    logic              active_d;
    logic              active_rise;
    logic              active_fall;

    assign active_rise =  i_active & ~active_d;
    assign active_fall = ~i_active &  active_d;

    //==============================================================================
    // Combinational shadow of the staging buffer after an incoming sample
    //==============================================================================
    logic [DDR_W-1:0] buf_next;
    always_comb begin
        buf_next = buf_data;
        if (i_adc_data_valid && i_active) begin
            // little-endian pack: sample_cnt = 0 goes in the lowest DATA_W bits
            buf_next[sample_cnt*DATA_W +: DATA_W] = i_adc_data;
        end
    end

    //==============================================================================
    // Strobe helper: full strobe for a complete word, masked strobe for a partial
    // flush word where only `n` samples are populated.
    //==============================================================================
    function automatic logic [TOTAL_STRB_W-1:0] partial_strobe(input int n);
        logic [TOTAL_STRB_W-1:0] s;
        int bytes_valid;
        begin
            bytes_valid = n * BYTES_PER_SAMPLE;
            s = '0;
            for (int b = 0; b < TOTAL_STRB_W; b++) begin
                s[b] = (b < bytes_valid);
            end
            return s;
        end
    endfunction

    //==============================================================================
    // Main sequential logic
    //==============================================================================
    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            buf_data      <= '0;
            sample_cnt    <= '0;
            next_addr     <= BASE_ADDR;
            active_d      <= 1'b0;

            o_ddr_wdata   <= '0;
            o_ddr_waddr   <= '0;
            o_ddr_wvalid  <= 1'b0;
            o_ddr_wstrb   <= '0;
            o_ddr_wlast   <= 1'b0;
        end
        else begin
            active_d     <= i_active;

            // defaults - pulse outputs only for the exact cycle they are emitted
            o_ddr_wvalid <= 1'b0;
            o_ddr_wlast  <= 1'b0;

            //------------------------------------------------------------------
            // Priority:
            //   1. active_rise  -> re-arm for a new session
            //   2. new sample   -> ingest (and emit word when full)
            //   3. active_fall / i_flush with non-empty buffer -> flush
            //------------------------------------------------------------------
            if (active_rise) begin
                sample_cnt <= '0;
                next_addr  <= BASE_ADDR;
                buf_data   <= '0;
            end
            else if (i_adc_data_valid && i_active) begin
                if (sample_cnt == CNT_W'(RATIO-1)) begin
                    // we just filled the word - emit it this cycle
                    o_ddr_wdata  <= buf_next;
                    o_ddr_waddr  <= next_addr;
                    o_ddr_wvalid <= 1'b1;
                    o_ddr_wstrb  <= {TOTAL_STRB_W{1'b1}};
                    o_ddr_wlast  <= 1'b0;

                    next_addr    <= next_addr + ADDR_W'(ADDR_STEP);
                    sample_cnt   <= '0;
                    buf_data     <= '0;
                end
                else begin
                    buf_data   <= buf_next;
                    sample_cnt <= sample_cnt + 1'b1;
                end
            end
            else if ((active_fall || i_flush) && (sample_cnt != '0)) begin
                // flush partial word (active_fall + i_adc_data_valid never overlap
                // in this design, so this branch is safe as a lower priority)
                o_ddr_wdata  <= buf_data;
                o_ddr_waddr  <= next_addr;
                o_ddr_wvalid <= 1'b1;
                o_ddr_wstrb  <= partial_strobe(int'(sample_cnt));
                o_ddr_wlast  <= 1'b1;

                next_addr    <= next_addr + ADDR_W'(ADDR_STEP);
                sample_cnt   <= '0;
                buf_data     <= '0;
            end
        end
    end

endmodule