#!/usr/bin/env python3
"""
gen_pal_circuit.py
Real chip-level circuit diagram of old Soviet PAL video tester.
Every pin connected, proper DIP symbols, power rails, signal buses.
Output: docs/pal_circuit_diagram.pdf + .png
"""

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np

# A2 landscape (23.4 × 16.5 inches)
fig, ax = plt.subplots(figsize=(23.4, 16.5))
ax.set_xlim(0, 23.4)
ax.set_ylim(0, 16.5)
ax.axis('off')
fig.patch.set_facecolor('white')
ax.set_facecolor('white')

# ── colours ────────────────────────────────────────────────────────
CB = '#1a1a1a'    # body border
CF = '#EEF4FB'    # chip fill
CW = '#000000'    # wire
CS = '#B03A2E'    # signal label
CP = '#1A5276'    # pin text inside chip
CV = '#C0392B'    # VCC wire/label
CG = '#2E4053'    # GND wire/label
CBU = '#2471A3'   # bus line

# ── drawing primitives ────────────────────────────────────────────
def hrule(x1, y, x2, color=CW, lw=0.7, ls='-'):
    ax.plot([x1, x2], [y, y], color=color, lw=lw, ls=ls, zorder=2)

def vrule(x, y1, y2, color=CW, lw=0.7, ls='-'):
    ax.plot([x, x], [y1, y2], color=color, lw=lw, ls=ls, zorder=2)

def route(pts, color=CW, lw=0.7):
    """Draw polyline through list of (x,y) points."""
    xs = [p[0] for p in pts]
    ys = [p[1] for p in pts]
    ax.plot(xs, ys, color=color, lw=lw, zorder=2)

def dot(x, y, r=0.04):
    ax.add_patch(mpatches.Circle((x, y), r, color=CW, zorder=4))

def text(x, y, s, size=6, ha='center', va='center', color=CB, bold=False, rotation=0):
    w = 'bold' if bold else 'normal'
    ax.text(x, y, s, ha=ha, va=va, fontsize=size, color=color,
            fontweight=w, rotation=rotation, zorder=5)

def pwr_vcc(x, y, label='+5V'):
    """VCC power symbol (upward arrow + label)."""
    ax.annotate('', xy=(x, y+0.35), xytext=(x, y),
                arrowprops=dict(arrowstyle='->', color=CV, lw=1.2))
    text(x, y+0.45, label, size=6.5, color=CV, bold=True)

def pwr_gnd(x, y):
    """GND symbol (three horizontal bars decreasing)."""
    for i, w in enumerate([0.20, 0.14, 0.08]):
        yy = y - i*0.09
        hrule(x-w, yy, x+w, color=CG, lw=1.0)
    vrule(x, y, y+0.15, color=CG, lw=0.8)

def bus_line(x1, y, x2, label='', lw=2.5, color=CBU):
    ax.plot([x1, x2], [y, y], color=color, lw=lw, zorder=2)
    if label:
        text((x1+x2)/2, y+0.13, label, size=6.5, color=color, bold=True)

def vbus_line(x, y1, y2, label='', lw=2.5, color=CBU):
    ax.plot([x, x], [y1, y2], color=color, lw=lw, zorder=2)
    if label:
        text(x+0.15, (y1+y2)/2, label, size=6.5, color=color, bold=True,
             rotation=90, ha='left', va='center')

def res_sym(x, y, horiz=True, val=''):
    """Resistor symbol (zigzag)."""
    if horiz:
        zx = [x, x+0.1, x+0.15, x+0.25, x+0.30, x+0.40, x+0.45, x+0.55, x+0.6]
        zy = [y,   y,  y+0.08, y-0.08, y+0.08, y-0.08, y+0.08,   y,    y]
        ax.plot(zx, zy, color=CW, lw=0.8, zorder=3)
        if val: text(x+0.3, y+0.18, val, size=5.5)
    else:
        zy = [y, y-0.1, y-0.15, y-0.25, y-0.30, y-0.40, y-0.45, y-0.55, y-0.6]
        zx = [x,   x, x+0.08,  x-0.08, x+0.08, x-0.08, x+0.08,   x,    x]
        ax.plot(zx, zy, color=CW, lw=0.8, zorder=3)
        if val: text(x+0.18, y-0.3, val, size=5.5, ha='left')

def cap_sym(x, y):
    """Capacitor symbol (two horizontal lines)."""
    hrule(x-0.10, y, x+0.10, color=CW, lw=1.2)
    hrule(x-0.10, y-0.08, x+0.10, color=CW, lw=1.2)
    vrule(x, y, y+0.15, color=CW, lw=0.7)
    vrule(x, y-0.08, y-0.25, color=CW, lw=0.7)

# ── DIP chip drawing ──────────────────────────────────────────────
def dip(x, y, ref, val, lpins, rpins, w=1.5, pitch=0.33, color=CF):
    """
    Draw a DIP IC.
    x, y    : top-left of body
    lpins   : [(pinnum, name), ...] left side, top→bottom
    rpins   : [(pinnum, name), ...] right side, top→bottom
    Returns : dict  (pinnum → (px, py)) for wire routing
    """
    n = max(len(lpins), len(rpins))
    h = n * pitch
    stub = 0.22     # pin stub length
    nw = 0.07       # pin number text offset from stub end

    # Body
    rect = mpatches.FancyBboxPatch((x, y-h), w, h, linewidth=1.0,
                                    edgecolor=CB, facecolor=color,
                                    boxstyle='round,pad=0.02', zorder=3)
    ax.add_patch(rect)
    # Notch
    ax.add_patch(mpatches.Arc((x+w/2, y), 0.15, 0.10,
                              theta1=180, theta2=360,
                              color=CB, lw=0.8, zorder=4))
    # Ref + value
    text(x+w/2, y-h/2+0.10, ref,   size=5.5, color=CB, bold=True)
    text(x+w/2, y-h/2-0.08, val,   size=5.0, color='#555555')

    pos = {}

    for i, (pn, pname) in enumerate(lpins):
        py = y - pitch*(i+0.5)
        px = x - stub
        hrule(px, py, x, color=CB, lw=0.7)
        text(px-nw, py, str(pn), size=4.5, ha='right', color='#333333')
        text(x+0.07, py, pname, size=4.5, ha='left', color=CP)
        pos[pn] = (px, py)

    for i, (pn, pname) in enumerate(rpins):
        py = y - pitch*(i+0.5)
        px = x + w + stub
        hrule(x+w, py, px, color=CB, lw=0.7)
        text(px+nw, py, str(pn), size=4.5, ha='left', color='#333333')
        text(x+w-0.07, py, pname, size=4.5, ha='right', color=CP)
        pos[pn] = (px, py)

    return pos

