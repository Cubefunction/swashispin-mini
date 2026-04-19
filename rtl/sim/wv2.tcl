set nw [wvCreateWindow]
wvRenameGroup -win $nw {G1} {uart}
wvAddGroup -win $nw {dc}
wvAddGroup -win $nw {launch}
wvAddGroup -win $nw {v}

wvSetPosition -win $nw {("v" 0)}
wvAddSignal -win $nw "simulator/vdc\[0:23\]" \
                     "simulator/vdc_digital\[0:23\]\[19:0\]"

wvCollapseGroup -win $nw "v"

# ── launch ────────────────────────────────────────────────────────────────────

wvSelectGroup -win $nw "launch"
wvAddSubGroup -win $nw "LCH"

wvSelectGroup -win $nw "launch/LCH"
wvAddSubGroup -win $nw "start"
wvAddSubGroup -win $nw "armed"
wvAddSubGroup -win $nw "new"

wvSetPosition -win $nw {("launch/LCH" 0)}
wvAddSignal -win $nw "/simulator/PROCESSOR/LCH/i_clk" \
                     "/simulator/PROCESSOR/LCH/i_rst" \
                     "/simulator/PROCESSOR/LCH/r_state" \
                     "/simulator/PROCESSOR/LCH/w_next_state" \
                     "/simulator/PROCESSOR/LCH/r_dc_active_mask"

wvSetPosition -win $nw {("launch/LCH/new" 0)}
wvAddSignal -win $nw "/simulator/PROCESSOR/LCH/i_regs" \
                     "/simulator/PROCESSOR/LCH/w_new_ctrl" \
                     "/simulator/PROCESSOR/LCH/w_start"

wvSetPosition -win $nw {("launch/LCH/armed" 0)}
wvAddSignal -win $nw "/simulator/PROCESSOR/LCH/i_trigger" \
                     "/simulator/PROCESSOR/LCH/i_dc_armed" \
                     "/simulator/PROCESSOR/LCH/r_dc_armed" \
                     "/simulator/PROCESSOR/LCH/w_dc_ready" \
                     "/simulator/PROCESSOR/LCH/w_all_ready"

wvSetPosition -win $nw {("launch/LCH/start" 0)}
wvAddSignal -win $nw "/simulator/PROCESSOR/LCH/o_dc_start"

wvCollapseGroup -win $nw "launch/LCH/new"
wvCollapseGroup -win $nw "launch/LCH/armed"
wvCollapseGroup -win $nw "launch/LCH/start"
wvCollapseGroup -win $nw "launch/LCH"
wvCollapseGroup -win $nw "launch"

# ── uart ──────────────────────────────────────────────────────────────────────

wvSelectGroup -win $nw "uart"
wvAddSubGroup -win $nw "REGS"
wvAddSubGroup -win $nw "TSMT"
wvAddSubGroup -win $nw "RECV"

wvSelectGroup -win $nw "uart/RECV"
wvAddSubGroup -win $nw "RXFIFO"

wvSetPosition -win $nw {("uart/RECV" 0)}
wvAddSignal -win $nw "/simulator/REGS/UART/RECV/i_clk" \
                     "/simulator/REGS/UART/RECV/i_rst" \
                     "/simulator/REGS/UART/RECV/r_state" \
                     "/simulator/REGS/UART/RECV/i_rx" \
                     "/simulator/REGS/UART/RECV/i_sample_tick" \
                     "/simulator/REGS/UART/RECV/r_cycle_counter" \
                     "/simulator/REGS/UART/RECV/r_bit_counter" \
                     "/simulator/REGS/UART/RECV/w_data_en" \
                     "/simulator/REGS/UART/RECV/r_data" \
                     "/simulator/REGS/UART/RECV/o_enq_rxq" \
                     "/simulator/REGS/UART/RECV/o_data"

wvSetPosition -win $nw {("uart/RECV/RXFIFO" 0)}
wvAddSignal -win $nw "/simulator/REGS/UART/RXFIFO/i_clk" \
                     "/simulator/REGS/UART/RXFIFO/i_rst" \
                     "/simulator/REGS/UART/RXFIFO/r_num_data" \
                     "/simulator/REGS/UART/RXFIFO/r_enq_ptr" \
                     "/simulator/REGS/UART/RXFIFO/i_enq" \
                     "/simulator/REGS/UART/RXFIFO/w_enq_en" \
                     "/simulator/REGS/UART/RXFIFO/o_full" \
                     "/simulator/REGS/UART/RXFIFO/r_deq_ptr" \
                     "/simulator/REGS/UART/RXFIFO/i_deq" \
                     "/simulator/REGS/UART/RXFIFO/o_empty" \
                     "/simulator/REGS/UART/RXFIFO/r_data"

