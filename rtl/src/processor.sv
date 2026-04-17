// `default_nettype none
`timescale 1ns / 1ps
`include "dc.svh"
`include "launch.svh"

module processor
   #(parameter NUM_DC_CHANNEL=24,
     parameter NUM_LI_CHANNEL=1,
     parameter TOTAL_REGS=DC_SEQ_REGS+DC_CTRL_REGS+
                          LI_SEQ_REGS+LI_CTRL_REGS+
                          LCH_TOTAL_REGS)
    (input  logic i_clk, i_rst,

     // uart registers
     input  logic [0:TOTAL_REGS-1][31:0] i_regs,

     // dc spi buses
     output logic [0:NUM_DC_CHANNEL-1] o_dc_sclk_bus,
     output logic [0:NUM_DC_CHANNEL-1] o_dc_mosi_bus,
     input  logic [0:NUM_DC_CHANNEL-1] i_dc_miso_bus,
     output logic [0:NUM_DC_CHANNEL-1] o_dc_cs_n_bus,
     output logic [0:NUM_DC_CHANNEL-1] o_dc_ldac_n_bus,

     // dc armed bus for LED
     output logic [NUM_DC_CHANNEL-1:0] o_dc_armed_bus,

     // dc empty bus for simulation
     output logic [0:NUM_DC_CHANNEL-1] o_dc_empty_bus,

     // dc eop bus
     output dc_eop_t [0:NUM_DC_CHANNEL-1] o_dc_eop_bus);

    localparam DC_SEQ_START = 0;
    localparam DC_SEQ_END = DC_SEQ_START + DC_SEQ_REGS - 1;

    localparam DC_CTRL_START = DC_SEQ_END + 1;
    localparam DC_CTRL_END = DC_CTRL_START + DC_CTRL_REGS - 1;

    localparam LI_SEQ_START = DC_CTRL_END + 1;
    localparam LI_SEQ_END = LI_SEQ_START + LI_SEQ_REGS - 1;

    localparam LI_CTRL_START = LI_SEQ_END + 1;
    localparam LI_CTRL_END = LI_CTRL_START + LI_CTRL_REGS - 1;

    localparam LCH_START = LI_CTRL_END + 1;
    localparam LCH_END = LCH_START + LCH_TOTAL_REGS - 1;
     
    /****************
    * dc connections
    ****************/

    logic [NUM_DC_CHANNEL-1:0] w_dc_start_bus;
    logic [NUM_DC_CHANNEL-1:0] w_dc_armed_bus;

    for (genvar i = 0; i < NUM_DC_CHANNEL; i++) begin : DC_GEN

        dc DC (
            .i_clk(i_clk),
            .i_rst(i_rst),

            .i_seq_regs({i_regs[DC_SEQ_START:DC_SEQ_END-1], 31'h0, 
                         i_regs[DC_SEQ_END][i]}),

            .i_ctrl_regs({i_regs[DC_CTRL_START:DC_CTRL_END-1], 31'h0, 
                          i_regs[DC_CTRL_END][i]}),

            .o_sclk(o_dc_sclk_bus[i]),
            .o_mosi(o_dc_mosi_bus[i]),
            .i_miso(i_dc_miso_bus[i]),
            .o_cs_n(o_dc_cs_n_bus[i]),
            .o_ldac_n(o_dc_ldac_n_bus[i]),

            .i_start(w_dc_start_bus[i]),
            .o_armed(w_dc_armed_bus[i]),

            .o_empty(o_dc_empty_bus[i]),

            .o_eop(o_dc_eop_bus[i])
        );

    end

    /********************
    * launch connections
    ********************/

    launch #(
        .NUM_DC_CHANNEL(NUM_DC_CHANNEL),
        .NUM_RF_CHANNEL(1),
        .NUM_LI_CHANNEL(NUM_LI_CHANNEL)
    ) LCH (
        .i_clk(i_clk),
        .i_rst(i_rst),

        .i_regs(i_regs[LCH_START:LCH_END]),

        .i_dc_armed(w_dc_armed_bus),
        .i_rf_armed(1'b0),
        .i_li_armed(NUM_LI_CHANNEL'('h0)),

        .i_trigger(1'b1),

        .o_dc_start(w_dc_start_bus),
        .o_rf_start(),
        .o_li_start()
    );

    assign o_dc_armed_bus = w_dc_armed_bus;

endmodule
