// `default_nettype none
`timescale 1ns / 1ps
`include "launch.svh"

module launch
   #(parameter NUM_DC_CHANNEL=24)
    (input  logic i_clk, i_rst,

     input  logic [0:LCH_TOTAL_REGS-1][31:0] i_regs,

     input  logic [NUM_DC_CHANNEL-1:0] i_dc_armed,

     input  logic i_trigger,

     output logic [NUM_DC_CHANNEL-1:0] o_dc_start);

    logic w_new_ctrl;

    edge_detector IWR (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_signal(i_regs[LCH_TOTAL_REGS-1][0]),
        .o_posedge(w_new_ctrl),
        .o_negedge()
    );

    logic [NUM_DC_CHANNEL-1:0] r_dc_active_mask;

    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            r_dc_active_mask <= 'h0;
        end
        else if (w_new_ctrl) begin
            r_dc_active_mask <= i_regs[0][NUM_DC_CHANNEL-1:0];
        end
    end

    logic [NUM_DC_CHANNEL-1:0] r_dc_armed;

    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            r_dc_armed <= 'h0;
        end
        else begin
            r_dc_armed <= i_dc_armed;
        end
    end

    logic w_dc_ready;
    assign w_dc_ready = ((r_dc_active_mask ^ r_dc_armed) == 'h0);

    enum {IDLE, LAUNCH} r_state, w_next_state;

    always_ff @(posedge i_clk) begin
        r_state <= i_rst ? IDLE : w_next_state;
    end

    logic w_all_ready;
    assign w_all_ready = (r_state == LAUNCH) && w_dc_ready && i_trigger;

    logic w_start;
    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            o_dc_start <= 'h0;
        end
        else if (w_start) begin
            o_dc_start <= r_dc_active_mask;
        end
        else begin
            o_dc_start <= 'h0;
        end
    end

    always_comb begin

        w_start = 1'b0;

        case (r_state)
            IDLE: begin
                w_next_state = w_new_ctrl ? LAUNCH : IDLE;
            end
            default: begin
                w_next_state = w_all_ready ? IDLE : LAUNCH;
                w_start = w_all_ready;
            end
        endcase

    end

endmodule
