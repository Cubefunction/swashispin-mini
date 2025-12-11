module adc_to_fifo (
    input  logic        i_clk,
    input  logic        i_rst,

    // Request one ADC sample
    input  logic        i_sample_req,

    // SPI interface to MAX11100
    input  logic        i_miso,
    output logic        o_mosi,
    output logic        o_sclk,
    output logic        o_cs_n,

    // FIFO output interface
    output logic [15:0] o_fifo_data,
    output logic        o_fifo_empty
);

    //  MAX11100 SPI Reader
    logic adc_busy, adc_done;
    logic [15:0] adc_data;

    max11100_reader u_adc (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_start(i_sample_req),

        .o_busy(adc_busy),
        .o_done(adc_done),
        .o_data(adc_data),

        .i_miso(i_miso),
        .o_mosi(o_mosi),
        .o_sclk(o_sclk),
        .o_cs_n(o_cs_n)
    );

    //  FIFO Instance
    logic fifo_enq, fifo_deq;
    logic fifo_full, fifo_af, fifo_ae;

    fifo #(
        .WIDTH(16),
        .DEPTH(32),
        .AF_DEPTH(28),
        .AE_DEPTH(2)
    ) u_fifo (
        .i_clk(i_clk),
        .i_rst(i_rst),

        .i_data(adc_data),
        .i_enq(fifo_enq),
        .i_deq(fifo_deq),

        .o_data(o_fifo_data),
        .o_full(fifo_full),
        .o_empty(o_fifo_empty),
        .o_almost_full(fifo_af),
        .o_almost_empty(fifo_ae)
    );

    assign fifo_enq = adc_done & ~fifo_full;

    assign fifo_deq = 1'b0;

endmodule
