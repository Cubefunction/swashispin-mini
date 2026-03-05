module adc_test #(
    parameter int DATA_WIDTH = 20,
    parameter int CLK_DIV    = 2
)(
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,      // External trigger to start the whole test

    
    output logic                  id_ok,      // High if ID matches 0x50

    // Physical SPI Pins
    output logic        spi_cs,
    output logic        spi_sclk,
    output logic        spi_mosi,
    input  logic        spi_miso
);
    logic [DATA_WIDTH-1:0] final_data;
    logic                  test_done;
    // Internal Control Signals
    logic [15:0] ctrl_reg;
    logic [15:0] burst_cnt;
    logic        spi_start;
    logic        spi_busy;
    logic        spi_valid;
    logic [DATA_WIDTH-1:0] spi_rx_data;

    // FSM States for Testing Sequence
    typedef enum logic [1:0] {
        IDLE,
        READ_ID,    // Step 1: Request ID from 0x0004
        READ_SAMPLES, // Step 2: Request real data from 0x0000
        FINISH
    } test_state_t;

    test_state_t state;

    // --- SPI Master Instance ---
    ad4080_spi_master #(
        .DATA_WIDTH(DATA_WIDTH),
        .CLK_DIV(CLK_DIV)
    ) spi_inst (
        .clk(clk),
        .rst_n(rst_n),
        .start(spi_start),
        .ctrl_reg(ctrl_reg),
        .burst_cnt(burst_cnt),
        .rx_data(spi_rx_data),
        .data_valid(spi_valid),
        .busy(spi_busy),
        .spi_cs(spi_cs),
        .spi_sclk(spi_sclk),
        .spi_mosi(spi_mosi),
        .spi_miso(spi_miso)
    );

    // --- Top Level Test Control ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            spi_start <= 1'b0;
            ctrl_reg <= 16'h0;
            burst_cnt <= 16'h0;
            id_ok <= 1'b0;
            test_done <= 1'b0;
            final_data <= 0;
        end else begin
            case (state)
                IDLE: begin
                    test_done <= 1'b0;
                    if (start) begin
                        // Prepare to read ID register (0x0004)
                        ctrl_reg <= 16'h8004; // R=1, Addr=0x0004
                        burst_cnt <= 0;
                        spi_start <= 1'b1;
                        state <= READ_ID;
                    end
                end

                READ_ID: begin
                    spi_start <= 1'b0; // Pulse start
                    if (spi_valid) begin
                        // AD4080 ID is typically 0x50 at Reg 0x04
                        // Note: Depending on DATA_WIDTH, ID is in the MSB part of rx_data
                        if (spi_rx_data[DATA_WIDTH-1 : DATA_WIDTH-8] == 8'h50) begin
                            id_ok <= 1'b1;
                            // Now move to read actual data from 0x0000
                            ctrl_reg <= 16'h8000; // R=1, Addr=0x0000
                            burst_cnt <= 1;       // Read 2 samples
                            spi_start <= 1'b1;
                            state <= READ_SAMPLES;
                        end else begin
                            id_ok <= id_ok;
                            state <= FINISH; // ID mismatch
                        end
                    end
                end

                READ_SAMPLES: begin
                    spi_start <= 1'b0;
                    if (spi_valid) begin
                        final_data <= spi_rx_data;
                        if (!spi_busy) state <= FINISH;
                    end
                end

                FINISH: begin
                    test_done <= 1'b1;
                    if (!start) state <= IDLE;
                end
            endcase
        end
    end
    
    ila_0 your_instance_name (
	.clk(clk), // input wire clk


	.probe0(spi_cs), // input wire [0:0]  probe0  
	.probe1(spi_sclk), // input wire [0:0]  probe1 
	.probe2(spi_mosi), // input wire [0:0]  probe2 
	.probe3(spi_miso), // input wire [0:0]  probe3 
	.probe4(start) // input wire [0:0]  probe4
);

endmodule