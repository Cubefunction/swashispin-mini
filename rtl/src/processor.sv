// `default_nettype none
`timescale 1ns / 1ps
`include "dc.svh"
`include "launch.svh"

module processor
   #(parameter NUM_DC_CHANNEL=24,
     parameter NUM_MARKER_CHANNEL=3,
     parameter EXE_REGS=DC_SEQ_REGS+DC_CTRL_REGS+LCH_CTRL_REGS+NUM_MARKER_CHANNEL,
     parameter RO_REGS=DC_REG_PER_INSN+2+NUM_DC_CHANNEL*2+1)
    (input  logic i_clk, i_rst,

     // uart registers
     input  logic [0:EXE_REGS-1][31:0] i_regs,
     output logic [0:RO_REGS-1][31:0] o_regs,

     // dc spi buses
     output logic [0:NUM_DC_CHANNEL-1] o_dc_sclk_bus,
     output logic [0:NUM_DC_CHANNEL-1] o_dc_mosi_bus,
     input  logic [0:NUM_DC_CHANNEL-1] i_dc_miso_bus,
     output logic [0:NUM_DC_CHANNEL-1] o_dc_cs_n_bus,
     output logic [0:NUM_DC_CHANNEL-1] o_dc_ldac_n_bus,

     // dc armed bus for LED
     output logic [NUM_DC_CHANNEL-1:0] o_dc_armed_bus,

     // dc empty bus for simulation
     output logic [0:NUM_DC_CHANNEL-1] o_dc_empty_bus,

     // dc eop bus
     output dc_eop_t [0:NUM_DC_CHANNEL-1] o_dc_eop_bus,

     // trigger
     input  logic i_async_trigger,

     // markers
     output logic [NUM_MARKER_CHANNEL-1:0] o_marker_bus);

    // i_regs
    localparam DC_ILDST_ADDR_REG = 0;
    localparam DC_IST_REG_LO = DC_ILDST_ADDR_REG + 1;
    localparam DC_IST_REG_HI = DC_IST_REG_LO + DC_REG_PER_INSN - 1;
    localparam DC_IST_STRB_REG = DC_IST_REG_HI + 1;

    localparam DC_ILD_STRB_REG = DC_IST_STRB_REG + 1;

    localparam DC_ITERS_REG = DC_ILD_STRB_REG + 1;
    localparam DC_DEPTH_REG = DC_ITERS_REG + 1;
    localparam DC_START_STRB_REG = DC_DEPTH_REG + 1;
    localparam DC_HALT_STRB_REG = DC_START_STRB_REG + 1;

    localparam DC_CTRL_START = DC_HALT_STRB_REG + 1;
    localparam DC_CTRL_END = DC_CTRL_START + DC_CTRL_REGS - 1;

    localparam LCH_CTRL_START = DC_CTRL_END + 1;
    localparam LCH_CTRL_END = LCH_CTRL_START + LCH_CTRL_REGS - 1;

    localparam MARKER_SEL_START = LCH_CTRL_END + 1;
    localparam MARKER_SEL_END = MARKER_SEL_START + NUM_MARKER_CHANNEL - 1;

    // o_regs
    localparam DC_ILD_REG_LO = 0;
    localparam DC_ILD_REG_HI = DC_ILD_REG_LO + DC_REG_PER_INSN - 1;

    localparam DC_EMPTY_REG = DC_ILD_REG_HI + 1;
    localparam DC_ARMED_REG = DC_EMPTY_REG + 1;

    localparam DC_ITERS_REG_LO = DC_ARMED_REG + 1;
    localparam DC_ITERS_REG_HI = DC_ITERS_REG_LO + NUM_DC_CHANNEL - 1;

    localparam DC_DEPTH_REG_LO = DC_ITERS_REG_HI + 1;
    localparam DC_DEPTH_REG_HI = DC_DEPTH_REG_LO + NUM_DC_CHANNEL - 1;

    localparam LCH_ITERS_REG = DC_DEPTH_REG_HI + 1;
     
    /****************
    * dc connections
    ****************/

    logic [NUM_DC_CHANNEL-1:0][DC_INSN_WIDTH-1:0] w_dc_insn_rd_bus;
    logic [NUM_DC_CHANNEL-1:0][DC_SEQ_ITER_WIDTH-1:0] w_dc_iters_bus;
    logic [NUM_DC_CHANNEL-1:0][$clog2(DC_DEPTH)-1:0] w_dc_depth_bus;

    logic [NUM_DC_CHANNEL-1:0] w_dc_start_bus;
    logic [NUM_DC_CHANNEL-1:0] w_dc_armed_bus;
    logic [NUM_DC_CHANNEL-1:0] w_dc_marker_bus;

    for (genvar i = 0; i < NUM_DC_CHANNEL; i++) begin : DC_GEN

        dc DC (
            .i_clk(i_clk),
            .i_rst(i_rst),

            .i_seq_regs({
                i_regs[DC_ILDST_ADDR_REG], 
                i_regs[DC_IST_REG_LO:DC_IST_REG_HI], 
                31'h0, i_regs[DC_IST_STRB_REG][i], 
                31'h0, i_regs[DC_ILD_STRB_REG][i], 
                i_regs[DC_ITERS_REG], 
                i_regs[DC_DEPTH_REG], 
                31'h0, i_regs[DC_START_STRB_REG][i], 
                31'h0, i_regs[DC_HALT_STRB_REG][i]
            }),

            .i_ctrl_regs({
                i_regs[DC_CTRL_START:DC_CTRL_END-1], 
                31'h0, i_regs[DC_CTRL_END][i]
            }),

            .o_insn_rd(w_dc_insn_rd_bus[i]),

            .o_iters(w_dc_iters_bus[i]),
            .o_depth(w_dc_depth_bus[i]),

            .o_sclk(o_dc_sclk_bus[i]),
            .o_mosi(o_dc_mosi_bus[i]),
            .i_miso(i_dc_miso_bus[i]),
            .o_cs_n(o_dc_cs_n_bus[i]),
            .o_ldac_n(o_dc_ldac_n_bus[i]),

            .o_marker(w_dc_marker_bus[i]),

            .i_start(w_dc_start_bus[i]),
            .o_armed(w_dc_armed_bus[i]),

            .o_empty(o_dc_empty_bus[i]),

            .o_eop(o_dc_eop_bus[i])
        );

        assign o_regs[DC_ITERS_REG_LO + i] = {{(32-DC_SEQ_ITER_WIDTH){1'b0}}, w_dc_iters_bus[i]};
        assign o_regs[DC_DEPTH_REG_LO + i] = {{(32-$clog2(DC_DEPTH)){1'b0}}, w_dc_iters_bus[i]};

    end

    assign o_dc_armed_bus = w_dc_armed_bus;

    assign o_regs[DC_EMPTY_REG] = {{(32-NUM_DC_CHANNEL){1'b0}}, o_dc_empty_bus};
    assign o_regs[DC_ARMED_REG] = {{(32-NUM_DC_CHANNEL){1'b0}}, w_dc_armed_bus};

    logic [DC_INSN_WIDTH-1:0] w_dc_insn_rd_mux;

    always_comb begin

        w_dc_insn_rd_mux = 'h0;

        for (int i = 0; i < NUM_DC_CHANNEL; i++) begin
            if (i_regs[DC_ILD_STRB_REG][i])
                w_dc_insn_rd_mux = w_dc_insn_rd_bus[i];
        end

        {o_regs[DC_ILD_REG_LO:DC_ILD_REG_HI]} = {
            {(DC_REG_PER_INSN*32-DC_INSN_WIDTH){1'b0}}, w_dc_insn_rd_mux
        };

    end

    /********************
    * launch connections
    ********************/

    logic r_trigger_ff1, r_trigger_ff2;

    always_ff @(posedge i_clk) begin
        if (i_rst) begin
            r_trigger_ff1 <= 1'b0;
            r_trigger_ff2 <= 1'b0;
        end
        else begin
            r_trigger_ff1 <= i_async_trigger;
            r_trigger_ff2 <= r_trigger_ff1;
        end
    end

    logic [LCH_ITER_WIDTH-1:0] w_lch_iters;

    launch #(
        .NUM_DC_CHANNEL(NUM_DC_CHANNEL)
    ) LCH (
        .i_clk(i_clk),
        .i_rst(i_rst),

        .i_regs(i_regs[LCH_CTRL_START:LCH_CTRL_END]),

        .i_dc_armed(w_dc_armed_bus),

        .i_trigger(r_trigger_ff2),

        .o_iters(w_lch_iters),

        .o_dc_start(w_dc_start_bus)
    );

    assign o_regs[LCH_ITERS_REG] = {{(32-LCH_ITER_WIDTH){1'b0}}, w_lch_iters};

    /********************
    * marker connections
    ********************/

    logic [NUM_MARKER_CHANNEL-1:0][$clog2(NUM_DC_CHANNEL)-1:0] w_marker_sel_bus;

    for (genvar i = 0; i < NUM_MARKER_CHANNEL; i++) begin : MARKER_GEN
        assign w_marker_sel_bus[i] = i_regs[MARKER_SEL_START + i];
        assign o_marker_bus[i] = w_dc_marker_bus[w_marker_sel_bus[i]];
    end

endmodule
