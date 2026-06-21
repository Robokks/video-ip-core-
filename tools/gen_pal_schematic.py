#!/usr/bin/env python3
"""
gen_pal_schematic.py
Generates a complete chip-level schematic of the old Soviet PAL video tester.

Chips shown:
  IC1         Crystal 10 MHz + 74LS04 clock buffer
  IC2-IC4     74LS163 x3  H counter  (bits H0-H9, counts 0-639)
  IC5-IC7     74LS163 x3  V counter  (bits V0-V9, counts 0-624)
  IC8-IC10    74LS688 x3  H comparators (H_FRONT=16, H_SYNC_END=63, H_ACT_S=120)
  IC11-IC13   74LS688 x3  V comparators (22, 309, 335, 622)
  IC14-IC16   74LS74  x3  SR latches for H-sync, H-active, field detect
  IC17        2732 EPROM  Pattern data (4K x 8)
  IC18        74LS138     3-to-8 decoder (pattern select)
  IC19        74LS251     8-to-1 MUX (pixel data)
  IC20        7805        5V regulator
  DAC         R-2R ladder 4-bit (R=1kΩ, 2R=2kΩ) + 75Ω cable load

Output: docs/pal_old_tester_schematic.pdf
"""

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch
import matplotlib.lines as mlines

fig, ax = plt.subplots(figsize=(24, 16))
ax.set_xlim(0, 24)
ax.set_ylim(0, 16)
ax.axis('off')
ax.set_facecolor('#FAFAFA')
fig.patch.set_facecolor('#FAFAFA')

# ── colour palette ───────────────────────────────────────────────────
C_CHIP    = '#D6EAF8'   # chip body
C_BORDER  = '#1A5276'   # chip border
C_CLK     = '#D5F5E3'   # clock/supply chips
C_DAC     = '#FAD7A0'   # DAC section
C_WIRE    = '#1A1A1A'   # signal wire
C_LABEL   = '#1A1A1A'
C_SIG     = '#922B21'   # signal name on wire

# ── helpers ──────────────────────────────────────────────────────────
def chip(ax, x, y, w, h, name, number, color=C_CHIP,
         left_pins=None, right_pins=None, fontsize=7.5):
    """Draw a chip box with pin labels on left and right."""
    box = FancyBboxPatch((x, y), w, h,
                         boxstyle="round,pad=0.05",
                         linewidth=1.2, edgecolor=C_BORDER, facecolor=color, zorder=3)
    ax.add_patch(box)
    # Chip name
    ax.text(x+w/2, y+h/2+0.1, name,
            ha='center', va='center', fontsize=fontsize, fontweight='bold',
            color=C_BORDER, zorder=4)
    ax.text(x+w/2, y+h/2-0.22, number,
            ha='center', va='center', fontsize=fontsize-1.5,
            color='#555555', zorder=4)

    pin_count_l = len(left_pins)  if left_pins  else 0
    pin_count_r = len(right_pins) if right_pins else 0
    pin_len = 0.25

    lcoords = {}
    if left_pins:
        for i, pname in enumerate(left_pins):
            py = y + h - h*(i+1)/(pin_count_l+1)
            ax.plot([x-pin_len, x], [py, py], '-', color=C_BORDER, lw=0.8, zorder=3)
            ax.text(x+0.06, py, pname, ha='left', va='center',
                    fontsize=fontsize-2.5, color=C_LABEL, zorder=4)
            lcoords[pname] = (x - pin_len, py)

    rcoords = {}
    if right_pins:
        for i, pname in enumerate(right_pins):
            py = y + h - h*(i+1)/(pin_count_r+1)
            ax.plot([x+w, x+w+pin_len], [py, py], '-', color=C_BORDER, lw=0.8, zorder=3)
            ax.text(x+w-0.06, py, pname, ha='right', va='center',
                    fontsize=fontsize-2.5, color=C_LABEL, zorder=4)
            rcoords[pname] = (x+w+pin_len, py)

    return lcoords, rcoords

