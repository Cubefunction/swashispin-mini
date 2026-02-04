`timescale 1ns / 1ps

module ad4080_spi_reader_tb();

    // ---------------------------------------------------------
    // Parameters & Signals
    // ---------------------------------------------------------
    parameter CLK_PERIOD = 10; // 100MHz System Clock
    
    reg         clk;
    reg         rst_n;
    reg         start;
    wire        adc_cnv;
    wire        adc_cs_n;
    wire        adc_sclk;
    reg         adc_sdo;
    wire [19:0] adc_data;
    wire        data_valid;

    // ---------------------------------------------------------
    // DUT Instance
    // ---------------------------------------------------------
    ad4080_spi_reader #(
        .CNV_HIG_CNT(5),      
        .CONV_WAIT_CNT(60),   
        .SCLK_HALF_CNT(1)     
    ) dut (
        .clk        (clk       ),
        .rst_n      (rst_n     ),
        .start      (start     ),
        .adc_cnv    (adc_cnv   ),
        .adc_cs_n   (adc_cs_n  ),
        .adc_sclk   (adc_sclk  ),
        .adc_sdo    (adc_sdo   ),
        .adc_data   (adc_data  ),
        .data_valid (data_valid)
    );

   // ---------------------------------------------------------
    // Verdi FSDB Dumping (Protected)
    // ---------------------------------------------------------
    initial begin
        
            $fsdbDumpfile("ad4080_spi_reader_tb.fsdb");
            $fsdbDumpvars(0, ad4080_spi_reader_tb);
        
    end

    // ---------------------------------------------------------
    // Clock Generation
    // ---------------------------------------------------------
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // ---------------------------------------------------------
    // Stimulus
    // ---------------------------------------------------------
    initial begin
        // Reset sequence
        rst_n = 0;
        start = 0;
        adc_sdo = 0;
        #(CLK_PERIOD * 10);
        rst_n = 1;
        #(CLK_PERIOD * 10);

        // Test Case 1
        $display("[%0t] Starting Conversion 1...", $time);
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        // Simulate ADC driving 0x3FC01
        drive_mock_sdo(20'h3FC01);

        wait(data_valid);
        $display("[%0t] Captured Data 1: %h", $time, adc_data);

        #(CLK_PERIOD * 50);

        // Test Case 2
        $display("[%0t] Starting Conversion 2...", $time);
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        // Simulate ADC driving 0x80005
        drive_mock_sdo(20'h80005);

        wait(data_valid);
        $display("[%0t] Captured Data 2: %h", $time, adc_data);

        #(CLK_PERIOD * 100);
        $display("[%0t] Simulation Finished.", $time);
        $finish;
    end

    // ---------------------------------------------------------
    // Helper Task: Mock ADC SDO behavior
    // ---------------------------------------------------------
    task drive_mock_sdo(input [19:0] data_value);
        integer i;
        begin
            wait(adc_cs_n == 0);
            for (i = 19; i >= 0; i = i - 1) begin
                @(negedge adc_sclk);
                adc_sdo = data_value[i];
            end
        end
    endtask

endmodule