# ════════════════════════════════════════════════════════════════════
# TITLE
# ════════════════════════════════════════════════════════════════════
text(11.7, 16.1, 'PAL VIDEO TESTER — COMPLETE CIRCUIT DIAGRAM',
     size=14, bold=True, color='#1A2952')
text(11.7, 15.75,
     'H_TOTAL=640  V_TOTAL=625  CLK=10 MHz  H_ACT_S=120  R=1kΩ  2R=2kΩ',
     size=8.5, color='#555555')
hrule(0.2, 15.55, 23.2, color='#1A2952', lw=1.5)

# ════════════════════════════════════════════════════════════════════
# SECTION 1 — Power supply (7805)  [top-left]
# ════════════════════════════════════════════════════════════════════
p_7805 = dip(0.3, 15.3, 'IC20', '7805',
             [(1,'IN'), (2,'GND')],
             [(3,'+5V')],
             w=1.2, pitch=0.38, color='#FDEBD0')
# +12V in
text(p_7805[1][0]-0.15, p_7805[1][1], '+12V', size=5.5, ha='right', color=CV, bold=True)
# GND
pwr_gnd(p_7805[2][0]-0.12, p_7805[2][1])
# +5V out → vertical rail
vrule(p_7805[3][0]+0.1, p_7805[3][1], 0.4, color=CV, lw=1.2)
text(p_7805[3][0]+0.25, 0.5, '+5V RAIL', size=6, color=CV, bold=True, ha='left')

# ════════════════════════════════════════════════════════════════════
# SECTION 2 — Crystal oscillator + 74LS04 buffer  [top-left]
# ════════════════════════════════════════════════════════════════════
# Crystal symbol
CX, CY = 0.5, 13.8
vrule(CX, CY,   CY-0.25, color=CW, lw=0.7)
vrule(CX, CY-0.55, CY-0.80, color=CW, lw=0.7)
rect_xtal = mpatches.Rectangle((CX-0.12, CY-0.55), 0.24, 0.30,
                                 linewidth=0.9, edgecolor=CB, facecolor='#FFFDE7', zorder=3)
ax.add_patch(rect_xtal)
text(CX, CY-0.40, 'XTAL\n10MHz', size=5.5, color=CB)
pwr_gnd(CX, CY-0.80)

# 74LS04 buffer IC (hex inverter used as oscillator driver)
p_04 = dip(1.0, 14.2, 'IC1', '74LS04',
           [(7,'GND'), (1,'A1'), (3,'A2')],
           [(14,'VCC'), (2,'Y1'), (4,'Y2')],
           w=1.2, pitch=0.33, color='#D5F5E3')
pwr_vcc(p_04[14][0]+0.1, p_04[14][1])
pwr_gnd(p_04[7][0]-0.12, p_04[7][1])
# Crystal to buffer
route([(CX, CY), (CX, p_04[1][1]), (p_04[1][0], p_04[1][1])])
# Y1 feedback to A2 (oscillator feedback)
route([(p_04[2][0], p_04[2][1]),
       (p_04[2][0]+0.12, p_04[2][1]),
       (p_04[2][0]+0.12, p_04[3][1]),
       (p_04[3][0], p_04[3][1])], color=CW, lw=0.5)
# CLK output from Y2
CLK_Y_LINE = p_04[4][1]
hrule(p_04[4][0], CLK_Y_LINE, p_04[4][0]+0.5, color=CW)
text(p_04[4][0]+0.55, CLK_Y_LINE+0.07, 'CLK 10MHz', size=6, color=CS, bold=True, ha='left')
# Decoupling cap on VCC
cap_sym(p_04[14][0]+0.1, p_04[7][1]+0.35)
text(p_04[14][0]+0.28, p_04[7][1]+0.28, '100n', size=5)
pwr_gnd(p_04[14][0]+0.1, p_04[7][1]+0.1)

# ════════════════════════════════════════════════════════════════════
# SECTION 3 — H Counter  (74LS163 × 3)
# IC2: H bits 0-3,  IC3: H bits 4-7,  IC4: H bits 8-9
# Synchronous cascade: all share CLK, carry via ENT/ENP
# ════════════════════════════════════════════════════════════════════
HC_X = 2.8
HC_Y = 15.3
HP = 0.30   # pin pitch

ic2 = dip(HC_X, HC_Y, 'IC2', '74LS163',
          [(1,'/CLR'),(2,'CLK'),(3,'A'),(4,'B'),(5,'C'),(6,'D'),
           (7,'ENP'),(8,'GND')],
          [(16,'VCC'),(15,'RCO'),(14,'QA'),(13,'QB'),(12,'QC'),(11,'QD'),
           (10,'ENT'),(9,'/LD')],
          w=1.4, pitch=HP, color=CF)

ic3 = dip(HC_X+2.2, HC_Y, 'IC3', '74LS163',
          [(1,'/CLR'),(2,'CLK'),(3,'A'),(4,'B'),(5,'C'),(6,'D'),
           (7,'ENP'),(8,'GND')],
          [(16,'VCC'),(15,'RCO'),(14,'QA'),(13,'QB'),(12,'QC'),(11,'QD'),
           (10,'ENT'),(9,'/LD')],
          w=1.4, pitch=HP, color=CF)

ic4 = dip(HC_X+4.4, HC_Y, 'IC4', '74LS163',
          [(1,'/CLR'),(2,'CLK'),(3,'A'),(4,'B'),(5,'C'),(6,'D'),
           (7,'ENP'),(8,'GND')],
          [(16,'VCC'),(15,'RCO'),(14,'QA'),(13,'QB'),(12,'QC'),(11,'QD'),
           (10,'ENT'),(9,'/LD')],
          w=1.4, pitch=HP, color=CF)

# Power
for ic in [ic2, ic3, ic4]:
    pwr_vcc(ic[16][0]+0.1, ic[16][1])
    pwr_gnd(ic[8][0]-0.1,  ic[8][1])
    # Data inputs tied LOW (load 0 on reset)
    for p in [3,4,5,6]:
        pwr_gnd(ic[p][0]-0.1, ic[p][1])
    # /LD tied HIGH (no parallel load except reset via /CLR)
    pwr_vcc(ic[9][0]+0.1, ic[9][1])

# CLK bus to all three H counter ICs (horizontal CLK line)
CLK_BUS_Y = ic2[2][1]
hrule(p_04[4][0]+0.5, CLK_BUS_Y, HC_X+8.0, color=CV if False else CW, lw=1.0)
# Branch to each CLK input
for ic in [ic2, ic3, ic4]:
    route([(p_04[4][0]+0.5, CLK_Y_LINE),
           (p_04[4][0]+0.5, ic[2][1]),
           (ic[2][0], ic[2][1])], lw=0.8)
dot(p_04[4][0]+0.5, CLK_Y_LINE)
dot(p_04[4][0]+0.5, ic3[2][1])
dot(p_04[4][0]+0.5, ic4[2][1])

# RCO cascade: IC2.RCO → IC3.ENP + IC3.ENT
RCO2_X, RCO2_Y = ic2[15]
route([(RCO2_X, RCO2_Y), (HC_X+2.05, RCO2_Y), (HC_X+2.05, ic3[7][1]),
       (ic3[7][0], ic3[7][1])])
dot(HC_X+2.05, RCO2_Y)
route([(HC_X+2.05, RCO2_Y), (HC_X+2.05, ic3[10][1]),
       (ic3[10][0], ic3[10][1])])
text(HC_X+2.1, RCO2_Y+0.07, 'H-RCO2', size=5, color=CS, ha='left')

# RCO cascade: IC3.RCO → IC4.ENP + IC4.ENT
RCO3_X, RCO3_Y = ic3[15]
route([(RCO3_X, RCO3_Y), (HC_X+4.25, RCO3_Y), (HC_X+4.25, ic4[7][1]),
       (ic4[7][0], ic4[7][1])])
dot(HC_X+4.25, RCO3_Y)
route([(HC_X+4.25, RCO3_Y), (HC_X+4.25, ic4[10][1]),
       (ic4[10][0], ic4[10][1])])

# IC2 ENP + ENT tied HIGH
pwr_vcc(ic2[7][0]-0.1, ic2[7][1])
pwr_vcc(ic2[10][0]+0.1, ic2[10][1])

# H Bus: outputs → vertical bus line then to comparators
# Collect all H output pins
H_OUTS = {
    0: ic2[14], 1: ic2[13], 2: ic2[12], 3: ic2[11],
    4: ic3[14], 5: ic3[13], 6: ic3[12], 7: ic3[11],
    8: ic4[14], 9: ic4[13],
}
HBUS_X = HC_X + 7.2
HBUS_Y_TOP = 15.0
HBUS_Y_BOT = 10.0
vbus_line(HBUS_X, HBUS_Y_BOT, HBUS_Y_TOP, 'H[9:0]')

for bit, (px, py) in H_OUTS.items():
    route([(px, py), (HBUS_X, py)], lw=0.5)
    text(HBUS_X+0.06, py, f'H{bit}', size=4.5, ha='left', color=CBU)

# CLR for H counter — NAND detects H=639 (0b1001111111)
# Use IC4.QB (bit9) AND IC3.QD(bit7)..IC2.QA(bit0) minus IC4.QA(bit8)
CLR_X = HC_X+7.9
# NAND gate symbol (simple box)
nand_box = mpatches.FancyBboxPatch((CLR_X, HC_Y-3.5), 0.85, 1.0,
                                    linewidth=0.8, edgecolor=CB,
                                    facecolor='#FDFEFE', boxstyle='round,pad=0.02', zorder=3)
ax.add_patch(nand_box)
text(CLR_X+0.42, HC_Y-3.0, 'NAND\n(74LS30)', size=5.5, bold=True)
text(CLR_X+0.42, HC_Y-3.35, 'detect H=639', size=4.5, color='#777')
text(CLR_X-0.12, HC_Y-3.0, 'H9,H7..H0\n(excl H8)', size=4.5, ha='right', color=CS)
# /CLR output
CLR_OUT_X = CLR_X + 0.85
route([(CLR_OUT_X, HC_Y-3.0), (CLR_OUT_X+0.4, HC_Y-3.0)])
CLR_BUS_X = CLR_OUT_X + 0.4
# Wire /CLR to all ICs
for ic in [ic2, ic3, ic4]:
    route([(ic[1][0], ic[1][1]), (HC_X-0.3, ic[1][1]),
           (HC_X-0.3, HC_Y-3.0), (CLR_BUS_X, HC_Y-3.0)], lw=0.5)
dot(HC_X-0.3, ic3[1][1])
dot(HC_X-0.3, ic4[1][1])
text(CLR_BUS_X+0.05, HC_Y-2.95, '/CLR', size=5, color=CS, ha='left')

# ════════════════════════════════════════════════════════════════════
# SECTION 4 — H Comparators  (74LS688 × 3)
# IC8: detects H=H_FRONT=16, IC9: H=63, IC10: H=120
# P inputs = hardwired to constant (target value)
# Q inputs = from H bus
# /P=Q output goes LOW when match
# ════════════════════════════════════════════════════════════════════
HCMP_X = 9.3
HCMP_Y = 15.3
CP2 = 0.26   # pin pitch for 20-pin DIP

