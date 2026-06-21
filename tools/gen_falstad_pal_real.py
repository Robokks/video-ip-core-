#!/usr/bin/env python3
"""
gen_falstad_pal_real.py
Complete real PAL video tester Falstad circuit.

Matches old Soviet tester architecture:
  Crystal 10 MHz -> H counter (0-639) -> H timing decode
                                       -> V counter (0-624) -> V active decode
  H-sync + V-active + field -> DAC code select -> R-2R DAC -> video out

Falstad component formats:
  dc  counter   dc x1 y1 x2 y2 0 maxCount initState numBits
  A   AND gate  A  x1 y1 x2 y2 0 numIn 0 1
  O   OR  gate  O  x1 y1 x2 y2 0 numIn 0 1
  I   NOT gate  I  x1 y1 x2 y2 0
  N   NAND gate N  x1 y1 x2 y2 0 numIn 0 1
  df  D flip-flop df x1 y1 x2 y2 0 0
  r   resistor  r  x1 y1 x2 y2 0 value
  g   ground    g  x1 y1 x2 y2 0
  w   wire      w  x1 y1 x2 y2 0
  R   source    R  x1 y1 x2 y2 0 waveform freq/v v2 offset phase
  s   switch    s  x1 y1 x2 y2 0 state false
  p   probe     p  x1 y1 x2 y2 1 0
"""

lines = []

def emit(s): lines.append(s)

# ── primitives ────────────────────────────────────────────────────────
def wire(x1,y1,x2,y2):   emit(f"w {x1} {y1} {x2} {y2} 0")
def res(x1,y1,x2,y2,v):  emit(f"r {x1} {y1} {x2} {y2} 0 {v}")
def gnd(x,y):             emit(f"g {x} {y} {x} {y+32} 0")
def vsq(x,y,f,v=5):       emit(f"R {x} {y} {x} {y-32} 0 2 {f} {v} 0 0 0.5")
def vdc(x,y,v):           emit(f"R {x} {y} {x} {y-32} 0 0 {v} 0 0 0.5")
def sw(x,ya,yb,st=0):     emit(f"s {x} {ya} {x} {yb} 0 {st} false")
def probe(x1,y1,x2,y2):   emit(f"p {x1} {y1} {x2} {y2} 1 0")

def AND(x1,y1,x2,y2,n=2):  emit(f"A {x1} {y1} {x2} {y2} 0 {n} 0 1")
def OR(x1,y1,x2,y2,n=2):   emit(f"O {x1} {y1} {x2} {y2} 0 {n} 0 1")
def NOT(x1,y1,x2,y2):       emit(f"I {x1} {y1} {x2} {y2} 0")
def NAND(x1,y1,x2,y2,n=2): emit(f"N {x1} {y1} {x2} {y2} 0 {n} 0 1")
def XOR(x1,y1,x2,y2,n=2):  emit(f"X {x1} {y1} {x2} {y2} 0 {n} 0 1")

def counter(x1,y1,x2,y2,maxCount,bits):
    emit(f"dc {x1} {y1} {x2} {y2} 0 {maxCount} 0 {bits}")

def dff(x1,y1,x2,y2):
    emit(f"df {x1} {y1} {x2} {y2} 0 0")

