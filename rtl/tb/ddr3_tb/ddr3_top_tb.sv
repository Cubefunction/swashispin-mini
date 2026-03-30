`timescale 1ps/100fs

module ddr3_top_tb;

    //============================================================
    // Parameters
    //============================================================
    parameter int COL_WIDTH      = 10;
    parameter int CS_WIDTH       = 1;
    parameter int DM_WIDTH       = 2;
    parameter int DQ_WIDTH       = 16;
    parameter int DQS_WIDTH      = 2;
    parameter int DQS_CNT_WIDTH  = 1;
    parameter int DRAM_WIDTH     = 8;
    parameter int ECC            = 0;
    parameter int RANKS          = 1;
    parameter int ODT_WIDTH      = 1;
    parameter int ROW_WIDTH      = 14;
    parameter int ADDR_WIDTH     = 28;

    parameter real REFCLK_FREQ   = 200.0;
    parameter int  CLKIN_PERIOD  = 10000;     // ps
    parameter int  RESET_PERIOD  = 200000;    // ps
    parameter int  tCK           = 2500;

    parameter int DDR3_WITH      = 128;
    parameter int WR_FIFO_DEPTH  = 64;
    parameter int RD_FIFO_DEPTH  = 64;
    parameter int P_WR_BURST_LEN = 1;
    parameter int P_WR_BURST_NUM = 1;
    parameter int P_RD_BURST_LEN = 1;
    parameter int P_RD_BURST_NUM = 1;

    localparam int MEMORY_WIDTH  = 16;
    localparam int NUM_COMP      = DQ_WIDTH / MEMORY_WIDTH;
    localparam real REFCLK_PERIOD = (1000000.0/(2.0*REFCLK_FREQ));

    //============================================================
    // Reset / clocks
    //============================================================
    logic sys_rst_n;
    logic sys_rst;
    logic sys_clk_i;
    logic clk_ref_i;

    initial begin
        sys_rst_n = 1'b0;
        #RESET_PERIOD;
        sys_rst_n = 1'b1;
    end

    assign sys_rst = sys_rst_n;  // active-high reset to ddr3_top

    initial sys_clk_i = 1'b0;
    always #(CLKIN_PERIOD/2.0) sys_clk_i = ~sys_clk_i;

    initial clk_ref_i = 1'b0;
    always #REFCLK_PERIOD clk_ref_i = ~clk_ref_i;

    //============================================================
    // DDR3 PHY wires
    //============================================================
    wire [DQ_WIDTH-1:0]       ddr3_dq_fpga;
    wire [DQS_WIDTH-1:0]      ddr3_dqs_p_fpga;
    wire [DQS_WIDTH-1:0]      ddr3_dqs_n_fpga;
    wire [ROW_WIDTH-1:0]      ddr3_addr_fpga;
    wire [2:0]                ddr3_ba_fpga;
    wire                      ddr3_ras_n_fpga;
    wire                      ddr3_cas_n_fpga;
    wire                      ddr3_we_n_fpga;
    wire                      ddr3_reset_n;
    wire [0:0]                ddr3_ck_p_fpga;
    wire [0:0]                ddr3_ck_n_fpga;
    wire [0:0]                ddr3_cke_fpga;
    wire [CS_WIDTH-1:0]       ddr3_cs_n_fpga;
    wire [DM_WIDTH-1:0]       ddr3_dm_fpga;
    wire [ODT_WIDTH-1:0]      ddr3_odt_fpga;

    //============================================================
    // SDRAM side wires
    //============================================================
    wire [DQ_WIDTH-1:0]       ddr3_dq_sdram;
    wire [DQS_WIDTH-1:0]      ddr3_dqs_p_sdram;
    wire [DQS_WIDTH-1:0]      ddr3_dqs_n_sdram;
    logic [ROW_WIDTH-1:0]     ddr3_addr_sdram [0:1];
    logic [2:0]               ddr3_ba_sdram   [0:1];
    logic                     ddr3_ras_n_sdram;
    logic                     ddr3_cas_n_sdram;
    logic                     ddr3_we_n_sdram;
    logic [0:0]               ddr3_cke_sdram;
    logic [0:0]               ddr3_ck_p_sdram;
    logic [0:0]               ddr3_ck_n_sdram;
    logic [CS_WIDTH-1:0]      ddr3_cs_n_sdram_tmp;
    logic [DM_WIDTH-1:0]      ddr3_dm_sdram_tmp;
    logic [ODT_WIDTH-1:0]     ddr3_odt_sdram_tmp;

    wire [CS_WIDTH-1:0]       ddr3_cs_n_sdram;
    wire [DM_WIDTH-1:0]       ddr3_dm_sdram;
    wire [ODT_WIDTH-1:0]      ddr3_odt_sdram;

    //============================================================
    // DUT user-side test interface
    //============================================================
    logic                     i_user_wr_valid;
    logic [27:0]              i_user_wr_addr_base;
    logic                     o_user_wr_finish;
    logic                     i_user_wr_data_valid;
    logic [DDR3_WITH-1:0]     i_user_wr_data;
    logic                     o_user_wr_fifo_ready;

    logic                     i_user_rd_valid;
    logic [27:0]              i_user_rd_addr_base;
    logic                     o_user_rd_finish;
    logic                     o_user_rd_data_valid;
    logic [DDR3_WITH-1:0]     o_user_rd_data;

    logic                     init_calib_complete;
    logic                     mmcm_locked;

    logic [DDR3_WITH-1:0]     expected_data;
    logic                     compare_pass;
    logic                     compare_fail;

    //============================================================
    // PCB delay modeling (borrowed from official tb)
    //============================================================
    always @(*) begin
        ddr3_ck_p_sdram    <= ddr3_ck_p_fpga;
        ddr3_ck_n_sdram    <= ddr3_ck_n_fpga;
        ddr3_addr_sdram[0] <= ddr3_addr_fpga;
        ddr3_addr_sdram[1] <= ddr3_addr_fpga;
        ddr3_ba_sdram[0]   <= ddr3_ba_fpga;
        ddr3_ba_sdram[1]   <= ddr3_ba_fpga;
        ddr3_ras_n_sdram   <= ddr3_ras_n_fpga;
        ddr3_cas_n_sdram   <= ddr3_cas_n_fpga;
        ddr3_we_n_sdram    <= ddr3_we_n_fpga;
        ddr3_cke_sdram     <= ddr3_cke_fpga;
    end

    always @(*) ddr3_cs_n_sdram_tmp <= ddr3_cs_n_fpga;
    assign ddr3_cs_n_sdram = ddr3_cs_n_sdram_tmp;

    always @(*) ddr3_dm_sdram_tmp <= ddr3_dm_fpga;
    assign ddr3_dm_sdram = ddr3_dm_sdram_tmp;

    always @(*) ddr3_odt_sdram_tmp <= ddr3_odt_fpga;
    assign ddr3_odt_sdram = ddr3_odt_sdram_tmp;

    genvar dqwd;
    generate
        for (dqwd = 0; dqwd < DQ_WIDTH; dqwd++) begin : dq_delay
            WireDelay #(
                .Delay_g   (0.0),
                .Delay_rd  (0.0),
                .ERR_INSERT("OFF")
            ) u_delay_dq (
                .A             (ddr3_dq_fpga[dqwd]),
                .B             (ddr3_dq_sdram[dqwd]),
                .reset         (sys_rst_n),
                .phy_init_done (init_calib_complete)
            );
        end
    endgenerate

    genvar dqswd;
    generate
        for (dqswd = 0; dqswd < DQS_WIDTH; dqswd++) begin : dqs_delay
            WireDelay #(
                .Delay_g   (0.0),
                .Delay_rd  (0.0),
                .ERR_INSERT("OFF")
            ) u_delay_dqs_p (
                .A             (ddr3_dqs_p_fpga[dqswd]),
                .B             (ddr3_dqs_p_sdram[dqswd]),
                .reset         (sys_rst_n),
                .phy_init_done (init_calib_complete)
            );

            WireDelay #(
                .Delay_g   (0.0),
                .Delay_rd  (0.0),
                .ERR_INSERT("OFF")
            ) u_delay_dqs_n (
                .A             (ddr3_dqs_n_fpga[dqswd]),
                .B             (ddr3_dqs_n_sdram[dqswd]),
                .reset         (sys_rst_n),
                .phy_init_done (init_calib_complete)
            );
        end
    endgenerate

    //============================================================
    // DUT
    //============================================================
    ddr3_top #(
        .DDR3_WITH      (DDR3_WITH),
        .WR_FIFO_DEPTH  (WR_FIFO_DEPTH),
        .RD_FIFO_DEPTH  (RD_FIFO_DEPTH),
        .P_WR_BURST_LEN (P_WR_BURST_LEN),
        .P_WR_BURST_NUM (P_WR_BURST_NUM),
        .P_RD_BURST_LEN (P_RD_BURST_LEN),
        .P_RD_BURST_NUM (P_RD_BURST_NUM)
    ) u_ip_top (
        .ddr3_addr            (ddr3_addr_fpga),
        .ddr3_ba              (ddr3_ba_fpga),
        .ddr3_cas_n           (ddr3_cas_n_fpga),
        .ddr3_ck_n            (ddr3_ck_n_fpga),
        .ddr3_ck_p            (ddr3_ck_p_fpga),
        .ddr3_cke             (ddr3_cke_fpga),
        .ddr3_ras_n           (ddr3_ras_n_fpga),
        .ddr3_reset_n         (ddr3_reset_n),
        .ddr3_we_n            (ddr3_we_n_fpga),
        .ddr3_dq              (ddr3_dq_fpga),
        .ddr3_dqs_n           (ddr3_dqs_n_fpga),
        .ddr3_dqs_p           (ddr3_dqs_p_fpga),
        .ddr3_cs_n            (ddr3_cs_n_fpga),
        .ddr3_dm              (ddr3_dm_fpga),
        .ddr3_odt             (ddr3_odt_fpga),

        .sys_clk_i            (sys_clk_i),
        .sys_rst_n              (sys_rst),

        .i_user_wr_valid      (i_user_wr_valid),
        .i_user_wr_addr_base  (i_user_wr_addr_base),
        .i_user_wr_data_valid (i_user_wr_data_valid),
        .i_user_wr_data       (i_user_wr_data),
        .o_user_wr_finish     (o_user_wr_finish),
        .o_user_wr_fifo_ready (o_user_wr_fifo_ready),

        .i_user_rd_valid      (i_user_rd_valid),
        .i_user_rd_addr_base  (i_user_rd_addr_base),
        .o_user_rd_finish     (o_user_rd_finish),
        .o_user_rd_data_valid (o_user_rd_data_valid),
        .o_user_rd_data       (o_user_rd_data),

        .init_calib_complete  (init_calib_complete),
        .mmcm_locked          (mmcm_locked)
    );

    //============================================================
    // DDR3 memory models (example ip)
    //============================================================
    genvar r, i;
    generate
        for (r = 0; r < CS_WIDTH; r = r + 1) begin : mem_rnk
            for (i = 0; i < NUM_COMP; i = i + 1) begin : gen_mem
                ddr3_model u_comp_ddr3 (
                    .rst_n   (ddr3_reset_n),
                    .ck      (ddr3_ck_p_sdram),
                    .ck_n    (ddr3_ck_n_sdram),
                    .cke     (ddr3_cke_sdram[r]),
                    .cs_n    (ddr3_cs_n_sdram[r]),
                    .ras_n   (ddr3_ras_n_sdram),
                    .cas_n   (ddr3_cas_n_sdram),
                    .we_n    (ddr3_we_n_sdram),
                    .dm_tdqs (ddr3_dm_sdram[(2*(i+1)-1):(2*i)]),
                    .ba      (ddr3_ba_sdram[r]),
                    .addr    (ddr3_addr_sdram[r]),
                    .dq      (ddr3_dq_sdram[16*(i+1)-1:16*i]),
                    .dqs     (ddr3_dqs_p_sdram[(2*(i+1)-1):(2*i)]),
                    .dqs_n   (ddr3_dqs_n_sdram[(2*(i+1)-1):(2*i)]),
                    .tdqs_n  (),
                    .odt     (ddr3_odt_sdram[r])
                );
            end
        end
    endgenerate

    //============================================================
    // Simple user-side stimulus 
    //============================================================
    initial begin
        i_user_wr_valid      = 1'b0;
        i_user_wr_addr_base  = 28'h0;
        i_user_wr_data_valid = 1'b0;
        i_user_wr_data       = '0;

        i_user_rd_valid      = 1'b0;
        i_user_rd_addr_base  = 28'h0;

        expected_data        = 128'h1234_5678_9ABC_DEF0_55AA_33CC_F00D_CAFE;
        compare_pass         = 1'b0;
        compare_fail         = 1'b0;

        wait(init_calib_complete);
        $display("[%0t] Calibration Done", $time);

        // give some margin
        repeat (20) @(posedge u_ip_top.ui_clk);

        // 1) start write transaction
        @(posedge u_ip_top.ui_clk);
        i_user_wr_addr_base <= 28'h0000100;
        i_user_wr_valid     <= 1'b1;
        @(posedge u_ip_top.ui_clk);
        i_user_wr_valid     <= 1'b0;

        // 2) push one write data beat
        wait(o_user_wr_fifo_ready);
        @(posedge u_ip_top.ui_clk);
        i_user_wr_data       <= expected_data;
        i_user_wr_data_valid <= 1'b1;
        @(posedge u_ip_top.ui_clk);
        i_user_wr_data_valid <= 1'b0;

        // 3) wait write finish
        wait(o_user_wr_finish);
        $display("[%0t] Write finished", $time);

        // 4) start read transaction
        @(posedge u_ip_top.ui_clk);
        i_user_rd_addr_base <= 28'h0000100;
        i_user_rd_valid     <= 1'b1;
        @(posedge u_ip_top.ui_clk);
        i_user_rd_valid     <= 1'b0;

        // 5) wait read data
        wait(o_user_rd_data_valid);
        $display("[%0t] Read data = %h", $time, o_user_rd_data);

        if (o_user_rd_data == expected_data) begin
            compare_pass = 1'b1;
            $display("TEST PASSED");
        end else begin
            compare_fail = 1'b1;
            $display("TEST FAILED: DATA MISMATCH");
        end

        #100000;
        $finish;
    end

    //============================================================
    // Timeout
    //============================================================
    initial begin
        #1000000000.0;
        if (!init_calib_complete) begin
            $display("TEST FAILED: INITIALIZATION DID NOT COMPLETE");
        end else if (!compare_pass && !compare_fail) begin
            $display("TEST FAILED: NO READBACK RESULT");
        end
        $finish;
    end

endmodule