# Helper: draw 74LS688 and wire /G to GND
def draw_688(x, y, ref, target_dec, target_name):
    target_bin = format(target_dec, '010b')
    l = [(1,'/G'),(2,'P0'),(3,'Q0'),(4,'P1'),(5,'Q1'),
         (6,'P2'),(7,'Q2'),(8,'P3'),(9,'Q3'),(10,'GND')]
    r = [(20,'VCC'),(19,'/P=Q'),(18,'Q7'),(17,'P7'),
         (16,'Q6'),(15,'P6'),(14,'Q5'),(13,'P5'),
         (12,'Q4'),(11,'P4')]
    pos = dip(x, y, ref, f'74LS688\n{target_name}={target_dec}', l, r,
              w=1.4, pitch=CP2, color='#EBF5FB')
    pwr_vcc(pos[20][0]+0.1, pos[20][1])
    pwr_gnd(pos[10][0]-0.1, pos[10][1])
    pwr_gnd(pos[1][0]-0.1, pos[1][1])   # /G tied LOW → always enabled
    # P inputs: tied to constant bits of target value
    p_pins = {2:0, 4:1, 6:2, 8:3, 11:4, 13:5, 15:6, 17:7}
    q_pins = {3:0, 5:1, 7:2, 9:3, 12:4, 14:5, 16:6, 18:7}
    for pp, bit in p_pins.items():
        bv = int(target_bin[9-bit])  # target_bin is MSB first
        if bv == 1:
            pwr_vcc(pos[pp][0]-0.1 if pp<10 else pos[pp][0]+0.1, pos[pp][1])
        else:
            pwr_gnd(pos[pp][0]-0.1 if pp<10 else pos[pp][0]+0.1, pos[pp][1])
    # Q inputs: connected to H bus
    for qp, bit in q_pins.items():
        bx, by = pos[qp]
        # short wire to bus tap
        tap_x = HBUS_X
        tap_y = H_OUTS[bit][1]
        route([(bx, by), (bx-0.12, by), (bx-0.12, tap_y), (tap_x, tap_y)], lw=0.4)
        dot(tap_x, tap_y)
    return pos

p_ic8  = draw_688(HCMP_X,     HCMP_Y, 'IC8',  16,  'H_FRONT')
p_ic9  = draw_688(HCMP_X+2.2, HCMP_Y, 'IC9',  63,  'H_SYNC_E')
p_ic10 = draw_688(HCMP_X+4.4, HCMP_Y, 'IC10', 120, 'H_ACT_S')

# /P=Q outputs → H timing signals
H_SYNC_ST_X = p_ic8[19][0]+0.05
route([(p_ic8[19][0],  p_ic8[19][1]),  (H_SYNC_ST_X+0.4, p_ic8[19][1])])
text(H_SYNC_ST_X+0.45, p_ic8[19][1]+0.07, '/H_SYNC_ST', size=5.5, color=CS, ha='left')

route([(p_ic9[19][0],  p_ic9[19][1]),  (p_ic9[19][0]+0.45, p_ic9[19][1])])
text(p_ic9[19][0]+0.5, p_ic9[19][1]+0.07, '/H_SYNC_EN', size=5.5, color=CS, ha='left')

route([(p_ic10[19][0], p_ic10[19][1]), (p_ic10[19][0]+0.45, p_ic10[19][1])])
text(p_ic10[19][0]+0.5, p_ic10[19][1]+0.07, '/H_ACT_ST', size=5.5, color=CS, ha='left')

# ════════════════════════════════════════════════════════════════════
# SECTION 5 — V Counter  (74LS163 × 3)
# Positioned below H counters
# ════════════════════════════════════════════════════════════════════
VC_X = HC_X
VC_Y = 9.2

ic5 = dip(VC_X, VC_Y, 'IC5', '74LS163',
          [(1,'/CLR'),(2,'CLK'),(3,'A'),(4,'B'),(5,'C'),(6,'D'),
           (7,'ENP'),(8,'GND')],
          [(16,'VCC'),(15,'RCO'),(14,'QA'),(13,'QB'),(12,'QC'),(11,'QD'),
           (10,'ENT'),(9,'/LD')],
          w=1.4, pitch=HP, color='#EAF0FB')

ic6 = dip(VC_X+2.2, VC_Y, 'IC6', '74LS163',
          [(1,'/CLR'),(2,'CLK'),(3,'A'),(4,'B'),(5,'C'),(6,'D'),
           (7,'ENP'),(8,'GND')],
          [(16,'VCC'),(15,'RCO'),(14,'QA'),(13,'QB'),(12,'QC'),(11,'QD'),
           (10,'ENT'),(9,'/LD')],
          w=1.4, pitch=HP, color='#EAF0FB')

ic7 = dip(VC_X+4.4, VC_Y, 'IC7', '74LS163',
          [(1,'/CLR'),(2,'CLK'),(3,'A'),(4,'B'),(5,'C'),(6,'D'),
           (7,'ENP'),(8,'GND')],
          [(16,'VCC'),(15,'RCO'),(14,'QA'),(13,'QB'),(12,'QC'),(11,'QD'),
           (10,'ENT'),(9,'/LD')],
          w=1.4, pitch=HP, color='#EAF0FB')

for ic in [ic5, ic6, ic7]:
    pwr_vcc(ic[16][0]+0.1, ic[16][1])
    pwr_gnd(ic[8][0]-0.1,  ic[8][1])
    for p in [3,4,5,6]:
        pwr_gnd(ic[p][0]-0.1, ic[p][1])
    pwr_vcc(ic[9][0]+0.1, ic[9][1])

# V counter CLK = IC4 RCO (end of each H line)
H_CARRY_X = ic4[15][0]
H_CARRY_Y = ic4[15][1]
route([(H_CARRY_X, H_CARRY_Y),
       (H_CARRY_X+0.3, H_CARRY_Y),
       (H_CARRY_X+0.3, ic5[2][1]),
       (ic5[2][0], ic5[2][1])], lw=0.9)
text(H_CARRY_X+0.35, (H_CARRY_Y+ic5[2][1])/2,
     'H-carry\n(line clock)', size=5, color=CS, ha='left')

# RCO cascade V
RCO5_X, RCO5_Y = ic5[15]
route([(RCO5_X, RCO5_Y), (VC_X+2.05, RCO5_Y),
       (VC_X+2.05, ic6[7][1]), (ic6[7][0], ic6[7][1])])
dot(VC_X+2.05, RCO5_Y)
route([(VC_X+2.05, RCO5_Y), (VC_X+2.05, ic6[10][1]),
       (ic6[10][0], ic6[10][1])])

RCO6_X, RCO6_Y = ic6[15]
route([(RCO6_X, RCO6_Y), (VC_X+4.25, RCO6_Y),
       (VC_X+4.25, ic7[7][1]), (ic7[7][0], ic7[7][1])])
dot(VC_X+4.25, RCO6_Y)
route([(VC_X+4.25, RCO6_Y), (VC_X+4.25, ic7[10][1]),
       (ic7[10][0], ic7[10][1])])

pwr_vcc(ic5[7][0]-0.1, ic5[7][1])
pwr_vcc(ic5[10][0]+0.1, ic5[10][1])

