`timescale 1ns / 1ps

module uart_api_dc_tb;

    localparam DAC_WIDTH=16;
    localparam CYCLE_WIDTH=30;
    localparam STREAM_ITER_WIDTH=10;
    localparam CORE_ITER_WIDTH=10;
    localparam STREAM_DEPTH=2;
    localparam INSN_WIDTH=DAC_WIDTH*2+CORE_ITER_WIDTH+CYCLE_WIDTH;
    localparam CHANNEL_MES_WIDTH=96;
    localparam TOTAL_REGS=STREAM_DEPTH*3+2;

    localparam NUM_CHANNEL = 4;

    localparam UART_BAUD   = 921600;
    localparam real BIT_DUR = 1e9 / UART_BAUD;
    localparam CLK_PERIOD  = 10;

    // =======================================
    // DUT
    // =======================================
    logic w_clk, w_rst;
    logic w_rx;
    logic [NUM_CHANNEL-1:0] w_sclk_bus, w_mosi_bus, w_ldac_n_bus, w_cs_n_bus;

    uart_api_dc #(
        .DAC_WIDTH(DAC_WIDTH),
        .CYCLE_WIDTH(CYCLE_WIDTH),
        .DAC_CHANNEL(NUM_CHANNEL),
        .CHANNEL_MES_WIDTH(CHANNEL_MES_WIDTH),
        .STREAM_ITER_WIDTH(STREAM_ITER_WIDTH),
        .CORE_ITER_WIDTH(CORE_ITER_WIDTH),
        .DEPTH(STREAM_DEPTH)
    ) dut (
        .i_clk    (w_clk),
        .i_rst    (w_rst),
        .i_rx     (w_rx),
        .o_sclk   (w_sclk_bus),
        .o_mosi   (w_mosi_bus),
        .o_cs_n   (w_cs_n_bus),
        .o_ldac_n (w_ldac_n_bus)
    );

    logic [NUM_CHANNEL-1:0][DAC_WIDTH-1:0] vdc;

    for (genvar i = 0; i < NUM_CHANNEL; i++) begin : DC_DAC_GEN
        ad4451a DC_DAC (
            .i_sclk(w_sclk_bus[i]),
            .i_mosi(w_mosi_bus[i]),
            .i_cs_n(w_cs_n_bus[i]),
            .i_ldac_n(w_ldac_n_bus[i]),
            .o_vdc(vdc[i])
        );
    end

    // =======================================
    // Clock generation
    // =======================================
    initial begin
        w_clk = 1'b0;
        forever #(CLK_PERIOD/2.0) w_clk = ~w_clk;
    end

    // =======================================
    // UART byte transmit task
    // =======================================
    task automatic pc_tsmt (input logic [7:0] data);
        $display("data: %b", data);
        assert (data !== 8'bxxxxxxxx)
        else $fatal(1, "all x");
        w_rx = 1'b0; #(BIT_DUR);      // start bit
        for (int i = 0; i < 8; i++) begin
            w_rx = data[i];
            #(BIT_DUR);
        end
        w_rx = 1'b1; #(BIT_DUR);      // stop bit
    endtask

    // =======================================
    // Single-channel fixed data (channel 0 only)
    // =======================================
    logic [31:0] dc_regs_unpacked [0:NUM_CHANNEL-1][0:TOTAL_REGS-1];
    logic [31:0] launch_regs_unpacked [0:3];
    logic [NUM_CHANNEL-1:0] w_dc_empty_bus;
    logic [NUM_CHANNEL-1:0] w_dc_idle_bus;

    for (genvar i = 0; i < NUM_CHANNEL; i++) begin : GEN_EMPTY_IDLE
        assign w_dc_empty_bus[i] = dut.GEN_DC[i].u_dc.w_empty;
        assign w_dc_idle_bus[i] = dut.GEN_DC[i].u_dc.core.r_state == dut.GEN_DC[i].u_dc.core.IDLE;
    end

    logic dc_empty, dc_idle;
    assign dc_empty = w_dc_empty_bus == {(NUM_CHANNEL){1'b1}};
    assign dc_idle = w_dc_idle_bus == {(NUM_CHANNEL){1'b1}};

    string path;
    logic [31:0] header;
    logic tsmt_done;

    initial begin
        tsmt_done = 1'b0;
        for (int i = 0; i < NUM_CHANNEL; i++)
            for (int j = 0; j < TOTAL_REGS; j++)
                dc_regs_unpacked[i][j] = 'h0;

        for (int i = 0; i <= 3; i++)
            launch_regs_unpacked[i] = 'h0;

        w_rst = 1'b1;
        @(negedge w_clk);
        w_rst = 1'b0;

        repeat(5) @(negedge w_clk);

        repeat (10) begin

            $readmemb("../sw/dump/launch.txt", launch_regs_unpacked);

            // transmit activated dc channels
            for (int i = 0; i < NUM_CHANNEL; i++) begin

                if (launch_regs_unpacked[0][i]) begin

                    $display("i: %0d, NUM_CHANNEL: %0d", i, NUM_CHANNEL);

                    path = $sformatf("../sw/dump/dc%0d.txt", i);
                    $readmemb(path, dc_regs_unpacked[i]);

                    header = 32'hffff_ffff ^ (32'b1 << (i + 8));
                    $display("transmit byte 3 of header");
                    pc_tsmt(header[31:24]);
                    $display("transmit byte 2 of header");
                    pc_tsmt(header[23:16]);
                    $display("transmit byte 1 of header");
                    pc_tsmt(header[15:8]);
                    $display("transmit byte 0 of header");
                    pc_tsmt(header[7:0]);

                    for (int j = 0; j < TOTAL_REGS; j++) begin
                        $display("i: %0d, j: %0d, NUM_CHANNEL: %0d, TOTAL_REGS: %0d", i, j, NUM_CHANNEL, TOTAL_REGS);
                        $display("transmit byte 3 of dc_regs_unpacked[%0d][%0d]", i, j);
                        pc_tsmt(dc_regs_unpacked[i][j][31:24]);
                        $display("transmit byte 2 of dc_regs_unpacked[%0d][%0d]", i, j);
                        pc_tsmt(dc_regs_unpacked[i][j][23:16]);
                        $display("transmit byte 1 of dc_regs_unpacked[%0d][%0d]", i, j);
                        pc_tsmt(dc_regs_unpacked[i][j][15:8]);
                        $display("transmit byte 0 of dc_regs_unpacked[%0d][%0d]", i, j);
                        pc_tsmt(dc_regs_unpacked[i][j][7:0]);
                    end

                end
            end

            // transmit launch
            $display("transmit launch");
            header = 32'hffff_ffff;
            pc_tsmt(header[31:24]);
            pc_tsmt(header[23:16]);
            pc_tsmt(header[15:8]);
            pc_tsmt(header[7:0]);

            for (int i = 0; i < 4; i++) begin
                $display("transmit byte 3 of launch_regs_unpacked[%0d]", i);
                pc_tsmt(launch_regs_unpacked[i][31:24]);
                $display("transmit byte 2 of launch_regs_unpacked[%0d]", i);
                pc_tsmt(launch_regs_unpacked[i][23:16]);
                $display("transmit byte 1 of launch_regs_unpacked[%0d]", i);
                pc_tsmt(launch_regs_unpacked[i][15:8]);
                $display("transmit byte 0 of launch_regs_unpacked[%0d]", i);
                pc_tsmt(launch_regs_unpacked[i][7:0]);
            end

            tsmt_done = 1'b1;

            wait(dc_empty && dc_idle);
            @(negedge w_clk);
        end

        $finish;

    end

endmodule
