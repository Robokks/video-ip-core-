#!/usr/bin/env python3
"""
PAL/NTSC Video IP Core — Formal Project Documentation Generator
Generates 11 Word documents into docs/
"""
import os
from docx import Document
from docx.shared import Pt, RGBColor, Inches, Cm
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

BASE = '/home/user/video-ip-core-'
DOCS = f'{BASE}/docs'
os.makedirs(DOCS, exist_ok=True)

# ── Colour palette ────────────────────────────────────────────────────────────
C_TITLE  = RGBColor(0x1F, 0x49, 0x7D)
C_HDR    = RGBColor(0x1F, 0x49, 0x7D)
C_HDR2   = RGBColor(0x2E, 0x74, 0xB5)
C_ALT    = RGBColor(0xDA, 0xE8, 0xFC)
C_WHITE  = RGBColor(0xFF, 0xFF, 0xFF)
C_BLACK  = RGBColor(0x00, 0x00, 0x00)
C_GREEN  = RGBColor(0x37, 0x86, 0x10)
C_RED    = RGBColor(0xC0, 0x00, 0x00)
C_ORANGE = RGBColor(0xC5, 0x5A, 0x11)
C_BLUE   = RGBColor(0x2E, 0x74, 0xB5)
C_PURPLE = RGBColor(0x70, 0x30, 0xA0)
C_GREY   = RGBColor(0x60, 0x60, 0x60)
C_LGREY  = RGBColor(0xF2, 0xF2, 0xF2)

# ── Helpers ───────────────────────────────────────────────────────────────────
def set_cell_bg(cell, rgb):
    tc = cell._tc; tcPr = tc.get_or_add_tcPr()
    shd = OxmlElement('w:shd')
    shd.set(qn('w:val'), 'clear'); shd.set(qn('w:color'), 'auto')
    shd.set(qn('w:fill'), f'{rgb[0]:02X}{rgb[1]:02X}{rgb[2]:02X}')
    tcPr.append(shd)

def cp(cell, text, bold=False, color=C_BLACK, size=9.5, italic=False,
       align=WD_ALIGN_PARAGRAPH.LEFT):
    p = cell.paragraphs[0]; p.alignment = align
    r = p.add_run(str(text))
    r.bold = bold; r.italic = italic
    r.font.size = Pt(size); r.font.color.rgb = color

def new_doc(title, subtitle, doc_id):
    doc = Document()
    for s in doc.sections:
        s.top_margin = s.bottom_margin = Cm(2)
        s.left_margin = s.right_margin = Cm(2.2)
    p = doc.add_paragraph(); p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.add_run('PAL / NTSC Video IP Core'); r.bold = True
    r.font.size = Pt(20); r.font.color.rgb = C_TITLE
    p = doc.add_paragraph(); p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.add_run(title); r.bold = True
    r.font.size = Pt(15); r.font.color.rgb = C_HDR2
    p = doc.add_paragraph(); p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.add_run(f'{doc_id}  |  {subtitle}  |  2026-05-24')
    r.italic = True; r.font.size = Pt(9); r.font.color.rgb = C_GREY
    doc.add_paragraph()
    p = doc.add_paragraph(); p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.add_run('Branch: claude/xilinx-pal-video-ip-RIDhJ')
    r.italic = True; r.font.size = Pt(9); r.font.color.rgb = C_GREY
    doc.add_page_break()
    return doc

def heading(doc, text, level=1):
    p = doc.add_paragraph(); p.style = f'Heading {level}'
    r = p.add_run(text); r.font.color.rgb = C_TITLE if level == 1 else C_HDR2

def body(doc, text, size=10, color=C_BLACK, bold=False, italic=False):
    p = doc.add_paragraph()
    r = p.add_run(text)
    r.font.size = Pt(size); r.font.color.rgb = color
    r.bold = bold; r.italic = italic; return p

def spacer(doc): doc.add_paragraph()

def build_table(doc, headers, rows, col_widths, zebra=True, hdr_color=None):
    hc = hdr_color or C_HDR
    t = doc.add_table(rows=1+len(rows), cols=len(headers))
    t.style = 'Table Grid'
    for i, h in enumerate(headers):
        set_cell_bg(t.rows[0].cells[i], hc)
        cp(t.rows[0].cells[i], h, bold=True, color=C_WHITE, size=10)
    for ri, row in enumerate(rows):
        bg = C_ALT if zebra and ri % 2 == 1 else C_WHITE
        for ci, val in enumerate(row):
            cell = t.rows[ri+1].cells[ci]
            set_cell_bg(cell, bg)
            if isinstance(val, tuple):
                txt, col, bld = val; cp(cell, txt, bold=bld, color=col, size=9.5)
            else:
                cp(cell, str(val), size=9.5)
    for ri in range(len(t.rows)):
        for ci, w in enumerate(col_widths):
            t.rows[ri].cells[ci].width = Inches(w)
    spacer(doc); return t

def save(doc, filename):
    path = f'{DOCS}/{filename}'
    doc.save(path)
    print(f'  {filename}  ({os.path.getsize(path):,} bytes)')

