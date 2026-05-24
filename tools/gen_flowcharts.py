#!/usr/bin/env python3
"""
Flowchart image generator for PAL/NTSC Video IP Core documentation.
Saves PNG files to docs/img/ for embedding in Word documents.
"""
import os
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.patches import FancyBboxPatch
import numpy as np

IMG_DIR = '/home/user/video-ip-core-/docs/img'
os.makedirs(IMG_DIR, exist_ok=True)

# ── Colour palette ────────────────────────────────────────────────────────────
BG      = '#F8F9FA'
C_START = '#37860A'   # green
C_END   = '#C00000'   # red
C_PROC  = '#1F497D'   # dark blue
C_DEC   = '#C55A11'   # orange
C_IO    = '#2E74B5'   # mid blue
C_SUB   = '#70309F'   # purple
C_RED   = '#C00000'   # red (alias)
C_NOTE  = '#404040'   # dark grey
ARROW   = '#222222'
WHITE   = '#FFFFFF'
LGREY   = '#E8EEF4'

# ── Flowchart primitives ──────────────────────────────────────────────────────
def oval(ax, x, y, w, h, text, fc=C_START, tc=WHITE, fs=8.5, lw=0):
    ellipse = mpatches.Ellipse((x, y), w, h, facecolor=fc, edgecolor=WHITE, linewidth=2)
    ax.add_patch(ellipse)
    ax.text(x, y, text, ha='center', va='center', fontsize=fs,
            color=tc, fontweight='bold', multialignment='center')

def rect(ax, x, y, w, h, text, fc=C_PROC, tc=WHITE, fs=8.5, radius=0.12):
    box = FancyBboxPatch((x-w/2, y-h/2), w, h,
                          boxstyle=f'round,pad={radius}',
                          facecolor=fc, edgecolor=WHITE, linewidth=1.5)
    ax.add_patch(box)
    ax.text(x, y, text, ha='center', va='center', fontsize=fs,
            color=tc, multialignment='center', wrap=True)

def diamond(ax, x, y, w, h, text, fc=C_DEC, tc=WHITE, fs=8):
    pts = np.array([[x, y+h/2], [x+w/2, y], [x, y-h/2], [x-w/2, y]])
    poly = mpatches.Polygon(pts, facecolor=fc, edgecolor=WHITE, linewidth=1.5)
    ax.add_patch(poly)
    ax.text(x, y, text, ha='center', va='center', fontsize=fs,
            color=tc, fontweight='bold', multialignment='center')

def arrow(ax, x1, y1, x2, y2, label='', label_side='right', color=ARROW, lw=1.5):
    ax.annotate('', xy=(x2, y2), xytext=(x1, y1),
                arrowprops=dict(arrowstyle='->', color=color, lw=lw,
                                connectionstyle='arc3,rad=0.0'))
    if label:
        mx = (x1+x2)/2 + (0.12 if label_side=='right' else -0.12)
        my = (y1+y2)/2
        ax.text(mx, my, label, fontsize=7.5, color='#333',
                ha='left' if label_side=='right' else 'right', va='center')

def arrow_bend(ax, x1, y1, xm, ym, x2, y2, color=ARROW, lw=1.5):
    """L-shaped arrow through midpoint"""
    ax.annotate('', xy=(xm, ym), xytext=(x1, y1),
                arrowprops=dict(arrowstyle='-', color=color, lw=lw))
    ax.annotate('', xy=(x2, y2), xytext=(xm, ym),
                arrowprops=dict(arrowstyle='->', color=color, lw=lw))

def title_band(ax, text, ymax):
    ax.text(0.5, ymax-0.15, text, ha='center', va='top',
            fontsize=11, fontweight='bold', color=C_PROC,
            transform=ax.transAxes)

def finalize(ax, fig, path, title):
    ax.set_aspect('equal')
    ax.axis('off')
    fig.patch.set_facecolor(BG)
    ax.set_facecolor(BG)
    fig.suptitle(title, fontsize=10, fontweight='bold', color=C_PROC, y=0.98)
    fig.tight_layout(pad=0.3)
    fig.savefig(path, dpi=140, bbox_inches='tight', facecolor=BG)
    plt.close(fig)
    print(f'  {os.path.basename(path)}')

