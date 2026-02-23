`timescale 1ns/1ps

module async_fifo_tb;


  // Parameters
  localparam int WIDTH     = 20;
  localparam int DEPTH     = 8;
  localparam int AF_DEPTH  = 6;
  localparam int AE_DEPTH  = 2;
  localparam int NUM_WRITE = 800;


  // DUT interface signals
  logic             rst_n;

  logic             w_clk;
  logic [WIDTH-1:0] w_data;
  logic             w_enq;
  logic             w_full;
  logic             w_almost_full;
  logic [$clog2(DEPTH+1)-1:0] wr_data_count;

  logic             r_clk;
  logic             r_deq;
  logic [WIDTH-1:0] r_data;
  logic             r_empty;
  logic             r_almost_empty;
  logic             r_valid;
  logic [$clog2(DEPTH+1)-1:0] rd_data_count;
  // Instantiate DUT
  async_fifo #(
    .WIDTH(WIDTH),
    .DEPTH(DEPTH),
    .AF_DEPTH(AF_DEPTH),
    .AE_DEPTH(AE_DEPTH)
  ) dut (
    .rst_n(rst_n),
    .w_clk(w_clk),
    .w_data(w_data),
    .w_enq(w_enq),
    .w_full(w_full),
    .w_almost_full(w_almost_full),
    .r_clk(r_clk),
    .r_deq(r_deq),
    .r_data(r_data),
    .r_empty(r_empty),
    .r_almost_empty(r_almost_empty),
    .wr_data_count(wr_data_count),
    .rd_data_count(rd_data_count),
    .r_valid(r_valid)
  );

  // ----------------------------
  // Clocks
  //   w_clk = 100 MHz  => 10 ns period
  //   r_clk = 400 MHz  => 2.5 ns period
  // ----------------------------
  initial begin
    w_clk = 1'b0;
    forever #5 w_clk = ~w_clk;
  end

  initial begin
    r_clk = 1'b0;
    forever #1.25 r_clk = ~r_clk;
  end


  // FSDB dump for Verdi
  initial begin
    $fsdbDumpfile("async_fifo.fsdb");
    $fsdbDumpvars(0, async_fifo_tb);
    $fsdbDumpon;
  end


  // Reset 
  initial begin
    rst_n = 1'b0;
    #100;
    rst_n = 1'b1;
  end


  logic tb_w_ready, tb_r_ready;

  initial begin
    tb_w_ready = 1'b0;
    @(posedge rst_n);
    repeat (2) @(posedge w_clk);   // match DUT's w_rst_reg[1]
    tb_w_ready = 1'b1;
  end

  initial begin
    tb_r_ready = 1'b0;
    @(posedge rst_n);
    repeat (2) @(posedge r_clk);   // match DUT's r_rst_reg[1]
    tb_r_ready = 1'b1;
  end


  // Scoreboard 
  logic [WIDTH-1:0] exp_q[$];
  int unsigned write_cnt;
  int unsigned read_cnt;
  int unsigned err_cnt;

  function automatic bit has_unknown(input logic [WIDTH-1:0] v);
    return $isunknown(v);
  endfunction

  
  // WRITE: continuous 800 random numbers (no drops)
  always_ff @(posedge w_clk or negedge rst_n) begin
    if (!rst_n) begin
      w_enq     <= 1'b0;
      w_data    <= '0;
      write_cnt <= 0;
    end else if (!tb_w_ready) begin
      w_enq  <= 1'b0;
      w_data <= '0;
    end else begin
      if (write_cnt < NUM_WRITE) begin
        if (!w_full) begin
          logic [31:0] rnd;
          logic [WIDTH-1:0] rand_data;

          rnd       = $urandom();
          rand_data = rnd[WIDTH-1:0];

          w_enq  <= 1'b1;
          w_data <= rand_data;

          exp_q.push_back(rand_data);
          write_cnt <= write_cnt + 1;
        end else begin
          w_enq <= 1'b0; // wait when full (do not consume a random number)
        end
      end else begin
        w_enq <= 1'b0;
      end
    end
  end

  
  always_ff @(posedge r_clk or negedge rst_n) begin
    if (!rst_n) begin
      r_deq <= 1'b0;
    end else if (!tb_r_ready) begin
      r_deq <= 1'b0;
    end else begin
      r_deq <= ~r_empty; // only request when data is available
    end
  end

 
  // CHECKER:
  always_ff @(posedge r_clk or negedge rst_n) begin
    if (!rst_n) begin
      read_cnt <= 0;
      err_cnt  <= 0;
    end else if (!tb_r_ready) begin
      //
    end else begin
      if (r_valid) begin
        if (has_unknown(r_data)) begin
        end else if (exp_q.size() == 0) begin
          $display("[%0t][ERROR] r_valid but exp_q empty! got=0x%0h", $time, r_data);
          err_cnt <= err_cnt + 1;
        end else begin
          logic [WIDTH-1:0] exp;
          exp = exp_q.pop_front();
          read_cnt <= read_cnt + 1;

          if (r_data !== exp) begin
            $display("[%0t][ERROR] MISMATCH got=0x%0h exp=0x%0h (q_sz=%0d)",
                     $time, r_data, exp, exp_q.size());
            err_cnt <= err_cnt + 1;
          end
        end
      end
    end
  end

 
  // Finish:

  initial begin
    wait (tb_w_ready && tb_r_ready);
    wait (read_cnt == NUM_WRITE);

    #100;
    $display("================================");
    $display("TB_W_READY = %0d  TB_R_READY = %0d", tb_w_ready, tb_r_ready);
    $display("WRITE_CNT  = %0d", write_cnt);
    $display("READ_CNT   = %0d", read_cnt);
    $display("EXP_Q_SZ   = %0d", exp_q.size());
    $display("ERR_CNT    = %0d", err_cnt);
    $display("================================");

    if (err_cnt == 0) $display("[PASS] async_fifo 800-random test PASS");
    else              $display("[FAIL] async_fifo 800-random test FAIL");

    $finish;
  end

  // timeout guard
  initial begin
    #10_000_000;
    $display("[%0t][FATAL] TIMEOUT", $time);
    $finish;
  end

endmodule