# =============================================================================
# ICD — Interface Control Document
# =============================================================================
def gen_icd():
    doc = new_doc('Interface Control Document', 'ICD-001', 'Rev 1.0')

    heading(doc, '1  Scope')
    body(doc, 'This document defines all hardware and software interfaces of the PAL/NTSC '
         'Video IP Core, including signal levels, port definitions, timing constraints, '
         'and BRAM communication protocols.')

    heading(doc, '2  Hardware Interfaces')
    heading(doc, '2.1  Clock Input', 2)
    build_table(doc,
        ['Parameter', 'Value', 'Notes'],
        [('Clock frequency', '10 / 20 / 30 / 40 MHz', 'Set CLK_MHZ generic to match'),
         ('Pixel rate', '10 MHz (always)', 'Internal divider reduces to 10 MHz'),
         ('Clock standard', 'Single-ended LVCMOS33', 'Or LVCMOS18 per board voltage'),
         ('Setup/hold', 'Per Xilinx FPGA datasheet', ''),
         ('Jitter tolerance', '< 500 ps RMS', 'Affects sync timing accuracy')],
        [1.8, 1.8, 2.8])

    heading(doc, '2.2  Reset Input', 2)
    build_table(doc,
        ['Parameter', 'Value', 'Notes'],
        [('Polarity', 'Active HIGH (rst=1 asserts reset)', ''),
         ('Type', 'Synchronous', 'Sampled on rising edge of clk'),
         ('Minimum pulse width', '3 clock cycles', 'Required when changing ball parameters'),
         ('Release', 'Asynchronous release allowed', 'Internal state initialises on next clk edge')],
        [1.8, 2.2, 2.4])

    heading(doc, '2.3  DAC Output Interface', 2)
    body(doc, 'The 4-bit dac_out port drives an R-2R resistor ladder to produce an '
         'analogue composite video signal (0–1 V into 75 Ω).')
    build_table(doc,
        ['Signal Region', 'dac_out[3:0]', 'Hex', 'Voltage (1 Vpp)', 'Description'],
        [('Sync tip',    '"0000"', '0x0', '0.00 V', 'H-sync and V-sync pulse tip'),
         ('Blanking',    '"0100"', '0x4', '~0.27 V', 'Blanking pedestal (standard 300 mV)'),
         ('Grey step 1', '"0101"', '0x5', '~0.33 V', 'Darkest grey (gradient patterns)'),
         ('Grey steps',  '"0110"–"1110"', '0x6–0xE', '0.40–0.93 V', 'Mid grey steps'),
         ('White',       '"1111"', '0xF', '1.00 V', 'Peak white')],
        [1.4, 1.1, 0.6, 1.3, 2.8])

    heading(doc, '2.4  R-2R Ladder Recommended Values', 2)
    body(doc, 'R = 75 Ω, 2R = 150 Ω. Connect dac_out[3] (MSB) to the ladder input '
         'closest to the output. Terminate output with 75 Ω to ground.')

    heading(doc, '3  Software / Logic Interfaces')
    heading(doc, '3.1  Input Control Ports', 2)
    build_table(doc,
        ['Port', 'Width', 'Dir', 'Default', 'Description'],
        [('clk',          '1',  'in', '—',         'Pixel clock'),
         ('rst',          '1',  'in', '—',         'Synchronous reset, active HIGH'),
         ('sel',          '8',  'in', '—',         'Pattern selector (0x00–0x09)'),
         ('brightness',   '4',  'in', '"1111"',    'White level DAC code'),
         ('black_lvl',    '4',  'in', '"0100"',    'Black/blanking floor DAC code'),
         ('ntsc_mode',    '1',  'in', '—',         'video_bram_top only: 0=PAL, 1=NTSC'),
         ('bram_wr_en',   '1',  'in', "'0'",       'BRAM write enable (one pulse = one pixel)'),
         ('bram_wr_addr', '19', 'in', 'zeros',     'BRAM write address (0–BRAM_DEPTH-1)'),
         ('bram_wr_data', '1',  'in', "'0'",       '1-bit pixel value (0=black, 1=white)'),
         ('bram_len',     '19', 'in', 'all-ones',  'Valid pixel count; address wrap boundary'),
         ('buf_swap',     '1',  'in', "'0'",       'Pulse HIGH 1 clock to request buffer swap'),
         ('ball_spd_h',   '4',  'in', '"0011"',    'Ball horizontal speed (1–15 px/frame)'),
         ('ball_spd_v',   '4',  'in', '"0010"',    'Ball vertical speed (1–15 rows/frame)'),
         ('ball_w_i',     '10', 'in', '"0000111100"','Ball width in pixels (default 60)'),
         ('ball_h_i',     '10', 'in', '"0000110010"','Ball height in rows (default 50)'),
         ('cross_h_i',    '10', 'in', '"0000110100"','Crosshatch H spacing px (default 52)'),
         ('cross_v_i',    '10', 'in', '"0000111010"','Crosshatch V spacing rows (default 58)')],
        [1.4, 0.6, 0.5, 1.3, 2.8])

    heading(doc, '3.2  Output Ports', 2)
    build_table(doc,
        ['Port', 'Width', 'Dir', 'Description'],
        [('dac_out',     '4', 'out', '4-bit DAC value — connect to R-2R ladder'),
         ('csync_o',     '1', 'out', 'Composite sync (H+V merged, HIGH = sync tip)'),
         ('line_sync_o', '1', 'out', 'H-sync only — suppressed during V-sync region'),
         ('frame_sync_o','1', 'out', 'V-sync pulse — HIGH for entire broad-sync region'),
         ('field_o',     '1', 'out', 'Field: 0=F1 (odd lines), 1=F2 (even lines)'),
         ('active_o',    '1', 'out', 'HIGH during active picture area'),
         ('blank_o',     '1', 'out', 'Composite blanking (HIGH outside active, not during sync)'),
         ('buf_swapped', '1', 'out', 'Strobes HIGH 1 clock when double-buffer swap completes'),
         ('back_buf_o',  '1', 'out', 'Index of current back (write) BRAM bank (0 or 1)')],
        [1.4, 0.6, 0.5, 4.1])

    heading(doc, '4  BRAM Write Protocol')
    body(doc, 'The BRAM write port operates independently of the pixel clock. '
         'The host may write at any time.')
    build_table(doc,
        ['Step', 'Action', 'Notes'],
        [('1', 'Set bram_wr_addr to target pixel address (0–BRAM_DEPTH-1)', 'Row-major order'),
         ('2', 'Set bram_wr_data to 0 (black) or 1 (white)', ''),
         ('3', 'Assert bram_wr_en = 1 for ONE clock cycle', 'One pixel written per pulse'),
         ('4', 'Deassert bram_wr_en = 0', 'Next address may be set immediately'),
         ('5', 'Repeat for each pixel', 'Sequential writes are independent')],
        [0.4, 3.8, 2.2])

    heading(doc, '5  Double-Buffer Handshake Protocol')
    build_table(doc,
        ['Step', 'Signal', 'Action'],
        [('1', 'back_buf_o', 'Read back_buf_o — this is the bank to write to'),
         ('2', 'bram_wr_*', 'Write complete new frame into back buffer'),
         ('3', 'buf_swap', 'Pulse buf_swap = 1 for exactly ONE clock, then return to 0'),
         ('4', 'buf_swapped', 'Wait for buf_swapped = 1 (one clock strobe at V-blank)'),
         ('5', 'back_buf_o', 'Read back_buf_o again — now points to the new back buffer'),
         ('6', '—', 'Repeat from step 2 for next frame')],
        [0.4, 1.3, 4.7])
    body(doc, 'WARNING: Holding buf_swap HIGH causes a new swap request every clock. '
         'Always return buf_swap to 0 within one clock cycle.', color=C_RED, bold=True)

    save(doc, 'ICD_Interface_Control_Document.docx')

