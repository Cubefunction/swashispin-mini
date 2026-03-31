`timescale 1ns/1ps

module adc_test #(
    parameter int DATA_WIDTH = 20,
    parameter int CLK_DIV    = 2
)(
    input  logic        clk,
    input  logic        rst_n,

    output logic        id_ok,      // High if ID matches 0x50

    // Physical SPI Pins
    output logic        spi_cs,
    output logic        spi_sclk,
    output logic        spi_mosi,
    input  logic        spi_miso
);

    logic [DATA_WIDTH-1:0] final_data;
    logic                  test_done;

    // Internal Control Signals
    logic        spi_start;
    logic        spi_rw;
    logic [14:0] spi_reg_addr;
    logic [7:0]  spi_wr_data;

    logic        spi_busy;
    logic        spi_done;
    logic [7:0]  spi_rd_data;
    logic        spi_rd_valid;

    // FSM States for Testing Sequence
    typedef enum logic [1:0] {
        IDLE,
        READ_ID,
        READ_DATA,
        FINISH
    } test_state_t;

    test_state_t state;

    // --- SPI Master Instance ---
    ad4080_spi_master #(
        .ADDR_W  (15),
        .DATA_W  (8),
        .CLK_DIV (CLK_DIV)
    ) spi_inst (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (spi_start),
        .rw       (spi_rw),
        .reg_addr (spi_reg_addr),
        .wr_data  (spi_wr_data),

        .spi_sdo  (spi_miso),

        .spi_sclk (spi_sclk),
        .spi_cs_n (spi_cs),
        .spi_sdi  (spi_mosi),

        .rd_data  (spi_rd_data),
        .rd_valid (spi_rd_valid),
        .done     (spi_done),
        .busy     (spi_busy)
    );

    // --- Top Level Test Control ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            spi_start    <= 1'b0;
            spi_rw       <= 1'b0;
            spi_reg_addr <= 15'h0000;
            spi_wr_data  <= 8'h00;
            id_ok        <= 1'b0;
            test_done    <= 1'b0;
            final_data   <= '0;
        end
        else begin
            spi_start <= 1'b0;

            case (state)
                IDLE: begin
                    test_done <= 1'b0;

                    spi_rw       <= 1'b1;
                    spi_reg_addr <= 15'h0004;
                    spi_wr_data  <= 8'h00;
                    spi_start    <= 1'b1;
                    state        <= READ_ID;
                end

                READ_ID: begin
                    if (spi_rd_valid) begin
                        if (spi_rd_data == 8'h50) begin
                            id_ok <= 1'b1;

                            spi_rw       <= 1'b1;
                            spi_reg_addr <= 15'h0000;
                            spi_wr_data  <= 8'h00;
                            spi_start    <= 1'b1;
                            state        <= READ_DATA;
                        end
                        else begin
                            id_ok <= 1'b0;
                            state <= FINISH;
                        end
                    end
                end

                READ_DATA: begin
                    if (spi_rd_valid) begin
                        final_data <= {{(DATA_WIDTH-8){1'b0}}, spi_rd_data};
                        state      <= FINISH;
                    end
                end

                FINISH: begin
                    test_done <= 1'b1;
                    state     <= FINISH;
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

    ila_0 your_instance_name (
        .clk   (clk),
        .probe0(spi_cs),
        .probe1(spi_sclk),
        .probe2(spi_mosi),
        .probe3(spi_miso),
        .probe4(id_ok)
    );

endmodule