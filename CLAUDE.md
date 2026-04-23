# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**Swashispin-Mini** is an FPGA firmware for driving 24 parallel DAC channels via SPI, designed for scientific instrumentation with microsecond-scale timing precision. It targets Xilinx FPGAs (synthesized with Vivado) and uses VCS/Verdi for simulation.

## Build & Simulation Commands

All simulation commands run from the `rtl/` directory:

```bash
# Compile testbenches (VCS)
make simulator2          # Main processor testbench
make dc_tb               # Single DC channel testbench
make serial_sequencer_tb # Instruction sequencer testbench
make uart_regs_tb        # UART register interface testbench

# Run simulation
make run                 # Run default simulator

# Waveform debug
make gui                 # Launch Verdi (requires FSDB waveform file)

make clean               # Remove build artifacts
```

Synthesis is done via Vivado using the project files in `rtl/synth/`. The assembly toolchain lives in `asm/src/` and is C-based.

## Architecture

### Signal Naming Conventions
- `i_` = input, `o_` = output, `w_` = combinatorial wire, `r_` = registered (flip-flop)

### Key Parameters (defined in `rtl/include/dc.svh`)
- `DC_INSN_WIDTH` = 72 bits — packed instruction format (sized to fit Xilinx BRAM width)
- `DC_DEPTH` = 512 — instructions per channel
- `DC_CORE_ITER_WIDTH` = 8 bits — iterations per instruction (max 256)
- `DC_SEQ_ITER_WIDTH` = 10 bits — sequence repeats (max 1024)
- `SPI_DATA_WIDTH` = 24 bits — matches AD5791 DAC

The 72-bit instruction is composed of: `DC_CORE_ITER_WIDTH(8)` + `DC_SPI_DATA_WIDTH(24)` + `DC_DELTA_WIDTH(16)` + `DC_CYCLE_WIDTH(18)` + 6 control flags.

### Module Hierarchy

```
rtl/synth/top.sv          — FPGA top: wires processor, UART, and IO
  rtl/src/processor.sv    — Instantiates 24 DC channels + launch controller
    rtl/src/dc.sv         — DC channel: wraps seq + core + ctrl
      rtl/src/serial_sequencer.sv  — Dual-port BRAM instruction memory, PC tracking
      rtl/src/dc_core.sv           — Pipelined execution: decode → iterate → SPI → hold
      rtl/src/dc_ctrl.sv           — SPI clock divider and CS/LDAC timing config
      rtl/src/dc_decode.sv         — Instruction field extraction
    rtl/src/launch.sv     — Synchronizes trigger across all 24 channels
  rtl/src/uart_regs.sv    — 32-bit register file bridging UART to processor
  rtl/lib/uart.sv         — 115200-baud UART transceiver with 8-entry FIFOs
```

### DC Channel Execution Pipeline

Each of the 24 channels runs independently:
1. `serial_sequencer` fetches the current instruction from BRAM and manages the program counter and loop iteration counts.
2. `dc_core` executes a 4-stage pipeline: decode → iterate → SPI → hold. Bubble insertion handles structural hazards.
3. `dc_ctrl` provides timing parameters (SPI clock divider, CS assert/deassert delays, LDAC pulse width).
4. Instructions are 72 bits wide (`dc_insn_t`) and include: SPI data (24b), delta (16b), hold cycles (18b), iteration count (8b), and control flags (`arm`, `sticky_arm`, `modify`, `strobe_ldac`, `marker`, `idle`).

### Launch Controller (`rtl/src/launch.sv`)

Waits until all 24 channels report `armed`, then fires a single-cycle start pulse synchronously. Supports external trigger input or free-running mode. Manages global iteration loops across the whole processor.

### Host Interface

The host communicates over UART → `uart_regs` → processor registers:
- DC instruction writes: `DC_IST_REG_LO` to `DC_IST_REG_HI`
- Launch parameters: `LCH_CTRL_START` to `LCH_CTRL_END`
- Marker channel selects: `MARKER_SEL_START` to `MARKER_SEL_END`

Edge detectors (`rtl/lib/edge_detector.sv`) convert level-based register strobes into single-cycle pulses for instruction writes, control updates, and trigger detection.

### Simulation Infrastructure

- Testbenches: `rtl/tb/` — per-module behavioral tests
- Top-level sim model: `rtl/sim/simulator2.sv`
- Waveforms in FSDB format (`inter.fsdb`, `run.fsdb`), viewed in Verdi
- Behavioral models for AD4080 ADC and AD9833 signal generator live in `rtl/sim/`

### Assembly Language

Experiment programs in `exp/` use a custom assembly format parsed by `asm/src/`. Key mnemonics:
- `swp` — DAC voltage set/sweep
- `lvl` — level hold for a specified duration
- `ful` — full SPI instruction (raw control)
- `.repeat` / `.launch` — loop and trigger directives

The assembler generates UART register-write sequences that the host sends to load programs into the 24 channel BRAMs.

### ADC & DDR3 (optional subsystems)
- `rtl/src/adc/` — AD4080 SPI ADC capture, async FIFO for clock crossing, DDR3 burst writer
- `rtl/src/ddr3/` — AXI4 master to Xilinx MIG for DDR3 writes
- `rtl/src/signal_gen/` — AD9833 waveform generator (SPI-controlled)