# =============================================================================
# FC-1: SDD — System Architecture Flow
# =============================================================================
def fc_architecture():
    fig, ax = plt.subplots(figsize=(5.5, 10))
    ax.set_xlim(-3, 3); ax.set_ylim(-11, 1)

    steps = [
        (0,  0.0,  'Clock Input\n10 / 20 / 30 / 40 MHz', C_IO,    'oval'),
        (0, -1.5,  'pal_timing\nH/V Counters + CLK_DIV', C_PROC,  'rect'),
        (0, -3.0,  'pal_csync_il\nSync Decode  |  Field  |  Active', C_PROC, 'rect'),
        (0, -4.6,  'Pattern Generators\nsel 0–9', C_SUB,  'rect'),
        (0, -6.2,  'Active Level Mux\n(sel → DAC level)', C_DEC,  'rect'),
        (0, -7.7,  'Sync / Blanking Overlay\n(dac_out assignment)', C_PROC, 'rect'),
        (0, -9.2,  'dac_out [3:0]\n→ R-2R DAC → Video Out', C_END, 'oval'),
    ]
    labels = ['CLK_MHZ\ngeneric', 'h_cnt, v_cnt\nce', 'csync, field\nactive', 'active_level', 'LEVEL_SYNC\nLEVEL_BLANK', '']

    for i, (x, y, txt, col, sh) in enumerate(steps):
        if sh == 'oval': oval(ax, x, y, 3.8, 0.7, txt, fc=col)
        else:            rect(ax, x, y, 3.6, 0.7, txt, fc=col)
        if i < len(steps)-1:
            arrow(ax, 0, y-0.35, 0, steps[i+1][1]+0.35, label=labels[i], label_side='right')

    # Side inputs
    rect(ax, -2.2, -4.6, 1.5, 0.5, 'BRAM\n(sel=4)', fc=C_IO, fs=7.5)
    arrow(ax, -1.45, -4.6, -1.8, -4.6)
    rect(ax, 2.2, -4.6, 1.5, 0.5, 'Ball / Cross\n(sel 5–9)', fc=C_IO, fs=7.5)
    arrow(ax, 1.45, -4.6, 1.8, -4.6)

    finalize(ax, fig, f'{IMG_DIR}/fc_architecture.png', 'SDD — System Architecture Flow')

# =============================================================================
# FC-2: SDD — Double-Buffer State Machine
# =============================================================================
def fc_double_buffer():
    fig, ax = plt.subplots(figsize=(7, 9))
    ax.set_xlim(-4, 4); ax.set_ylim(-10, 1)

    oval(ax, 0, 0, 2.8, 0.65, 'RESET', fc=C_END)
    arrow(ax, 0, -0.33, 0, -1.17)

    rect(ax, 0, -1.6, 4.0, 0.75,
         'IDLE\ndisp_buf=0  swap_req=0  buf_swapped=0', fc=C_PROC)
    arrow(ax, 0, -2.0, 0, -2.8, label='buf_swap=1')

    rect(ax, 0, -3.2, 3.2, 0.65,
         'PENDING\nswap_req=1', fc=C_SUB)
    arrow(ax, 0, -3.55, 0, -4.4, label='every clock: buf_swapped←0')

    diamond(ax, 0, -5.0, 3.8, 0.9,
            'v_cnt=V_ACT_E_F2\nAND h_cnt=H_TOTAL-1\nAND swap_req=1?', fc=C_DEC)

    # NO branch — right side loop back
    arrow(ax, 1.9, -5.0, 3.2, -5.0, label='NO', label_side='right')
    ax.annotate('', xy=(3.2, -3.2), xytext=(3.2, -5.0),
                arrowprops=dict(arrowstyle='-', color=ARROW, lw=1.5))
    ax.annotate('', xy=(1.6, -3.2), xytext=(3.2, -3.2),
                arrowprops=dict(arrowstyle='->', color=ARROW, lw=1.5))
    ax.text(3.35, -4.1, 'Next clock', fontsize=7.5, color='#333', va='center')

    # YES branch
    arrow(ax, 0, -5.45, 0, -6.3, label='YES')
    rect(ax, 0, -6.7, 4.0, 0.75,
         'SWAP EXECUTE\ndisp_buf ← NOT disp_buf\nswap_req ← 0\nbuf_swapped_s ← 1', fc=C_START, fs=8)
    arrow(ax, 0, -7.1, 0, -7.85)

    rect(ax, 0, -8.3, 4.0, 0.75,
         'IDLE (new state)\ndisp_buf swapped  |  buf_swapped strobes 1 clock', fc=C_PROC)

    # Loop arrow back from idle to pending
    arrow(ax, 0, -8.7, 0, -9.4)
    rect(ax, 0, -9.7, 2.4, 0.45, 'Back to IDLE', fc=C_IO, fs=8)

    # Annotations
    ax.text(-3.8, -3.2, 'Host writes to\nback buffer\n(NOT disp_buf)', fontsize=7.5,
            color=C_PROC, ha='left', va='center',
            bbox=dict(boxstyle='round', fc=LGREY, ec=C_PROC, lw=0.8))
    ax.text(-3.8, -8.3, 'Display reads from\nfront buffer\n(disp_buf)', fontsize=7.5,
            color=C_PROC, ha='left', va='center',
            bbox=dict(boxstyle='round', fc=LGREY, ec=C_PROC, lw=0.8))

    finalize(ax, fig, f'{IMG_DIR}/fc_double_buffer.png', 'SDD — Double-Buffer State Machine')