def sig(ax, x1, y1, x2, y2, name='', color=C_WIRE, lw=1.0, via=None):
    """Draw a signal wire (horizontal-then-vertical routing). via = (xv, yv)."""
    if via:
        ax.plot([x1, via[0]], [y1, y1], '-', color=color, lw=lw, zorder=2)
        ax.plot([via[0], via[0]], [y1, y2], '-', color=color, lw=lw, zorder=2)
        ax.plot([via[0], x2], [y2, y2], '-', color=color, lw=lw, zorder=2)
    else:
        ax.plot([x1, x2], [y1, y1], '-', color=color, lw=lw, zorder=2)
        ax.plot([x2, x2], [y1, y2], '-', color=color, lw=lw, zorder=2)
        ax.plot([x2, x2], [y2, y2], '-', color=color, lw=lw, zorder=2)
    if name:
        mx = (x1+x2)/2
        my = (y1+y2)/2
        ax.text(mx, my+0.08, name, ha='center', va='bottom',
                fontsize=6.5, color=C_SIG, zorder=5)

def hline(ax, x1, y, x2, name='', color=C_WIRE, lw=1.0):
    ax.plot([x1, x2], [y, y], '-', color=color, lw=lw, zorder=2)
    if name:
        ax.text((x1+x2)/2, y+0.07, name, ha='center', va='bottom',
                fontsize=6.5, color=C_SIG, zorder=5)

def vline(ax, x, y1, y2, name='', color=C_WIRE, lw=1.0):
    ax.plot([x, x], [y1, y2], '-', color=color, lw=lw, zorder=2)
    if name:
        ax.text(x+0.08, (y1+y2)/2, name, ha='left', va='center',
                fontsize=6.5, color=C_SIG, rotation=90, zorder=5)

def dot(ax, x, y):
    ax.plot(x, y, 'o', color=C_WIRE, markersize=3, zorder=4)

def bus(ax, x1, y1, x2, y2, name, color='#7F8C8D', lw=2.5):
    """Bold bus line."""
    ax.annotate('', xy=(x2, y2), xytext=(x1, y1),
                arrowprops=dict(arrowstyle='->', color=color, lw=lw))
    mx, my = (x1+x2)/2, (y1+y2)/2
    ax.text(mx+0.1, my+0.1, name, ha='center', va='bottom',
            fontsize=7, color=color, fontweight='bold', zorder=5)

# ════════════════════════════════════════════════════════════════════
# Title block
# ════════════════════════════════════════════════════════════════════
ax.text(12, 15.7, 'Old Soviet PAL Video Tester — Complete Circuit Schematic',
        ha='center', va='top', fontsize=14, fontweight='bold', color=C_BORDER)
ax.text(12, 15.35,
        'PAL 625-line  H_TOTAL=640  V_TOTAL=625  CLK=10 MHz  H_ACT_S=120  R-2R DAC 4-bit',
        ha='center', va='top', fontsize=9, color='#555555')
ax.axhline(15.1, color=C_BORDER, lw=1.2)

# ════════════════════════════════════════════════════════════════════
# SECTION A — Power supply + clock  (left column)
# ════════════════════════════════════════════════════════════════════
# 7805 regulator
chip(ax, 0.3, 13.2, 1.4, 0.8, '7805', 'IC20\n+5V reg',
     color=C_CLK,
     left_pins=['IN(+12V)', 'GND'],
     right_pins=['+5V'])

# Crystal + 74LS04 buffer
chip(ax, 0.3, 11.6, 1.4, 1.2, '10 MHz\nXTAL+74LS04', 'IC1',
     color=C_CLK,
     left_pins=['GND', '+5V'],
     right_pins=['CLK'])

# Supply bus
vline(ax, 1.7+0.25, 13.6, 13.0, '+5V', color='#E74C3C', lw=1.5)
vline(ax, 1.95, 13.0, 13.6, 'GND', color='#7F8C8D', lw=1.5)

# ════════════════════════════════════════════════════════════════════
# SECTION B — H Counter  (74LS163 × 3)
# ════════════════════════════════════════════════════════════════════
H_CTR_Y = 11.8

