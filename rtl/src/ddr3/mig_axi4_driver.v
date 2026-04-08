`timescale 1ns/1ps

module mig_axi4_driver#(
    parameter       DDR3_WITH       = 'd128,
    parameter       P_WR_BURST_LEN  = 'd80 ,
    parameter       P_WR_BURST_NUM  = 'd5  ,

    parameter       P_RD_BURST_LEN  = 'd80 ,
    parameter       P_RD_BURST_NUM  = 'd5  ,
    parameter       WR_FIFO_DEPTH   = 128  ,
    parameter       RD_FIFO_DEPTH   = 128
)(
    /*=======================MIG_CLK=======================*/
    input               i_clk,
    input               i_rst_n,
    /*=======================WR_CLK/RD_CLK=======================*/
    input               i_user_wr_clk       ,
    input               i_user_rd_clk       ,
    /*=======================USER=======================*/
    input               i_user_wr_valid        , // Start a write transaction
    input      [27:0]   i_user_wr_addr_base    , // Base address of this write transaction
    output              o_user_wr_finish       , // Write transaction completion signal

    input                       i_user_wr_data_valid   , // Write data valid
    input     [DDR3_WITH-1:0]   i_user_wr_data         , // Data to be written
    output                      o_user_wr_fifo_ready   , // Write FIFO not full, ready to accept data

    input               i_user_rd_valid        , // Start a read transaction
    input      [27:0]   i_user_rd_addr_base    , // Base address of this read transaction
    output              o_user_rd_finish       , // Read transaction completion signal

    output                      o_user_rd_data_valid   , // Read data valid signal
    output     [DDR3_WITH-1:0]  o_user_rd_data         , // Read data output

    /*======================= MIG AXI4 Interface =======================*/
    input  init_calib_complete ,  // MIG initialization and calibration complete

    input  mmcm_locked         ,  // MMCM clock is locked and stable
    output aresetn             ,  // Active-low AXI reset signal
    output app_sr_req          ,  // Self-refresh request
    output app_ref_req         ,  // Refresh request
    output app_zq_req          ,  // ZQ calibration request
    input  app_sr_active       ,  // Self-refresh mode active
    input  app_ref_ack         ,  // Refresh request acknowledge
    input  app_zq_ack          ,  // ZQ calibration acknowledge
    

    output      [3:0]   s_axi_awid     , // Write address ID
    (* MARK_DEBUG="true" *) output  [27:0]  s_axi_awaddr   , // Write address
    output              [7:0]   s_axi_awlen    , // Burst length
    output              [2:0]   s_axi_awsize   , // Burst size
    output              [1:0]   s_axi_awburst  , // Burst type
    output              [0:0]   s_axi_awlock   , // Lock signal
    output              [3:0]   s_axi_awcache  , // Cache type
    output              [2:0]   s_axi_awprot   , // Protection type
    output              [3:0]   s_axi_awqos    , // Quality of Service
    (* MARK_DEBUG="true" *) output          s_axi_awvalid  , // Write address valid
    (* MARK_DEBUG="true" *) input           s_axi_awready  , // Write address ready


    /*======================= AXI4 Write Data Channel =======================*/

    (* MARK_DEBUG="true" *) output [DDR3_WITH-1:0]  s_axi_wdata    , // Write data
    output                  [15:0]  s_axi_wstrb    , // Write strobe (byte enable)
    (* MARK_DEBUG="true" *) output          s_axi_wlast    , // Write last beat
    (* MARK_DEBUG="true" *) output          s_axi_wvalid   , // Write data valid
    (* MARK_DEBUG="true" *) input           s_axi_wready   , // Write data ready


    /*======================= AXI4 Write Response Channel =======================*/

    input                   [3:0]   s_axi_bid      , // Write response ID
    input                   [1:0]   s_axi_bresp    , // Write response
    input                            s_axi_bvalid   , // Write response valid
    output                           s_axi_bready   , // Write response ready

    /*---------------------- AXI4 Read Address Channel ----------------------*/

    output      [3:0]   s_axi_arid     , // Read address ID
    (* MARK_DEBUG="true" *) output [27:0]  s_axi_araddr   , // Read address
    output             [7:0]   s_axi_arlen    , // Burst length
    output             [2:0]   s_axi_arsize   , // Burst size
    output             [1:0]   s_axi_arburst  , // Burst type
    output             [0:0]   s_axi_arlock   , // Lock signal
    output             [3:0]   s_axi_arcache  , // Cache type
    output             [2:0]   s_axi_arprot   , // Protection type
    output             [3:0]   s_axi_arqos    , // Quality of Service
    (* MARK_DEBUG="true" *) output          s_axi_arvalid , // Read address valid
    (* MARK_DEBUG="true" *) input           s_axi_arready , // Read address ready


    /*---------------------- AXI4 Read Data Channel ----------------------*/

    input                  [3:0]   s_axi_rid     , // Read response ID
    (* MARK_DEBUG="true" *) input  [DDR3_WITH-1:0] s_axi_rdata   , // Read data
    input                  [1:0]   s_axi_rresp   , // Read response
    (* MARK_DEBUG="true" *) input           s_axi_rlast   , // Read last beat
    (* MARK_DEBUG="true" *) input           s_axi_rvalid  , // Read data valid
    (* MARK_DEBUG="true" *) output          s_axi_rready   // Read data ready
);
    //==============================================================
    // FIFO control signals (Write FIFO)
    //==============================================================

    localparam  AXI_DATA_W = DDR3_WITH;          // 128 by default
    localparam  AXI_STRB_W = AXI_DATA_W / 8;     // 16 when AXI_DATA_W=128
    localparam  AXI_ADDR_W = 28;

    wire                    w_wr_fifo_rd_en       ;
    wire [AXI_DATA_W-1:0]   w_wr_fifo_dout        ;
    wire [$clog2(WR_FIFO_DEPTH+1)-1:0] w_wfifo_rd_data_count ;
    wire [$clog2(WR_FIFO_DEPTH+1)-1:0] w_wfifo_wr_data_count ;

    //==============================================================
    // FIFO control signals (Read FIFO)
    //==============================================================

    wire                    w_rd_fifo_wr_en       ;
    wire [AXI_DATA_W-1:0]   w_rd_fifo_din         ;
    wire                    w_rd_fifo_empty       ;
    wire [$clog2(RD_FIFO_DEPTH+1)-1:0] w_rfifo_rd_data_count ;
    wire [$clog2(RD_FIFO_DEPTH+1)-1:0] w_rfifo_wr_data_count ;
    wire                    w_rd_fifo_rd_en       ;
    wire [AXI_DATA_W-1:0]   w_rd_fifo_dout        ;

    //==============================================================
    // Write State Machine
    //==============================================================

    reg  [7:0]              r_wr_state_current    ;
    reg  [7:0]              r_wr_state_next       ;

    reg  [27:0]             ri_user_wr_addr_base  ;
    reg  [15:0]             r_wr_burst_num_cnt    ;

    //==============================================================
    // Write Burst Control Signals
    //==============================================================

    reg                     r_wr_burst_flag       ;
    reg                     r_wr_burst_flag_d1    ;
    wire                    w_pos_wr_burst_flag   ;

    //================ Write address channel control signals ================
    reg [AXI_ADDR_W-1:0]    r_axi_awaddr   ;
    reg                     r_axi_awvalid  ;

    //================ Write data channel ==================================
    reg [AXI_DATA_W-1:0]    r_axi_wdata    ;
    reg                     r_axi_wlast    ;
    reg [15:0]              r_axi_wr_cnt   ;
    reg                     r_axi_wr_flag  ;
    reg                     ro_user_wr_finish;

    //================ Read state machine ==================================
    reg [7:0]               r_rd_state_current ;
    reg [7:0]               r_rd_state_next    ;

    reg [AXI_ADDR_W-1:0]    ri_user_rd_addr_base ;
    reg [15:0]              r_rd_burst_num_cnt   ;

    reg                     r_rd_burst_flag      ;
    reg                     r_rd_burst_flag_d1   ;
    wire                    w_pos_rd_burst_flag  ;

    //---------------- Read address channel control ----------------
    reg  [AXI_ADDR_W-1:0]   r_axi_araddr  ;
    reg                     r_axi_arvalid ;

    //---------------- Read control ----------------
    reg  [15:0]             r_axi_rd_cnt   ;
    reg                     r_axi_rd_flag  ;

    reg                     ro_user_rd_finish;
    reg  [31:0]             r_rfifo_rd_cnt  ;

    //---------------- AXI handshake helpers ----------------
    reg                     r_axi_rready   ;

    //---------------- State encoding ----------------
    parameter P_STATE_WR_INIT  = 'd0;
    parameter P_STATE_WR_IDLE  = 'd1;
    parameter P_STATE_WR_WRITE = 'd2;

    parameter P_STATE_RD_INIT  = 'd0;
    parameter P_STATE_RD_IDLE  = 'd1;
    parameter P_STATE_RD       = 'd2;

    //---------------- Address increment & total read beats ----------------
    parameter P_WR_INCR_ADDR = P_WR_BURST_LEN * AXI_STRB_W;
    parameter P_RD_INCR_ADDR = P_RD_BURST_LEN * AXI_STRB_W;
    parameter P_RD_DATA_NUM  = P_RD_BURST_LEN * P_RD_BURST_NUM;

    // ----------------- MIG control pins -----------------
    assign aresetn     = i_rst_n;
    assign app_sr_req  = 1'b0;
    assign app_ref_req = 1'b0;
    assign app_zq_req  = 1'b0;

    // ----------------- User status/outputs -----------------
    assign o_user_wr_finish     = ro_user_wr_finish;
    assign o_user_rd_finish     = ro_user_rd_finish;

    assign o_user_rd_data_valid = w_rd_fifo_rd_en;
    assign o_user_rd_data       = w_rd_fifo_dout;

    // ----------------- AXI Write Address Channel -----------------
    assign s_axi_awaddr  = r_axi_awaddr;
    assign s_axi_awvalid = r_axi_awvalid;

    assign s_axi_awid     = 4'd4;
    assign s_axi_awlen    = P_WR_BURST_LEN - 8'd1;
    assign s_axi_awsize   = 3'd4;
    assign s_axi_awburst  = 2'b01;
    assign s_axi_awlock   = 1'b0;
    assign s_axi_awcache  = 4'b0010;
    assign s_axi_awprot   = 3'b000;
    assign s_axi_awqos    = 4'b0000;

    wire w_wr_fifo_rvalid;
    assign s_axi_wdata  = w_wr_fifo_dout;
    assign s_axi_wstrb  = {AXI_STRB_W{1'b1}};
    assign s_axi_wvalid = r_axi_wr_flag && w_wr_fifo_rvalid;
    assign w_wr_fifo_rd_en = s_axi_wvalid && s_axi_wready;

    //================ AXI Write Response Channel ================
    assign s_axi_bready    = 1'b1;

    //================ AXI Read Address Channel ==================
    assign s_axi_araddr   = r_axi_araddr;
    assign s_axi_arvalid  = r_axi_arvalid;
    assign s_axi_rready   = r_axi_rready;

    assign s_axi_arid     = 4'd4;
    assign s_axi_arlen    = P_RD_BURST_LEN - 8'd1;
    assign s_axi_arsize   = 3'd4;
    assign s_axi_arburst  = 2'b01;
    assign s_axi_arlock   = 1'b0;
    assign s_axi_arcache  = 4'b0010;
    assign s_axi_arprot   = 3'b000;
    assign s_axi_arqos    = 4'b0000;


    async_fifo #(
        .WIDTH    (DDR3_WITH),
        .DEPTH    (WR_FIFO_DEPTH),
        .AF_DEPTH (WR_FIFO_DEPTH-2),
        .AE_DEPTH (2)
    ) WR_FIFO (
        .rst_n          (i_rst_n),

        .w_clk          (i_user_wr_clk),
        .w_data         (i_user_wr_data),
        .w_enq          (i_user_wr_data_valid),
        .w_full         (),
        .w_almost_full  (),
        .wr_data_count  (w_wfifo_wr_data_count),

        .r_clk          (i_clk),
        .r_deq          (w_wr_fifo_rd_en),
        .r_data         (w_wr_fifo_dout),
        .r_empty        (),
        .r_almost_empty (),
        .r_valid        (w_wr_fifo_rvalid),
        .rd_data_count  (w_wfifo_rd_data_count)
    );

    assign o_user_wr_fifo_ready = (w_wfifo_wr_data_count <= (WR_FIFO_DEPTH - P_WR_BURST_LEN));

    /*-------------------- write --------------------*/

    // Write state machine
    always @(posedge i_clk or negedge i_rst_n)
    begin
        if (!i_rst_n)
            r_wr_state_current <= P_STATE_WR_INIT;
        else
            r_wr_state_current <= r_wr_state_next;
    end


    always @(*)
    begin
        case (r_wr_state_current)

            P_STATE_WR_INIT :
                r_wr_state_next <= init_calib_complete ?
                                   P_STATE_WR_IDLE :
                                   P_STATE_WR_INIT;

            P_STATE_WR_IDLE :
                r_wr_state_next <= i_user_wr_valid ?
                                   P_STATE_WR_WRITE :
                                   P_STATE_WR_IDLE;

            P_STATE_WR_WRITE :
                r_wr_state_next <= s_axi_wvalid  && s_axi_wready &&
                                   r_axi_wr_cnt == (P_WR_BURST_LEN - 1) &&
                                   r_wr_burst_num_cnt == (P_WR_BURST_NUM - 1) ?
                                   P_STATE_WR_IDLE : P_STATE_WR_WRITE;

            default :
                r_wr_state_next <= P_STATE_WR_INIT;

        endcase
    end

    // Save write base address
    always @(posedge i_clk or negedge i_rst_n)
    begin
        if (!i_rst_n)
            ri_user_wr_addr_base <= 'd0;
        else if (i_user_wr_valid)
            ri_user_wr_addr_base <= i_user_wr_addr_base;
        else
            ri_user_wr_addr_base <= ri_user_wr_addr_base;
    end


    // Write burst number counter
    always @(posedge i_clk or negedge i_rst_n)
    begin
        if (!i_rst_n)
            r_wr_burst_num_cnt <= 'd0;

        else if (s_axi_wvalid && s_axi_wready &&
                 r_axi_wr_cnt == (P_WR_BURST_LEN - 1) &&
                 r_wr_burst_num_cnt == (P_WR_BURST_NUM - 1))
            r_wr_burst_num_cnt <= 'd0;

        else if (s_axi_wvalid && s_axi_wready &&
                 r_axi_wr_cnt == (P_WR_BURST_LEN - 1))
            r_wr_burst_num_cnt <= r_wr_burst_num_cnt + 'd1;

        else
            r_wr_burst_num_cnt <= r_wr_burst_num_cnt;
    end

    always @(posedge i_clk or negedge i_rst_n)
    begin
        if (!i_rst_n)
            r_wr_burst_flag <= 'd0;
        else if (r_wr_burst_flag && s_axi_wvalid && s_axi_wready && r_axi_wr_cnt==(P_WR_BURST_LEN-1))
            r_wr_burst_flag <= 'd0;
        else if (r_wr_state_current== P_STATE_WR_WRITE && w_wfifo_rd_data_count >= (P_WR_BURST_LEN-1))
            r_wr_burst_flag <= 'd1;
        else
            r_wr_burst_flag <= r_wr_burst_flag;
    end


    always @(posedge i_clk or negedge i_rst_n)
    begin
        if (!i_rst_n)
            r_wr_burst_flag_d1 <= 'd0;
        else
            r_wr_burst_flag_d1 <= r_wr_burst_flag;
    end

    assign w_pos_wr_burst_flag = r_wr_burst_flag & ~r_wr_burst_flag_d1;

    // AXI4 Interface - Write Address Channel
    always @(posedge i_clk or negedge i_rst_n)
    begin
        if (!i_rst_n) begin
            r_axi_awaddr  <= 'd0;
            r_axi_awvalid <= 'd0;
        end
        else if (w_pos_wr_burst_flag && r_wr_burst_num_cnt == 'd0) begin
            r_axi_awvalid <= 'd1;
            r_axi_awaddr  <= ri_user_wr_addr_base;
        end
        else if (w_pos_wr_burst_flag) begin
            r_axi_awvalid <= 'd1;
        end
        else if (s_axi_awready && r_axi_awvalid) begin
            r_axi_awaddr  <= r_axi_awaddr + P_WR_INCR_ADDR;
            r_axi_awvalid <= 'd0;
        end
        else begin
            r_axi_awaddr  <= r_axi_awaddr;
            r_axi_awvalid <= r_axi_awvalid;
        end
    end

    // Beat counter inside one write burst
    always @(posedge i_clk or negedge i_rst_n)
    begin
        if (!i_rst_n) begin
            r_axi_wr_cnt <= 16'd0;
        end
        else if (r_axi_wr_flag && s_axi_wvalid && s_axi_wready) begin
            if (r_axi_wr_cnt == (P_WR_BURST_LEN - 1))
                r_axi_wr_cnt <= 16'd0;
            else
                r_axi_wr_cnt <= r_axi_wr_cnt + 16'd1;
        end
    end

    // Write data phase flag
    always @(posedge i_clk or negedge i_rst_n)
    begin
        if (!i_rst_n) begin
            r_axi_wr_flag <= 1'b0;
        end
        else if (r_axi_wr_flag && s_axi_wvalid && s_axi_wready &&
                 (r_axi_wr_cnt == (P_WR_BURST_LEN - 1))) begin
            r_axi_wr_flag <= 1'b0;
        end
        else if (r_axi_awvalid && s_axi_awready) begin
            r_axi_wr_flag <= 1'b1;
        end
    end

    assign s_axi_wlast = r_axi_wr_flag && (r_axi_wr_cnt == (P_WR_BURST_LEN - 1));

    // Write finish flag
    always @(posedge i_clk or negedge i_rst_n)
    begin
        if (!i_rst_n)
            ro_user_wr_finish <= 'd0;
        else if (s_axi_wvalid && s_axi_wready &&
                 r_axi_wr_cnt==(P_WR_BURST_LEN - 1) &&
                 r_wr_burst_num_cnt==(P_WR_BURST_NUM - 1))
            ro_user_wr_finish <= 'd1;
        else
            ro_user_wr_finish <= 'd0;
    end


/*====================================================read====================================================*/


    //========================= RD_FIFO =========================
    async_fifo #(
        .WIDTH    (DDR3_WITH),
        .DEPTH    (RD_FIFO_DEPTH),
        .AF_DEPTH (RD_FIFO_DEPTH-2),
        .AE_DEPTH (2)
    ) RD_FIFO (
        .rst_n          (i_rst_n),

        .w_clk          (i_clk),
        .w_data         (w_rd_fifo_din),
        .w_enq          (w_rd_fifo_wr_en),
        .w_full         (),
        .w_almost_full  (),
        .wr_data_count  (w_rfifo_wr_data_count),

        .r_clk          (i_user_rd_clk),
        .r_deq          (w_rd_fifo_rd_en),
        .r_data         (w_rd_fifo_dout),
        .r_empty        (w_rd_fifo_empty),
        .r_almost_empty (),
        .r_valid        (),
        .rd_data_count  (w_rfifo_rd_data_count)
    );


    assign w_rd_fifo_wr_en = (r_rd_state_current == P_STATE_RD) && s_axi_rready && s_axi_rvalid;
    assign w_rd_fifo_din   = s_axi_rdata;
    assign w_rd_fifo_rd_en = ~w_rd_fifo_empty;

    always @(posedge i_clk or negedge i_rst_n)
    begin
        if (!i_rst_n)
            r_rd_state_current <= P_STATE_RD_INIT ;
        else
            r_rd_state_current <= r_rd_state_next ;
    end


    always @(*)
    begin
        case (r_rd_state_current)

            P_STATE_RD_INIT :
                r_rd_state_next <= init_calib_complete ?
                                   P_STATE_RD_IDLE :
                                   P_STATE_RD_INIT ;

            P_STATE_RD_IDLE :
                r_rd_state_next <= i_user_rd_valid ?
                                   P_STATE_RD :
                                   P_STATE_RD_IDLE ;

            P_STATE_RD :
                r_rd_state_next <= s_axi_rvalid && s_axi_rready &&
                                   r_axi_rd_cnt == (P_RD_BURST_LEN - 1) &&
                                   r_rd_burst_num_cnt == (P_RD_BURST_NUM - 1) ?
                                   P_STATE_RD_IDLE :
                                   P_STATE_RD ;

            default :
                r_rd_state_next <= P_STATE_RD_INIT ;

        endcase
    end

    // Latch the user read base address
    always @(posedge i_clk or negedge i_rst_n)
    begin
        if (!i_rst_n)
            ri_user_rd_addr_base <= 'd0;
        else if (i_user_rd_valid)
            ri_user_rd_addr_base <= i_user_rd_addr_base;
        else
            ri_user_rd_addr_base <= ri_user_rd_addr_base;
    end

    // Read burst transaction counter
    always @(posedge i_clk or negedge i_rst_n)
    begin
        if (!i_rst_n)
            r_rd_burst_num_cnt <= 'd0;

        else if (s_axi_rvalid && s_axi_rready &&
                 r_axi_rd_cnt == (P_RD_BURST_LEN - 1) &&
                 r_rd_burst_num_cnt == (P_RD_BURST_NUM - 1))
            r_rd_burst_num_cnt <= 'd0;

        else if (s_axi_rvalid && s_axi_rready &&
                 r_axi_rd_cnt == (P_RD_BURST_LEN - 1))
            r_rd_burst_num_cnt <= r_rd_burst_num_cnt + 'd1;

        else
            r_rd_burst_num_cnt <= r_rd_burst_num_cnt;
    end

    // Read burst start control flag
    always @(posedge i_clk or negedge i_rst_n)
    begin
        if (!i_rst_n)
            r_rd_burst_flag <= 'd0;

        else if (r_rd_burst_flag && s_axi_rvalid && s_axi_rready &&
                 r_axi_rd_cnt == (P_RD_BURST_LEN - 1))
            r_rd_burst_flag <= 'd0;

        else if (r_rd_state_current == P_STATE_RD &&
                 w_rfifo_wr_data_count <= (RD_FIFO_DEPTH - P_RD_BURST_LEN))
            r_rd_burst_flag <= 'd1;

        else
            r_rd_burst_flag <= r_rd_burst_flag;
    end

    always @(posedge i_clk or negedge i_rst_n)
    begin
        if (!i_rst_n)
            r_rd_burst_flag_d1 <= 'd0;
        else
            r_rd_burst_flag_d1 <= r_rd_burst_flag;
    end

    assign w_pos_rd_burst_flag = r_rd_burst_flag && ~r_rd_burst_flag_d1;

    // Read address channel
    always @(posedge i_clk or negedge i_rst_n)
    begin
        if (!i_rst_n) begin
            r_axi_araddr  <= 'd0;
            r_axi_arvalid <= 'd0;
        end
        else if (w_pos_rd_burst_flag && r_rd_burst_num_cnt == 'd0) begin
            r_axi_arvalid <= 'd1;
            r_axi_araddr  <= ri_user_rd_addr_base;
        end
        else if (w_pos_rd_burst_flag) begin
            r_axi_arvalid <= 'd1;
        end
        else if (s_axi_arready && r_axi_arvalid) begin
            r_axi_araddr  <= r_axi_araddr + P_RD_INCR_ADDR;
            r_axi_arvalid <= 'd0;
        end
        else begin
            r_axi_araddr  <= r_axi_araddr;
            r_axi_arvalid <= r_axi_arvalid;
        end
    end

    // Read data channel
    always @(posedge i_clk or negedge i_rst_n)
    begin
        if (!i_rst_n)
            r_axi_rd_cnt <= 'd0;
        else if (r_axi_rready && s_axi_rvalid &&
                 r_axi_rd_cnt == (P_RD_BURST_LEN - 1))
            r_axi_rd_cnt <= 'd0;
        else if (r_axi_rready && s_axi_rvalid)
            r_axi_rd_cnt <= r_axi_rd_cnt + 'd1;
        else
            r_axi_rd_cnt <= r_axi_rd_cnt;
    end

    always @(posedge i_clk or negedge i_rst_n)
    begin
        if (!i_rst_n)
            r_axi_rd_flag <= 'd0;

        else if (r_axi_rd_flag && s_axi_rvalid && s_axi_rready &&
                 r_axi_rd_cnt == (P_RD_BURST_LEN - 1))
            r_axi_rd_flag <= 'd0;

        else if (s_axi_arready && r_axi_arvalid)
            r_axi_rd_flag <= 'd1;

        else
            r_axi_rd_flag <= r_axi_rd_flag;
    end

    always @(posedge i_clk or negedge i_rst_n)
    begin
        if (!i_rst_n)
            r_axi_rready <= 'd0;

        else if (r_axi_rready && s_axi_rvalid &&
                 r_axi_rd_cnt == (P_RD_BURST_LEN - 1))
            r_axi_rready <= 'd0;

        else if (s_axi_arready && r_axi_arvalid)
            r_axi_rready <= 'd1;

        else
            r_axi_rready <= r_axi_rready;
    end

    // Count the number of data words read from RD FIFO
    always @(posedge i_user_rd_clk or negedge i_rst_n)
    begin
        if (!i_rst_n)
            r_rfifo_rd_cnt <= 'd0;
        else if (w_rd_fifo_rd_en && r_rfifo_rd_cnt == (P_RD_DATA_NUM - 1))
            r_rfifo_rd_cnt <= 'd0;
        else if (w_rd_fifo_rd_en)
            r_rfifo_rd_cnt <= r_rfifo_rd_cnt + 'd1;
        else
            r_rfifo_rd_cnt <= r_rfifo_rd_cnt;
    end


    // Assert user read finish flag after all expected data words are read
    always @(posedge i_clk or negedge i_rst_n)
    begin
        if (!i_rst_n)
            ro_user_rd_finish <= 'd0;
        else if (w_rd_fifo_rd_en && r_rfifo_rd_cnt == (P_RD_DATA_NUM - 1))
            ro_user_rd_finish <= 'd1;
        else
            ro_user_rd_finish <= 'd0;
    end
endmodule