#!/usr/bin/env python3
"""Generate the PAL/NTSC Video IP Core – User & Reference Guide (Word .docx)."""

from docx import Document
from docx.shared import Pt, RGBColor, Inches, Cm
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_ALIGN_VERTICAL
from docx.oxml.ns import qn
from docx.oxml import OxmlElement
import copy, os

# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────
ACCENT   = RGBColor(0x1F, 0x49, 0x8C)   # dark blue headings
RED      = RGBColor(0xC0, 0x10, 0x10)
GREEN    = RGBColor(0x1A, 0x6B, 0x30)
MONO_FNT = 'Courier New'
BODY_FNT = 'Calibri'

def add_heading(doc, text, level=1, colour=ACCENT):
    h = doc.add_heading(text, level=level)
    h.alignment = WD_ALIGN_PARAGRAPH.LEFT
    for run in h.runs:
        run.font.color.rgb = colour
        run.font.bold = True
    return h

def add_para(doc, text='', bold=False, italic=False, size=10, colour=None, mono=False):
    p = doc.add_paragraph()
    run = p.add_run(text)
    run.bold   = bold
    run.italic = italic
    run.font.size = Pt(size)
    if colour:
        run.font.color.rgb = colour
    run.font.name = MONO_FNT if mono else BODY_FNT
    return p

def add_code(doc, lines):
    """Monospace grey box for code / file lists."""
    for line in lines:
        p = doc.add_paragraph()
        p.paragraph_format.left_indent = Cm(0.8)
        run = p.add_run(line)
        run.font.name = MONO_FNT
        run.font.size = Pt(9)
        run.font.color.rgb = RGBColor(0x30, 0x30, 0x60)
    return

def add_note(doc, text):
    p = doc.add_paragraph()
    run = p.add_run('NOTE: ')
    run.bold = True
    run.font.color.rgb = RED
    run.font.size = Pt(9)
    run2 = p.add_run(text)
    run2.font.size = Pt(9)
    run2.italic = True
    p.paragraph_format.left_indent = Cm(0.4)

def set_col_width(table, col_idx, width_cm):
    for row in table.rows:
        row.cells[col_idx].width = Cm(width_cm)

def style_table(table):
    table.style = 'Table Grid'
    table.alignment = WD_TABLE_ALIGNMENT.CENTER
    # Header row shading
    hdr = table.rows[0]
    for cell in hdr.cells:
        tc = cell._tc
        tcPr = tc.get_or_add_tcPr()
        shd = OxmlElement('w:shd')
        shd.set(qn('w:val'),   'clear')
        shd.set(qn('w:color'), 'auto')
        shd.set(qn('w:fill'),  '1F498C')
        tcPr.append(shd)
        for p in cell.paragraphs:
            for run in p.runs:
                run.font.color.rgb = RGBColor(0xFF, 0xFF, 0xFF)
                run.font.bold = True
                run.font.size = Pt(9)

def tbl_cell(cell, text, bold=False, mono=False, size=9, colour=None, align=WD_ALIGN_PARAGRAPH.LEFT):
    cell.text = ''
    p = cell.paragraphs[0]
    p.alignment = align
    run = p.add_run(text)
    run.font.size  = Pt(size)
    run.font.bold  = bold
    run.font.name  = MONO_FNT if mono else BODY_FNT
    if colour:
        run.font.color.rgb = colour

def add_waveform(doc, label, diagram_lines):
    add_para(doc, label, bold=True, size=9)
    add_code(doc, diagram_lines)

# ─────────────────────────────────────────────────────────────────────────────
# Document
# ─────────────────────────────────────────────────────────────────────────────
doc = Document()

# Page margins
for section in doc.sections:
    section.top_margin    = Cm(2.0)
    section.bottom_margin = Cm(2.0)
    section.left_margin   = Cm(2.5)
    section.right_margin  = Cm(2.0)

# Normal style tweaks
style = doc.styles['Normal']
style.font.name = BODY_FNT
style.font.size = Pt(10)

# ══════════════════════════════════════════════════════════════════════════════
# TITLE PAGE
# ══════════════════════════════════════════════════════════════════════════════
doc.add_paragraph()
t = doc.add_paragraph()
t.alignment = WD_ALIGN_PARAGRAPH.CENTER
r = t.add_run('PAL / NTSC Video IP Core')
r.font.size = Pt(28); r.bold = True; r.font.color.rgb = ACCENT

t2 = doc.add_paragraph()
t2.alignment = WD_ALIGN_PARAGRAPH.CENTER
r2 = t2.add_run('User & Reference Guide')
r2.font.size = Pt(18); r2.font.color.rgb = RGBColor(0x40, 0x40, 0x80)

doc.add_paragraph()
t3 = doc.add_paragraph()
t3.alignment = WD_ALIGN_PARAGRAPH.CENTER
r3 = t3.add_run('Repository: robokks/video-ip-core-    Branch: claude/xilinx-pal-video-ip-RIDhJ')
r3.font.size = Pt(10); r3.italic = True; r3.font.color.rgb = RGBColor(0x60, 0x60, 0x60)

doc.add_paragraph()
add_para(doc,
    'This document describes all Video IP core variants contained in the tv/ folder. '
    'It explains which VHDL files to load, the correct compile order, how to configure '
    'each option, what output to expect for every pattern selection, and reference '
    'waveform diagrams for key signals.',
    size=10)

doc.add_page_break()

# ══════════════════════════════════════════════════════════════════════════════
# 1. OVERVIEW
# ══════════════════════════════════════════════════════════════════════════════
add_heading(doc, '1. Overview', 1)
add_para(doc,
    'The IP core generates composite-video-compatible B&W test signals targeting a '
    '4-bit R-2R DAC (0–15 levels).  Three separate design variants cover different '
    'use-cases; a fourth BRAM-based layer adds host-loadable pixel patterns on top '
    'of the interlaced variant.')

doc.add_paragraph()
add_heading(doc, '1.1  DAC Output Levels', 2)
add_para(doc, 'All variants share the same 4-bit DAC coding:')

tbl = doc.add_table(rows=5, cols=3)
style_table(tbl)
headers = ['Signal Region', 'DAC Code (4-bit)', 'Approx Voltage (1 V pk)']
for i, h in enumerate(headers):
    tbl_cell(tbl.rows[0].cells[i], h)