V_OUTS = {
    0: ic5[14], 1: ic5[13], 2: ic5[12], 3: ic5[11],
    4: ic6[14], 5: ic6[13], 6: ic6[12], 7: ic6[11],
    8: ic7[14], 9: ic7[13],
}
VBUS_X = VC_X + 7.2
VBUS_Y_TOP = 8.8
VBUS_Y_BOT = 4.0
vbus_line(VBUS_X, VBUS_Y_BOT, VBUS_Y_TOP, 'V[9:0]')

for bit, (px, py) in V_OUTS.items():
    route([(px, py), (VBUS_X, py)], lw=0.5)
    text(VBUS_X+0.06, py, f'V{bit}', size=4.5, ha='left', color=CBU)

# V counter /CLR detect V=624 = 0b1001110000
vrule(VC_X-0.3, ic5[1][1], ic7[1][1], color=CW, lw=0.5)
dot(VC_X-0.3, ic6[1][1])
dot(VC_X-0.3, ic7[1][1])
vclr_box = mpatches.FancyBboxPatch((VC_X+6.5, VC_Y-3.3), 0.85, 0.8,
                                    linewidth=0.8, edgecolor=CB,
                                    facecolor='#FDFEFE', boxstyle='round,pad=0.02', zorder=3)
ax.add_patch(vclr_box)
text(VC_X+6.92, VC_Y-2.9, 'NAND\ndetect V=624', size=5)
route([(VC_X-0.3, ic5[1][1]), (VC_X-0.5, ic5[1][1]),
       (VC_X-0.5, VC_Y-2.9), (VC_X+6.5, VC_Y-2.9)])
text(VC_X+6.5+0.9, VC_Y-2.95, '/CLR', size=5, color=CS, ha='left')

# ════════════════════════════════════════════════════════════════════
# SECTION 6 — V Comparators  (74LS688 × 4)
# IC11: V=22, IC12: V=309, IC13: V=335, IC13b: V=622
# ════════════════════════════════════════════════════════════════════
VCMP_X = 9.3
VCMP_Y = 8.5

def draw_688v(x, y, ref, target_dec, target_name):
    target_bin = format(target_dec, '010b')
    l = [(1,'/G'),(2,'P0'),(3,'Q0'),(4,'P1'),(5,'Q1'),
         (6,'P2'),(7,'Q2'),(8,'P3'),(9,'Q3'),(10,'GND')]
    r = [(20,'VCC'),(19,'/P=Q'),(18,'Q7'),(17,'P7'),
         (16,'Q6'),(15,'P6'),(14,'Q5'),(13,'P5'),
         (12,'Q4'),(11,'P4')]
    pos = dip(x, y, ref, f'74LS688\n{target_name}={target_dec}', l, r,
              w=1.4, pitch=CP2, color='#E8F8F5')
    pwr_vcc(pos[20][0]+0.1, pos[20][1])
    pwr_gnd(pos[10][0]-0.1, pos[10][1])
    pwr_gnd(pos[1][0]-0.1, pos[1][1])
    p_pins = {2:0, 4:1, 6:2, 8:3, 11:4, 13:5, 15:6, 17:7}
    q_pins = {3:0, 5:1, 7:2, 9:3, 12:4, 14:5, 16:6, 18:7}
    for pp, bit in p_pins.items():
        bv = int(target_bin[9-bit])
        if bv == 1:
            pwr_vcc(pos[pp][0]-0.1 if pp<10 else pos[pp][0]+0.1, pos[pp][1])
        else:
            pwr_gnd(pos[pp][0]-0.1 if pp<10 else pos[pp][0]+0.1, pos[pp][1])
    for qp, bit in q_pins.items():
        bx, by = pos[qp]
        tap_y = V_OUTS[bit][1]
        route([(bx, by), (bx-0.12, by), (bx-0.12, tap_y), (VBUS_X, tap_y)], lw=0.4)
        dot(VBUS_X, tap_y)
    return pos

p_ic11  = draw_688v(VCMP_X,     VCMP_Y, 'IC11', 22,  'V_SF1')
p_ic12  = draw_688v(VCMP_X+2.2, VCMP_Y, 'IC12', 309, 'V_EF1')
p_ic13  = draw_688v(VCMP_X+4.4, VCMP_Y, 'IC13', 335, 'V_SF2')
p_ic13b = draw_688v(VCMP_X+6.6, VCMP_Y, 'IC13b',622, 'V_EF2')

for ic, sig in [(p_ic11,'V_SF1'),(p_ic12,'V_EF1'),(p_ic13,'V_SF2'),(p_ic13b,'V_EF2')]:
    route([(ic[19][0], ic[19][1]), (ic[19][0]+0.45, ic[19][1])])
    text(ic[19][0]+0.5, ic[19][1]+0.07, f'/{sig}', size=5.5, color=CS, ha='left')

# ════════════════════════════════════════════════════════════════════
# SECTION 7 — H and V SR latches  (74LS74 dual D-FF)
# IC14: H-sync FF (FF1=H-sync, FF2=H-active)
# IC15: F1-active, F2-active
# ════════════════════════════════════════════════════════════════════
FF_X = 15.5
FF_Y_H = 15.0
FF_Y_V = 9.2

ic14 = dip(FF_X, FF_Y_H, 'IC14', '74LS74\nH-sync/H-act',
           [(1,'/CLR1'),(2,'D1'),(3,'CLK1'),(4,'/PRE1'),(5,'Q1'),(6,'/Q1'),(7,'GND')],
           [(14,'VCC'),(13,'/CLR2'),(12,'D2'),(11,'CLK2'),(10,'/PRE2'),(9,'Q2'),(8,'/Q2')],
           w=1.5, pitch=0.30, color='#FDEDEC')

ic15 = dip(FF_X, FF_Y_V, 'IC15', '74LS74\nF1/F2-active',
           [(1,'/CLR1'),(2,'D1'),(3,'CLK1'),(4,'/PRE1'),(5,'Q1'),(6,'/Q1'),(7,'GND')],
           [(14,'VCC'),(13,'/CLR2'),(12,'D2'),(11,'CLK2'),(10,'/PRE2'),(9,'Q2'),(8,'/Q2')],
           w=1.5, pitch=0.30, color='#FDEDEC')

