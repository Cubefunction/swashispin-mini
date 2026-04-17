`default_nettype none
`timescale 1ns / 1ps
`include "include/dc.svh"

module dc_tb;

    localparam IST_ADDR_REG = 0;
    localparam IST_REG_LO = IST_ADDR_REG + 1;
    localparam IST_REG_HI = IST_REG_LO + DC_REG_PER_INSN - 1;
    localparam IST_STRB_REG = IST_REG_HI + 1;

    localparam ITERS_REG = IST_STRB_REG + 1;
    localparam DEPTH_REG = ITERS_REG + 1;
    localparam START_STRB_REG = DEPTH_REG + 1;
    localparam HALT_STRB_REG = START_STRB_REG + 1;

    localparam INSN_WIDTH = DC_INSN_WIDTH;
    localparam PC_WIDTH = $clog2(DC_DEPTH);

    logic w_clk, w_rst;

    logic w_sclk;
    logic w_mosi;
    logic w_miso;
    logic w_cs_n;
    logic w_ldac_n;

    logic [0:DC_SEQ_REGS-1][31:0] w_seq_regs;
    logic [0:DC_CTRL_REGS-1][31:0] w_ctrl_regs;

    dc_eop_t w_eop;

    logic w_start;
    logic w_armed;

    logic w_empty;

    dc #(
        .SPI_DATA_WIDTH(DC_SPI_DATA_WIDTH),
        .CYCLE_WIDTH(DC_CYCLE_WIDTH),
        .SEQ_ITER_WIDTH(DC_SEQ_ITER_WIDTH),
        .CORE_ITER_WIDTH(DC_CORE_ITER_WIDTH),
        .SPI_DVSR_WIDTH(DC_SPI_DVSR_WIDTH),
        .SPI_CS_UP_WIDTH(DC_SPI_CS_UP_WIDTH),
        .SPI_LDAC_WIDTH(DC_SPI_LDAC_WIDTH),
        .DEPTH(DC_DEPTH),
        .INSN_WIDTH(DC_INSN_WIDTH),
        .REG_PER_INSN(DC_REG_PER_INSN),
        .SEQ_REGS(DC_SEQ_REGS),
        .CTRL_REGS(DC_CTRL_REGS)
    ) DC (
        .i_clk(w_clk),
        .i_rst(w_rst),

        .i_seq_regs(w_seq_regs),
        .i_ctrl_regs(w_ctrl_regs),

        .o_sclk(w_sclk),
        .o_mosi(w_mosi),
        .i_miso(w_miso),
        .o_cs_n(w_cs_n),
        .o_ldac_n(w_ldac_n),

        .i_start(w_start),
        .o_armed(w_armed),

        .o_empty(w_empty),

        .o_eop(w_eop)
    );

    logic [19:0] w_vout;
    real vdc;

    ad5791 DC_DAC (
        .SCLK(w_sclk),
        .SDIN(w_mosi),
        .SYNC_N(w_cs_n),
        .SDO(w_miso),
        .LDAC_N(w_ldac_n),
        .CLR_N(1'b1),
        .RESET_N(1'b1),
        .VDIGITAL(w_vout),
        .VOUT(vdc)
    );

    // tasks
    task load_insn
    (
        input logic [PC_WIDTH-1:0] addr,
        input logic [INSN_WIDTH-1:0] insn
    );
        @(negedge w_clk);
        w_seq_regs[IST_ADDR_REG] = '0;

        for (int i = 0; i < DC_REG_PER_INSN; i++) begin
            w_seq_regs[IST_REG_LO + i] = '0;
        end
        w_seq_regs[IST_STRB_REG] = '0;

        w_seq_regs[IST_ADDR_REG][PC_WIDTH-1:0] = addr;

        w_seq_regs[IST_REG_LO][INSN_WIDTH - (DC_REG_PER_INSN - 1) * 32 - 1:0] =
            insn[(DC_REG_PER_INSN - 1) * 32 +: INSN_WIDTH - (DC_REG_PER_INSN - 1) * 32];
        for (int i = 1; i < DC_REG_PER_INSN; i++) begin
            w_seq_regs[IST_REG_LO + i] = insn[(DC_REG_PER_INSN - 1 - i) * 32 +: 32];
        end

        w_seq_regs[IST_STRB_REG][0] = 1'b1;

        @(negedge w_clk);
        w_seq_regs[IST_STRB_REG][0] = 1'b0;
        @(negedge w_clk);
    endtask

    task start_seq;
        @(negedge w_clk);
        w_seq_regs[START_STRB_REG][0] = 1'b1;

        @(negedge w_clk);
        w_seq_regs[START_STRB_REG][0] = 1'b0;
    endtask

    task halt_seq;
        @(negedge w_clk);
        w_seq_regs[HALT_STRB_REG][0] = 1'b1;

        @(negedge w_clk);
        w_seq_regs[HALT_STRB_REG][0] = 1'b0;
    endtask

    task load_iters(input logic [DC_SEQ_ITER_WIDTH-1:0] iters);
        @(negedge w_clk);
        w_seq_regs[ITERS_REG] = '0;
        w_seq_regs[ITERS_REG][DC_SEQ_ITER_WIDTH-1:0] = iters;
    endtask

    task load_depth(input logic [PC_WIDTH-1:0] depth);
        @(negedge w_clk);
        w_seq_regs[DEPTH_REG] = '0;
        w_seq_regs[DEPTH_REG][PC_WIDTH-1:0] = depth;
    endtask

    localparam MAX_SEQ_ITERS = 10;
    localparam MAX_CORE_ITERS = 100;
    localparam MAX_CYCLES = 2000;

    dc_eop_t golden_seq [$];
    int num_insns;
    int iters;
    dc_eop_t eop;
    dc_eop_t golden_eop;

    dc_insn_t [0:DC_DEPTH-1] insns;
    
    logic [DC_SPI_DVSR_WIDTH-1:0] dvsr_reg;
    logic [DC_SPI_DELAY_WIDTH-1:0] delay_reg;
    logic [DC_SPI_CS_UP_WIDTH-1:0] cs_up_reg;
    logic [DC_SPI_LDAC_WIDTH-1:0] ldac_reg;
    logic [31:0] new_ctrl_reg;
    assign w_ctrl_regs[0] = {{(32-DC_SPI_DVSR_WIDTH){1'b0}}, dvsr_reg};
    assign w_ctrl_regs[1] = {{(32-DC_SPI_DELAY_WIDTH){1'b0}}, delay_reg};
    assign w_ctrl_regs[2] = {{(32-DC_SPI_CS_UP_WIDTH){1'b0}}, cs_up_reg};
    assign w_ctrl_regs[3] = {{(32-DC_SPI_LDAC_WIDTH){1'b0}}, ldac_reg};
    assign w_ctrl_regs[4] = new_ctrl_reg;

    task get_golden_seq;

        if (golden_seq.size() > 0)
            golden_seq.delete();

        for (int i = 0; i < iters; i++) begin

            for (int j = 0; j < num_insns; j++) begin

                for (int iter = insns[j].w_iters; iter >= 0; iter--) begin

                    for (int cycle = ldac_reg; cycle >= 0; cycle--) begin

                        eop.w_addr = j;
                        eop.w_iter = iter;
                        eop.w_spi_din = {
                            insns[j].w_spi_din[DC_SPI_DATA_WIDTH-1:DC_DAC_WIDTH], 
                            insns[j].w_spi_din[DC_DAC_WIDTH-1:0] + 
                            20'({{(DC_DAC_WIDTH-DC_DELTA_WIDTH){insns[j].w_delta[DC_DELTA_WIDTH-1]}}, insns[j].w_delta} * (insns[j].w_iters - iter))};
                        eop.w_ldac_cycles = cycle;
                        eop.w_cycles_left = insns[j].w_hold_cycles - (ldac_reg - cycle);

                        golden_seq.push_back(eop);

                    end

                    for (int cycle = insns[j].w_hold_cycles - ldac_reg - 1; cycle >= 0; cycle--) begin

                        eop.w_addr = j;
                        eop.w_iter = iter;
                        eop.w_spi_din = {
                            insns[j].w_spi_din[DC_SPI_DATA_WIDTH-1:DC_DAC_WIDTH], 
                            insns[j].w_spi_din[DC_DAC_WIDTH-1:0] + 
                            20'({{(DC_DAC_WIDTH-DC_DELTA_WIDTH){insns[j].w_delta[DC_DELTA_WIDTH-1]}}, insns[j].w_delta} * (insns[j].w_iters - iter))};
                        eop.w_ldac_cycles = 'h0;
                        eop.w_cycles_left = cycle;

                        golden_seq.push_back(eop);

                    end

                end

            end

        end

    endtask

    task init;

        $display("init");

        insns[0] = '{
            w_iters: 'd0,
            w_spi_din: {1'b0, 3'b010, 10'b0, 4'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0},
            w_delta: 'h0,
            w_strb_ldac: 1'b0,
            w_hold_cycles: 'h0,
            w_modify: 1'b0,
            w_arm: 1'b1,
            w_idle: 1'b0
        };

        load_insn('d0, insns[0]);
        load_iters('d1);
        load_depth('d0);
        start_seq;

        wait(w_armed);
        repeat(3) @(negedge w_clk);

        w_start = 1'b1;
        @(negedge w_clk);
        w_start = 1'b0;

    endtask

    int min_hold_cycles;

    task rand_insns;

        dvsr_reg = $urandom_range(6, 20);
        delay_reg = $urandom_range(10, 20);
        cs_up_reg = $urandom_range(10, 20);
        ldac_reg = $urandom_range(2, 10);
        $display("dvsr_reg=%0d", dvsr_reg);
        $display("delay_reg=%0d", delay_reg);
        $display("cs_up_reg=%0d", cs_up_reg);
        $display("ldac_reg=%0d", ldac_reg);

        min_hold_cycles = (dvsr_reg + 1) * 48 + delay_reg + cs_up_reg + 10;
        $display("min_hold_cycles=%0d", min_hold_cycles);

        for (int i = 0; i < DC_DEPTH; i++) begin
            insns[i] = 'h0;
        end

        num_insns = $urandom_range(1, DC_DEPTH - 1);
        // num_insns = $urandom_range(1, 5);

        for (int i = 0; i < num_insns; i++) begin
            insns[i] = '{
                w_iters: $urandom_range(0, MAX_CORE_ITERS),
                w_spi_din: {1'b0, 3'b001, 20'($urandom_range(0, 20'hfffff))},
                w_delta: $urandom_range(0, 16'hffff),
                w_strb_ldac: 1'b1,
                w_hold_cycles: $urandom_range(min_hold_cycles, MAX_CYCLES),
                w_modify: 1'b0,
                w_arm: (i == 0),
                w_idle: 1'b0
            };
            $display("insn%0d", i);
            $display("w_iters=%0d", insns[i].w_iters);
            $display("w_spi_din=0x%0h", insns[i].w_spi_din);
            $display("w_delta=0x%0h", insns[i].w_delta);
            $display("w_strb_ldac=0x%0h", insns[i].w_strb_ldac);
            $display("w_hold_cycles=%0d", insns[i].w_hold_cycles);
            $display("w_arm=0x%0h\n", insns[i].w_arm);
        end

        for (int i = 0; i < num_insns; i++) begin
            load_insn(i, insns[i]);
        end

        iters = $urandom_range(1, MAX_SEQ_ITERS);
        load_iters(iters);
        load_depth(num_insns - 1);

        new_ctrl_reg = 32'h0;

        get_golden_seq;

        @(negedge w_clk);
        new_ctrl_reg = 32'b1;
        start_seq;

        wait(w_armed);
        $display("armed");
        repeat(3) @(negedge w_clk);
        new_ctrl_reg = 'd0;
        w_start = 1'b1;
        @(negedge w_clk);
        w_start = 1'b0;

        for (int i = 0; i < golden_seq.size(); i++) begin
            golden_eop = golden_seq[i];
            assert (w_eop.w_addr == golden_seq[i].w_addr &&
                    w_eop.w_iter == golden_seq[i].w_iter &&
                    w_eop.w_cycles_left == golden_seq[i].w_cycles_left &&
                    w_eop.w_spi_din == golden_seq[i].w_spi_din &&
                    w_vout == w_eop.w_spi_din[DC_DAC_WIDTH-1:0])
            else $fatal(1, "At %0.3f ns: o = %p, golden_seq[%0d] = %p, vout = %0h", $realtime,
                        w_eop, i, golden_seq[i], w_vout);
            @(negedge w_clk);
        end

    endtask

    initial begin
        w_clk = 1'b0;
        forever #5 w_clk = !w_clk;
    end

    int test;

    initial begin
        $fsdbDumpfile("run.fsdb");
        $fsdbDumpvars(0, dc_tb, "+all");
        $fsdbDumpoff();
        w_rst = 1'b1;
        w_start = 1'b0;
        for (int i = 0; i < DC_DEPTH; i++) begin
            insns[i] = 'h0;
        end
        for (int i = 0; i < DC_SEQ_REGS; i++) begin
            w_seq_regs[i] = 'h0;
        end
        dvsr_reg = 'h0;
        delay_reg = 'h0;
        cs_up_reg = 'h0;
        ldac_reg = 'h0;
        new_ctrl_reg = 32'h0;
        @(negedge w_clk);
        w_rst = 1'b0;

        init;
        $display($realtime, "init finished");

        test = 0;
        repeat (10) begin
            $display("test%0d", test);
            if (test == 7)
                $fsdbDumpon();
            rand_insns;
            test++;
        end
        $finish;
    end

endmodule