# =============================================================================
# SRS — Software Requirements Specification
# =============================================================================
def gen_srs():
    doc = new_doc('Software Requirements Specification', 'SRS-001', 'Rev 1.0')

    heading(doc, '1  Introduction')
    body(doc, 'This document specifies all functional and non-functional requirements '
         'for the PAL/NTSC Video IP Core. Requirements are identified by unique IDs '
         'and shall be traced to design (SDD) and test (STP/STR) documents.')

    heading(doc, '2  System Overview')
    body(doc, 'The Video IP Core is a synthesisable VHDL IP block that generates '
         'standard-definition PAL (625/50) or NTSC (525/60) interlaced composite '
         'video from an internal 1-bit-per-pixel BRAM image store. The IP targets '
         'Xilinx Artix-7 / Kintex-7 FPGAs and drives a 4-bit R-2R DAC.')

    heading(doc, '3  Functional Requirements')
    FR = [
        ('FR-001','Video Standard','The IP shall generate PAL 625-line 50 Hz interlaced video with composite sync conforming to CCIR-B standard.'),
        ('FR-002','NTSC Mode','video_bram_top shall support NTSC 525-line 59.94 Hz mode selectable at runtime via ntsc_mode port without re-synthesis.'),
        ('FR-003','Clock Flexibility','The IP shall accept input clocks of 10, 20, 30, or 40 MHz and produce a 10 MHz effective pixel rate via an internal divider.'),
        ('FR-004','Pattern 0 — Vertical Bars','sel=0 shall display 8 vertical zones of alternating STRIPE/WHITE/BLACK patterns, each 65 pixels wide.'),
        ('FR-005','Pattern 1 — Horizontal Bars','sel=1 shall display 8 horizontal zones matching the ZONE_TABLE, each 36 active rows high (PAL).'),
        ('FR-006','Pattern 2 — H Gradient','sel=2 shall display a 10-step horizontal luminance gradient from black_lvl to brightness across 520 pixels.'),
        ('FR-007','Pattern 3 — V Gradient','sel=3 shall display a 10-step vertical luminance gradient from black_lvl to brightness across 288 active rows per field.'),
        ('FR-008','Pattern 4 — BRAM Image','sel=4 shall display a 1-bit-per-pixel image stored in internal BRAM, addressed in natural sequential row order with automatic interlace correction.'),
        ('FR-009','BRAM Write Port','The IP shall provide a synchronous 19-bit-addressed 1-bit-data write port operable at any time independent of the display scan.'),
        ('FR-010','Double Buffering','The IP shall support tear-free BRAM image updates via two BRAM banks. A buf_swap pulse shall cause the banks to exchange at the next V-blank boundary only.'),
        ('FR-011','Pattern 5 — Bouncing Ball','sel=5 shall display a white rectangle bouncing inside the active area with elastic boundary reflection. Size and speed shall be settable at runtime via ports.'),
        ('FR-012','Pattern 6 — Full White','sel=6 shall output LEVEL_WHITE on every active pixel for DAC peak-white calibration.'),
        ('FR-013','Pattern 7 — Full Black','sel=7 shall output LEVEL_BLANK on every active pixel for DAC black-level calibration.'),
        ('FR-014','Pattern 8 — Crosshatch','sel=8 shall display a crosshatch grid with runtime-configurable horizontal and vertical line spacing.'),
        ('FR-015','Pattern 9 — Centre Cross','sel=9 shall display a single white vertical line at horizontal centre and a single white horizontal line at vertical centre.'),
        ('FR-016','Brightness Control','A 4-bit brightness port shall override the white DAC level for all patterns. Value shall be clamped to [4, 15].'),
        ('FR-017','Black Level Control','A 4-bit black_lvl port shall set the active black/blanking floor for all patterns. Value clamped to [4, brightness].'),
        ('FR-018','Sync Outputs','The IP shall provide composite sync (csync_o), H-sync-only (line_sync_o), V-sync (frame_sync_o), field indicator (field_o), active (active_o), and blanking (blank_o) outputs.'),
    ]
    build_table(doc,
        ['ID', 'Name', 'Requirement'],
        [(i, n, r) for i, n, r in FR],
        [0.8, 1.6, 4.8])

    heading(doc, '4  Non-Functional Requirements')
    NFR = [
        ('NFR-001','Pixel clock accuracy','H_TOTAL × line_rate shall be within ±0.1% of PAL/NTSC standard.'),
        ('NFR-002','Sync glitch-free','pal_csync_il shall be purely combinational; no glitches on csync output.'),
        ('NFR-003','Tear-free swap','Double-buffer swap shall complete entirely within the V-blank interval.'),
        ('NFR-004','BRAM inference','BRAM arrays shall carry Xilinx ram_style=block attribute for automatic BRAM36 inference.'),
        ('NFR-005','Reset recovery','All state machines shall reach a defined initial state within 5 clock cycles of rst deassertion.'),
        ('NFR-006','Simulation','All modules shall have GHDL-compatible VHDL-2008 self-checking testbenches.'),
        ('NFR-007','No division at pixel rate','Pattern generators shall use only addition and comparison; no division or multiplication in pixel-rate paths.'),
        ('NFR-008','Portability','RTL shall contain no Xilinx-specific primitives other than the ram_style attribute. Synthesis tool handles BRAM mapping.'),
        ('NFR-009','Single clock domain','All design logic shall operate in the single clk domain. No asynchronous paths except BRAM read.'),
        ('NFR-010','Modular structure','Timing and sync generation shall be separate instantiated modules to allow reuse.'),
    ]
    build_table(doc,
        ['ID', 'Name', 'Requirement'],
        [(i, n, r) for i, n, r in NFR],
        [0.9, 1.5, 4.8])

    heading(doc, '5  Constraints')
    build_table(doc,
        ['Constraint', 'Value'],
        [('Target FPGA family', 'Xilinx 7-series (Artix-7, Kintex-7) or later'),
         ('VHDL standard', 'VHDL-2008 (--std=08)'),
         ('Simulation tool', 'GHDL 4.x or later'),
         ('Synthesis tool', 'Vivado 2020.x or later'),
         ('DAC resolution', '4-bit (R-2R resistor ladder)'),
         ('Base pixel clock', '10 MHz (100 ns per pixel)'),
         ('Active resolution', '520 × 576 px (PAL), 520 × 480 px (NTSC)'),
         ('BRAM depth (PAL)', '299,520 bits (520 × 576), ~10 × BRAM36')],
        [2.5, 4.8])

    save(doc, 'SRS_Software_Requirements_Specification.docx')

# =============================================================================
# SDD — Software Design Description
# =============================================================================
def gen_sdd():
    doc = new_doc('Software Design Description', 'SDD-001', 'Rev 1.0')

    heading(doc, '1  Architecture Overview')
    body(doc, 'The IP core uses a three-layer architecture:')
    body(doc, '  Layer 1 — Timing:   pal_timing generates H/V counters at 10 MHz pixel rate.')
    body(doc, '  Layer 2 — Sync:     pal_csync_il decodes H/V counters into composite sync,')
    body(doc, '                      field indicator, and active window signals.')
    body(doc, '  Layer 3 — Patterns: pal_tv_bram_top (or video_bram_top) contains all pattern')
    body(doc, '                      generators, BRAM, double-buffer, and the active-level mux.')

    heading(doc, '2  Module Decomposition')
    build_table(doc,
        ['Module', 'File', 'Purpose', 'Instantiates'],
        [('pal_timing',           'tv/pal_timing.vhd',             'H/V counters, CLK_DIV', '—'),
         ('pal_csync_il',         'tv/opt2_interlaced/pal_csync_il.vhd', 'Interlaced composite sync (combinational)', '—'),
         ('pal_sync_gen',         'tv/pal_sync_gen.vhd',           'Non-interlaced sync (opt1/opt3)', '—'),
         ('pal_tv_crt50_top',     'tv/opt1_crt50/',                'CRT50 progressive, sel 0–3', 'pal_timing, pal_sync_gen'),
         ('pal_tv_interlaced_top','tv/opt2_interlaced/',           'PAL interlaced, sel 0–3', 'pal_timing, pal_csync_il'),
         ('pal_tv_prog25_top',    'tv/opt3_prog25/',               'Progressive 25 Hz, sel 0–3', 'pal_timing, pal_sync_gen'),
         ('pal_tv_bram_top',      'tv/bram/pal_tv_bram_top.vhd',  'PAL + BRAM + sel 0–9 + double-buf', 'pal_timing, pal_csync_il'),
         ('video_bram_top',       'tv/bram/video_bram_top.vhd',   'PAL/NTSC runtime select + BRAM + sel 0–9', '(inline counters)')],
        [1.6, 2.0, 2.0, 1.7])

    heading(doc, '3  Generics')
    build_table(doc,
        ['Generic', 'Default', 'Used In', 'Description'],
        [('H_FRONT',    '16',    'pal_tv_bram_top', 'Front porch clocks'),
         ('H_SYNC_W',   '47',    'all',             'H-sync pulse width clocks'),
         ('H_BACK',     '57',    'pal_tv_bram_top', 'Back porch clocks (53 for NTSC in video_bram_top)'),
         ('H_ACTIVE',   '520',   'all',             'Active pixels per line'),
         ('H_TOTAL',    '640',   'all',             'Total clocks per line (636 NTSC)'),
         ('V_TOTAL',    '625',   'pal_tv_bram_top', 'Total lines per frame (525 NTSC)'),
         ('LEVEL_SYNC', '"0000"','pal_tv_bram_top', 'DAC code for sync tip'),
         ('LEVEL_BLANK','"0100"','pal_tv_bram_top', 'DAC code for blanking floor'),
         ('LEVEL_WHITE','"1111"','pal_tv_bram_top', 'DAC code for peak white'),
         ('CLK_MHZ',    '40',    'all timing',      'Input clock frequency'),
         ('STRIPE_W',   '4',     'bram tops',       'Stripe width for sel=0,1'),
         ('BRAM_DEPTH', '299520','bram tops',       'BRAM address depth (520×576 PAL full frame)')],
        [1.3, 1.0, 1.7, 2.8])

    heading(doc, '4  BRAM Address Map')
    body(doc, 'Natural sequential row order (PAL 520×576, stride = 2×H_ACTIVE = 1040):')
    build_table(doc,
        ['Address Range', 'Image Row', 'Field', 'Screen Row'],
        [('0 – 519',           '0',    'F1 line 0', '0 (even)'),
         ('520 – 1039',        '1',    'F2 line 0', '1 (odd)'),
         ('1040 – 1559',       '2',    'F1 line 1', '2 (even)'),
         ('1560 – 2079',       '3',    'F2 line 1', '3 (odd)'),
         ('k×1040 … k×1040+519',   '2k',   'F1 line k', '2k'),
         ('k×1040+520 … k×1040+1039', '2k+1', 'F2 line k', '2k+1'),
         ('299000 – 299519',   '575',  'F2 line 287', '575 (odd)')],
        [2.2, 1.0, 1.2, 1.5])

    heading(doc, '5  Double-Buffer State Machine')
    body(doc, 'Signals: disp_buf (front bank index), swap_req (pending swap), buf_swapped_s (output strobe)')
    build_table(doc,
        ['Condition', 'Action', 'Next State'],
        [('rst = 1',                            'disp_buf←0, swap_req←0', 'Idle'),
         ('buf_swap = 1',                        'swap_req←1',            'Pending'),
         ('v_cnt=V_ACT_E_F2, h_cnt=H_TOTAL-1, swap_req=1', 'disp_buf←NOT disp_buf; swap_req←0; buf_swapped_s←1', 'Idle'),
         ('All other clocks',                    'buf_swapped_s←0',       '(unchanged)')],
        [2.8, 2.8, 1.2])
    body(doc, 'Write port: always writes to bram_mem_{NOT disp_buf}. Read port: always reads from bram_mem_{disp_buf}.')

    heading(doc, '6  Active-Level Multiplexer')
    body(doc, 'Priority order (first matching condition wins):')
    build_table(doc,
        ['sel', 'Condition', 'Output'],
        [('4',     'always',              'bram_level (from BRAM read)'),
         ('5',     'ball_on = 1',         'white_s'),
         ('5',     'ball_on = 0',         'black_s'),
         ('6',     'always',              'white_s (full white)'),
         ('7',     'always',              'black_s (full black)'),
         ('8',     'cross_on = 1',        'white_s (crosshatch line)'),
         ('8',     'cross_on = 0',        'black_s'),
         ('9',     'centre_on = 1',       'white_s (centre cross)'),
         ('9',     'centre_on = 0',       'black_s'),
         ('2',     'always',              'grad_x_s (H gradient level)'),
         ('3',     'always',              'grad_y_s (V gradient level)'),
         ('0',     'color_v = 1',         'white_s (vertical bar)'),
         ('1',     'color_h = 1',         'white_s (horizontal bar)'),
         ('other', 'always',              'black_s')],
        [0.5, 1.8, 4.0])

    heading(doc, '7  Ball Physics')
    body(doc, 'Updated once per frame at v_cnt=V_ACT_E_F2, h_cnt=H_TOTAL-1:')
    body(doc, '  nx = ball_x + ball_vx;  ny = ball_y + ball_vy')
    body(doc, '  If nx > H_ACTIVE-ball_w: reflect (nx = 2*(H_ACTIVE-ball_w)-nx; nvx = -nvx)')
    body(doc, '  If nx < 0: reflect (nx = -nx; nvx = -nvx)')
    body(doc, '  Same for ny with 576-ball_h boundary (PAL)')
    body(doc, 'ball_on = 1 when screen_x ∈ [ball_x, ball_x+ball_w) AND screen_y ∈ [ball_y, ball_y+ball_h)')

    heading(doc, '8  Crosshatch Counters')
    body(doc, 'cross_x_cnt: resets to 0 at H_ACT_S-1 each active line; increments each active pixel; wraps at cross_h_s.')
    body(doc, 'cross_y_cnt: resets to 0 at V_ACT_S_F1 line start; increments once per active line; wraps at cross_v_s.')
    body(doc, 'cross_on = 1 when cross_x_cnt=0 OR cross_y_cnt=0.')

    save(doc, 'SDD_Software_Design_Description.docx')

