#!/usr/bin/env python3
"""
gen_falstad_pal_full.py
Generates a complete PAL video tester Falstad circuit file.

Sections:
  A  4-bit R-2R DAC  (x=48-640, y=100-420)
  B  Signal level reference: SYNC / BLANK / GREY / WHITE  (x=750-1050, y=100-420)
  C  H-sync timing: clock + RC filter to show 4.7 us pulse  (x=48-640, y=500-750)

Usage:
  python3 tools/gen_falstad_pal_full.py > tools/falstad_pal_full.txt
"""

out = []

# -----------------------------------------------------------------------
# Primitive helpers  (all coordinates in Falstad canvas pixels)
# -----------------------------------------------------------------------
def res(x1,y1,x2,y2,v):    out.append(f"r {x1} {y1} {x2} {y2} 0 {v}")
def gnd(x,y):               out.append(f"g {x} {y} {x} {y+32} 0")
def wire(x1,y1,x2,y2):     out.append(f"w {x1} {y1} {x2} {y2} 0")
def cap(x1,y1,x2,y2,v):    out.append(f"c {x1} {y1} {x2} {y2} 0 {v} 0")

def vdc(x,y,v):
    """DC voltage source. Terminal at (x,y), body extends 32 px UP."""
    out.append(f"R {x} {y} {x} {y-32} 0 0 {v} 0 0 0.5")

def vsq(x,y,freq,v=5.0):
    """Square-wave source. Terminal at (x,y), body extends 32 px UP."""
    out.append(f"R {x} {y} {x} {y-32} 0 2 {freq} {v} 0 0 0.5")

def sw(x,ya,yb,state=0):
    """Switch from (x,ya) to (x,yb).  state 0=open, 1=closed."""
    out.append(f"s {x} {ya} {x} {yb} 0 {state} false")

def probe(x1,y1,x2,y2):
    """Oscilloscope / voltmeter probe (type=1)."""
    out.append(f"p {x1} {y1} {x2} {y2} 1 0")

# -----------------------------------------------------------------------
# SECTION A  -  4-bit R-2R DAC
# Identical to falstad_pal_dac.txt but with 75-ohm load on a separate node
# Bus: y=288   Bit nodes: x = 96 (D3/MSB) 208 (D2) 320 (D1) 432 (D0/LSB)
# -----------------------------------------------------------------------

BUS_Y   = 288
SW_BOT  = 208
VSRC_Y  = 128
BX      = [96, 208, 320, 432]       # D3 D2 D1 D0

# Termination 2R-to-GND at left end
res(48, BUS_Y, 48, BUS_Y+80, 2000)
gnd(48, BUS_Y+80)
wire(48, BUS_Y, BX[0], BUS_Y)

# Horizontal R = 1 kΩ between adjacent bit nodes
for i in range(3):
    res(BX[i], BUS_Y, BX[i+1], BUS_Y, 1000)

# Each bit: 5 V DC source -> switch -> 2R -> bus
for bx in BX:
    vdc(bx, VSRC_Y, 5)
    sw(bx, VSRC_Y, SW_BOT)
    res(bx, SW_BOT, bx, BUS_Y, 2000)

# Output node to the right of D0 (x=560)
OUT_X = 560
wire(BX[-1], BUS_Y, OUT_X, BUS_Y)
res(OUT_X, BUS_Y, OUT_X, BUS_Y+80, 75)   # 75-ohm cable load
gnd(OUT_X, BUS_Y+80)
probe(OUT_X, BUS_Y, OUT_X+96, BUS_Y)      # oscilloscope probe

# -----------------------------------------------------------------------
# SECTION B  -  Fixed signal level reference
# Shows exact output voltages for 4 key DAC codes (with 75-ohm load)
# Thevenin analysis for ideal R-2R:
#   code k (0..15) -> Vout = 5 * k/16  (into 75 ohm, load divider included)
# x=800, y stepping by 80 per level
# -----------------------------------------------------------------------

REF_X = 800

LEVELS = [
    ("SYNC  0000  0.00V", 0.000),
    ("BLANK 0100  1.25V", 5 * 4/16),
    ("GREY  0111  2.19V", 5 * 7/16),
    ("WHITE 1111  4.69V", 5 * 15/16),
]

for i, (name, v) in enumerate(LEVELS):
    y = 160 + i * 80
    vdc(REF_X, y, round(v, 3))
    res(REF_X, y, REF_X, y+48, 75)
    gnd(REF_X, y+48)
    probe(REF_X, y, REF_X+96, y)

# -----------------------------------------------------------------------
# SECTION C  -  H-sync timing demonstration
# Clock: 10 kHz square wave  (scaled 1000x from 10 MHz; 1 count = 0.1 ms)
# H_SYNC_W = 47 counts -> sync pulse width = 4.7 ms at this scale
# RC filter: R=1 kΩ, C=0.1 uF -> tau = 100 us (short vs 4.7 ms -> clean edge)
# -----------------------------------------------------------------------

CLK_X = 96
CLK_Y = 580

vsq(CLK_X, CLK_Y, 10000, 5)          # 10 kHz square wave, 5 V

# Probe directly on clock (raw square wave)
probe(CLK_X, CLK_Y, CLK_X, CLK_Y-96)

# RC low-pass filter to show analog rise/fall edge behaviour
wire(CLK_X, CLK_Y, CLK_X+80, CLK_Y)
res(CLK_X+80, CLK_Y, CLK_X+160, CLK_Y, 1000)
cap(CLK_X+160, CLK_Y, CLK_X+160, CLK_Y+64, 0.0000001)   # 100 nF
gnd(CLK_X+160, CLK_Y+64)
probe(CLK_X+160, CLK_Y, CLK_X+256, CLK_Y)                # filtered output

# 75-ohm load at filter output (simulates cable termination)
res(CLK_X+256, CLK_Y, CLK_X+256, CLK_Y+64, 75)
gnd(CLK_X+256, CLK_Y+64)

# -----------------------------------------------------------------------
# Emit complete circuit file
# -----------------------------------------------------------------------
print("$ 1 0.000005 10.20220290220148 50 5 43 50")
for line in out:
    print(line)
