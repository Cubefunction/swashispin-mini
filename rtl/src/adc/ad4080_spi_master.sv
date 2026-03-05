module ad4080_spi_master #(
    parameter int DATA_WIDTH = 20,
    parameter int CLK_DIV    = 2
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    
    // 16-bit combined: [15]=R/W, [14:0]=Address
    input  logic [15:0] ctrl_reg, 
    input  logic [15:0] burst_cnt,  // Number of extra samples in the same CS frame

    output logic [DATA_WIDTH-1:0] rx_data, 
    output logic                  data_valid, 
    output logic                  busy,

    // SPI Physical Pins
    output logic        spi_cs,
    output logic        spi_sclk,
    output logic        spi_mosi,
    input  logic        spi_miso
);

    typedef enum logic [1:0] {
        IDLE, 
        TX_INST,    // Transmit 16-bit Instruction
        RX_DATA,    // Receive 20-bit Data
        DONE
    } state_t;

    state_t state;
    logic [7:0]  div_cnt;
    logic [5:0]  bit_cnt;
    logic [5:0]  rx_cnt;
    logic [31:0] shift_reg;
    logic [15:0] b_cnt;
    logic        sclk_en;

    // --- SCLK Generation (SPI Mode 3) ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            div_cnt  <= 0;
            spi_sclk <= 1'b1; 
        end else if (sclk_en) begin
            if (div_cnt >= (CLK_DIV - 1)) begin
                div_cnt  <= 0;
                spi_sclk <= ~spi_sclk;
            end else div_cnt <= div_cnt + 1;
        end else begin
            div_cnt  <= 0;
            spi_sclk <= 1'b1;
        end
    end

    // Timing Strobes
    wire shift_edge  = (sclk_en && spi_sclk  && div_cnt == CLK_DIV - 1); 
    wire sample_edge = (sclk_en && !spi_sclk && div_cnt == CLK_DIV - 1); 

    // --- Simple State Machine ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; spi_cs <= 1'b1; spi_mosi <= 1'b0;
            data_valid <= 1'b0; busy <= 1'b0; sclk_en <= 1'b0;
            rx_data <= 0; rx_cnt <= 0; b_cnt <= 0;
        end else begin
            case (state)
                IDLE: begin
                    busy <= 1'b0; data_valid <= 1'b0; sclk_en <= 1'b0;
                    if (start) begin
                        busy <= 1'b1;
                        spi_cs <= 1'b0;
                        sclk_en <= 1'b1;
                        shift_reg <= {ctrl_reg, 16'h0}; // Load 16-bit instruction
                        bit_cnt <= 15;
                        b_cnt <= burst_cnt;
                        state <= TX_INST;
                    end
                end

                TX_INST: if (shift_edge) begin
                    // Shift out 16 bits of [R/W + Address]
                    spi_mosi <= shift_reg[31];
                    shift_reg <= {shift_reg[30:0], 1'b0};
                    if (bit_cnt == 0) begin
                        state <= RX_DATA;
                        rx_cnt <= 0;
                    end else bit_cnt <= bit_cnt - 1;
                end

                RX_DATA: if (sample_edge) begin
                    // Shift in 20 bits of ADC data
                    rx_data <= {rx_data[DATA_WIDTH-2:0], spi_miso};
                    if (rx_cnt == DATA_WIDTH - 1) begin
                        data_valid <= 1'b1;
                        rx_cnt <= 0;
                        if (b_cnt == 0) begin
                            state <= DONE;
                            sclk_en <= 1'b0;
                        end else begin
                            b_cnt <= b_cnt - 1;
                            // Continue in RX_DATA for burst
                        end
                    end else begin
                        data_valid <= 1'b0;
                        rx_cnt <= rx_cnt + 1;
                    end
                end else data_valid <= 1'b0;

                DONE: begin
                    spi_cs <= 1'b1;
                    busy <= 1'b0;
                    state <= IDLE;
                end
            endcase
        end
    end
endmodule