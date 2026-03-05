`timescale 1ns/1ps

module async_fifo #(
    parameter int WIDTH    = 8,
    parameter int DEPTH    = 8,   
    parameter int AF_DEPTH = 6,
    parameter int AE_DEPTH = 2
)(
    input  logic             rst_n, 

    // Write side 
    input  logic             w_clk,
    input  logic [WIDTH-1:0] w_data,
    input  logic             w_enq,
    output logic             w_full,
    output logic             w_almost_full,
    output logic [$clog2(DEPTH+1)-1:0] wr_data_count,
    

    // Read side 
    input  logic             r_clk,
    input  logic             r_deq,
    output logic [WIDTH-1:0] r_data,
    output logic             r_empty,
    output logic             r_almost_empty,
    output logic             r_valid    ,
    output logic [$clog2(DEPTH+1)-1:0] rd_data_count
);

    localparam int ADDR_W = $clog2(DEPTH);
    localparam int PTR_W  = ADDR_W + 1;

    logic w_rst_n_sync, r_rst_n_sync;
    logic [1:0] w_rst_reg, r_rst_reg;

    // sync w_rst
    always_ff @(posedge w_clk or negedge rst_n) begin
        if (!rst_n) w_rst_reg <= 2'b00;
        else        w_rst_reg <= {w_rst_reg[0], 1'b1};
    end
    assign w_rst_n_sync = w_rst_reg[1];

    // sync r_rst
    always_ff @(posedge r_clk or negedge rst_n) begin
        if (!rst_n) r_rst_reg <= 2'b00;
        else        r_rst_reg <= {r_rst_reg[0], 1'b1};
    end
    assign r_rst_n_sync = r_rst_reg[1];

    // Mem
    logic [WIDTH-1:0] mem [0:DEPTH-1];

    //  Gray/Bin Helpers
    function automatic logic [PTR_W-1:0] bin2gray(input logic [PTR_W-1:0] b);
        return (b >> 1) ^ b;
    endfunction

    function automatic logic [PTR_W-1:0] gray2bin(input logic [PTR_W-1:0] g);
        logic [PTR_W-1:0] b;
        b[PTR_W-1] = g[PTR_W-1];
        for (int i = PTR_W-2; i >= 0; i--) b[i] = b[i+1] ^ g[i];
        return b;
    endfunction

    //  Write Domain Logic 
    logic [PTR_W-1:0] w_bin, w_bin_n, w_gray, w_gray_n;
    logic [PTR_W-1:0] r_gray_w1, r_gray_w2;
    logic             w_full_reg, w_full_next;
    logic             push;

    assign push = w_enq && !w_full_reg;
    assign w_full = w_full_reg;

    always_comb begin
        w_bin_n  = w_bin + (push ? 1'b1 : 1'b0);
        w_gray_n = bin2gray(w_bin_n);
        w_full_next = (w_gray_n == {~r_gray_w2[PTR_W-1:PTR_W-2], r_gray_w2[PTR_W-3:0]});
    end

    always_ff @(posedge w_clk or negedge w_rst_n_sync) begin
        if (!w_rst_n_sync) begin
            w_bin      <= '0;
            w_gray     <= '0;
            w_full_reg <= 1'b0;
        end else begin
            w_bin      <= w_bin_n;
            w_gray     <= w_gray_n;
            w_full_reg <= w_full_next;
            if (push) mem[w_bin[ADDR_W-1:0]] <= w_data;
        end
    end

    //  Read Domain Logic 
    logic [PTR_W-1:0] r_bin, r_bin_n, r_gray, r_gray_n;
    logic [PTR_W-1:0] w_gray_r1, w_gray_r2;
    logic             r_empty_reg, r_empty_next;
    logic             pop;

    // w bin
    always_ff @(posedge w_clk or negedge w_rst_n_sync) begin
        if (!w_rst_n_sync) {r_gray_w2, r_gray_w1} <= '0;
        else               {r_gray_w2, r_gray_w1} <= {r_gray_w1, r_gray};
    end

    // Almost Full
    logic [PTR_W-1:0] w_level;
    always_comb begin
        w_level = w_bin - gray2bin(r_gray_w2);
        w_almost_full = (w_level >= AF_DEPTH);
    end



    assign pop = r_deq && !r_empty_reg;
    assign r_empty = r_empty_reg;

    always_comb begin
        r_bin_n  = r_bin + (pop ? 1'b1 : 1'b0);
        r_gray_n = bin2gray(r_bin_n);
        r_empty_next = (r_gray_n == w_gray_r2);
    end

    always_ff @(posedge r_clk or negedge r_rst_n_sync) begin
        if (!r_rst_n_sync) begin
            r_bin       <= '0;
            r_gray      <= '0;
            r_empty_reg <= 1'b1;
        end else begin
            r_bin       <= r_bin_n;
            r_gray       <= r_gray_n;
            r_empty_reg <= r_empty_next;
        end
    end

    // r bin
    always_ff @(posedge r_clk or negedge r_rst_n_sync) begin
        if (!r_rst_n_sync) {w_gray_r2, w_gray_r1} <= '0;
        else               {w_gray_r2, w_gray_r1} <= {w_gray_r1, w_gray};
    end

    // Sync-Read RAM 
    logic [ADDR_W-1:0] r_addr;
    logic              pop_q;

    always_ff @(posedge r_clk or negedge r_rst_n_sync) begin
        if (!r_rst_n_sync) begin
            r_addr  <= '0;
            r_data  <= '0;
            pop_q   <= 1'b0;
            r_valid <= 1'b0;
        end else begin
            if (pop) r_addr <= r_bin[ADDR_W-1:0];
            pop_q   <= pop;
            r_data  <= mem[r_addr];
            r_valid <= pop_q;
        end
    end

    // Almost Empty
    logic [PTR_W-1:0] r_level;
    always_comb begin
        r_level = gray2bin(w_gray_r2) - r_bin;
        r_almost_empty = (r_level <= AE_DEPTH);
    end


    assign wr_data_count = (w_bin - gray2bin(r_gray_w2));
    assign rd_data_count = (gray2bin(w_gray_r2) - r_bin);
endmodule