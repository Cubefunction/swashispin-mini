`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/11/13 15:49:08
// Design Name: 
// Module Name: top_dc
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module top_dc
(
    input  logic i_clk,
    input  logic i_rstn,

    // UART RX from host PC / controller
    input  logic i_rx,
    input   logic trigger,
    // MAX11100 SPI ADC interface (single ADC)
    input  logic  i_adc_miso,
    output logic  o_adc_mosi,
    output logic  o_adc_sclk,
    output logic  o_adc_cs_n,

    // Outputs to DAC array (24 channels)
    output logic [23:0] o_sclk,
    output logic [23:0] o_mosi,
    output logic [23:0] o_cs_n,
    output logic [23:0] o_ldac_n
);
    ila_0 u_ila(
        .clk(i_clk),
        
        
        .probe0(o_adc_sclk),
        .probe1(i_adc_miso),
        .probe2(trigger),
        .probe3(fifo_data)
        );
    // ============================================================
    //  uart_api_dc 
    // ============================================================

    uart_api_dc #(
        .DAC_WIDTH(16),
        .CYCLE_WIDTH(30),
        .DAC_CHANNEL(24),
        .CHANNEL_MES_WIDTH(96),
        .STREAM_ITER_WIDTH(10),
        .CORE_ITER_WIDTH(10),
        .DEPTH(10),
        .INSN_WIDTH(16*2 + 10 + 30),
        .TOTAL_REGS(10*3+2)
    ) 
    u_uart_api_dc (
        .i_clk(i_clk),
        .i_rst(!i_rstn),

        .i_rx(i_rx),

        // DAC output buses (24 channels)
        .o_sclk   (o_sclk),
        .o_mosi   (o_mosi),
        .o_cs_n   (o_cs_n),
        .o_ldac_n (o_ldac_n)
    );

    // ============================================================
    //  Instance: ADC-to-FIFO pipeline
    //  Reads MAX11100 16-bit values into FIFO
    // ============================================================

    // Sample trigger (you may connect from uart_api_dc later)
    logic sample_req;
    assign sample_req = !trigger;   // default: disabled or attach external logic

    // FIFO output (if needed for integration later)
    logic [15:0] fifo_data;
    logic        fifo_empty;

    adc_to_fifo u_adc_to_fifo (
        .i_clk(i_clk),
        .i_rst(!i_rstn),

        .i_sample_req(sample_req),

        .i_miso(i_adc_miso),
        .o_mosi(o_adc_mosi),
        .o_sclk(o_adc_sclk),
        .o_cs_n(o_adc_cs_n),

        .o_fifo_data(fifo_data),
        .o_fifo_empty(fifo_empty)
    );

endmodule