rows_data = [
    ('Sync tip',        '0000  (0)',  '0.00 V'),
    ('Blank / pedestal','0100  (4)',  '0.27 V'),
    ('Black',          '0100  (4)',  '0.27 V  (same as blank)'),
    ('Peak white',     '1111  (15)', '1.00 V'),
]
for r, (a,b,c) in enumerate(rows_data, 1):
    tbl_cell(tbl.rows[r].cells[0], a)
    tbl_cell(tbl.rows[r].cells[1], b, mono=True)
    tbl_cell(tbl.rows[r].cells[2], c)

doc.add_paragraph()
add_heading(doc, '1.2  Clock Requirements', 2)
add_para(doc,
    'All entities accept CLK_MHZ = 10, 20, 30, or 40 MHz via a generic. An internal '
    'clock-enable divider keeps the effective pixel clock at exactly 10 MHz '
    '(100 ns/pixel).  All timing values below assume 10 MHz pixel rate.')

doc.add_paragraph()
add_heading(doc, '1.3  Horizontal Timing (common to all variants)', 2)
tbl2 = doc.add_table(rows=6, cols=4)
style_table(tbl2)
for i, h in enumerate(['Region', 'Pixels', 'Duration (µs)', 'h_cnt range']):
    tbl_cell(tbl2.rows[0].cells[i], h)
ht = [
    ('H Front Porch',  '16',  '1.6',  '0 – 15'),
    ('H Sync Pulse',   '47',  '4.7',  '16 – 62'),
    ('H Back Porch',   '57',  '5.7',  '63 – 119'),
    ('H Active',       '520', '52.0', '120 – 639'),
    ('H Total',        '640', '64.0', '0 – 639 (wrap)'),
]
for r, row in enumerate(ht, 1):
    for c, val in enumerate(row):
        tbl_cell(tbl2.rows[r].cells[c], val, mono=(c>0))

doc.add_page_break()

# ══════════════════════════════════════════════════════════════════════════════
# 2. REPOSITORY STRUCTURE
# ══════════════════════════════════════════════════════════════════════════════
add_heading(doc, '2. Repository File Structure', 1)
add_para(doc, 'Files under tv/ (compile dependencies shown with indentation):')
add_code(doc, [
    'tv/',
    '├── pal_timing.vhd               (shared – H/V counter, must compile first)',
    '├── pal_sync_gen.vhd             (shared – combinational sync decode)',
    '│',
    '├── opt1_crt50/',
    '│   ├── pal_tv_crt50_top.vhd     (Option 1 top)',
    '│   └── tb_pal_tv_crt50_top.vhd  (testbench)',
    '│',
    '├── opt2_interlaced/',
    '│   ├── pal_csync_il.vhd         (interlaced composite sync – must compile before top)',
    '│   ├── pal_tv_interlaced_top.vhd(Option 2 top)',
    '│   └── tb_pal_tv_interlaced_top.vhd',
    '│',
    '├── opt3_prog25/',
    '│   ├── pal_tv_prog25_top.vhd    (Option 3 top)',
    '│   └── tb_pal_tv_prog25_top.vhd',
    '│',
    '└── bram/',
    '    ├── pal_bram_loader.vhd      (host-side FIFO-to-BRAM loader)',
    '    ├── pal_tv_bram_top.vhd      (PAL-only BRAM top – 10 patterns)',
    '    ├── video_bram_top.vhd       (PAL+NTSC runtime selection – 10 patterns)',
    '    ├── tb_pal_tv_bram_top.vhd',
    '    ├── tb_pal_sel5.vhd',
    '    ├── tb_new_patterns.vhd',
    '    └── tb_video_bram_top.vhd',
    '',
    'tools/',
    '    └── bram_pattern_gen.html    (browser-based 1-bit BRAM pattern generator)',
])

doc.add_page_break()

# ══════════════════════════════════════════════════════════════════════════════
# 3. OPTION 1 – CRT-50
# ══════════════════════════════════════════════════════════════════════════════
add_heading(doc, '3. Option 1 – CRT-50 (50 Hz Progressive)', 1)
add_para(doc,
    'A 50 Hz non-interlaced design intended for CRT monitors. The frame has 312 total '
    'lines with 288 active video lines.  Outputs separate H-sync and V-sync signals '
    'plus a 4-bit DAC word.')

add_heading(doc, '3.1  Files to Load (compile order)', 2)
add_code(doc, [
    '1.  tv/pal_timing.vhd                      -- H/V counters',
    '2.  tv/pal_sync_gen.vhd                    -- sync decode',
    '3.  tv/opt1_crt50/pal_tv_crt50_top.vhd     -- top entity',
    '',
    'Testbench (simulation only):',
    '    tv/opt1_crt50/tb_pal_tv_crt50_top.vhd',
])
add_note(doc, 'In Vivado, add all three design files to the project sources. '
              'The testbench is for Vivado Simulator / GHDL only.')

add_heading(doc, '3.2  Entity & Generics', 2)
tbl = doc.add_table(rows=10, cols=3)
style_table(tbl)
for i, h in enumerate(['Generic', 'Default', 'Description']):
    tbl_cell(tbl.rows[0].cells[i], h)
gens = [
    ('CLK_MHZ',    '40',    'Input clock frequency (10/20/30/40 MHz)'),
    ('H_ACTIVE',   '520',   'Active pixels per line'),
    ('H_TOTAL',    '640',   'Total pixels per line (640 at 10 MHz = 64 µs)'),
    ('V_ACTIVE_L', '288',   'Active lines per frame'),
    ('V_TOTAL',    '312',   'Total lines per frame'),
    ('LEVEL_SYNC', '"0000"','DAC code for sync tip'),
    ('LEVEL_BLANK','"0100"','DAC code for blanking pedestal'),
    ('LEVEL_WHITE','"1111"','DAC code for peak white'),
    ('STRIPE_W',   '4',     'Stripe width for alternating-stripe zones (px)'),
]
for r, (a,b,c) in enumerate(gens, 1):
    tbl_cell(tbl.rows[r].cells[0], a, mono=True)
    tbl_cell(tbl.rows[r].cells[1], b, mono=True)
    tbl_cell(tbl.rows[r].cells[2], c)

