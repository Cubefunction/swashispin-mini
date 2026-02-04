`timescale 1ns/1ps

module adc_core_tb;

    // Clock and Reset
    logic clk;
    logic rst_n;

    // UART Interface (Inputs to FIFO)
    logic [31:0] uart_wr_data;
    logic [6:0]  uart_addr;
    logic        uart_wr_en;

    // ADC Interface
    logic        adc_cnv;
    logic        adc_sclk;
    logic        adc_cs_n;
    logic        adc_sdo;

    // Output Data
    logic [19:0] adc_raw_data;
    logic        adc_data_valid;

    // --- Clock Generation (100MHz) ---
    initial clk = 0;
    always #5 clk = ~clk; 

    // --- DUT Instantiation ---
    adc_core dut (
        .clk            (clk),
        .rst_n          (rst_n),
        .uart_wr_data   (uart_wr_data),
        .uart_addr      (uart_addr),
        .uart_wr_en     (uart_wr_en),
        .adc_cnv        (adc_cnv),
        .adc_sclk       (adc_sclk),
        .adc_cs_n       (adc_cs_n),
        .adc_sdo        (adc_sdo),
        .adc_raw_data   (adc_raw_data),
        .adc_data_valid (adc_data_valid)
    );

    // --- UART Command Task ---
    task send_uart_cmd(input [6:0] addr, input [31:0] data);
        begin
            @(posedge clk);
            uart_addr   <= addr;
            uart_wr_data <= data;
            uart_wr_en   <= 1'b1;
            @(posedge clk);
            uart_wr_en   <= 1'b0;
            #10; 
        end
    endtask

    // --- ADC SDO Simulation Model ---
    logic [19:0] fake_adc_val = 20'hA5A5A; 
    integer bit_ptr;

    initial bit_ptr = 19;

    always @(negedge adc_sclk or posedge adc_cs_n) begin
        if (adc_cs_n) begin
            adc_sdo <= 1'bz;
            bit_ptr <= 19;
        end else begin
            #1 adc_sdo <= fake_adc_val[bit_ptr];
            if (bit_ptr > 0) bit_ptr <= bit_ptr - 1;
            else             bit_ptr <= 19;
        end
    end

    // --- ADC SDO Real-time Monitor ---
    initial begin
        $display("\n[Monitor] Time\t\tSignal\tValue");
        $display("---------------------------------------");
        forever begin
            @(adc_sdo); 
            $display("[Monitor] %0t\tadc_sdo\t%b", $time, adc_sdo);
        end
    end

    // --- Stimulus Process (Anti-Hanging Version) ---
    initial begin
        // 1. 初始化
        rst_n = 0;
        uart_wr_en = 0;
        uart_addr = 0;
        uart_wr_data = 0;

        #100;
        rst_n = 1;
        #200;

        // 2. 发送采样指令
        $display("\n[TB] Sending OP_SAMPLE header...");
        send_uart_cmd(7'd50, 32'hADCA0002);

        $display("[TB] Sending duration: 500 ticks...");
        send_uart_cmd(7'd50, 32'd500); 

        fork : wait_logic
            begin

                @(posedge adc_data_valid);
                $display("[TB] Captured ADC Data: %h at time %0t", adc_raw_data, $time);
                disable wait_logic; 
            end
            begin

                #100000; 
                $display("[TB] TIMEOUT ERROR: Did not see adc_data_valid within 100us!");
                disable wait_logic; 
            end
        join


        #500;
        $display("\n[TB] Simulation Finished.");
        $finish;
    end

    // --- Waveform Dump ---
    initial begin
        $fsdbDumpfile("adc_sim.fsdb");
        $fsdbDumpvars(0, adc_core_tb.dut);
    end

endmodule