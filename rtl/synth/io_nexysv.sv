// `default_nettype none
`timescale 1ns / 1ps
`include "dc.svh"

module io_nexysv
   #(parameter NUM_DC_CHANNEL=24,
     parameter NUM_LI_CHANNEL=1)
    (input  logic [0:NUM_DC_CHANNEL-1] i_dc_sclk_bus,
     input  logic [0:NUM_DC_CHANNEL-1] i_dc_mosi_bus,
     input  logic [0:NUM_DC_CHANNEL-1] i_dc_cs_n_bus,
     input  logic [0:NUM_DC_CHANNEL-1] i_dc_ldac_n_bus,
     input  logic i_dc_clr_n, i_dc_rst_n,

     output logic [7:0] o_ja,
     output logic [7:0] o_jb,
     output logic [7:0] o_jc);

     assign o_ja[7] = 1'b1;
     assign o_ja[6] = 1'b1;
     assign o_ja[5] = 1'b1;
     assign o_ja[4] = i_dc_ldac_n_bus[0];
     assign o_ja[3] = i_dc_sclk_bus[0];
     assign o_ja[2] = 1'b0;
     assign o_ja[1] = i_dc_mosi_bus[0];
     assign o_ja[0] = i_dc_cs_n_bus[0];
     
     assign o_jb[7] = 1'b1;
     assign o_jb[6] = 1'b1;
     assign o_jb[5] = 1'b1;
     assign o_jb[4] = i_dc_ldac_n_bus[1];
     assign o_jb[3] = i_dc_sclk_bus[1];
     assign o_jb[2] = 1'b0;
     assign o_jb[1] = i_dc_mosi_bus[1];
     assign o_jb[0] = i_dc_cs_n_bus[1];
     
     assign o_jc[7] = 1'b1;
     assign o_jc[6] = 1'b1;
     assign o_jc[5] = 1'b1;
     assign o_jc[4] = i_dc_ldac_n_bus[2];
     assign o_jc[3] = i_dc_sclk_bus[2];
     assign o_jc[2] = 1'b0;
     assign o_jc[1] = i_dc_mosi_bus[2];
     assign o_jc[0] = i_dc_cs_n_bus[2];

//     assign o_ja[7] = i_dc_ldac_n_bus[1];
//     assign o_ja[6] = i_dc_mosi_bus[1];
//     assign o_ja[5] = i_dc_sclk_bus[1];
//     assign o_ja[4] = i_dc_cs_n_bus[1];

//     assign o_jb[3] = i_dc_ldac_n_bus[2];
//     assign o_jb[2] = i_dc_mosi_bus[2];
//     assign o_jb[1] = i_dc_sclk_bus[2];
//     assign o_jb[0] = i_dc_cs_n_bus[2];

//     assign o_jb[7] = 1'b1;
//     assign o_jb[6] = 1'b1;
//     assign o_jb[5] = i_dc_clr_n;
//     assign o_jb[4] = i_dc_rst_n;

//     assign o_jc[3] = i_dc_ldac_n_bus[3];
//     assign o_jc[2] = i_dc_mosi_bus[3];
//     assign o_jc[1] = i_dc_sclk_bus[3];
//     assign o_jc[0] = i_dc_cs_n_bus[3];

//     assign o_jc[7] = i_dc_ldac_n_bus[4];
//     assign o_jc[6] = i_dc_mosi_bus[4];
//     assign o_jc[5] = i_dc_sclk_bus[4];
//     assign o_jc[4] = i_dc_cs_n_bus[4];

endmodule
