`timescale 1ns/1ps

module adc_core_tb;

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

    task automatic send_finish_pulse;
        begin
            @(negedge i_clk);
            i_adc_spi_finish = 1'b1;
            @(negedge i_clk);
            i_adc_spi_finish = 1'b0;
        end
    endtask

    integer sample_session_cnt;
    logic   o_adc_sampling_d;

    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            o_adc_sampling_d   <= 1'b0;
            sample_session_cnt <= 0;
        end
        else begin
            o_adc_sampling_d <= o_adc_sampling;

            if (o_adc_sampling && !o_adc_sampling_d) begin
                sample_session_cnt <= sample_session_cnt + 1;
                $display("[%0t] INFO: sampling window #%0d starts", $time, sample_session_cnt + 1);
            end
        end
    end

    initial begin
        i_clk            = 1'b0;
        i_rst            = 1'b1;
        i_adc_spi_finish = 1'b0;

        for (int k = 0; k < NUM_REGS; k++) begin
            i_all_regs[k] = 32'h0;
        end

        // program:
        // 0: NOP 4 cycles
        // 1: SAM 3 samples
        // 2: NOP 2 cycles
        // 3: SAM 2 samples
        // 4: JMP 6
        // 5: SAM 8 samples   (should be skipped)
        // 6: END
        i_all_regs[0] = make_nop(16'd4);
        i_all_regs[1] = make_sam(12'd3);
        i_all_regs[2] = make_nop(16'd2);
        i_all_regs[3] = make_sam(12'd2);
        i_all_regs[4] = make_jmp(ADDR_WIDTH'(6));
        i_all_regs[5] = make_sam(12'd8);
        i_all_regs[6] = make_end();

        repeat (4) @(posedge i_clk);
        i_rst = 1'b0;
        $display("[%0t] Release reset", $time);

        repeat (2) @(posedge i_clk);
        i_all_regs[CTRL_REG_IDX] = 32'h8000_0000;
        $display("[%0t] Start adc_core", $time);

        wait (o_active == 1'b1);
        $display("[%0t] o_active asserted", $time);

        // first SAM
        wait (o_adc_sampling == 1'b1);
        $display("[%0t] first SAM started, send 3 finish pulses", $time);
        repeat (3) send_finish_pulse();

        wait (o_adc_sampling == 1'b0);
        $display("[%0t] first SAM completed", $time);

        // second SAM
        wait (o_adc_sampling == 1'b1);
        $display("[%0t] second SAM started, send 2 finish pulses", $time);
        repeat (2) send_finish_pulse();

        wait (o_adc_sampling == 1'b0);
        $display("[%0t] second SAM completed", $time);

        wait (o_active == 1'b0);
        $display("[%0t] program finished, o_active deasserted", $time);

        repeat (5) @(posedge i_clk);

        if (sample_session_cnt != 2)
            $error("Expected 2 sampling sessions, got %0d", sample_session_cnt);
        else
            $display("PASS: observed exactly 2 sampling sessions");

        if (o_active !== 1'b0)
            $error("Expected o_active=0 at end");
        else
            $display("PASS: o_active returned to 0");

        if (o_adc_sampling !== 1'b0)
            $error("Expected o_adc_sampling=0 at end");
        else
            $display("PASS: o_adc_sampling returned to 0");

        $finish;
    end

endmodule