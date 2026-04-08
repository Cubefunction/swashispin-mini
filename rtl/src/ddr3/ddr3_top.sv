`timescale 1ns/1ps

module ddr3_top #(
    parameter int DDR3_WITH      = 128,
    parameter int WR_FIFO_DEPTH  = 64,
    parameter int RD_FIFO_DEPTH  = 64,
    parameter int P_WR_BURST_LEN = 8,
    parameter int P_WR_BURST_NUM = 1,
    parameter int P_RD_BURST_LEN = 8,
    parameter int P_RD_BURST_NUM = 1
)(
    //==============================
    // DDR3 PHY
    //==============================
    output logic [13:0] ddr3_addr,
    output logic [2:0]  ddr3_ba,
    output logic        ddr3_cas_n,
    output logic [0:0]  ddr3_ck_n,
    output logic [0:0]  ddr3_ck_p,
    output logic [0:0]  ddr3_cke,
    output logic        ddr3_ras_n,
    output logic        ddr3_reset_n,
    output logic        ddr3_we_n,
    inout  wire [15:0]  ddr3_dq,
    inout  wire [1:0]   ddr3_dqs_n,
    inout  wire [1:0]   ddr3_dqs_p,
    output logic [0:0]  ddr3_cs_n,
    output logic [1:0]  ddr3_dm,
    output logic [0:0]  ddr3_odt,

    //==============================
    // Board IO
    //==============================
    input  logic        sys_clk_i,
    input  logic        sys_rst_n,   
    output logic        ui_clk,
    output logic        ui_clk_sync_rst,
    //==============================
    // User interface
    //==============================
    input  logic                     i_user_wr_valid,
    input  logic [27:0]              i_user_wr_addr_base,
    input  logic                     i_user_wr_data_valid,
    input  logic [DDR3_WITH-1:0]     i_user_wr_data,
    output logic                     o_user_wr_finish,
    output logic                     o_user_wr_fifo_ready,

    input  logic                     i_user_rd_valid,
    input  logic [27:0]              i_user_rd_addr_base,
    output logic                     o_user_rd_finish,
    output logic                     o_user_rd_data_valid,
    output logic [DDR3_WITH-1:0]     o_user_rd_data,

    //==============================
    // Status
    //==============================
    output logic init_calib_complete,
    output logic mmcm_locked
);

    //============================================================
    // Internal signals
    //============================================================
    //logic ui_clk;
    //logic ui_clk_sync_rst;   
    logic aresetn;

    logic clk_ref_i;
    //logic clk_ddr3_i;
    logic locked;

    logic mig_sys_rst_n;       

    // MIG sideband
    logic app_sr_req;
    logic app_ref_req;
    logic app_zq_req;
    logic app_sr_active;
    logic app_ref_ack;
    logic app_zq_ack;

    //============================================================
    // AXI signals
    //============================================================
    logic [3:0]  s_axi_awid;
    logic [27:0] s_axi_awaddr;
    logic [7:0]  s_axi_awlen;
    logic [2:0]  s_axi_awsize;
    logic [1:0]  s_axi_awburst;
    logic [0:0]  s_axi_awlock;
    logic [3:0]  s_axi_awcache;
    logic [2:0]  s_axi_awprot;
    logic [3:0]  s_axi_awqos;
    logic        s_axi_awvalid;
    logic        s_axi_awready;

    logic [DDR3_WITH-1:0] s_axi_wdata;
    logic [15:0]          s_axi_wstrb;
    logic                 s_axi_wlast;
    logic                 s_axi_wvalid;
    logic                 s_axi_wready;

    logic [3:0]  s_axi_bid;
    logic [1:0]  s_axi_bresp;
    logic        s_axi_bvalid;
    logic        s_axi_bready;

    logic [3:0]  s_axi_arid;
    logic [27:0] s_axi_araddr;
    logic [7:0]  s_axi_arlen;
    logic [2:0]  s_axi_arsize;
    logic [1:0]  s_axi_arburst;
    logic [0:0]  s_axi_arlock;
    logic [3:0]  s_axi_arcache;
    logic [2:0]  s_axi_arprot;
    logic [3:0]  s_axi_arqos;
    logic        s_axi_arvalid;
    logic        s_axi_arready;

    logic [3:0]           s_axi_rid;
    logic [DDR3_WITH-1:0] s_axi_rdata;
    logic [1:0]           s_axi_rresp;
    logic                 s_axi_rlast;
    logic                 s_axi_rvalid;
    logic                 s_axi_rready;

    
    assign mig_sys_rst_n = sys_rst_n & locked;

    //============================================================
    // Clock Wizard
    //============================================================
    clk_wiz_0 u_clk (
        .clk_out1 (clk_ddr3_i),
        .clk_out2 (clk_ref_i),
        .reset    (!sys_rst_n),
        .locked   (locked),
        .clk_in1  (sys_clk_i)
    );

    //============================================================
    // Driver
    //============================================================
    mig_axi4_driver #(
        .DDR3_WITH      (DDR3_WITH),
        .P_WR_BURST_LEN (P_WR_BURST_LEN),
        .P_WR_BURST_NUM (P_WR_BURST_NUM),
        .P_RD_BURST_LEN (P_RD_BURST_LEN),
        .P_RD_BURST_NUM (P_RD_BURST_NUM),
        .WR_FIFO_DEPTH  (WR_FIFO_DEPTH),
        .RD_FIFO_DEPTH  (RD_FIFO_DEPTH)
    ) u_driver (
        .i_clk                (ui_clk),
        .i_rst_n              (!ui_clk_sync_rst),   

        .i_user_wr_clk        (ui_clk),
        .i_user_rd_clk        (ui_clk),

        .i_user_wr_valid      (i_user_wr_valid),
        .i_user_wr_addr_base  (i_user_wr_addr_base),
        .o_user_wr_finish     (o_user_wr_finish),
        .i_user_wr_data_valid (i_user_wr_data_valid),
        .i_user_wr_data       (i_user_wr_data),
        .o_user_wr_fifo_ready (o_user_wr_fifo_ready),

        .i_user_rd_valid      (i_user_rd_valid),
        .i_user_rd_addr_base  (i_user_rd_addr_base),
        .o_user_rd_finish     (o_user_rd_finish),
        .o_user_rd_data_valid (o_user_rd_data_valid),
        .o_user_rd_data       (o_user_rd_data),

        .init_calib_complete  (init_calib_complete),
        .mmcm_locked          (mmcm_locked),
        .aresetn              (aresetn),

        .app_sr_req           (app_sr_req),
        .app_ref_req          (app_ref_req),
        .app_zq_req           (app_zq_req),
        .app_sr_active        (app_sr_active),
        .app_ref_ack          (app_ref_ack),
        .app_zq_ack           (app_zq_ack),

        .s_axi_awid           (s_axi_awid),
        .s_axi_awaddr         (s_axi_awaddr),
        .s_axi_awlen          (s_axi_awlen),
        .s_axi_awsize         (s_axi_awsize),
        .s_axi_awburst        (s_axi_awburst),
        .s_axi_awlock         (s_axi_awlock),
        .s_axi_awcache        (s_axi_awcache),
        .s_axi_awprot         (s_axi_awprot),
        .s_axi_awqos          (s_axi_awqos),
        .s_axi_awvalid        (s_axi_awvalid),
        .s_axi_awready        (s_axi_awready),

        .s_axi_wdata          (s_axi_wdata),
        .s_axi_wstrb          (s_axi_wstrb),
        .s_axi_wlast          (s_axi_wlast),
        .s_axi_wvalid         (s_axi_wvalid),
        .s_axi_wready         (s_axi_wready),

        .s_axi_bid            (s_axi_bid),
        .s_axi_bresp          (s_axi_bresp),
        .s_axi_bvalid         (s_axi_bvalid),
        .s_axi_bready         (s_axi_bready),

        .s_axi_arid           (s_axi_arid),
        .s_axi_araddr         (s_axi_araddr),
        .s_axi_arlen          (s_axi_arlen),
        .s_axi_arsize         (s_axi_arsize),
        .s_axi_arburst        (s_axi_arburst),
        .s_axi_arlock         (s_axi_arlock),
        .s_axi_arcache        (s_axi_arcache),
        .s_axi_arprot         (s_axi_arprot),
        .s_axi_arqos          (s_axi_arqos),
        .s_axi_arvalid        (s_axi_arvalid),
        .s_axi_arready        (s_axi_arready),

        .s_axi_rid            (s_axi_rid),
        .s_axi_rdata          (s_axi_rdata),
        .s_axi_rresp          (s_axi_rresp),
        .s_axi_rlast          (s_axi_rlast),
        .s_axi_rvalid         (s_axi_rvalid),
        .s_axi_rready         (s_axi_rready)
    );

    //============================================================
    // MIG
    //============================================================
    mig_7series_0 u_mig (
        .sys_clk_i            (clk_ddr3_i),
        .clk_ref_i            (clk_ref_i),
        .sys_rst              (mig_sys_rst_n),   

        .ui_clk               (ui_clk),
        .ui_clk_sync_rst      (ui_clk_sync_rst),
        .mmcm_locked          (mmcm_locked),
        .aresetn              (aresetn),
        .init_calib_complete  (init_calib_complete),

        .ddr3_addr            (ddr3_addr),
        .ddr3_ba              (ddr3_ba),
        .ddr3_cas_n           (ddr3_cas_n),
        .ddr3_ck_n            (ddr3_ck_n),
        .ddr3_ck_p            (ddr3_ck_p),
        .ddr3_cke             (ddr3_cke),
        .ddr3_ras_n           (ddr3_ras_n),
        .ddr3_reset_n         (ddr3_reset_n),
        .ddr3_we_n            (ddr3_we_n),
        .ddr3_dq              (ddr3_dq),
        .ddr3_dqs_n           (ddr3_dqs_n),
        .ddr3_dqs_p           (ddr3_dqs_p),
        .ddr3_cs_n            (ddr3_cs_n),
        .ddr3_dm              (ddr3_dm),
        .ddr3_odt             (ddr3_odt),

        .app_sr_req           (app_sr_req),
        .app_ref_req          (app_ref_req),
        .app_zq_req           (app_zq_req),
        .app_sr_active        (app_sr_active),
        .app_ref_ack          (app_ref_ack),
        .app_zq_ack           (app_zq_ack),

        .s_axi_awid           (s_axi_awid),
        .s_axi_awaddr         (s_axi_awaddr),
        .s_axi_awlen          (s_axi_awlen),
        .s_axi_awsize         (s_axi_awsize),
        .s_axi_awburst        (s_axi_awburst),
        .s_axi_awlock         (s_axi_awlock),
        .s_axi_awcache        (s_axi_awcache),
        .s_axi_awprot         (s_axi_awprot),
        .s_axi_awqos          (s_axi_awqos),
        .s_axi_awvalid        (s_axi_awvalid),
        .s_axi_awready        (s_axi_awready),

        .s_axi_wdata          (s_axi_wdata),
        .s_axi_wstrb          (s_axi_wstrb),
        .s_axi_wlast          (s_axi_wlast),
        .s_axi_wvalid         (s_axi_wvalid),
        .s_axi_wready         (s_axi_wready),

        .s_axi_bid            (s_axi_bid),
        .s_axi_bresp          (s_axi_bresp),
        .s_axi_bvalid         (s_axi_bvalid),
        .s_axi_bready         (s_axi_bready),

        .s_axi_arid           (s_axi_arid),
        .s_axi_araddr         (s_axi_araddr),
        .s_axi_arlen          (s_axi_arlen),
        .s_axi_arsize         (s_axi_arsize),
        .s_axi_arburst        (s_axi_arburst),
        .s_axi_arlock         (s_axi_arlock),
        .s_axi_arcache        (s_axi_arcache),
        .s_axi_arprot         (s_axi_arprot),
        .s_axi_arqos          (s_axi_arqos),
        .s_axi_arvalid        (s_axi_arvalid),
        .s_axi_arready        (s_axi_arready),

        .s_axi_rid            (s_axi_rid),
        .s_axi_rdata          (s_axi_rdata),
        .s_axi_rresp          (s_axi_rresp),
        .s_axi_rlast          (s_axi_rlast),
        .s_axi_rvalid         (s_axi_rvalid),
        .s_axi_rready         (s_axi_rready)
    );

endmodule