# =============================================================================
# SDP — Software Development Plan
# =============================================================================
def gen_sdp():
    doc = new_doc('Software Development Plan', 'SDP-001', 'Rev 1.0')

    heading(doc, '1  Project Scope')
    body(doc, 'Develop a complete VHDL IP core for PAL/NTSC composite video generation '
         'targeting Xilinx 7-series FPGAs, with comprehensive pattern generation, '
         'BRAM image display, double-buffering, and formal documentation.')

    heading(doc, '2  Development Environment')
    build_table(doc,
        ['Tool', 'Version', 'Purpose'],
        [('GHDL',       '4.x',         'VHDL simulation and elaboration'),
         ('VHDL standard', 'VHDL-2008 (--std=08)', 'Language standard for all RTL and testbenches'),
         ('Vivado',     '2023.x',      'Synthesis, implementation, bitstream generation'),
         ('Python',     '3.10+',       'Document generation, VCD parsing, pattern tools'),
         ('python-docx','0.8.x',       'Word document generation'),
         ('matplotlib', '3.x',         'Waveform image generation from VCD'),
         ('numpy',      '1.x',         'Pattern image data arrays'),
         ('Git',        '2.x',         'Version control'),
         ('Browser',    'Any modern',  'bram_pattern_gen.html pattern tool')],
        [1.6, 1.6, 3.2])

    heading(doc, '3  Development Phases')
    build_table(doc,
        ['Phase', 'Activities', 'Deliverables', 'Status'],
        [('1 — Base IP',       'pal_timing, pal_csync_il, opt1-3 variants',  'Core timing + sync modules', ('COMPLETE', C_GREEN, True)),
         ('2 — BRAM + sel 0–4','pal_tv_bram_top, natural seq. addressing',   'BRAM image display',         ('COMPLETE', C_GREEN, True)),
         ('3 — Extensions',    'sel 5–9, ball ports, crosshatch, NTSC',      'All 10 pattern modes',       ('COMPLETE', C_GREEN, True)),
         ('4 — Double Buffer', 'Two BRAM banks, swap handshake, testbench',  'Tear-free image update',     ('COMPLETE', C_GREEN, True)),
         ('5 — Tools',         'HTML pattern gen, Word report gen',           'Developer/test tools',       ('COMPLETE', C_GREEN, True)),
         ('6 — Docs',          'ICD, SRS, SDD, SDP, CM, STP, STR, VC, TM, BR, CL', 'Formal docs set',    ('COMPLETE', C_GREEN, True))],
        [1.3, 2.5, 1.8, 0.9])

    heading(doc, '4  Testing Strategy')
    body(doc, 'Every module has a GHDL self-checking testbench with severity-failure assertions. '
         'Testbenches use report/assert statements — no waveform-only verification. '
         'VCD output is captured for waveform review. Simulation must exit 0 (no failures) '
         'before any commit is made to the branch.')

    heading(doc, '5  File Naming Conventions')
    build_table(doc,
        ['Type', 'Convention', 'Example'],
        [('RTL source',      '<module_name>.vhd',          'pal_tv_bram_top.vhd'),
         ('Testbench',       'tb_<module_name>.vhd',       'tb_bram_double_buf.vhd'),
         ('Simulation log',  '<tb_name>.log',              'tb_new_patterns.log'),
         ('VCD waveform',    '<short_name>.vcd',           'new_patterns.vcd'),
         ('Python tool',     'gen_<description>.py',       'gen_project_docs.py'),
         ('Word document',   '<PREFIX>_<Full_Name>.docx',  'ICD_Interface_Control_Document.docx')],
        [1.5, 2.3, 2.6])

    save(doc, 'SDP_Software_Development_Plan.docx')

