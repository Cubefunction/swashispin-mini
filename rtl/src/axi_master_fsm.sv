`timescale 1ns / 1ps

/**
 * Module: axi_master_fsm
 * Description: A basic AXI4 Full Master FSM to interface with Xilinx MIG.
 * Designed for storing ADC data into DDR3 memory.
 */

module axi_master_fsm #(
    parameter integer C_M_AXI_ADDR_WIDTH = 28,
    parameter integer C_M_AXI_DATA_WIDTH = 128,
    parameter integer C_M_AXI_ID_WIDTH   = 4
)(
    // Global Control Signals
    input  logic                                 clk,           // UI Clock from MIG
    input  logic                                 rst_n,         // Active low reset
    input  logic                                 init_done,     // From MIG init_calib_complete

    // User Logic Interface
    input  logic                                 wr_req,        // Pulse to start a write
    input  logic [C_M_AXI_ADDR_WIDTH-1:0]        wr_addr,       
    input  logic [C_M_AXI_DATA_WIDTH-1:0]        wr_data,       
    output logic                                 wr_done,       // High when write transaction finished

    input  logic                                 rd_req,        // Pulse to start a read
    input  logic [C_M_AXI_ADDR_WIDTH-1:0]        rd_addr,       
    output logic [C_M_AXI_DATA_WIDTH-1:0]        rd_data_out,   
    output logic                                 rd_data_valid, // High when read data is ready

    // AXI4 Master Interface (Connect to MIG Slave Interface)
    // --- Write Address Channel ---
    output logic [C_M_AXI_ID_WIDTH-1:0]          m_axi_awid,
    output logic [C_M_AXI_ADDR_WIDTH-1:0]        m_axi_awaddr,
    output logic [7:0]                           m_axi_awlen,   // Burst length
    output logic [2:0]                           m_axi_awsize,  // Burst size
    output logic [1:0]                           m_axi_awburst, // Burst type
    output logic                                 m_axi_awvalid,
    input  logic                                 m_axi_awready,

    // --- Write Data Channel ---
    output logic [C_M_AXI_DATA_WIDTH-1:0]        m_axi_wdata,
    output logic [(C_M_AXI_DATA_WIDTH/8)-1:0]    m_axi_wstrb,
    output logic                                 m_axi_wlast,
    output logic                                 m_axi_wvalid,
    input  logic                                 m_axi_wready,

    // --- Write Response Channel ---
    input  logic                                 m_axi_bvalid,
    output logic                                 m_axi_bready,

    // --- Read Address Channel ---
    output logic [C_M_AXI_ID_WIDTH-1:0]          m_axi_arid,
    output logic [C_M_AXI_ADDR_WIDTH-1:0]        m_axi_araddr,
    output logic [7:0]                           m_axi_arlen,
    output logic [2:0]                           m_axi_arsize,
    output logic [1:0]                           m_axi_arburst,
    output logic                                 m_axi_arvalid,
    input  logic                                 m_axi_arready,

    // --- Read Data Channel ---
    input  logic [C_M_AXI_DATA_WIDTH-1:0]        m_axi_rdata,
    input  logic                                 m_axi_rvalid,
    input  logic                                 m_axi_rlast,
    output logic                                 m_axi_rready
);

    // SystemVerilog Enumeration for FSM States
    typedef enum logic [2:0] {
        ST_IDLE       = 3'b000,
        ST_WRITE_ADDR = 3'b001,
        ST_WRITE_DATA = 3'b010,
        ST_WRITE_RESP = 3'b011,
        ST_READ_ADDR  = 3'b100,
        ST_READ_DATA  = 3'b101,
        ST_DONE       = 3'b110
    } state_t;

    state_t state;

    // Fixed AXI configuration for DDR3 Single Access
    assign m_axi_awid    = '0;
    assign m_axi_awlen   = 8'd0;        // Single beat (1 burst)
    assign m_axi_awsize  = 3'b100;      // 128-bit (16 Bytes)
    assign m_axi_awburst = 2'b01;       // INCR
    assign m_axi_wstrb   = '1;          // All bytes enabled
    assign m_axi_wlast   = 1'b1;
    assign m_axi_bready  = 1'b1;

    assign m_axi_arid    = '0;
    assign m_axi_arlen   = 8'd0;
    assign m_axi_arsize  = 3'b100;
    assign m_axi_arburst = 2'b01;
    assign m_axi_rready  = 1'b1;

    // Address and Data Assignments
    assign m_axi_awaddr  = wr_addr;
    assign m_axi_wdata   = wr_data;
    assign m_axi_araddr  = rd_addr;

    // --- Main FSM Logic ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            m_axi_awvalid <= 1'b0;
            m_axi_wvalid  <= 1'b0;
            m_axi_arvalid <= 1'b0;
            wr_done       <= 1'b0;
            rd_data_valid <= 1'b0;
            rd_data_out   <= '0;
        end else begin
            case (state)
                // Wait for Calibration and User Request
                ST_IDLE: begin
                    wr_done       <= 1'b0;
                    rd_data_valid <= 1'b0;
                    if (init_done) begin
                        if (wr_req) begin
                            state <= ST_WRITE_ADDR;
                            m_axi_awvalid <= 1'b1;
                        end else if (rd_req) begin
                            state <= ST_READ_ADDR;
                            m_axi_arvalid <= 1'b1;
                        end
                    end
                end

                // AW Channel Handshake
                ST_WRITE_ADDR: begin
                    if (m_axi_awready) begin
                        m_axi_awvalid <= 1'b0;
                        m_axi_wvalid  <= 1'b1;
                        state         <= ST_WRITE_DATA;
                    end
                end

                // W Channel Handshake
                ST_WRITE_DATA: begin
                    if (m_axi_wready) begin
                        m_axi_wvalid <= 1'b0;
                        state        <= ST_WRITE_RESP;
                    end
                end

                // B Channel (Wait for Ack)
                ST_WRITE_RESP: begin
                    if (m_axi_bvalid) begin
                        wr_done <= 1'b1; // Notify user logic write is complete
                        state   <= ST_DONE;
                    end
                end

                // AR Channel Handshake
                ST_READ_ADDR: begin
                    if (m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        state         <= ST_READ_DATA;
                    end
                end

                // R Channel (Capture Data)
                ST_READ_DATA: begin
                    if (m_axi_rvalid) begin
                        rd_data_out   <= m_axi_rdata;
                        rd_data_valid <= 1'b1;
                        state         <= ST_DONE;
                    end
                end

                ST_DONE: begin
                    wr_done       <= 1'b0;
                    rd_data_valid <= 1'b0;
                    state         <= ST_IDLE;
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule