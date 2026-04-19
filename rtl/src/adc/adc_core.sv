`timescale 1ns/1ps

module adc_core #(
    parameter int NUM_REGS      = 54,
    parameter int CTRL_REG_IDX  = 53,
    parameter int ADDR_WIDTH    = $clog2(NUM_REGS)
)(
    input  logic i_clk,
    input  logic i_rst,
    input  logic [0:NUM_REGS-1][31:0] i_all_regs,
    input  logic i_adc_spi_finish,

    output logic o_adc_sampling,
    output logic o_active
);

    //==================================================
    // opcode
    //==================================================
    localparam logic [3:0] OP_NOP = 4'b0000;
    localparam logic [3:0] OP_SAM = 4'b0001;
    localparam logic [3:0] OP_JMP = 4'b0010;
    localparam logic [3:0] OP_END = 4'b1111;

    //==================================================
    // start control
    //==================================================
    logic start_en;
    logic start_en_d;
    logic start_pulse;
    logic run_latched;

    assign start_en    = (i_all_regs[CTRL_REG_IDX] == 32'h8000_0000);
    assign start_pulse = start_en & ~start_en_d;

    //==================================================
    // adc_spi_finish rising edge detect
    //==================================================
    logic adc_spi_finish_d;
    logic adc_spi_finish_rise;

    assign adc_spi_finish_rise = i_adc_spi_finish & ~adc_spi_finish_d;

    //==================================================
    // IF stage regs
    //==================================================
    logic [ADDR_WIDTH-1:0] if_pc;
    logic [31:0]           if_insn;
    logic                  if_valid;

    //==================================================
    // ID stage regs
    //==================================================
    logic [ADDR_WIDTH-1:0] id_pc;
    logic [3:0]            id_opcode;
    logic [11:0]           id_sample_count;
    logic [ADDR_WIDTH-1:0] id_target;
    logic [15:0]           id_delay_cycles;
    logic                  id_valid;

    //==================================================
    // EX stage regs
    //==================================================
    logic [ADDR_WIDTH-1:0] ex_pc;
    logic [3:0]            ex_opcode;
    logic [11:0]           ex_sample_count;
    logic [ADDR_WIDTH-1:0] ex_target;
    logic [15:0]           ex_delay_cycles;
    logic                  ex_valid;

    //==================================================
    // EX execution context
    //==================================================
    logic [15:0]           ex_timer;
    logic [11:0]           ex_samples_left;
    logic                  ex_busy;

    //==================================================
    // decode wires from IF
    //==================================================
    logic [3:0]            d_opcode;
    logic [11:0]           d_sample_count;
    logic [ADDR_WIDTH-1:0] d_target;
    logic [15:0]           d_delay_cycles;

    assign d_opcode       = if_insn[31:28];
    assign d_sample_count = if_insn[27:16];
    assign d_target       = if_insn[ADDR_WIDTH-1:0];
    assign d_delay_cycles = if_insn[15:0];

    //==================================================
    // pipeline control
    //==================================================
    logic                  stall_pipe;
    logic                  ex_done;
    logic                  commit_fire;
    logic                  ex_load_new;
    logic [ADDR_WIDTH-1:0] commit_next_pc;

    assign stall_pipe  = ex_valid && ex_busy;
    assign commit_fire = ex_valid && ex_done;
    assign ex_load_new = (!stall_pipe) && id_valid && !commit_fire;

    //==================================================
    // execution done / next pc
    //==================================================
    always_comb begin
        ex_done        = 1'b0;
        commit_next_pc = ex_pc + ADDR_WIDTH'(1);

        unique case (ex_opcode)
            OP_NOP: begin
                if (ex_valid && ex_busy && (ex_timer == 16'd1))
                    ex_done = 1'b1;
            end

            OP_SAM: begin
                if (ex_valid && ex_busy && adc_spi_finish_rise && (ex_samples_left == 12'd1))
                    ex_done = 1'b1;
            end

            OP_JMP: begin
                if (ex_valid)
                    ex_done = 1'b1;
                commit_next_pc = ex_target;
            end

            OP_END: begin
                if (ex_valid)
                    ex_done = 1'b1;
                commit_next_pc = '0;
            end

            default: begin
                if (ex_valid)
                    ex_done = 1'b1;
                commit_next_pc = ex_pc + ADDR_WIDTH'(1);
            end
        endcase
    end

    //==================================================
    // sequential
    //==================================================
    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            start_en_d        <= 1'b0;
            run_latched       <= 1'b0;
            adc_spi_finish_d  <= 1'b0;

            if_pc             <= '0;
            if_insn           <= '0;
            if_valid          <= 1'b0;

            id_pc             <= '0;
            id_opcode         <= '0;
            id_sample_count   <= '0;
            id_target         <= '0;
            id_delay_cycles   <= '0;
            id_valid          <= 1'b0;

            ex_pc             <= '0;
            ex_opcode         <= '0;
            ex_sample_count   <= '0;
            ex_target         <= '0;
            ex_delay_cycles   <= '0;
            ex_valid          <= 1'b0;

            ex_timer          <= '0;
            ex_samples_left   <= '0;
            ex_busy           <= 1'b0;

            o_adc_sampling    <= 1'b0;
            o_active          <= 1'b0;
        end
        else begin
            start_en_d       <= start_en;
            adc_spi_finish_d <= i_adc_spi_finish;

            // one-shot run latch
            if (start_pulse)
                run_latched <= 1'b1;
            else if (commit_fire && (ex_opcode == OP_END))
                run_latched <= 1'b0;

            //==================================================
            // idle / stopped
            //==================================================
            if (!run_latched) begin
                if (start_pulse) begin
                    // arm pipeline only once on start pulse
                    if_pc           <= '0;
                    if_insn         <= i_all_regs['0];
                    if_valid        <= 1'b1;

                    id_pc           <= '0;
                    id_opcode       <= '0;
                    id_sample_count <= '0;
                    id_target       <= '0;
                    id_delay_cycles <= '0;
                    id_valid        <= 1'b0;

                    ex_pc           <= '0;
                    ex_opcode       <= '0;
                    ex_sample_count <= '0;
                    ex_target       <= '0;
                    ex_delay_cycles <= '0;
                    ex_valid        <= 1'b0;

                    ex_timer        <= '0;
                    ex_samples_left <= '0;
                    ex_busy         <= 1'b0;

                    o_adc_sampling  <= 1'b0;
                    o_active        <= 1'b1;
                end
                else begin
                    if_pc           <= '0;
                    if_insn         <= '0;
                    if_valid        <= 1'b0;

                    id_pc           <= '0;
                    id_opcode       <= '0;
                    id_sample_count <= '0;
                    id_target       <= '0;
                    id_delay_cycles <= '0;
                    id_valid        <= 1'b0;

                    ex_pc           <= '0;
                    ex_opcode       <= '0;
                    ex_sample_count <= '0;
                    ex_target       <= '0;
                    ex_delay_cycles <= '0;
                    ex_valid        <= 1'b0;

                    ex_timer        <= '0;
                    ex_samples_left <= '0;
                    ex_busy         <= 1'b0;

                    o_adc_sampling  <= 1'b0;
                    o_active        <= 1'b0;
                end
            end
            else begin
                o_active <= 1'b1;

                //==================================================
                // EX running state update
                //==================================================
                if (ex_valid && ex_busy) begin
                    unique case (ex_opcode)
                        OP_NOP: begin
                            if (ex_timer > 16'd0)
                                ex_timer <= ex_timer - 16'd1;
                        end

                        OP_SAM: begin
                            if (adc_spi_finish_rise && (ex_samples_left > 12'd0))
                                ex_samples_left <= ex_samples_left - 12'd1;
                        end

                        default: begin
                        end
                    endcase
                end

                //==================================================
                // EX bookkeeping
                //==================================================
                if (commit_fire) begin
                    ex_busy         <= 1'b0;
                    ex_timer        <= '0;
                    ex_samples_left <= '0;
                end
                else if (ex_load_new) begin
                    unique case (id_opcode)
                        OP_NOP: begin
                            ex_timer        <= id_delay_cycles;
                            ex_samples_left <= '0;
                            ex_busy         <= (id_delay_cycles != 16'd0);
                        end

                        OP_SAM: begin
                            ex_timer        <= '0;
                            ex_samples_left <= id_sample_count;
                            ex_busy         <= (id_sample_count != 12'd0);
                        end

                        default: begin
                            ex_timer        <= '0;
                            ex_samples_left <= '0;
                            ex_busy         <= 1'b0;
                        end
                    endcase
                end

                //==================================================
                // outputs
                //==================================================
                if (ex_valid && (ex_opcode == OP_SAM) && ex_busy)
                    o_adc_sampling <= 1'b1;
                else
                    o_adc_sampling <= 1'b0;

                if (commit_fire && (ex_opcode == OP_END))
                    o_active <= 1'b0;

                //==================================================
                // pipeline movement
                //==================================================
                if (commit_fire) begin
                    if (ex_opcode == OP_END) begin
                        if_pc    <= '0;
                        if_insn  <= '0;
                        if_valid <= 1'b0;
                    end
                    else begin
                        if_pc    <= commit_next_pc;
                        if_insn  <= i_all_regs[commit_next_pc];
                        if_valid <= 1'b1;
                    end

                    // flush younger stages
                    id_pc           <= '0;
                    id_opcode       <= '0;
                    id_sample_count <= '0;
                    id_target       <= '0;
                    id_delay_cycles <= '0;
                    id_valid        <= 1'b0;

                    ex_pc           <= '0;
                    ex_opcode       <= '0;
                    ex_sample_count <= '0;
                    ex_target       <= '0;
                    ex_delay_cycles <= '0;
                    ex_valid        <= 1'b0;
                end
                else if (!stall_pipe) begin
                    // IF sequential fetch
                    if_insn  <= i_all_regs[if_pc];
                    if_valid <= 1'b1;
                    if_pc    <= if_pc + ADDR_WIDTH'(1);

                    // ID
                    id_pc           <= if_pc;
                    id_opcode       <= d_opcode;
                    id_sample_count <= d_sample_count;
                    id_target       <= d_target;
                    id_delay_cycles <= d_delay_cycles;
                    id_valid        <= if_valid;

                    // EX
                    ex_pc           <= id_pc;
                    ex_opcode       <= id_opcode;
                    ex_sample_count <= id_sample_count;
                    ex_target       <= id_target;
                    ex_delay_cycles <= id_delay_cycles;
                    ex_valid        <= id_valid;
                end
                else begin
                    // hold all pipeline regs
                    if_pc           <= if_pc;
                    if_insn         <= if_insn;
                    if_valid        <= if_valid;

                    id_pc           <= id_pc;
                    id_opcode       <= id_opcode;
                    id_sample_count <= id_sample_count;
                    id_target       <= id_target;
                    id_delay_cycles <= id_delay_cycles;
                    id_valid        <= id_valid;

                    ex_pc           <= ex_pc;
                    ex_opcode       <= ex_opcode;
                    ex_sample_count <= ex_sample_count;
                    ex_target       <= ex_target;
                    ex_delay_cycles <= ex_delay_cycles;
                    ex_valid        <= ex_valid;
                end
            end
        end
    end

endmodule