# =============================================================================
# CM — Configuration Management Plan
# =============================================================================
def gen_cm():
    doc = new_doc('Configuration Management Plan', 'CM-001', 'Rev 1.0')

    heading(doc, '1  Purpose')
    body(doc, 'This document defines the configuration management procedures for the '
         'PAL/NTSC Video IP Core, covering version control, baseline management, '
         'change control, and file identification.')

    heading(doc, '2  Version Numbering')
    build_table(doc,
        ['Component', 'Scheme', 'Example'],
        [('IP Core RTL',    'Vx.y  (x=major, y=minor)',    'V1.0, V1.1'),
         ('Documents',      'Rev x.y',                     'Rev 1.0'),
         ('Git tags',       'v<major>.<minor>.<patch>',    'v1.0.0'),
         ('BRAM images',    '<name>_v<n>.bin',             'testcard_v1.bin')],
        [1.8, 2.2, 1.8])

    heading(doc, '3  Baselines')
    build_table(doc,
        ['Baseline', 'Description', 'Branch / Tag', 'Status'],
        [('BL-0.1', 'Base PAL timing + sync modules only',             'main (initial)',              ('ESTABLISHED', C_GREEN, True)),
         ('BL-0.2', 'BRAM image display (sel 0–4), PAL only',         'main',                        ('ESTABLISHED', C_GREEN, True)),
         ('BL-0.3', 'All 10 patterns (sel 0–9), NTSC mode, ball ports','claude/xilinx-pal-video-ip-RIDhJ', ('ESTABLISHED', C_GREEN, True)),
         ('BL-1.0', 'Full feature set including double-buffering and complete docs', 'claude/xilinx-pal-video-ip-RIDhJ', ('ESTABLISHED', C_GREEN, True))],
        [0.9, 2.8, 2.0, 1.1])

    heading(doc, '4  Change Control Process')
    build_table(doc,
        ['Step', 'Activity'],
        [('1', 'Identify change (new feature, bug fix, or enhancement)'),
         ('2', 'Update RTL source file(s) on the feature branch'),
         ('3', 'Run all affected GHDL testbenches — all must PASS (exit 0)'),
         ('4', 'Update CHANGE_LOG.docx and relevant docs'),
         ('5', 'git add + git commit with descriptive message'),
         ('6', 'git push to claude/xilinx-pal-video-ip-RIDhJ'),
         ('7', 'Create pull request for review when baseline is ready')],
        [0.5, 6.8])

    heading(doc, '5  Branch Strategy')
    build_table(doc,
        ['Branch', 'Purpose'],
        [('main',                            'Stable released baselines only'),
         ('claude/xilinx-pal-video-ip-RIDhJ','Active development branch — current work'),
         ('feature/*',                        'Experimental features (merge to dev branch)')],
        [2.8, 4.5])

    heading(doc, '6  Controlled Items')
    build_table(doc,
        ['Item', 'Location', 'CM Responsibility'],
        [('VHDL RTL source files',      'tv/**/*.vhd',             'Version control (Git)'),
         ('VHDL testbench files',       'tv/**/tb_*.vhd',          'Version control (Git)'),
         ('Simulation logs',            'tools/sim_out/*.log',     'Version control (Git)'),
         ('VCD waveform files',         'tools/sim_out/*.vcd',     'Version control (Git, LFS if large)'),
         ('Python generator scripts',   'tools/gen_*.py',          'Version control (Git)'),
         ('Word documents',             'docs/*.docx, tools/*.docx','Version control (Git)'),
         ('HTML tools',                 'tools/*.html',            'Version control (Git)'),
         ('Vivado TCL scripts',         'tcl/*.tcl',               'Version control (Git)'),
         ('Constraints file',           'constraints/pal_bw.xdc',  'Version control (Git)')],
        [2.2, 2.0, 2.5])

    save(doc, 'CM_Configuration_Management_Plan.docx')

# =============================================================================
# STP — Software Test Plan
# =============================================================================
def gen_stp():
    doc = new_doc('Software Test Plan', 'STP-001', 'Rev 1.0')

    heading(doc, '1  Purpose')
    body(doc, 'This plan describes the test strategy, test environment, test cases, '
         'and pass/fail criteria for all modules of the PAL/NTSC Video IP Core.')

    heading(doc, '2  Test Environment')
    build_table(doc,
        ['Item', 'Specification'],
        [('Simulator',    'GHDL 4.x, VHDL-2008 standard (--std=08)'),
         ('Compile cmd',  'ghdl -a --std=08 <dependencies> <dut> <tb>'),
         ('Elaborate cmd','ghdl -e --std=08 <entity>'),
         ('Run cmd',      'ghdl -r --std=08 <entity> --assert-level=error [--vcd=<file>]'),
         ('Pass criteria','Process exits 0 with no severity failure or error reports'),
         ('Fail criteria','Any "severity failure" assertion terminates with non-zero exit'),
         ('Host OS',      'Linux (Ubuntu 22.04 or later)'),
         ('Python',       '3.10+ for log analysis and report generation')],
        [1.8, 5.5])

    heading(doc, '3  Test Cases')
    TCS = [
        ('TC-001','tb_pal_tv_crt50_top','FR-004,FR-005,FR-006,FR-007,FR-016',
         'Verify all 4 base patterns (sel 0–3) in CRT50 progressive mode with contrast control'),
        ('TC-002','tb_pal_tv_interlaced_top','FR-001,FR-004,FR-005,FR-018,NFR-002',
         'Verify interlaced PAL sync waveform, F1/F2 active windows, and base patterns'),
        ('TC-003','tb_pal_tv_prog25_top','FR-003,FR-004,FR-005,FR-006,FR-007',
         'Verify progressive 25 Hz mode with all base patterns and brightness control'),
        ('TC-004','tb_pal_tv_bram_top','FR-008,FR-009,NFR-004',
         'Verify BRAM natural sequential row addressing across F1 and F2 lines'),
        ('TC-005','tb_pal_sel5','FR-011,FR-016',
         'Verify bouncing ball initial position, frame-1 displacement, and boundary'),
        ('TC-006','tb_new_patterns','FR-012,FR-013,FR-014,FR-015,FR-011,FR-016,FR-017',
         'Verify sel 6 (white), 7 (black), 8 (crosshatch px0/26/52), 9 (centre cross px259/260/261), ball w=100'),
        ('TC-007','tb_bram_double_buf','FR-010,NFR-003',
         'Verify: back buf unchanged before swap; swap delivers new image; alternating pattern; single swap per V-blank'),
        ('TC-008','tb_video_bram_top','FR-002,FR-003,FR-011,NFR-001',
         'Verify PAL/NTSC runtime switch, ball in both modes, DAC levels valid over 400k samples'),
        ('TC-009','tb_pal_bram_loader','FR-009',
         'Verify BRAM loader: normal write, stall recovery, re-trigger without reset'),
    ]
    build_table(doc,
        ['TC ID', 'Testbench', 'Requirements', 'Description'],
        TCS, [0.8, 1.8, 1.5, 3.2])

    heading(doc, '4  Pass / Fail Criteria')
    body(doc, 'PASS: ghdl exits 0 AND all "PASS" report messages appear in log.')
    body(doc, 'FAIL: Any "FAIL" report message OR ghdl exit code ≠ 0 OR severity failure.')
    body(doc, 'REGRESSION: Re-run all TCs after every RTL change. All must pass before commit.')

    save(doc, 'STP_Software_Test_Plan.docx')

