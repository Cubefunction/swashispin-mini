`timescale 1ns/1ps

module ad9833_top_tb;

    localparam int SPI_CLK_DIV = 10;

    logic        w_clk;
    logic        w_rst_n;

    logic [31:0] w_reg_cmd;
    logic [31:0] w_reg_freq;
    logic [31:0] w_reg_phase_ctrl;
    logic [31:0] w_reg_control;

    logic        w_spi_sclk;
    logic        w_spi_fsync;
    logic        w_spi_mosi;

    logic        w_busy;
    logic        w_done_pulse;
    logic [31:0] w_status_word;

    logic [15:0] captured_words [0:4];

    // ------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------
    ad9833_top #(
        .FRAME_W     (16),
        .SPI_CLK_DIV (SPI_CLK_DIV)
    ) dut (
        .i_clk            (w_clk),
        .i_rst_n          (w_rst_n),

        .i_reg_cmd        (w_reg_cmd),
        .i_reg_freq       (w_reg_freq),
        .i_reg_phase_ctrl (w_reg_phase_ctrl),
        .i_reg_control    (w_reg_control),

        .o_spi_sclk       (w_spi_sclk),
        .o_spi_fsync      (w_spi_fsync),
        .o_spi_mosi       (w_spi_mosi),

        .o_busy           (w_busy),
        .o_done_pulse     (w_done_pulse),
        .o_status_word    (w_status_word)
    );

    // ------------------------------------------------------------
    // clock
    // ------------------------------------------------------------
    initial begin
        w_clk = 1'b0;
        forever #5 w_clk = ~w_clk; // 100MHz
    end

    // ------------------------------------------------------------
    // reset
    // ------------------------------------------------------------
    initial begin
        w_rst_n = 1'b0;

        w_reg_cmd        = 32'h0;
        w_reg_freq       = 32'h0;
        w_reg_phase_ctrl = 32'h0;
        w_reg_control    = 32'h0;

        repeat (20) @(posedge w_clk);
        w_rst_n = 1'b1;
    end

    // ------------------------------------------------------------
    // Capture one SPI 16-bit frame
    // Assumption:
    //   - fsync low means active frame
    //   - MOSI is sampled on posedge spi_sclk
    // If your spi_master uses the opposite edge, change it here.
    // ------------------------------------------------------------
    task automatic capture_one_word(output logic [15:0] word);
        begin
            word = 16'h0000;

            @(negedge w_spi_fsync);

            for (int i = 15; i >= 0; i--) begin
                @(posedge w_spi_sclk);
                word[i] = w_spi_mosi;
            end

            @(posedge w_spi_fsync);

            $display("[%0t ns] captured SPI word = 0x%04x", $time, word);
        end
    endtask

    // ------------------------------------------------------------
    // Start pulse helper
    // reg_control[0] = start
    // ------------------------------------------------------------
    task automatic pulse_start;
        begin
            @(posedge w_clk);
            w_reg_control[0] <= 1'b0;

            @(posedge w_clk);
            w_reg_control[0] <= 1'b1;

            @(posedge w_clk);
            w_reg_control[0] <= 1'b0;
        end
    endtask

    // ------------------------------------------------------------
    // Main test
    // ------------------------------------------------------------
    initial begin : main_test
        logic [15:0] exp_word0;
        logic [15:0] exp_word1;
        logic [15:0] exp_word2;
        logic [15:0] exp_word3;
        logic [15:0] exp_word4;

        wait (w_rst_n == 1'b1);
        repeat (20) @(posedge w_clk);

        // Example AD9833 programming words
        exp_word0 = 16'h2100; // init ctrl/reset
        exp_word1 = 16'h4567; // freq lsb
        exp_word2 = 16'h48D1; // freq msb
        exp_word3 = 16'hC100; // phase
        exp_word4 = 16'h2000; // final ctrl/run

        // Map into the 4 input regs
        w_reg_cmd        = {16'h0000, exp_word0};
        w_reg_freq       = {exp_word2, exp_word1};
        w_reg_phase_ctrl = {exp_word4, exp_word3};
        w_reg_control    = 32'h0000_0000;

        fork
            begin : capture_thread
                capture_one_word(captured_words[0]);
                capture_one_word(captured_words[1]);
                capture_one_word(captured_words[2]);
                capture_one_word(captured_words[3]);
                capture_one_word(captured_words[4]);
            end

            begin : start_thread
                pulse_start();
            end
        join

        repeat (50) @(posedge w_clk);

        if (captured_words[0] !== exp_word0)
            $fatal(1, "word0 mismatch: exp=0x%04x got=0x%04x", exp_word0, captured_words[0]);

        if (captured_words[1] !== exp_word1)
            $fatal(1, "word1 mismatch: exp=0x%04x got=0x%04x", exp_word1, captured_words[1]);

        if (captured_words[2] !== exp_word2)
            $fatal(1, "word2 mismatch: exp=0x%04x got=0x%04x", exp_word2, captured_words[2]);

        if (captured_words[3] !== exp_word3)
            $fatal(1, "word3 mismatch: exp=0x%04x got=0x%04x", exp_word3, captured_words[3]);

        if (captured_words[4] !== exp_word4)
            $fatal(1, "word4 mismatch: exp=0x%04x got=0x%04x", exp_word4, captured_words[4]);

        if (w_busy !== 1'b0)
            $fatal(1, "Expected busy=0 after completion, got %0b", w_busy);

        $display("--------------------------------------------------");
        $display("PASS: ad9833_top sent 5 SPI words in correct order");
        $display("status_word = 0x%08x", w_status_word);
        $display("--------------------------------------------------");

        $finish;
    end

endmodule