# =============================================================================
# FC-3: SDD — Ball Physics Update
# =============================================================================
def fc_ball_physics():
    fig, ax = plt.subplots(figsize=(6, 11))
    ax.set_xlim(-3.5, 3.5); ax.set_ylim(-12, 1)

    oval(ax, 0, 0, 3.2, 0.65, 'Trigger: v_cnt=V_ACT_E_F2, h_cnt=H_TOTAL-1', fc=C_START, fs=7.5)
    arrow(ax, 0, -0.33, 0, -1.05)
    rect(ax, 0, -1.45, 4.0, 0.65, 'nx = ball_x + ball_vx\nny = ball_y + ball_vy', fc=C_IO)
    arrow(ax, 0, -1.8, 0, -2.6)
    diamond(ax, 0, -3.1, 3.6, 0.9, 'nx > H_ACTIVE\n− ball_w ?', fc=C_DEC)
    # YES right
    arrow(ax, 1.8, -3.1, 2.8, -3.1, label='YES', label_side='right')
    rect(ax, 3.1, -3.1, 1.2, 0.6, 'nx=reflect\nnvx=−nvx', fc=C_DEC, fs=7.5)
    # NO down
    arrow(ax, 0, -3.55, 0, -4.35, label='NO')
    diamond(ax, 0, -4.85, 3.2, 0.9, 'nx < 0 ?', fc=C_DEC)
    arrow(ax, 1.6, -4.85, 2.8, -4.85, label='YES', label_side='right')
    rect(ax, 3.1, -4.85, 1.2, 0.6, 'nx=−nx\nnvx=−nvx', fc=C_DEC, fs=7.5)
    arrow(ax, 0, -5.3, 0, -6.1, label='NO')
    diamond(ax, 0, -6.6, 3.6, 0.9, 'ny > 576\n− ball_h ?', fc=C_DEC)
    arrow(ax, 1.8, -6.6, 2.8, -6.6, label='YES', label_side='right')
    rect(ax, 3.1, -6.6, 1.2, 0.6, 'ny=reflect\nnvy=−nvy', fc=C_DEC, fs=7.5)
    arrow(ax, 0, -7.05, 0, -7.85, label='NO')
    diamond(ax, 0, -8.35, 3.2, 0.9, 'ny < 0 ?', fc=C_DEC)
    arrow(ax, 1.6, -8.35, 2.8, -8.35, label='YES', label_side='right')
    rect(ax, 3.1, -8.35, 1.2, 0.6, 'ny=−ny\nnvy=−nvy', fc=C_DEC, fs=7.5)
    arrow(ax, 0, -8.8, 0, -9.55, label='NO')
    rect(ax, 0, -9.95, 4.0, 0.65,
         'ball_x←nx  ball_y←ny\nball_vx←nvx  ball_vy←nvy', fc=C_PROC)
    arrow(ax, 0, -10.3, 0, -10.95)
    oval(ax, 0, -11.2, 2.2, 0.5, 'Done (next frame)', fc=C_END, fs=8)

    # Connect YES branches back down to main flow via merge dots
    for ry, fy in [(-3.1, -3.55), (-4.85, -5.3), (-6.6, -7.05), (-8.35, -8.8)]:
        ax.annotate('', xy=(3.1, ry+0.3), xytext=(3.1, ry-0.3),
                    arrowprops=dict(arrowstyle='-', color=ARROW, lw=0.8))
        # vertical line from rect to merge
        nxt_diamond_y = fy + 0.25
        ax.annotate('', xy=(0.18, nxt_diamond_y), xytext=(3.1, ry-0.3),
                    arrowprops=dict(arrowstyle='->', color=ARROW, lw=1.0,
                                    connectionstyle='angle,angleA=0,angleB=90'))

    finalize(ax, fig, f'{IMG_DIR}/fc_ball_physics.png', 'SDD — Ball Physics Update (per frame)')