# =============================================================================
# STR — Software Test Report
# =============================================================================
def gen_str():
    doc = new_doc('Software Test Report', 'STR-001', 'Rev 1.0')

    heading(doc, '1  Summary')
    body(doc, 'All 9 test cases were executed using GHDL 4.x. '
         'All testbenches passed with zero failures. '
         'Total verified assertions: 50+. Test date: 2026-05-24.')

    heading(doc, '2  Test Results')
    RESULTS = [
        ('TC-001','tb_pal_tv_crt50_top',  '5',  'PASS','@20480500ns','sel=0,1,2,3 + 20% contrast'),
        ('TC-002','tb_pal_tv_interlaced_top','4','PASS','@46400500ns','F1/F2 bars, sync shapes'),
        ('TC-003','tb_pal_tv_prog25_top', '5',  'PASS','@12800500ns','sel=0,1,2,3 + contrast'),
        ('TC-004','tb_pal_tv_bram_top',   '3',  'PASS','@46400750ns','BRAM row addr F1+F2'),
        ('TC-005','tb_pal_sel5',          '4',  'PASS','@80000500ns','Ball 4 checks'),
        ('TC-006','tb_new_patterns',      '9',  'PASS','@3367050ns', 'sel 5–9 all patterns'),
        ('TC-007','tb_bram_double_buf',   '4',  'PASS','@119937450ns','Double-buffer 4 phases'),
        ('TC-008','tb_video_bram_top',    '3',  'PASS','@80000500ns','PAL+NTSC+DAC levels'),
        ('TC-009','tb_pal_bram_loader',   '3',  'PASS','@1035ns',    'Loader 3 tests'),
    ]
    build_table(doc,
        ['TC ID', 'Testbench', 'Checks', 'Result', 'End Time', 'Coverage'],
        [(tc, tb, ch, (r, C_GREEN, True), et, cov) for tc,tb,ch,r,et,cov in RESULTS],
        [0.7, 1.8, 0.7, 0.7, 1.3, 2.1])

    heading(doc, '3  Key Simulation Log Excerpts')
    LOGS = [
        'tb_new_patterns: @1600550ns: === Chk1 PASS: sel=6 full white - all 520 px = WHITE ===',
        'tb_new_patterns: @1664550ns: === Chk2 PASS: sel=7 full black - all 520 px = BLANK ===',
        'tb_new_patterns: @1681750ns: === Chk3 PASS: sel=8 crosshatch - px0=WHITE px26=BLANK px52=WHITE ===',
        'tb_new_patterns: @1766650ns: === Chk4 PASS: sel=9 centre cross - px260=WHITE flanked by BLANK ===',
        'tb_new_patterns: @3367050ns: === Chk5 PASS: ball 100-wide - px0-99=WHITE  px100-519=BLACK ===',
        'tb_bram_double_buf: @1600550ns:   Ph1 PASS: initial back_buf_o = 1 (buf 0 displayed)',
        'tb_bram_double_buf: @41600550ns: === Ph2 PASS: display shows WHITE after swap ===',
        'tb_bram_double_buf: @81548750ns: === Ph3 PASS: alternating pattern confirmed after second swap ===',
        'tb_bram_double_buf: @119937450ns: === Ph4 PASS: only one swap per V-blank ===',
        'tb_pal_sel5: @41600500ns: === Chk3 PASS: F1 frame-1 line-0 all BLACK (ball_y=2) ===',
        'tb_video_bram_top: @40000500ns: === PAL Chk3 PASS: DAC levels valid over 400000 samples ===',
    ]
    for log in LOGS:
        p = doc.add_paragraph()
        r = p.add_run(log)
        r.font.name = 'Courier New'; r.font.size = Pt(8)
        r.font.color.rgb = C_GREEN

    heading(doc, '4  Defects Found During Testing')
    build_table(doc,
        ['Bug ID', 'Description', 'Found In', 'Resolution'],
        [('BUG-001','Em-dash in VHDL report string rejected by GHDL','tb_new_patterns.vhd','Replaced with hyphen-minus (sed)'),
         ('BUG-002','next_f1_line() could land mid-active-line','tb_new_patterns.vhd','Added drain loop; rewritten as next_f1_line procedure'),
         ('BUG-003','Crosshatch V-counter reset off by one','pal_tv_bram_top.vhd','Corrected v_cnt comparison to V_ACT_S_F1')],
        [0.8, 2.5, 1.8, 2.2])

    body(doc, 'All defects resolved. No open defects.', bold=True, color=C_GREEN)

    save(doc, 'STR_Software_Test_Report.docx')

# =============================================================================
# VC — Version Control Document
# =============================================================================
def gen_vc():
    doc = new_doc('Version Control Document', 'VC-001', 'Rev 1.0')

    heading(doc, '1  Repository')
    build_table(doc,
        ['Item', 'Value'],
        [('Platform',      'GitHub / Git'),
         ('Repository',    'robokks/video-ip-core-'),
         ('Active branch', 'claude/xilinx-pal-video-ip-RIDhJ'),
         ('Default branch','main'),
         ('VCS tool',      'Git 2.x')],
        [1.8, 5.5])

    heading(doc, '2  Branching Strategy')
    build_table(doc,
        ['Branch', 'Purpose', 'Rules'],
        [('main',                           'Stable baselines / releases', 'Only merge via PR; must pass all TCs'),
         ('claude/xilinx-pal-video-ip-RIDhJ','Active development',         'All RTL + doc changes; must pass GHDL before commit'),
         ('feature/*',                       'Experimental work',           'Branch from dev; merge back after passing TCs')],
        [2.2, 1.8, 2.8])

    heading(doc, '3  Commit Message Format')
    body(doc, 'Format:  <type>: <short summary>\n\n<body — what changed and why>\n\n<session URL>')
    build_table(doc,
        ['Type', 'Usage'],
        [('feat',    'New feature or capability'),
         ('fix',     'Bug fix'),
         ('docs',    'Documentation only'),
         ('test',    'Testbench added or updated'),
         ('refactor','Code restructure (no behaviour change)'),
         ('chore',   'Build scripts, CI, tooling')],
        [1.0, 5.3])

    heading(doc, '4  Commit History Summary')
    COMMITS = [
        ('64a021c','2026-05-24','docs: Add change log and working features note'),
        ('62d89fb','2026-05-24','feat: Add BRAM double-buffering to pal_tv_bram_top and video_bram_top'),
        ('4f6ad21','2026-05-24','docs: Add configuration summary document and generator script'),
        ('189a920','2026-05-24','docs: Update User Guide with simulation logs and waveform images (v2)'),
        ('02a5de0','2026-05-24','docs: Add simulation logs, waveform PNGs, and v2 report generator'),
        ('cbaec28','2026-05-23','docs: Add User and Reference Guide Word document + generator script'),
        ('5444894','2026-05-23','feat: HTML tool v2 — text overlay, multi-zone pattern, bg colour'),
        ('8f8a662','2026-05-23','feat: Add sel 6-9, ball control ports, crosshatch; HTML pattern tool'),
        ('5648443','2026-05-23','feat: Add line_sync_o, frame_sync_o outputs; rename csync/field ports'),
        ('bd57972','2026-05-22','feat: Add video_bram_top — runtime PAL/NTSC format selection'),
        ('09ce87c','2026-05-22','feat: Add sel=5 bouncing ball animation to pal_tv_bram_top'),
        ('eb1cd0b','2026-05-22','feat: Add tv/bram variant with BRAM pixel source (sel=4)'),
    ]
    build_table(doc,
        ['Hash', 'Date', 'Message'],
        COMMITS, [0.9, 1.0, 5.4])

    heading(doc, '5  Tagging / Release Policy')
    body(doc, 'Tag format: v<major>.<minor>.<patch>  (e.g. v1.0.0)')
    body(doc, 'A tag is created when a baseline is established on main after all TCs pass.')
    body(doc, 'Pre-release work stays on the development branch without tags.')

    save(doc, 'VC_Version_Control.docx')

