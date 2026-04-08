`timescale 1ns/1ps

module ad9833_top #(
    parameter int FRAME_W     = 16,
    parameter int SPI_CLK_DIV = 10
)(
    input  logic        i_clk,
    input  logic        i_rst_n,

    // User config registers
    input  logic [31:0] i_reg_cmd,         // spi_word0
    input  logic [31:0] i_reg_freq,        // {spi_word2, spi_word1}
    input  logic [31:0] i_reg_phase_ctrl,  // {spi_word4, spi_word3}
    input  logic [31:0] i_reg_control,     // bit0 = start

    // AD9833 SPI pins
    output logic        o_spi_sclk,
    output logic        o_spi_fsync,
    output logic        o_spi_mosi,

    // Debug/status
    output logic        o_busy,
    output logic        o_done_pulse,
    output logic [31:0] o_status_word
);

    logic        w_spi_start;
    logic [15:0] w_spi_frame_data;
    logic        w_spi_done;
    logic        w_spi_busy;

    ad9833_user_ctrl u_ad9833_user_ctrl (
        .clk            (i_clk),
        .rst_n          (i_rst_n),

        .reg_cmd        (i_reg_cmd),
        .reg_freq       (i_reg_freq),
        .reg_phase_ctrl (i_reg_phase_ctrl),
        .reg_control    (i_reg_control),

        .spi_start      (w_spi_start),
        .spi_frame_data (w_spi_frame_data),
        .spi_done       (w_spi_done),
        .spi_busy       (w_spi_busy),

        .busy           (o_busy),
        .done_pulse     (o_done_pulse),
        .status_word    (o_status_word)
    );

    ad9833_spi_master #(
        .FRAME_W (FRAME_W),
        .CLK_DIV (SPI_CLK_DIV)
    ) u_ad9833_spi_master (
        .clk        (i_clk),
        .rst_n      (i_rst_n),
        .start      (w_spi_start),
        .frame_data (w_spi_frame_data),

        .spi_sclk   (o_spi_sclk),
        .spi_fsync  (o_spi_fsync),
        .spi_mosi   (o_spi_mosi),
        .done       (w_spi_done),
        .busy       (w_spi_busy)
    );

endmodule