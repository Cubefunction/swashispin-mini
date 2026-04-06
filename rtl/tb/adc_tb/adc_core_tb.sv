`timescale 1ns/1ps

module adc_core_tb;

    localparam int NUM_REGS      = 54;
    localparam int CTRL_REG_IDX  = 53;
    localparam int ADDR_WIDTH    = $clog2(NUM_REGS);

    logic i_clk;
    logic i_rst;
    logic [0:NUM_REGS-1][31:0] i_all_regs;

    logic o_adc_sampling;
    logic o_active;

    //==================================================
    // DUT
    //==================================================
    adc_core #(
        .NUM_REGS     (NUM_REGS),
        .CTRL_REG_IDX (CTRL_REG_IDX),
        .ADDR_WIDTH   (ADDR_WIDTH)
    ) dut (
        .i_clk          (i_clk),
        .i_rst          (i_rst),
        .i_all_regs     (i_all_regs),
        .o_adc_sampling (o_adc_sampling),
        .o_active       (o_active)
    );

    //==================================================
    // Clock : 100MHz
    //==================================================
    initial begin
        i_clk = 1'b0;
        forever #5 i_clk = ~i_clk;
    end

    //==================================================
    // VCD
    //==================================================
    initial begin
        $dumpfile("adc_core_tb.vcd");
        $dumpvars(0, adc_core_tb);
    end

    //==================================================
    // Helper
    //==================================================
    function automatic [31:0] make_insn(
        input logic [3:0]  opcode,
        input logic [11:0] loop_max,
        input logic [15:0] delay_or_target
    );
        begin
            make_insn = {opcode, loop_max, delay_or_target};
        end
    endfunction

    task automatic clear_regs;
        integer k;
        begin
            for (k = 0; k < NUM_REGS; k = k + 1) begin
                i_all_regs[k] = 32'h0;
            end
        end
    endtask

    task automatic print_state(input string tag);
        begin
            $display("[%0t] %s", $time, tag);
            $display("    start_en=%0d active=%0d adc_sampling=%0d",
                     dut.start_en, o_active, o_adc_sampling);

            $display("    IF : pc=%0d insn=0x%08h valid=%0d",
                     dut.if_pc, dut.if_insn, dut.if_valid);

            $display("    ID : pc=%0d opcode=0x%0h loop_max=%0d target=%0d delay=%0d valid=%0d",
                     dut.id_pc, dut.id_opcode, dut.id_loop_max,
                     dut.id_target, dut.id_delay_cycles, dut.id_valid);

            $display("    EX : pc=%0d opcode=0x%0h loop_max=%0d target=%0d delay=%0d timer=%0d busy=%0d valid=%0d",
                     dut.ex_pc, dut.ex_opcode, dut.ex_loop_max,
                     dut.ex_target, dut.ex_delay_cycles,
                     dut.ex_timer, dut.ex_busy, dut.ex_valid);

            $display("    loop_cnt=%0d stall_pipe=%0d next_pc=%0d next_pc_valid=%0d",
                     dut.loop_cnt, dut.stall_pipe, dut.next_pc, dut.next_pc_valid);
        end
    endtask

    task automatic wait_cycles(input int n);
        int j;
        begin
            for (j = 0; j < n; j = j + 1) begin
                @(posedge i_clk);
                #1;
                print_state("RUN");
            end
        end
    endtask

    //==================================================
    // Monitor
    //==================================================
    always @(posedge i_clk) begin
        #1;
        $display("[%0t] MON | if_pc=%0d id_pc=%0d ex_pc=%0d | ex_opcode=%0h ex_busy=%0d ex_timer=%0d | active=%0d sampling=%0d loop_cnt=%0d",
                 $time,
                 dut.if_pc,
                 dut.id_pc,
                 dut.ex_pc,
                 dut.ex_opcode,
                 dut.ex_busy,
                 dut.ex_timer,
                 o_active,
                 o_adc_sampling,
                 dut.loop_cnt);
    end

    //==================================================
    // Stimulus
    //==================================================
    initial begin
        clear_regs();
        i_rst = 1'b1;

        repeat (5) @(posedge i_clk);
        #1;
        print_state("RESET ASSERTED");

        i_rst = 1'b0;
        @(posedge i_clk);
        #1;
        print_state("RESET RELEASED");

        //------------------------------------------------
        // Program
        //
        // reg[0] = NOP 3
        // reg[1] = SAM 5
        // reg[2] = JMP target=1 loop_max=2
        // reg[3] = END
        //
        //------------------------------------------------
        i_all_regs[0] = make_insn(4'b0000, 12'd0, 16'd3); // NOP 3 cycles
        i_all_regs[1] = make_insn(4'b0001, 12'd0, 16'd5); // SAM 5 cycles
        i_all_regs[2] = make_insn(4'b0010, 12'd2, 16'd0); // JMP target = 1
        i_all_regs[3] = make_insn(4'b1111, 12'd0, 16'd0); // END

        $display("\n================ PROGRAM LOADED ================");
        $display("reg[0] = 0x%08h  NOP 3", i_all_regs[0]);
        $display("reg[1] = 0x%08h  SAM 5", i_all_regs[1]);
        $display("reg[2] = 0x%08h  JMP target=1 loop_max=2", i_all_regs[2]);
        $display("reg[3] = 0x%08h  END", i_all_regs[3]);
        $display("CTRL   = reg[%0d][31] start bit", CTRL_REG_IDX);
        $display("================================================\n");

        //------------------------------------------------
        // start
        //------------------------------------------------
        @(posedge i_clk);
        i_all_regs[CTRL_REG_IDX][31] = 1'b1;
        #1;
        print_state("START ASSERTED");

        //------------------------------------------------
        // run
        //------------------------------------------------
        wait_cycles(50);

        //------------------------------------------------
        // stop externally
        //------------------------------------------------
        @(posedge i_clk);
        i_all_regs[CTRL_REG_IDX][31] = 1'b0;
        #1;
        print_state("START DEASSERTED");

        wait_cycles(5);

        $display("\n================ TB FINISHED ================\n");
        $finish;
    end

endmodule