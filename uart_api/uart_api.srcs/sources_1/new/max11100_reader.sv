module max11100_reader (
    input  logic        i_clk,
    input  logic        i_rst,

    input  logic        i_start,
    output logic        o_busy,
    output logic        o_done,
    output logic [15:0] o_data,

    input  logic        i_miso,
    output logic        o_mosi,
    output logic        o_sclk,
    output logic        o_cs_n
);

    enum {IDLE, ASSERT_CS, READ_SPI, DONE} r_state, w_state;

    logic spi_done;
    logic [15:0] spi_dout;

    logic [15:0] dvsr = 16'd5;

    spi_master #(
        .DATA_WIDTH(16),
        .SCLK_POLARITY(0),
        .SCLK_PHASE(0)
    ) u_spi (
        .i_clk   (i_clk),
        .i_rst   (i_rst),

        .i_din   (16'h0000),   
        .o_dout  (spi_dout),

        .i_start (r_state == ASSERT_CS),   
        .o_done  (spi_done),

        .i_dvsr  (dvsr),

        .i_miso  (i_miso),
        .o_mosi  (o_mosi),
        .o_sclk  (o_sclk)
    );

    logic cs_n;

    assign o_cs_n = cs_n;
    assign o_busy = (r_state != IDLE);
    assign o_done = (r_state == DONE);
    assign o_data = spi_dout;

    always_ff @(posedge i_clk) begin
        if (i_rst)
            r_state <= IDLE;
        else
            r_state <= w_state;
    end

    always_comb begin
        w_state = r_state;
        cs_n = 1'b1;

        case (r_state)

            IDLE: begin
                if (i_start)
                    w_state = ASSERT_CS;
            end

            // CS_low
            ASSERT_CS: begin
                cs_n = 1'b0;
                w_state = READ_SPI;
            end

            // SPI master  16 bit
            READ_SPI: begin
                cs_n = 1'b0;
                if (spi_done)
                    w_state = DONE;
            end

            DONE: begin
                cs_n = 1'b1;
                w_state = IDLE;
            end
        endcase
    end

endmodule