doc.add_paragraph()
add_heading(doc, '3.3  Ports', 2)
add_code(doc, [
    'clk         in   std_logic                    -- system clock',
    'rst         in   std_logic                    -- synchronous reset (active high)',
    'sel         in   std_logic_vector(7 downto 0) -- pattern select (0–3 used)',
    'brightness  in   std_logic_vector(3 downto 0) -- white level  (default 1111)',
    'black_lvl   in   std_logic_vector(3 downto 0) -- black level  (default 0100)',
    '',
    'dac_out     out  std_logic_vector(3 downto 0) -- 4-bit DAC',
    'hsync_o     out  std_logic                    -- H sync  (active high, ~4.7 µs)',
    'vsync_o     out  std_logic                    -- V sync  (active high, ~3 lines)',
    'active_o    out  std_logic                    -- 1 during active picture',
    'blank_o     out  std_logic                    -- 1 outside active (not sync)',
])

add_heading(doc, '3.4  Pattern Selections', 2)
add_para(doc, 'Set sel[7:0] to the value below before de-asserting rst:')

tbl = doc.add_table(rows=5, cols=4)
style_table(tbl)
for i, h in enumerate(['sel (hex)', 'Pattern Name', 'Description', 'Expected DAC Output']):
    tbl_cell(tbl.rows[0].cells[i], h)
pats = [
    ('0x00', 'Vertical Bars',       '8 vertical zones (65 px each): STRIPE | WHITE | STRIPE | WHITE | STRIPE | WHITE | STRIPE | BLACK', 'Repeating white/stripe blocks 65 px wide across 520 px'),
    ('0x01', 'Horizontal Bars',     '8 horizontal zones (36 lines each): alternating white and stripe rows within each 288-line active area', 'Repeating white/stripe blocks 36 lines tall'),
    ('0x02', 'Horizontal Gradient', '10 vertical grey steps, each 52 px wide, stepping from black (black_lvl) to white (brightness)', '10 discrete grey steps, darkest left, brightest right'),
    ('0x03', 'Vertical Gradient',   '10 horizontal grey steps, each ~29 lines, stepping from black to white top-to-bottom', '10 discrete grey steps, darkest top, brightest bottom'),
]
for r, (a,b,c,d) in enumerate(pats, 1):
    tbl_cell(tbl.rows[r].cells[0], a, mono=True)
    tbl_cell(tbl.rows[r].cells[1], b, bold=True)
    tbl_cell(tbl.rows[r].cells[2], c)
    tbl_cell(tbl.rows[r].cells[3], d)

add_heading(doc, '3.5  Output Waveforms', 2)
add_para(doc, 'Single horizontal line timing (one 64 µs line):')
add_waveform(doc, 'H-sync and DAC output – one line (sel=0, vertical bars shown):', [
    'Time:    0µs        1.6µs   6.3µs  12.0µs    64.0µs',
    '         |<-FRONT->|<-SYNC->|<-BACK->|<------ ACTIVE 520px ------>|',
    '',
    'hsync_o: ___________|‾‾‾‾‾‾‾|___________________________________|  ',
    'dac_out:  0100        0000    0100   |zone0|zone1|zone2|...|zone7|  ',
    '                                     W/S   W/S   W/S        BLK   ',
    '',
    'W/S = alternating White(1111) and Stripe pixels; BLK = Black(0100)',
])
doc.add_paragraph()
add_para(doc, 'V-sync region (frame boundary, CRT-50):')
add_waveform(doc, 'V-sync timing (opt1 – 50 Hz progressive):', [
    'Line:  307 308 309   310 311 312/0   1    2  ...  23   24 ...  311',
    '       |   |   |     |   |   |       |    |        |    |        |',
    'vsync: ___|‾‾‾|‾‾‾|‾‾‾|___|________________________________...____',
    '       active  sync  active  blank back-porch     active picture',
    '',
    'vsync_o = HIGH for 3 lines (V_SYNC_L = 3)',
    'active_o = HIGH only during lines 24–311 (288 active lines)',
])

doc.add_page_break()

# ══════════════════════════════════════════════════════════════════════════════
# 4. OPTION 2 – INTERLACED PAL
# ══════════════════════════════════════════════════════════════════════════════
add_heading(doc, '4. Option 2 – Interlaced PAL 625/50', 1)
add_para(doc,
    'Standards-compliant interlaced PAL: 625 total lines, 50 Hz field rate, 25 Hz frame rate. '
    'Two fields (F1 and F2) each with 288 active lines.  Composite sync includes proper '
    'equalising and broad-sync pulses for correct interlace lock on TV sets.')

add_heading(doc, '4.1  Files to Load (compile order)', 2)
add_code(doc, [
    '1.  tv/pal_timing.vhd                              -- H/V counters',
    '2.  tv/opt2_interlaced/pal_csync_il.vhd            -- interlaced composite sync',
    '3.  tv/opt2_interlaced/pal_tv_interlaced_top.vhd   -- top entity',
    '',
    'Testbench:',
    '    tv/opt2_interlaced/tb_pal_tv_interlaced_top.vhd',
])
add_note(doc, 'pal_csync_il.vhd MUST be compiled before pal_tv_interlaced_top.vhd '
              'because the top instantiates it as a component.')

add_heading(doc, '4.2  Key Timing Differences vs Option 1', 2)
tbl = doc.add_table(rows=7, cols=3)
style_table(tbl)
for i, h in enumerate(['Parameter', 'Opt 1 CRT-50', 'Opt 2 Interlaced PAL']):
    tbl_cell(tbl.rows[0].cells[i], h)
diffs = [
    ('V_TOTAL',      '312 lines',    '625 lines (half-line interleave)'),
    ('Field rate',   '50 Hz',        '50 Hz  (2 fields/frame, 25 Hz frame)'),
    ('Active lines', '288 / frame',  '576 / frame  (288 per field)'),
    ('Sync type',    'Sep. H+V sync','Composite sync with equalising pulses'),
    ('V-sync pulse', '3-line broad', '5 broad + 5 pre/post equalising half-lines'),
    ('Output port',  'hsync_o + vsync_o', 'csync_o only (composite)'),
]
for r, (a,b,c) in enumerate(diffs, 1):
    tbl_cell(tbl.rows[r].cells[0], a, bold=True)
    tbl_cell(tbl.rows[r].cells[1], b, mono=True)
    tbl_cell(tbl.rows[r].cells[2], c)

