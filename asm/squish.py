#!/home/shizeche/software/venv/bin/python3
"""
squish.py - DC sequencer assembler for swashispin-mini

Usage:
    squish.py -f input.asm [-o out.txt] [-u uart.txt] [-m mem_dir/] [-x /dev/ttyUSBx] [--baud N]

Assembly syntax (unchanged from C assembler):
    .program dc<N>
    .dvsr <val>          ; SPI clock divisor (optional)
    .dlay <val>          ; SPI delay cycles (optional)
    .csup <val>          ; CS hold-up cycles (optional)
    .ldac <val>          ; LDAC strobe cycles (optional)
    .repeat <count>      ; outer sequence iteration count
    swp v1=<V> v2=<V> n=<steps> dt=<time> (<opts>)
    lvl v=<V> t=<time> (<opts>)
    set <reg> <hex> (<opts>)
    get <reg> (<opts>)
    nop (<opts>)
    ful its=<n> din=<hex24> cyc=<n> (<opts>)

    .launch
    <dc_chmask_hex>

Options in (): arm  rd  ldc  v+<voltage>  mk  srm
Time units: ns us ms s
    -r dc<N>   read back BRAM instructions and runtime status for channel N
"""

import argparse
import math
import os
import re
import sys
from dataclasses import dataclass, field
from typing import Optional

# ── Hardware constants ───────────────────────────────────────────────────────
VMIN           = -10.0
VMAX           =  10.0
DAC_BITS       = 20
DELTA_BITS     = 16
CYCLE_BITS     = 18
INSN_ITER_BITS = 8    # per-instruction iteration counter width
SPI_DATA_BITS  = 24
INSN_WIDTH     = 72   # INSN_ITER_BITS + SPI_DATA_BITS + DELTA_BITS + CYCLE_BITS + 6
REG_PER_INSN   = 3    # ceil(72/32)
NS_PER_CYCLE   = 10
MAX_HOLD_CYCLES = (1 << CYCLE_BITS) - 1
MAX_INSN_ITERS  = (1 << INSN_ITER_BITS) - 1
CTRL_BITS      = 16   # dvsr, dlay, csup, ldac register widths
REPEAT_BITS    = 16   # outer sequence repeat count
MAX_CTRL       = (1 << CTRL_BITS) - 1
MAX_REPEAT     = (1 << REPEAT_BITS) - 1
DC_CHANNELS    = 24
DC_DEPTH       = 512  # max instructions per channel
SIM_BIT_NS     = 1085              # localparam bit_duration in simulator2.sv
SIM_FRAME_NS   = 10 * SIM_BIT_NS  # start + 8 data + stop bits per UART byte

# ── Global register map ──────────────────────────────────────────────────────
# These are shared across all channels; channel selection via strobe bit[n].
IST_ADDR_REG   = 0   # BRAM write/load address (9-bit)
IST_REG_LO     = 1   # insn[71:64] in bits [7:0] of this register
                      # insn[63:32] goes in reg 2
IST_REG_HI     = 3   # insn[31:0]
IST_STRB_REG   = 4   # posedge of bit[n] → write to channel n BRAM
ILD_STRB_REG   = 5   # level bit[n]=1 → mux channel n insn_rd; posedge → latch BRAM[addr]
ITERS_REG      = 6   # outer sequence repeat count (16-bit)
DEPTH_REG      = 7   # num_instructions - 1 (9-bit)
START_STRB_REG = 8   # posedge of bit[n] → start channel n
HALT_STRB_REG  = 9   # posedge of bit[n] → halt channel n
CTRL_DVSR_REG  = 10
CTRL_DELAY_REG = 11
CTRL_CSUP_REG  = 12
CTRL_LDAC_REG  = 13
CTRL_STRB_REG  = 14  # posedge of bit[n] → apply ctrl to channel n

# Read-only register base address in r_regs[] = WRITE_REGS + o_regs offset
WRITE_REGS     = 23  # DC_SEQ_REGS(10)+DC_CTRL_REGS(5)+LCH_CTRL_REGS(5)+MARKER(3)
RO_ILD_BASE    = 0   # 3-reg instruction readout slot (muxed by ILD_STRB_REG level)
RO_EMPTY_REG   = 3   # bit[n] = channel n empty
RO_ARMED_REG   = 4   # bit[n] = channel n armed
RO_ITERS_BASE  = 5   # per-channel runtime iters remaining (10-bit), one reg each
RO_DEPTH_BASE  = 29  # per-channel depth latched at start (9-bit), one reg each
RO_LCH_ITERS   = 53  # launch controller iters remaining (32-bit)
LCH_MASK_REG   = 15  # i_regs[0]: launch DC channel mask
LCH_TRIG_REG   = 16  # i_regs[1]: use_trigger flag (0 = free-running)
LCH_ITERS_REG  = 17  # i_regs[2]: launch iteration count (32-bit)
LCH_CLR_REG    = 18  # i_regs[3]: clear strobe
LCH_STRB_REG   = 19  # i_regs[4]: new_ctrl strobe (posedge → apply)
MARKER_SEL_REG = 20  # marker_sel[0..2]: which DC channel index drives each marker output
NUM_MARKERS    = 3

DAC_REG_MAP = {'dr': 1, 'cr': 2, 'clr': 3, 'scr': 4}

_REG_NAMES = {
    IST_ADDR_REG:   'IST_ADDR',
    IST_REG_LO:     'IST_LO',
    IST_REG_LO + 1: 'IST_MID',
    IST_REG_HI:     'IST_HI',
    IST_STRB_REG:   'IST_STRB',
    ILD_STRB_REG:   'ILD_STRB',
    ITERS_REG:      'ITERS',
    DEPTH_REG:      'DEPTH',
    START_STRB_REG: 'START_STRB',
    HALT_STRB_REG:  'HALT_STRB',
    CTRL_DVSR_REG:  'CTRL_DVSR',
    CTRL_DELAY_REG: 'CTRL_DELAY',
    CTRL_CSUP_REG:  'CTRL_CSUP',
    CTRL_LDAC_REG:  'CTRL_LDAC',
    CTRL_STRB_REG:  'CTRL_STRB',
    LCH_MASK_REG:   'LCH_MASK',
    LCH_TRIG_REG:   'LCH_TRIG',
    LCH_ITERS_REG:  'LCH_ITERS',
    LCH_CLR_REG:        'LCH_CLR',
    LCH_STRB_REG:       'LCH_STRB',
    MARKER_SEL_REG:     'MK_SEL0',
    MARKER_SEL_REG + 1: 'MK_SEL1',
    MARKER_SEL_REG + 2: 'MK_SEL2',
}


# ── Voltage / time helpers ───────────────────────────────────────────────────