for ic in [ic14, ic15]:
    pwr_vcc(ic[14][0]+0.1, ic[14][1])
    pwr_gnd(ic[7][0]-0.1,  ic[7][1])
    pwr_vcc(ic[2][0]-0.1,  ic[2][1])    # D1 tied HIGH
    pwr_vcc(ic[12][0]+0.1, ic[12][1])   # D2 tied HIGH

# H-sync FF: CLK1=/H_SYNC_ST, /CLR1=/H_SYNC_EN → Q1=HSYNC
route([(p_ic8[19][0]+0.4,  p_ic8[19][1]),
       (ic14[3][0]+0.2, p_ic8[19][1]),
       (ic14[3][0]+0.2, ic14[3][1]),
       (ic14[3][0], ic14[3][1])], lw=0.7)
route([(p_ic9[19][0]+0.4,  p_ic9[19][1]),
       (ic14[1][0]+0.1, p_ic9[19][1]),
       (ic14[1][0]+0.1, ic14[1][1]),
       (ic14[1][0], ic14[1][1])], lw=0.7)
pwr_vcc(ic14[4][0]-0.1, ic14[4][1])  # /PRE1 HIGH (unused)

# H-active FF: CLK2=/H_ACT_ST, /CLR2=CLK (resets at each H start)
route([(p_ic10[19][0]+0.4, p_ic10[19][1]),
       (ic14[11][0]+0.15, p_ic10[19][1]),
       (ic14[11][0]+0.15, ic14[11][1]),
       (ic14[11][0], ic14[11][1])], lw=0.7)
pwr_vcc(ic14[10][0]+0.1, ic14[10][1])  # /PRE2 HIGH

# Q outputs with labels
text(ic14[5][0]+0.5, ic14[5][1]+0.07, 'HSYNC', size=6, color=CS, bold=True, ha='left')
hrule(ic14[5][0], ic14[5][1], ic14[5][0]+0.45, color=CS)
text(ic14[9][0]+0.5, ic14[9][1]+0.07, 'H_ACT', size=6, color=CS, bold=True, ha='left')
hrule(ic14[9][0], ic14[9][1], ic14[9][0]+0.45, color=CS)

# V latches: V_SF1→CLK1, V_EF1→/CLR1, V_SF2→CLK2, V_EF2→/CLR2
for i, (src, pin, lbl) in enumerate([
    (p_ic11, 3,  '/V_SF1'),
    (p_ic12, 1,  '/V_EF1'),
    (p_ic13, 11, '/V_SF2'),
    (p_ic13b,13, '/V_EF2')
]):
    x2 = ic15[pin][0]
    route([(src[19][0]+0.45, src[19][1]),
           (x2+0.1+i*0.07, src[19][1]),
           (x2+0.1+i*0.07, ic15[pin][1]),
           (x2, ic15[pin][1])], lw=0.6)
pwr_vcc(ic15[4][0]-0.1, ic15[4][1])
pwr_vcc(ic15[10][0]+0.1, ic15[10][1])

text(ic15[5][0]+0.5, ic15[5][1]+0.07, 'F1_ACT', size=6, color=CS, bold=True, ha='left')
hrule(ic15[5][0], ic15[5][1], ic15[5][0]+0.45, color=CS)
text(ic15[9][0]+0.5, ic15[9][1]+0.07, 'F2_ACT', size=6, color=CS, bold=True, ha='left')
hrule(ic15[9][0], ic15[9][1], ic15[9][0]+0.45, color=CS)

# ════════════════════════════════════════════════════════════════════
# SECTION 8 — Combining logic  (74LS08 AND + 74LS32 OR)
# V_ACT = F1_ACT OR F2_ACT
# PIXEL  = H_ACT AND V_ACT
# ════════════════════════════════════════════════════════════════════
COMB_X = 17.6
COMB_Y_OR  = 10.2
COMB_Y_AND = 12.5

# OR gate
or_box = mpatches.FancyBboxPatch((COMB_X, COMB_Y_OR-0.5), 1.0, 0.8,
                                  linewidth=0.8, edgecolor=CB,
                                  facecolor='#FDFEFE', boxstyle='round,pad=0.02', zorder=3)
ax.add_patch(or_box)
text(COMB_X+0.5, COMB_Y_OR-0.1, 'OR\n74LS32', size=5.5, bold=True)
text(COMB_X-0.25, COMB_Y_OR+0.1, 'F1_ACT', size=5, ha='right', color=CS)
text(COMB_X-0.25, COMB_Y_OR-0.3, 'F2_ACT', size=5, ha='right', color=CS)
# Output
hrule(COMB_X+1.0, COMB_Y_OR-0.1, COMB_X+1.5)
text(COMB_X+1.55, COMB_Y_OR-0.03, 'V_ACT', size=6, color=CS, bold=True, ha='left')

# AND gate
and_box = mpatches.FancyBboxPatch((COMB_X, COMB_Y_AND-0.5), 1.0, 0.8,
                                   linewidth=0.8, edgecolor=CB,
                                   facecolor='#FDFEFE', boxstyle='round,pad=0.02', zorder=3)
ax.add_patch(and_box)
text(COMB_X+0.5, COMB_Y_AND-0.1, 'AND\n74LS08', size=5.5, bold=True)
text(COMB_X-0.25, COMB_Y_AND+0.1, 'H_ACT', size=5, ha='right', color=CS)
text(COMB_X-0.25, COMB_Y_AND-0.3, 'V_ACT', size=5, ha='right', color=CS)
hrule(COMB_X+1.0, COMB_Y_AND-0.1, COMB_X+1.5)
text(COMB_X+1.55, COMB_Y_AND-0.03, 'PIXEL', size=6, color=CS, bold=True, ha='left')

# ════════════════════════════════════════════════════════════════════
# SECTION 9 — Pattern EPROM 2732 + 74LS138 decoder + 74LS251 MUX
# ════════════════════════════════════════════════════════════════════
ROM_X = 17.5
ROM_Y = 15.5

rom = dip(ROM_X, ROM_Y, 'IC17', '2732 EPROM\n(4K×8)',
          [(21,'VPP'),(22,'A10'),(23,'A9'),(24,'A8'),(1,'A7'),(2,'A6'),
           (3,'A5'),(4,'A4'),(5,'A3'),(6,'A2'),(7,'A1'),(8,'A0'),(12,'GND')],
          [(18,'VCC'),(20,'/OE'),(19,'/CE'),(17,'O7'),(16,'O6'),
           (15,'O5'),(14,'O4'),(13,'O3'),(11,'O2'),(10,'O1'),(9,'O0')],
          w=1.5, pitch=0.25, color='#F9F0FF')
