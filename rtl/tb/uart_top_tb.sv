`timescale 1ns/1ps

module uart_top_tb;

    //============================================================
    // Test selection flags
    //============================================================
    parameter bit SIGNAL_TB_FLAG = 1'b0;
    parameter bit ADC_TB_FLAG    = 1'b1;

    //============================================================
    // Register map
    //============================================================
    localparam int N_REGS             = 64;

    localparam int AD9833_BASE_ADDR   = 0;

    localparam int ADC_CORE_BASE_ADDR = 4;
    localparam int ADC_CORE_NUM_REGS  = 54;
    localparam int ADC_CTRL_REG_IDX   = 53;
    localparam int ADC_CTRL_REG_ADDR  = ADC_CORE_BASE_ADDR+ADC_CTRL_REG_IDX;

    //============================================================
    // UART timing
    //============================================================
    localparam int BAUDRATE = 921600;
    localparam realtime bit_duration = (1.0e9 / BAUDRATE);

    //============================================================
    // DUT I/O
    //============================================================
    logic w_clk;
    logic w_rst = 1'b0;

    logic w_rx  = 1'b1;
    logic w_tx;

    logic w_spi_sclk;
    logic w_spi_fsync;
    logic w_spi_mosi;

    //============================================================
    // Internal capture / monitor
    //============================================================
    logic [15:0] spi_words_captured [0:4];
    integer      pc_tsmt_which_bit;

    wire w_adc_sampling = DUT.u_adc_core.o_adc_sampling;
    wire w_adc_active   = DUT.u_adc_core.o_active;

    //============================================================
    // DUT
    //============================================================
    uart_top #(
        .DATA_WIDTH         (8),
        .RX_FIFO_DEPTH      (8),
        .RX_FIFO_AF_DEPTH   (6),
        .RX_FIFO_AE_DEPTH   (2),
        .TX_FIFO_DEPTH      (8),
        .TX_FIFO_AF_DEPTH   (6),
        .TX_FIFO_AE_DEPTH   (2),
        .NUM_REGS           (N_REGS),
        .AD9833_BASE_ADDR   (AD9833_BASE_ADDR),
        .SPI_FRAME_W        (16),
        .SPI_CLK_DIV        (10)
    ) DUT (
        .i_clk        (w_clk),
        .i_rst_n      (w_rst),
        .i_rx         (w_rx),
        .o_tx         (w_tx),
        .o_spi_sclk   (w_spi_sclk),
        .o_spi_fsync  (w_spi_fsync),
        .o_spi_mosi   (w_spi_mosi)
    );

    //============================================================
    // Clock / Reset
    //============================================================
    initial begin
        w_clk = 1'b0;
        forever #5 w_clk = ~w_clk;   // 100 MHz
    end

    initial begin
        repeat (20) @(negedge w_clk);
        w_rst <= 1'b1;
    end

    //============================================================
    // PC -> FPGA UART byte transmit
    // UART frame: start(0), 8 data bits LSB-first, stop(1)
    //============================================================
    task automatic pc_tsmt(input logic [7:0] data);
    begin
        $display("At %0.3f ns: pc sends 0x%02h", $realtime, data);

        @(negedge w_clk);
        w_rx = 1'b0;
        pc_tsmt_which_bit = -1;
        #bit_duration;

        for (int i = 0; i < 8; i++) begin
            @(negedge w_clk);
            w_rx = data[i];
            pc_tsmt_which_bit = i;
            #bit_duration;
        end

        @(negedge w_clk);
        w_rx = 1'b1;
        pc_tsmt_which_bit = 8;
        #bit_duration;
    end
    endtask

    task automatic pc_tsmt_gap(input int max_bits_idle = 3);
        int idle_bits;
        begin
            idle_bits = $urandom_range(0, max_bits_idle);
            if (idle_bits > 0)
                #(bit_duration * idle_bits);
        end
    endtask

    //============================================================
    // UART register write helper
    // Protocol:
    //   op[7]=0 write
    //   op[6:0]=addr
    //   then 4 data bytes: [31:24] [23:16] [15:8] [7:0]
    //============================================================
    task automatic send_write(input logic [6:0] idx, input logic [31:0] data);
    begin
        $display("WRITE regs[%0d] = 0x%08x", idx, data);

        pc_tsmt({1'b0, idx});
        pc_tsmt_gap();

        pc_tsmt(data[31:24]);
        pc_tsmt_gap();

        pc_tsmt(data[23:16]);
        pc_tsmt_gap();

        pc_tsmt(data[15:8]);
        pc_tsmt_gap();

        pc_tsmt(data[7:0]);
        pc_tsmt_gap();
    end
    endtask

    //============================================================
    // SPI capture helper
    //============================================================
    task automatic capture_one_spi_word(output logic [15:0] word);
    begin
        word = 16'h0000;
    
        @(negedge w_spi_fsync);
    
        for (int i = 15; i >= 0; i--) begin
            @(negedge w_spi_sclk);
            #1step;
            word[i] = w_spi_mosi;
        end
    
        @(posedge w_spi_fsync);
    
        $display("At %0.3f ns: captured SPI word = 0x%04x", $realtime, word);
    end
    endtask

    //============================================================
    // ADC instruction helper
    // Current encoding:
    //   [31:28] opcode
    //   [27:16] loop_max
    //   [15:0]  delay_or_target
    //============================================================
    function automatic [31:0] make_adc_insn(
        input logic [3:0]  opcode,
        input logic [11:0] loop_max,
        input logic [15:0] delay_or_target
    );
        begin
            make_adc_insn = {opcode, loop_max, delay_or_target};
        end
    endfunction

    //============================================================
    // SIGNAL GEN TEST
    //============================================================
task automatic run_signal_test;
    logic [15:0] exp_word0;
    logic [15:0] exp_word1;
    logic [15:0] exp_word2;
    logic [15:0] exp_word3;
    logic [15:0] exp_word4;

    logic [31:0] reg_cmd;
    logic [31:0] reg_freq;
    logic [31:0] reg_phase_ctrl;
begin
    $display("\n==================================================");
    $display("START SIGNAL GENERATION TEST");
    $display("==================================================");

    exp_word0 = 16'h2100;
    exp_word1 = 16'h4567;
    exp_word2 = 16'h48D1;
    exp_word3 = 16'hC100;
    exp_word4 = 16'h2000;

    reg_cmd        = {16'h0000, exp_word0};
    reg_freq       = {exp_word2, exp_word1};
    reg_phase_ctrl = {exp_word4, exp_word3};

    for (int k = 0; k < 5; k++) begin
        spi_words_captured[k] = 16'h0000;
    end

    // --------------------------------------------------------
    // Write registers through UART
    // --------------------------------------------------------
    send_write(AD9833_BASE_ADDR + 0, reg_cmd);
    send_write(AD9833_BASE_ADDR + 1, reg_freq);
    send_write(AD9833_BASE_ADDR + 2, reg_phase_ctrl);

    // clear start first
    send_write(AD9833_BASE_ADDR + 3, 32'h0000_0000);

    repeat (50) @(posedge w_clk);


    fork
        begin : trigger_thread
            send_write(AD9833_BASE_ADDR + 3, 32'h0000_0001);
        end
    join_none

    fork : signal_wait_group
        begin : capture_thread
            capture_one_spi_word(spi_words_captured[0]);
            capture_one_spi_word(spi_words_captured[1]);
            capture_one_spi_word(spi_words_captured[2]);
            capture_one_spi_word(spi_words_captured[3]);
            capture_one_spi_word(spi_words_captured[4]);
        end

        begin : timeout_thread
            #(bit_duration * 5000.0);
            $fatal(1, "Timeout waiting for AD9833 SPI sequence at %0.3f ns", $realtime);
        end
    join_any

    disable signal_wait_group;

    // --------------------------------------------------------
    // give some time for signals to settle
    // --------------------------------------------------------
    repeat (50) @(posedge w_clk);

    // --------------------------------------------------------
    // Check order and data
    // --------------------------------------------------------
    if (spi_words_captured[0] !== exp_word0)
        $fatal(1, "SPI word0 mismatch: exp=0x%04x got=0x%04x",
               exp_word0, spi_words_captured[0]);

    if (spi_words_captured[1] !== exp_word1)
        $fatal(1, "SPI word1 mismatch: exp=0x%04x got=0x%04x",
               exp_word1, spi_words_captured[1]);

    if (spi_words_captured[2] !== exp_word2)
        $fatal(1, "SPI word2 mismatch: exp=0x%04x got=0x%04x",
               exp_word2, spi_words_captured[2]);

    if (spi_words_captured[3] !== exp_word3)
        $fatal(1, "SPI word3 mismatch: exp=0x%04x got=0x%04x",
               exp_word3, spi_words_captured[3]);

    if (spi_words_captured[4] !== exp_word4)
        $fatal(1, "SPI word4 mismatch: exp=0x%04x got=0x%04x",
               exp_word4, spi_words_captured[4]);

    $display("--------------------------------------------------");
    $display("SIGNAL TEST PASS");
    $display("SPI words sent in correct order:");
    $display("  word0 = 0x%04x", spi_words_captured[0]);
    $display("  word1 = 0x%04x", spi_words_captured[1]);
    $display("  word2 = 0x%04x", spi_words_captured[2]);
    $display("  word3 = 0x%04x", spi_words_captured[3]);
    $display("  word4 = 0x%04x", spi_words_captured[4]);
    $display("--------------------------------------------------");
end
endtask

    //============================================================
    // ADC CORE TEST
    //============================================================
    task automatic run_adc_test;
        logic [31:0] adc_insn0;
        logic [31:0] adc_insn1;
        logic [31:0] adc_insn2;
        logic [31:0] adc_insn3;
    begin
        $display("\n==================================================");
        $display("START ADC CORE TEST");
        $display("==================================================");


        // insn0: NOP delay=3
        // insn1: SAM delay=5
        // insn2: JMP target=0, loop_max=2
        // insn3: END
        adc_insn0 = make_adc_insn(4'b0000, 12'd0, 16'd3);
        adc_insn1 = make_adc_insn(4'b0001, 12'd0, 16'd5);
        adc_insn2 = make_adc_insn(4'b0010, 12'd2, 16'd0);
        adc_insn3 = make_adc_insn(4'b1111, 12'd0, 16'd0);

        // 先清 start
        send_write(ADC_CTRL_REG_ADDR, 32'h0000_0000);

        // 写 ADC program memory
        send_write(ADC_CORE_BASE_ADDR + 0, adc_insn0);
        send_write(ADC_CORE_BASE_ADDR + 1, adc_insn1);
        send_write(ADC_CORE_BASE_ADDR + 2, adc_insn2);
        send_write(ADC_CORE_BASE_ADDR + 3, adc_insn3);

        $display("ADC program loaded:");
        $display("  reg[%0d] = 0x%08x", ADC_CORE_BASE_ADDR + 0, adc_insn0);
        $display("  reg[%0d] = 0x%08x", ADC_CORE_BASE_ADDR + 1, adc_insn1);
        $display("  reg[%0d] = 0x%08x", ADC_CORE_BASE_ADDR + 2, adc_insn2);
        $display("  reg[%0d] = 0x%08x", ADC_CORE_BASE_ADDR + 3, adc_insn3);
        $display("  reg[%0d][31] = start", ADC_CTRL_REG_ADDR);

        repeat (50) @(posedge w_clk);

        send_write(ADC_CTRL_REG_ADDR, 32'h8000_0000);

        fork
            begin : wait_active_high
                wait (w_adc_active === 1'b1);
                $display("At %0.3f ns: ADC core became ACTIVE", $realtime);
            end

            begin : timeout_active_high
                #(bit_duration * 5000.0);
                $fatal(1, "Timeout waiting ADC active high at %0.3f ns", $realtime);
            end
        join_any
        disable fork;

        fork
            begin : wait_sampling_high
                wait (w_adc_sampling === 1'b1);
                $display("At %0.3f ns: ADC sampling asserted", $realtime);
            end

            begin : timeout_sampling_high
                #(bit_duration * 10000.0);
                $fatal(1, "Timeout waiting ADC sampling high at %0.3f ns", $realtime);
            end
        join_any
        disable fork;

        
        fork
            begin : wait_active_low
                wait (w_adc_active === 1'b0);
                $display("At %0.3f ns: ADC core finished, active deasserted", $realtime);
            end

            begin : timeout_active_low
                #(bit_duration * 30000.0);
                $fatal(1, "Timeout waiting ADC active low at %0.3f ns", $realtime);
            end
        join_any
        disable fork;

        
        send_write(ADC_CTRL_REG_ADDR, 32'h0000_0000);

        repeat (50) @(posedge w_clk);

        $display("ADC TEST PASS");
    end
    endtask

    //============================================================
    // Main test control
    //============================================================
    initial begin : main
        @(posedge w_rst);
        repeat (50) @(posedge w_clk);

        $display("\n==================================================");
        $display("TB CONFIG:");
        $display("  SIGNAL_TB_FLAG = %0d", SIGNAL_TB_FLAG);
        $display("  ADC_TB_FLAG    = %0d", ADC_TB_FLAG);
        $display("==================================================\n");

        if (!SIGNAL_TB_FLAG && !ADC_TB_FLAG) begin
            $display("No test selected. Nothing to run.");
            $finish;
        end

        if (SIGNAL_TB_FLAG) begin
            run_signal_test();
        end

        if (ADC_TB_FLAG) begin
            run_adc_test();
        end

        $display("\n==================================================");
        $display("uart_top_tb: ALL SELECTED TESTS PASSED");
        $display("==================================================\n");

        $finish;
    end

endmodule