wvSelectGroup -win $nw "uart/TSMT"
wvAddSubGroup -win $nw "TXFIFO"

wvSetPosition -win $nw {("uart/TSMT" 0)}
wvAddSignal -win $nw "/simulator/REGS/UART/TSMT/i_clk" \
                     "/simulator/REGS/UART/TSMT/i_rst" \
                     "/simulator/REGS/UART/TSMT/r_state" \
                     "/simulator/REGS/UART/TSMT/o_tx" \
                     "/simulator/REGS/UART/TSMT/i_sample_tick" \
                     "/simulator/REGS/UART/TSMT/i_data" \
                     "/simulator/REGS/UART/TSMT/o_deq_txq" \
                     "/simulator/REGS/UART/TSMT/r_data" \
                     "/simulator/REGS/UART/TSMT/r_cycle_counter" \
                     "/simulator/REGS/UART/TSMT/r_bit_counter" \
                     "/simulator/REGS/UART/TSMT/w_data_en" \
                     "/simulator/REGS/UART/TSMT/w_data_shift"

wvSetPosition -win $nw {("uart/TSMT/TXFIFO" 0)}
wvAddSignal -win $nw "/simulator/REGS/UART/TXFIFO/i_clk" \
                     "/simulator/REGS/UART/TXFIFO/i_rst" \
                     "/simulator/REGS/UART/TXFIFO/r_num_data" \
                     "/simulator/REGS/UART/TXFIFO/r_enq_ptr" \
                     "/simulator/REGS/UART/TXFIFO/i_enq" \
                     "/simulator/REGS/UART/TXFIFO/w_enq_en" \
                     "/simulator/REGS/UART/TXFIFO/o_full" \
                     "/simulator/REGS/UART/TXFIFO/r_deq_ptr" \
                     "/simulator/REGS/UART/TXFIFO/i_deq" \
                     "/simulator/REGS/UART/TXFIFO/o_empty" \
                     "/simulator/REGS/UART/TXFIFO/r_data"

wvSelectGroup -win $nw "uart/REGS"
wvSetPosition -win $nw {("uart/REGS" 0)}
wvAddSignal -win $nw "/simulator/REGS/i_clk" \
                     "/simulator/REGS/i_rst" \
                     "/simulator/REGS/r_regs" \
                     "/simulator/REGS/o_regs" \
                     "/simulator/REGS/w_deq_rxq" \
                     "/simulator/REGS/w_rxq_data" \
                     "/simulator/REGS/w_rxq_empty" \
                     "/simulator/REGS/w_enq_txq" \
                     "/simulator/REGS/w_txq_data" \
                     "/simulator/REGS/w_latch_op" \
                     "/simulator/REGS/r_op" \
                     "/simulator/REGS/w_addr" \
                     "/simulator/REGS/w_wr" \
                     "/simulator/REGS/w_shift_in" \
                     "/simulator/REGS/r_wr_data" \
                     "/simulator/REGS/w_rd" \
                     "/simulator/REGS/w_shift_out" \
                     "/simulator/REGS/r_rd_data" \
                     "/simulator/REGS/w_bcnt_en" \
                     "/simulator/REGS/w_bcnt_clr" \
                     "/simulator/REGS/r_bcnt" \
                     "/simulator/REGS/r_state"

wvCollapseGroup -win $nw "uart/RECV/RXFIFO"
wvCollapseGroup -win $nw "uart/RECV"
wvCollapseGroup -win $nw "uart/TSMT/TXFIFO"
wvCollapseGroup -win $nw "uart/TSMT"
wvCollapseGroup -win $nw "uart/REGS"
wvCollapseGroup -win $nw "uart"

# ── dc channels ───────────────────────────────────────────────────────────────