# =============================================================================
# FC-4: ICD — BRAM Write Protocol
# =============================================================================
def fc_bram_write():
    fig, ax = plt.subplots(figsize=(5.5, 9.5))
    ax.set_xlim(-3, 3); ax.set_ylim(-10.5, 1)

    oval(ax, 0,  0.0, 3.0, 0.6, 'Start: Write pixel to BRAM', fc=C_START)
    arrow(ax, 0, -0.3, 0, -1.0)
    rect(ax, 0, -1.4, 4.2, 0.6, 'Set bram_wr_addr = pixel address\n(0 … BRAM_DEPTH − 1)', fc=C_IO)
    arrow(ax, 0, -1.7, 0, -2.45)
    rect(ax, 0, -2.85, 3.6, 0.6, 'Set bram_wr_data = 0 (black)\nor bram_wr_data = 1 (white)', fc=C_IO)
    arrow(ax, 0, -3.15, 0, -3.9)
    rect(ax, 0, -4.3, 3.2, 0.55, 'Assert bram_wr_en = 1', fc=C_PROC)
    arrow(ax, 0, -4.58, 0, -5.3)
    rect(ax, 0, -5.7, 3.2, 0.6, 'rising_edge(clk)\n↓\nIP writes pixel to back buffer bank', fc=C_SUB)
    arrow(ax, 0, -6.0, 0, -6.7)
    rect(ax, 0, -7.1, 3.2, 0.55, 'Deassert bram_wr_en = 0', fc=C_PROC)
    arrow(ax, 0, -7.38, 0, -8.1)
    diamond(ax, 0, -8.6, 2.8, 0.9, 'More\npixels?', fc=C_DEC)
    # YES — loop back left
    arrow(ax, -1.4, -8.6, -2.5, -8.6, label='YES', label_side='right')
    ax.annotate('', xy=(-2.5, -1.4), xytext=(-2.5, -8.6),
                arrowprops=dict(arrowstyle='-', color=ARROW, lw=1.5))
    ax.annotate('', xy=(-2.1, -1.4), xytext=(-2.5, -1.4),
                arrowprops=dict(arrowstyle='->', color=ARROW, lw=1.5))
    ax.text(-2.65, -5.0, 'Next\npixel', fontsize=7.5, color='#555', ha='right', va='center')
    # NO — down
    arrow(ax, 0, -9.05, 0, -9.75, label='NO')
    oval(ax, 0, -10.0, 2.6, 0.5, 'Write complete', fc=C_END, fs=8.5)

    finalize(ax, fig, f'{IMG_DIR}/fc_bram_write.png', 'ICD — BRAM Write Protocol')

