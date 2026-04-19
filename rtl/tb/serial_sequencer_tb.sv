`default_nettype none
`timescale 1ns / 1ps

module serial_sequencer_tb;

    localparam PC_WIDTH = 9;
    localparam INSN_WIDTH = 72;
    localparam REG_PER_INSN = (INSN_WIDTH + 31) / 32;
    localparam ITER_WIDTH = 16;
    localparam DEPTH_WIDTH = PC_WIDTH;
    localparam SEQ_REGS = REG_PER_INSN + 6;

    localparam IST_ADDR_REG = 0;
    localparam IST_REG_LO = IST_ADDR_REG + 1;
    localparam IST_REG_HI = IST_REG_LO + REG_PER_INSN - 1;
    localparam IST_STRB_REG = IST_REG_HI + 1;

    localparam ITERS_REG = IST_STRB_REG + 1;
    localparam DEPTH_REG = ITERS_REG + 1;
    localparam START_STRB_REG = DEPTH_REG + 1;
    localparam HALT_STRB_REG = START_STRB_REG + 1;

    logic w_clk, w_rst;

    logic [0:SEQ_REGS-1][31:0] w_regs;
    logic w_active;

    logic [PC_WIDTH-1:0] w_pc;
    logic [INSN_WIDTH-1:0] w_insn;
    logic w_next;
    logic w_empty;
    logic [INSN_WIDTH-1:0] w_insn_modified;

    serial_sequencer #(
        .PC_WIDTH(PC_WIDTH),
        .INSN_WIDTH(INSN_WIDTH),
        .ITER_WIDTH(ITER_WIDTH)
    ) DUT (
        .i_clk(w_clk),
        .i_rst(w_rst),

        .i_regs(w_regs),
        .o_active(w_active),

        .o_pc(w_pc),
        .o_insn(w_insn),
        .i_next(w_next),
        .o_empty(w_empty),
        .i_insn_modified(w_insn_modified)
    );

    // tasks
    task load_insn
    (
        input logic [PC_WIDTH-1:0] addr,
        input logic [INSN_WIDTH-1:0] insn
    );
        @(negedge w_clk);
        w_regs[IST_ADDR_REG] = '0;

        for (int i = 0; i < REG_PER_INSN; i++) begin
            w_regs[IST_REG_LO + i] = '0;
        end
        w_regs[IST_STRB_REG] = '0;

        w_regs[IST_ADDR_REG][PC_WIDTH-1:0] = addr;

        w_regs[IST_REG_LO][INSN_WIDTH - (REG_PER_INSN - 1) * 32 - 1:0] =
            insn[(REG_PER_INSN - 1) * 32 +: INSN_WIDTH - (REG_PER_INSN - 1) * 32];
        for (int i = 1; i < REG_PER_INSN; i++) begin
            w_regs[IST_REG_LO + i] = insn[(REG_PER_INSN - 1 - i) * 32 +: 32];
        end

        w_regs[IST_STRB_REG][0] = 1'b1;

        @(negedge w_clk);
        w_regs[IST_STRB_REG][0] = 1'b0;
        @(negedge w_clk);
    endtask

    task start_seq;
        @(negedge w_clk);
        w_regs[START_STRB_REG][0] = 1'b1;

        @(negedge w_clk);
        w_regs[START_STRB_REG][0] = 1'b0;
    endtask

    task halt_seq;
        @(negedge w_clk);
        w_regs[HALT_STRB_REG][0] = 1'b1;

        @(negedge w_clk);
        w_regs[HALT_STRB_REG][0] = 1'b0;
    endtask

    task load_iters(input logic [ITER_WIDTH-1:0] iters);
        @(negedge w_clk);
        w_regs[ITERS_REG] = '0;
        w_regs[ITERS_REG][ITER_WIDTH-1:0] = iters;
    endtask

    task load_depth(input logic [DEPTH_WIDTH-1:0] depth);
        @(negedge w_clk);
        w_regs[DEPTH_REG] = '0;
        w_regs[DEPTH_REG][DEPTH_WIDTH-1:0] = depth;
    endtask

    logic [PC_WIDTH-1:0] ref_pcs [0:(1 << PC_WIDTH) - 1];
    logic [INSN_WIDTH-1:0] ref_insns [0:(1 << PC_WIDTH) - 1];

    task run_rand_next;
        logic [ITER_WIDTH-1:0] iters;
        logic [DEPTH_WIDTH-1:0] depth;
        logic [PC_WIDTH-1:0] pc;
        logic [INSN_WIDTH-1:0] insn;
        int total_out;
        int out_idx;
        int seq_idx;
        logic prev_next;

        depth = $urandom_range(0, (1 << DEPTH_WIDTH) - 2);
        iters = $urandom_range(1, 16);
        $display("depth=%0b", depth);

        for (int i = 0; i < (1 << PC_WIDTH); i++) begin
            ref_pcs[pc] = '0;
            ref_insns[i] = '0;
        end

        for (pc = 0; pc <= depth; pc = pc + 'd1) begin
            insn = '0;
            for (int i = 0; i < REG_PER_INSN - 1; i++)
                insn[i * 32 +: 32] = $urandom;
            insn[INSN_WIDTH - (REG_PER_INSN - 1) * 32 - 1:0] = $urandom;

            ref_pcs[pc] = pc;
            ref_insns[pc] = insn;

            load_insn(pc, insn);
        end

        load_iters(iters);
        load_depth(depth);

        total_out = (depth + 1) * iters;
        out_idx = 0;
        seq_idx = 0;

        start_seq;

        wait(!w_empty);

        @(negedge w_clk);

        while (out_idx < total_out) begin

            w_next = $urandom_range(0, 1);
            w_insn_modified = w_insn;

            assert (!w_empty)
            else $fatal(1, "At %0.3f ns: w_empty asserted while w_next is held high at out_idx=%0d", $realtime, out_idx);

            assert (w_pc == ref_pcs[seq_idx])
            else $fatal(1, "At %0.3f ns: w_pc=0x%0x, should be 0x%0x for pc_addr=%0d",
                         $realtime, w_pc, ref_pcs[seq_idx], seq_idx);

            assert (w_insn == ref_insns[ref_pcs[seq_idx]])
            else $fatal(1, "At %0.3f ns: w_insn=0x%0x, should be 0x%0x for pc_addr=%0d pc=0x%0x",
                         $realtime, w_insn, ref_insns[ref_pcs[seq_idx]], seq_idx, ref_pcs[seq_idx]);

            if (w_next) begin

                out_idx++;

                if (seq_idx == depth)
                    seq_idx = 0;
                else
                    seq_idx++;

            end

            @(negedge w_clk);
        end

        w_next = 1'b0;
        assert (w_empty)
        else $fatal(1, "At %0.3f ns: w_empty=%0b after sequence completion, should be 1", $realtime, w_empty);

    endtask

    initial begin
        w_clk = 1'b0;
        forever #2 w_clk = !w_clk;
    end

    int test;

    initial begin
        w_rst = 1'b1;
        w_regs = '{default:'0};
        w_next = 1'b0;
        w_insn_modified = '0;

        @(negedge w_clk);
        w_rst = 1'b0;

        test = 0;
        repeat (10000) begin
            $display("test%0d", test);
            run_rand_next;
            test++;
        end

        $finish;
    end

endmodule
