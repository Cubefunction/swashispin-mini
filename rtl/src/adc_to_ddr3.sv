`timescale 1ns / 1ps

module adc_to_ddr3 #(
    parameter integer ADC_WIDTH      = 20,
    parameter integer AXI_ADDR_WIDTH = 28,
    parameter integer AXI_DATA_WIDTH = 128,
    parameter [27:0]  BASE_ADDR      = 28'h0000000
)(
    // Global Clock and Reset 
    input  logic          clk,
    input  logic          rst_n,
    input  logic          init_calib_complete,

    // ADC Input Side
    input  logic [ADC_WIDTH-1:0] adc_data,
    input  logic                 adc_valid,

    // AXI4 Master 
    // Write Address Channel
    output logic [3:0]           m_axi_awid,
    output logic [27:0]          m_axi_awaddr,
    output logic [7:0]           m_axi_awlen,
    output logic [2:0]           m_axi_awsize,
    output logic [1:0]           m_axi_awburst,
    output logic                 m_axi_awvalid,
    input  logic                 m_axi_awready,

    // Write Data Channel
    output logic [127:0]         m_axi_wdata,
    output logic [15:0]          m_axi_wstrb,
    output logic                 m_axi_wlast,
    output logic                 m_axi_wvalid,
    input  logic                 m_axi_wready,

    // Write Response Channel
    input  logic                 m_axi_bvalid,
    output logic                 m_axi_bready
);

    // --- Internal Signals ---
    logic [AXI_DATA_WIDTH-1:0] packed_data;
    logic                      packed_valid;
    logic [AXI_ADDR_WIDTH-1:0] current_wr_addr;
    
    logic                      fifo_empty;
    logic                      fifo_deq;
    logic [AXI_ADDR_WIDTH-1:0] cmd_addr_from_fifo;
    
    logic                      master_wr_done;
    logic                      master_wr_ready;

    // ---  Data Width Converter (20 to 128 bit) ---
    data_width_converter #(
        .ADC_WIDTH(ADC_WIDTH),
        .AXI_WIDTH(AXI_DATA_WIDTH)
    ) u_conv (
        .clk            (clk),
        .rst_n          (rst_n),
        .adc_data       (adc_data),
        .adc_valid      (adc_valid),
        .data_to_axi    (packed_data),
        .data_pkg_valid (packed_valid)
    );

    // ---  Address Generation Logic ---
    // Increment address only when a new 128-bit package is ready
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_wr_addr <= BASE_ADDR;
        end else if (packed_valid) begin
            current_wr_addr <= current_wr_addr + 28'd16; // 128 bits = 16 bytes
        end
    end

    // --- Command FIFO (Buffers Write Addresses) ---
    fifo #(
        .WIDTH(AXI_ADDR_WIDTH),
        .DEPTH(16)
    ) u_cmd_fifo (
        .i_clk          (clk),
        .i_rst          (!rst_n),
        .i_data         (current_wr_addr),
        .i_enq          (packed_valid),
        .i_deq          (fifo_deq),
        .o_data         (cmd_addr_from_fifo),
        .o_empty        (fifo_empty),
        .o_full         (),
        .o_almost_full  (),
        .o_almost_empty ()
    );

    // --- AXI Master FSM ---
    axi_master_fsm #(
        .C_M_AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .C_M_AXI_DATA_WIDTH(AXI_DATA_WIDTH)
    ) u_master (
        .clk            (clk),
        .rst_n          (rst_n),
        .init_done      (init_calib_complete),

        // User Interface side
        .wr_req         (!fifo_empty),
        .wr_addr        (cmd_addr_from_fifo),
        .wr_data        (packed_data),
        .wr_done        (master_wr_done),
        .wr_ready       (master_wr_ready),

        // AXI Interface side
        .m_axi_awid     (m_axi_awid),
        .m_axi_awaddr   (m_axi_awaddr),
        .m_axi_awlen    (m_axi_awlen),
        .m_axi_awsize   (m_axi_awsize),
        .m_axi_awburst  (m_axi_awburst),
        .m_axi_awvalid  (m_axi_awvalid),
        .m_axi_awready  (m_axi_awready),
        .m_axi_wdata    (m_axi_wdata),
        .m_axi_wstrb    (m_axi_wstrb),
        .m_axi_wlast    (m_axi_wlast),
        .m_axi_wvalid   (m_axi_wvalid),
        .m_axi_wready   (m_axi_wready),
        .m_axi_bvalid   (m_axi_bvalid),
        .m_axi_bready   (m_axi_bready)
    );

    // Dequeue address from FIFO when the Master accepts the start of transaction
    assign fifo_deq = !fifo_empty && master_wr_ready;

endlogic
endmodule