# =============================================================================
# FC-5: ICD — Double-Buffer Handshake
# =============================================================================
def fc_buf_handshake():
    fig, ax = plt.subplots(figsize=(8, 9))
    ax.set_xlim(-4.2, 4.2); ax.set_ylim(-10.5, 1.5)

    # Column headers
    ax.text(-2.5, 1.2, 'HOST', fontsize=11, fontweight='bold', color=C_PROC, ha='center')
    ax.text( 2.5, 1.2, 'IP CORE', fontsize=11, fontweight='bold', color=C_IO,  ha='center')
    ax.axvline(0, color='#CCC', lw=1, linestyle='--', ymin=0.02, ymax=0.97)

    # ── Step 1
    rect(ax, -2.5, 0, 3.2, 0.55, '1. Read back_buf_o\n(which bank to write to)', fc=C_PROC, fs=8)
    rect(ax,  2.5, 0, 3.0, 0.55, 'Displaying front bank', fc=C_IO, fs=8)
    arrow(ax, -2.5, -0.28, -2.5, -1.05)
    arrow(ax,  2.5, -0.28,  2.5, -1.05)

    # ── Step 2
    rect(ax, -2.5, -1.45, 3.2, 0.65, '2. Write new frame\nto back buffer\n(addr 0 … BRAM_DEPTH−1)', fc=C_PROC, fs=8)
    rect(ax,  2.5, -1.45, 3.0, 0.65, 'Continuously\ndisplaying front bank', fc=C_IO, fs=8)
    arrow(ax, -2.5, -1.78, -2.5, -2.6)
    arrow(ax,  2.5, -1.78,  2.5, -2.6)

    # ── Step 3 — buf_swap pulse →
    rect(ax, -2.5, -3.0, 3.2, 0.65, '3. Pulse buf_swap = 1\nfor ONE clock then → 0', fc=C_DEC, fs=8)
    ax.annotate('', xy=(0.7, -3.0), xytext=(-0.9, -3.0),
                arrowprops=dict(arrowstyle='->', color=C_DEC, lw=2))
    ax.text(-0.1, -2.82, 'buf_swap', fontsize=7.5, color=C_DEC, ha='center')
    rect(ax,  2.5, -3.0, 3.0, 0.65, 'Latches swap_req=1\nContinues display', fc=C_IO, fs=8)
    arrow(ax, -2.5, -3.33, -2.5, -4.1)
    arrow(ax,  2.5, -3.33,  2.5, -4.1)

    # ── Step 4 — V-blank swap
    rect(ax, -2.5, -4.5, 3.2, 0.55, '4. Waiting for\nbuf_swapped strobe', fc=C_PROC, fs=8)
    rect(ax,  2.5, -4.5, 3.0, 0.65, 'At V-blank:\nFlip disp_buf\nStrobe buf_swapped=1', fc=C_START, fs=8)
    ax.annotate('', xy=(-0.9, -4.5), xytext=(0.7, -4.5),
                arrowprops=dict(arrowstyle='->', color=C_START, lw=2))
    ax.text(-0.1, -4.32, 'buf_swapped', fontsize=7.5, color=C_START, ha='center')
    arrow(ax, -2.5, -4.78, -2.5, -5.55)
    arrow(ax,  2.5, -4.78,  2.5, -5.55)

    # ── Step 5 — After swap
    rect(ax, -2.5, -5.95, 3.2, 0.65, '5. Swap confirmed\nback_buf_o updated\nStart writing next frame', fc=C_SUB, fs=8)
    rect(ax,  2.5, -5.95, 3.0, 0.65, 'New frame now live\non screen', fc=C_IO, fs=8)
    arrow(ax, -2.5, -6.28, -2.5, -7.0)
    oval(ax, -2.5, -7.3, 3.0, 0.55, 'Repeat from Step 2', fc=C_END, fs=8.5)

    finalize(ax, fig, f'{IMG_DIR}/fc_buf_handshake.png', 'ICD — Double-Buffer Handshake Protocol')

# =============================================================================
# FC-6: CM — Change Control Process
# =============================================================================
def fc_change_control():
    fig, ax = plt.subplots(figsize=(5.5, 11.5))
    ax.set_xlim(-3, 3); ax.set_ylim(-12.5, 1)

    oval(ax, 0, 0, 3.0, 0.6, 'Identify Change\n(feature / fix / doc)', fc=C_START)
    arrow(ax, 0, -0.3, 0, -1.05)
    rect(ax, 0, -1.45, 4.2, 0.6, 'Create / switch to feature branch\nModify RTL source or documents', fc=C_PROC)
    arrow(ax, 0, -1.75, 0, -2.5)
    rect(ax, 0, -2.9, 4.0, 0.6, 'Run GHDL testbenches\nghdl -a / -e / -r --std=08', fc=C_IO)
    arrow(ax, 0, -3.2, 0, -3.95)
    diamond(ax, 0, -4.45, 3.0, 0.9, 'All TCs\nPASS?', fc=C_DEC)
    # NO — left loop
    arrow(ax, -1.5, -4.45, -2.5, -4.45, label='NO', label_side='right')
    ax.annotate('', xy=(-2.5, -1.45), xytext=(-2.5, -4.45),
                arrowprops=dict(arrowstyle='-', color=ARROW, lw=1.5))
    ax.annotate('', xy=(-2.1, -1.45), xytext=(-2.5, -1.45),
                arrowprops=dict(arrowstyle='->', color=ARROW, lw=1.5))
    ax.text(-2.65, -2.95, 'Debug\n& Fix', fontsize=7.5, color='#555', ha='right', va='center')
    # YES — down
    arrow(ax, 0, -4.9, 0, -5.65, label='YES')
    rect(ax, 0, -6.05, 3.6, 0.6, 'Update CHANGE_LOG\nand relevant doc files', fc=C_SUB)
    arrow(ax, 0, -6.35, 0, -7.1)
    rect(ax, 0, -7.5, 3.6, 0.6, 'git add + git commit\n(descriptive message)', fc=C_PROC)
    arrow(ax, 0, -7.8, 0, -8.55)
    rect(ax, 0, -8.95, 3.6, 0.55, 'git push origin\nclaude/xilinx-pal-video-ip-RIDhJ', fc=C_PROC)
    arrow(ax, 0, -9.23, 0, -9.95)
    diamond(ax, 0, -10.45, 3.0, 0.9, 'Baseline\nready?', fc=C_DEC)
    arrow(ax, 1.5, -10.45, 2.5, -10.45, label='YES', label_side='right')
    rect(ax, 2.8, -10.45, 1.4, 0.55, 'Create PR\n→ merge main', fc=C_START, fs=7.5)
    arrow(ax, 0, -10.9, 0, -11.65, label='NO')
    oval(ax, 0, -11.9, 3.0, 0.55, 'Continue development', fc=C_END, fs=8.5)

    finalize(ax, fig, f'{IMG_DIR}/fc_change_control.png', 'CM — Change Control Process')