def volt_to_signed(v: float, bits: int = DAC_BITS,
                   vmin: float = VMIN, vmax: float = VMAX) -> int:
    kmin = -(1 << (bits - 1))
    kmax =  (1 << (bits - 1)) - 1
    if v <= vmin:
        return kmin
    if v >= vmax:
        return kmax
    k = round(kmin + (v - vmin) * (kmax - kmin) / (vmax - vmin))
    return max(kmin, min(kmax, k))


def volt_to_code(v: float, bits: int = DAC_BITS) -> int:
    return volt_to_signed(v, bits) & ((1 << bits) - 1)


def to_bits(val: int, bits: int) -> int:
    """Clamp signed int to range and return unsigned bit pattern."""
    kmin = -(1 << (bits - 1))
    kmax =  (1 << (bits - 1)) - 1
    return max(kmin, min(kmax, val)) & ((1 << bits) - 1)


def code_to_volt(code: int, bits: int = DAC_BITS,
                 vmin: float = VMIN, vmax: float = VMAX) -> float:
    kmin = -(1 << (bits - 1))
    kmax =  (1 << (bits - 1)) - 1
    k = code if code < (1 << (bits - 1)) else code - (1 << bits)
    return vmin + (k - kmin) * (vmax - vmin) / (kmax - kmin)


def parse_time(s: str) -> int:
    """Parse '10ns', '1us', '1ms', '1s' → integer nanoseconds."""
    s = s.strip()
    for suffix, scale in [('ns', 1), ('us', 1_000), ('ms', 1_000_000), ('s', 1_000_000_000)]:
        if s.endswith(suffix):
            return round(float(s[:-len(suffix)]) * scale)
    raise ValueError(f"Unknown time unit: {s!r}")


def time_to_cycles(t_ns: int) -> int:
    c = max(1, round(t_ns / NS_PER_CYCLE))
    if c > MAX_HOLD_CYCLES:
        max_ns = MAX_HOLD_CYCLES * NS_PER_CYCLE
        raise ValueError(
            f"hold time {t_ns}ns ({t_ns/1e6:.3f}ms) exceeds {CYCLE_BITS}-bit max "
            f"({MAX_HOLD_CYCLES} cycles × {NS_PER_CYCLE}ns = {max_ns/1e6:.3f}ms)"
        )
    return c


# ── Instruction ──────────────────────────────────────────────────────────────

@dataclass
class DcInsn:
    iters:       int = 0   # [71:64] 8-bit per-instruction iteration count
    spi_din:     int = 0   # [63:40] 24-bit: bits[23:20]=DAC reg, bits[19:0]=DAC code
    delta:       int = 0   # [39:24] 16-bit signed (two's complement bit pattern)
    strb_ldac:   int = 0   # [23]    1-bit
    hold_cycles: int = 0   # [22:5]  18-bit
    modify:      int = 0   # [4]     1-bit: apply delta as secondary DAC output
    arm:         int = 0   # [3]     1-bit
    sticky_arm:  int = 0   # [2]     1-bit: arm that does not get cleared
    idle:        int = 0   # [1]     1-bit: skip SPI transaction
    marker:      int = 0   # [0]     1-bit: digital marker output

    def encode(self) -> int:
        v  = (self.iters       & 0xFF)     << 64
        v |= (self.spi_din     & 0xFFFFFF) << 40
        v |= (self.delta       & 0xFFFF)   << 24
        v |= (self.strb_ldac   & 0x1)      << 23
        v |= (self.hold_cycles & 0x3FFFF)  << 5
        v |= (self.modify      & 0x1)      << 4
        v |= (self.arm         & 0x1)      << 3
        v |= (self.sticky_arm  & 0x1)      << 2
        v |= (self.idle        & 0x1)      << 1
        v |= (self.marker      & 0x1)
        return v

    def to_regs(self) -> tuple[int, int, int]:
        """
        Split 72-bit instruction into 3 × 32-bit words for IST_REG_LO..IST_REG_HI.

        The serial_sequencer reconstructs as {reg[LO], reg[LO+1], reg[HI]}[71:0]:
          insn[71:64] ← reg[LO][7:0]
          insn[63:32] ← reg[LO+1][31:0]
          insn[31:0]  ← reg[HI][31:0]
        """
        v = self.encode()
        return (v >> 64) & 0xFF, (v >> 32) & 0xFFFFFFFF, v & 0xFFFFFFFF


# ── Instruction decode / display ────────────────────────────────────────────

def decode_insn(v: int) -> 'DcInsn':
    return DcInsn(
        iters       = (v >> 64) & 0xFF,
        spi_din     = (v >> 40) & 0xFFFFFF,
        delta       = (v >> 24) & 0xFFFF,
        strb_ldac   = (v >> 23) & 0x1,
        hold_cycles = (v >> 5)  & 0x3FFFF,
        modify      = (v >> 4)  & 0x1,
        arm         = (v >> 3)  & 0x1,
        sticky_arm  = (v >> 2)  & 0x1,
        idle        = (v >> 1)  & 0x1,
        marker      = v         & 0x1,
    )


_REG_CODE_TO_NAME = {v: k for k, v in DAC_REG_MAP.items()}


def _format_time(ns: int) -> str:
    """Convert nanoseconds to the most readable time unit string."""
    if ns >= 1_000_000_000 and ns % 1_000_000_000 == 0:
        return f"{ns // 1_000_000_000}s"
    if ns >= 1_000_000 and ns % 1_000_000 == 0:
        return f"{ns // 1_000_000}ms"
    if ns >= 1_000 and ns % 1_000 == 0:
        return f"{ns // 1_000}us"
    return f"{ns}ns"


def _delta_signed(delta: int) -> int:
    """Interpret 16-bit delta field as a signed integer."""
    return delta if delta < 0x8000 else delta - 0x10000


def _opts_str(insn: DcInsn, include_ldc: bool = False, include_vplus: bool = False) -> str:
    """Build the options string (without outer parens)."""
    flags = []
    if include_vplus and insn.modify:
        # delta holds volt_to_signed(vplus, 20) truncated to 16 bits; recover via sign-extension
        vplus = code_to_volt(_delta_signed(insn.delta), bits=20)
        flags.append(f"v+{vplus:.4f}")
    if include_ldc and insn.strb_ldac:
        flags.append("ldc")
    if insn.arm:
        flags.append("arm")
    if insn.sticky_arm:
        flags.append("srm")
    if insn.marker:
        flags.append("mk")
    return " ".join(flags)


