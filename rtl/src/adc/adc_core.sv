`timescale 1ns/1ps

//==============================================================================
// adc_core  (2-stage pipeline : FD + EX)
//------------------------------------------------------------------------------
// Opcodes (unchanged)
//   [31:28] opcode      : NOP=0000, SAM=0001, JMP=0010, END=1111
//   [27:16] count_field : sample count for SAM (also loop count for JMP)
//   [15:0]  delay       : NOP delay cycles
//   [ADDR_WIDTH-1:0] target : JMP destination address
//==============================================================================
module adc_core #(
    parameter int NUM_REGS     = 54,
    parameter int CTRL_REG_IDX = 53,
    parameter int ADDR_WIDTH   = $clog2(NUM_REGS)
)(
    input  logic                       i_clk,
    input  logic                       i_rst,
    input  logic [0:NUM_REGS-1][31:0]  i_all_regs,
    input  logic                       i_adc_spi_finish,

    output logic                       o_adc_sampling,
    output logic                       o_active
);

    //==========================================================================
    // Opcodes
    //==========================================================================
    localparam logic [3:0] OP_NOP = 4'b0000;
    localparam logic [3:0] OP_SAM = 4'b0001;
    localparam logic [3:0] OP_JMP = 4'b0010;
    localparam logic [3:0] OP_END = 4'b1111;

    //==========================================================================
    // Start control (rising edge on reg[CTRL_REG_IDX] == 8000_0000)
    //==========================================================================
    logic start_en;
    logic start_en_d;
    logic start_pulse;
    logic run_latched;

    assign start_en    = (i_all_regs[CTRL_REG_IDX] == 32'h8000_0000);
    assign start_pulse = start_en & ~start_en_d;

    //==========================================================================
    // i_adc_spi_finish rising-edge detector
    //==========================================================================
    logic adc_spi_finish_d;
    wire  adc_spi_finish_rise = i_adc_spi_finish & ~adc_spi_finish_d;

    //==========================================================================
    // Fetch pointer (address of the NEXT instruction to prefetch into FD)
    //==========================================================================
    logic [ADDR_WIDTH-1:0] fetch_pc;

    //==========================================================================
    // FD stage (1-deep pre-fetch buffer + combinational decode)
    //==========================================================================
    logic [ADDR_WIDTH-1:0] fd_pc;     // pc of the instruction held in fd_insn
    logic [31:0]           fd_insn;
    logic                  fd_valid;

    wire [3:0]             d_opcode       = fd_insn[31:28];
    wire [11:0]            d_count_field  = fd_insn[27:16];
    wire [ADDR_WIDTH-1:0]  d_target       = fd_insn[ADDR_WIDTH-1:0];
    wire [15:0]            d_delay_cycles = fd_insn[15:0];

    //==========================================================================
    // EX stage
    //==========================================================================
    logic [ADDR_WIDTH-1:0] ex_pc;
    logic [3:0]            ex_opcode;
    logic [11:0]           ex_count_field;
    logic [ADDR_WIDTH-1:0] ex_target;
    logic [15:0]           ex_delay_cycles;
    logic                  ex_valid;

    // execution context for multi-cycle ops
    logic [15:0]           ex_timer;
    logic [11:0]           ex_samples_left;
    logic                  ex_busy;

    //==========================================================================
    // Per-JMP loop state, keyed by the JMP's own pc
    //==========================================================================
    logic [11:0]           jmp_left_mem [0:NUM_REGS-1];
    logic                  jmp_init_mem [0:NUM_REGS-1];

    logic                  ex_jmp_init;
    logic [11:0]           ex_jmp_left;

    wire [11:0]            ex_jmp_left_effective =
        ex_jmp_init ? ex_jmp_left : ex_count_field;
    wire                   ex_jmp_take =
        (ex_valid && (ex_opcode == OP_JMP) && (ex_jmp_left_effective != 12'd0));

    //==========================================================================
    // commit control
    //==========================================================================
    logic                  ex_done;
    logic [ADDR_WIDTH-1:0] commit_next_pc;

    wire                   stall_pipe      = ex_valid && ex_busy;
    wire                   commit_fire     = ex_valid && ex_done;
    wire                   commit_redirect =
        commit_fire && ((ex_opcode == OP_JMP && ex_jmp_take) ||
                        (ex_opcode == OP_END));

    // FD -> EX transfer.  Fires on:

    wire                   ex_load_new =
        fd_valid && (!stall_pipe || commit_fire) && !commit_redirect;

    always_comb begin
        ex_done        = 1'b0;
        commit_next_pc = ex_pc + ADDR_WIDTH'(1);

        unique case (ex_opcode)
            OP_NOP: begin
                if (ex_valid && ex_busy && (ex_timer == 16'd1))
                    ex_done = 1'b1;
            end

            OP_SAM: begin
                if (ex_valid && ex_busy && adc_spi_finish_rise &&
                    (ex_samples_left == 12'd1))
                    ex_done = 1'b1;
            end

            OP_JMP: begin
                if (ex_valid)
                    ex_done = 1'b1;
                commit_next_pc = ex_jmp_take ? ex_target
                                             : (ex_pc + ADDR_WIDTH'(1));
            end

            OP_END: begin
                if (ex_valid)
                    ex_done = 1'b1;
                commit_next_pc = '0;
            end

            default: begin
                if (ex_valid)
                    ex_done = 1'b1;
            end
        endcase
    end

    //==========================================================================
    // Sequential
    //==========================================================================
    integer k;
    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            start_en_d       <= 1'b0;
            run_latched      <= 1'b0;
            adc_spi_finish_d <= 1'b0;

            fetch_pc         <= '0;
            fd_pc            <= '0;
            fd_insn          <= '0;
            fd_valid         <= 1'b0;

            ex_pc            <= '0;
            ex_opcode        <= '0;
            ex_count_field   <= '0;
            ex_target        <= '0;
            ex_delay_cycles  <= '0;
            ex_valid         <= 1'b0;
            ex_timer         <= '0;
            ex_samples_left  <= '0;
            ex_busy          <= 1'b0;
            ex_jmp_init      <= 1'b0;
            ex_jmp_left      <= '0;

            o_adc_sampling   <= 1'b0;
            o_active         <= 1'b0;

            for (k = 0; k < NUM_REGS; k++) begin
                jmp_left_mem[k] <= '0;
                jmp_init_mem[k] <= 1'b0;
            end
        end
        else begin
            start_en_d       <= start_en;
            adc_spi_finish_d <= i_adc_spi_finish;

            //------------------------------------------------------------------
            // Run latch: set on start_pulse, cleared on END commit
            //------------------------------------------------------------------
            if (start_pulse)
                run_latched <= 1'b1;
            else if (commit_fire && (ex_opcode == OP_END))
                run_latched <= 1'b0;

            //------------------------------------------------------------------
            // JMP loop memory bookkeeping
            //------------------------------------------------------------------
            if (start_pulse) begin
                for (k = 0; k < NUM_REGS; k++) begin
                    jmp_left_mem[k] <= '0;
                    jmp_init_mem[k] <= 1'b0;
                end
            end
            else if (commit_fire && (ex_opcode == OP_JMP)) begin
                jmp_init_mem[ex_pc] <= 1'b1;
                jmp_left_mem[ex_pc] <=
                    ex_jmp_take ? (ex_jmp_left_effective - 12'd1) : 12'd0;
            end

            //==================================================================
            // idle / stopped
            //==================================================================
            if (!run_latched) begin
                if (start_pulse) begin
                    // seed FD with the very first instruction and set
                    // fetch_pc one ahead.
                    fetch_pc        <= ADDR_WIDTH'(1);
                    fd_pc           <= '0;
                    fd_insn         <= i_all_regs['0];
                    fd_valid        <= 1'b1;

                    ex_valid        <= 1'b0;
                    ex_busy         <= 1'b0;
                    ex_timer        <= '0;
                    ex_samples_left <= '0;

                    o_adc_sampling  <= 1'b0;
                    o_active        <= 1'b1;
                end
                else begin
                    fetch_pc        <= '0;
                    fd_valid        <= 1'b0;
                    ex_valid        <= 1'b0;
                    ex_busy         <= 1'b0;
                    ex_timer        <= '0;
                    ex_samples_left <= '0;
                    o_adc_sampling  <= 1'b0;
                    o_active        <= 1'b0;
                end
            end
            //==================================================================
            // running
            //==================================================================
            else begin
                //--------------------------------------------------------------
                // EX execution context countdown (timer / samples_left)
                // Safe to run unconditionally; the commit / load paths below
                // will overwrite samples_left / ex_timer if commit_fire
                // fires on the same cycle.
                //--------------------------------------------------------------
                if (ex_valid && ex_busy) begin
                    unique case (ex_opcode)
                        OP_NOP: begin
                            if (ex_timer > 16'd0)
                                ex_timer <= ex_timer - 16'd1;
                        end
                        OP_SAM: begin
                            if (adc_spi_finish_rise &&
                                (ex_samples_left > 12'd0))
                                ex_samples_left <= ex_samples_left - 12'd1;
                        end
                        default: ;
                    endcase
                end

                //--------------------------------------------------------------
                // EX register-set : try to load FD -> EX first (this
                //--------------------------------------------------------------
                if (ex_load_new) begin
                    ex_pc           <= fd_pc;
                    ex_opcode       <= d_opcode;
                    ex_count_field  <= d_count_field;
                    ex_target       <= d_target;
                    ex_delay_cycles <= d_delay_cycles;
                    ex_valid        <= 1'b1;

                    // Snapshot the JMP-loop state for this pc.  After this,
                    // ex_jmp_left_effective uses the registered copy instead
                    // of indexing into jmp_*_mem[].
                    ex_jmp_init     <= jmp_init_mem[fd_pc];
                    ex_jmp_left     <= jmp_left_mem[fd_pc];

                    unique case (d_opcode)
                        OP_NOP: begin
                            ex_timer        <= d_delay_cycles;
                            ex_samples_left <= '0;
                            ex_busy         <= (d_delay_cycles != 16'd0);
                        end
                        OP_SAM: begin
                            ex_timer        <= '0;
                            ex_samples_left <= d_count_field;
                            ex_busy         <= (d_count_field != 12'd0);
                        end
                        default: begin
                            // JMP / END / unknown : single-cycle commit,
                            // no busy phase.
                            ex_timer        <= '0;
                            ex_samples_left <= '0;
                            ex_busy         <= 1'b0;
                        end
                    endcase
                end
                else if (commit_fire) begin
                    // Committed but nothing loaded this edge (redirect or
                    // FD not valid).  Empty EX so ex_done doesn't fire
                    // again next cycle.
                    ex_valid        <= 1'b0;
                    ex_busy         <= 1'b0;
                    ex_timer        <= '0;
                    ex_samples_left <= '0;
                end

                //--------------------------------------------------------------
                // FD buffer / fetch_pc management
                //   commit_redirect  : flush FD, re-seed from target (or
                //                      drop it on END).
                //   ex_load_new      : FD was consumed -> fetch next.
                //   !fd_valid        : FD empty (usually right after a
                //                      redirect) -> fetch.
                //--------------------------------------------------------------
                if (commit_redirect) begin
                    if (ex_opcode == OP_END) begin
                        fetch_pc <= '0;
                        fd_valid <= 1'b0;
                    end
                    else begin
                        fd_pc    <= commit_next_pc;
                        fd_insn  <= i_all_regs[commit_next_pc];
                        fd_valid <= 1'b1;
                        fetch_pc <= commit_next_pc + ADDR_WIDTH'(1);
                    end
                end
                else if (ex_load_new) begin
                    fd_pc    <= fetch_pc;
                    fd_insn  <= i_all_regs[fetch_pc];
                    fd_valid <= 1'b1;
                    fetch_pc <= fetch_pc + ADDR_WIDTH'(1);
                end
                else if (!fd_valid) begin
                    fd_pc    <= fetch_pc;
                    fd_insn  <= i_all_regs[fetch_pc];
                    fd_valid <= 1'b1;
                    fetch_pc <= fetch_pc + ADDR_WIDTH'(1);
                end
                // else: FD holds its value (EX is stalled on the current
                // instruction and FD is already full with the next one).

                //--------------------------------------------------------------
                // Outputs
                //--------------------------------------------------------------

                if (ex_load_new) begin
                    o_adc_sampling <=
                        (d_opcode == OP_SAM) && (d_count_field != 12'd0);
                end
                else if (commit_fire) begin
                    o_adc_sampling <= 1'b0;
                end

                if (commit_fire && (ex_opcode == OP_END))
                    o_active <= 1'b0;
                else
                    o_active <= 1'b1;
            end
        end
    end

endmodule