# =============================================================================
# FC-7: STP — Test Execution Process
# =============================================================================
def fc_test_execution():
    fig, ax = plt.subplots(figsize=(5.5, 11))
    ax.set_xlim(-3, 3); ax.set_ylim(-12, 1)

    oval(ax, 0, 0, 3.2, 0.6, 'Select Module Under Test', fc=C_START)
    arrow(ax, 0, -0.3, 0, -1.0)
    rect(ax, 0, -1.4, 4.2, 0.6, 'Compile:\nghdl -a --std=08 <deps> <dut> <tb>', fc=C_IO, fs=8)
    arrow(ax, 0, -1.7, 0, -2.45)
    diamond(ax, 0, -2.95, 2.8, 0.9, 'Compile\nOK?', fc=C_DEC)
    arrow(ax, 1.4, -2.95, 2.5, -2.95, label='NO', label_side='right')
    rect(ax, 2.8, -2.95, 1.3, 0.55, 'Fix VHDL\nsyntax', fc=C_RED, fs=7.5)
    ax.annotate('', xy=(2.8, -1.4), xytext=(2.8, -2.68),
                arrowprops=dict(arrowstyle='-', color=ARROW, lw=1.5))
    ax.annotate('', xy=(2.1, -1.4), xytext=(2.8, -1.4),
                arrowprops=dict(arrowstyle='->', color=ARROW, lw=1.5))
    arrow(ax, 0, -3.4, 0, -4.15, label='YES')
    rect(ax, 0, -4.55, 4.0, 0.55, 'Elaborate:\nghdl -e --std=08 <entity>', fc=C_IO, fs=8)
    arrow(ax, 0, -4.83, 0, -5.58)
    rect(ax, 0, -5.98, 4.2, 0.65,
         'Run:\nghdl -r --std=08 <entity>\n--assert-level=error [--vcd=file]', fc=C_IO, fs=8)
    arrow(ax, 0, -6.31, 0, -7.06)
    diamond(ax, 0, -7.55, 2.8, 0.9, 'Exit\ncode = 0?', fc=C_DEC)
    arrow(ax, 1.4, -7.55, 2.5, -7.55, label='NO', label_side='right')
    rect(ax, 2.8, -7.55, 1.4, 0.65, 'Analyse\nfailure\nreport', fc=C_RED, fs=7.5)
    ax.annotate('', xy=(2.8, -5.98), xytext=(2.8, -7.22),
                arrowprops=dict(arrowstyle='-', color=ARROW, lw=1.5))
    ax.annotate('', xy=(2.1, -5.98), xytext=(2.8, -5.98),
                arrowprops=dict(arrowstyle='->', color=ARROW, lw=1.5))
    arrow(ax, 0, -8.0, 0, -8.75, label='YES')
    rect(ax, 0, -9.15, 3.8, 0.65, 'Save log: tools/sim_out/<tb>.log\nCapture VCD (optional)', fc=C_SUB, fs=8)
    arrow(ax, 0, -9.48, 0, -10.2)
    rect(ax, 0, -10.6, 3.0, 0.6, 'PASS\nCommit allowed', fc=C_START, fs=9)
    arrow(ax, 0, -10.9, 0, -11.55)
    diamond(ax, 0, -11.9, 2.8, 0.65, 'More modules?', fc=C_DEC, fs=7.5)
    arrow(ax, -1.4, -11.9, -2.5, -11.9, label='YES', label_side='right')
    ax.annotate('', xy=(-2.5, 0), xytext=(-2.5, -11.9),
                arrowprops=dict(arrowstyle='-', color=ARROW, lw=1.5))
    ax.annotate('', xy=(-1.6, 0), xytext=(-2.5, 0),
                arrowprops=dict(arrowstyle='->', color=ARROW, lw=1.5))

    finalize(ax, fig, f'{IMG_DIR}/fc_test_execution.png', 'STP — Test Execution Process')

