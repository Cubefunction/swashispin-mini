`timescale 1ns/1ps

module uart_top #(
    parameter int DATA_WIDTH        = 8,
    parameter int RX_FIFO_DEPTH     = 8,
    parameter int RX_FIFO_AF_DEPTH  = 6,
    parameter int RX_FIFO_AE_DEPTH  = 2,
    parameter int TX_FIFO_DEPTH     = 8,
    parameter int TX_FIFO_AF_DEPTH  = 6,
    parameter int TX_FIFO_AE_DEPTH  = 2,

    parameter int NUM_REGS          = 64,

    // AD9833 register map
    parameter int AD9833_BASE_ADDR  = 0,
    parameter int SPI_FRAME_W       = 16,
    parameter int SPI_CLK_DIV       = 65535,

    // ADC core register map
    parameter int ADC_CORE_BASE_ADDR = 4,
    parameter int ADC_CORE_NUM_REGS  = 54,
    parameter int ADC_CTRL_REG_IDX   = 53
)(
    input  logic i_clk,
    input  logic i_rst_n,

    input  logic i_rx,
    output logic o_tx,

    output logic o_spi_sclk,
    output logic o_spi_fsync,
    output logic o_spi_mosi,

    // adc_core outputs
    output logic o_adc_sampling,
    output logic o_adc_active
);

    logic w_rst;
    assign w_rst = ~i_rst_n;

    logic [0:NUM_REGS-1][31:0] w_regs;

    logic [31:0] w_reg_cmd;
    logic [31:0] w_reg_freq;
    logic [31:0] w_reg_phase_ctrl;
    logic [31:0] w_reg_control;

    //==================================================
    // UART register block
    //==================================================
    uart_regs #(
        .DATA_WIDTH       (DATA_WIDTH),
        .RX_FIFO_DEPTH    (RX_FIFO_DEPTH),
        .RX_FIFO_AF_DEPTH (RX_FIFO_AF_DEPTH),
        .RX_FIFO_AE_DEPTH (RX_FIFO_AE_DEPTH),
        .TX_FIFO_DEPTH    (TX_FIFO_DEPTH),
        .TX_FIFO_AF_DEPTH (TX_FIFO_AF_DEPTH),
        .TX_FIFO_AE_DEPTH (TX_FIFO_AE_DEPTH),
        .NUM_REGS         (NUM_REGS)
    ) u_uart_regs (
        .i_clk  (i_clk),
        .i_rst  (w_rst),
        .i_rx   (i_rx),
        .o_tx   (o_tx),
        .o_regs (w_regs)
    );

    //==================================================
    // AD9833 register mapping
    //==================================================
    assign w_reg_cmd        = w_regs[AD9833_BASE_ADDR + 0];
    assign w_reg_freq       = w_regs[AD9833_BASE_ADDR + 1];
    assign w_reg_phase_ctrl = w_regs[AD9833_BASE_ADDR + 2];
    assign w_reg_control    = w_regs[AD9833_BASE_ADDR + 3];

    ad9833_top #(
        .FRAME_W     (SPI_FRAME_W),
        .SPI_CLK_DIV (SPI_CLK_DIV)
    ) u_ad9833_top (
        .i_clk            (i_clk),
        .i_rst_n          (i_rst_n),

        .i_reg_cmd        (w_reg_cmd),
        .i_reg_freq       (w_reg_freq),
        .i_reg_phase_ctrl (w_reg_phase_ctrl),
        .i_reg_control    (w_reg_control),

        .o_spi_sclk       (o_spi_sclk),
        .o_spi_fsync      (o_spi_fsync),
        .o_spi_mosi       (o_spi_mosi)
    );

    //==================================================
    // ADC core
    //==================================================
    adc_core #(
        .NUM_REGS      (ADC_CORE_NUM_REGS),
        .CTRL_REG_IDX  (ADC_CTRL_REG_IDX),
        .ADDR_WIDTH    ($clog2(ADC_CORE_NUM_REGS)),
        .BASE_ADDR     (ADC_CORE_BASE_ADDR)
    ) u_adc_core (
        .i_clk          (i_clk),
        .i_rst          (w_rst),
        .i_all_regs     (w_regs[ADC_CORE_BASE_ADDR +: ADC_CORE_NUM_REGS]),

        .o_adc_sampling (o_adc_sampling),
        .o_active       (o_adc_active)
    );

endmodule