# IC2: H bits 0-3
chip(ax, 2.2, H_CTR_Y, 1.8, 1.6, '74LS163\nH bits 0-3', 'IC2',
     left_pins=['CLK', 'CLR', 'LD', 'ENP','ENT','D0','D1','D2','D3'],
     right_pins=['Q0','Q1','Q2','Q3','RCO'])

# IC3: H bits 4-7
chip(ax, 4.4, H_CTR_Y, 1.8, 1.6, '74LS163\nH bits 4-7', 'IC3',
     left_pins=['CLK','CLR','LD','ENP','ENT','D0','D1','D2','D3'],
     right_pins=['Q4','Q5','Q6','Q7','RCO'])

# IC4: H bits 8-9
chip(ax, 6.6, H_CTR_Y, 1.8, 1.6, '74LS163\nH bits 8-9', 'IC4',
     left_pins=['CLK','CLR','LD','ENP','ENT','D8','D9'],
     right_pins=['Q8','Q9','RCO'])

# Clock feeds IC2 CLK
hline(ax, 1.7+0.25, 12.5, 2.2, 'CLK 10MHz')
# RCO chain: IC2→IC3→IC4
hline(ax, 4.0, 12.2, 4.4, 'RCO')
hline(ax, 6.2, 12.2, 6.6, 'RCO')

# H bus (10-bit, goes down to comparators)
ax.text(5.5, H_CTR_Y-0.2, 'H[9:0] — 10-bit H counter bus (0 to 639)',
        ha='center', va='top', fontsize=7.5, color='#7F8C8D', style='italic')

# CLR: NAND gate detects H=640 → reset all IC2/IC3/IC4
chip(ax, 8.6, H_CTR_Y+0.4, 1.2, 0.7, 'NAND\n(H=640)', 'IC4b\n74LS00',
     color='#FDFEFE',
     left_pins=['H9','H7'],
     right_pins=['CLR'])
hline(ax, 9.8, H_CTR_Y+0.75, 10.2, 'CLR→IC2/3/4')

# ════════════════════════════════════════════════════════════════════
# SECTION C — H timing comparators  (74LS688 × 3)
# ════════════════════════════════════════════════════════════════════
H_CMP_Y = 9.5

chip(ax, 2.2, H_CMP_Y, 2.0, 1.4, '74LS688\nH==16?', 'IC8\nH_FRONT',
     color='#EBF5FB',
     left_pins=['P0..P9', 'Q0..Q9', '/G'],
     right_pins=['/P=Q\n(H_SYNC_ST)'])

chip(ax, 4.7, H_CMP_Y, 2.0, 1.4, '74LS688\nH==63?', 'IC9\nH_SYNC_END',
     color='#EBF5FB',
     left_pins=['P0..P9', 'Q0..Q9', '/G'],
     right_pins=['/P=Q\n(H_SYNC_EN)'])

chip(ax, 7.2, H_CMP_Y, 2.0, 1.4, '74LS688\nH==120?', 'IC10\nH_ACT_S',
     color='#EBF5FB',
     left_pins=['P0..P9', 'Q0..Q9', '/G'],
     right_pins=['/P=Q\n(H_ACT_ST)'])

# H bus arrow to comparators
bus(ax, 5.3, H_CTR_Y, 5.3, H_CMP_Y+1.4, 'H[9:0]')

# ════════════════════════════════════════════════════════════════════
# SECTION D — H sync + active latches  (74LS74)
# ════════════════════════════════════════════════════════════════════
H_FF_Y = 7.8

chip(ax, 2.2, H_FF_Y, 1.6, 1.0, '74LS74\nH-sync FF', 'IC14',
     color='#FDEDEC',
     left_pins=['SET(H=16)', 'RST(H=63)', 'D'],
     right_pins=['Q=HSYNC', '/Q'])

chip(ax, 4.4, H_FF_Y, 1.6, 1.0, '74LS74\nH-active FF', 'IC15',
     color='#FDEDEC',
     left_pins=['SET(H=120)', 'RST(H=0)', 'D'],
     right_pins=['Q=HACT', '/Q'])

