`default_nettype none
`timescale 1ns / 1ps
`include "include/dc.svh"
`include "include/launch.svh"

import "DPI-C" function int cmd_open(input string path);
import "DPI-C" function int cmd_accept_poll(input int timeout_ms);
import "DPI-C" function int cmd_getline(output byte unsigned line_buf[]);

module simulator;

    // define number of dc/li channels
    localparam NUM_DC_CHANNEL=24;

    localparam TOTAL_REGS=DC_SEQ_REGS+DC_CTRL_REGS+LCH_TOTAL_REGS;

    /********************
    * signal declaration
    ********************/

    // clocks and reset
    logic w_clk, w_rst;

    // data transmit
    logic w_rx, w_tx;
    logic [0:TOTAL_REGS-1][31:0] w_regs;

    // dc spi bus
    logic [0:NUM_DC_CHANNEL-1] w_dc_sclk_bus;
    logic [0:NUM_DC_CHANNEL-1] w_dc_mosi_bus;
    logic [0:NUM_DC_CHANNEL-1] w_dc_miso_bus;
    logic [0:NUM_DC_CHANNEL-1] w_dc_cs_n_bus;
    logic [0:NUM_DC_CHANNEL-1] w_dc_ldac_n_bus;

    logic [0:NUM_DC_CHANNEL-1] w_dc_empty_bus;

    // dc voltage output
    logic [DC_DAC_WIDTH-1:0] vdc_digital [NUM_DC_CHANNEL];
    real vdc [NUM_DC_CHANNEL];

    /********************************
    * top-level module instantiation
    ********************************/

    uart_regs #(
        .DATA_WIDTH(8),
        .RX_FIFO_DEPTH(8),
        .RX_FIFO_AF_DEPTH(6),
        .RX_FIFO_AE_DEPTH(2),
        .TX_FIFO_DEPTH(8),
        .TX_FIFO_AF_DEPTH(6),
        .TX_FIFO_AE_DEPTH(2),
        .NUM_REGS(TOTAL_REGS)
    ) REGS (
        .i_clk(w_clk),
        .i_rst(w_rst),
        .i_rx(w_rx),
        .o_tx(w_tx),
        .i_dvsr(11'd6),
        .o_regs(w_regs)
    );


    processor #(
        .NUM_DC_CHANNEL(NUM_DC_CHANNEL)
    ) PROCESSOR (
        .i_clk(w_clk),
        .i_rst(w_rst),

        // dc
        .i_regs(w_regs),

        .o_dc_sclk_bus(w_dc_sclk_bus),
        .o_dc_mosi_bus(w_dc_mosi_bus),
        .i_dc_miso_bus(w_dc_miso_bus),
        .o_dc_cs_n_bus(w_dc_cs_n_bus),
        .o_dc_ldac_n_bus(w_dc_ldac_n_bus),

        .o_dc_armed_bus(),
        .o_dc_empty_bus(w_dc_empty_bus),
        .o_dc_eop_bus()
    );

    /*******************
    * dac instantiation
    ********************/

    // dc axil reg and dac instantiation
    for (genvar i = 0; i < NUM_DC_CHANNEL; i++) begin : DC_IO_GEN

        ad5791 DAC (
            .SCLK(w_dc_sclk_bus[i]),
            .SDIN(w_dc_mosi_bus[i]),
            .SYNC_N(w_dc_cs_n_bus[i]),
            .SDO(w_dc_miso_bus[i]),
            .LDAC_N(w_dc_ldac_n_bus[i]),

            .CLR_N(1'b1),
            .RESET_N(1'b1),

            .VDIGITAL(vdc_digital[i]),
            .VOUT(vdc[i])
        );

    end

    /*****************
    * clock and reset
    ******************/

    initial begin
        w_clk = 1'b0;
        forever #5 w_clk = !w_clk;
    end

    initial begin
        w_rst = 1'b1;
        @(negedge w_clk);
        w_rst = 1'b0;
    end

    /************
    * uart tasks
    *************/

    localparam bit_duration = 1085.069;
    task pc_tsmt(input logic [7:0] data);
        // start bit = 0
        w_rx = 1'b0;
        #bit_duration;

        // data bits
        for (int i = 0; i < 8; i++) begin
            w_rx = data[i];
            #bit_duration;
        end

        // end bit = 1
        w_rx = 1'b1;
        #bit_duration;
    endtask

    logic [7:0] pc_received [$];
    logic [7:0] rx_data;

    task pc_recv;

        // start bit == 0
        @(negedge w_tx);
        #(bit_duration / 2);
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

        pc_received.push_back(rx_data);

    endtask

    /******************
    * socket interface
    ******************/

    logic [7:0] tx_data;
    longint unsigned t;
    int rc;
    localparam LINE_MAX = 512;
    byte unsigned line_buf[LINE_MAX];
    string line;

    function automatic string bytes2string(input byte unsigned b[]);
        string s = "";
        for (int i = 0; i < b.size(); i++) begin
            if (b[i] == 0) break;           // stop at NUL
            s = {s, byte'(b[i])};
        end
        return s;
    endfunction

    task wait_client;
        $display("Waiting for command connection...");
        forever begin
            if (cmd_accept_poll(100) == 0)
                break;
        end
        $display("Client connected");
    endtask

    initial begin
        rc = cmd_open("/tmp/tb_cmd.sock");
        if (rc != 0) $fatal("cmd_open failed");

        wait_client;

        forever begin

            rc = cmd_getline(line_buf);

            if (rc == 1) begin
                line = bytes2string(line_buf);
                $display("tx_data: %s", line);

                if ($sscanf(line, "0x%4h", tx_data) == 1) begin
                    pc_tsmt(tx_data);
                end
                else if ($sscanf(line, "run %d", t) == 1) begin
                    repeat (t/10) @(negedge w_clk);
                end
                else begin
                    $display("Unknown command: %s", line);
                end

            end else if (rc == 0) begin
                $display("Client disconnected, waiting...");
                wait_client;
            end else begin
                $fatal("cmd_getline error");
            end
        end
    end

endmodule