# ── pin position helper for chip east/west side ───────────────────────
def east_pins(x2, y1, y2, n):
    """Y coords of n east-side pins evenly spaced in chip height."""
    h = y2 - y1
    return [y1 + h * (i+1) // (n+1) for i in range(n)]

def west_pins(x1, y1, y2, n):
    """Y coords of n west-side pins."""
    h = y2 - y1
    return [y1 + h * (i+1) // (n+1) for i in range(n)]

# ═══════════════════════════════════════════════════════════════════════
# PAL constants
# ═══════════════════════════════════════════════════════════════════════
H_TOTAL     = 640
H_FRONT     = 16
H_SYNC_END  = 63    # H_FRONT + H_SYNC_W - 1 = 16+47-1
H_ACT_S     = 120   # H_FRONT + H_SYNC_W + H_BACK

V_TOTAL     = 625
V_ACT_S_F1  = 22
V_ACT_E_F1  = 309
V_ACT_S_F2  = 335
V_ACT_E_F2  = 622

# ═══════════════════════════════════════════════════════════════════════
# BLOCK 1 — Master clock (10 kHz = 10 MHz / 1000)
# ═══════════════════════════════════════════════════════════════════════
CLK_X, CLK_Y = 64, 200
vsq(CLK_X, CLK_Y, 10000)
probe(CLK_X, CLK_Y, CLK_X+64, CLK_Y)   # raw clock probe

# ═══════════════════════════════════════════════════════════════════════
# BLOCK 2 — H counter  (74LS163 × 3 cascade, here as single 10-bit chip)
# Counts 0 to 639, resets at 640 via carry
# ═══════════════════════════════════════════════════════════════════════
HC_X1, HC_Y1 = 176,  80
HC_X2, HC_Y2 = 288, 560

counter(HC_X1, HC_Y1, HC_X2, HC_Y2, H_TOTAL, 10)

# West pins: CLK (index 0), RST (index 1)
hc_west = west_pins(HC_X1, HC_Y1, HC_Y2, 2)
CLK_IN_Y  = hc_west[0]
HC_RST_Y  = hc_west[1]

# Clock wire  (horizontal then meet chip)
wire(CLK_X, CLK_Y, HC_X1, CLK_IN_Y)

# East pins: Q0 (LSB, index 0) .. Q9 (MSB, index 9)
hq = east_pins(HC_X2, HC_Y1, HC_Y2, 10)   # hq[0]=Q0 .. hq[9]=Q9

# ═══════════════════════════════════════════════════════════════════════
# BLOCK 3 — H timing decode
# Detect three boundaries: H_FRONT, H_SYNC_END, H_ACT_S
# For each boundary value B:
#   - per bit: if B bit i == 1  → use Qi directly
#              if B bit i == 0  → use NOT Qi
#   - 10-input AND of all per-bit signals → "H == B"
#   - SR latch from "start" / "end" detects ranges
#
# Simplified: only wire bits that differ between boundaries.
# ═══════════════════════════════════════════════════════════════════════

DECODE_X = HC_X2 + 64   # x where decode logic starts

def h_eq_gate(target, row_y, q_x, q_ys, gate_w=80):
    """
    Emit 10-bit comparator for H counter == target.
    q_x   : x of counter east face
    q_ys  : list of 10 y-coords for Q0..Q9
    row_y : y of the 10-input AND gate output
    Returns (out_x, out_y) of AND gate output.
    """
    bits = [(target >> i) & 1 for i in range(10)]
    sig_xs = []
    sig_ys = []
    ox = DECODE_X
    for i, (b, qy) in enumerate(zip(bits, q_ys)):
        if b == 1:
            # Connect Q directly to a 32-pixel horizontal stub
            tx = ox
            wire(q_x, qy, tx, qy)
            sig_xs.append(tx); sig_ys.append(qy)
        else:
            # NOT gate: input at (ox, qy), output at (ox+48, qy)
            NOT(ox, qy, ox+48, qy)
            wire(q_x, qy, ox, qy)
            sig_xs.append(ox+48); sig_ys.append(qy)
        ox = max(ox, q_x + 32)

    # 10-input AND gate: span from top to bottom of signals
    and_x1 = DECODE_X + 64
    and_y1 = min(sig_ys) - 16
    and_y2 = max(sig_ys) + 16
    and_x2 = and_x1 + gate_w
    AND(and_x1, and_y1, and_x2, and_y2, n=10)

    # Wire each per-bit result to AND gate (horizontal wires at each y)
    for (sx, sy) in zip(sig_xs, sig_ys):
        wire(sx, sy, and_x1, sy)

    return (and_x2, (and_y1 + and_y2) // 2)

# Row positions for the three H comparators
ROW_FRONT   = HC_Y1 + 40
ROW_SYNCEND = HC_Y1 + 200
ROW_ACTS    = HC_Y1 + 360

h_front_out  = h_eq_gate(H_FRONT,   ROW_FRONT,   HC_X2, hq)
h_sende_out  = h_eq_gate(H_SYNC_END, ROW_SYNCEND, HC_X2, hq)
h_acts_out   = h_eq_gate(H_ACT_S,   ROW_ACTS,    HC_X2, hq)

# H_SYNC range: active from H_FRONT until H_SYNC_END
# Use SR-latch: SET on H==H_FRONT, RESET on H==H_SYNC_END
# Simplified: D flip-flop clocked on H=H_FRONT, cleared on H=H_SYNC_END
HSYNC_FF_X1 = h_front_out[0] + 80
HSYNC_FF_Y1 = (ROW_FRONT + ROW_SYNCEND) // 2 - 60
HSYNC_FF_X2 = HSYNC_FF_X1 + 80
HSYNC_FF_Y2 = HSYNC_FF_Y1 + 120
dff(HSYNC_FF_X1, HSYNC_FF_Y1, HSYNC_FF_X2, HSYNC_FF_Y2)
# D input tied high (Vcc)
vdc(HSYNC_FF_X1, HSYNC_FF_Y1 + 30, 5)
# CLK = H==H_FRONT signal
wire(h_front_out[0], h_front_out[1], HSYNC_FF_X1, HSYNC_FF_Y1 + 60)
# RST = H==H_SYNC_END signal
wire(h_sende_out[0], h_sende_out[1], HSYNC_FF_X1, HSYNC_FF_Y2 - 30)

HSYNC_Q_X  = HSYNC_FF_X2
HSYNC_Q_Y  = HSYNC_FF_Y1 + 30   # Q output (H-sync signal)

probe(HSYNC_Q_X, HSYNC_Q_Y, HSYNC_Q_X + 64, HSYNC_Q_Y)  # H-sync probe

# H_ACTIVE range: starts at H==H_ACT_S, D-FF cleared at H==0 (RST from carry)
HACT_FF_X1 = h_acts_out[0] + 80
HACT_FF_Y1 = ROW_ACTS - 60
HACT_FF_X2 = HACT_FF_X1 + 80
HACT_FF_Y2 = HACT_FF_Y1 + 120
dff(HACT_FF_X1, HACT_FF_Y1, HACT_FF_X2, HACT_FF_Y2)
vdc(HACT_FF_X1, HACT_FF_Y1 + 30, 5)
wire(h_acts_out[0], h_acts_out[1], HACT_FF_X1, HACT_FF_Y1 + 60)

HACT_Q_X = HACT_FF_X2
HACT_Q_Y = HACT_FF_Y1 + 30

# ═══════════════════════════════════════════════════════════════════════
# BLOCK 4 — V counter  (74LS163 × 3, here single 10-bit chip)
# Clocked by H counter carry (carry = H just wrapped, i.e., end of every line)
# ═══════════════════════════════════════════════════════════════════════
VC_X1, VC_Y1 = 176,  660
VC_X2, VC_Y2 = 288, 1140

counter(VC_X1, VC_Y1, VC_X2, VC_Y2, V_TOTAL, 10)

vc_west = west_pins(VC_X1, VC_Y1, VC_Y2, 2)
VC_CLK_Y = vc_west[0]
VC_RST_Y = vc_west[1]

# V counter clocked by H counter carry (RST output of H counter → V CLK)
# In Falstad counter: when it wraps (reaches maxCount), it generates a carry.
# Connect H-counter carry out to V-counter CLK.
# H counter carry is on east side beyond Q9, or we use the H RST wire.
# Simple approach: wire the H counter carry (approximate at bottom-east) to VC CLK
HC_CARRY_Y = HC_Y2 - 20  # approximate carry at bottom of H counter east side
wire(HC_X2, HC_CARRY_Y, VC_X1, VC_CLK_Y)

vq = east_pins(VC_X2, VC_Y1, VC_Y2, 10)   # vq[0]=Q0 .. vq[9]=Q9

# ═══════════════════════════════════════════════════════════════════════
# BLOCK 5 — V active decode (74LS688-style comparators)
# Detect: V==V_ACT_S_F1, V==V_ACT_E_F1, V==V_ACT_S_F2, V==V_ACT_E_F2
# SR latches produce: F1_ACTIVE (lines V_ACT_S_F1..V_ACT_E_F1)
#                     F2_ACTIVE (lines V_ACT_S_F2..V_ACT_E_F2)
# ═══════════════════════════════════════════════════════════════════════

VDEC_X = VC_X2 + 64

def v_eq_gate(target, row_y, gate_w=80):
    bits = [(target >> i) & 1 for i in range(10)]
    sig_xs, sig_ys = [], []
    for i, (b, qy) in enumerate(zip(bits, vq)):
        if b == 1:
            wire(VC_X2, qy, VDEC_X, qy)
            sig_xs.append(VDEC_X); sig_ys.append(qy)
        else:
            NOT(VDEC_X, qy, VDEC_X+48, qy)
            wire(VC_X2, qy, VDEC_X, qy)
            sig_xs.append(VDEC_X+48); sig_ys.append(qy)
    and_x1 = VDEC_X + 64
    and_y1 = min(sig_ys) - 16
    and_y2 = max(sig_ys) + 16
    AND(and_x1, and_y1, and_x1+gate_w, and_y2, n=10)
    for sx, sy in zip(sig_xs, sig_ys):
        wire(sx, sy, and_x1, sy)
    return (and_x1+gate_w, (and_y1+and_y2)//2)

V_ROW = [VC_Y1 + 40, VC_Y1+160, VC_Y1+280, VC_Y1+400]
v_sf1 = v_eq_gate(V_ACT_S_F1, V_ROW[0])
v_ef1 = v_eq_gate(V_ACT_E_F1, V_ROW[1])
v_sf2 = v_eq_gate(V_ACT_S_F2, V_ROW[2])
v_ef2 = v_eq_gate(V_ACT_E_F2, V_ROW[3])

# SR latches for F1_ACTIVE and F2_ACTIVE
FF_W = 80
F1_FF_X1 = v_sf1[0] + 80
F1_FF_Y1 = (V_ROW[0]+V_ROW[1])//2 - 60
dff(F1_FF_X1, F1_FF_Y1, F1_FF_X1+FF_W, F1_FF_Y1+120)
vdc(F1_FF_X1, F1_FF_Y1+30, 5)
wire(v_sf1[0], v_sf1[1], F1_FF_X1, F1_FF_Y1+60)
wire(v_ef1[0], v_ef1[1], F1_FF_X1, F1_FF_Y1+90)
F1_Q_X = F1_FF_X1 + FF_W
F1_Q_Y = F1_FF_Y1 + 30

F2_FF_X1 = v_sf2[0] + 80
F2_FF_Y1 = (V_ROW[2]+V_ROW[3])//2 - 60
dff(F2_FF_X1, F2_FF_Y1, F2_FF_X1+FF_W, F2_FF_Y1+120)
vdc(F2_FF_X1, F2_FF_Y1+30, 5)
wire(v_sf2[0], v_sf2[1], F2_FF_X1, F2_FF_Y1+60)
wire(v_ef2[0], v_ef2[1], F2_FF_X1, F2_FF_Y1+90)
F2_Q_X = F2_FF_X1 + FF_W
F2_Q_Y = F2_FF_Y1 + 30

# ═══════════════════════════════════════════════════════════════════════
# BLOCK 6 — Output combining logic
# active = H_ACT AND (F1_ACTIVE OR F2_ACTIVE)
# video_state: sync=0, blank=1, active=2
# dac code: sync=0x0, blank=0x4, white=0xF (switches select pattern)
# ═══════════════════════════════════════════════════════════════════════

COMB_X = max(F1_Q_X, F2_Q_X) + 80
COMB_Y  = (F1_Q_Y + F2_Q_Y) // 2

# OR gate: F1_ACTIVE OR F2_ACTIVE → V_ACTIVE
OR(COMB_X, F1_Q_Y-20, COMB_X+64, F2_Q_Y+20, n=2)
wire(F1_Q_X, F1_Q_Y, COMB_X, F1_Q_Y)
wire(F2_Q_X, F2_Q_Y, COMB_X, F2_Q_Y)
VACT_X = COMB_X + 64
VACT_Y = (F1_Q_Y + F2_Q_Y) // 2

# AND gate: H_ACTIVE AND V_ACTIVE → PIXEL_ACTIVE
AND(VACT_X+48, VACT_Y-20, VACT_X+112, VACT_Y+20, n=2)
wire(HACT_Q_X, HACT_Q_Y, VACT_X+48, HACT_Q_Y)
wire(VACT_X, VACT_Y, VACT_X+48, VACT_Y)
PIX_X = VACT_X + 112
PIX_Y = VACT_Y
probe(PIX_X, PIX_Y, PIX_X+64, PIX_Y)   # PIXEL_ACTIVE probe

# ═══════════════════════════════════════════════════════════════════════
# BLOCK 7 — DAC code multiplexer
# Switches select which DAC code feeds the R-2R ladder:
#   SYNC    → 0b0000 (0x0 = 0V)
#   BLANK   → 0b0100 (0x4 = 1.25V)
#   WHITE   → 0b1111 (0xF = ~4.7V)
# Manual switches simulate pattern EPROM + selector logic
# ═══════════════════════════════════════════════════════════════════════

DAC_X0 = PIX_X + 128
DAC_BUS_Y = 1300

# 4-bit R-2R DAC (same layout as previous circuits, moved right)
DAC_BX = [DAC_X0 + 96*i for i in range(4)]   # D3 D2 D1 D0
DAC_BUS_Y2 = DAC_BUS_Y

# Termination 2R
res(DAC_X0-48, DAC_BUS_Y2, DAC_X0-48, DAC_BUS_Y2+80, 2000)
gnd(DAC_X0-48, DAC_BUS_Y2+80)
wire(DAC_X0-48, DAC_BUS_Y2, DAC_BX[0], DAC_BUS_Y2)

# Series R between bits
for i in range(3):
    res(DAC_BX[i], DAC_BUS_Y2, DAC_BX[i+1], DAC_BUS_Y2, 1000)

# Each bit: 5V source + switch + 2R
for bx in DAC_BX:
    vdc(bx, DAC_BUS_Y2-160, 5)
    sw(bx, DAC_BUS_Y2-160, DAC_BUS_Y2-80)
    res(bx, DAC_BUS_Y2-80, bx, DAC_BUS_Y2, 2000)

# Output: 75 Ω load + scope probe
OUT_X = DAC_BX[-1] + 112
wire(DAC_BX[-1], DAC_BUS_Y2, OUT_X, DAC_BUS_Y2)
res(OUT_X, DAC_BUS_Y2, OUT_X, DAC_BUS_Y2+80, 75)
gnd(OUT_X, DAC_BUS_Y2+80)
probe(OUT_X, DAC_BUS_Y2, OUT_X+96, DAC_BUS_Y2)

# ═══════════════════════════════════════════════════════════════════════
# Emit Falstad file
# ═══════════════════════════════════════════════════════════════════════
print("$ 1 0.000001 5 50 5 43 50")
for line in lines:
    print(line)
