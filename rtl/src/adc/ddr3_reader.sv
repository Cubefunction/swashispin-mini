`timescale 1ns/1ps

//==============================================================================
// ddr3_reader  (STREAM version, burst-aware)
//==============================================================================
module ddr3_reader #(
    parameter int DDR_DATA_W     = 128,
    parameter int DDR_ADDR_W     = 28,
    parameter int P_RD_BURST_LEN = 8,
    parameter int P_RD_BURST_NUM = 1
)(
    input  logic                     i_clk,
    input  logic                     i_rst,

    // Stream control from uart_regs
    input  logic                     i_stream_start,
    input  logic [DDR_ADDR_W-1:0]    i_start_addr,
    input  logic [DDR_ADDR_W-1:0]    i_total_bytes,
    output logic                     o_stream_done,

    // Byte stream to uart_regs
    output logic [7:0]               o_stream_byte,
    output logic                     o_stream_valid,
    input  logic                     i_stream_ready,

    // DDR3 user-side read port (connect to ddr3_top.i_user_rd_* / o_user_rd_*)
    output logic                     o_user_rd_valid,
    output logic [DDR_ADDR_W-1:0]    o_user_rd_addr_base,
    input  logic                     i_user_rd_data_valid,
    input  logic [DDR_DATA_W-1:0]    i_user_rd_data,
    input  logic                     i_user_rd_finish
);

    //--------------------------------------------------------------------------
    // Derived constants
    //--------------------------------------------------------------------------
    localparam int BYTES_PER_WORD = DDR_DATA_W / 8;                   // 16
    localparam int BURST_WORDS    = P_RD_BURST_LEN * P_RD_BURST_NUM;  // 8
    localparam int BURST_BYTES    = BURST_WORDS * BYTES_PER_WORD;     // 128

    localparam int BYTE_IDX_W = (BYTES_PER_WORD <= 1) ? 1 : $clog2(BYTES_PER_WORD);
    localparam int WORD_IDX_W = (BURST_WORDS    <= 1) ? 1 : $clog2(BURST_WORDS);

    // +1 bit headroom so we can represent "== BURST_WORDS" as a terminal value
    localparam logic [WORD_IDX_W:0] LAST_WORD  = (WORD_IDX_W+1)'(BURST_WORDS - 1);
    localparam logic [WORD_IDX_W:0] FULL_BURST = (WORD_IDX_W+1)'(BURST_WORDS);

    //--------------------------------------------------------------------------
    // FSM
    //--------------------------------------------------------------------------
    typedef enum logic [1:0] {
        S_IDLE  = 2'd0,
        S_REQ   = 2'd1,
        S_BURST = 2'd2,
        S_DONE  = 2'd3
    } state_e;

    state_e state;

    //--------------------------------------------------------------------------
    // Local word buffer
    //   Catch: catch_idx points at the next slot to be filled.  Incremented on
    //          every i_user_rd_data_valid while we are in S_BURST.
    //   Drain: drain_word_idx points at the slot currently being byte-drained,
    //          drain_byte_idx picks the byte within that word.  A byte is
    //          available whenever drain_word_idx < catch_idx.
    //--------------------------------------------------------------------------
    logic [DDR_DATA_W-1:0]   word_buf [BURST_WORDS];
    logic [WORD_IDX_W:0]     catch_idx;
    logic [WORD_IDX_W:0]     drain_word_idx;
    logic [BYTE_IDX_W-1:0]   drain_byte_idx;

    logic [DDR_ADDR_W-1:0]   cur_addr;    // base of the CURRENT burst
    logic [DDR_ADDR_W-1:0]   bytes_left;  // bytes in session still to emit

    //--------------------------------------------------------------------------
    // Combinational stream outputs
    //--------------------------------------------------------------------------
    wire drain_has_word = (state == S_BURST) && (drain_word_idx < catch_idx);

    assign o_stream_valid = drain_has_word;
    assign o_stream_byte  =
        word_buf[drain_word_idx[WORD_IDX_W-1:0]]
                [((BYTES_PER_WORD-1-drain_byte_idx)*8) +: 8];

    //--------------------------------------------------------------------------
    // Sequential logic
    //--------------------------------------------------------------------------
    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            state               <= S_IDLE;
            o_user_rd_valid     <= 1'b0;
            o_user_rd_addr_base <= '0;
            o_stream_done       <= 1'b0;
            cur_addr            <= '0;
            bytes_left          <= '0;
            catch_idx           <= '0;
            drain_word_idx      <= '0;
            drain_byte_idx      <= '0;
        end
        else begin
            // defaults
            o_user_rd_valid <= 1'b0;
            o_stream_done   <= 1'b0;

            //------------------------------------------------------------------
            // Catch MIG words (independent of the main state case).  Only
            // active in S_BURST so the same data_valid pulse can't race with
            // the catch_idx reset done in S_REQ.
            //------------------------------------------------------------------
            if ((state == S_BURST) && i_user_rd_data_valid
                && (catch_idx < FULL_BURST)) begin
                word_buf[catch_idx[WORD_IDX_W-1:0]] <= i_user_rd_data;
                catch_idx                           <= catch_idx + 1'b1;
            end

            //------------------------------------------------------------------
            // Main state
            //------------------------------------------------------------------
            unique case (state)
                //--------------------------------------------------------------
                S_IDLE: begin
                    if (i_stream_start) begin
                        cur_addr   <= i_start_addr;
                        bytes_left <= i_total_bytes;
                        if (i_total_bytes == '0) begin
                            state <= S_DONE;           // nothing to send
                        end
                        else begin
                            state <= S_REQ;
                        end
                    end
                end

                //--------------------------------------------------------------
                S_REQ: begin
                    o_user_rd_valid     <= 1'b1;
                    o_user_rd_addr_base <= cur_addr;
                    catch_idx           <= '0;
                    drain_word_idx      <= '0;
                    drain_byte_idx      <= '0;
                    state               <= S_BURST;
                end

                //--------------------------------------------------------------
                S_BURST: begin
                    // catch handled above; drain here
                    if (drain_has_word && i_stream_ready) begin
                        bytes_left <= bytes_left - 1'b1;

                        if (bytes_left == 1) begin
                            // final byte of the whole session
                            state <= S_DONE;
                        end
                        else if (drain_byte_idx ==
                                 BYTE_IDX_W'(BYTES_PER_WORD-1)) begin
                            drain_byte_idx <= '0;
                            if (drain_word_idx == LAST_WORD) begin
                                // consumed the last word of this burst,
                                // but more bytes still remain in the session
                                drain_word_idx <= '0;
                                cur_addr       <= cur_addr
                                                  + DDR_ADDR_W'(BURST_BYTES);
                                state          <= S_REQ;
                            end
                            else begin
                                drain_word_idx <= drain_word_idx + 1'b1;
                            end
                        end
                        else begin
                            drain_byte_idx <= drain_byte_idx + 1'b1;
                        end
                    end
                end

                //--------------------------------------------------------------
                S_DONE: begin
                    o_stream_done <= 1'b1;
                    state         <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule