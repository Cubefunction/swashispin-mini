// `default_nettype none
`timescale 1ns / 1ps
`include "dc.svh"
`include "li.svh"
`include "launch.svh"

module top_nexysv
    (input  logic i_clk,
     input  logic i_btn_c,
    
     input  logic i_rx,
     output logic o_tx,
     
     output logic [7:0] o_ja,
     output logic [7:0] o_jb,
     output logic [7:0] o_jc);

    localparam NUM_DC_CHANNEL=24;
    localparam NUM_LI_CHANNEL=1;

    localparam TOTAL_REGS=DC_SEQ_REGS+DC_CTRL_REGS+
                          LI_SEQ_REGS+LI_CTRL_REGS+
                          LCH_TOTAL_REGS;

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
        .i_rst(i_btn_c),
        .i_rx(i_rx),
        .o_tx(o_tx),
        .i_dvsr(11'd6),
        .o_regs(w_regs)
    );

    logic [0:NUM_DC_CHANNEL-1] w_dc_sclk_bus;
    logic [0:NUM_DC_CHANNEL-1] w_dc_mosi_bus;
    logic [0:NUM_DC_CHANNEL-1] w_dc_cs_n_bus;
    logic [0:NUM_DC_CHANNEL-1] w_dc_ldac_n_bus;

    dcli #(
        .NUM_DC_CHANNEL(NUM_DC_CHANNEL),
        .NUM_LI_CHANNEL(NUM_LI_CHANNEL)
    ) DCLI (
        .i_clk(i_clk),
        .i_rst(i_btn_c),

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

    io_nexysv #(
        .NUM_DC_CHANNEL(NUM_DC_CHANNEL),
        .NUM_LI_CHANNEL(NUM_LI_CHANNEL)
    ) IO (
        .i_dc_sclk_bus(w_dc_sclk_bus),
        .i_dc_mosi_bus(w_dc_mosi_bus),
        .i_dc_cs_n_bus(w_dc_cs_n_bus),
        .i_dc_ldac_n_bus(w_dc_ldac_n_bus),
        .i_dc_clr_n(1'b1),
        .i_dc_rst_n(1'b1),

        .o_ja(o_ja),
        .o_jb(o_jb),
        .o_jc(o_jc)
    );

endmodule
