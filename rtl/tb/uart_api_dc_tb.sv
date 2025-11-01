`timescale 1ns / 1ps

module uart_api_dc_tb;

    localparam FRAME_WORDS = 62;
    localparam UART_BAUD   = 115200;
    localparam real BIT_DUR = 1e9 / UART_BAUD;
    localparam CLK_PERIOD  = 10;

    // =======================================
    // DUT
    // =======================================
    logic w_clk, w_rst;
    logic w_rx, w_tx;
    logic w_sclk, w_mosi, w_ldac_n;
    logic [23:0] w_cs_n;

    uart_api_dc dut (
        .i_clk    (w_clk),
        .i_rst    (w_rst),
        .i_rx     (w_rx),
        .o_tx     (w_tx),
        .o_sclk   (w_sclk),
        .o_mosi   (w_mosi),
        .o_cs_n   (w_cs_n),
        .o_ldac_n (w_ldac_n)
    );

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
    logic [31:0] frame_data [0:FRAME_WORDS-1];

    initial begin
        // Header (bit 31 == 0 for channel 0)
        frame_data[0] = 32'h7FFFFFFF;

        // 61 payload words (固定内容)
        frame_data[1]  = 32'h12345678;
        frame_data[2]  = 32'h9ABCDEF0;
        frame_data[3]  = 32'h00010002;
        frame_data[4]  = 32'h00030004;
        frame_data[5]  = 32'h00050006;
        frame_data[6]  = 32'h00070008;
        frame_data[7]  = 32'h0009000A;
        frame_data[8]  = 32'h000B000C;
        frame_data[9]  = 32'h000D000E;
        frame_data[10] = 32'h000F0010;
        frame_data[11] = 32'h00110012;
        frame_data[12] = 32'h00130014;
        frame_data[13] = 32'h00150016;
        frame_data[14] = 32'h00170018;
        frame_data[15] = 32'h0019001A;
        frame_data[16] = 32'h001B001C;
        frame_data[17] = 32'h001D001E;
        frame_data[18] = 32'h001F0020;
        frame_data[19] = 32'h00210022;
        frame_data[20] = 32'h00230024;
        frame_data[21] = 32'h00250026;
        frame_data[22] = 32'h00270028;
        frame_data[23] = 32'h0029002A;
        frame_data[24] = 32'h002B002C;
        frame_data[25] = 32'h002D002E;
        frame_data[26] = 32'h002F0030;
        frame_data[27] = 32'h00310032;
        frame_data[28] = 32'h00330034;
        frame_data[29] = 32'h00350036;
        frame_data[30] = 32'h00370038;
        frame_data[31] = 32'h0039003A;
        frame_data[32] = 32'h003B003C;
        frame_data[33] = 32'h003D003E;
        frame_data[34] = 32'h003F0040;
        frame_data[35] = 32'h00410042;
        frame_data[36] = 32'h00430044;
        frame_data[37] = 32'h00450046;
        frame_data[38] = 32'h00470048;
        frame_data[39] = 32'h0049004A;
        frame_data[40] = 32'h004B004C;
        frame_data[41] = 32'h004D004E;
        frame_data[42] = 32'h004F0050;
        frame_data[43] = 32'h00510052;
        frame_data[44] = 32'h00530054;
        frame_data[45] = 32'h00550056;
        frame_data[46] = 32'h00570058;
        frame_data[47] = 32'h0059005A;
        frame_data[48] = 32'h005B005C;
        frame_data[49] = 32'h005D005E;
        frame_data[50] = 32'h005F0060;
        frame_data[51] = 32'h00610062;
        frame_data[52] = 32'h00630064;
        frame_data[53] = 32'h00650066;
        frame_data[54] = 32'h00670068;
        frame_data[55] = 32'h0069006A;
        frame_data[56] = 32'h006B006C;
        frame_data[57] = 32'h006D006E;
        frame_data[58] = 32'h006F0070;
        frame_data[59] = 32'h00710072;
        frame_data[60] = 32'h00730074;
        frame_data[61] = 32'h00750076;
    end

    // =======================================
    // Main stimulus: send channel-0 frame only
    // =======================================
    initial begin
        w_rst = 1'b0;
        w_rx  = 1'b1;
        repeat(20) @(negedge w_clk);
        w_rst = 1'b1;

        $display("---- Sending fixed frame for Channel 0 ----");

        for (int i = 0; i < FRAME_WORDS; i++) begin
            pc_tsmt(frame_data[i][31:24]);
            pc_tsmt(frame_data[i][23:16]);
            pc_tsmt(frame_data[i][15:8]);
            pc_tsmt(frame_data[i][7:0]);
        end

        #(BIT_DUR * 200);
        $display("Channel 0 frame transmitted successfully.");
        $finish;
    end

endmodule
