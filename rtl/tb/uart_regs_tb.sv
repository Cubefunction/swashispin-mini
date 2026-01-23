`timescale 1ns/1ps

module uart_regs_tb;

    localparam N_REGS = 54;
    localparam NUM_ITERS = 50000;

    localparam BAUDRATE = 921600;
    localparam realtime bit_duration = (1.0e9 / BAUDRATE); // ~1085.069 ns

    logic w_clk;
    logic w_rst = 1'b1;

    logic w_rx  = 1'b1;
    logic w_tx;

    logic [0:N_REGS-1][31:0] w_regs;

    byte unsigned pc_received[$];
    logic [7:0] rx_data;
    integer pc_tsmt_which_bit;

    logic [0:N_REGS-1][31:0] r_exp_regs;

    bit r_do_read;
    logic [6:0] r_idx;
    logic [31:0] r_data;
    logic [31:0] r_exp;
    int unsigned r_j;

    uart_regs #(
        .DATA_WIDTH(8),
        .RX_FIFO_DEPTH(8),
        .RX_FIFO_AF_DEPTH(6),
        .RX_FIFO_AE_DEPTH(2),
        .TX_FIFO_DEPTH(8),
        .TX_FIFO_AF_DEPTH(6),
        .TX_FIFO_AE_DEPTH(2),
        .NUM_REGS(N_REGS)
    ) DUT (
        .i_clk(w_clk),
        .i_rst(w_rst),
        .i_rx(w_rx),
        .o_tx(w_tx),
        .o_regs(w_regs)
    );

    initial begin
        w_clk = 1'b0;
        forever #5 w_clk = !w_clk;
    end

    initial begin
        repeat (20) @(negedge w_clk);
        w_rst <= 1'b0;
    end

    // pc->fpga
    task pc_tsmt (input logic [7:0] data);

        $display("At %0.3f ns: pc sends 0x%2h", $realtime, data);

        // start bit = 0
        @(negedge w_clk);
        w_rx = 1'b0;
        pc_tsmt_which_bit = -1;
        #bit_duration;

        // data bits
        for (int i = 0; i < 8; i++) begin
            @(negedge w_clk);
            w_rx = data[i];
            pc_tsmt_which_bit = i;
            #bit_duration;
        end

        // end bit = 1
        @(negedge w_clk);
        w_rx = 1'b1;
        pc_tsmt_which_bit = 8;
        #bit_duration;

    endtask

    // fpga->pc
    task pc_recv;

        // start bit == 0
        @(negedge w_tx);

        $display("At %0.3f ns: pc starts receiving", $realtime);

        #(bit_duration / 2.0);
        assert (w_tx == 1'b0)
        else $fatal(1, "At %0.3f ns: o_tx didn't hold start bit as 0", $realtime);

        // data bits
        for (int i = 0; i < 8; i++) begin
            #bit_duration;
            rx_data[i] = w_tx;
        end

        // stop bit == 1
        #bit_duration;
        assert (w_tx == 1'b1)
        else $fatal(1, "At %0.3f ns: o_tx didn't hold stop bit as 1", $realtime);

        $display("At %0.3f ns: pc received 0x%2h", $realtime, rx_data);

        pc_received.push_back(rx_data);

    endtask

    task automatic pc_tsmt_gap(input int max_bits_idle = 3);
        int idle_bits;
        idle_bits = $urandom_range(0, max_bits_idle);
        if (idle_bits > 0) #(bit_duration * idle_bits);
    endtask

    task automatic send_write(input logic [6:0] idx, input logic [31:0] data);

        $display("write regs[%0d] = %4h", idx, data);

        pc_tsmt({1'b0, idx});
        pc_tsmt_gap();

        pc_tsmt(data[31:24]);
        pc_tsmt_gap();

        pc_tsmt(data[23:16]);
        pc_tsmt_gap();

        pc_tsmt(data[15:8]);
        pc_tsmt_gap();

        pc_tsmt(data[7:0]);
        pc_tsmt_gap();

    endtask

    event e_recv_done;

    task automatic send_read_and_recv4(input logic [6:0] idx);

        $display("read regs[%0d]", idx);

        pc_received.delete();

        // Start receiver BEFORE sending the header so we never miss the first start bit.
        fork

            begin : recv_thread
                for (int i = 0; i < 4; i++) begin
                    pc_recv();
                end
                ->e_recv_done;
            end

            begin : send_thread
                pc_tsmt({1'b1, idx});
                @e_recv_done;
            end

            begin : timeout_thread
                // Conservative timeout: header TX time + response time + slack
                #(bit_duration * 10.0 * 6.0);
                $fatal(1, "Timeout waiting for read response (idx=%0d) at %0.3f ns", idx, $realtime);
            end

        join_any

        disable fork;

        if (pc_received.size() != 4) begin
            $fatal(1, "Expected 4 received bytes, got %0d (idx=%0d) at %0.3f ns",
                pc_received.size(), idx, $realtime);
        end

    endtask

    int unsigned c;
    task automatic wait_reg_eq(
        input logic [6:0] idx,
        input logic [31:0] exp,
        input int unsigned max_cycles = 50000
    );
        $display("wait regs[%0d]", idx);
        c = 0;
        while (w_regs[idx] !== exp) begin
            @(posedge w_clk);
            c++;
            if (c >= max_cycles) begin
                $fatal(1, "Timeout waiting for reg[%0d]==0x%08x (got 0x%08x) at %0.3f ns",
                       idx, exp, w_regs[idx], $realtime);
            end
        end
    endtask

    task automatic check_all_regs(input logic [0:N_REGS-1][31:0] exp_regs);
        for (int i = 0; i < N_REGS; i++) begin
            if (w_regs[i] !== exp_regs[i]) begin
                $fatal(1, "REG MISMATCH i=%0d exp=0x%08x got=0x%08x at %0.3f ns",
                       i, exp_regs[i], w_regs[i], $realtime);
            end
        end
    endtask

    initial begin : main

        // init expected model
        for (int i = 0; i < N_REGS; i++) r_exp_regs[i] = 32'hDEADC0DE;

        // wait reset deassert
        @(negedge w_rst);
        repeat (50) @(posedge w_clk);

        // quick sanity: regs should be 0 after reset
        check_all_regs(r_exp_regs);

        for (int iter = 0; iter < NUM_ITERS; iter++) begin
            r_do_read = ($urandom_range(0, 1) == 1);
            r_idx = $urandom_range(0, N_REGS-1);
            r_data = $urandom();

            if (!r_do_read) begin

                // WRITE
                send_write(r_idx, r_data);

                // Update expected model
                r_exp_regs[r_idx] = r_data;

                // Wait until DUT reflects it
                wait_reg_eq(r_idx, r_data);

                // Spot check a few other random registers too
                for (int k = 0; k < 3; k++) begin
                    r_j = $urandom_range(0, N_REGS-1);
                    if (w_regs[r_j] !== r_exp_regs[r_j]) begin
                      $fatal(1, "Post-write spot-check mismatch iter=%0d j=%0d exp=0x%08x got=0x%08x at %0.3f ns",
                             iter, r_j, r_exp_regs[r_j], w_regs[r_j], $realtime);
                    end
                end

            end 
            else begin

                // READ
                send_read_and_recv4(r_idx);

                r_exp = r_exp_regs[r_idx];

                // Compare received bytes with expected little-endian order
                if (pc_received[3] !== r_exp[7:0]   ||
                    pc_received[2] !== r_exp[15:8]  ||
                    pc_received[1] !== r_exp[23:16] ||
                    pc_received[0] !== r_exp[31:24]) begin
                    $fatal(1, "Read mismatch iter=%0d idx=%0d exp=0x%08x got_bytes=%02x %02x %02x %02x at %0.3f ns",
                           iter, r_idx, r_exp,
                           pc_received[0], pc_received[1], pc_received[2], pc_received[3],
                           $realtime);
                end

                // Ensure DUT regs still match expected (no side effects)
                if (w_regs[r_idx] !== r_exp_regs[r_idx]) begin
                    $fatal(1, "Reg changed unexpectedly after read iter=%0d idx=%0d exp=0x%08x got=0x%08x at %0.3f ns",
                           iter, r_idx, r_exp_regs[r_idx], w_regs[r_idx], $realtime);
                end
            end

            // Random inter-transaction idle time
            #(bit_duration * $urandom_range(0, 20));

          end

          // Final full check
          check_all_regs(r_exp_regs);

          $display("dc_shared_regs_tb: PASS (%0d randomized iterations @ %0d baud)", NUM_ITERS, BAUDRATE);
          $finish;

      end

endmodule
