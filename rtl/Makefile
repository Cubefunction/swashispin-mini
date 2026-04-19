SIM   := vcs
CORES := $(shell getconf _NPROCESSORS_ONLN)

VCS_FLAGS := -full64 -sverilog +incdir+include \
             -debug_acc+all+dmptf +memcbk \
             -debug_region+cell+encrypt \
             -kdb +warn=all -j$(CORES) +v2k

VERDI_FLAGS := +fsdbfile+inter.fsdb +vcs+all -gui

# ── source groups ────────────────────────────────────────────────────────────

SRC_UART := lib/fifo.sv \
            lib/baudx16_generator.sv \
            lib/receiver.sv \
            lib/transmitter.sv \
            lib/uart.sv

SRC_DC := lib/bram.sv \
          lib/edge_detector.sv \
          src/dc_decode.sv \
          src/dc_spi_master.sv \
          src/dc_core.sv \
          src/dc_ctrl.sv \
          src/serial_sequencer.sv \
          src/dc.sv

SRC_PROC := $(SRC_DC) $(SRC_UART) \
            src/launch.sv \
            src/uart_regs.sv \
            src/processor.sv

# ── targets ──────────────────────────────────────────────────────────────────

.PHONY: all simulator2 dc_tb serial_sequencer_tb uart_regs_tb run gui clean list

all: simulator2

simulator2: sim/simulator2.sv sim/cmd_dpi.c $(SRC_PROC) lib/ad5791.sv
	$(SIM) $(VCS_FLAGS) $^ -o $@

dc_tb: tb/dc_tb.sv $(SRC_DC) lib/ad5791.sv
	$(SIM) $(VCS_FLAGS) $^ -o $@

serial_sequencer_tb: tb/serial_sequencer_tb.sv src/serial_sequencer.sv \
                     lib/bram.sv lib/edge_detector.sv
	$(SIM) $(VCS_FLAGS) $^ -o $@

uart_regs_tb: tb/uart_regs_tb.sv src/uart_regs.sv $(SRC_UART)
	$(SIM) $(VCS_FLAGS) $^ -o $@

# ── simulation ───────────────────────────────────────────────────────────────

TARGET ?= simulator2

run:
	./$(TARGET)

gui:
	./$(TARGET) $(VERDI_FLAGS) &

# ── housekeeping ─────────────────────────────────────────────────────────────

list:
	@echo "Targets:  simulator2  dc_tb  serial_sequencer_tb  uart_regs_tb"
	@echo "Sources:"
	@ls -1 src/*.sv lib/*.sv sim/*.sv tb/*.sv 2>/dev/null | sed 's/^/  /'

clean:
	rm -rf simulator2 simulator2.daidir \
	       dc_tb dc_tb.daidir \
	       serial_sequencer_tb serial_sequencer_tb.daidir \
	       uart_regs_tb uart_regs_tb.daidir \
	       csrc ucli.key vc_hdrs.h \
	       inter.fsdb novas.conf novas.rc novas_dump.log \
	       verdi_config_file verdiLog sysBusyPLog \
	       .inter.fsdb.tbsim \
	       vivado.jou vivado.log vivado_pid*.str

