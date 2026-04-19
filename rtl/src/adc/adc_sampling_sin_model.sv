`timescale 1ns/1ps

module adc_sampling_sin_model #(
    parameter int DATA_W      = 16,
    parameter int LUT_DEPTH   = 256,
    parameter int SAMPLE_GAP  = 8,
    parameter int PHASE_STEP  = 1
)(
    input  logic                     i_clk,
    input  logic                     i_rst,
    input  logic                     i_adc_sampling,

    output logic signed [DATA_W-1:0] o_adc_data,
    output logic                     o_adc_data_valid,
    output logic                     o_adc_spi_finish
);

    localparam int LUT_ADDR_W = (LUT_DEPTH <= 1) ? 1 : $clog2(LUT_DEPTH);
    localparam int GAP_W      = (SAMPLE_GAP <= 1) ? 1 : $clog2(SAMPLE_GAP);

    logic signed [DATA_W-1:0] sine_lut [0:LUT_DEPTH-1];
    logic [LUT_ADDR_W-1:0]    lut_idx;
    logic [GAP_W-1:0]         gap_cnt;
    logic                     sampling_d;

    integer i;
    real angle;
    real amp;

    initial begin
        for (i = 0; i < LUT_DEPTH; i = i + 1) begin
            angle = 2.0 * 3.14159265358979323846 * i / LUT_DEPTH;
            amp   = $sin(angle) * ((1 << (DATA_W-1)) - 1);
            sine_lut[i] = $rtoi(amp);
        end
    end

    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            lut_idx           <= '0;
            gap_cnt           <= '0;
            sampling_d        <= 1'b0;
            o_adc_data        <= '0;
            o_adc_data_valid  <= 1'b0;
            o_adc_spi_finish  <= 1'b0;
        end
        else begin
            sampling_d       <= i_adc_sampling;
            o_adc_data_valid <= 1'b0;
            o_adc_spi_finish <= 1'b0;

            // sampling window starts
            if (i_adc_sampling && !sampling_d) begin
                gap_cnt    <= '0;
                o_adc_data <= sine_lut[lut_idx];

                o_adc_data_valid <= 1'b1;
                o_adc_spi_finish <= 1'b1;
                lut_idx          <= lut_idx + PHASE_STEP[LUT_ADDR_W-1:0];
            end
            else if (i_adc_sampling) begin
                if (gap_cnt == SAMPLE_GAP-1) begin
                    gap_cnt    <= '0;
                    o_adc_data <= sine_lut[lut_idx];

                    o_adc_data_valid <= 1'b1;
                    o_adc_spi_finish <= 1'b1;
                    lut_idx          <= lut_idx + PHASE_STEP[LUT_ADDR_W-1:0];
                end
                else begin
                    gap_cnt <= gap_cnt + 1'b1;
                end
            end
            else begin
                gap_cnt <= '0;
            end
        end
    end

endmodule