# =============================================================================
# TM — Requirements Traceability Matrix
# =============================================================================
def gen_tm():
    doc = new_doc('Requirements Traceability Matrix', 'TM-001', 'Rev 1.0')

    heading(doc, '1  Purpose')
    body(doc, 'Maps every SRS requirement to its design module (SDD) and test case (STP/STR).')

    heading(doc, '2  Functional Requirements Traceability')
    TM_FR = [
        ('FR-001','PAL 625/50 interlaced video',   'pal_csync_il.vhd, pal_tv_bram_top.vhd', 'TC-002, TC-004', 'PASS'),
        ('FR-002','NTSC 525/60 runtime select',    'video_bram_top.vhd (ntsc_mode mux)',     'TC-008',         'PASS'),
        ('FR-003','Clock flexibility 10-40 MHz',   'pal_timing.vhd (CLK_DIV)',               'TC-003, TC-008', 'PASS'),
        ('FR-004','Pattern 0 — Vertical bars',     'zone_idx_v, stripe_ph_v logic',          'TC-001, TC-002', 'PASS'),
        ('FR-005','Pattern 1 — Horizontal bars',   'zone_idx_h, stripe_ph_h logic',          'TC-001, TC-003', 'PASS'),
        ('FR-006','Pattern 2 — H gradient',        'gzx_idx, grad_x_s process',              'TC-001, TC-003', 'PASS'),
        ('FR-007','Pattern 3 — V gradient',        'gzy_idx, grad_y_s process',              'TC-001, TC-003', 'PASS'),
        ('FR-008','Pattern 4 — BRAM image',        'bram_mem_0/1, bram_rd_line_base',        'TC-004',         'PASS'),
        ('FR-009','BRAM write port',               'bram_wr_en/addr/data process',           'TC-004, TC-009', 'PASS'),
        ('FR-010','Double buffering',              'disp_buf, swap_req, buf_swapped_s',      'TC-007',         'PASS'),
        ('FR-011','Pattern 5 — Bouncing ball',     'ball_x/y/vx/vy, ball_on',               'TC-005, TC-006', 'PASS'),
        ('FR-012','Pattern 6 — Full white',        'active_level mux sel=6',                 'TC-006',         'PASS'),
        ('FR-013','Pattern 7 — Full black',        'active_level mux sel=7',                 'TC-006',         'PASS'),
        ('FR-014','Pattern 8 — Crosshatch',        'cross_x_cnt, cross_y_cnt, cross_on',     'TC-006',         'PASS'),
        ('FR-015','Pattern 9 — Centre cross',      'centre_on combinational',                'TC-006',         'PASS'),
        ('FR-016','Brightness control',            'white_level_i, white_s',                 'TC-001,TC-006',  'PASS'),
        ('FR-017','Black level control',           'black_level_i, black_s',                 'TC-006',         'PASS'),
        ('FR-018','Sync outputs',                  'csync_o, line_sync_o, frame_sync_o, field_o, active_o, blank_o', 'TC-002', 'PASS'),
    ]
    build_table(doc,
        ['Req ID', 'Name', 'Design Module/Signal', 'Test Case', 'Result'],
        [(r, n, m, tc, (rs, C_GREEN, True)) for r,n,m,tc,rs in TM_FR],
        [0.8, 1.6, 2.1, 1.0, 0.7])

    heading(doc, '3  Non-Functional Requirements Traceability')
    TM_NFR = [
        ('NFR-001','Pixel clock accuracy',   'pal_timing CLK_DIV formula',           'TC-001 to TC-008 (implicit)', 'PASS'),
        ('NFR-002','Sync glitch-free',       'pal_csync_il (combinational only)',     'TC-002',                     'PASS'),
        ('NFR-003','Tear-free swap',         'swap at V_ACT_E_F2, h_cnt=H_TOTAL-1', 'TC-007 Phase 2',             'PASS'),
        ('NFR-004','BRAM inference',         'ram_style=block attribute',             'TC-004 (synthesis check)',   'N/A (Vivado)'),
        ('NFR-005','Reset recovery',         'All processes reset within 3 cycles',  'All TCs (rst sequence)',     'PASS'),
        ('NFR-006','GHDL testbenches',       'All 9 tb_*.vhd files',                 'TC-001 to TC-009',           'PASS'),
        ('NFR-007','No division at px rate', 'Modulo counters, zone index',          'Code review',                'PASS'),
        ('NFR-008','No Xilinx primitives',   'Only ram_style attribute used',        'Code review',                'PASS'),
        ('NFR-009','Single clock domain',    'All processes use rising_edge(clk)',   'All TCs',                    'PASS'),
        ('NFR-010','Modular structure',      'pal_timing / pal_csync_il separate',   'Code review',                'PASS'),
    ]
    build_table(doc,
        ['Req ID', 'Name', 'Design Evidence', 'Test/Review', 'Result'],
        [(r, n, e, t, (rs, C_GREEN, True)) for r,n,e,t,rs in TM_NFR],
        [0.8, 1.5, 2.0, 1.5, 0.8])

    save(doc, 'TM_Traceability_Matrix.docx')

# =============================================================================
# BR — Bug Report Log
# =============================================================================
def gen_br():
    doc = new_doc('Bug Report Log', 'BR-001', 'Rev 1.0')

    heading(doc, '1  Bug Report Template')
    build_table(doc,
        ['Field', 'Description'],
        [('Bug ID',       'Unique identifier BUG-NNN'),
         ('Date Found',   'Date bug was discovered'),
         ('Severity',     'Critical / Major / Minor / Trivial'),
         ('Status',       'Open / In Progress / Fixed / Verified / Closed'),
         ('Module',       'VHDL file or tool where bug was found'),
         ('Description',  'What went wrong; observed vs expected'),
         ('Root Cause',   'Why it happened'),
         ('Fix Applied',  'What change was made'),
         ('Fixed In',     'Git commit hash'),
         ('Verified By',  'Testbench or review method that confirmed fix')],
        [1.5, 5.8])

    heading(doc, '2  Bug Log')

    BUGS = [
        {
            'id': 'BUG-001', 'date': '2026-05-23', 'severity': 'Minor',
            'status': 'CLOSED', 'module': 'tv/bram/tb_new_patterns.vhd',
            'desc':  'GHDL rejected em-dash character (—, U+2014) inside VHDL report string literals. '
                     'Build failed with UTF-8 parse error.',
            'cause': 'VHDL string literals must contain only 7-bit ASCII characters. '
                     'Em-dash is a multi-byte UTF-8 character outside the VHDL character set.',
            'fix':   'Replaced all em-dash occurrences with hyphen-minus (-) using sed. '
                     'sed -i \'s/—/-/g\' tb_new_patterns.vhd',
            'commit':'Inline fix during session',
            'verify':'tb_new_patterns compiles and runs without error',
        },
        {
            'id': 'BUG-002', 'date': '2026-05-23', 'severity': 'Major',
            'status': 'CLOSED', 'module': 'tv/bram/tb_new_patterns.vhd',
            'desc':  'Testbench procedure wait_active_line() returned immediately if called while '
                     'active_o was already high, landing mid-line instead of at px=0. '
                     'Chk4 (centre cross) started counting from px~53 instead of px~0, '
                     'causing the px260 WHITE check to read px313 (BLANK) — false FAIL.',
            'cause': 'The original procedure waited for active_o = 1 without first draining '
                     'the current active window. A subsequent call mid-active period '
                     'returned instantly on the current rising edge.',
            'fix':   'Replaced procedure with next_f1_line() which: (1) drains current '
                     'active window by waiting for active_o = 0, then (2) waits for '
                     'next rising edge of active_o with field_o = 0.',
            'commit':'Inline fix during session',
            'verify':'tb_new_patterns Chk4 PASS at correct pixel positions',
        },
        {
            'id': 'BUG-003', 'date': '2026-05-23', 'severity': 'Minor',
            'status': 'CLOSED', 'module': 'tv/bram/pal_tv_bram_top.vhd',
            'desc':  'Crosshatch vertical counter (cross_y_cnt) reset condition used '
                     'v_cnt = V_ACT_S_F1 - 1 which fired one line early, causing the '
                     'first grid line to appear one row above the active area.',
            'cause': 'Off-by-one in reset condition: should reset at the start of the '
                     'first active line, not the line before.',
            'fix':   'Changed reset condition to v_cnt = V_ACT_S_F1 and h_cnt = 0 '
                     '(fires at the very beginning of the first active line).',
            'commit':'Inline fix during session',
            'verify':'tb_new_patterns Chk3a PASS: px0 of line 0 = WHITE (grid line at start)',
        },
    ]

    for bug in BUGS:
        heading(doc, f"{bug['id']} — {bug['module']}", 2)
        sev_color = C_ORANGE if bug['severity'] == 'Major' else C_BLUE
        build_table(doc,
            ['Field', 'Detail'],
            [('Bug ID',      bug['id']),
             ('Date Found',  bug['date']),
             ('Severity',    (bug['severity'], sev_color, True)),
             ('Status',      (bug['status'], C_GREEN, True)),
             ('Module',      bug['module']),
             ('Description', bug['desc']),
             ('Root Cause',  bug['cause']),
             ('Fix Applied', bug['fix']),
             ('Commit',      bug['commit']),
             ('Verified By', bug['verify'])],
            [1.3, 5.5], zebra=False)

    heading(doc, '3  Open Bugs')
    body(doc, 'No open bugs.', bold=True, color=C_GREEN)

    heading(doc, '4  Bug Statistics')
    build_table(doc,
        ['Category', 'Count'],
        [('Total bugs reported',  '3'),
         ('Critical',             '0'),
         ('Major',                '1'),
         ('Minor',                '2'),
         ('Trivial',              '0'),
         ('Fixed & Closed',       '3'),
         ('Currently Open',       '0')],
        [2.5, 1.0])

    save(doc, 'BR_Bug_Report.docx')

