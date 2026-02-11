`timescale 1ns / 1ps

module data_width_converter #(
    parameter integer ADC_WIDTH = 20,
    parameter integer AXI_WIDTH = 128
)(
    input  logic                   clk,    // Connected to ui_clk
    input  logic                   rst_n,

    // ADC Side (Assuming coming from an Async FIFO)
    input  logic [ADC_WIDTH-1:0]   adc_data,
    input  logic                   adc_valid,

    // AXI Master Side
    output logic [AXI_WIDTH-1:0]   data_to_axi,
    output logic                   data_pkg_valid
);

    // We fit 4 samples into 128 bits. 
    // Each sample takes 32 bits (20 bits data + 12 bits zero padding)
    logic [1:0] count; 
    logic [127:0] shift_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= '0;
            shift_reg <= '0;
            data_to_axi <= '0;
            data_pkg_valid <= 1'b0;
        end else begin
            if (adc_valid) begin
                // Pad 20-bit to 32-bit and shift into buffer
                // {Padding (12-bit), ADC_DATA (20-bit)}
                shift_reg <= { {12{1'b0}}, adc_data, shift_reg[127:32] };
                
                if (count == 2'd3) begin
                    count <= 2'd0;
                    // Output the final 128-bit packed word
                    data_to_axi <= { {12{1'b0}}, adc_data, shift_reg[127:32] };
                    data_pkg_valid <= 1'b1;
                end else begin
                    count <= count + 1'b1;
                    data_pkg_valid <= 1'b0;
                end
            end else begin
                data_pkg_valid <= 1'b0;
            end
        end
    end

endmodule