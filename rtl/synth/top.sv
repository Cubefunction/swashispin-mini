// `default_nettype none
`timescale 1ns / 1ps
`include "dc.svh"
`include "launch.svh"

module top
    (input  logic i_clk, i_rst_n,
    
     input  logic i_rx,
     output logic o_tx,
     
     output logic o_a3, o_a5, o_a4, o_a6,
                  o_a9, o_a11, o_a10, o_a12,
                  o_a15, o_a17, o_a16, o_a18,
                  o_a21, o_a23, o_a22, o_a24,
                  o_a27, o_a29, o_a28, o_a30,
                  o_a33, o_a35, o_a34, o_a36,
                  o_a39, o_a41, o_a40, o_a42,
                  o_a45, o_a47, o_a46, o_a48,
                  o_a51, o_a53, o_a52, o_a54,
                  o_a57, o_a59, o_a58, o_a60,
                  o_a63, o_a65, o_a64, o_a66,
                  o_a69, o_a71, o_a70, o_a72,
                  o_a75, o_a77, o_a76, o_a78,

     output logic o_b3, o_b5, o_b4, o_b6,
                  o_b9, o_b11, o_b10, o_b12,
                  o_b15, o_b17, o_b16, o_b18,
                  o_b21, o_b23, o_b22, o_b24,
                  o_b27, o_b29, o_b28, o_b30,
                  o_b33, o_b35, o_b34, o_b36,
                  o_b39, o_b41, o_b40, o_b42,
                  o_b45, o_b47, /* o_b46, o_b48, */
                  o_b51, o_b53, o_b52, o_b54,
                  o_b57, o_b59, o_b58, o_b60,
                  o_b63, o_b65, o_b64, o_b66,
                  o_b69, o_b71, o_b70, o_b72,
                  o_b75, o_b77, o_b76, o_b78);

    localparam NUM_DC_CHANNEL=24;

    localparam TOTAL_REGS=DC_SEQ_REGS+DC_CTRL_REGS+LCH_TOTAL_REGS;

    logic [0:TOTAL_REGS-1][31:0] w_regs;

    uart_regs #(
        .DATA_WIDTH(8),
        .RX_FIFO_DEPTH(8),
        .RX_FIFO_AF_DEPTH(6),
        .RX_FIFO_AE_DEPTH(2),
        .TX_FIFO_DEPTH(8),
        .TX_FIFO_AF_DEPTH(6),
        .TX_FIFO_AE_DEPTH(2),
        .NUM_REGS(TOTAL_REGS)
    ) REGS (
        .i_clk(i_clk),
        .i_rst(!i_rst_n),
        .i_rx(i_rx),
        .o_tx(o_tx),
        .i_dvsr(11'd6),
        .o_regs(w_regs)
    );

    logic [0:NUM_DC_CHANNEL-1] w_dc_sclk_bus;
    logic [0:NUM_DC_CHANNEL-1] w_dc_mosi_bus;
    logic [0:NUM_DC_CHANNEL-1] w_dc_cs_n_bus;
    logic [0:NUM_DC_CHANNEL-1] w_dc_ldac_n_bus;

    processor #(
        .NUM_DC_CHANNEL(NUM_DC_CHANNEL)
    ) PROCESSOR (
        .i_clk(i_clk),
        .i_rst(!i_rst_n),

        .i_regs(w_regs),

        .o_dc_sclk_bus(w_dc_sclk_bus),
        .o_dc_mosi_bus(w_dc_mosi_bus),
        .i_dc_miso_bus('h0),
        .o_dc_cs_n_bus(w_dc_cs_n_bus),
        .o_dc_ldac_n_bus(w_dc_ldac_n_bus),

        .o_dc_armed_bus(),
        .o_dc_empty_bus(),
        .o_dc_eop_bus()
    );

    io #(
        .NUM_DC_CHANNEL(NUM_DC_CHANNEL)
    ) IO (
        .i_dc_sclk_bus(w_dc_sclk_bus),
        .i_dc_mosi_bus(w_dc_mosi_bus),
        .i_dc_cs_n_bus(w_dc_cs_n_bus),
        .i_dc_ldac_n_bus(w_dc_ldac_n_bus),
        .i_dc_clr_n(1'b1),
        .i_dc_rst_n(1'b1),

        .i_aux_bus({w_dc_ldac_n_bus[13], w_dc_cs_n_bus[1], 4'h0}),

        .*
    );

endmodule
