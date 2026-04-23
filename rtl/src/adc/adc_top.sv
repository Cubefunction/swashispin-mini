`timescale 1ns/1ps

//==============================================================================
// adc_top
//==============================================================================
module adc_top #(
    parameter int NUM_REGS        = 54,
    parameter int CTRL_REG_IDX    = 53,
    parameter int ADDR_WIDTH      = $clog2(NUM_REGS),

    parameter int ADC_DATA_W      = 16,
    parameter int ADC_LUT_DEPTH   = 256,
    parameter int ADC_SAMPLE_GAP  = 8,
    parameter int ADC_PHASE_STEP  = 4,

    // ---- DDR3 writer parameters (keep in lock-step with ddr3_top / mig_axi4_driver) ----
    parameter int                      DDR_DATA_W     = 128,
    parameter int                      DDR_ADDR_W     = 28,
    parameter int                      P_WR_BURST_LEN = 8,
    parameter int                      P_WR_BURST_NUM = 1,
    parameter logic [DDR_ADDR_W-1:0]   DDR_BASE_ADDR  = '0
)(
    input  logic i_clk,
    input  logic i_rst,

    input  logic [0:NUM_REGS-1][31:0] i_all_regs,

    // ADC status
    output logic o_adc_sampling,
    output logic o_active,

    // raw ADC stream (kept exposed for debug/visibility)
    output logic signed [ADC_DATA_W-1:0] o_adc_data,
    output logic                         o_adc_data_valid,
    output logic                         o_adc_spi_finish,

    // ---- DDR3 writer user port (connect to ddr3_top.i_user_wr_*) ----
    output logic                     o_user_wr_valid,
    output logic [DDR_ADDR_W-1:0]    o_user_wr_addr_base,
    output logic [DDR_DATA_W-1:0]    o_user_wr_data,
    output logic                     o_user_wr_data_valid,

    // ---- Byte counter (for PC-visible readback) ----
    output logic [DDR_ADDR_W-1:0]    o_bytes_written
);

    //==========================================================================
    // Internal nets
    //==========================================================================
    logic                         w_adc_spi_finish;
    logic                         w_adc_sampling;
    logic                         w_active;
    logic signed [ADC_DATA_W-1:0] w_adc_data;
    logic                         w_adc_data_valid;

    assign o_adc_sampling   = w_adc_sampling;
    assign o_active         = w_active;
    assign o_adc_data       = w_adc_data;
    assign o_adc_data_valid = w_adc_data_valid;
    assign o_adc_spi_finish = w_adc_spi_finish;

    //==========================================================================
    // ADC control core (instruction processor)
    //==========================================================================
    adc_core #(
        .NUM_REGS     (NUM_REGS),
        .CTRL_REG_IDX (CTRL_REG_IDX),
        .ADDR_WIDTH   (ADDR_WIDTH)
    ) u_adc_core (
        .i_clk            (i_clk),
        .i_rst            (i_rst),
        .i_all_regs       (i_all_regs),
        .i_adc_spi_finish (w_adc_spi_finish),
        .o_adc_sampling   (w_adc_sampling),
        .o_active         (w_active)
    );

    //==========================================================================
    // Sine ADC model (replace with real ADC front-end later)
    //==========================================================================
    adc_sampling_sin_model #(
        .DATA_W     (ADC_DATA_W),
        .LUT_DEPTH  (ADC_LUT_DEPTH),
        .SAMPLE_GAP (ADC_SAMPLE_GAP),
        .PHASE_STEP (ADC_PHASE_STEP)
    ) u_adc_sampling_sin_model (
        .i_clk            (i_clk),
        .i_rst            (i_rst),
        .i_adc_sampling   (w_adc_sampling),
        .o_adc_data       (w_adc_data),
        .o_adc_data_valid (w_adc_data_valid),
        .o_adc_spi_finish (w_adc_spi_finish)
    );

    //==========================================================================
    // ADC -> DDR3 writer
    //   packs 16-bit samples into 128-bit words AND
    //   pulses i_user_wr_valid + base address on every transaction boundary.
    //==========================================================================
    adc_ddr3_writer #(
        .DATA_W         (ADC_DATA_W),
        .DDR_W          (DDR_DATA_W),
        .ADDR_W         (DDR_ADDR_W),
        .P_WR_BURST_LEN (P_WR_BURST_LEN),
        .P_WR_BURST_NUM (P_WR_BURST_NUM),
        .BASE_ADDR      (DDR_BASE_ADDR)
    ) u_adc_ddr3_writer (
        .i_clk                (i_clk),
        .i_rst                (i_rst),

        .i_active             (w_active),

        .i_adc_data           (w_adc_data),
        .i_adc_data_valid     (w_adc_data_valid),

        .o_user_wr_valid      (o_user_wr_valid),
        .o_user_wr_addr_base  (o_user_wr_addr_base),
        .o_user_wr_data       (o_user_wr_data),
        .o_user_wr_data_valid (o_user_wr_data_valid),
        .o_bytes_written      (o_bytes_written)
    );

endmodule