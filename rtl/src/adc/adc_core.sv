`timescale 1ns/1ps

module adc_core #(
    parameter int NUM_REGS      = 54,
    parameter int CTRL_REG_IDX  = 53,
    parameter int ADDR_WIDTH    = $clog2(NUM_REGS),
    parameter int BASE_ADDR     = 0
)(
    input  logic i_clk,
    input  logic i_rst,
    input  logic [0:NUM_REGS-1][31:0] i_all_regs,

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
    // control
    //==================================================
    logic start_en;
    assign start_en = i_all_regs[CTRL_REG_IDX] == 32'h8000_0000;

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
    logic [11:0]           id_loop_max;
    logic [ADDR_WIDTH-1:0] id_target;
    logic [15:0]           id_delay_cycles;
    logic                  id_valid;

    //==================================================
    // EX stage regs
    //==================================================
    logic [ADDR_WIDTH-1:0] ex_pc;
    logic [3:0]            ex_opcode;
    logic [11:0]           ex_loop_max;
    logic [ADDR_WIDTH-1:0] ex_target;
    logic [15:0]           ex_delay_cycles;
    logic [15:0]           ex_timer;
    logic                  ex_busy;
    logic                  ex_valid;

    //==================================================
    // loop counter
    //==================================================
    logic [11:0] loop_cnt;

    //==================================================
    // decode wires
    //==================================================
    logic [3:0]            d_opcode;
    logic [11:0]           d_loop_max;
    logic [ADDR_WIDTH-1:0] d_target;
    logic [15:0]           d_delay_cycles;

    assign d_opcode       = if_insn[31:28];
    assign d_loop_max     = if_insn[27:16];
    assign d_target       = if_insn[ADDR_WIDTH-1:0];
    assign d_delay_cycles = if_insn[15:0];

    //==================================================
    // helper flags
    //==================================================
    logic ex_is_timed_op;
    logic stall_pipe;
    logic exec_done;

    assign ex_is_timed_op = ex_valid &&
                            ((ex_opcode == OP_NOP) || (ex_opcode == OP_SAM));

    assign stall_pipe = ex_is_timed_op && ex_busy;

    assign exec_done = ex_valid &&
                       (
                           (((ex_opcode == OP_NOP) || (ex_opcode == OP_SAM)) && !ex_busy) ||
                           (ex_opcode == OP_JMP) ||
                           (ex_opcode == OP_END)
                       );

    //==================================================
    // next pc decision
    //==================================================
    logic [ADDR_WIDTH-1:0] next_pc;
    logic                  next_pc_valid;

    always_comb begin
        next_pc       = if_pc;
        next_pc_valid = 1'b0;

        if (exec_done) begin
            unique case (ex_opcode)
                OP_NOP,
                OP_SAM: begin
                    next_pc       = ex_pc + 1'b1;
                    next_pc_valid = 1'b1;
                end

                OP_JMP: begin
                    if (loop_cnt < ex_loop_max)
                        next_pc = ex_target;
                    else
                        next_pc = ex_pc + 1'b1;

                    next_pc_valid = 1'b1;
                end

                OP_END: begin
                    next_pc       = '0;
                    next_pc_valid = 1'b1;
                end

                default: begin
                    next_pc       = ex_pc + 1'b1;
                    next_pc_valid = 1'b1;
                end
            endcase
        end
    end

    //==================================================
    // sequential logic
    //==================================================
    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            if_pc           <= '0;
            if_insn         <= '0;
            if_valid        <= 1'b0;

            id_pc           <= '0;
            id_opcode       <= '0;
            id_loop_max     <= '0;
            id_target       <= '0;
            id_delay_cycles <= '0;
            id_valid        <= 1'b0;

            ex_pc           <= '0;
            ex_opcode       <= '0;
            ex_loop_max     <= '0;
            ex_target       <= '0;
            ex_delay_cycles <= '0;
            ex_timer        <= '0;
            ex_busy         <= 1'b0;
            ex_valid        <= 1'b0;

            loop_cnt        <= '0;
            o_adc_sampling  <= 1'b0;
            o_active        <= 1'b0;
        end
        else if (!start_en) begin
            if_pc           <= '0;
            if_insn         <= '0;
            if_valid        <= 1'b0;

            id_pc           <= '0;
            id_opcode       <= '0;
            id_loop_max     <= '0;
            id_target       <= '0;
            id_delay_cycles <= '0;
            id_valid        <= 1'b0;

            ex_pc           <= '0;
            ex_opcode       <= '0;
            ex_loop_max     <= '0;
            ex_target       <= '0;
            ex_delay_cycles <= '0;
            ex_timer        <= '0;
            ex_busy         <= 1'b0;
            ex_valid        <= 1'b0;

            loop_cnt        <= '0;
            o_adc_sampling  <= 1'b0;
            o_active        <= 1'b0;
        end
        else begin
            o_active <= 1'b1;

            if (stall_pipe) begin
                if (ex_timer > 16'd1) begin
                    ex_timer <= ex_timer - 16'd1;
                end
                else begin
                    ex_timer <= '0;
                    ex_busy  <= 1'b0;

                    if (ex_opcode == OP_SAM)
                        o_adc_sampling <= 1'b0;
                end
            end
            else begin
                // execute
                if (ex_valid) begin
                    unique case (ex_opcode)
                        OP_NOP: begin
                            if (!ex_busy) begin
                                if (ex_delay_cycles > 16'd0) begin
                                    ex_timer <= ex_delay_cycles;
                                    ex_busy  <= 1'b1;
                                end
                                else begin
                                    ex_timer <= '0;
                                    ex_busy  <= 1'b0;
                                end
                            end
                        end

                        OP_SAM: begin
                            if (!ex_busy) begin
                                if (ex_delay_cycles > 16'd0) begin
                                    ex_timer     <= ex_delay_cycles;
                                    ex_busy      <= 1'b1;
                                    o_adc_sampling <= 1'b1;
                                end
                                else begin
                                    ex_timer       <= '0;
                                    ex_busy        <= 1'b0;
                                    o_adc_sampling <= 1'b0;
                                end
                            end
                        end

                        OP_JMP: begin
                            if (loop_cnt < ex_loop_max)
                                loop_cnt <= loop_cnt + 1'b1;
                            else
                                loop_cnt <= '0;
                        end

                        OP_END: begin
                            o_active       <= 1'b0;
                            o_adc_sampling <= 1'b0;
                        end

                        default: begin
                        end
                    endcase
                end

                // pipeline advance
                if (next_pc_valid) begin
                    if_pc   <= next_pc;
                    if_insn <= i_all_regs[next_pc];

                    if (ex_opcode == OP_END)
                        if_valid <= 1'b0;
                    else
                        if_valid <= 1'b1;
                end
                else begin
                    if_insn  <= i_all_regs[if_pc];
                    if_valid <= 1'b1;
                end

                id_pc           <= if_pc;
                id_opcode       <= d_opcode;
                id_loop_max     <= d_loop_max;
                id_target       <= d_target;
                id_delay_cycles <= d_delay_cycles;
                id_valid        <= if_valid;

                ex_pc           <= id_pc;
                ex_opcode       <= id_opcode;
                ex_loop_max     <= id_loop_max;
                ex_target       <= id_target;
                ex_delay_cycles <= id_delay_cycles;
                ex_valid        <= id_valid;

                ex_busy         <= 1'b0;
                ex_timer        <= '0;
            end
        end
    end

endmodule