# Wires from H comparators to FFs
vline(ax, 4.2, H_CMP_Y, H_FF_Y+0.9, 'H_SYNC_ST')
vline(ax, 6.7, H_CMP_Y, H_FF_Y+0.9, 'H_SYNC_EN')
vline(ax, 9.2, H_CMP_Y, H_FF_Y+0.9, 'H_ACT_ST')

# ════════════════════════════════════════════════════════════════════
# SECTION E — V Counter  (74LS163 × 3)
# ════════════════════════════════════════════════════════════════════
V_CTR_Y = 6.0

chip(ax, 2.2, V_CTR_Y, 1.8, 1.4, '74LS163\nV bits 0-3', 'IC5',
     left_pins=['CLK(H-carry)','CLR','LD','ENP','ENT'],
     right_pins=['Q0','Q1','Q2','Q3','RCO'])

chip(ax, 4.4, V_CTR_Y, 1.8, 1.4, '74LS163\nV bits 4-7', 'IC6',
     left_pins=['CLK','CLR','LD','ENP','ENT'],
     right_pins=['Q4','Q5','Q6','Q7','RCO'])

chip(ax, 6.6, V_CTR_Y, 1.8, 1.4, '74LS163\nV bits 8-9', 'IC7',
     left_pins=['CLK','CLR','LD','ENP','ENT'],
     right_pins=['Q8','Q9','RCO'])

# H carry (RCO of IC4) clocks V counter IC5
vline(ax, 8.5, H_CTR_Y, V_CTR_Y+1.2, 'H-carry\n(line end)')
hline(ax, 2.2, V_CTR_Y+1.2, 8.5, '')
# RCO chain V counters
hline(ax, 4.0, V_CTR_Y+0.9, 4.4, 'RCO')
hline(ax, 6.2, V_CTR_Y+0.9, 6.6, 'RCO')

# V bus label
ax.text(5.5, V_CTR_Y-0.2, 'V[9:0] — 10-bit V counter bus (0 to 624)',
        ha='center', va='top', fontsize=7.5, color='#7F8C8D', style='italic')

# ════════════════════════════════════════════════════════════════════
# SECTION F — V active comparators  (74LS688 × 4)
# ════════════════════════════════════════════════════════════════════
V_CMP_Y = 4.2

chip(ax, 1.2, V_CMP_Y, 1.8, 1.2, '74LS688\nV==22?', 'IC11',
     color='#E8F8F5',
     left_pins=['P[9:0]','Q[9:0]'],
     right_pins=['F1_S'])

chip(ax, 3.4, V_CMP_Y, 1.8, 1.2, '74LS688\nV==309?', 'IC12',
     color='#E8F8F5',
     left_pins=['P[9:0]','Q[9:0]'],
     right_pins=['F1_E'])

chip(ax, 5.6, V_CMP_Y, 1.8, 1.2, '74LS688\nV==335?', 'IC13',
     color='#E8F8F5',
     left_pins=['P[9:0]','Q[9:0]'],
     right_pins=['F2_S'])

chip(ax, 7.8, V_CMP_Y, 1.8, 1.2, '74LS688\nV==622?', 'IC13b',
     color='#E8F8F5',
     left_pins=['P[9:0]','Q[9:0]'],
     right_pins=['F2_E'])

bus(ax, 5.3, V_CTR_Y, 5.3, V_CMP_Y+1.2, 'V[9:0]')

# ════════════════════════════════════════════════════════════════════
# SECTION G — Field / active SR latches  (74LS74 × 2)
# ════════════════════════════════════════════════════════════════════
FF2_Y = 2.8

chip(ax, 1.2, FF2_Y, 1.8, 1.1, '74LS74\nF1-active', 'IC16a',
     color='#FDEDEC',
     left_pins=['SET(F1_S)','RST(F1_E)','D'],
     right_pins=['Q=F1_ACT'])

