`timescale 1ns / 1ps

module uart_api_dc
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
     
     output logic [DAC_CHANNEL-1:0] o_sclk,
     output logic [DAC_CHANNEL-1:0] o_mosi,
     output logic [DAC_CHANNEL-1:0] o_cs_n,
     output logic [DAC_CHANNEL-1:0] o_ldac_n);

    logic w_deq_rxq, w_rxq_empty;
    logic [7:0] w_rxq_data;
    
    localparam NUM_BYTES = INSN_WIDTH / 8;
    localparam FRAME_BYTES = TOTAL_REGS * 4; 
    
    uart #(
        .DATA_WIDTH(8),
        .RX_FIFO_DEPTH(100),
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
        .DEPTH(64),       
        .AF_DEPTH(56),
        .AE_DEPTH(8)
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

    logic [TOTAL_REGS-1:0][31:0]   w_dc_regs;       
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
        .o_dc_regs(w_dc_regs),
        .o_channel_sel(w_channel_sel),
        .o_valid_frame(w_valid_frame),
        .o_launch_cmd(w_launch_cmd_reg),
        .o_launch_valid(w_launch_valid)
    );

    logic [DAC_CHANNEL-1:0]             r_dc_valid_flags;  
    logic [DAC_CHANNEL-1:0]             w_start;     
    logic [DAC_CHANNEL-1:0]             w_armed;     

    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            r_dc_valid_flags <= 'h0;
        end 
        else if (w_valid_frame) begin
            case (w_channel_sel)
                5'd0 :  r_dc_valid_flags[0]  <= 1'b1;
                5'd1 :  r_dc_valid_flags[1]  <= 1'b1;
                5'd2 :  r_dc_valid_flags[2]  <= 1'b1;
                5'd3 :  r_dc_valid_flags[3]  <= 1'b1;
                // 5'd4 :  r_dc_valid_flags[4]  <= 1'b1;
                // 5'd5 :  r_dc_valid_flags[5]  <= 1'b1;
                // 5'd6 :  r_dc_valid_flags[6]  <= 1'b1;
                // 5'd7 :  r_dc_valid_flags[7]  <= 1'b1;
                // 5'd8 :  r_dc_valid_flags[8]  <= 1'b1;
                // 5'd9 :  r_dc_valid_flags[9]  <= 1'b1;
                // 5'd10:  r_dc_valid_flags[10] <= 1'b1;
                // 5'd11:  r_dc_valid_flags[11] <= 1'b1;
                // 5'd12:  r_dc_valid_flags[12] <= 1'b1;
                // 5'd13:  r_dc_valid_flags[13] <= 1'b1;
                // 5'd14:  r_dc_valid_flags[14] <= 1'b1;
                // 5'd15:  r_dc_valid_flags[15] <= 1'b1;
                // 5'd16:  r_dc_valid_flags[16] <= 1'b1;
                // 5'd17:  r_dc_valid_flags[17] <= 1'b1;
                // 5'd18:  r_dc_valid_flags[18] <= 1'b1;
                // 5'd19:  r_dc_valid_flags[19] <= 1'b1;
                // 5'd20:  r_dc_valid_flags[20] <= 1'b1;
                // 5'd21:  r_dc_valid_flags[21] <= 1'b1;
                // 5'd22:  r_dc_valid_flags[22] <= 1'b1;
                // 5'd23:  r_dc_valid_flags[23] <= 1'b1;
                default: ;
            endcase
        end
        else if (r_dc_valid_flags != 'h0) begin
            r_dc_valid_flags <= 'h0;
        end
    end

    genvar i;
    generate
        for (i = 0; i < DAC_CHANNEL; i++) begin : GEN_DC
            dc #(
                .DAC_WIDTH(DAC_WIDTH),
                .CYCLE_WIDTH(CYCLE_WIDTH),
                .STREAM_ITER_WIDTH(STREAM_ITER_WIDTH),
                .CORE_ITER_WIDTH(CORE_ITER_WIDTH),
                .DEPTH(DEPTH)
                ) u_dc (
                .i_clk(i_clk),
                .i_rst(i_rst),
                .i_regs({31'h0, r_dc_valid_flags[i], w_dc_regs[TOTAL_REGS-2:0]}),
                .i_start(w_start[i]),
                .o_armed(w_armed[i]),
                .o_sclk(o_sclk[i]),
                .o_mosi(o_mosi[i]),
                .o_cs_n(o_cs_n[i]),
                .o_ldac_n(o_ldac_n[i])
            );
        end
    endgenerate

    launch #(
    .NUM_DC_CHANNEL(DAC_CHANNEL),
    .NUM_RF_CHANNEL(7),
    .NUM_LI_CHANNEL(2)
    ) u_launch (
       .i_clk(i_clk), 
       .i_rst(i_rst),

       .i_regs({31'h0, w_launch_valid, w_launch_cmd_reg[2:0]}),

       .i_dc_armed(w_armed),
       .i_rf_armed(7'h0),
       .i_li_armed(2'h0),

       .o_dc_start(w_start),
       .o_rf_start(),
       .o_li_start(),
       .i_trigger(1'b1)
    );


endmodule
