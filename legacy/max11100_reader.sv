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

    enum {IDLE, ASSERT_CS, WAIT_CSS, READ_SPI, WAIT_CSH, DONE} r_state, w_state;

    logic spi_done;
    logic [23:0] spi_dout;

    logic [15:0] dvsr = 16'd24;   // 2MHz SPI

    spi_master #(
        .DATA_WIDTH(24),
        .SCLK_POLARITY(0),
        .SCLK_PHASE(0)
    ) u_spi (
        .i_clk   (i_clk),
        .i_rst   (i_rst),

        .i_din   (24'h000000),   
        .o_dout  (spi_dout),

        .i_start (r_state == WAIT_CSS),   
        .o_done  (spi_done),

        .i_dvsr  (dvsr),

        .i_miso  (i_miso),
        .o_mosi  (o_mosi),
        .o_sclk  (o_sclk)
    );

    // CS signal
    logic cs_n;
    assign o_cs_n = cs_n;

    // outputs
    assign o_busy = (r_state != IDLE);
    assign o_done = (r_state == DONE);
    assign o_data = spi_dout[15:0];    // D15..D0

    // delay counters
    logic [7:0] css_cnt;
    logic [7:0] csh_cnt;

    // FSM
    always_ff @(posedge i_clk) begin
        if (i_rst)
            r_state <= IDLE;
        else
            r_state <= w_state;
    end

    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            css_cnt <= 0;
            csh_cnt <= 0;
        end
        else begin
            // tCSS counter
            if (r_state == ASSERT_CS)
                css_cnt <= 0;
            else if (r_state == WAIT_CSS)
                css_cnt <= css_cnt + 1;

            // tCSH counter
            if (r_state == READ_SPI)
                csh_cnt <= 0;
            else if (r_state == WAIT_CSH)
                csh_cnt <= csh_cnt + 1;
        end
    end

    always_comb begin
        w_state = r_state;
        cs_n = 1'b1;

        case (r_state)

        IDLE: begin
            if (i_start)
                w_state = ASSERT_CS;
        end

        ASSERT_CS: begin
            cs_n = 1'b0;
            w_state = WAIT_CSS;
        end

        WAIT_CSS: begin
            cs_n = 1'b0;
            if (css_cnt >= 8'd10)    // 10 * 10ns = 100ns
                w_state = READ_SPI;
        end

        READ_SPI: begin
            cs_n = 1'b0;
            if (spi_done)
                w_state = WAIT_CSH;
        end

        WAIT_CSH: begin
            cs_n = 1'b1;
            if (csh_cnt >= 8'd5)     
                w_state = DONE;
        end

        DONE: begin
            cs_n = 1'b1;
            w_state = IDLE;
        end

        endcase
    end

endmodule