for {set ch 23} {$ch >= 0} {incr ch -1} {

    set dc "/simulator/PROCESSOR/DC_GEN\[$ch\]/DC"

    wvSelectGroup -win $nw {dc}
    wvAddSubGroup -win $nw "ch$ch"

    wvSelectGroup -win $nw "dc/ch$ch"
    wvAddSubGroup -win $nw "DAC"
    wvAddSubGroup -win $nw "CTRL"
    wvAddSubGroup -win $nw "CORE"
    wvAddSubGroup -win $nw "SEQ"

    # ── SEQ (serial_sequencer) ────────────────────────────────────────────────
    wvSelectGroup -win $nw "dc/ch$ch/SEQ"
    wvAddSubGroup -win $nw "out"
    wvAddSubGroup -win $nw "insn"
    wvAddSubGroup -win $nw "pc"
    wvAddSubGroup -win $nw "ist"

    wvSetPosition -win $nw [format {("dc/ch%d/SEQ" 0)} $ch]
    wvAddSignal -win $nw "$dc/SEQ/i_clk" \
                         "$dc/SEQ/i_rst" \
                         "$dc/SEQ/w_propagate" \
                         "$dc/SEQ/o_active" \

    wvSetPosition -win $nw [format {("dc/ch%d/SEQ/ist" 0)} $ch]
    wvAddSignal -win $nw "$dc/SEQ/w_ist_addr" \
                         "$dc/SEQ/w_ist" \
                         "$dc/SEQ/w_ist_strb" \
                         "$dc/SEQ/w_ist_wr" \
                         "$dc/SEQ/w_imem_wr" \
                         "$dc/SEQ/w_imem_wr_addr" \
                         "$dc/SEQ/w_imem_wr_data"

    wvSetPosition -win $nw [format {("dc/ch%d/SEQ/pc" 0)} $ch]
    wvAddSignal -win $nw "$dc/SEQ/w_iters" \
                         "$dc/SEQ/w_depth" \
                         "$dc/SEQ/w_start_strb" \
                         "$dc/SEQ/w_halt_strb" \
                         "$dc/SEQ/p"

    wvSetPosition -win $nw [format {("dc/ch%d/SEQ/insn" 0)} $ch]
    wvAddSignal -win $nw "$dc/SEQ/i"

    wvSetPosition -win $nw [format {("dc/ch%d/SEQ/out" 0)} $ch]
    wvAddSignal -win $nw "$dc/SEQ/o_pc" \
                         "$dc/SEQ/o_insn" \
                         "$dc/SEQ/i_next" \
                         "$dc/SEQ/o_empty" \
                         "$dc/SEQ/i_insn_modified" \
                         "$dc/SEQ/o"

    # ── CORE (dc_core) ────────────────────────────────────────────────────────
    wvSelectGroup -win $nw "dc/ch$ch/CORE"
    wvAddSubGroup -win $nw "hold"
    wvAddSubGroup -win $nw "spi"
    wvAddSubGroup -win $nw "iterate"
    wvAddSubGroup -win $nw "decode"

    wvSetPosition -win $nw [format {("dc/ch%d/CORE" 0)} $ch]
    wvAddSignal -win $nw "$dc/CORE/i_clk" \
                         "$dc/CORE/i_rst" \
                         "$dc/CORE/w_propagate_i2s" \
                         "$dc/CORE/w_propagate_s2h" \
                         "$dc/CORE/o_empty" \
                         "$dc/CORE/i_ctrl"

    wvSetPosition -win $nw [format {("dc/ch%d/CORE/decode" 0)} $ch]
    wvAddSignal -win $nw "$dc/CORE/d" \
                         "$dc/CORE/i_empty" \
                         "$dc/CORE/o_next" \
                         "$dc/CORE/i_addr" \
                         "$dc/CORE/i_insn" \
                         "$dc/CORE/o_insn_modified"

    wvSetPosition -win $nw [format {("dc/ch%d/CORE/iterate" 0)} $ch]
    wvAddSignal -win $nw "$dc/CORE/i"

    wvSetPosition -win $nw [format {("dc/ch%d/CORE/spi" 0)} $ch]
    wvAddSignal -win $nw "$dc/CORE/s" \
                         "$dc/CORE/w_spi_done" \
                         "$dc/CORE/o_armed" \
                         "$dc/CORE/i_start"

    wvSelectGroup -win $nw "dc/ch$ch/CORE/spi"
    wvAddSubGroup -win $nw "wires"
    wvSetPosition -win $nw [format {("dc/ch%d/CORE/spi/wires" 0)} $ch]
    wvAddSignal -win $nw "$dc/CORE/o_sclk" \
                         "$dc/CORE/o_mosi" \
                         "$dc/CORE/i_miso" \
                         "$dc/CORE/o_cs_n" \
                         "$dc/CORE/o_ldac_n"

    wvSetPosition -win $nw [format {("dc/ch%d/CORE/hold" 0)} $ch]
    wvAddSignal -win $nw "$dc/CORE/h" \
                         "$dc/CORE/o_eop"

    # ── CTRL (dc_ctrl) ────────────────────────────────────────────────────────
    wvSelectGroup -win $nw "dc/ch$ch/CTRL"
    wvAddSubGroup -win $nw "new"

    wvSetPosition -win $nw [format {("dc/ch%d/CTRL" 0)} $ch]
    wvAddSignal -win $nw "$dc/CTRL/o_ctrl" \
                         "$dc/CTRL/r_dvsr" \
                         "$dc/CTRL/r_delay_cycles" \
                         "$dc/CTRL/r_cs_up_cycles" \
                         "$dc/CTRL/r_ldac_cycles"

    wvSetPosition -win $nw [format {("dc/ch%d/CTRL/new" 0)} $ch]
    wvAddSignal -win $nw "$dc/CTRL/i_regs" \
                         "$dc/CTRL/w_last0" \
                         "$dc/CTRL/w_last0_ff1" \
                         "$dc/CTRL/w_last0_ff2" \
                         "$dc/CTRL/w_new_ctrl"

    # ── DAC (ad5791) ──────────────────────────────────────────────────────────
    wvSelectGroup -win $nw "dc/ch$ch/DAC"
    wvAddSubGroup -win $nw "v"
    wvAddSubGroup -win $nw "regs"
    wvAddSubGroup -win $nw "pins"

    wvSetPosition -win $nw [format {("dc/ch%d/DAC" 0)} $ch]
    wvAddSignal -win $nw "/simulator/DC_IO_GEN\[$ch\]/DAC/valid_transaction" \
                         "/simulator/DC_IO_GEN\[$ch\]/DAC/input_shift_reg" \
                         "/simulator/DC_IO_GEN\[$ch\]/DAC/rw" \
                         "/simulator/DC_IO_GEN\[$ch\]/DAC/addr" \
                         "/simulator/DC_IO_GEN\[$ch\]/DAC/data" \
                         "/simulator/DC_IO_GEN\[$ch\]/DAC/rd_data"

    wvSetPosition -win $nw [format {("dc/ch%d/DAC/pins" 0)} $ch]
    wvAddSignal -win $nw "/simulator/DC_IO_GEN\[$ch\]/DAC/SCLK" \
                         "/simulator/DC_IO_GEN\[$ch\]/DAC/SDIN" \
                         "/simulator/DC_IO_GEN\[$ch\]/DAC/SYNC_N" \
                         "/simulator/DC_IO_GEN\[$ch\]/DAC/SDO" \
                         "/simulator/DC_IO_GEN\[$ch\]/DAC/LDAC_N" \
                         "/simulator/DC_IO_GEN\[$ch\]/DAC/CLR_N" \
                         "/simulator/DC_IO_GEN\[$ch\]/DAC/RESET_N"

    wvSetPosition -win $nw [format {("dc/ch%d/DAC/regs" 0)} $ch]
    wvAddSignal -win $nw "/simulator/DC_IO_GEN\[$ch\]/DAC/dac_reg" \
                         "/simulator/DC_IO_GEN\[$ch\]/DAC/ctrl_reg" \
                         "/simulator/DC_IO_GEN\[$ch\]/DAC/clrcode_reg" \
                         "/simulator/DC_IO_GEN\[$ch\]/DAC/sw_ctrl_reg" \
                         "/simulator/DC_IO_GEN\[$ch\]/DAC/dac_input_reg" \
                         "/simulator/DC_IO_GEN\[$ch\]/DAC/SDODIS" \
                         "/simulator/DC_IO_GEN\[$ch\]/DAC/DACTRI" \
                         "/simulator/DC_IO_GEN\[$ch\]/DAC/OPGND"

    wvSetPosition -win $nw [format {("dc/ch%d/DAC/v" 0)} $ch]
    wvAddSignal -win $nw "/simulator/DC_IO_GEN\[$ch\]/DAC/VOUT" \
                         "/simulator/DC_IO_GEN\[$ch\]/DAC/VDIGITAL"

}

