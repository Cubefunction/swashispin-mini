`timescale 1ns / 1ps

module uart_arbiter
   #(parameter DC_BYTES=124,
     parameter LAUNCH_BYTES=3,
     parameter NUM_DC_CHANNEL=24)
    (input  logic i_clk, i_rst,

     output logic o_deq_rxq,
     input  logic i_rxq_empty,
     input  logic [7:0] i_rxq_data,

     output logic [DC_BYTES/4-1:0][31:0] o_regs_bus,
     output logic [NUM_DC_CHANNEL:0] o_valid_bus)

    logic [7:0] r_channel;
    logic r_channel_clr, r_channel_en;

    always_ff @(posedge i_clk) begin
        if (i_rst || r_channel_clr)
            r_channel <= 8'hff;
        else if (r_channel_en)
            r_channel <= i_rxq_data;
    end

    // byte shifter
    logic [DC_BYTES-1:0][7:0] r_byte_shift;
    logic w_bytes_clr, w_byte_shift_en;

    assign o_regs_bus = r_byte_shift;

    always_ff @(posedge i_clk) begin
        if (i_rst || w_bytes_clr)
            r_bytes <= 'h0;
        else if (w_bytes_en)
            r_bytes <= {r_bytes[DC_BYTES-2:0], i_rxq_data};
    end

    // byte counter
    logic [$clog2(DC_BYTES)-1:0] r_byte_cnt;
    logic w_byte_cnt_clr, w_byte_cnt_en;

    always_ff @(posedge i_clk) begin
        if (i_rst || w_byte_cnt_clr)
            r_byte_cnt <= 'd0;
        else if (w_byte_cnt_en)
            r_byte_cnt <= r_byte_cnt + 'd1;
    end

    // fsm
    enum {IDLE, DC, LAUNCH} r_state, w_next_state;

    always_ff @(posedge i_clk)
        r_state <= i_rst ? IDLE : w_next_state;

    always_comb begin

        w_channel_clr = 1'b0;
        w_channel_en = 1'b0;
        w_byte_shift_clr = 1'b0;
        w_byte_shift_en = 1'b0;
        w_byte_cnt_clr = 1'b0;
        w_byte_cnt_en = 1'b0;

        o_deq_rxq = 1'b0;
        o_valid_bus = 'h0;

        w_next_state = r_state;

        case (r_state)
            IDLE: begin
                if (!i_rxq_empty) begin
                    w_next_state = i_rxq_data ? LAUNCH : DC;
                    o_deq_rxq = 1'b1;
                end
            end
            PAYLOAD: begin
            end
        endcase

    end

endmodule
