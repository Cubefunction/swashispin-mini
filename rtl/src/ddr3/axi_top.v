`timescale 1ns/1ps

module axi_top #(
    parameter       DDR3_WITH       = 128,
    parameter       WR_FIFO_DEPTH   = 64  ,
    parameter       RD_FIFO_DEPTH   = 64
)(
    // --- Physical DDR3 Interface (To Pins) ---
    output [13:0]   ddr3_addr,
    output [2:0]    ddr3_ba,
    output          ddr3_cas_n,
    output [0:0]    ddr3_ck_n,
    output [0:0]    ddr3_ck_p,
    output [0:0]    ddr3_cke,
    output          ddr3_ras_n,
    output          ddr3_reset_n,
    output          ddr3_we_n,
    inout  [15:0]   ddr3_dq,
    inout  [1:0]    ddr3_dqs_n,
    inout  [1:0]    ddr3_dqs_p,
    output [0:0]    ddr3_cs_n,
    output [1:0]    ddr3_dm,
    output [0:0]    ddr3_odt,

    // --- System Signals ---
    input           sys_clk_i,      // 100MHz Input
    input           sys_rst        // Global Reset

    
);

    // --- Internal Interconnect Signals ---
    wire        ui_clk;
    wire        ui_clk_sync_rst;
    wire        mmcm_locked;
    wire        init_calib_complete;
    wire        aresetn;

    // AXI Bus Signals
    wire [3:0]  s_axi_awid;
    wire [27:0] s_axi_awaddr;
    wire [7:0]  s_axi_awlen;
    wire [2:0]  s_axi_awsize;
    wire [1:0]  s_axi_awburst;
    wire [0:0]  s_axi_awlock;
    wire [3:0]  s_axi_awcache;
    wire [2:0]  s_axi_awprot;
    wire [3:0]  s_axi_awqos;
    wire        s_axi_awvalid;
    wire        s_axi_awready;

    wire [DDR3_WITH-1:0] s_axi_wdata;
    wire [15:0] s_axi_wstrb;
    wire        s_axi_wlast;
    wire        s_axi_wvalid;
    wire        s_axi_wready;

    wire [3:0]  s_axi_bid;
    wire [1:0]  s_axi_bresp;
    wire        s_axi_bvalid;
    wire        s_axi_bready;

    wire [3:0]  s_axi_arid;
    wire [27:0] s_axi_araddr;
    wire [7:0]  s_axi_arlen;
    wire [2:0]  s_axi_arsize;
    wire [1:0]  s_axi_arburst;
    wire [0:0]  s_axi_arlock;
    wire [3:0]  s_axi_arcache;
    wire [2:0]  s_axi_arprot;
    wire [3:0]  s_axi_arqos;
    wire        s_axi_arvalid;
    wire        s_axi_arready;

    wire [3:0]  s_axi_rid;
    wire [DDR3_WITH-1:0] s_axi_rdata;
    wire [1:0]  s_axi_rresp;
    wire        s_axi_rlast;
    wire        s_axi_rvalid;
    wire        s_axi_rready;

    // --- 1. Custom Driver Instance ---
    mig_axi4_driver #(
        .DDR3_WITH       (DDR3_WITH),
        .P_WR_BURST_LEN  (P_WR_BURST_LEN),
        .P_WR_BURST_NUM  (P_WR_BURST_NUM),
        .P_RD_BURST_LEN  (P_RD_BURST_LEN),
        .P_RD_BURST_NUM  (P_RD_BURST_NUM),
        .WR_FIFO_DEPTH   (WR_FIFO_DEPTH),
        .RD_FIFO_DEPTH   (RD_FIFO_DEPTH)
    ) u_driver (
        .i_clk                (ui_clk),            // Driver runs on MIG UI clock
        .i_rst                (ui_clk_sync_rst),   // Use MIG synchronized reset
        .i_user_wr_clk        (ui_clk),
        .i_user_rd_clk        (ui_clk),
        .i_user_wr_valid      (i_user_wr_valid),
        .i_user_wr_addr_base  (i_user_wr_addr_base),
        .o_user_wr_finish     (w_user_wr_finish),
        .i_user_wr_data_valid (i_user_wr_data_valid),
        .i_user_wr_data       (i_user_wr_data),
        .o_user_wr_fifo_ready (w_user_wr_fifo_ready),
        .i_user_rd_valid      (i_user_rd_valid),
        .i_user_rd_addr_base  (i_user_rd_addr_base),
        .o_user_rd_finish     (w_user_rd_finish),
        .o_user_rd_data_valid (w_user_rd_data_valid),
        .o_user_rd_data       (w_user_rd_data),

        .init_calib_complete  (init_calib_complete),
        .mmcm_locked          (mmcm_locked),
        .aresetn              (aresetn),
        .app_sr_req           (app_sr_req),
        .app_ref_req          (app_ref_req),
        .app_zq_req           (app_zq_req),
        .app_sr_active        (app_sr_active),
        .app_ref_ack          (app_ref_ack),
        .app_zq_ack           (app_zq_ack),

        // AXI4 Interface Master Output
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

    // --- 2. Xilinx MIG IP Instance ---
    mig_7series_0 u_mig (
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

        .ui_clk               (ui_clk),
        .ui_clk_sync_rst      (ui_clk_sync_rst),
        .mmcm_locked          (mmcm_locked),
        .aresetn              (aresetn),
        .app_sr_req           (app_sr_req),
        .app_ref_req          (app_ref_req),
        .app_zq_req           (app_zq_req),
        .app_sr_active        (app_sr_active),
        .app_ref_ack          (app_ref_ack),
        .app_zq_ack           (app_zq_ack),

        .init_calib_complete  (init_calib_complete),

        // AXI4 Slave Interface
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
        .s_axi_rready         (s_axi_rready),

        // System Clocks
        .sys_clk_i            (clk_ddr3_i),
        .clk_ref_i            (clk_ref_i),
        .sys_rst              (locked)
    );
    
    wire clk_ref_i;
    wire clk_ddr3_i;
    
    clk_wiz_0 u_wiz
   (
    // Clock out ports
    .clk_out1(clk_ref_i),     // output clk_out1
    .clk_out2(clk_ddr3_i),     // output clk_out2
    // Status and control signals
    .reset(sys_rst), // input reset
    .locked(locked),       // output locked
   // Clock in ports
    .clk_in1(sys_clk_i)      // input clk_in1
);

//---------------------test-----------------------------------
// --- User Interface (To your Logic) ---
    reg            i_user_wr_valid;
    reg  [27:0]   i_user_wr_addr_base;
    wire          w_user_wr_finish;
    reg           i_user_wr_data_valid;
    reg  [DDR3_WITH-1:0] i_user_wr_data;
    wire          w_user_wr_fifo_ready;

    reg           i_user_rd_valid;
    reg  [27:0]   i_user_rd_addr_base;
    wire          w_user_rd_finish;
    wire          w_user_rd_data_valid;
    wire [DDR3_WITH-1:0] w_user_rd_data;


////////////////////////////////////////////////
parameter
    P_ST_IDLE   = 'd0 ,   
    P_ST_WR     = 'd1 ,   
    P_ST_WR_WAIT= 'd2 ,   
    P_ST_RD     = 'd3 ,
    P_ST_RD_WAIT= 'd4 ,
    P_ST_FINISH = 'd5 ;

parameter  P_WR_BURST_LEN = 'd16 ;
parameter  P_WR_BURST_NUM = 'd5 ;
parameter  P_RD_BURST_LEN = 'd16 ;
parameter  P_RD_BURST_NUM = 'd5 ;

parameter  P_WR_NUM = P_WR_BURST_LEN * P_WR_BURST_NUM ;

reg [7:0]  r_state_current ;
reg [7:0]  r_state_next    ;
reg [7:0]  r_state_cnt     ;

reg [15:0] r_write_num_cnt ;
///////////////
always@(posedge ui_clk ,posedge ui_clk_sync_rst)
begin
    if (ui_clk_sync_rst)
        r_state_current <= P_ST_IDLE;
    else
        r_state_current <= r_state_next;
end


always @(*) begin
    case(r_state_current)
        P_ST_IDLE    : r_state_next <= init_calib_complete ? P_ST_WR      : P_ST_IDLE;
        P_ST_WR      : r_state_next <= i_user_wr_valid     ? P_ST_WR_WAIT : P_ST_WR;   //发出写地址
        P_ST_WR_WAIT : r_state_next <= w_user_wr_finish    ? P_ST_RD      : P_ST_WR_WAIT;
        P_ST_RD      : r_state_next <= i_user_rd_valid     ? P_ST_RD_WAIT : P_ST_RD;
        P_ST_RD_WAIT : r_state_next <= w_user_rd_finish    ? P_ST_FINISH  : P_ST_RD_WAIT;
        P_ST_FINISH  : r_state_next <= P_ST_FINISH;
        default      : r_state_next <= P_ST_IDLE;
    endcase
end

always@(posedge ui_clk ,posedge ui_clk_sync_rst)
begin
    if(ui_clk_sync_rst) begin
        i_user_wr_valid      <= 'd0;
        i_user_wr_addr_base  <= 'd0;
    end
    else if(r_state_current==P_ST_WR && r_state_cnt=='d0) begin
        i_user_wr_valid      <= 'd1;
        i_user_wr_addr_base  <= 'd0;
    end
    else begin
        i_user_wr_valid      <= 'd0;
        i_user_wr_addr_base  <= 'd0;
    end
end


always@(posedge ui_clk ,posedge ui_clk_sync_rst)
begin
    if(ui_clk_sync_rst) begin
        i_user_wr_data_valid <= 'd0;
        i_user_wr_data       <= 'd0;
    end
    else if(r_state_current==P_ST_WR_WAIT && w_user_wr_fifo_ready && r_write_num_cnt < (P_WR_NUM-1)) begin
        i_user_wr_data_valid <= 'd1;
        i_user_wr_data       <= i_user_wr_data + 'd1;
    end
    else begin
        i_user_wr_data_valid <= 'd0;
        i_user_wr_data       <= 'd0;
    end
end

always@(posedge ui_clk ,posedge ui_clk_sync_rst)
begin
    if(ui_clk_sync_rst)
        r_write_num_cnt <= 'd0;
    else if(i_user_wr_data_valid && r_write_num_cnt <= (P_WR_NUM-1))
        r_write_num_cnt <= r_write_num_cnt + 'd1;
    else if(r_write_num_cnt == (P_WR_NUM))
        r_write_num_cnt <= r_write_num_cnt;
end


always@(posedge ui_clk ,posedge ui_clk_sync_rst)
begin
    if(ui_clk_sync_rst) begin
        i_user_rd_valid      <= 'd0;
        i_user_rd_addr_base  <= 'd0;
    end
    else if(r_state_current==P_ST_RD && r_state_cnt=='d0) begin
        i_user_rd_valid      <= 'd1;
        i_user_rd_addr_base  <= 'd0;
    end
    else begin
        i_user_rd_valid      <= 'd0;
        i_user_rd_addr_base  <= 'd0;
    end
end
endmodule