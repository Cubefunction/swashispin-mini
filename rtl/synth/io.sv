// `default_nettype none
`timescale 1ns / 1ps
`include "dc.svh"

module io
   #(parameter NUM_DC_CHANNEL=24)
    (input  logic [0:NUM_DC_CHANNEL-1] i_dc_sclk_bus,
     input  logic [0:NUM_DC_CHANNEL-1] i_dc_mosi_bus,
     input  logic [0:NUM_DC_CHANNEL-1] i_dc_cs_n_bus,
     input  logic [0:NUM_DC_CHANNEL-1] i_dc_ldac_n_bus,
     input  logic i_dc_clr_n, i_dc_rst_n,

     input  logic [0:5] i_aux_bus,

     // bank A
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

     // bank B
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

    // bank A
    assign o_a3 = i_dc_sclk_bus[10];
    assign o_a5 = i_dc_ldac_n_bus[22];
    assign o_a4 = i_dc_mosi_bus[23];
    assign o_a6 = i_aux_bus[5];

    assign o_a9 = i_dc_mosi_bus[10];
    assign o_a11 = i_dc_mosi_bus[22];
    assign o_a10 = i_dc_cs_n_bus[11];
    assign o_a12 = i_aux_bus[4];

    assign o_a15 = i_dc_ldac_n_bus[10];
    assign o_a17 = i_dc_sclk_bus[22];
    assign o_a16 = i_dc_sclk_bus[23];
    assign o_a18 = i_aux_bus[3];

    assign o_a21 = i_aux_bus[1];
    assign o_a23 = i_dc_cs_n_bus[22];
    assign o_a22 = i_dc_sclk_bus[11];
    assign o_a24 = i_aux_bus[2];

    assign o_a27 = i_dc_cs_n_bus[9];
    assign o_a29 = i_aux_bus[0];
    assign o_a28 = i_dc_cs_n_bus[23];
    assign o_a30 = i_dc_cs_n_bus[10];

    assign o_a33 = i_dc_sclk_bus[9];
    assign o_a35 = i_dc_ldac_n_bus[21];
    assign o_a34 = i_dc_mosi_bus[11];
    assign o_a36 = i_dc_ldac_n_bus[23];

    assign o_a39 = i_dc_mosi_bus[9];
    assign o_a41 = i_dc_mosi_bus[21];
    assign o_a40 = i_dc_ldac_n_bus[11];
    assign o_a42 = i_dc_mosi_bus[20];

    assign o_a45 = i_dc_ldac_n_bus[9];
    assign o_a47 = i_dc_sclk_bus[21];
    assign o_a46 = i_dc_ldac_n_bus[20];
    assign o_a48 = i_dc_cs_n_bus[8];

    assign o_a51 = i_dc_mosi_bus[8];
    assign o_a53 = i_dc_cs_n_bus[20];
    assign o_a52 = i_dc_sclk_bus[8];
    assign o_a54 = i_dc_sclk_bus[20];

    assign o_a57 = i_dc_cs_n_bus[7];
    assign o_a59 = i_dc_mosi_bus[19];
    assign o_a58 = i_dc_ldac_n_bus[19];
    assign o_a60 = i_dc_ldac_n_bus[8];

    assign o_a63 = i_dc_mosi_bus[7];
    assign o_a65 = i_dc_cs_n_bus[19];
    assign o_a64 = i_dc_sclk_bus[7];
    assign o_a66 = i_dc_sclk_bus[19];

    assign o_a69 = i_dc_mosi_bus[18];
    assign o_a71 = i_dc_cs_n_bus[21];
    assign o_a70 = i_dc_ldac_n_bus[18];
    assign o_a72 = i_dc_ldac_n_bus[7];

    assign o_a75 = i_dc_cs_n_bus[18];
    assign o_a77 = i_dc_sclk_bus[6];
    assign o_a76 = i_dc_sclk_bus[18];
    assign o_a78 = i_dc_cs_n_bus[6];

    // bank B
    assign o_b3 = i_dc_mosi_bus[3];
    assign o_b5 = i_dc_cs_n_bus[15];
    assign o_b4 = i_dc_ldac_n_bus[0];
    assign o_b6 = i_dc_cs_n_bus[12];

    assign o_b9 = i_dc_sclk_bus[3];
    assign o_b11 = i_dc_sclk_bus[15];
    assign o_b10 = i_dc_mosi_bus[0];
    assign o_b12 = i_dc_sclk_bus[12];

    assign o_b15 = i_dc_cs_n_bus[3];
    assign o_b17 = i_dc_mosi_bus[15];
    assign o_b16 = i_dc_sclk_bus[0];
    assign o_b18 = i_dc_mosi_bus[12];

    assign o_b21 = i_dc_ldac_n_bus[4];
    assign o_b23 = i_dc_ldac_n_bus[15];
    assign o_b22 = i_dc_cs_n_bus[0];
    assign o_b24 = i_dc_ldac_n_bus[12];

    assign o_b27 = i_dc_mosi_bus[4];
    assign o_b29 = i_dc_cs_n_bus[16];
    assign o_b28 = i_dc_ldac_n_bus[1];
    assign o_b30 = i_dc_cs_n_bus[13];

    assign o_b33 = i_dc_sclk_bus[4];
    assign o_b35 = i_dc_sclk_bus[16];
    assign o_b34 = i_dc_mosi_bus[1];
    assign o_b36 = i_dc_sclk_bus[13];

    assign o_b39 = i_dc_cs_n_bus[4];
    assign o_b41 = i_dc_mosi_bus[16];
    assign o_b40 = i_dc_sclk_bus[1];
    assign o_b42 = i_dc_mosi_bus[13];

    assign o_b45 = i_dc_ldac_n_bus[5];
    assign o_b47 = i_dc_ldac_n_bus[16];
    // assign o_b46 = i_dc_cs_n_bus[1];
    // assign o_b48 = i_dc_ldac_n_bus[13];

    assign o_b51 = i_dc_mosi_bus[5];
    assign o_b53 = i_dc_cs_n_bus[17];
    assign o_b52 = i_dc_ldac_n_bus[2];
    assign o_b54 = i_dc_cs_n_bus[14];

    assign o_b57 = i_dc_sclk_bus[5];
    assign o_b59 = i_dc_sclk_bus[17];
    assign o_b58 = i_dc_mosi_bus[2];
    assign o_b60 = i_dc_sclk_bus[14];

    assign o_b63 = i_dc_cs_n_bus[5];
    assign o_b65 = i_dc_mosi_bus[17];
    assign o_b64 = i_dc_sclk_bus[2];
    assign o_b66 = i_dc_mosi_bus[14];

    assign o_b69 = i_dc_clr_n;
    assign o_b71 = i_dc_ldac_n_bus[17];
    assign o_b70 = i_dc_cs_n_bus[2];
    assign o_b72 = i_dc_ldac_n_bus[14];

    assign o_b75 = i_dc_ldac_n_bus[6];
    assign o_b77 = i_dc_rst_n;
    assign o_b76 = i_dc_mosi_bus[6];
    assign o_b78 = i_dc_ldac_n_bus[3];

endmodule