chip(ax, 5.6, FF2_Y, 1.8, 1.1, '74LS74\nF2-active', 'IC16b',
     color='#FDEDEC',
     left_pins=['SET(F2_S)','RST(F2_E)','D'],
     right_pins=['Q=F2_ACT'])

# Wires from V comparators to FFs
vline(ax, 3.0,  V_CMP_Y, FF2_Y+0.9, 'F1_S')
vline(ax, 5.2,  V_CMP_Y, FF2_Y+0.9, 'F1_E')
vline(ax, 7.4,  V_CMP_Y, FF2_Y+0.9, 'F2_S')
vline(ax, 9.6,  V_CMP_Y, FF2_Y+0.9, 'F2_E')

# OR gate: F1_ACT | F2_ACT
chip(ax, 3.4, FF2_Y, 1.8, 1.1, 'OR gate\nF1|F2', 'IC14b\n74LS32',
     color='#FDFEFE',
     left_pins=['F1_ACT','F2_ACT'],
     right_pins=['V_ACT'])

# AND gate: V_ACT & H_ACT
chip(ax, 8.0, FF2_Y, 1.8, 1.1, 'AND gate\nPIXEL', 'IC15b\n74LS08',
     color='#FDFEFE',
     left_pins=['V_ACT','H_ACT'],
     right_pins=['PIXEL'])

# ════════════════════════════════════════════════════════════════════
# SECTION H — Pattern EPROM  (2732) + selector
# ════════════════════════════════════════════════════════════════════
P_Y = 9.5

chip(ax, 10.5, P_Y, 2.0, 2.8, '2732\nPATTERN ROM\n4K×8', 'IC17\nEPROM',
     color='#F9F0FF',
     left_pins=['A0..A11', 'CE', 'OE'],
     right_pins=['D0..D3\n(pattern\nbits)'])

chip(ax, 10.5, P_Y-1.8, 2.0, 1.4, '74LS138\n3→8 decoder', 'IC18',
     color='#F9F0FF',
     left_pins=['SEL[2:0]','E1','E2'],
     right_pins=['Y0..Y7\n(pattern\nselect)'])

chip(ax, 13.0, P_Y-0.5, 2.0, 2.0, '74LS251\n8→1 MUX', 'IC19',
     color='#F9F0FF',
     left_pins=['I0..I7','SEL[2:0]','/E'],
     right_pins=['Y\n(pixel bit)'])

# EPROM address from H[5:0],V[4:0]
bus(ax, 10.5, H_CTR_Y, 10.5, P_Y+2.0, 'H[5:0]+V[4:0]→A[10:0]')

# ════════════════════════════════════════════════════════════════════
# SECTION I — DAC code MUX and R-2R DAC
# ════════════════════════════════════════════════════════════════════
MUX_Y = 7.0
chip(ax, 10.5, MUX_Y, 2.2, 2.2, 'DAC Code\nSelector', 'LOGIC',
     color='#FEF9E7',
     left_pins=['HSYNC','PIXEL','PATTERN'],
     right_pins=['D3','D2','D1','D0'])

# Logic:
# HSYNC active  → DAC code = 0000 (0V sync tip)
# HSYNC=0, PIXEL=0 → 0100 (blank pedestal)
# HSYNC=0, PIXEL=1 → pattern from EPROM (up to 1111 = white)
ax.text(12.8, MUX_Y+1.6,
        'SYNC→0x0 (0V)\nBLANK→0x4 (1.25V)\nWHITE→0xF (4.69V)',
        ha='left', va='top', fontsize=7, color='#7D6608',
        bbox=dict(boxstyle='round', facecolor='#FEF9E7', alpha=0.8))

# R-2R DAC
DAC_Y = 4.5
DAC_X = 10.5

# Draw resistor ladder
R_VAL = 1   # kΩ  (2R = 2kΩ)
bit_labels = ['D3(MSB)', 'D2', 'D1', 'D0(LSB)']
node_x = [DAC_X + 0.6 + 1.0*i for i in range(4)]
bus_y  = DAC_Y + 1.0
sw_y   = DAC_Y + 1.8