add_heading(doc, '4.3  Ports', 2)
add_code(doc, [
    'clk         in   std_logic',
    'rst         in   std_logic',
    'sel         in   std_logic_vector(7 downto 0)',
    'brightness  in   std_logic_vector(3 downto 0)',
    'black_lvl   in   std_logic_vector(3 downto 0)',
    '',
    'dac_out     out  std_logic_vector(3 downto 0)',
    'hsync_o     out  std_logic   -- composite sync (same signal as csync, labelled hsync)',
    'vsync_o     out  std_logic   -- field indicator: 0 = Field-1, 1 = Field-2',
    'active_o    out  std_logic',
    'blank_o     out  std_logic',
])

add_heading(doc, '4.4  Pattern Selections', 2)
add_para(doc, 'Same four patterns as Option 1 (sel = 0x00–0x03). Vertical bar zone count '
              'is 8 × 65 px = 520 px. Horizontal bar zone count is 8 zones over 288 lines.')

add_heading(doc, '4.5  Interlaced Field Waveform', 2)
add_waveform(doc, 'PAL 625/50 field structure (50 Hz, two fields per frame):', [
    'Field 1 (F1)                         Field 2 (F2)',
    '|<----- 312.5 lines ----->|           |<----- 312.5 lines ----->|',
    '',
    'Line: 0  5  10  24        311 312    336        623 625/0',
    '      |  |   |   |          |   |      |           |   |',
    'csync: __|‾|__|‾|___________| ½ line  __|‾|________|   (repeat)',
    '       eq  broad  post eq    offset    eq  broad   post eq',
    '',
    'active_o: __________|‾‾‾‾‾‾‾‾|_______|‾‾‾‾‾‾‾‾‾‾‾‾‾|___',
    '                   L24      L311    L336           L623',
    '',
    'field_o:  00000000000000000000000001111111111111111111110000...',
    '          (F1=0)                   (F2=1)',
    '',
    'Screen rows:  F1 lines → even rows 0,2,4..574',
    '              F2 lines → odd  rows 1,3,5..575',
])

doc.add_page_break()

# ══════════════════════════════════════════════════════════════════════════════
# 5. OPTION 3 – PROGRESSIVE 25 Hz
# ══════════════════════════════════════════════════════════════════════════════
add_heading(doc, '5. Option 3 – Progressive 25 Hz (Reference)', 1)
add_para(doc,
    'A 25 Hz progressive design using the full 625-line frame for 576 active lines. '
    'Intended as a reference / simulation baseline. Many TVs will NOT lock at 25 Hz '
    '(they expect 50 Hz fields); use Option 2 for real TV output.')

add_heading(doc, '5.1  Files to Load (compile order)', 2)
add_code(doc, [
    '1.  tv/pal_timing.vhd',
    '2.  tv/pal_sync_gen.vhd',
    '3.  tv/opt3_prog25/pal_tv_prog25_top.vhd',
    '',
    'Testbench:',
    '    tv/opt3_prog25/tb_pal_tv_prog25_top.vhd',
])

add_heading(doc, '5.2  Key Differences vs Option 2', 2)
tbl = doc.add_table(rows=5, cols=3)
style_table(tbl)
for i, h in enumerate(['Parameter', 'Opt 2 Interlaced', 'Opt 3 Prog-25']):
    tbl_cell(tbl.rows[0].cells[i], h)
diffs = [
    ('Frame rate',    '25 Hz (50 Hz fields)','25 Hz (no interlace)'),
    ('Active lines',  '576 (288×2 fields)',  '576 in one progressive frame'),
    ('V-sync pulse',  '5 broad + equalising','5-line broad only (simplified)'),
    ('TV lock',       'Yes – standards PAL', 'May not lock on all TVs'),
]
for r, (a,b,c) in enumerate(diffs, 1):
    tbl_cell(tbl.rows[r].cells[0], a, bold=True)
    tbl_cell(tbl.rows[r].cells[1], b)
    tbl_cell(tbl.rows[r].cells[2], c, colour=RED)

add_heading(doc, '5.3  Pattern Selections (sel 0–3)', 2)
add_para(doc, 'Identical to Option 1 but with 576 active lines instead of 288:')
tbl = doc.add_table(rows=5, cols=3)
style_table(tbl)
for i, h in enumerate(['sel', 'Pattern', 'Zone Size']):
    tbl_cell(tbl.rows[0].cells[i], h)
for r, (a,b,c) in enumerate([
    ('0x00','Vertical Bars',    '8 zones × 65 px = 520 px'),
    ('0x01','Horizontal Bars',  '8 zones × 72 lines = 576 lines'),
    ('0x02','H-Gradient',       '10 steps × 52 px = 520 px'),
    ('0x03','V-Gradient',       '10 steps × ~58 lines = ~576 lines'),
], 1):
    tbl_cell(tbl.rows[r].cells[0], a, mono=True)
    tbl_cell(tbl.rows[r].cells[1], b, bold=True)
    tbl_cell(tbl.rows[r].cells[2], c, mono=True)

doc.add_page_break()

# ══════════════════════════════════════════════════════════════════════════════
# 6. PAL TV BRAM TOP (PAL-only)
# ══════════════════════════════════════════════════════════════════════════════
add_heading(doc, '6. BRAM Option A – pal_tv_bram_top (PAL-only)', 1)
add_para(doc,
    'Extends Option 2 (interlaced PAL) with an internal 1-bit BRAM that the host '
    'can write pixel data into.  Adds 6 extra pattern selections on top of the '
    'standard four bar/gradient patterns, giving 10 total.  The BRAM holds one '
    'full PAL frame (520 × 576 = 299 520 pixels).')

add_heading(doc, '6.1  Files to Load (compile order)', 2)
add_code(doc, [
    '1.  tv/pal_timing.vhd',
    '2.  tv/opt2_interlaced/pal_csync_il.vhd',
    '3.  tv/bram/pal_tv_bram_top.vhd',
    '',
    '(Optional) BRAM loader:',
    '    tv/bram/pal_bram_loader.vhd    -- add if using FIFO-to-BRAM host loading',
    '',
    'Testbenches:',
    '    tv/bram/tb_pal_tv_bram_top.vhd',
    '    tv/bram/tb_pal_sel5.vhd',
    '    tv/bram/tb_new_patterns.vhd',
])

