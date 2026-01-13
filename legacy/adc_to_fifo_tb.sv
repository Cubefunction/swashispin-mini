`timescale 1ns/1ps

module adc_to_fifo_tb;

    // -------------------------
    // Clock & Reset
    // -------------------------
    logic clk;
    logic rst;

    always #5 clk = ~clk;   // 100MHz clock (10ns period)

    // -------------------------
    // DUT IO
    // -------------------------
    logic        sample_req;
    logic        miso;
    logic        mosi, sclk, cs_n;

    logic [15:0] fifo_data;
    logic        fifo_empty;

    // -------------------------
    // Instantiate DUT
    // -------------------------
    adc_to_fifo dut (
        .i_clk(clk),
        .i_rst(rst),

        .i_sample_req(sample_req),

        .i_miso(miso),
        .o_mosi(mosi),
        .o_sclk(sclk),
        .o_cs_n(cs_n),

        .o_fifo_data(fifo_data),
        .o_fifo_empty(fifo_empty)
    );

    // -------------------------
    // MAX11100 Behavioral Model
    // (Simple MISO Shifter)
    // -------------------------
    logic [15:0] adc_data_pattern = 16'hB26E;   
    logic [15:0] shift_reg;

    always_ff @(negedge cs_n) begin
        shift_reg <= adc_data_pattern;
        miso      <= adc_data_pattern[15];  
    end

    // Shift out MSB first on each SCLK rising edge
    always_ff @(negedge sclk) begin
        if (!cs_n) begin
            shift_reg <= {shift_reg[14:0], 1'b0};
            miso      <= shift_reg[14];     
        end else begin
            miso <= 1'bZ;
        end
    end 

    // Test Stimulus

    initial begin
        clk = 0;
        rst = 1;
        sample_req = 0;
        miso = 0;

        #50;
        rst = 0;

        // Trigger one ADC sample
        @(posedge clk);
        sample_req = 1;
        @(posedge clk);
        sample_req = 0;

        // Wait for conversion & FIFO enqueue
        repeat (2000) @(posedge clk);

        // Check FIFO output
        if (!fifo_empty) begin
            $display("FIFO Output: %h (Expected: %h)", fifo_data, adc_data_pattern);
        end else begin
            $display("ERROR: FIFO is empty!");
        end

        #100;
        $finish;
    end

endmodule