ax.text(DAC_X+2.5, DAC_Y+2.6, '4-bit R-2R DAC', ha='center', fontsize=9,
        fontweight='bold', color=C_BORDER)
ax.text(DAC_X+2.5, DAC_Y+2.3, 'R = 1 kΩ   2R = 2 kΩ', ha='center',
        fontsize=7.5, color='#555555')

# Termination 2R to GND
ax.plot([DAC_X+0.1, DAC_X+0.1], [bus_y, bus_y-0.5], '-', color=C_WIRE, lw=1.2, zorder=2)
ax.text(DAC_X+0.15, bus_y-0.25, '2R\n2kΩ', ha='left', va='center', fontsize=6.5)
ax.plot([DAC_X+0.1], [bus_y-0.5], 'v', color=C_WIRE, markersize=6, zorder=3)
ax.text(DAC_X+0.15, bus_y-0.58, 'GND', ha='left', fontsize=6)
hline(ax, DAC_X+0.1, bus_y, node_x[0])

# Bus horizontal R between nodes
for i in range(3):
    hline(ax, node_x[i], bus_y, node_x[i+1])
    mx = (node_x[i]+node_x[i+1])/2
    ax.text(mx, bus_y+0.08, '1kΩ', ha='center', va='bottom', fontsize=6.5)

# Each bit: 5V source → switch → 2R → bus node
for i, (nx, lbl) in enumerate(zip(node_x, bit_labels)):
    vline(ax, nx, bus_y, sw_y)
    ax.text(nx+0.05, (bus_y+sw_y)/2, '2kΩ', ha='left', va='center', fontsize=6.5)
    # Switch symbol
    ax.plot([nx-0.12, nx+0.12], [sw_y, sw_y+0.15], '-', color=C_WIRE, lw=1.2, zorder=3)
    ax.plot([nx, nx], [sw_y+0.15, sw_y+0.45], '-', color=C_WIRE, lw=1.2, zorder=3)
    ax.text(nx, sw_y+0.5, f'{lbl}\n5V', ha='center', va='bottom', fontsize=6.5)

# Output: 75Ω load to GND + BNC label
out_x = node_x[-1] + 0.6
hline(ax, node_x[-1], bus_y, out_x)
dot(ax, node_x[-1], bus_y)
vline(ax, out_x, bus_y, bus_y-0.5)
ax.text(out_x+0.05, bus_y-0.25, '75Ω\ncable', ha='left', va='center', fontsize=6.5)
ax.plot([out_x], [bus_y-0.5], 'v', color=C_WIRE, markersize=6, zorder=3)
ax.text(out_x+0.05, bus_y-0.58, 'GND', ha='left', fontsize=6)
# Probe/BNC connector
ax.plot([out_x, out_x+0.8], [bus_y, bus_y], '-', color=C_WIRE, lw=1.5, zorder=2)
ax.add_patch(mpatches.Circle((out_x+0.8, bus_y), 0.12,
             color='#E67E22', zorder=4, label='BNC'))
ax.text(out_x+1.0, bus_y, 'VIDEO OUT\n(BNC)\n0–5V', ha='left', va='center',
        fontsize=7.5, color='#E67E22', fontweight='bold')

# DAC code wire from selector
hline(ax, 12.7, MUX_Y+0.5, DAC_X+2.5, name='D[3:0] DAC code')

# ════════════════════════════════════════════════════════════════════
# SECTION J — Pattern selector switches
# ════════════════════════════════════════════════════════════════════
chip(ax, 15.0, 10.5, 2.0, 2.0, 'PATTERN\nSELECTOR\n(SEL[2:0])', 'SW1\nrotary',
     color='#EBF5FB',
     left_pins=['GND'],
     right_pins=['SEL0','SEL1','SEL2'])

ax.text(15.5, 10.1, 'SW1 selects pattern:\n'
        '0=Sync bar  1=White  2=Ramp\n'
        '3=Crosshatch  4=Circle  5=Dot\n'
        '6=Zone bar  7=Colour bar',
        ha='left', va='top', fontsize=7, color='#555555')

