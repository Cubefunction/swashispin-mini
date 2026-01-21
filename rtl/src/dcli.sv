// `default_nettype none
`timescale 1ns / 1ps
`include "dc.svh"
//`include "rf.svh"
`include "launch.vh"

module dcli
   #(parameter NUM_DC_CHANNEL=24,
     parameter NUM_LI_CHANNEL=1)
    (input  logic i_clk, i_rst,

     input  logic [0:DC_TOTAL_REGS-1][31:0] i_dc_regs,

     output logic [0:NUM_DC_CHANNEL-1] o_dc_sclk_bus,
     output logic [0:NUM_DC_CHANNEL-1] o_dc_mosi_bus,
     input  logic [0:NUM_DC_CHANNEL-1] i_dc_miso_bus,
     output logic [0:NUM_DC_CHANNEL-1] o_dc_cs_n_bus,
     output logic [0:NUM_DC_CHANNEL-1] o_dc_ldac_n_bus,

     input  logic [0:LCH_TOTAL_REGS-1][31:0] i_lch_regs);
     
    logic [NUM_DC_CHANNEL-1:0] w_dc_start_bus;
    logic [NUM_DC_CHANNEL-1:0] w_dc_armed_bus;

    for (genvar i = 0; i < NUM_DC_CHANNEL; i++) begin : DC_GEN

        dc DC (
            .i_clk(i_clk),
            .i_rst(i_rst),

            .i_regs({i_dc_regs[0:DC_TOTAL_REGS-2], 
                     31'h0, i_dc_regs[DC_TOTAL_REGS-1][i]}),

            .o_sclk(o_dc_sclk_bus[i]),
            .o_mosi(o_dc_mosi_bus[i]),
            .i_miso(i_dc_miso_bus[i]),
            .o_cs_n(o_dc_cs_n_bus[i]),
            .o_ldac_n(o_dc_ldac_n_bus[i]),

            .i_start(w_dc_start_bus[i]),
            .o_armed(w_dc_armed_bus[i])
        );

    end

    launch #(
        .NUM_DC_CHANNEL(NUM_DC_CHANNEL),
        .NUM_RF_CHANNEL(1),
        .NUM_LI_CHANNEL(NUM_LI_CHANNEL)
    ) LCH (
        .i_clk(i_clk),
        .i_rst(i_rst),

        .i_regs(i_lch_regs),

        .i_dc_armed(w_dc_armed_bus),
        .i_rf_armed(1'b0),
        .i_li_armed(NUM_LI_CHANNEL'('h0)),

        .i_trigger(1'b1),

        .o_dc_start(w_dc_start_bus),
        .o_rf_start(),
        .o_li_start()
    );

endmodule
