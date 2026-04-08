`timescale 1ns / 1ps
module ad4080_spi_reader #(
    // 100MHz
    parameter CNV_HIG_CNT = 5,      // CNV=50ns
    parameter CONV_WAIT_CNT = 60,   // tCONV=600ns
    parameter SCLK_HALF_CNT = 1     // 1=10ns, 20ns=50MHz
)(
    input  wire        clk,         
    input  wire        rst_n,       
    input  wire        start,       
    
    // ADC 
    output reg         adc_cnv,     
    output reg         adc_cs_n,    
    output reg         adc_sclk,    
    input  wire        adc_sdo,     
    
    output reg [19:0]  adc_data,    
    output reg         data_valid   
);
    localparam IDLE    = 3'd0;
    localparam T_CNV   = 3'd1;
    localparam T_WAIT  = 3'd2;
    localparam T_READ  = 3'd3;
    localparam T_DONE  = 3'd4;

    reg [2:0]  state;
    reg [15:0] cnt;       
    reg [4:0]  bit_cnt;   
    reg [19:0] shift_reg;
    reg [15:0] sclk_cnt;  

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            adc_cnv    <= 0;
            adc_cs_n   <= 1;
            adc_sclk   <= 0;
            cnt        <= 0;
            bit_cnt    <= 0;
            data_valid <= 0;
            sclk_cnt   <= 0;
        end else begin
            case (state)
                IDLE: begin
                    data_valid <= 0;
                    if (start) begin
                        adc_cnv <= 1;
                        cnt     <= 0;
                        state   <= T_CNV;
                    end
                end

                T_CNV: begin
                    if (cnt >= CNV_HIG_CNT - 1) begin
                        adc_cnv <= 0;
                        cnt     <= 0;
                        state   <= T_WAIT;
                    end else cnt <= cnt + 1'b1;
                end

                T_WAIT: begin
                    if (cnt >= CONV_WAIT_CNT - 1) begin
                        adc_cs_n <= 0;
                        cnt      <= 0;
                        bit_cnt  <= 0;
                        sclk_cnt <= 0;
                        state    <= T_READ;
                    end else cnt <= cnt + 1'b1;
                end

                T_READ: begin
                    if (sclk_cnt >= SCLK_HALF_CNT - 1) begin
                        sclk_cnt <= 0;
                        adc_sclk <= ~adc_sclk;
                        
                        if (adc_sclk == 1'b0) begin 
                            shift_reg <= {shift_reg[18:0], adc_sdo};
                        end else begin
                            if (bit_cnt >= 19) begin
                                state <= T_DONE;
                            end else begin
                                bit_cnt <= bit_cnt + 1'b1;
                            end
                        end
                    end else begin
                        sclk_cnt <= sclk_cnt + 1'b1;
                    end
                end

                T_DONE: begin
                    adc_cs_n   <= 1;
                    adc_sclk   <= 0;
                    adc_data   <= shift_reg;
                    data_valid <= 1;
                    state      <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end
endmodule