# ── collapse all ──────────────────────────────────────────────────────────────

for {set ch 23} {$ch >= 0} {incr ch -1} {

    wvCollapseGroup -win $nw "dc/ch$ch/SEQ/ist"
    wvCollapseGroup -win $nw "dc/ch$ch/SEQ/pc"
    wvCollapseGroup -win $nw "dc/ch$ch/SEQ/out"
    wvCollapseGroup -win $nw "dc/ch$ch/SEQ"

    wvCollapseGroup -win $nw "dc/ch$ch/CORE/decode"
    wvCollapseGroup -win $nw "dc/ch$ch/CORE/iterate"
    wvCollapseGroup -win $nw "dc/ch$ch/CORE/spi/wires"
    wvCollapseGroup -win $nw "dc/ch$ch/CORE/spi"
    wvCollapseGroup -win $nw "dc/ch$ch/CORE/hold"
    wvCollapseGroup -win $nw "dc/ch$ch/CORE"

    wvCollapseGroup -win $nw "dc/ch$ch/CTRL/new"
    wvCollapseGroup -win $nw "dc/ch$ch/CTRL"

    wvCollapseGroup -win $nw "dc/ch$ch/DAC/pins"
    wvCollapseGroup -win $nw "dc/ch$ch/DAC/regs"
    wvCollapseGroup -win $nw "dc/ch$ch/DAC/v"
    wvCollapseGroup -win $nw "dc/ch$ch/DAC"

    wvCollapseGroup -win $nw "dc/ch$ch"

}

wvCollapseGroup -win $nw "dc"