def format_insn(insn: DcInsn) -> str:
    """Reconstruct assembly source line from a decoded instruction."""

    if insn.idle:
        opts = _opts_str(insn, include_ldc=True, include_vplus=True)
        return f"nop ({opts})" if opts else "nop"

    is_rd    = bool((insn.spi_din >> 23) & 1)
    dac_reg  = (insn.spi_din >> 20) & 0x7
    dac_code = insn.spi_din & 0xFFFFF
    reg_name = _REG_CODE_TO_NAME.get(dac_reg, f"r{dac_reg}")

    if is_rd:
        opts = _opts_str(insn, include_ldc=True)
        return f"get {reg_name} ({opts})" if opts else f"get {reg_name}"

    if dac_reg == DAC_REG_MAP['dr'] and insn.strb_ldac:
        t_str = _format_time(insn.hold_cycles * NS_PER_CYCLE)
        opts = _opts_str(insn, include_vplus=True)
        opts_part = f" ({opts})" if opts else ""

        if insn.iters == 0:
            v = code_to_volt(dac_code)
            return f"lvl v={v:+.4f} t={t_str}{opts_part}"
        else:
            # reconstruct v2 from v1 + delta * steps
            steps = insn.iters
            v1_s = dac_code if dac_code < (1 << 19) else dac_code - (1 << 20)
            dv   = _delta_signed(insn.delta)
            v2_code = (v1_s + dv * steps) & 0xFFFFF
            v1 = code_to_volt(dac_code)
            v2 = code_to_volt(v2_code)
            return f"swp v1={v1:+.4f} v2={v2:+.4f} n={steps + 1} dt={t_str}{opts_part}"

    if dac_reg != DAC_REG_MAP['dr'] and not is_rd:
        opts = _opts_str(insn, include_ldc=True, include_vplus=True)
        return f"set {reg_name} 0x{dac_code:05X} ({opts})" if opts else f"set {reg_name} 0x{dac_code:05X}"

    # raw fallback for anything that doesn't fit a clean mnemonic
    opts = _opts_str(insn, include_ldc=True, include_vplus=True)
    opts_part = f" ({opts})" if opts else ""
    return f"ful its={insn.iters} din={insn.spi_din:06X} cyc={insn.hold_cycles}{opts_part}"


# ── Option parsing ───────────────────────────────────────────────────────────

def parse_opts(paren: str) -> dict:
    opts = {'arm': 0, 'rd': 0, 'ldc': 0, 'has_vplus': 0, 'vplus': 0.0, 'mk': 0, 'srm': 0}
    for tok in paren.split():
        if tok == 'arm':
            opts['arm'] = 1
        elif tok == 'rd':
            opts['rd'] = 1
        elif tok == 'ldc':
            opts['ldc'] = 1
        elif tok == 'mk':
            opts['mk'] = 1
        elif tok == 'srm':
            opts['srm'] = 1
        elif tok.startswith('v+'):
            opts['has_vplus'] = 1
            opts['vplus'] = float(tok[2:])
        else:
            raise ValueError(f"Unknown option: {tok!r}")
    return opts


def get_opts(line: str) -> dict:
    m = re.search(r'\(([^)]*)\)', line)
    return parse_opts(m.group(1)) if m else {'arm': 0, 'rd': 0, 'ldc': 0, 'has_vplus': 0, 'vplus': 0.0, 'mk': 0, 'srm': 0}


# ── Instruction parsers ──────────────────────────────────────────────────────

