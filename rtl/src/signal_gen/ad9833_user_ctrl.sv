`timescale 1ns/1ps

module ad9833_user_ctrl (
    input  logic        clk,
    input  logic        rst_n,

    // From uart_regs / top-level register decode
    input  logic [31:0] reg_cmd,         // spi_word0
    input  logic [31:0] reg_freq,        // {spi_word2, spi_word1}
    input  logic [31:0] reg_phase_ctrl,  // {spi_word4, spi_word3}
    input  logic [31:0] reg_control,     // bit0 = start

    // To ad9833_spi_master
    output logic        spi_start,
    output logic [15:0] spi_frame_data,
    input  logic        spi_done,
    input  logic        spi_busy,

    // Status outputs
    output logic        busy,
    output logic        done_pulse,
    output logic [31:0] status_word
);

    typedef enum logic [1:0] {
        S_IDLE      = 2'd0,
        S_LAUNCH    = 2'd1,
        S_WAIT_DONE = 2'd2,
        S_DONE      = 2'd3
    } state_t;

    state_t r_state, w_state_n;

    logic        w_start_req;
    logic        r_start_req_d;
    logic        w_start_pulse;

    logic [2:0]  r_word_idx, w_word_idx_n;

    logic [15:0] r_word_buf [0:4];
    logic [15:0] w_cur_word;

    logic        w_busy_n;
    logic        w_done_pulse_n;

    integer i;

    // ------------------------------------------------------------
    // start edge detect
    // reg_control[0] = start
    // ------------------------------------------------------------
    assign w_start_req   = reg_control[0];
    assign w_start_pulse = w_start_req & ~r_start_req_d;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            r_start_req_d <= 1'b0;
        else
            r_start_req_d <= w_start_req;
    end

    // ------------------------------------------------------------
    // current word select
    // ------------------------------------------------------------
    always_comb begin
        unique case (r_word_idx)
            3'd0:    w_cur_word = r_word_buf[0];
            3'd1:    w_cur_word = r_word_buf[1];
            3'd2:    w_cur_word = r_word_buf[2];
            3'd3:    w_cur_word = r_word_buf[3];
            3'd4:    w_cur_word = r_word_buf[4];
            default: w_cur_word = 16'h0000;
        endcase
    end

    // ------------------------------------------------------------
    // next-state logic
    // ------------------------------------------------------------
    always_comb begin
        w_state_n      = r_state;
        w_word_idx_n   = r_word_idx;

        spi_start      = 1'b0;
        spi_frame_data = w_cur_word;

        w_busy_n       = busy;
        w_done_pulse_n = 1'b0;  // default: one-cycle pulse

        unique case (r_state)

            S_IDLE: begin
                w_busy_n = 1'b0;

                if (w_start_pulse) begin
                    w_state_n    = S_LAUNCH;
                    w_word_idx_n = 3'd0;
                    w_busy_n     = 1'b1;
                end
            end

            S_LAUNCH: begin
                // one-cycle pulse to SPI master
                spi_start  = 1'b1;
                w_busy_n   = 1'b1;
                w_state_n  = S_WAIT_DONE;
            end

            S_WAIT_DONE: begin
                w_busy_n = 1'b1;

                if (spi_done) begin
                    if (r_word_idx == 3'd4) begin
                        w_state_n = S_DONE;
                    end
                    else begin
                        w_word_idx_n = r_word_idx + 3'd1;
                        w_state_n    = S_LAUNCH;
                    end
                end
            end

            S_DONE: begin
                w_busy_n       = 1'b0;
                w_done_pulse_n = 1'b1;
                w_state_n      = S_IDLE;
            end

            default: begin
                w_state_n      = S_IDLE;
                w_word_idx_n   = 3'd0;
                w_busy_n       = 1'b0;
                w_done_pulse_n = 1'b0;
            end
        endcase
    end

    // ------------------------------------------------------------
    // sequential logic
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_state     <= S_IDLE;
            r_word_idx  <= 3'd0;
            busy        <= 1'b0;
            done_pulse  <= 1'b0;

            for (i = 0; i < 5; i++) begin
                r_word_buf[i] <= 16'h0000;
            end
        end
        else begin
            r_state    <= w_state_n;
            r_word_idx <= w_word_idx_n;
            busy       <= w_busy_n;
            done_pulse <= w_done_pulse_n;

            // latch all 5 SPI words only once at start
            if (w_start_pulse && (r_state == S_IDLE)) begin
                r_word_buf[0] <= reg_cmd[15:0];          // spi_word0
                r_word_buf[1] <= reg_freq[15:0];         // spi_word1
                r_word_buf[2] <= reg_freq[31:16];        // spi_word2
                r_word_buf[3] <= reg_phase_ctrl[15:0];   // spi_word3
                r_word_buf[4] <= reg_phase_ctrl[31:16];  // spi_word4
            end
        end
    end

    // ------------------------------------------------------------
    // packed debug/status word
    // ------------------------------------------------------------
    always_comb begin
        status_word         = 32'h0000_0000;
        status_word[0]      = busy;
        status_word[1]      = done_pulse;
        status_word[2]      = (r_state == S_IDLE);
        status_word[3]      = spi_busy;
        status_word[6:4]    = r_word_idx;
        status_word[10:8]   = r_state;
        status_word[31:24]  = 8'hA5;
    end

endmodule