pwr_vcc(rom[18][0]+0.1, rom[18][1])
pwr_vcc(rom[21][0]-0.1, rom[21][1])  # VPP=+5V for read mode
pwr_gnd(rom[12][0]-0.1, rom[12][1])
pwr_gnd(rom[20][0]+0.1, rom[20][1])  # /OE = GND (always output enabled)
pwr_gnd(rom[19][0]+0.1, rom[19][1])  # /CE = GND (always chip enabled)
text(rom[1][0]-0.15, rom[1][1]-0.3,
     'A[10:0] from\nH[5:0]+V[4:0]\n(pattern address)',
     size=5, ha='right', color=CBU)

# 74LS138 decoder (pattern select)
sel_x = ROM_X + 2.3
sel = dip(sel_x, ROM_Y-1.0, 'IC18', '74LS138',
          [(1,'A'),(2,'B'),(3,'C'),(4,'/E1'),(5,'/E2'),(6,'E3'),(8,'GND')],
          [(16,'VCC'),(15,'Y0'),(14,'Y1'),(13,'Y2'),(12,'Y3'),
           (11,'Y4'),(10,'Y5'),(9,'Y6'),(7,'Y7')],
          w=1.4, pitch=0.28, color='#F9F0FF')
pwr_vcc(sel[16][0]+0.1, sel[16][1])
pwr_gnd(sel[8][0]-0.1, sel[8][1])
pwr_gnd(sel[4][0]-0.1, sel[4][1])   # /E1 tied LOW
pwr_gnd(sel[5][0]-0.1, sel[5][1])   # /E2 tied LOW
pwr_vcc(sel[6][0]-0.1, sel[6][1])   # E3 tied HIGH
text(sel[1][0]-0.15, sel[3][1],
     'SEL[2:0]\nrotary\nswitch', size=5, ha='right', color=CBU)

# 74LS251 8:1 MUX
mux_x = sel_x + 2.2
mux = dip(mux_x, ROM_Y-0.5, 'IC19', '74LS251\n8:1 MUX',
          [(1,'A'),(2,'B'),(3,'C'),(4,'/E'),(5,'D0'),(6,'D1'),(7,'D2'),(8,'GND')],
          [(16,'VCC'),(15,'W'),(14,'Y'),(13,'D3'),(12,'D4'),(11,'D5'),
           (10,'D6'),(9,'D7')],
          w=1.4, pitch=0.28, color='#F9F0FF')
pwr_vcc(mux[16][0]+0.1, mux[16][1])
pwr_gnd(mux[8][0]-0.1, mux[8][1])
pwr_gnd(mux[4][0]-0.1, mux[4][1])   # /E tied LOW

# EPROM data → MUX inputs
route([(rom[9][0], rom[9][1]), (mux[5][0]-0.1, rom[9][1]),
       (mux[5][0]-0.1, mux[5][1]), (mux[5][0], mux[5][1])], lw=0.5)

text(mux[15][0]+0.5, mux[15][1]+0.07, 'PIXEL_BIT', size=6, color=CS, bold=True, ha='left')
hrule(mux[15][0], mux[15][1], mux[15][0]+0.45, color=CS)

# ════════════════════════════════════════════════════════════════════
# SECTION 10 — R-2R DAC  (4-bit, R=1kΩ, 2R=2kΩ)
# DAC input: D3=MSB, D2, D1, D0=LSB
# Sources: HSYNC=0x0, BLANK=0x4, pattern from EPROM/MUX
# ════════════════════════════════════════════════════════════════════
DAC_X = 19.5
DAC_Y = 7.5
BUS_Y_DAC = DAC_Y - 1.2
NX = [DAC_X + 0.1 + 1.0*i for i in range(4)]  # node X positions D3,D2,D1,D0
SH = 1.4   # switch height

# DAC code mux box (logic that selects SYNC/BLANK/WHITE)
mux_box = mpatches.FancyBboxPatch((DAC_X-1.5, DAC_Y-2.5), 1.2, 2.2,
                                   linewidth=0.9, edgecolor=CB,
                                   facecolor='#FEF9E7', boxstyle='round,pad=0.03', zorder=3)
ax.add_patch(mux_box)
text(DAC_X-0.9, DAC_Y-1.2, 'DAC CODE\nSELECTOR', size=6, bold=True)
text(DAC_X-0.9, DAC_Y-1.8,
     'SYNC → 0x0\nBLANK→ 0x4\nWHITE → 0xF',
     size=5.2, color='#7D6608')
text(DAC_X-0.68, DAC_Y-0.4, '74LS32+74LS08\n74LS04', size=5, color='#777')

hrule(DAC_X-0.3, BUS_Y_DAC+0.6, DAC_X, color=CS, lw=0.7)
text(DAC_X-0.35, BUS_Y_DAC+0.68, 'D[3:0]', size=5.5, color=CS, ha='right', bold=True)

# Labels D3-D0
for i, lbl in enumerate(['D3(MSB)', 'D2', 'D1', 'D0(LSB)']):
    text(NX[i], DAC_Y+0.25, lbl, size=5, ha='center')

# 5V source + switch + 2R for each bit
for nx in NX:
    # 5V source
    pwr_vcc(nx, DAC_Y + SH + 0.2)
    # switch symbol
    vrule(nx, DAC_Y, DAC_Y + SH, color=CW, lw=0.7)
    ax.plot([nx-0.12, nx+0.12], [DAC_Y+SH*0.6, DAC_Y+SH*0.8],
            color=CW, lw=0.9, zorder=3)
    # 2R resistor
    res_sym(nx, BUS_Y_DAC+0.6, horiz=False, val='2kΩ')
    vrule(nx, BUS_Y_DAC+0.0, BUS_Y_DAC, color=CW, lw=0.7)

# Termination 2R to GND at left
res_sym(NX[0]-0.85, BUS_Y_DAC, horiz=False, val='2kΩ')
vrule(NX[0]-0.85, BUS_Y_DAC-0.6, BUS_Y_DAC-0.6, color=CW, lw=0.7)
pwr_gnd(NX[0]-0.85, BUS_Y_DAC-0.6)
hrule(NX[0]-0.85, BUS_Y_DAC, NX[0], color=CW, lw=0.9)