add_heading(doc, '6.2  All Ports', 2)
add_code(doc, [
    '-- Clock / Reset',
    'clk           in  std_logic',
    'rst           in  std_logic',
    '',
    '-- Pattern select & levels',
    'sel           in  std_logic_vector(7 downto 0)',
    'brightness    in  std_logic_vector(3 downto 0)   -- peak-white DAC code (def "1111")',
    'black_lvl     in  std_logic_vector(3 downto 0)   -- black/blank DAC code (def "0100")',
    '',
    '-- BRAM write port (host side; write at any time)',
    'bram_wr_en    in  std_logic                      -- pulse 1 clk to write one pixel',
    'bram_wr_addr  in  std_logic_vector(18 downto 0)  -- pixel address 0..BRAM_DEPTH-1',
    'bram_wr_data  in  std_logic                      -- 1 = brightness, 0 = black_lvl',
    'bram_len      in  std_logic_vector(18 downto 0)  -- valid pixels in BRAM (wrap addr)',
    '',
    '-- Ball animation control (sel=5)',
    'ball_spd_h    in  std_logic_vector(3 downto 0)   -- H speed 1-15 px/frame (def "0011")',
    'ball_spd_v    in  std_logic_vector(3 downto 0)   -- V speed 1-15 rows/frame(def "0010")',
    'ball_w_i      in  std_logic_vector(9 downto 0)   -- ball width  px (def 60)',
    'ball_h_i      in  std_logic_vector(9 downto 0)   -- ball height rows (def 50)',
    '',
    '-- Crosshatch spacing (sel=8)',
    'cross_h_i     in  std_logic_vector(9 downto 0)   -- H grid pitch px   (def 52)',
    'cross_v_i     in  std_logic_vector(9 downto 0)   -- V grid pitch lines (def 58)',
    '',
    '-- Video outputs',
    'dac_out       out std_logic_vector(3 downto 0)',
    'csync_o       out std_logic   -- composite sync (H+V merged)',
    'line_sync_o   out std_logic   -- H sync only (suppressed during vsync)',
    'frame_sync_o  out std_logic   -- vsync region only',
    'field_o       out std_logic   -- 0=Field1, 1=Field2',
    'active_o      out std_logic',
    'blank_o       out std_logic',
])

add_heading(doc, '6.3  All 10 Pattern Selections', 2)
tbl = doc.add_table(rows=11, cols=5)
style_table(tbl)
for i, h in enumerate(['sel', 'Name', 'Description', 'Runtime Control Ports', 'Expected DAC Output']):
    tbl_cell(tbl.rows[0].cells[i], h)
all_pats = [
    ('0x00','Vertical Bars',
     '8 zones (65 px) cycling: Stripe | White | Stripe | White | Stripe | White | Stripe | Black',
     'brightness, black_lvl',
     'White / stripe blocks 65 px wide; repeats horizontally'),
    ('0x01','Horizontal Bars',
     '8 horizontal zones per field; alternating white and stripe rows',
     'brightness, black_lvl',
     'Alternating white/stripe bands across the 576 active rows'),
    ('0x02','H-Gradient',
     '10 vertical grey steps left-to-right, 52 px each',
     'brightness, black_lvl',
     'dark_lvl → brightness in 10 discrete steps left to right'),
    ('0x03','V-Gradient',
     '10 horizontal grey steps top-to-bottom',
     'brightness, black_lvl',
     'dark_lvl → brightness in 10 steps top to bottom'),
    ('0x04','BRAM Pixel',
     'Pixel data read from internal 1-bit BRAM. 0 = black_lvl, 1 = brightness. '
     'Address wraps at bram_len.',
     'bram_wr_en, bram_wr_addr, bram_wr_data, bram_len',
     'Arbitrary bitmap loaded by host; interlace-correct row routing'),
    ('0x05','Bouncing Ball',
     'White rectangle bouncing elastically inside the frame. Size and speed '
     'controlled by ball_w_i/ball_h_i/ball_spd_h/ball_spd_v.',
     'ball_w_i, ball_h_i, ball_spd_h, ball_spd_v',
     'White rectangle (default 60×50 px) on black, moves 3 px/frame H, 2 rows/frame V'),
    ('0x06','Full White',
     'All 520×576 active pixels at peak white. Useful for DAC peak-white calibration.',
     '(none)',
     'dac_out = brightness for every active pixel'),
    ('0x07','Full Black',
     'All active pixels at black level. Useful for black-level / offset calibration.',
     '(none)',
     'dac_out = black_lvl for every active pixel'),
    ('0x08','Crosshatch Grid',
     'Horizontal and vertical grid lines. Spacing set by cross_h_i (pixels) and '
     'cross_v_i (lines). Grid line width = 1 pixel.',
     'cross_h_i, cross_v_i',
     'White grid on black; default 52×58 px spacing = 10×10 grid on 520×576 screen'),
    ('0x09','Centre Cross',
     'Single vertical line at H_ACTIVE/2 = 260 and single horizontal line at '
     'screen row 288. Useful for centering and geometry checks.',
     '(none)',
     'White "+" mark at screen centre; all other pixels black'),
]
for r, (a,b,c,d,e) in enumerate(all_pats, 1):
    tbl_cell(tbl.rows[r].cells[0], a, mono=True)
    tbl_cell(tbl.rows[r].cells[1], b, bold=True)
    tbl_cell(tbl.rows[r].cells[2], c)
    tbl_cell(tbl.rows[r].cells[3], d, mono=True, size=8)
    tbl_cell(tbl.rows[r].cells[4], e)

add_heading(doc, '6.4  BRAM Address Layout (sel = 4)', 2)
add_para(doc,
    'Pixels are stored in natural image order (row 0 first, then row 1, etc.). '
    'The hardware routes each row to the correct interlaced field automatically.')
add_code(doc, [
    'BRAM address layout (stride = H_ACTIVE = 520):',
    '',
    '  addr       0 ..     519   image row  0  (F1 line 0,  screen row  0)',
    '  addr     520 ..    1039   image row  1  (F2 line 0,  screen row  1)',
    '  addr    1040 ..    1559   image row  2  (F1 line 1,  screen row  2)',
    '  addr    1560 ..    2079   image row  3  (F2 line 1,  screen row  3)',
    '  ...',
    '  addr k*1040 ..k*1040+519  image row 2k  (F1 line k)',
    '  addr k*1040+520..k*1040+1039  image row 2k+1 (F2 line k)',
    '  ...',
    '  addr 299000..299519       image row 575 (F2 line 287, screen row 575)',
    '',
    'bram_len shortcuts:',
    '  520      = single row, repeated on every active line',
    '  1040     = two rows (one even/odd pair), repeated',
    '  299520   = full PAL frame  (520 × 576)',
])

