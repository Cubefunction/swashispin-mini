`timescale 1ns/1ps

//==============================================================================
// uart_top (board-level top)
//==============================================================================
module uart_top #(
    parameter int DATA_WIDTH         = 8,
    parameter int RX_FIFO_DEPTH      = 8,
    parameter int RX_FIFO_AF_DEPTH   = 6,
    parameter int RX_FIFO_AE_DEPTH   = 2,
    parameter int TX_FIFO_DEPTH      = 8,
    parameter int TX_FIFO_AF_DEPTH   = 6,
    parameter int TX_FIFO_AE_DEPTH   = 2,
    parameter int NUM_REGS           = 64,

    // AD9833 register map
    parameter int AD9833_BASE_ADDR   = 0,
    parameter int SPI_FRAME_W        = 16,
    parameter int SPI_CLK_DIV        = 65535,

    // ADC core / top register map
    parameter int ADC_CORE_BASE_ADDR = 4,
    parameter int ADC_CORE_NUM_REGS  = 54,
    parameter int ADC_CTRL_REG_IDX   = 53,

    // ADC front-end (sine model)
    parameter int ADC_DATA_W         = 16,
    parameter int ADC_LUT_DEPTH      = 256,
    parameter int ADC_SAMPLE_GAP     = 8,
    parameter int ADC_PHASE_STEP     = 4,

    // DDR3 user interface
    parameter int                     DDR_DATA_W     = 128,
    parameter int                     DDR_ADDR_W     = 28,
    parameter int                     P_WR_BURST_LEN = 8,
    parameter int                     P_WR_BURST_NUM = 1,
    parameter int                     P_RD_BURST_LEN = 8,
    parameter int                     P_RD_BURST_NUM = 1,
    parameter int                     WR_FIFO_DEPTH  = 64,
    parameter int                     RD_FIFO_DEPTH  = 64,
    parameter logic [DDR_ADDR_W-1:0]  DDR_BASE_ADDR  = '0
)(
    //==========================================================================
    // Board IO
    //==========================================================================
    input  logic                         i_clk,         // 100 MHz board clock
    input  logic                         i_rst_n,       // active-low reset

    // UART
    input  logic                         i_rx,
    output logic                         o_tx,

    // AD9833 SPI
    output logic                         o_spi_sclk,
    output logic                         o_spi_fsync,
    output logic                         o_spi_mosi,

    //==========================================================================
    // DDR3 PHY pins (to the chip)
    //==========================================================================
    output logic [13:0]                  ddr3_addr,
    output logic [2:0]                   ddr3_ba,
    output logic                         ddr3_cas_n,
    output logic [0:0]                   ddr3_ck_n,
    output logic [0:0]                   ddr3_ck_p,
    output logic [0:0]                   ddr3_cke,
    output logic                         ddr3_ras_n,
    output logic                         ddr3_reset_n,
    output logic                         ddr3_we_n,
    inout  wire  [15:0]                  ddr3_dq,
    inout  wire  [1:0]                   ddr3_dqs_n,
    inout  wire  [1:0]                   ddr3_dqs_p,
    output logic [0:0]                   ddr3_cs_n,
    output logic [1:0]                   ddr3_dm,
    output logic [0:0]                   ddr3_odt,

    //==========================================================================
    // Status / debug (for LEDs or ILA)
    //==========================================================================
    output logic                         o_pll_locked,
    output logic                         o_init_calib_complete,
    output logic                         o_mmcm_locked,
    output logic                         o_user_wr_fifo_ready,
    output logic                         o_wr_fifo_stuck,       // sticky: WR FIFO was ever not-ready when a write was attempted

    output logic                         o_adc_sampling,
    output logic                         o_adc_active,

    // Raw ADC stream (optional debug probes)
    output logic signed [ADC_DATA_W-1:0] o_adc_data,
    output logic                         o_adc_data_valid,
    output logic                         o_adc_spi_finish
);

    //==========================================================================
    // Clock generation (clk_wiz_0) - feeds the MIG
    //==========================================================================
    logic clk_ddr3_100;    // 100 MHz -> MIG sys_clk_i
    logic clk_ref_200;     // 200 MHz -> MIG clk_ref_i
    logic pll_locked;

    clk_wiz_0 sys_clk_gen (
        .clk_out1 (clk_ddr3_100),   // 100 MHz
        .clk_out2 (clk_ref_200),    // 200 MHz
        .resetn   (i_rst_n),
        .locked   (pll_locked),
        .clk_in1  (i_clk)
    );

    assign o_pll_locked = pll_locked;

    //==========================================================================
    // ui_clk / ui_clk_sync_rst come out of ddr3_top (MIG)
    //==========================================================================
    logic w_ui_clk;
    logic w_ui_clk_sync_rst;        // active-high, synchronous to w_ui_clk
    logic w_init_calib_complete;
    logic w_mmcm_locked;

    assign o_init_calib_complete = w_init_calib_complete;
    assign o_mmcm_locked         = w_mmcm_locked;
    assign o_user_wr_fifo_ready  = w_user_wr_fifo_ready;

    //==========================================================================
    // User-domain reset (active high / active low)
    //   ui_clk_sync_rst is already properly synchronous to ui_clk.
    //==========================================================================
    logic w_user_rst;
    logic w_user_rst_n;

    assign w_user_rst   =  w_ui_clk_sync_rst;
    assign w_user_rst_n = ~w_ui_clk_sync_rst;

    //==========================================================================
    // DDR3 user-side signals (driven by adc_top, consumed by ddr3_top)
    //==========================================================================
    logic                    w_user_wr_valid;
    logic [DDR_ADDR_W-1:0]   w_user_wr_addr_base;
    logic                    w_user_wr_data_valid;
    logic [DDR_DATA_W-1:0]   w_user_wr_data;
    logic                    w_user_wr_finish;
    logic                    w_user_wr_fifo_ready;

    // Read port currently unused - tie off.
    logic                    w_user_rd_valid;
    logic [DDR_ADDR_W-1:0]   w_user_rd_addr_base;
    logic                    w_user_rd_finish;
    logic                    w_user_rd_data_valid;
    logic [DDR_DATA_W-1:0]   w_user_rd_data;

    assign w_user_rd_valid     = 1'b0;
    assign w_user_rd_addr_base = '0;

    //==========================================================================
    // DDR3 controller (ddr3_top)
    //==========================================================================
    ddr3_top #(
        .DDR3_WITH      (DDR_DATA_W),
        .WR_FIFO_DEPTH  (WR_FIFO_DEPTH),
        .RD_FIFO_DEPTH  (RD_FIFO_DEPTH),
        .P_WR_BURST_LEN (P_WR_BURST_LEN),
        .P_WR_BURST_NUM (P_WR_BURST_NUM),
        .P_RD_BURST_LEN (P_RD_BURST_LEN),
        .P_RD_BURST_NUM (P_RD_BURST_NUM)
    ) u_ddr3 (
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

        .i_clk_ddr3           (clk_ddr3_100),
        .i_clk_ref            (clk_ref_200),
        .i_clk_locked         (pll_locked),
        .sys_rst_n            (i_rst_n),

        .ui_clk               (w_ui_clk),
        .ui_clk_sync_rst      (w_ui_clk_sync_rst),

        .i_user_wr_valid      (w_user_wr_valid),
        .i_user_wr_addr_base  (w_user_wr_addr_base),
        .i_user_wr_data_valid (w_user_wr_data_valid),
        .i_user_wr_data       (w_user_wr_data),
        .o_user_wr_finish     (w_user_wr_finish),
        .o_user_wr_fifo_ready (w_user_wr_fifo_ready),

        .i_user_rd_valid      (w_user_rd_valid),
        .i_user_rd_addr_base  (w_user_rd_addr_base),
        .o_user_rd_finish     (w_user_rd_finish),
        .o_user_rd_data_valid (w_user_rd_data_valid),
        .o_user_rd_data       (w_user_rd_data),

        .init_calib_complete  (w_init_calib_complete),
        .mmcm_locked          (w_mmcm_locked)
    );

    //==========================================================================
    // Sticky WR FIFO backpressure indicator
    //   Goes HIGH (and stays high until reset) the first time the ADC writer
    //   asserts data_valid while the WR FIFO reports not-ready.
    //   -> drive an LED from o_wr_fifo_stuck. If it lights up at any point,
    //      the ADC rate is exceeding DDR3 write bandwidth.
    //==========================================================================
    logic r_wr_fifo_stuck;

    always_ff @(posedge w_ui_clk) begin
        if (w_user_rst)
            r_wr_fifo_stuck <= 1'b0;
        else if (w_user_wr_data_valid && !w_user_wr_fifo_ready)
            r_wr_fifo_stuck <= 1'b1;
    end

    assign o_wr_fifo_stuck = r_wr_fifo_stuck;

    //==========================================================================
    // Elaboration-time sanity check on the register map
    //==========================================================================
    localparam int AD9833_END_ADDR   = AD9833_BASE_ADDR + 4 - 1;
    localparam int ADC_CORE_END_ADDR = ADC_CORE_BASE_ADDR + ADC_CORE_NUM_REGS - 1;

    if (ADC_CORE_END_ADDR >= NUM_REGS) begin : gen_bad_adc_window
        $error("uart_top: ADC window [%0d..%0d] exceeds NUM_REGS=%0d",
               ADC_CORE_BASE_ADDR, ADC_CORE_END_ADDR, NUM_REGS);
    end

    if ((AD9833_BASE_ADDR   <= ADC_CORE_END_ADDR) &&
        (ADC_CORE_BASE_ADDR <= AD9833_END_ADDR  )) begin : gen_overlap
        $error("uart_top: AD9833 window [%0d..%0d] overlaps ADC window [%0d..%0d]",
               AD9833_BASE_ADDR,   AD9833_END_ADDR,
               ADC_CORE_BASE_ADDR, ADC_CORE_END_ADDR);
    end

    //==========================================================================
    // Register file (on ui_clk)
    //==========================================================================
    logic [0:NUM_REGS-1][31:0] w_regs;

    uart_regs #(
        .DATA_WIDTH       (DATA_WIDTH),
        .RX_FIFO_DEPTH    (RX_FIFO_DEPTH),
        .RX_FIFO_AF_DEPTH (RX_FIFO_AF_DEPTH),
        .RX_FIFO_AE_DEPTH (RX_FIFO_AE_DEPTH),
        .TX_FIFO_DEPTH    (TX_FIFO_DEPTH),
        .TX_FIFO_AF_DEPTH (TX_FIFO_AF_DEPTH),
        .TX_FIFO_AE_DEPTH (TX_FIFO_AE_DEPTH),
        .NUM_REGS         (NUM_REGS)
    ) u_uart_regs (
        .i_clk  (w_ui_clk),
        .i_rst  (w_user_rst),
        .i_rx   (i_rx),
        .o_tx   (o_tx),
        .o_regs (w_regs)
    );

    //==========================================================================
    // AD9833 sub-block (regs 0..3)
    //==========================================================================
    logic [31:0] w_reg_cmd;
    logic [31:0] w_reg_freq;
    logic [31:0] w_reg_phase_ctrl;
    logic [31:0] w_reg_control;

    assign w_reg_cmd        = w_regs[AD9833_BASE_ADDR + 0];
    assign w_reg_freq       = w_regs[AD9833_BASE_ADDR + 1];
    assign w_reg_phase_ctrl = w_regs[AD9833_BASE_ADDR + 2];
    assign w_reg_control    = w_regs[AD9833_BASE_ADDR + 3];

    ad9833_top #(
        .FRAME_W     (SPI_FRAME_W),
        .SPI_CLK_DIV (SPI_CLK_DIV)
    ) u_ad9833_top (
        .i_clk            (w_ui_clk),
        .i_rst_n          (w_user_rst_n),
        .i_reg_cmd        (w_reg_cmd),
        .i_reg_freq       (w_reg_freq),
        .i_reg_phase_ctrl (w_reg_phase_ctrl),
        .i_reg_control    (w_reg_control),
        .o_spi_sclk       (o_spi_sclk),
        .o_spi_fsync      (o_spi_fsync),
        .o_spi_mosi       (o_spi_mosi)
    );

    //==========================================================================
    // ADC subsystem (regs ADC_CORE_BASE_ADDR .. ADC_CORE_BASE_ADDR+53)
    //   adc_top = adc_core + adc_sampling_sin_model + adc_ddr3_writer
    //   Its user_wr_* outputs go straight into ddr3_top (same clock domain).
    //==========================================================================
    adc_top #(
        .NUM_REGS       (ADC_CORE_NUM_REGS),
        .CTRL_REG_IDX   (ADC_CTRL_REG_IDX),
        .ADC_DATA_W     (ADC_DATA_W),
        .ADC_LUT_DEPTH  (ADC_LUT_DEPTH),
        .ADC_SAMPLE_GAP (ADC_SAMPLE_GAP),
        .ADC_PHASE_STEP (ADC_PHASE_STEP),
        .DDR_DATA_W     (DDR_DATA_W),
        .DDR_ADDR_W     (DDR_ADDR_W),
        .P_WR_BURST_LEN (P_WR_BURST_LEN),
        .P_WR_BURST_NUM (P_WR_BURST_NUM),
        .DDR_BASE_ADDR  (DDR_BASE_ADDR)
    ) u_adc_top (
        .i_clk                (w_ui_clk),
        .i_rst                (w_user_rst),
        .i_all_regs           (w_regs[ADC_CORE_BASE_ADDR +: ADC_CORE_NUM_REGS]),

        .o_adc_sampling       (o_adc_sampling),
        .o_active             (o_adc_active),

        .o_adc_data           (o_adc_data),
        .o_adc_data_valid     (o_adc_data_valid),
        .o_adc_spi_finish     (o_adc_spi_finish),

        .o_user_wr_valid      (w_user_wr_valid),
        .o_user_wr_addr_base  (w_user_wr_addr_base),
        .o_user_wr_data       (w_user_wr_data),
        .o_user_wr_data_valid (w_user_wr_data_valid)
    );

endmodule