# Bus horizontal 1kΩ resistors between nodes
for i in range(3):
    res_sym(NX[i]+0.02, BUS_Y_DAC, horiz=True, val='1kΩ')
    hrule(NX[i]+0.62, BUS_Y_DAC, NX[i+1], color=CW, lw=0.9)

# Output: 75Ω to GND + BNC
OUT_DAC_X = NX[-1] + 0.85
hrule(NX[-1], BUS_Y_DAC, OUT_DAC_X, color=CW, lw=0.9)
res_sym(OUT_DAC_X, BUS_Y_DAC, horiz=False, val='75Ω')
pwr_gnd(OUT_DAC_X, BUS_Y_DAC-0.6)

# BNC connector symbol
BNC_X = OUT_DAC_X + 0.8
hrule(OUT_DAC_X, BUS_Y_DAC, BNC_X-0.12, color=CW, lw=1.2)
circle = mpatches.Circle((BNC_X, BUS_Y_DAC), 0.14,
                          color='#E67E22', linewidth=1.2,
                          fill=True, zorder=4)
ax.add_patch(circle)
text(BNC_X+0.25, BUS_Y_DAC+0.10, 'J1', size=6, bold=True, color='#E67E22', ha='left')
text(BNC_X+0.25, BUS_Y_DAC-0.10, 'VIDEO OUT\n75Ω BNC', size=5.5, color='#E67E22', ha='left')
text(BNC_X+0.25, BUS_Y_DAC-0.40, '0V=sync\n1.25V=blank\n4.69V=white', size=5, ha='left')

# ════════════════════════════════════════════════════════════════════
# DECOUPLING CAPS (100nF on +5V near each IC group)
# ════════════════════════════════════════════════════════════════════
for cx, cy, lbl in [
    (HC_X+1.5, HC_Y-2.8, 'C1\n100n'),
    (VC_X+1.5, VC_Y-2.8, 'C2\n100n'),
    (HCMP_X+2, HCMP_Y-3.5, 'C3\n100n'),
    (VCMP_X+2, VCMP_Y-3.5, 'C4\n100n'),
    (FF_X+0.5, FF_Y_H-2.5, 'C5\n100n'),
    (ROM_X+0.5, ROM_Y-4.5, 'C6\n100n'),
]:
    cap_sym(cx, cy)
    pwr_vcc(cx, cy+0.15+0.02)
    pwr_gnd(cx, cy-0.25-0.08)
    text(cx+0.18, cy-0.15, lbl, size=5, ha='left')

# ════════════════════════════════════════════════════════════════════
# ANNOTATION BOX  (bottom-right)
# ════════════════════════════════════════════════════════════════════
ann_text = (
    "H Timing (10 MHz clock, 0.1µs/clock):\n"
    "  H_TOTAL   = 640 clocks  = 64.0 µs / line\n"
    "  H_FRONT   =  16 clocks  =  1.6 µs  front porch\n"
    "  H_SYNC_W  =  47 clocks  =  4.7 µs  H-sync tip\n"
    "  H_BACK    =  57 clocks  =  5.7 µs  back porch\n"
    "  H_ACTIVE  = 520 clocks  = 52.0 µs  active video\n"
    "\n"
    "V Timing (625 lines / frame = 40 ms):\n"
    "  F1 active  : V=22..309   (288 lines)\n"
    "  F2 active  : V=335..622  (288 lines)\n"
    "  Field freq : 50 Hz,  Frame : 25 Hz\n"
    "\n"
    "DAC output levels (R=1kΩ, 2R=2kΩ, 75Ω load):\n"
    "  0x0=0000  → 0.00V  sync tip\n"
    "  0x4=0100  → 1.25V  blank pedestal\n"
    "  0x7=0111  → 2.19V  50% grey\n"
    "  0xF=1111  → 4.69V  white peak\n"
    "\n"
    "IC refs  (Soviet / К-series equivalent):\n"
    "  74LS163 → К555ИЕ7 (sync binary counter)\n"
    "  74LS688 → К555СП1 (8-bit comparator)\n"
    "  74LS74  → К555ТМ2 (dual D flip-flop)\n"
    "  74LS30  → К555ЛА2 (8-input NAND)\n"
    "  74LS08  → К555ЛИ1 (quad AND)\n"
    "  74LS32  → К555ЛЛ1 (quad OR)\n"
    "  2732    → К573РФ2 (4K×8 UV EPROM)\n"
    "  74LS138 → К555ИД7 (3-to-8 decoder)\n"
    "  74LS251 → К555КП7 (8-to-1 MUX)\n"
    "  7805    → КР142ЕН5 (+5V regulator)"
)
ax.text(19.5, 4.5, ann_text,
        ha='left', va='top', fontsize=5.8,
        color='#1a1a1a', family='monospace',
        bbox=dict(boxstyle='round,pad=0.4', facecolor='#FFFDE7',
                  edgecolor='#BDC3C7', linewidth=0.8), zorder=5)

# ════════════════════════════════════════════════════════════════════
# BORDER + FOOTER
# ════════════════════════════════════════════════════════════════════
for x_,y_,w_,h_ in [(0.1, 0.1, 23.2, 16.3)]:
    ax.add_patch(mpatches.Rectangle((x_,y_), w_, h_,
                 linewidth=1.5, edgecolor='#1A2952', fill=False, zorder=6))
hrule(0.1, 0.7, 23.3, color='#1A2952', lw=0.8)
text(0.4, 0.45, 'PAL Video IP Core  |  Old Soviet Tester Reference  |  Complete Circuit', size=7, ha='left', color='#555')
text(23.0, 0.45, 'Rev 1.0  •  2026-06-21', size=7, ha='right', color='#555')

# ════════════════════════════════════════════════════════════════════
# Save
# ════════════════════════════════════════════════════════════════════
plt.tight_layout(pad=0.2)
pdf_path = '/home/user/video-ip-core-/docs/pal_circuit_diagram.pdf'
png_path = '/home/user/video-ip-core-/docs/pal_circuit_diagram.png'
plt.savefig(pdf_path, dpi=200, bbox_inches='tight', facecolor='white')
plt.savefig(png_path, dpi=150, bbox_inches='tight', facecolor='white')
print(f"Saved: {pdf_path}")
print(f"Saved: {png_path}")