add_heading(doc, '6.5  Waveforms – sel=4 BRAM', 2)
add_waveform(doc, 'BRAM write then read-back on an active line:', [
    '(Host writes pixels 0..519 for row 0 into addr 0..519 before video starts)',
    '',
    'clk:       _|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_',
    'bram_wr_en: ‾|___|‾|___|‾|___|  ... 520 pulses       _____',
    'bram_wr_addr:0    1    2  ...',
    '',
    '(During video line 0, Field 1:)',
    'active_o:  __________________|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾|__',
    'dac_out:         0100(blank)  |pix0|pix1|pix2|...|pix519|',
    '                              (0=0100, 1=1111)            ',
])

add_heading(doc, '6.6  Waveforms – sel=5 Bouncing Ball', 2)
add_waveform(doc, 'Ball position over two frames (spd_h=3, spd_v=2, w=60, h=50):', [
    'Frame 0: ball at (0,0)   → pixels 0-59 of rows 0-49 = WHITE',
    'Frame 1: ball at (3,2)   → pixels 3-62 of rows 2-51 = WHITE',
    'Frame 2: ball at (6,4)   → pixels 6-65 of rows 4-53 = WHITE',
    '',
    'Active line (row 0, frame 0):',
    'dac_out: 0100 0100 | 1111×60px | 0100×460px | ... ',
    '         blank     | ball pix  | background |',
    '',
    'After reset, ball_x=0, ball_y=0; velocity=(+spd_h, +spd_v).',
    'Ball reflects elastically off all four screen edges.',
])

doc.add_page_break()

# ══════════════════════════════════════════════════════════════════════════════
# 7. VIDEO BRAM TOP (PAL + NTSC)
# ══════════════════════════════════════════════════════════════════════════════
add_heading(doc, '7. BRAM Option B – video_bram_top (PAL + NTSC)', 1)
add_para(doc,
    'Drop-in superset of pal_tv_bram_top. A single rtl_mode input selects between '
    'PAL 625/50 and NTSC 525/60 at runtime.  Same 10 pattern selections; zone heights '
    'adapt automatically to the selected format.  Use this when a single bitstream '
    'must support both standards.')

add_heading(doc, '7.1  Files to Load', 2)
add_code(doc, [
    '1.  tv/pal_timing.vhd',
    '2.  tv/opt2_interlaced/pal_csync_il.vhd',
    '3.  tv/bram/video_bram_top.vhd',
    '',
    'Testbench:',
    '    tv/bram/tb_video_bram_top.vhd',
])

add_heading(doc, '7.2  Extra Port vs pal_tv_bram_top', 2)
add_code(doc, [
    'ntsc_mode  in  std_logic   -- 0 = PAL 625/50  |  1 = NTSC 525/60',
])
add_para(doc,
    'All other ports are identical to pal_tv_bram_top. '
    'ntsc_mode can be tied to a GPIO or register bit.')

add_heading(doc, '7.3  Format-Dependent Timing', 2)
tbl = doc.add_table(rows=10, cols=3)
style_table(tbl)
for i, h in enumerate(['Parameter', 'PAL (ntsc_mode=0)', 'NTSC (ntsc_mode=1)']):
    tbl_cell(tbl.rows[0].cells[i], h)
fmt_diff = [
    ('H_TOTAL',      '640  (64.0 µs)', '636  (63.6 µs)'),
    ('H_BACK',       '57',             '53'),
    ('H_ACT_S',      '120',            '116'),
    ('V_TOTAL',      '625',            '525'),
    ('V_ACT_S_F1',   '24',             '21'),
    ('V_ACT_E_F1',   '311 (288 lines)','260 (240 lines)'),
    ('V_ACT_S_F2',   '336',            '283'),
    ('V_ACT_E_F2',   '623',            '522'),
    ('V_ACTIVE total','576',           '480'),
]
for r, (a,b,c) in enumerate(fmt_diff, 1):
    tbl_cell(tbl.rows[r].cells[0], a, mono=True)
    tbl_cell(tbl.rows[r].cells[1], b, mono=True)
    tbl_cell(tbl.rows[r].cells[2], c, mono=True)

doc.add_page_break()

# ══════════════════════════════════════════════════════════════════════════════
# 8. BRAM LOADER
# ══════════════════════════════════════════════════════════════════════════════
add_heading(doc, '8. BRAM Loader – pal_bram_loader', 1)
add_para(doc,
    'A companion module that transfers pixel data from a FIFO into the BRAM write '
    'port of pal_tv_bram_top or video_bram_top. It counts from address 0 to '
    'TOTAL_PX-1, stalls when the FIFO is empty, and asserts done when the full frame '
    'has been loaded.')

add_heading(doc, '8.1  Files to Load', 2)
add_code(doc, [
    '(Requires pal_tv_bram_top or video_bram_top to be compiled first)',
    '    tv/bram/pal_bram_loader.vhd',
    '',
    'Testbench:',
    '    tv/bram/tb_pal_bram_loader.vhd',
])

add_heading(doc, '8.2  Ports', 2)
add_code(doc, [
    'clk           in  std_logic',
    'rst           in  std_logic',
    'start         in  std_logic    -- rising edge begins/re-triggers a load',
    'fifo_data     in  std_logic    -- 1-bit pixel from FIFO',
    'fifo_empty    in  std_logic    -- loader stalls when HIGH',
    '',
    'done          out std_logic    -- pulsed 1 clk when TOTAL_PX pixels written',
    'busy          out std_logic    -- HIGH during active load',
    'fifo_rd       out std_logic    -- FIFO read enable',
    'bram_wr_en    out std_logic    -- connect to pal_tv_bram_top.bram_wr_en',
    'bram_wr_addr  out std_logic_vector(ADDR_BITS-1 downto 0)',
    'bram_wr_data  out std_logic    -- connect to pal_tv_bram_top.bram_wr_data',
])

