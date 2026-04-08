`timescale 1ns/1ps

module async_fifo #(
    parameter int WIDTH    = 8,
    parameter int DEPTH    = 8,
    parameter int AF_DEPTH = 6,
    parameter int AE_DEPTH = 2
)(
    input  logic             rst_n,

    //==============================
    // Write side
    //==============================
    input  logic             w_clk,
    input  logic [WIDTH-1:0] w_data,
    input  logic             w_enq,
    output logic             w_full,
    output logic             w_almost_full,
    output logic [$clog2(DEPTH+1)-1:0] wr_data_count,

    //==============================
    // Read side
    //==============================
    input  logic             r_clk,
    input  logic             r_deq,
    output logic [WIDTH-1:0] r_data,
    output logic             r_empty,
    output logic             r_almost_empty,
    output logic             r_valid,
    output logic [$clog2(DEPTH+1)-1:0] rd_data_count
);

    localparam int ADDR_W = $clog2(DEPTH);
    localparam int PTR_W  = ADDR_W + 1;

    //============================================================
    // DEPTH check: async gray-pointer FIFO should use power-of-2
    //============================================================
    initial begin
        if ((1 << ADDR_W) != DEPTH) begin
            $error("async_fifo DEPTH must be a power of 2. DEPTH=%0d", DEPTH);
        end
    end

    //============================================================
    // Reset synchronizers
    //============================================================
    logic [1:0] w_rst_reg;
    logic [1:0] r_rst_reg;
    logic       w_rst_n_sync;
    logic       r_rst_n_sync;

    always_ff @(posedge w_clk or negedge rst_n) begin
        if (!rst_n)
            w_rst_reg <= 2'b00;
        else
            w_rst_reg <= {w_rst_reg[0], 1'b1};
    end

    always_ff @(posedge r_clk or negedge rst_n) begin
        if (!rst_n)
            r_rst_reg <= 2'b00;
        else
            r_rst_reg <= {r_rst_reg[0], 1'b1};
    end

    assign w_rst_n_sync = w_rst_reg[1];
    assign r_rst_n_sync = r_rst_reg[1];

    //============================================================
    // Memory
    //============================================================
    logic [WIDTH-1:0] mem [0:DEPTH-1];

    //============================================================
    // Helpers
    //============================================================
    function automatic logic [PTR_W-1:0] bin2gray(input logic [PTR_W-1:0] b);
        bin2gray = (b >> 1) ^ b;
    endfunction

    function automatic logic [PTR_W-1:0] gray2bin(input logic [PTR_W-1:0] g);
        logic [PTR_W-1:0] b;
        integer i;
        begin
            b[PTR_W-1] = g[PTR_W-1];
            for (i = PTR_W-2; i >= 0; i = i - 1)
                b[i] = b[i+1] ^ g[i];
            gray2bin = b;
        end
    endfunction

    //============================================================
    // Pointer / sync declarations
    //============================================================
    logic [PTR_W-1:0] w_bin,  w_bin_n;
    logic [PTR_W-1:0] w_gray, w_gray_n;

    logic [PTR_W-1:0] r_bin,  r_bin_n;
    logic [PTR_W-1:0] r_gray, r_gray_n;

    logic [PTR_W-1:0] r_gray_w1, r_gray_w2;
    logic [PTR_W-1:0] w_gray_r1, w_gray_r2;

    logic             push, pop;
    logic             w_full_reg,  w_full_next;
    logic             r_empty_reg, r_empty_next;

    logic [PTR_W-1:0] w_level, r_level;

    //============================================================
    // Write side
    //============================================================
    assign push   = w_enq && !w_full_reg;
    assign w_full = w_full_reg;

    always_comb begin
        w_bin_n  = w_bin + (push ? 1'b1 : 1'b0);
        w_gray_n = bin2gray(w_bin_n);

        // Full when next write pointer equals synchronized read pointer
        // with MSBs inverted
        w_full_next =
            (w_gray_n == {~r_gray_w2[PTR_W-1:PTR_W-2], r_gray_w2[PTR_W-3:0]});
    end

    always_ff @(posedge w_clk) begin
        if (!w_rst_n_sync) begin
            w_bin      <= '0;
            w_gray     <= '0;
            w_full_reg <= 1'b0;
        end
        else begin
            w_bin      <= w_bin_n;
            w_gray     <= w_gray_n;
            w_full_reg <= w_full_next;

            if (push)
                mem[w_bin[ADDR_W-1:0]] <= w_data;
        end
    end

    // Synchronize read pointer into write clock domain
    always_ff @(posedge w_clk) begin
        if (!w_rst_n_sync) begin
            r_gray_w1 <= '0;
            r_gray_w2 <= '0;
        end
        else begin
            r_gray_w1 <= r_gray;
            r_gray_w2 <= r_gray_w1;
        end
    end

    //============================================================
    // Read side
    //============================================================
    assign pop     = r_deq && !r_empty_reg;
    assign r_empty = r_empty_reg;

    always_comb begin
        r_bin_n  = r_bin + (pop ? 1'b1 : 1'b0);
        r_gray_n = bin2gray(r_bin_n);

        // Empty when next read pointer equals synchronized write pointer
        r_empty_next = (r_gray_n == w_gray_r2);
    end

    always_ff @(posedge r_clk) begin
        if (!r_rst_n_sync) begin
            r_bin       <= '0;
            r_gray      <= '0;
            r_empty_reg <= 1'b1;
        end
        else begin
            r_bin       <= r_bin_n;
            r_gray      <= r_gray_n;
            r_empty_reg <= r_empty_next;
        end
    end

    // Synchronize write pointer into read clock domain
    always_ff @(posedge r_clk) begin
        if (!r_rst_n_sync) begin
            w_gray_r1 <= '0;
            w_gray_r2 <= '0;
        end
        else begin
            w_gray_r1 <= w_gray;
            w_gray_r2 <= w_gray_r1;
        end
    end

    //============================================================
    // FWFT-style output
    //============================================================
    // Current head is always visible when not empty
    always_comb begin
        r_data  = mem[r_bin[ADDR_W-1:0]];
        r_valid = !r_empty_reg;
    end

    //============================================================
    // Counts / almost flags
    //============================================================
    always_comb begin
        w_level = w_bin - gray2bin(r_gray_w2);
        w_almost_full = (w_level >= AF_DEPTH);
    end

    always_comb begin
        r_level = gray2bin(w_gray_r2) - r_bin;
        r_almost_empty = (r_level <= AE_DEPTH);
    end

    assign wr_data_count = w_bin - gray2bin(r_gray_w2);
    assign rd_data_count = gray2bin(w_gray_r2) - r_bin;

endmodule