# =============================================================================
# FC-8: SDP — Development Phase Flow
# =============================================================================
def fc_dev_phases():
    fig, ax = plt.subplots(figsize=(6, 11.5))
    ax.set_xlim(-3.2, 3.2); ax.set_ylim(-12.5, 1)

    phases = [
        (0,  0,   'PHASE 1 — Base IP\npal_timing · pal_csync_il · opt1/2/3 variants\nBase patterns sel 0–3', C_IO),
        (0, -2.0, 'PHASE 2 — BRAM Image (sel=4)\nNatural sequential row addressing\npal_bram_loader utility', C_PROC),
        (0, -4.0, 'PHASE 3 — Extensions\nsel 5–9 · Ball ports · Crosshatch\nNTSC mode (video_bram_top)', C_PROC),
        (0, -6.0, 'PHASE 4 — Double Buffering\nTwo BRAM banks · buf_swap handshake\nTear-free image update', C_SUB),
        (0, -8.0, 'PHASE 5 — Developer Tools\nHTML pattern generator (v1+v2)\nUser Guide Word document', C_IO),
        (0,-10.0, 'PHASE 6 — Formal Documentation\nICD · SRS · SDD · SDP · CM · STP\nSTR · VC · TM · BR · CL', C_IO),
    ]
    for i, (x, y, txt, col) in enumerate(phases):
        rect(ax, x, y, 5.5, 1.3, txt, fc=col, fs=8.5)
        if i < len(phases)-1:
            arrow(ax, 0, y-0.65, 0, phases[i+1][1]+0.65)
        # status badge
        ax.text(3.0, y, '✓ COMPLETE', fontsize=7.5, color=C_START,
                fontweight='bold', ha='center', va='center',
                bbox=dict(boxstyle='round,pad=0.2', fc=LGREY, ec=C_START, lw=0.8))

    arrow(ax, 0, -10.65, 0, -11.4)
    oval(ax, 0, -11.7, 2.8, 0.55, 'V1.0 Release', fc=C_START, fs=9)

    finalize(ax, fig, f'{IMG_DIR}/fc_dev_phases.png', 'SDP — Development Phase Flow')