add_heading(doc, '8.3  Load Sequence', 2)
add_waveform(doc, 'BRAM loader handshake:', [
    'clk:      _|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_',
    'rst:      ‾‾|__|_____________________________________________',
    'start:    ___|‾|__________________________________________',
    'fifo_empty:_____________________|‾‾‾|_______________________  (stall once)',
    'busy:     ____|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾|____',
    'fifo_rd:  ____|‾|_|‾|_|‾|_|‾|__|‾|_|‾|_|‾|_|‾|_|‾|_|___',
    'bram_wr_en:___|‾|_|‾|_|‾|_|‾|__|‾|_|‾|_|‾|_|‾|_|‾|_|___',
    'bram_addr: 0   1  2  3       3  4  5  6 ...  299519',
    'done:      ____________________________________________|‾|__',
    '',
    'Re-trigger: assert start again after done to reload frame.',
])

doc.add_page_break()

# ══════════════════════════════════════════════════════════════════════════════
# 9. HTML PATTERN GENERATOR TOOL
# ══════════════════════════════════════════════════════════════════════════════
add_heading(doc, '9. BRAM Pattern Generator Tool (HTML)', 1)
add_para(doc,
    'The file tools/bram_pattern_gen.html is a browser-based graphical tool for '
    'creating and exporting test patterns compatible with the BRAM write port.')

add_heading(doc, '9.1  How to Use', 2)
add_code(doc, [
    '1. Open tools/bram_pattern_gen.html in any modern browser (Chrome, Firefox, Edge).',
    '   No web server required – double-click the file.',
    '',
    '2. Select format preset: PAL 625/50 (520×576) pre-configures the canvas size.',
    '',
    '3. Choose a pattern type and configure its parameters.',
    '',
    '4. Add text overlays if needed (Text Overlay section → + Add Text).',
    '',
    '5. Export:',
    '   • "Save as PNG"            – full-colour preview image for documentation.',
    '   • "Save 1-bit Binary"      – raw binary file, MSB-first, row stride = W px.',
    '                                 Load this file into BRAM via the loader or DMA.',
    '   • "Copy VHDL comment"      – clipboard snippet with hex preview of first 64 B.',
    '',
    '6. Load the binary into BRAM:',
    '   a) Use pal_bram_loader: send binary file bytes through the FIFO one bit at a time.',
    '   b) Or directly: loop over the binary, extracting bits MSB-first and pulsing',
    '      bram_wr_en for each bit with the corresponding bram_wr_addr.',
])

add_heading(doc, '9.2  Available Pattern Types', 2)
tbl = doc.add_table(rows=12, cols=3)
style_table(tbl)
for i, h in enumerate(['Pattern', 'Key Controls', 'Use Case']):
    tbl_cell(tbl.rows[0].cells[i], h)
html_pats = [
    ('Solid White / Black',    'Foreground/Background colour', 'Full-screen DAC calibration'),
    ('Vertical Stripes',       'Stripe width (px)',            'H frequency response test'),
    ('Horizontal Stripes',     'Stripe width (px)',            'V frequency response test'),
    ('Checkerboard',           'Cell width × height (px)',     'Corner-frequency spatial test'),
    ('V-Gradient (H steps)',   'Number of steps',              'Grey-scale linearity'),
    ('H-Gradient (V steps)',   'Number of steps',              'Grey-scale linearity'),
    ('Crosshatch Grid',        'H spacing, V spacing, line W', 'Geometry / convergence'),
    ('Centre Cross',           '(none)',                       'Screen centring'),
    ('Circle / Ellipse',       'Centre X/Y, Radius X/Y, Fill', 'Aspect ratio check'),
    ('Colour Zones (V)',       'Zone count, per-zone colour',  'Custom test card'),
    ('Multi-Zone Pattern',     'Direction (V/H), per-zone:',   'Complex test sequences'),
    ('',                       '  pattern, size, stripe W,',   ''),
    ('',                       '  per-zone FG/BG colour',      ''),
]
for r, (a,b,c) in enumerate(html_pats[:11], 1):
    tbl_cell(tbl.rows[r].cells[0], a, bold=bool(a))
    tbl_cell(tbl.rows[r].cells[1], b, mono=True)
    tbl_cell(tbl.rows[r].cells[2], c)

doc.add_page_break()

# ══════════════════════════════════════════════════════════════════════════════
# 10. SIMULATION (GHDL)
# ══════════════════════════════════════════════════════════════════════════════
add_heading(doc, '10. Simulation with GHDL', 1)
add_para(doc, 'All testbenches are compatible with GHDL --std=08. Example commands:')

add_heading(doc, 'Option 1 – CRT-50', 2)
add_code(doc, [
    'ghdl -a --std=08 tv/pal_timing.vhd tv/pal_sync_gen.vhd \\',
    '     tv/opt1_crt50/pal_tv_crt50_top.vhd \\',
    '     tv/opt1_crt50/tb_pal_tv_crt50_top.vhd',
    'ghdl -e --std=08 tb_pal_tv_crt50_top',
    'ghdl -r --std=08 tb_pal_tv_crt50_top --assert-level=error',
])
add_heading(doc, 'Option 2 – Interlaced', 2)
add_code(doc, [
    'ghdl -a --std=08 tv/pal_timing.vhd \\',
    '     tv/opt2_interlaced/pal_csync_il.vhd \\',
    '     tv/opt2_interlaced/pal_tv_interlaced_top.vhd \\',
    '     tv/opt2_interlaced/tb_pal_tv_interlaced_top.vhd',
    'ghdl -e --std=08 tb_pal_tv_interlaced_top',
    'ghdl -r --std=08 tb_pal_tv_interlaced_top --assert-level=error',
])
add_heading(doc, 'BRAM Top (all tests)', 2)
add_code(doc, [
    'ghdl -a --std=08 tv/pal_timing.vhd \\',
    '     tv/opt2_interlaced/pal_csync_il.vhd \\',
    '     tv/bram/pal_tv_bram_top.vhd \\',
    '     tv/bram/video_bram_top.vhd \\',
    '     tv/bram/tb_pal_tv_bram_top.vhd \\',
    '     tv/bram/tb_pal_sel5.vhd \\',
    '     tv/bram/tb_new_patterns.vhd \\',
    '     tv/bram/tb_video_bram_top.vhd',
    '',
    'for tb in tb_pal_tv_bram_top tb_pal_sel5 tb_new_patterns tb_video_bram_top; do',
    '  ghdl -e --std=08 $tb',
    '  ghdl -r --std=08 $tb --assert-level=error',
    'done',
])

