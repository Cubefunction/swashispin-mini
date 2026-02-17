`timescale 1ns/1ps

module data_packer #(
    parameter int SAMPLE_W = 20,
    parameter int OUT_W    = 128
)(
    input  logic                 clk,
    input  logic                 rst,

    // from FIFO
    input  logic [SAMPLE_W-1:0]  fifo_data,
    input  logic                 fifo_valid,
    input  logic                 fifo_empty,
    output logic                 fifo_deq,

    // to downstream
    output logic [OUT_W-1:0]     o_data,
    output logic                 o_valid,
    input  logic                 o_ready
);


    // sample->32bit
    localparam int ELEM_W = 32;
    localparam int ELEMS  = OUT_W / ELEM_W;
    localparam int CNT_W  = (ELEMS <= 1) ? 1 : $clog2(ELEMS);

    logic [OUT_W-1:0] shift_reg;
    logic [CNT_W:0]   elem_cnt;

    logic hold_valid;

    assign o_data  = shift_reg;
    assign o_valid = hold_valid;

    // padding ->32bit
    logic [31:0] sample32;
    always_comb begin
        sample32 = '0;
        sample32[SAMPLE_W-1:0] = fifo_data;
    end

    always_comb begin
        fifo_deq = 1'b0;

        if (!rst) begin
            if (!hold_valid && !fifo_empty)
                fifo_deq = 1'b1;
        end
    end

    // -----------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            shift_reg  <= '0;
            elem_cnt   <= '0;
            hold_valid <= 1'b0;
        end
        else begin

            // 128bit word
            if (hold_valid && o_ready) begin
                hold_valid <= 1'b0;
                elem_cnt   <= '0;
                shift_reg  <= '0;
            end

            // sample
            if (!hold_valid && fifo_valid) begin

                shift_reg <= shift_reg | 
                             (sample32 << (elem_cnt * 32));

                if (elem_cnt == ELEMS-1) begin
                    hold_valid <= 1'b1;
                end
                else begin
                    elem_cnt <= elem_cnt + 1'b1;
                end
            end
        end
    end

endmodule