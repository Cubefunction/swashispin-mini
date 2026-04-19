`timescale 1ns/1ps

module adc_core_sin_tb;

    localparam int NUM_REGS     = 54;
    localparam int CTRL_REG_IDX = 53;
    localparam int ADDR_WIDTH   = $clog2(NUM_REGS);

    localparam logic [3:0] OP_NOP = 4'b0000;
    localparam logic [3:0] OP_SAM = 4'b0001;
    localparam logic [3:0] OP_JMP = 4'b0010;
    localparam logic [3:0] OP_END = 4'b1111;

    logic i_clk;
    logic i_rst;
    logic [0:NUM_REGS-1][31:0] i_all_regs;

    logic i_adc_spi_finish;
    logic o_adc_sampling;
    logic o_active;

    logic signed [15:0] adc_sample;
    logic               adc_sample_valid;

    adc_core #(
        .NUM_REGS(NUM_REGS),
        .CTRL_REG_IDX(CTRL_REG_IDX),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) dut (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_all_regs(i_all_regs),
        .i_adc_spi_finish(i_adc_spi_finish),
        .o_adc_sampling(o_adc_sampling),
        .o_active(o_active)
    );

    adc_sampling_sin_model #(
        .DATA_W(16),
        .LUT_DEPTH(256),
        .SAMPLE_GAP(8),
        .PHASE_STEP(4)
    ) u_sin_model (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_adc_sampling(o_adc_sampling),
        .o_adc_data(adc_sample),
        .o_adc_data_valid(adc_sample_valid),
        .o_adc_spi_finish(i_adc_spi_finish)
    );

    always #5 i_clk = ~i_clk;

    function automatic [31:0] make_nop(input [15:0] delay_cycles);
        make_nop = {OP_NOP, 12'd0, delay_cycles};
    endfunction

    function automatic [31:0] make_sam(input [11:0] sample_count);
        make_sam = {OP_SAM, sample_count, 16'd0};
    endfunction

    function automatic [31:0] make_jmp(input [ADDR_WIDTH-1:0] target);
        make_jmp = {OP_JMP, 12'd0, {(16-ADDR_WIDTH){1'b0}}, target};
    endfunction

    function automatic [31:0] make_end();
        make_end = {OP_END, 28'd0};
    endfunction

    integer valid_sample_cnt;

    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            valid_sample_cnt <= 0;
        end
        else if (adc_sample_valid) begin
            valid_sample_cnt <= valid_sample_cnt + 1;
            $display("[%0t] sample[%0d] = %0d", $time, valid_sample_cnt, adc_sample);
        end
    end

    initial begin
        i_clk = 1'b0;
        i_rst = 1'b1;
        valid_sample_cnt = 0;

        for (int k = 0; k < NUM_REGS; k++) begin
            i_all_regs[k] = 32'h0;
        end

        // program:
        // 0: NOP 5
        // 1: SAM 16
        // 2: NOP 3
        // 3: SAM 16
        // 4: END
        i_all_regs[0] = make_nop(16'd5);
        i_all_regs[1] = make_sam(12'd16);
        i_all_regs[2] = make_nop(16'd3);
        i_all_regs[3] = make_sam(12'd16);
        i_all_regs[4] = make_end();

        repeat (4) @(posedge i_clk);
        i_rst = 1'b0;
        $display("[%0t] reset released", $time);

        repeat (2) @(posedge i_clk);
        i_all_regs[CTRL_REG_IDX] = 32'h8000_0000;
        $display("[%0t] adc_core started", $time);

        wait (o_active == 1'b1);
        wait (o_active == 1'b0);

        repeat (10) @(posedge i_clk);

        $display("Total valid samples = %0d", valid_sample_cnt);
        if (valid_sample_cnt != 32)
            $error("Expected 32 samples, got %0d", valid_sample_cnt);
        else
            $display("PASS: sample count matched");

        $finish;
    end

    initial begin
        $dumpfile("adc_core_sin_tb.vcd");
        $dumpvars(0, adc_core_sin_tb);
    end

endmodule