def parse_swp(line: str) -> DcInsn:
    m = re.match(r'\s*swp\s+v1=(\S+)\s+v2=(\S+)\s+n=(\d+)\s+dt=([^\s(]+)', line)
    if not m:
        raise ValueError(f"Bad swp: {line!r}")
    v1, v2, n, dt = float(m[1]), float(m[2]), int(m[3]), parse_time(m[4])
    opts = get_opts(line)
    if not (VMIN <= v1 <= VMAX and VMIN <= v2 <= VMAX):
        raise ValueError(f"Voltage out of [{VMIN},{VMAX}] in: {line!r}")
    if not (1 < n <= MAX_INSN_ITERS + 1):
        raise ValueError(f"n={n} out of range in: {line!r}")
    steps = n - 1
    v1_s  = volt_to_signed(v1)
    v2_s  = volt_to_signed(v2)
    diff  = v2_s - v1_s

    # Ceiling magnitude so the sweep reaches or slightly exceeds v2
    if diff >= 0:
        dv = math.ceil(diff / steps)
    else:
        dv = -math.ceil(-diff / steps)

    # Reject if delta exceeds the 16-bit signed hardware field
    kmin_delta = -(1 << (DELTA_BITS - 1))
    kmax_delta =  (1 << (DELTA_BITS - 1)) - 1
    if abs(dv) > kmax_delta:
        min_n = math.ceil(abs(diff) / kmax_delta) + 1
        raise ValueError(
            f"swp: required delta {abs(dv)} codes/step exceeds 16-bit max {kmax_delta}. "
            f"Use at least n={min_n} to sweep {v1}V→{v2}V"
        )

    # Prevent 20-bit DAC accumulator wrap-around: if v1 + dv*steps overflows
    # the signed DAC range, pull dv back to the largest safe integer step
    kmin_dac = -(1 << (DAC_BITS - 1))
    kmax_dac =  (1 << (DAC_BITS - 1)) - 1
    final_code = v1_s + dv * steps
    if final_code > kmax_dac:
        dv = (kmax_dac - v1_s) // steps
    elif final_code < kmin_dac:
        dv = -((v1_s - kmin_dac) // steps)

    return DcInsn(
        iters       = steps,
        spi_din     = (1 << 20) | volt_to_code(v1),
        delta       = to_bits(dv, DELTA_BITS),
        strb_ldac   = 1,
        hold_cycles = time_to_cycles(dt),
        modify      = 0,
        arm         = opts['arm'],
        sticky_arm  = opts['srm'],
        marker      = opts['mk'],
    )


def parse_lvl(line: str) -> DcInsn:
    m = re.match(r'\s*lvl\s+v=(\S+)\s+t=([^\s(]+)', line)
    if not m:
        raise ValueError(f"Bad lvl: {line!r}")
    v, t = float(m[1]), parse_time(m[2])
    opts = get_opts(line)
    if not (VMIN <= v <= VMAX):
        raise ValueError(f"Voltage out of range in: {line!r}")
    vplus_delta = to_bits(volt_to_signed(opts['vplus']), DELTA_BITS) if opts['has_vplus'] else 0
    return DcInsn(
        iters       = 0,
        spi_din     = (1 << 20) | volt_to_code(v),
        delta       = vplus_delta,
        strb_ldac   = 1,
        hold_cycles = time_to_cycles(t),
        modify      = opts['has_vplus'],
        arm         = opts['arm'],
        sticky_arm  = opts['srm'],
        marker      = opts['mk'],
    )


def parse_set(line: str) -> DcInsn:
    m = re.match(r'\s*set\s+(\w+)\s+(?:0[xX])?([0-9a-fA-F]+)', line)
    if not m:
        raise ValueError(f"Bad set: {line!r}")
    reg_name, din = m[1], int(m[2], 16)
    if reg_name not in DAC_REG_MAP:
        raise ValueError(f"Unknown DAC register {reg_name!r} in: {line!r}")
    if din > (1 << DAC_BITS) - 1:
        raise ValueError(
            f"set din 0x{din:X} exceeds {DAC_BITS}-bit DAC field (max 0x{(1<<DAC_BITS)-1:X}) in: {line!r}"
        )
    opts = get_opts(line)
    vplus_delta = to_bits(volt_to_signed(opts['vplus']), DELTA_BITS) if opts['has_vplus'] else 0
    return DcInsn(
        spi_din    = (DAC_REG_MAP[reg_name] << 20) | (din & 0xFFFFF),
        delta      = vplus_delta,
        strb_ldac  = opts['ldc'],
        modify     = opts['has_vplus'],
        arm        = opts['arm'],
        sticky_arm = opts['srm'],
        marker     = opts['mk'],
    )


def parse_get(line: str) -> DcInsn:
    m = re.match(r'\s*get\s+(\w+)', line)
    if not m:
        raise ValueError(f"Bad get: {line!r}")
    reg_name = m[1]
    if reg_name not in DAC_REG_MAP:
        raise ValueError(f"Unknown DAC register {reg_name!r} in: {line!r}")
    opts = get_opts(line)
    return DcInsn(
        spi_din    = (1 << 23) | (DAC_REG_MAP[reg_name] << 20),
        strb_ldac  = opts['ldc'],
        arm        = opts['arm'],
        sticky_arm = opts['srm'],
        marker     = opts['mk'],
        idle       = 0,
    )


def parse_nop(line: str) -> DcInsn:
    opts = get_opts(line)
    vplus_delta = to_bits(volt_to_signed(opts['vplus']), DELTA_BITS) if opts['has_vplus'] else 0
    return DcInsn(
        delta      = vplus_delta,
        strb_ldac  = opts['ldc'],
        modify     = opts['has_vplus'],
        arm        = opts['arm'],
        sticky_arm = opts['srm'],
        marker     = opts['mk'],
        idle       = 1,
    )


def parse_ful(line: str) -> DcInsn:
    m = re.match(r'\s*ful\s+its=(\d+)\s+din=([0-9a-fA-F]+)\s+cyc=(\d+)', line)
    if not m:
        raise ValueError(f"Bad ful: {line!r}")
    its, din, cyc = int(m[1]), int(m[2], 16), int(m[3])
    if its > MAX_INSN_ITERS:
        raise ValueError(
            f"ful its={its} exceeds {INSN_ITER_BITS}-bit max {MAX_INSN_ITERS} in: {line!r}"
        )
    if din > (1 << SPI_DATA_BITS) - 1:
        raise ValueError(
            f"ful din 0x{din:X} exceeds {SPI_DATA_BITS}-bit SPI field (max 0x{(1<<SPI_DATA_BITS)-1:X}) in: {line!r}"
        )
    if cyc > MAX_HOLD_CYCLES:
        max_ns = MAX_HOLD_CYCLES * NS_PER_CYCLE
        raise ValueError(
            f"ful cyc={cyc} exceeds {CYCLE_BITS}-bit max {MAX_HOLD_CYCLES} "
            f"(= {max_ns/1e6:.3f}ms) in: {line!r}"
        )
    opts = get_opts(line)
    vplus_delta = to_bits(volt_to_signed(opts['vplus']), DELTA_BITS) if opts['has_vplus'] else 0
    return DcInsn(
        iters       = its,
        spi_din     = din,
        delta       = vplus_delta,
        hold_cycles = cyc,
        strb_ldac   = opts['ldc'],
        modify      = opts['has_vplus'],
        arm         = opts['arm'],
        sticky_arm  = opts['srm'],
        marker      = opts['mk'],
    )


INSN_PARSERS = {
    'swp': parse_swp, 'lvl': parse_lvl, 'set': parse_set,
    'get': parse_get, 'nop': parse_nop, 'ful': parse_ful,
}


# ── Program data structures ──────────────────────────────────────────────────

@dataclass
class DcCtrl:
    dvsr:         Optional[int] = None
    delay_cycles: Optional[int] = None
    cs_up_cycles: Optional[int] = None
    ldac_cycles:  Optional[int] = None


@dataclass
class DcProgram:
    channel: int               = 0
    ctrl:    DcCtrl            = field(default_factory=DcCtrl)
    repeat:  int               = 1
    insns:   list[DcInsn]      = field(default_factory=list)


@dataclass
class Launch:
    dc_chmask:   int = 0
    iters:       int = 1
    use_trigger: int = 0
    marker_sels: Optional[list[int]] = None  # length-3 list of DC channel indices, one per marker output


# ── Assembly file parser ─────────────────────────────────────────────────────

def line_empty(s: str) -> bool:
    s = s.strip()
    return not s or s.startswith(';')


def parse_asm(text: str) -> tuple[list[DcProgram], Optional[Launch]]:
    lines   = text.splitlines()
    programs: list[DcProgram] = []
    launch: Optional[Launch]  = None
    i = 0

    while i < len(lines):
        ln = lines[i]
        if line_empty(ln):
            i += 1
            continue

        m = re.match(r'\s*\.program\s+dc(\d+)', ln)
        if m:
            prog = DcProgram(channel=int(m[1]))
            i += 1

            # ctrl directives
            while i < len(lines):
                ln = lines[i]
                if line_empty(ln):
                    i += 1
                    continue
                mc = re.match(r'\s*\.dvsr\s+(\d+)', ln)
                if mc:
                    val = int(mc[1])
                    if val > MAX_CTRL:
                        raise ValueError(f".dvsr {val} exceeds {CTRL_BITS}-bit max {MAX_CTRL}")
                    prog.ctrl.dvsr = val
                    i += 1
                    continue
                mc = re.match(r'\s*\.dlay\s+(\d+)', ln)
                if mc:
                    val = int(mc[1])
                    if val > MAX_CTRL:
                        raise ValueError(f".dlay {val} exceeds {CTRL_BITS}-bit max {MAX_CTRL}")
                    prog.ctrl.delay_cycles = val
                    i += 1
                    continue
                mc = re.match(r'\s*\.csup\s+(\d+)', ln)
                if mc:
                    val = int(mc[1])
                    if val > MAX_CTRL:
                        raise ValueError(f".csup {val} exceeds {CTRL_BITS}-bit max {MAX_CTRL}")
                    prog.ctrl.cs_up_cycles = val
                    i += 1
                    continue
                mc = re.match(r'\s*\.ldac\s+(\d+)', ln)
                if mc:
                    val = int(mc[1])
                    if val > MAX_CTRL:
                        raise ValueError(f".ldac {val} exceeds {CTRL_BITS}-bit max {MAX_CTRL}")
                    prog.ctrl.ldac_cycles = val
                    i += 1
                    continue
                mc = re.match(r'\s*\.repeat\s+(\d+)', ln)
                if mc:
                    val = int(mc[1])
                    if val > MAX_REPEAT:
                        raise ValueError(f".repeat {val} exceeds {REPEAT_BITS}-bit max {MAX_REPEAT}")
                    prog.repeat = val
                    i += 1
                    break
                raise ValueError(f"Expected .repeat or ctrl directive, got: {ln!r}")

            # instructions
            while i < len(lines):
                ln = lines[i]
                if line_empty(ln):
                    i += 1
                    continue
                op = ln.strip().split()[0] if ln.strip() else ''
                if op in INSN_PARSERS:
                    if len(prog.insns) >= DC_DEPTH:
                        raise ValueError(f"dc{prog.channel}: exceeded max depth {DC_DEPTH}")
                    prog.insns.append(INSN_PARSERS[op](ln))
                    i += 1
                else:
                    break

            if not prog.insns:
                raise ValueError(f"dc{prog.channel} has no instructions")
            programs.append(prog)
            continue

        m = re.match(r'\s*\.launch(.*)', ln)
        if m:
            launch = Launch()
            rest = m.group(1).strip()
            i += 1
            # optional iteration count: x<n> as first token
            x_m = re.match(r'x(\d+)\s*(.*)', rest)
            if x_m:
                launch.iters = int(x_m[1])
                rest = x_m[2].strip()
            # optional (trig) flag at end
            trig_m = re.search(r'\(trig\)\s*$', rest)
            if trig_m:
                launch.use_trigger = 1
                rest = rest[:trig_m.start()].strip()
            if rest:
                # inline: .launch dc0 dc1 ... or .launch dc0-23
                mask = 0
                for tok in rest.split():
                    rng = re.match(r'dc(\d+)-(\d+)$', tok)
                    if rng:
                        for ch in range(int(rng[1]), int(rng[2]) + 1):
                            mask |= 1 << ch
                    else:
                        ch_m = re.match(r'dc(\d+)$', tok)
                        if ch_m:
                            mask |= 1 << int(ch_m[1])
                        else:
                            raise ValueError(f".launch: unexpected token {tok!r}")
                launch.dc_chmask = mask
            else:
                # legacy: hex mask on next non-empty line
                while i < len(lines):
                    ln = lines[i].strip()
                    if line_empty(ln):
                        i += 1
                        continue
                    launch.dc_chmask = int(ln, 16)
                    i += 1
                    break
            continue

        m = re.match(r'\s*\.marker\s+(.*)', ln)
        if m:
            toks = m.group(1).split()
            if len(toks) != NUM_MARKERS:
                raise ValueError(f".marker: expected {NUM_MARKERS} dc channels, got {len(toks)}: {toks}")
            sels = []
            for tok in toks:
                ch_m = re.match(r'dc(\d+)$', tok)
                if not ch_m:
                    raise ValueError(f".marker: expected dc<N>, got {tok!r}")
                ch = int(ch_m[1])
                if ch >= DC_CHANNELS:
                    raise ValueError(f".marker: dc{ch} out of range (max dc{DC_CHANNELS-1})")
                sels.append(ch)
            if launch is None:
                launch = Launch()
            launch.marker_sels = sels
            i += 1
            continue

        raise ValueError(f"Unexpected line {i+1}: {lines[i]!r}")

    return programs, launch


# ── Register write helpers ───────────────────────────────────────────────────

Ops = list[tuple[int, int]]   # list of (reg_addr, 32-bit data)


def reg_bytes(reg: int, data: int) -> bytes:
    return bytes([reg & 0xFF, (data >> 24) & 0xFF,
                  (data >> 16) & 0xFF, (data >> 8) & 0xFF, data & 0xFF])


def strobe(reg: int, mask: int) -> Ops:
    """Clear → assert → clear for edge-detected strobes."""
    return [(reg, 0), (reg, mask), (reg, 0)]


def load_ops(prog: DcProgram) -> Ops:
    ops: Ops = []
    n = prog.channel
    mask = 1 << n

    # ctrl registers
    if prog.ctrl.dvsr is not None:
        ops.append((CTRL_DVSR_REG, prog.ctrl.dvsr & 0xFFFF))
    if prog.ctrl.delay_cycles is not None:
        ops.append((CTRL_DELAY_REG, prog.ctrl.delay_cycles & 0xFFFF))
    if prog.ctrl.cs_up_cycles is not None:
        ops.append((CTRL_CSUP_REG, prog.ctrl.cs_up_cycles & 0xFFFF))
    if prog.ctrl.ldac_cycles is not None:
        ops.append((CTRL_LDAC_REG, prog.ctrl.ldac_cycles & 0xFFFF))
    if any(v is not None for v in [prog.ctrl.dvsr, prog.ctrl.delay_cycles,
                                    prog.ctrl.cs_up_cycles, prog.ctrl.ldac_cycles]):
        ops.extend(strobe(CTRL_STRB_REG, mask))

    # load instructions into BRAM
    for addr, insn in enumerate(prog.insns):
        r0, r1, r2 = insn.to_regs()
        ops.append((IST_ADDR_REG, addr))
        ops.append((IST_REG_LO,     r0))   # insn[71:64]
        ops.append((IST_REG_LO + 1, r1))   # insn[63:32]
        ops.append((IST_REG_HI,     r2))   # insn[31:0]
        ops.extend(strobe(IST_STRB_REG, mask))

    ops.append((ITERS_REG, prog.repeat & 0xFFFF))
    ops.append((DEPTH_REG, (len(prog.insns) - 1) & 0x1FF))
    return ops


def start_ops(prog: DcProgram) -> Ops:
    return strobe(START_STRB_REG, 1 << prog.channel)


def launch_ops(launch: Launch) -> Ops:
    ops: Ops = [
        (LCH_MASK_REG,  launch.dc_chmask),
        (LCH_TRIG_REG,  launch.use_trigger & 1),
        (LCH_ITERS_REG, launch.iters),
    ]
    ops.extend(strobe(LCH_STRB_REG, 1))
    if launch.marker_sels is not None:
        for idx, ch in enumerate(launch.marker_sels):
            ops.append((MARKER_SEL_REG + idx, ch & 0x1F))
    return ops


def clear_launch_ops() -> Ops:
    return strobe(LCH_CLR_REG, 1)


# ── Output writers ───────────────────────────────────────────────────────────

def write_uart_seq(programs: list[DcProgram], launch: Optional[Launch], path: str) -> None:
    with open(path, 'w') as f:
        for prog in programs:
            f.write(f"; dc{prog.channel} load\n")
            for reg, data in load_ops(prog):
                f.write(f"0x{reg:02X} 0x{data:08X}\n")
            f.write(f"; dc{prog.channel} start\n")
            for reg, data in start_ops(prog):
                f.write(f"0x{reg:02X} 0x{data:08X}\n")
            f.write("\n")
        if launch:
            f.write("; launch\n")
            for reg, data in launch_ops(launch):
                f.write(f"0x{reg:02X} 0x{data:08X}\n")


def write_mem_files(programs: list[DcProgram], outdir: str) -> None:
    """Write one $readmemh-compatible file per channel (18 hex digits per instruction)."""
    os.makedirs(outdir, exist_ok=True)
    for prog in programs:
        path = os.path.join(outdir, f"dc{prog.channel}.mem")
        with open(path, 'w') as f:
            for insn in prog.insns:
                f.write(f"{insn.encode():018x}\n")


def write_bin_file(programs: list[DcProgram], launch: Optional[Launch], path: str) -> None:
    with open(path, 'w') as f:
        for prog in programs:
            f.write(f"dc{prog.channel}\n")
            for reg, data in load_ops(prog):
                f.write(f"0x{reg:02X} 0x{data:08X}\n")
            f.write("\n")
        if launch:
            f.write("launch\n")
            f.write(f"0x{launch.dc_chmask:08X}\n\n")


def send_via_serial(programs: list[DcProgram], launch: Optional[Launch],
                    port: str, baud: int = 921600, clear: bool = False,
                    verbose: bool = False) -> None:
    try:
        import serial
    except ImportError:
        sys.exit("pyserial not installed — run: pip install pyserial")

    def _write(ser, reg: int, data: int) -> None:
        bs = reg_bytes(reg, data)
        if verbose:
            name = _REG_NAMES.get(reg, f'reg{reg}')
            print(f"  WRITE {name}[{reg}] = 0x{data:08X}  bytes: [{', '.join(f'0x{b:02X}' for b in bs)}]")
        ser.write(bs)

    with serial.Serial(port, baud, timeout=1) as ser:
        if clear:
            print("Clearing launch controller...")
            for reg, data in clear_launch_ops():
                _write(ser, reg, data)
        for prog in programs:
            print(f"Loading dc{prog.channel} ({len(prog.insns)} insns)...")
            for reg, data in load_ops(prog):
                _write(ser, reg, data)
            for reg, data in start_ops(prog):
                _write(ser, reg, data)
        if launch:
            print(f"Launch mask: 0x{launch.dc_chmask:06X}")
            for reg, data in launch_ops(launch):
                _write(ser, reg, data)


def send_via_sim(programs: list[DcProgram], launch: Optional[Launch],
                 sock_path: str = '/tmp/tb_cmd.sock', extra_ns: int = 1000,
                 clear: bool = False, verbose: bool = False) -> None:
    """
    Send register writes to the RTL simulator via Unix domain socket.

    The simulator (simulator2.sv) reads lines from the socket:
      '0xHH\\n'   — transmit one UART byte through pc_tsmt
      'run <ns>\\n' — advance simulation by <ns> nanoseconds
    """
    import socket as _socket

    sock = _socket.socket(_socket.AF_UNIX, _socket.SOCK_STREAM)
    try:
        sock.connect(sock_path)
    except FileNotFoundError:
        sys.exit(f"Simulator socket not found: {sock_path!r} — is the simulator running?")
    except ConnectionRefusedError:
        sys.exit(f"Simulator not accepting connections on {sock_path!r}")

    fp = sock.makefile('w', buffering=1)

    def send_byte(b: int) -> None:
        fp.write(f"0x{b:02X}\n")

    def send_reg(reg: int, data: int) -> None:
        bs = reg_bytes(reg, data)
        if verbose:
            name = _REG_NAMES.get(reg, f'reg{reg}')
            print(f"  WRITE {name}[{reg}] = 0x{data:08X}  bytes: [{', '.join(f'0x{b:02X}' for b in bs)}]")
        for b in bs:
            send_byte(b)

    print(f"Connected to simulator at {sock_path!r}")

    if clear:
        print("Clearing launch controller...")
        for reg, data in clear_launch_ops():
            send_reg(reg, data)

    for prog in programs:
        print(f"Loading dc{prog.channel} ({len(prog.insns)} insns)...")
        for reg, data in load_ops(prog):
            send_reg(reg, data)
        for reg, data in start_ops(prog):
            send_reg(reg, data)

    if launch:
        print(f"Launch mask: 0x{launch.dc_chmask:06X}")
        for reg, data in launch_ops(launch):
            send_reg(reg, data)

    run_ns = estimate_ns(programs) + extra_ns
    print(f"run {run_ns} ns")
    fp.write(f"run {run_ns}\n")

    fp.close()
    sock.close()


def read_via_serial(channel: int, port: str, baud: int = 921600,
                    verbose: bool = False) -> None:
    """Read BRAM contents and runtime status for one DC channel via real UART."""
    try:
        import serial
    except ImportError:
        sys.exit("pyserial not installed — run: pip install pyserial")

    with serial.Serial(port, baud, timeout=2) as ser:
        def send_reg(reg: int, data: int) -> None:
            bs = reg_bytes(reg, data)
            if verbose:
                name = _REG_NAMES.get(reg, f'reg{reg}')
                print(f"  WRITE {name}[{reg}] = 0x{data:08X}  bytes: [{', '.join(f'0x{b:02X}' for b in bs)}]")
            ser.write(bs)

        def uart_read(reg_addr: int) -> int:
            if verbose:
                name = _REG_NAMES.get(reg_addr, f'reg{reg_addr}')
                print(f"  READ  {name}[{reg_addr}]")
            ser.write(bytes([0x80 | reg_addr]))
            data = ser.read(4)
            if len(data) != 4:
                sys.exit(f"Read timeout: got {len(data)}/4 bytes for reg 0x{reg_addr:02X}")
            val = int.from_bytes(data, 'big')
            if verbose:
                print(f"         → 0x{val:08X}")
            return val

        def read_ro(ro_offset: int) -> int:
            return uart_read(WRITE_REGS + ro_offset)

        num_insns = (read_ro(RO_DEPTH_BASE + channel) & 0x1FF) + 1

        print(f"dc{channel}  insns={num_insns}")
        send_reg(ILD_STRB_REG, 0)
        for addr in range(num_insns):
            send_reg(IST_ADDR_REG, addr)
            send_reg(ILD_STRB_REG, 1 << channel)
            w0 = read_ro(RO_ILD_BASE + 0)
            w1 = read_ro(RO_ILD_BASE + 1)
            w2 = read_ro(RO_ILD_BASE + 2)
            v72 = ((w0 & 0xFF) << 64) | ((w1 & 0xFFFFFFFF) << 32) | (w2 & 0xFFFFFFFF)
            print(f"  [{addr:3d}]  {format_insn(decode_insn(v72))}")
            send_reg(ILD_STRB_REG, 0)

        iters_left = read_ro(RO_ITERS_BASE + channel)
        empty      = bool((read_ro(RO_EMPTY_REG) >> channel) & 1)
        armed      = bool((read_ro(RO_ARMED_REG) >> channel) & 1)
        print(f"  iters_left={iters_left}  armed={int(armed)}  empty={int(empty)}")


def read_launch_via_serial(port: str, baud: int = 921600,
                           verbose: bool = False) -> None:
    """Read all launch controller registers via real UART."""
    try:
        import serial
    except ImportError:
        sys.exit("pyserial not installed — run: pip install pyserial")

    with serial.Serial(port, baud, timeout=2) as ser:
        def uart_read(reg_addr: int) -> int:
            if verbose:
                name = _REG_NAMES.get(reg_addr, f'reg{reg_addr}')
                print(f"  READ  {name}[{reg_addr}]")
            ser.write(bytes([0x80 | reg_addr]))
            data = ser.read(4)
            if len(data) != 4:
                sys.exit(f"Read timeout: got {len(data)}/4 bytes for reg 0x{reg_addr:02X}")
            val = int.from_bytes(data, 'big')
            if verbose:
                print(f"         → 0x{val:08X}")
            return val

        def read_wreg(waddr: int) -> int:
            return uart_read(waddr)

        def read_ro(ro_offset: int) -> int:
            return uart_read(WRITE_REGS + ro_offset)

        lch_mask       = read_wreg(LCH_MASK_REG)
        lch_trig       = read_wreg(LCH_TRIG_REG)
        lch_iters_cfg  = read_wreg(LCH_ITERS_REG)
        lch_iters_left = read_ro(RO_LCH_ITERS)
        armed_bus      = read_ro(RO_ARMED_REG)
        empty_bus      = read_ro(RO_EMPTY_REG)

    armed_chs = [i for i in range(DC_CHANNELS) if (armed_bus >> i) & 1]
    empty_chs = [i for i in range(DC_CHANNELS) if (empty_bus >> i) & 1]
    not_armed = [i for i in range(DC_CHANNELS) if (lch_mask >> i) & 1 and not (armed_bus >> i) & 1]

    print(f"launch")
    print(f"  cfg  mask=0x{lch_mask:06X}  use_trigger={lch_trig & 1}  iters={lch_iters_cfg}")
    print(f"  live iters_left={lch_iters_left}")
    print(f"  armed_bus=0x{armed_bus:06X}  empty_bus=0x{empty_bus:06X}")
    print(f"  armed chs : {armed_chs if armed_chs else 'none'}")
    print(f"  empty chs : {empty_chs if empty_chs else 'none'}")
    if not_armed:
        print(f"  in-mask not armed: {not_armed}")


def read_via_sim(channel: int, sock_path: str = '/tmp/tb_cmd.sock',
                 verbose: bool = False) -> None:
    """
    Read BRAM contents and runtime status for one DC channel from the simulator.

    Protocol per register read:
      1. Send op byte  0x80|(WRITE_REGS+ro_offset)  via the UART byte command
      2. Wait — simulator's forever block catches the 4 DUT TX bytes and streams back "0x%08x"
    Write registers (addresses 0..WRITE_REGS-1) can also be read back the same way.
    """
    import socket as _socket

    sock = _socket.socket(_socket.AF_UNIX, _socket.SOCK_STREAM)
    try:
        sock.connect(sock_path)
    except FileNotFoundError:
        sys.exit(f"Simulator socket not found: {sock_path!r} — is the simulator running?")
    except ConnectionRefusedError:
        sys.exit(f"Simulator not accepting connections on {sock_path!r}")

    fp = sock.makefile('w', buffering=1)
    rp = sock.makefile('r', buffering=1)

    def send_byte(b: int) -> None:
        fp.write(f"0x{b:02X}\n")

    def send_reg(reg: int, data: int) -> None:
        bs = reg_bytes(reg, data)
        if verbose:
            name = _REG_NAMES.get(reg, f'reg{reg}')
            print(f"  WRITE {name}[{reg}] = 0x{data:08X}  bytes: [{', '.join(f'0x{b:02X}' for b in bs)}]")
        for b in bs:
            send_byte(b)

    def uart_read(rregs_addr: int) -> int:
        """Read r_regs[rregs_addr] (write or read-only reg) via UART read op."""
        if verbose:
            name = _REG_NAMES.get(rregs_addr, f'reg{rregs_addr}')
            print(f"  READ  {name}[{rregs_addr}]")
        send_byte(0x80 | rregs_addr)
        fp.write(f"run {5 * SIM_FRAME_NS}\n")  # 1 byte out + 4 bytes back
        fp.flush()
        val = int(rp.readline().strip(), 16)
        if verbose:
            print(f"         → 0x{val:08X}")
        return val

    def read_ro(ro_offset: int) -> int:
        return uart_read(WRITE_REGS + ro_offset)

    num_insns = (read_ro(RO_DEPTH_BASE + channel) & 0x1FF) + 1

    print(f"dc{channel}  insns={num_insns}")
    send_reg(ILD_STRB_REG, 0)          # ensure strobe starts low
    for addr in range(num_insns):
        send_reg(IST_ADDR_REG, addr)   # set BRAM read address
        send_reg(ILD_STRB_REG, 1 << channel)   # posedge: latch + mux select
        w0 = read_ro(RO_ILD_BASE + 0)  # insn[71:64]
        w1 = read_ro(RO_ILD_BASE + 1)  # insn[63:32]
        w2 = read_ro(RO_ILD_BASE + 2)  # insn[31:0]
        v72 = ((w0 & 0xFF) << 64) | ((w1 & 0xFFFFFFFF) << 32) | (w2 & 0xFFFFFFFF)
        print(f"  [{addr:3d}]  {format_insn(decode_insn(v72))}")
        send_reg(ILD_STRB_REG, 0)      # clear for next posedge

    # Runtime status
    iters_left = read_ro(RO_ITERS_BASE + channel)
    empty      = bool((read_ro(RO_EMPTY_REG) >> channel) & 1)
    armed      = bool((read_ro(RO_ARMED_REG) >> channel) & 1)

    fp.close()
    rp.close()
    sock.close()

    print(f"  iters_left={iters_left}  armed={int(armed)}  empty={int(empty)}")


def read_launch_via_sim(sock_path: str = '/tmp/tb_cmd.sock',
                        verbose: bool = False) -> None:
    """Read all launch controller registers from the simulator."""
    import socket as _socket

    sock = _socket.socket(_socket.AF_UNIX, _socket.SOCK_STREAM)
    try:
        sock.connect(sock_path)
    except FileNotFoundError:
        sys.exit(f"Simulator socket not found: {sock_path!r} — is the simulator running?")
    except ConnectionRefusedError:
        sys.exit(f"Simulator not accepting connections on {sock_path!r}")

    fp = sock.makefile('w', buffering=1)
    rp = sock.makefile('r', buffering=1)

    def send_byte(b: int) -> None:
        fp.write(f"0x{b:02X}\n")

    def uart_read(rregs_addr: int) -> int:
        if verbose:
            name = _REG_NAMES.get(rregs_addr, f'reg{rregs_addr}')
            print(f"  READ  {name}[{rregs_addr}]")
        send_byte(0x80 | rregs_addr)
        fp.write(f"run {5 * SIM_FRAME_NS}\n")
        fp.flush()
        val = int(rp.readline().strip(), 16)
        if verbose:
            print(f"         → 0x{val:08X}")
        return val

    def read_wreg(waddr: int) -> int:
        return uart_read(waddr)

    def read_ro(ro_offset: int) -> int:
        return uart_read(WRITE_REGS + ro_offset)

    # Configured (write) registers
    lch_mask     = read_wreg(LCH_MASK_REG)
    lch_trig     = read_wreg(LCH_TRIG_REG)
    lch_iters_cfg = read_wreg(LCH_ITERS_REG)

    # Runtime (read-only) registers
    lch_iters_left = read_ro(RO_LCH_ITERS)
    armed_bus      = read_ro(RO_ARMED_REG)
    empty_bus      = read_ro(RO_EMPTY_REG)

    fp.close()
    rp.close()
    sock.close()

    armed_chs = [i for i in range(DC_CHANNELS) if (armed_bus >> i) & 1]
    empty_chs = [i for i in range(DC_CHANNELS) if (empty_bus >> i) & 1]
    not_armed = [i for i in range(DC_CHANNELS) if (lch_mask >> i) & 1 and not (armed_bus >> i) & 1]

    print(f"launch")
    print(f"  cfg  mask=0x{lch_mask:06X}  use_trigger={lch_trig & 1}  iters={lch_iters_cfg}")
    print(f"  live iters_left={lch_iters_left}")
    print(f"  armed_bus=0x{armed_bus:06X}  empty_bus=0x{empty_bus:06X}")
    print(f"  armed chs : {armed_chs if armed_chs else 'none'}")
    print(f"  empty chs : {empty_chs if empty_chs else 'none'}")
    if not_armed:
        print(f"  in-mask not armed: {not_armed}")


# ── Program timing estimate ──────────────────────────────────────────────────

def estimate_ns(programs: list[DcProgram]) -> int:
    best = 0
    for prog in programs:
        t = sum(
            (insn.iters + 1) * insn.hold_cycles * NS_PER_CYCLE
            for insn in prog.insns
        ) * prog.repeat
        best = max(best, t)
    return best


# ── CLI ──────────────────────────────────────────────────────────────────────

def main() -> None:
    ap = argparse.ArgumentParser(
        description="squish — DC sequencer assembler",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    ap.add_argument('-f', metavar='FILE',   help='Assembly input file')
    ap.add_argument('-o', metavar='OUT',    help='Text register-dump output')
    ap.add_argument('-u', metavar='UART',   help='UART sequence file')
    ap.add_argument('-m', metavar='MEMDIR', help='$readmemh .mem file directory')
    ap.add_argument('-x', metavar='PORT',   help='Serial port (direct execution)')
    ap.add_argument('--baud', type=int, default=921600, metavar='N',
                    help='Baud rate for -x (default 921600)')
    ap.add_argument('-s', metavar='SOCK', nargs='?', const='/tmp/tb_cmd.sock',
                    help='Simulate via RTL socket (default /tmp/tb_cmd.sock)')
    ap.add_argument('-r', metavar='CHANNEL',
                    help="Read state: dc<N> for a DC channel, 'launch' for the launch controller (uses -x port if given, else simulator socket)")
    ap.add_argument('-c', action='store_true',
                    help='Send clear strobe to launch controller (before loading, if -f given)')
    ap.add_argument('-v', action='store_true',
                    help='Verbose: print all UART register reads and writes')
    args = ap.parse_args()

    if args.r:
        if args.r == 'launch':
            if args.x and not args.s:
                read_launch_via_serial(args.x, args.baud, verbose=args.v)
            else:
                read_launch_via_sim(sock_path=args.s if args.s else '/tmp/tb_cmd.sock',
                                    verbose=args.v)
        else:
            m = re.match(r'dc(\d+)$', args.r)
            if not m:
                sys.exit(f"-r: expected dc<N> or 'launch', got {args.r!r}")
            if args.x and not args.s:
                read_via_serial(int(m[1]), args.x, args.baud, verbose=args.v)
            else:
                read_via_sim(int(m[1]), sock_path=args.s if args.s else '/tmp/tb_cmd.sock',
                             verbose=args.v)
        return

    if not args.f and not args.c:
        ap.print_help()
        sys.exit(1)

    programs: list[DcProgram] = []
    launch: Optional[Launch] = None

    if args.f:
        with open(args.f) as fh:
            text = fh.read()
        try:
            programs, launch = parse_asm(text)
        except ValueError as e:
            sys.exit(f"Parse error: {e}")
        for prog in programs:
            print(f"dc{prog.channel}: {len(prog.insns)} insn(s), repeat={prog.repeat}")
        print(f"estimated program time: {estimate_ns(programs)} ns")

    if args.o:
        write_bin_file(programs, launch, args.o)
        print(f"register dump → {args.o}")

    if args.u:
        write_uart_seq(programs, launch, args.u)
        print(f"UART sequence → {args.u}")

    if args.m:
        write_mem_files(programs, args.m)
        print(f"mem files → {args.m}/")

    if args.x:
        send_via_serial(programs, launch, args.x, args.baud, clear=args.c, verbose=args.v)

    if args.s:
        send_via_sim(programs, launch, sock_path=args.s, clear=args.c, verbose=args.v)


if __name__ == '__main__':
    main()