doc.add_page_break()

# ══════════════════════════════════════════════════════════════════════════════
# 11. VIVADO INTEGRATION
# ══════════════════════════════════════════════════════════════════════════════
add_heading(doc, '11. Vivado / Xilinx Integration', 1)
add_para(doc,
    'All VHDL files are pure-RTL, technology-agnostic (no primitives). '
    'The BRAM is inferred via a Vivado ram_style="block" attribute already present '
    'in pal_tv_bram_top.vhd.')

add_heading(doc, '11.1  Recommended BRAM Generic for Vivado', 2)
add_code(doc, [
    '-- Artix-7 / Kintex-7: set BRAM_DEPTH to a power-of-2 for efficient packing',
    '-- PAL full frame needs 299520 bits → 10 × BRAM36',
    'BRAM_DEPTH => 524288,   -- 2^19, covers 299520 + spare',
])

add_heading(doc, '11.2  Typical Constraint Snippet (XDC)', 2)
add_code(doc, [
    '# 40 MHz clock',
    'create_clock -period 25.000 -name clk [get_ports clk]',
    '',
    '# DAC output pins  (R-2R ladder on JA or JB PMOD)',
    'set_property PACKAGE_PIN  V1   [get_ports {dac_out[3]}]',
    'set_property PACKAGE_PIN  U1   [get_ports {dac_out[2]}]',
    'set_property PACKAGE_PIN  T1   [get_ports {dac_out[1]}]',
    'set_property PACKAGE_PIN  R1   [get_ports {dac_out[0]}]',
    'set_property IOSTANDARD LVCMOS33 [get_ports {dac_out[*]}]',
    '',
    '# Composite sync out',
    'set_property PACKAGE_PIN  W1   [get_ports csync_o]',
    'set_property IOSTANDARD LVCMOS33 [get_ports csync_o]',
])

doc.add_page_break()

# ══════════════════════════════════════════════════════════════════════════════
# 12. QUICK-START SUMMARY
# ══════════════════════════════════════════════════════════════════════════════
add_heading(doc, '12. Quick-Start Summary', 1)
add_para(doc, 'Choose the right variant:')

tbl = doc.add_table(rows=6, cols=5)
style_table(tbl)
for i, h in enumerate(['Use Case', 'Top Entity', 'Files Required', 'sel Range', 'Key Output']):
    tbl_cell(tbl.rows[0].cells[i], h)
summary = [
    ('CRT monitor, simple',
     'pal_tv_crt50_top',
     'pal_timing\npal_sync_gen\npal_tv_crt50_top',
     '0–3',
     'dac_out + hsync_o + vsync_o'),
    ('Real TV / interlaced',
     'pal_tv_interlaced_top',
     'pal_timing\npal_csync_il\npal_tv_interlaced_top',
     '0–3',
     'dac_out + csync_o'),
    ('Reference / simulation',
     'pal_tv_prog25_top',
     'pal_timing\npal_sync_gen\npal_tv_prog25_top',
     '0–3',
     'dac_out + hsync_o + vsync_o'),
    ('PAL + custom BRAM image',
     'pal_tv_bram_top',
     'pal_timing\npal_csync_il\npal_tv_bram_top',
     '0–9',
     'dac_out + csync_o (10 patterns)'),
    ('PAL + NTSC switchable',
     'video_bram_top',
     'pal_timing\npal_csync_il\nvideo_bram_top',
     '0–9',
     'dac_out + csync_o + ntsc_mode port'),
]
for r, (a,b,c,d,e) in enumerate(summary, 1):
    tbl_cell(tbl.rows[r].cells[0], a)
    tbl_cell(tbl.rows[r].cells[1], b, mono=True, size=8)
    tbl_cell(tbl.rows[r].cells[2], c, mono=True, size=8)
    tbl_cell(tbl.rows[r].cells[3], d, mono=True)
    tbl_cell(tbl.rows[r].cells[4], e, mono=True, size=8)

doc.add_paragraph()
add_heading(doc, '12.1  Configuration Order (step-by-step)', 2)
steps = [
    ('1', 'Load VHDL files',        'Compile in dependency order shown in Section 2 / each option section.'),
    ('2', 'Set CLK_MHZ generic',    'Match your board clock: 10, 20, 30, or 40 MHz.'),
    ('3', 'Connect DAC',            'Wire dac_out[3:0] to 4-bit R-2R DAC (MSB = dac_out[3]).'),
    ('4', 'Connect sync',           'For TV output: use csync_o only (connect to composite video shield).'),
    ('5', 'Set levels',             'brightness = "1111" (1 V), black_lvl = "0100" (0.3 V) — defaults are correct.'),
    ('6', 'De-assert rst',          'Hold rst = 1 for ≥ 2 clock cycles, then rst = 0.'),
    ('7', 'Select pattern',         'Write sel[7:0] = desired pattern code (see Section 6.3 table).'),
    ('8', '(BRAM) Load image',      'Pulse bram_wr_en for each pixel, set bram_len = total pixels written.'),
    ('9', '(Ball) Set ball size',   'Write ball_w_i, ball_h_i, ball_spd_h, ball_spd_v before or after reset.'),
    ('10','(Crosshatch) Set pitch', 'Write cross_h_i (default 52) and cross_v_i (default 58) for sel=8.'),
]
tbl3 = doc.add_table(rows=len(steps)+1, cols=3)
style_table(tbl3)
for i, h in enumerate(['Step', 'Action', 'Detail']):
    tbl_cell(tbl3.rows[0].cells[i], h)
for r, (a,b,c) in enumerate(steps, 1):
    tbl_cell(tbl3.rows[r].cells[0], a, bold=True, align=WD_ALIGN_PARAGRAPH.CENTER)
    tbl_cell(tbl3.rows[r].cells[1], b, bold=True)
    tbl_cell(tbl3.rows[r].cells[2], c)

# ─────────────────────────────────────────────────────────────────────────────
# Save
# ─────────────────────────────────────────────────────────────────────────────
out = '/home/user/video-ip-core-/tools/PAL_NTSC_Video_IP_User_Guide.docx'
doc.save(out)
print(f'Saved: {out}')
print(f'Size:  {os.path.getsize(out):,} bytes')
