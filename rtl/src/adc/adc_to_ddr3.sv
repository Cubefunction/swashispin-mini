`timescale 1ns/1ps

module adc_to_ddr3 #(
    parameter int ADC_W      = 20,
    parameter int FIFO_DEPTH = 8,
    parameter int AF_DEPTH   = 6,
    parameter int AE_DEPTH   = 2,
    parameter int OUT_W      = 128
)(
    input  logic                 rst_n,


    // ADC/SPI domain (sys_clk)

    input  logic                 sys_clk,        // 100 MHz
    input  logic [ADC_W-1:0]     sample_data,    // ADC sample
    input  logic                 sample_valid,   

    // DDR/MIG domain
    input  logic                 ui_clk,         // from MIG

    // pack to axi (Burst Writer / AXI Master)
    output logic [OUT_W-1:0]     pack_data,
    output logic                 pack_valid,
    input  logic                 pack_ready,


    // Debug/Status
    output logic                 fifo_full,
    output logic                 fifo_empty,
    output logic                 fifo_almost_full,
    output logic                 fifo_almost_empty
);

    //Async FIFO: sys_clk -> ui_clk
    logic                 af_r_deq;
    logic [ADC_W-1:0]     af_r_data;
    logic                 af_r_valid;

    async_fifo #(
        .WIDTH(ADC_W),
        .DEPTH(FIFO_DEPTH),
        .AF_DEPTH(AF_DEPTH),
        .AE_DEPTH(AE_DEPTH)
    ) u_async_fifo (
        .rst_n          (rst_n),

        // write side (sys_clk domain)
        .w_clk          (sys_clk),
        .w_data         (sample_data),
        .w_enq          (sample_valid),
        .w_full         (fifo_full),
        .w_almost_full  (fifo_almost_full),

        // read side (ui_clk domain)
        .r_clk          (ui_clk),
        .r_deq          (af_r_deq),
        .r_data         (af_r_data),
        .r_empty        (fifo_empty),
        .r_almost_empty (fifo_almost_empty),
        .r_valid        (af_r_valid)
    );


    //  Generate a clean ui_clk-domain active-high reset for packer

    logic [1:0] ui_rst_ff;
    logic       ui_rst;  // active-high reset in ui_clk domain

    always_ff @(posedge ui_clk or negedge rst_n) begin
        if (!rst_n) ui_rst_ff <= 2'b11;
        else        ui_rst_ff <= {ui_rst_ff[0], 1'b0};
    end
    assign ui_rst = ui_rst_ff[1];

   
    //  Data Packer (ui_clk domain): 20b -> pad32 -> OUT_W (128b)
    data_packer #(
        .SAMPLE_W(ADC_W),
        .OUT_W   (OUT_W)
    ) u_data_packer (
        .clk        (ui_clk),
        .rst        (ui_rst),

        .fifo_data  (af_r_data),
        .fifo_valid (af_r_valid),
        .fifo_empty (fifo_empty),
        .fifo_deq   (af_r_deq),

        .o_data     (pack_data),
        .o_valid    (pack_valid),
        .o_ready    (pack_ready)
    );

endmodule