# ════════════════════════════════════════════════════════════════════
# Signal annotation boxes
# ════════════════════════════════════════════════════════════════════
annot_data = [
    (16.2, 14.5,
     'H Timing  (H_TOTAL=640 clocks @ 10 MHz = 64 µs/line)\n'
     '  H_FRONT   =  16 clocks =  1.6 µs  front porch\n'
     '  H_SYNC_W  =  47 clocks =  4.7 µs  H-sync pulse (csync LOW)\n'
     '  H_BACK    =  57 clocks =  5.7 µs  back porch / colour burst\n'
     '  H_ACTIVE  = 520 clocks = 52.0 µs  active pixels\n'
     '  H_ACT_S   = 120        (H_FRONT+H_SYNC_W+H_BACK)'),
    (16.2, 12.8,
     'V Timing  (V_TOTAL=625 lines = 2 fields @ 25 Hz frame)\n'
     '  Field 1 active : v_cnt  22–309  → scope lines  23–310 (288 lines)\n'
     '  Field 2 active : v_cnt 335–622  → scope lines 336–623 (288 lines)\n'
     '  VBI / vsync region: lines  1–22 (F1) and 311–335 (F2)\n'
     '  PAL vsync: 5 pre-eq + 5 broad + 5 post-eq half-lines each field'),
    (16.2, 10.6,
     'DAC Output Levels\n'
     '  Code 0x0 = 0000 →  0.00 V  sync tip\n'
     '  Code 0x4 = 0100 →  1.25 V  blanking pedestal\n'
     '  Code 0x7 = 0111 →  2.19 V  50% grey\n'
     '  Code 0xF = 1111 →  4.69 V  white peak\n'
     '  R=1 kΩ  2R=2 kΩ  load=75 Ω  (cable-terminated)'),
    (16.2, 8.5,
     'Key ICs  (74LS / К155 series)\n'
     '  74LS163  = 4-bit synchronous binary counter  (К155ИЕ7)\n'
     '  74LS688  = 8-bit magnitude comparator P==Q   (К555СП1)\n'
     '  74LS74   = dual D flip-flop with RST/SET     (К155ТМ2)\n'
     '  74LS00   = quad 2-input NAND gate            (К155ЛА3)\n'
     '  74LS08   = quad 2-input AND gate             (К155ЛИ1)\n'
     '  74LS32   = quad 2-input OR gate              (К155ЛЛ1)\n'
     '  2732     = 4K×8 UV-erasable EPROM            (К573РФ2)\n'
     '  74LS138  = 3-to-8 decoder                   (К155ИД7)\n'
     '  74LS251  = 8-to-1 MUX                       (К555КП7)\n'
     '  7805     = 5V linear regulator              (КР142ЕН5)'),
]

for (ax_x, ax_y, txt) in annot_data:
    ax.text(ax_x, ax_y, txt, ha='left', va='top', fontsize=7,
            color='#1A1A1A', family='monospace',
            bbox=dict(boxstyle='round', facecolor='white',
                      edgecolor='#BDC3C7', linewidth=0.8, alpha=0.95))

# ════════════════════════════════════════════════════════════════════
# Footer
# ════════════════════════════════════════════════════════════════════
ax.axhline(0.4, color=C_BORDER, lw=0.8)
ax.text(0.2, 0.3, 'PAL Video IP Core — Old Soviet Tester Reference Schematic',
        ha='left', va='top', fontsize=7, color='#555555')
ax.text(23.8, 0.3, 'rev 1.0  2026-06-21', ha='right', va='top',
        fontsize=7, color='#555555')

plt.tight_layout(pad=0.5)
out_path = '/home/user/video-ip-core-/docs/pal_old_tester_schematic.pdf'
plt.savefig(out_path, dpi=200, bbox_inches='tight', facecolor='#FAFAFA')
png_path = out_path.replace('.pdf', '.png')
plt.savefig(png_path, dpi=150, bbox_inches='tight', facecolor='#FAFAFA')
print(f"Saved: {out_path}")
print(f"Saved: {png_path}")