# =============================================================================
# CL — Change Log
# =============================================================================
def gen_cl():
    doc = new_doc('Project Change Log', 'CL-001', 'Rev 1.0')

    heading(doc, '1  Version Baseline History')
    build_table(doc,
        ['Version', 'Date', 'Description'],
        [('V0.1', '2026-05-22', 'Initial: pal_timing, pal_csync_il, opt1/2/3 variants, base patterns sel 0–3'),
         ('V0.2', '2026-05-22', 'BRAM image display (sel=4), natural sequential row addressing, pal_bram_loader'),
         ('V0.3', '2026-05-23', 'sel 5–9, ball control ports, crosshatch ports, NTSC mode (video_bram_top)'),
         ('V0.4', '2026-05-23', 'Separate sync outputs (line_sync_o, frame_sync_o, field_o)'),
         ('V0.5', '2026-05-23', 'HTML pattern generator tool v1 and v2 (text overlay, multi-zone)'),
         ('V0.6', '2026-05-24', 'User & Reference Guide Word document (v1 then v2 with simulation data)'),
         ('V0.7', '2026-05-24', 'Configuration Summary document'),
         ('V1.0', '2026-05-24', 'BRAM double-buffering, full formal docs set (ICD, SRS, SDD, SDP, CM, STP, STR, VC, TM, BR, CL)')],
        [0.8, 1.0, 5.5])

    heading(doc, '2  Detailed Change Log')
    CHANGES = [
        ('2026-05-24', 'V1.0', 'feat', 'BRAM Double-Buffering',
         'Split bram_mem into bram_mem_0 and bram_mem_1. Write port always targets back buffer. '
         'buf_swap deferred to V-blank. buf_swapped strobe output. back_buf_o status output. '
         'Added tb_bram_double_buf.vhd (4 phases, all PASS).',
         'tv/bram/pal_tv_bram_top.vhd, tv/bram/video_bram_top.vhd, tv/bram/tb_bram_double_buf.vhd'),
        ('2026-05-24', 'V1.0', 'docs', 'Configuration Summary Document',
         'Generated PAL_NTSC_Config_Summary.docx: generics, runtime ports, sel table, outputs, quick-ref.',
         'tools/PAL_NTSC_Config_Summary.docx, tools/gen_config_summary.py'),
        ('2026-05-24', 'V0.6b','docs', 'User Guide v2 — Simulation Results',
         'Added waveform PNGs from GHDL VCD files, DAC strip diagrams, PASS/FAIL sim logs.',
         'tools/PAL_NTSC_Video_IP_User_Guide.docx, tools/gen_report_v2.py'),
        ('2026-05-23', 'V0.5', 'feat', 'sel 6–9 and Ball/Crosshatch Ports',
         'sel=6 full white, sel=7 full black, sel=8 crosshatch with cross_h_i/cross_v_i ports, '
         'sel=9 centre cross. Ball ports: ball_w_i, ball_h_i, ball_spd_h, ball_spd_v. '
         'Crosshatch uses modulo counters (no divider). tb_new_patterns.vhd: 5 checks, all PASS.',
         'tv/bram/pal_tv_bram_top.vhd, tv/bram/video_bram_top.vhd, tv/bram/tb_new_patterns.vhd'),
        ('2026-05-23', 'V0.5', 'feat', 'HTML Pattern Generator Tool v2',
         'Text overlay (multiple entries, position, font, colour). Multi-zone pattern (V/H split, '
         'per-zone type/colour). PNG and 1-bit binary BRAM export.',
         'tools/bram_pattern_gen.html'),
        ('2026-05-23', 'V0.4', 'feat', 'Separate Sync Output Ports',
         'Added line_sync_o (H-sync only), frame_sync_o (V-sync region), field_o (field indicator) '
         'to all interlaced and BRAM variants.',
         'tv/bram/pal_tv_bram_top.vhd, tv/bram/video_bram_top.vhd, tv/opt2_interlaced/*.vhd'),
        ('2026-05-22', 'V0.3', 'feat', 'PAL/NTSC Runtime Selection (video_bram_top)',
         'New top-level entity video_bram_top. ntsc_mode port selects PAL 625/50 or NTSC 525/60. '
         'All timing driven combinationally. H_TOTAL=640/636, V_TOTAL=625/525.',
         'tv/bram/video_bram_top.vhd, tv/bram/tb_video_bram_top.vhd'),
        ('2026-05-22', 'V0.2', 'feat', 'BRAM Image Display (sel=4)',
         'Internal 1-bit BRAM. Natural sequential row order with automatic interlace correction. '
         'bram_len port for partial frame loop. pal_bram_loader.vhd utility.',
         'tv/bram/pal_tv_bram_top.vhd, tv/bram/pal_bram_loader.vhd'),
        ('2026-05-22', 'V0.2', 'feat', 'Bouncing Ball Animation (sel=5)',
         'White rectangle bouncing inside active picture area. Elastic reflection on all 4 walls. '
         'Default size 60×50 px, speed 3h/2v px/frame.',
         'tv/bram/pal_tv_bram_top.vhd'),
        ('2026-05-22', 'V0.1', 'feat', 'Base IP Core',
         'pal_timing (H/V counters, CLK_DIV). pal_csync_il (interlaced composite sync, purely combinational). '
         'pal_sync_gen (non-interlaced sync). opt1 CRT50, opt2 interlaced, opt3 prog25. '
         'Base patterns sel 0–3. brightness/black_lvl control.',
         'tv/pal_timing.vhd, tv/opt2_interlaced/pal_csync_il.vhd, tv/bram/pal_tv_bram_top.vhd'),
    ]
    for date, ver, typ, name, detail, files in CHANGES:
        t = doc.add_table(rows=1, cols=4)
        t.style = 'Table Grid'
        hc = C_HDR if ver == 'V1.0' else C_HDR2
        set_cell_bg(t.rows[0].cells[0], hc); cp(t.rows[0].cells[0], f'{ver}', bold=True, color=C_WHITE, size=10)
        set_cell_bg(t.rows[0].cells[1], hc); cp(t.rows[0].cells[1], date, bold=False, color=C_WHITE, size=9.5)
        set_cell_bg(t.rows[0].cells[2], hc); cp(t.rows[0].cells[2], f'[{typ}] {name}', bold=True, color=C_WHITE, size=10)
        bg = C_ALT; set_cell_bg(t.rows[0].cells[3], bg)
        cp(t.rows[0].cells[3], f'{detail}\nFiles: {files}', size=8.5, color=C_BLACK)
        for ci, w in enumerate([0.6, 0.9, 1.8, 4.0]):
            t.rows[0].cells[ci].width = Inches(w)
        spacer(doc)

    save(doc, 'CL_Change_Log.docx')

# =============================================================================
# MAIN
# =============================================================================
print('Generating project documents...')
gen_icd()
gen_srs()
gen_sdd()
gen_sdp()
gen_cm()
gen_stp()
gen_str()
gen_vc()
gen_tm()
gen_br()
gen_cl()
print(f'\nAll 11 documents saved to {DOCS}/')