# =============================================================================
# FC-9: SDD — Active Level Mux Decision Tree
# =============================================================================
def fc_active_mux():
    fig, ax = plt.subplots(figsize=(7, 11))
    ax.set_xlim(-4, 4); ax.set_ylim(-12, 1)

    oval(ax, 0, 0, 2.6, 0.6, 'active_s = 1\n(active pixel)', fc=C_START, fs=8.5)
    arrow(ax, 0, -0.3, 0, -1.05)
    diamond(ax, 0, -1.6, 2.8, 0.9, 'sel\nvalue?', fc=C_DEC)

    entries = [
        (-3.2, -3.5, 'sel=0', 'color_v=1\n→ white_s\nelse black_s', C_PROC),
        (-1.6, -3.5, 'sel=1', 'color_h=1\n→ white_s\nelse black_s', C_PROC),
        ( 0.0, -3.5, 'sel=2', 'grad_x_s\n(H gradient)', C_PROC),
        ( 1.6, -3.5, 'sel=3', 'grad_y_s\n(V gradient)', C_PROC),
        ( 3.2, -3.5, 'sel=4', 'bram_level\n(BRAM pixel)', C_IO),
    ]
    for ex, ey, slbl, out, col in entries:
        ax.annotate('', xy=(ex, ey+0.5), xytext=(0, -2.05),
                    arrowprops=dict(arrowstyle='->', color=ARROW, lw=1.0,
                                    connectionstyle='arc3,rad=0'))
        ax.text(ex, ey+0.65, slbl, fontsize=7, color=C_DEC, ha='center', fontweight='bold')
        rect(ax, ex, ey, 1.4, 0.85, out, fc=col, fs=7.5)

    entries2 = [
        (-2.8, -6.2, 'sel=5', 'ball_on=1\n→ white_s\nelse black_s', C_SUB),
        (-1.0, -6.2, 'sel=6', 'white_s\n(full white)', C_START),
        ( 0.8, -6.2, 'sel=7', 'black_s\n(full black)', C_END),
        ( 2.6, -6.2, 'sel=8', 'cross_on=1\n→ white_s\nelse black_s', C_SUB),
    ]
    # second diamond
    diamond(ax, 0, -4.8, 3.0, 0.9, 'sel=5–9\nor other?', fc=C_DEC)
    ax.annotate('', xy=(0, -4.35), xytext=(0, -4.05),
                arrowprops=dict(arrowstyle='->', color=ARROW, lw=1.0))
    # connect all sel=0-4 boxes to diamond
    for ex, _, _, _, _ in entries:
        ax.annotate('', xy=(0, -4.35), xytext=(ex, -3.93),
                    arrowprops=dict(arrowstyle='-', color='#aaa', lw=0.7,
                                    connectionstyle='arc3,rad=0'))

    for ex, ey, slbl, out, col in entries2:
        ax.annotate('', xy=(ex, ey+0.5), xytext=(0, -5.25),
                    arrowprops=dict(arrowstyle='->', color=ARROW, lw=1.0,
                                    connectionstyle='arc3,rad=0'))
        ax.text(ex, ey+0.65, slbl, fontsize=7, color=C_DEC, ha='center', fontweight='bold')
        rect(ax, ex, ey, 1.4, 0.85, out, fc=col, fs=7.5)

    # sel=9
    rect(ax, 0.8, -8.0, 1.4, 0.85, 'centre_on=1\n→ white_s\nelse black_s', fc=C_SUB, fs=7.5)
    ax.text(0.8, -7.3, 'sel=9', fontsize=7, color=C_DEC, ha='center', fontweight='bold')
    ax.annotate('', xy=(0.8, -7.57), xytext=(2.6, -6.63),
                arrowprops=dict(arrowstyle='->', color=ARROW, lw=0.8))

    # other
    rect(ax, -2.8, -8.0, 1.4, 0.65, 'black_s\n(default)', fc=C_NOTE, fs=7.5)
    ax.text(-2.8, -7.4, 'other', fontsize=7, color=C_DEC, ha='center', fontweight='bold')
    ax.annotate('', xy=(-2.8, -7.68), xytext=(-1.5, -5.25),
                arrowprops=dict(arrowstyle='->', color=ARROW, lw=0.8,
                                connectionstyle='arc3,rad=0.1'))

    # bottom
    arrow(ax, 0, -9.3, 0, -10.1)
    oval(ax, 0, -10.4, 3.2, 0.65, 'active_level → dac_out', fc=C_END, fs=8.5)

    # merge arrows
    for ex, ey, _, _, _ in entries2:
        ax.annotate('', xy=(0, -9.3), xytext=(ex, ey-0.43),
                    arrowprops=dict(arrowstyle='-', color='#aaa', lw=0.7,
                                    connectionstyle='arc3,rad=0'))
    ax.annotate('', xy=(0, -9.3), xytext=(0.8, -8.43),
                arrowprops=dict(arrowstyle='-', color='#aaa', lw=0.7))
    ax.annotate('', xy=(0, -9.3), xytext=(-2.8, -8.33),
                arrowprops=dict(arrowstyle='-', color='#aaa', lw=0.7,
                                connectionstyle='arc3,rad=0.1'))
    ax.annotate('', xy=(0, -9.3), xytext=(0, -9.3),
                arrowprops=dict(arrowstyle='->', color=ARROW, lw=1.5))

    finalize(ax, fig, f'{IMG_DIR}/fc_active_mux.png', 'SDD — Active Level Multiplexer')

# =============================================================================
# MAIN
# =============================================================================
print('Generating flowchart images...')
fc_architecture()
fc_double_buffer()
fc_ball_physics()
fc_bram_write()
fc_buf_handshake()
fc_change_control()
fc_test_execution()
fc_dev_phases()
fc_active_mux()
print(f'Done — 9 flowcharts saved to {IMG_DIR}/')
