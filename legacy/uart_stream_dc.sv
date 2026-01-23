`timescale 1ns / 1ps

module uart_stream_dc
   #(parameter DAC_WIDTH=16,
     parameter CYCLE_WIDTH=30,
     parameter DAC_CHANNEL=24,
     parameter CHANNEL_MES_WIDTH=96,
     parameter STREAM_ITER_WIDTH=10,
     parameter CORE_ITER_WIDTH=10,
     parameter DEPTH=10,
     parameter INSN_WIDTH=DAC_WIDTH*2+CORE_ITER_WIDTH+CYCLE_WIDTH,
     parameter TOTAL_REGS=DEPTH*3+2)
    (input  logic i_clk, i_rst,

     input  logic i_rx,

     //input  logic i_trigger,
     output logic [TOTAL_REGS-1:0][31:0]   o_dc_regs
     );

    logic w_deq_rxq, w_rxq_empty;
    logic [7:0] w_rxq_data;
    
    localparam NUM_BYTES = INSN_WIDTH / 8;
    localparam FRAME_BYTES = TOTAL_REGS * 4; 
    
    uart #(
        .DATA_WIDTH(8),
        .RX_FIFO_DEPTH(20),
        .RX_FIFO_AF_DEPTH(16),
        .RX_FIFO_AE_DEPTH(4),
        .TX_FIFO_DEPTH(20),
        .TX_FIFO_AF_DEPTH(16),
        .TX_FIFO_AE_DEPTH(4)
    ) U (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_rx(i_rx),
        .o_tx(),
        .i_deq_rxq(w_deq_rxq),
        .o_rxq_data(w_rxq_data),
        .o_rxq_empty(w_rxq_empty),
        .o_rxq_ae(),
        .o_rxq_full(),
        .o_rxq_af(),
        .i_enq_txq(),
        .i_txq_data(),
        .o_txq_empty(),
        .o_txq_ae(),
        .o_txq_full(),
        .o_txq_af()
    );

    assign w_deq_rxq = !w_rxq_empty;

// ================================================================
// UART-----FIFO32 
// ================================================================

    logic [1:0]  r_byte_cnt;
    logic [31:0] r_word_buf;
    logic        r_fifo32_enq;

    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            r_byte_cnt <= 'd0;
            r_word_buf <= 'd0;
        end
        else if (w_deq_rxq) begin
            r_word_buf <= {r_word_buf[23:0], w_rxq_data};

            if (r_byte_cnt == 'd3) begin
                r_byte_cnt <= 'd0;
                r_fifo32_enq <= 1'b1;
            end
            else begin
                r_byte_cnt <= r_byte_cnt + 'd1;
            end
        end
        else begin
            r_fifo32_enq <= 1'b0;
        end
    end

// ================================================================
// 32-bit FIFO 
// ================================================================

    logic        w_fifo32_full, w_fifo32_empty;
    logic [31:0] w_fifo32_dout;
    logic        w_fifo32_deq;

    fifo #(
        .WIDTH(32),
        .DEPTH(20),       
        .AF_DEPTH(16),
        .AE_DEPTH(4)
    ) u_fifo32 (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_data(r_word_buf),
        .i_enq(r_fifo32_enq),
        .i_deq(w_fifo32_deq),   
        .o_data(w_fifo32_dout),
        .o_full(w_fifo32_full),
        .o_empty(w_fifo32_empty),
        .o_almost_full(),
        .o_almost_empty()
    );
// ================================================================
// 32*32 register from fifo
// ================================================================

          
    logic [4:0]          w_channel_sel;   
    logic                w_valid_frame; 
    logic [3:0][31:0]    w_launch_cmd_reg;
    logic                w_launch_valid;

    dc_dispatcher #(
        .DAC_CHANNEL(DAC_CHANNEL),
        .FRAME_WORDS(TOTAL_REGS)
    ) u_dispatcher (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_fifo_data(w_fifo32_dout),
        .i_fifo_empty(w_fifo32_empty),
        .o_fifo_deq(w_fifo32_deq),
        .o_dc_regs(o_dc_regs),
        .o_channel_sel(w_channel_sel),
        .o_valid_frame(w_valid_frame),
        .o_launch_cmd(w_launch_cmd_reg),
        .o_launch_valid(w_launch_valid)
    );

endmodule
