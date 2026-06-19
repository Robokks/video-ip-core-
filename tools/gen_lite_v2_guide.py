#!/usr/bin/env python3
"""
gen_lite_v2_guide.py
Generate docs/PAL_LITE_V2_GUIDE.docx — plain-English, line-by-line
explanation of pal_timing.vhd, pal_csync_il.vhd, and pal_tv_bram_lite_v2.vhd.
Written so a junior engineer with NO FPGA background can understand.
"""

import os
from docx import Document
from docx.shared import Pt, Inches, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

OUT_DIR  = os.path.join(os.path.dirname(__file__), '..', 'docs')
OUT_FILE = os.path.join(OUT_DIR, 'PAL_LITE_V2_GUIDE.docx')

C_NAVY   = RGBColor(0x00, 0x27, 0x5A)
C_MID    = RGBColor(0x00, 0x5B, 0x96)
C_STEEL  = RGBColor(0x4A, 0x7C, 0xB4)
C_LTBLUE = RGBColor(0xD6, 0xE4, 0xF7)
C_YELLOW = RGBColor(0xFF, 0xF9, 0xC4)
C_GREEN  = RGBColor(0xD4, 0xED, 0xDA)
C_PINK   = RGBColor(0xF8, 0xD7, 0xDA)
C_WHITE  = RGBColor(0xFF, 0xFF, 0xFF)
C_BLACK  = RGBColor(0x00, 0x00, 0x00)
C_GREY   = RGBColor(0xF2, 0xF2, 0xF2)
C_ORANGE = RGBColor(0xFF, 0xE0, 0xB2)


def set_cell_bg(cell, rgb):
    tc   = cell._tc
    tcPr = tc.get_or_add_tcPr()
    shd  = OxmlElement('w:shd')
    shd.set(qn('w:val'),   'clear')
    shd.set(qn('w:color'), 'auto')
    shd.set(qn('w:fill'),  f'{rgb[0]:02X}{rgb[1]:02X}{rgb[2]:02X}')
    tcPr.append(shd)


def cp(cell, text, bold=False, italic=False, size=10, color=C_BLACK,
       font='Calibri'):
    para = cell.paragraphs[0] if cell.paragraphs else cell.add_paragraph()
    run = para.add_run(text)
    run.bold  = bold
    run.italic = italic
    run.font.size  = Pt(size)
    run.font.color.rgb = color
    run.font.name  = font
    return para


def heading(doc, text, level=1):
    styles = {
        1: (C_NAVY,  16, True),
        2: (C_MID,   13, True),
        3: (C_STEEL, 11, True),
    }
    color, size, bold = styles.get(level, styles[1])
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(12 if level == 1 else 6)
    p.paragraph_format.space_after  = Pt(4)
    run = p.add_run(text)
    run.bold = bold
    run.font.size  = Pt(size)
    run.font.color.rgb = color
    run.font.name  = 'Calibri'
    return p


def body(doc, text, italic=False, bold=False, size=10.5):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(2)
    p.paragraph_format.space_after  = Pt(4)
    run = p.add_run(text)
    run.font.size = Pt(size)
    run.italic = italic
    run.bold   = bold
    run.font.name = 'Calibri'
    return p


def note(doc, text):
    """Highlighted note box."""
    p = doc.add_paragraph()
    p.paragraph_format.left_indent  = Inches(0.3)
    p.paragraph_format.space_before = Pt(3)
    p.paragraph_format.space_after  = Pt(3)
    run = p.add_run('NOTE: ' + text)
    run.font.size = Pt(10)
    run.font.color.rgb = C_NAVY
    run.font.name = 'Calibri'
    run.bold = True
    return p


def tip(doc, text):
    """Green tip box."""
    p = doc.add_paragraph()
    p.paragraph_format.left_indent  = Inches(0.3)
    p.paragraph_format.space_before = Pt(3)
    p.paragraph_format.space_after  = Pt(3)
    run = p.add_run('TIP: ' + text)
    run.font.size = Pt(10)
    run.font.color.rgb = RGBColor(0x15, 0x5A, 0x1F)
    run.font.name = 'Calibri'
    run.italic = True
    return p


def code_line(doc, line_no, code, explanation, bg=C_GREY):
    """Two-column table row: line number+code | plain-English explanation."""
    tbl = doc.add_table(rows=1, cols=2)
    tbl.style = 'Table Grid'
    tbl.columns[0].width = Inches(2.8)
    tbl.columns[1].width = Inches(4.0)
    r = tbl.rows[0]
    set_cell_bg(r.cells[0], bg)
    set_cell_bg(r.cells[1], C_WHITE)
    lbl = f'Line {line_no}:  ' if line_no else '         '
    cp(r.cells[0], lbl + code, font='Courier New', size=8.5)
    cp(r.cells[1], explanation, size=10)
    doc.add_paragraph().paragraph_format.space_after = Pt(1)


def code_block_explain(doc, entries, bg=C_GREY):
    """
    entries = list of (line_no_str, code, explanation)
    Draws a compact table for a group of related lines.
    """
    tbl = doc.add_table(rows=len(entries), cols=3)
    tbl.style = 'Table Grid'
    tbl.columns[0].width = Inches(0.55)
    tbl.columns[1].width = Inches(2.6)
    tbl.columns[2].width = Inches(3.65)
    for i, (ln, code, expl) in enumerate(entries):
        r = tbl.rows[i]
        set_cell_bg(r.cells[0], C_LTBLUE)
        set_cell_bg(r.cells[1], bg)
        set_cell_bg(r.cells[2], C_WHITE)
        cp(r.cells[0], str(ln), bold=True, size=8.5)
        cp(r.cells[1], code, font='Courier New', size=8.5)
        cp(r.cells[2], expl, size=9.5)
    doc.add_paragraph().paragraph_format.space_after = Pt(2)


def section_banner(doc, filename, one_liner):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(4)
    p.paragraph_format.space_after  = Pt(2)
    run = p.add_run(f'  FILE: {filename}')
    run.font.size = Pt(10)
    run.bold = True
    run.font.color.rgb = C_WHITE
    run.font.name = 'Courier New'
    # shade the paragraph background
    pPr = p._p.get_or_add_pPr()
    shd = OxmlElement('w:shd')
    shd.set(qn('w:val'),   'clear')
    shd.set(qn('w:color'), 'auto')
    shd.set(qn('w:fill'),  '00275A')
    pPr.append(shd)
    body(doc, one_liner, italic=True)


# ===========================================================================
# Title page
# ===========================================================================
def make_title(doc):
    doc.add_paragraph()
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run = p.add_run('PAL Video IP Core')
    run.font.size = Pt(28)
    run.bold = True
    run.font.color.rgb = C_NAVY
    run.font.name = 'Calibri'

    p2 = doc.add_paragraph()
    p2.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run2 = p2.add_run('Beginner\'s Code Guide')
    run2.font.size = Pt(20)
    run2.font.color.rgb = C_MID
    run2.font.name = 'Calibri'

    doc.add_paragraph()
    p3 = doc.add_paragraph()
    p3.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run3 = p3.add_run(
        'pal_timing.vhd  |  pal_csync_il.vhd  |  pal_tv_bram_lite_v2.vhd')
    run3.font.size = Pt(12)
    run3.font.color.rgb = C_STEEL
    run3.font.name = 'Courier New'

    doc.add_paragraph()
    p4 = doc.add_paragraph()
    p4.alignment = WD_ALIGN_PARAGRAPH.CENTER
    run4 = p4.add_run(
        'Line-by-line explanation written for engineers with no FPGA background.\n'
        'Every VHDL keyword is explained in plain English.')
    run4.font.size = Pt(11)
    run4.font.color.rgb = C_BLACK
    run4.font.name = 'Calibri'
    run4.italic = True

    doc.add_page_break()


# ===========================================================================
# Chapter 1 — PAL Video Concepts
# ===========================================================================
def ch_pal_concepts(doc):
    heading(doc, 'Chapter 1 — PAL Video: Key Concepts', 1)
    body(doc,
         'Before reading the VHDL code, you need to understand what PAL video '
         'actually is and how it works. This chapter explains the key ideas in '
         'plain language.')

    heading(doc, '1.1  What is a Pixel Clock?', 2)
    body(doc,
         'A video signal is made up of thousands of tiny dots called pixels. '
         'The pixel clock is the heartbeat that says "move to the next pixel now." '
         'In our system the pixel clock runs at exactly 10 MHz — that means '
         '10,000,000 pixels per second, or one pixel every 100 nanoseconds (100 ns).')
    tip(doc, '100 ns per pixel. All timing numbers in this code are pixel counts.')

    heading(doc, '1.2  What is a Video Line?', 2)
    body(doc,
         'One video line is a single horizontal row of pixels scanned left to right. '
         'In PAL video a line is 64 microseconds long. At our 10 MHz pixel clock: '
         '64 µs ÷ 100 ns = 640 pixels per line. We call this H_TOTAL = 640.')
    body(doc,
         'Not all 640 pixels carry picture. The line is divided into sections:')
    rows = [
        ('Front porch',   '16 px = 1.6 µs',  'Short gap before the sync pulse'),
        ('H-sync pulse',  '47 px = 4.7 µs',  'Tells the display "new line starting"'),
        ('Back porch',    '57 px = 5.7 µs',  'Short gap after sync, before picture'),
        ('Active video',  '520 px = 52 µs',  'Actual picture pixels'),
        ('TOTAL',         '640 px = 64 µs',  '16+47+57+520 = 640'),
    ]
    tbl = doc.add_table(rows=len(rows)+1, cols=3)
    tbl.style = 'Table Grid'
    for ci, h_ in enumerate(['Section', 'Duration', 'Purpose']):
        set_cell_bg(tbl.rows[0].cells[ci], C_NAVY)
        cp(tbl.rows[0].cells[ci], h_, bold=True, color=C_WHITE)
    for i, (s, d, p) in enumerate(rows):
        r = tbl.rows[i+1]
        bg = C_LTBLUE if i < 4 else C_YELLOW
        set_cell_bg(r.cells[0], bg)
        cp(r.cells[0], s, bold=(i==4))
        cp(r.cells[1], d, font='Courier New', size=9)
        cp(r.cells[2], p)
    doc.add_paragraph()

    heading(doc, '1.3  What is a Video Frame?', 2)
    body(doc,
         'A frame is one complete picture. PAL has 625 lines per frame. '
         'At 64 µs per line: 625 × 64 µs = 40 ms per frame = 25 frames per second. '
         'We call the total line count V_TOTAL = 625.')
    body(doc,
         'Just like lines have a blanking period, frames also have a blanking period. '
         'Not all 625 lines carry picture. The top and bottom lines are "vertical '
         'blanking" lines used for sync signals.')

    heading(doc, '1.4  What is Interlaced Video?', 2)
    body(doc,
         'Interlaced video divides each frame into two FIELDS. '
         'Field 1 (F1) draws the ODD lines; Field 2 (F2) draws the EVEN lines. '
         'Each field takes 20 ms (50 fields per second). This makes motion smoother '
         'on old CRT displays even at only 25 frames per second.')
    body(doc,
         'F1 starts at the very beginning of a line (pixel 0 of line 0). '
         'F2 starts exactly HALF A LINE later — at pixel 320 of line 312. '
         'This half-line offset is what gives the interlaced look on a TV screen.')

    heading(doc, '1.5  What is Composite Sync (csync)?', 2)
    body(doc,
         'The composite sync signal tells the display where each line starts '
         '(H-sync) and where each field starts (V-sync). '
         'In PAL, the V-sync is not a simple pulse — it uses three groups of '
         'special pulses called pre-equalising, broad-sync, and post-equalising. '
         'Together they occupy 7.5 lines at the top of each field.')
    rows2 = [
        ('Pre-equalising', '5 half-line pulses', 'Narrow pulse = 2.3 µs (EQ_W = 23 px)'),
        ('Broad sync',     '5 half-line pulses', 'Wide pulse = 27.3 µs (BROAD_W = 273 px)'),
        ('Post-equalising','5 half-line pulses', 'Narrow pulse = 2.3 µs (EQ_W = 23 px)'),
    ]
    tbl2 = doc.add_table(rows=4, cols=3)
    tbl2.style = 'Table Grid'
    for ci, h_ in enumerate(['Group', 'Count', 'Pulse Width']):
        set_cell_bg(tbl2.rows[0].cells[ci], C_MID)
        cp(tbl2.rows[0].cells[ci], h_, bold=True, color=C_WHITE)
    for i, (g, c, p) in enumerate(rows2):
        r = tbl2.rows[i+1]
        set_cell_bg(r.cells[0], C_LTBLUE)
        cp(r.cells[0], g)
        cp(r.cells[1], c)
        cp(r.cells[2], p)
    doc.add_paragraph()

    heading(doc, '1.6  What is FSS (Field Sync Signal)?', 2)
    body(doc,
         'The FSS output is HIGH during the broad-sync + post-equalising interval '
         'of EVERY field. It fires at 50 Hz (once per field). '
         'Some video equipment — particularly aircraft avionics — uses FSS as a '
         'timing reference to lock onto the video source.')
    note(doc,
         'FSS is NOT the same as csync. csync is the full composite sync waveform. '
         'FSS is a clean logic-level signal that goes HIGH only during the '
         'broad-sync + post-eq region (320 µs = 5 lines per field).')

    heading(doc, '1.7  What is BRAM?', 2)
    body(doc,
         'BRAM stands for Block RAM — a fast memory built into the FPGA chip. '
         'In our design, BRAM stores the video frame as a grid of 1-bit pixels '
         '(0 = black, 1 = white/brightness level). '
         'The host processor writes pixels into BRAM; the video core reads them '
         'out in scan order and sends them to the DAC.')

    heading(doc, '1.8  What is a 4-bit R-2R DAC?', 2)
    body(doc,
         'A DAC (Digital-to-Analogue Converter) turns a digital number into a '
         'voltage. Our 4-bit DAC uses a resistor network (R-2R ladder) to produce '
         '16 voltage levels (0–15). In PAL video:')
    rows3 = [
        ('0x0 = 0000', 'Sync tip',      '0 V  — lowest voltage (sync pulse)'),
        ('0x4 = 0100', 'Blank level',   '0.3 V — black/blanking level'),
        ('0xF = 1111', 'Peak white',    '1.0 V — maximum brightness'),
    ]
    tbl3 = doc.add_table(rows=4, cols=3)
    tbl3.style = 'Table Grid'
    for ci, h_ in enumerate(['DAC value', 'Meaning', 'Voltage']):
        set_cell_bg(tbl3.rows[0].cells[ci], C_NAVY)
        cp(tbl3.rows[0].cells[ci], h_, bold=True, color=C_WHITE)
    for i, (v, m, vo) in enumerate(rows3):
        r = tbl3.rows[i+1]
        set_cell_bg(r.cells[0], C_LTBLUE)
        cp(r.cells[0], v, font='Courier New', size=9)
        cp(r.cells[1], m, bold=True)
        cp(r.cells[2], vo)
    doc.add_paragraph()

    doc.add_page_break()


# ===========================================================================
# Chapter 2 — VHDL Quick Reference
# ===========================================================================
def ch_vhdl_intro(doc):
    heading(doc, 'Chapter 2 — VHDL Quick Reference', 1)
    body(doc,
         'VHDL is a Hardware Description Language. It does NOT run as a program — '
         'it DESCRIBES a digital circuit that will be built inside an FPGA chip. '
         'Think of VHDL like an architect\'s blueprint, not a software program.')

    keywords = [
        ('library / use',
         'Import a package of pre-defined types. Like "import" in Python or '
         '"#include" in C. Almost every VHDL file starts with these two lines.'),
        ('entity',
         'The INTERFACE of a circuit block — lists all the input and output pins. '
         'Think of it like a chip datasheet listing the pins.'),
        ('generic',
         'A configuration parameter. Like a #define in C. Set once and used '
         'throughout the design. Example: CLK_MHZ=40 tells the code the board '
         'clock is 40 MHz.'),
        ('port',
         'The actual input/output signals of the entity. Each port has a direction '
         '(in or out) and a type (std_logic, integer, etc.).'),
        ('architecture',
         'The IMPLEMENTATION of the entity — the actual circuit logic inside. '
         'One entity can have multiple architectures (we always use one called rtl).'),
        ('signal',
         'An internal wire inside the architecture. Not visible outside the entity. '
         'Like a local variable but it represents an actual wire.'),
        ('constant',
         'A fixed value computed at synthesis time. Never changes at runtime.'),
        ('process(A, B)',
         'A block of code that executes whenever signal A or B changes. '
         'Sequential-style code inside (if/else, variable assignments). '
         'All processes run in parallel with each other.'),
        ('rising_edge(clk)',
         'Returns TRUE at the exact moment the clock signal transitions from '
         '0 to 1. This is how synchronous (clocked) logic is written.'),
        ('std_logic',
         'A single-bit digital signal. Can be \'0\' (low voltage) or \'1\' '
         '(high voltage). The fundamental type in VHDL.'),
        ('std_logic_vector(N downto 0)',
         'A bus of N+1 bits. Like an array of std_logic signals. '
         'Example: 4-bit DAC output is std_logic_vector(3 downto 0).'),
        ('integer range A to B',
         'A whole number between A and B. The synthesiser uses this range to '
         'decide how many bits of hardware to allocate.'),
        ('when ... else',
         'Conditional signal assignment. Like a ternary operator or short if/else. '
         'Evaluated continuously (not just on clock edges).'),
        ('variable',
         'Like a signal but LOCAL to a process and updates INSTANTLY (no clock '
         'delay). Used inside processes for intermediate calculations.'),
        (':= vs <=',
         ':= assigns to a variable (instant, within one process). '
         '<= assigns to a signal (takes effect at next delta cycle or clock edge).'),
        ('assert ... report ... severity failure',
         'A safety check. If the condition is false, the simulator prints the '
         'message and stops. Used to catch wrong parameter combinations.'),
    ]

    tbl = doc.add_table(rows=len(keywords)+1, cols=2)
    tbl.style = 'Table Grid'
    tbl.columns[0].width = Inches(1.9)
    tbl.columns[1].width = Inches(4.9)
    set_cell_bg(tbl.rows[0].cells[0], C_NAVY)
    set_cell_bg(tbl.rows[0].cells[1], C_NAVY)
    cp(tbl.rows[0].cells[0], 'VHDL Keyword', bold=True, color=C_WHITE)
    cp(tbl.rows[0].cells[1], 'Plain English Meaning', bold=True, color=C_WHITE)
    for i, (kw, meaning) in enumerate(keywords):
        r = tbl.rows[i+1]
        set_cell_bg(r.cells[0], C_LTBLUE)
        set_cell_bg(r.cells[1], C_WHITE)
        cp(r.cells[0], kw, font='Courier New', size=9, bold=True)
        cp(r.cells[1], meaning, size=9.5)
    doc.add_paragraph()

    doc.add_page_break()


# ===========================================================================
# Chapter 3 — pal_timing.vhd
# ===========================================================================
def ch_timing(doc):
    heading(doc, 'Chapter 3 — pal_timing.vhd', 1)
    section_banner(doc,
                   'tv/pal_timing.vhd',
                   'Generates the pixel clock enable (ce) and two counters '
                   '(h_cnt = horizontal position, v_cnt = vertical position) '
                   'that tell the rest of the system where we are in the video frame.')

    heading(doc, '3.1  What This File Does', 2)
    body(doc,
         'Think of this module as a stopwatch counting pixels and lines. '
         'Every time the pixel clock ticks, h_cnt goes up by 1. '
         'When h_cnt reaches 639 (end of line), it resets to 0 and v_cnt goes up by 1. '
         'When v_cnt reaches 624 (end of frame), both reset to 0 and a new frame begins.')
    body(doc,
         'The module also handles boards with different clock speeds (10, 20, 30, 40 MHz). '
         'It divides the input clock internally so the pixel rate is always 10 MHz.')

    heading(doc, '3.2  Line-by-Line Walkthrough', 2)

    code_block_explain(doc, [
        (1,  'library ieee;',
             'Import the IEEE standard library. Required by virtually every VHDL file. '
             'The IEEE library contains standard data types used in digital design.'),
        (2,  'use ieee.std_logic_1164.all;',
             'Import the std_logic type from the IEEE library. std_logic is the '
             'fundamental 1-bit digital signal type (\'0\' or \'1\'). '
             '.all means "import everything from this package".'),
    ])

    code_block_explain(doc, [
        (10, 'entity pal_timing is',
             'Start defining the interface of this circuit block. '
             'The entity is like the chip\'s pin list.'),
        (11, '  generic (',
             'Begin the list of configuration parameters. These are set by the '
             'parent module and cannot change at runtime.'),
        (12, '  H_TOTAL : integer := 640;',
             'Parameter: total pixels per line. Default = 640 '
             '(64 µs × 10 MHz). Can be overridden by the parent.'),
        (13, '  V_TOTAL : integer := 625;',
             'Parameter: total lines per frame. Default = 625 (PAL standard).'),
        (14, '  CLK_MHZ : integer := 10',
             'Parameter: input clock frequency in MHz. '
             'Default = 10 MHz. Set to 20, 30, or 40 if your board runs faster.'),
        (16, '  port (',
             'Begin the list of input/output pins.'),
        (17, '  clk   : in  std_logic;',
             'INPUT: the main clock signal from the FPGA board. '
             'The circuit does something at every rising edge of this signal.'),
        (18, '  rst   : in  std_logic;',
             'INPUT: reset signal. When rst=\'1\', all counters go back to zero. '
             'Use this to restart the video frame from the beginning.'),
        (19, '  ce    : out std_logic;',
             'OUTPUT: clock enable. Goes to \'1\' for exactly one clock cycle '
             'every 10 MHz pixel period. If CLK_MHZ=40, this fires once every '
             '4 clock cycles (40÷10=4). All downstream pixel logic uses this.'),
        (20, '  h_cnt : out integer range 0 to 639;',
             'OUTPUT: horizontal counter. Current pixel position in the line. '
             '0 = leftmost position, 639 = rightmost position.'),
        (21, '  v_cnt : out integer range 0 to 624',
             'OUTPUT: vertical counter. Current line number in the frame. '
             '0 = top line, 624 = bottom line.'),
        (23, 'end entity pal_timing;',
             'End of the entity (pin list) definition.'),
    ])

    code_block_explain(doc, [
        (25, 'architecture rtl of pal_timing is',
             'Begin the implementation section. rtl means Register Transfer Level — '
             'the standard name for synthesisable VHDL logic.'),
        (27, '  constant CLK_DIV : integer := CLK_MHZ / 10;',
             'Calculate the clock divider ratio. If CLK_MHZ=40, CLK_DIV=4 '
             '(divide 40 MHz by 4 to get 10 MHz pixel clock). '
             'If CLK_MHZ=10, CLK_DIV=1 (no division needed).'),
        (29, '  signal div_cnt : integer range 0 to 3 := 0;',
             'Internal wire: counts from 0 to CLK_DIV-1 to create the '
             'pixel clock enable. Starts at 0 when the FPGA powers up.'),
        (30, '  signal ce_c    : std_logic;',
             'Internal wire: the pixel clock enable signal before it is '
             'connected to the output port.'),
        (31, '  signal h : integer range 0 to H_TOTAL - 1 := 0;',
             'Internal register: the horizontal pixel counter (0 to 639). '
             'Starts at 0. This is the internal copy of h_cnt.'),
        (32, '  signal v : integer range 0 to V_TOTAL - 1 := 0;',
             'Internal register: the vertical line counter (0 to 624). '
             'Starts at 0. This is the internal copy of v_cnt.'),
        (34, 'begin',
             'End of signal declarations. Everything below is actual circuit logic.'),
    ])

    code_block_explain(doc, [
        (36, '  assert CLK_MHZ = 10 or CLK_MHZ = 20 ...',
             'SAFETY CHECK: if someone sets CLK_MHZ to an unsupported value '
             '(e.g. 15), the simulator will immediately stop with an error message. '
             'This prevents silent errors from wrong configuration.'),
        (39, '  ce_c <= \'1\' when (CLK_DIV = 1) or (div_cnt = CLK_DIV - 1) else \'0\';',
             'The pixel clock enable logic. ce_c = \'1\' when: '
             '(a) CLK_DIV=1 meaning no division needed (always enabled), OR '
             '(b) the divider counter has reached its maximum (CLK_DIV-1). '
             'At CLK_MHZ=40, CLK_DIV=4, so ce_c is \'1\' once every 4 clocks.'),
    ])

    code_block_explain(doc, [
        (41, '  process(clk)',
             'Start a process that runs every time the clk signal changes.'),
        (43, '  if rising_edge(clk) then',
             'Only act on the RISING EDGE (0→1 transition) of the clock. '
             'This is how synchronous digital logic works — all actions are '
             'aligned to the same clock edge.'),
        (44, '  if rst = \'1\' then',
             'If the reset pin is high...'),
        (45, '    div_cnt <= 0; h <= 0; v <= 0;',
             'Reset all three counters to zero simultaneously. '
             'This forces the video timing back to the start of frame.'),
        (47, '  if CLK_DIV > 1 then',
             'Only run the clock divider if we actually need division '
             '(i.e. board clock is faster than 10 MHz).'),
        (48, '    if div_cnt = CLK_DIV - 1 then div_cnt <= 0;',
             'If the divider has counted up to its maximum, reset it to 0.'),
        (49, '    else div_cnt <= div_cnt + 1; end if;',
             'Otherwise count up by 1 each clock.'),
        (51, '  if ce_c = \'1\' then',
             'Only move the pixel counters when the pixel clock enable is active. '
             'This ensures h_cnt and v_cnt advance at exactly 10 MHz regardless '
             'of the board clock speed.'),
        (52, '    if h = H_TOTAL - 1 then',
             'If we have reached the last pixel of the current line (h=639)...'),
        (53, '      h <= 0;',
             'Reset horizontal counter to 0 (start of new line).'),
        (54, '      if v = V_TOTAL - 1 then v <= 0; else v <= v + 1; end if;',
             'If we were also on the last line (v=624), reset v to 0 (new frame). '
             'Otherwise increment v by 1 (move to next line).'),
        (56, '    else h <= h + 1;',
             'Normal case: just increment the horizontal counter by 1 pixel.'),
        (63, '  ce    <= ce_c;',
             'Connect the internal ce_c wire to the output port ce.'),
        (64, '  h_cnt <= h;',
             'Connect the internal counter h to the output port h_cnt.'),
        (65, '  v_cnt <= v;',
             'Connect the internal counter v to the output port v_cnt.'),
    ])

    body(doc, '')
    note(doc,
         'Summary: pal_timing is just two nested counters. h counts 0-639 '
         '(pixels in a line), v counts 0-624 (lines in a frame). Both reset '
         'and wrap around automatically. The ce output enables downstream logic '
         'at exactly 10 MHz regardless of board clock speed.')

    doc.add_page_break()


# ===========================================================================
# Chapter 4 — pal_csync_il.vhd
# ===========================================================================
def ch_csync(doc):
    heading(doc, 'Chapter 4 — pal_csync_il.vhd', 1)
    section_banner(doc,
                   'tv/opt2_interlaced/pal_csync_il.vhd',
                   'Generates the composite sync waveform (csync), field indicator '
                   '(field), and active-pixel flag (active) from the h_cnt and v_cnt '
                   'counters produced by pal_timing.')

    heading(doc, '4.1  What This File Does', 2)
    body(doc,
         'This module is a pure combinational circuit — it has no clock. '
         'Every time h_cnt or v_cnt changes, the outputs immediately update '
         '(within a few nanoseconds). Think of it as a lookup table: '
         'given (h_cnt, v_cnt) → tell us what the sync/field/active signals should be.')
    body(doc,
         'The module must generate THREE different types of sync pulses at the '
         'right times:')
    rows = [
        ('Normal H-sync', 'Every non-vsync line', 'At h_cnt=16, duration 47 px (4.7 µs)'),
        ('Equalising pulses', 'v_cnt 0-2 (F1), 312-314 (F2)', 'At hp=0, duration 23 px per half-line'),
        ('Broad sync pulses', 'v_cnt 2-4 (F1), 315-317 (F2)', 'At hp=0, duration 273 px per half-line'),
    ]
    tbl = doc.add_table(rows=4, cols=3)
    tbl.style = 'Table Grid'
    for ci, h_ in enumerate(['Pulse Type', 'When it occurs', 'Width']):
        set_cell_bg(tbl.rows[0].cells[ci], C_NAVY)
        cp(tbl.rows[0].cells[ci], h_, bold=True, color=C_WHITE)
    for i, (pt, w, wd) in enumerate(rows):
        r = tbl.rows[i+1]
        set_cell_bg(r.cells[0], C_LTBLUE)
        cp(r.cells[0], pt, bold=True)
        cp(r.cells[1], w)
        cp(r.cells[2], wd, font='Courier New', size=9)
    doc.add_paragraph()

    heading(doc, '4.2  Line-by-Line Walkthrough', 2)

    code_block_explain(doc, [
        (1,  'library ieee; use ieee.std_logic_1164.all;',
             'Standard imports — same as pal_timing. Needed in every VHDL file.'),
    ])

    code_block_explain(doc, [
        (26, 'entity pal_csync_il is',
             'Start the interface definition for the composite sync generator.'),
        (28, '  H_FRONT  : integer := 16;',
             'Generic: number of pixels in the front porch (before H-sync). '
             'Default = 16 pixels = 1.6 µs.'),
        (29, '  H_SYNC_W : integer := 47;',
             'Generic: H-sync pulse width in pixels. Default = 47 px = 4.7 µs.'),
        (30, '  H_BACK   : integer := 57;',
             'Generic: back porch width in pixels. Default = 57 px = 5.7 µs.'),
        (31, '  H_ACTIVE : integer := 520;',
             'Generic: active pixel width per line. Default = 520 px = 52 µs.'),
        (32, '  H_TOTAL  : integer := 640;',
             'Generic: total pixels per line (must = H_FRONT+H_SYNC_W+H_BACK+H_ACTIVE).'),
        (33, '  HALF     : integer := 320;',
             'Generic: half of H_TOTAL. Used because PAL vsync works in HALF-LINE '
             'units — each vsync pulse period is 320 pixels (32 µs).'),
        (34, '  EQ_W     : integer := 23;',
             'Generic: width of each equalising pulse = 23 px = 2.3 µs.'),
        (35, '  BROAD_W  : integer := 273;',
             'Generic: width of each broad sync pulse = 273 px = 27.3 µs. '
             'Note: BROAD_W + H_SYNC_W = 273 + 47 = 320 = HALF (fills the half-line).'),
        (36, '  V_ACT_S_F1 : integer := 24;',
             'Generic: first active video line in Field 1 (v_cnt value).'),
        (37, '  V_ACT_E_F1 : integer := 311;',
             'Generic: last active video line in Field 1.'),
        (38, '  V_ACT_S_F2 : integer := 336;',
             'Generic: first active video line in Field 2.'),
        (39, '  V_ACT_E_F2 : integer := 623;',
             'Generic: last active video line in Field 2.'),
    ])

    code_block_explain(doc, [
        (42, '  h_cnt  : in  integer range 0 to 639;',
             'INPUT: current horizontal pixel counter (from pal_timing). '
             '0 = start of line, 639 = end of line.'),
        (43, '  v_cnt  : in  integer range 0 to 624;',
             'INPUT: current vertical line counter (from pal_timing). '
             '0 = top of frame, 624 = bottom of frame.'),
        (44, '  csync  : out std_logic;',
             'OUTPUT: composite sync signal. \'1\' = sync pulse is active (LOW voltage). '
             'This goes to the DAC which outputs 0V (sync tip level) when csync=\'1\'.'),
        (45, '  field  : out std_logic;',
             'OUTPUT: field indicator. \'0\' = we are in Field 1, \'1\' = Field 2.'),
        (46, '  active : out std_logic',
             'OUTPUT: active pixel flag. \'1\' = we are in the active picture area. '
             'When active=\'1\', the pattern generator output goes to the DAC.'),
    ])

    code_block_explain(doc, [
        (51, '  constant H_ACT_S : integer := H_FRONT + H_SYNC_W + H_BACK;',
             'Calculate the pixel position where active video starts. '
             '= 16 + 47 + 57 = 120. So active video starts at h_cnt = 120 '
             '(after front porch + sync + back porch).'),
    ])

    code_block_explain(doc, [
        (54, '  assert H_FRONT + H_SYNC_W + H_BACK + H_ACTIVE = H_TOTAL',
             'SAFETY CHECK: the four horizontal sections must add up to H_TOTAL. '
             '16 + 47 + 57 + 520 = 640. If they don\'t, simulation stops immediately.'),
        (56, '  assert BROAD_W + H_SYNC_W = HALF',
             'SAFETY CHECK: broad sync width + H-sync width must equal half-line length. '
             '273 + 47 = 320. This ensures the broad sync fills exactly one half-line.'),
    ])

    code_block_explain(doc, [
        (61, '  process(h_cnt, v_cnt)',
             'This process re-runs every time h_cnt or v_cnt changes. '
             'Since there is no rising_edge(clk) here, this is COMBINATIONAL logic — '
             'it responds instantly (no clock delay).'),
        (62, '    variable hp      : integer range 0 to HALF - 1;',
             'LOCAL variable: half-line pixel position (0 to 319). '
             'hp = h_cnt if in first half, hp = h_cnt - 320 if in second half. '
             'Variables are LOCAL to the process and update INSTANTLY.'),
        (63, '    variable first_h : boolean;',
             'LOCAL variable: TRUE if we are in the first half of the line (h_cnt < 320). '
             'PAL vsync pulses repeat every half-line, so we need to know which half.'),
        (64, '    variable f1p, f1b, f1q : boolean;',
             'LOCAL variables for Field 1: f1p=pre-eq, f1b=broad-sync, f1q=post-eq. '
             'Each is TRUE when we are in that vsync region.'),
        (65, '    variable f2p, f2b, f2q : boolean;',
             'LOCAL variables for Field 2: same three regions for the second field.'),
        (66, '    variable in_eq, in_brd  : boolean;',
             'Combined flags: in_eq=TRUE if any equalising pulse is active (F1 or F2), '
             'in_brd=TRUE if any broad sync is active.'),
    ])

    code_block_explain(doc, [
        (68, '    first_h := (h_cnt < HALF);',
             'Calculate: are we in the first half of the line? '
             'TRUE if h_cnt < 320 (first 32 µs), FALSE if h_cnt >= 320 (second 32 µs). '
             ':= is variable assignment — takes effect immediately, no clock delay.'),
        (69, '    if first_h then hp := h_cnt; else hp := h_cnt - HALF; end if;',
             'Calculate hp = position within the current half-line. '
             'First half: hp = h_cnt (0-319). '
             'Second half: hp = h_cnt - 320 (also 0-319). '
             'This allows the same pulse-width check to work for both halves.'),
    ])

    code_block_explain(doc, [
        (77, '    f1p := (v_cnt = 0) or (v_cnt = 1) or (v_cnt = 2 and first_h);',
             'Field 1 pre-equalising: TRUE during lines 0, 1, and the FIRST HALF '
             'of line 2. That is 2 full lines + 1 half = 2.5 lines = 5 half-lines. '
             'PAL spec requires 5 equalising pulses before broad sync.'),
        (78, '    f1b := (v_cnt = 2 and not first_h) or (v_cnt = 3) or (v_cnt = 4);',
             'Field 1 broad sync: TRUE during the SECOND HALF of line 2, '
             'all of line 3, and all of line 4 = 0.5 + 1 + 1 = 2.5 lines = 5 half-lines.'),
        (79, '    f1q := (v_cnt = 5) or (v_cnt = 6) or (v_cnt = 7 and first_h);',
             'Field 1 post-equalising: TRUE during lines 5, 6, and FIRST HALF '
             'of line 7 = 2.5 lines = 5 half-lines.'),
    ], bg=C_YELLOW)

    code_block_explain(doc, [
        (87, '    f2p := (v_cnt = 312 and not first_h) or (v_cnt = 313) or (v_cnt = 314);',
             'Field 2 pre-equalising: TRUE from the SECOND HALF of line 312 '
             '(h>=320) through all of lines 313 and 314 = 2.5 lines. '
             'Field 2 starts half a line AFTER Field 1 ends (at h=320 of line 312).'),
        (88, '    f2b := (v_cnt = 315) or (v_cnt = 316) or (v_cnt = 317 and first_h);',
             'Field 2 broad sync: all of lines 315, 316, and FIRST HALF '
             'of line 317 = 2.5 lines = 5 half-lines.'),
        (89, '    f2q := (v_cnt = 317 and not first_h) or (v_cnt = 318) or (v_cnt = 319);',
             'Field 2 post-equalising: SECOND HALF of line 317 through all '
             'of lines 318 and 319 = 2.5 lines = 5 half-lines.'),
    ], bg=C_GREEN)

    code_block_explain(doc, [
        (91, '    in_eq  := f1p or f1q or f2p or f2q;',
             'in_eq is TRUE if we are in ANY equalising pulse region '
             '(either field, either pre-eq or post-eq group).'),
        (92, '    in_brd := f1b or f2b;',
             'in_brd is TRUE if we are in ANY broad sync region.'),
    ])

    code_block_explain(doc, [
        (95, '    if in_eq and hp < EQ_W then csync <= \'1\';',
             'EQUALISING PULSE: if we are in an equalising region AND the '
             'half-line position (hp) is less than 23, output a sync pulse. '
             'This creates a narrow 2.3 µs pulse at the start of each half-line '
             'during pre-eq and post-eq periods.'),
        (97, '    elsif in_brd and hp < BROAD_W then csync <= \'1\';',
             'BROAD SYNC PULSE: if we are in a broad sync region AND hp < 273, '
             'output a sync pulse. This fills almost the entire half-line (27.3 µs) '
             'with a sync pulse — this is what tells the TV "vertical sync is happening".'),
        (99, '    elsif not (in_eq or in_brd)',
             'NORMAL H-SYNC: only if we are NOT in any vsync period...'),
        (100,'      and h_cnt >= H_FRONT and h_cnt < H_FRONT + H_SYNC_W then',
             '...AND h_cnt is in the sync window (h_cnt = 16 to 62), '
             'output a normal H-sync pulse (4.7 µs).'),
        (101,'      csync <= \'1\';',
             'Assert the sync output — this line is at sync tip level (0V on DAC).'),
        (103,'    else csync <= \'0\';',
             'All other times: csync is \'0\' (no sync pulse — DAC outputs blank or video).'),
    ], bg=C_ORANGE)

    code_block_explain(doc, [
        (107,'    if v_cnt > 312 or (v_cnt = 312 and not first_h) then',
             'FIELD INDICATOR: we are in Field 2 if: '
             'v_cnt is past line 312, OR we are in line 312 but in the second half '
             '(h >= 320). Field 2 starts exactly at h=320 of line 312.'),
        (108,'      field <= \'1\';',
             'Output field = \'1\' to indicate we are in Field 2.'),
        (110,'      field <= \'0\';',
             'Otherwise: field = \'0\' (we are in Field 1).'),
    ])

    code_block_explain(doc, [
        (114,'    if (v_cnt >= V_ACT_S_F1 and v_cnt <= V_ACT_E_F1 and h_cnt >= H_ACT_S) or',
             'ACTIVE PIXEL CHECK for Field 1: '
             'v_cnt must be in the active range (25 to 311 after our fix) AND '
             'h_cnt must be past the blanking interval (h_cnt >= 120).'),
        (115,'       (v_cnt >= V_ACT_S_F2 and v_cnt <= V_ACT_E_F2 and h_cnt >= H_ACT_S)',
             'OR active pixel check for Field 2: '
             'v_cnt in range 337-623 AND h_cnt >= 120.'),
        (116,'      active <= \'1\';',
             'If either condition is true, we are in the active picture area. '
             'The pattern generator output will be sent to the DAC.'),
        (118,'      active <= \'0\';',
             'Not in active area — DAC outputs blank level instead.'),
    ])

    note(doc,
         'pal_csync_il has NO clock input. It is a pure combinational circuit. '
         'Whenever h_cnt or v_cnt changes (driven by pal_timing), the outputs '
         'csync, field, and active update immediately.')

    doc.add_page_break()


# ===========================================================================
# Chapter 5 — pal_tv_bram_lite_v2.vhd
# ===========================================================================
def ch_bram_lite(doc):
    heading(doc, 'Chapter 5 — pal_tv_bram_lite_v2.vhd', 1)
    section_banner(doc,
                   'tv/bram/pal_tv_bram_lite_v2.vhd',
                   'The main video core: combines pal_timing + pal_csync_il, '
                   'adds a BRAM frame buffer and 7 test patterns, and drives '
                   'all output signals (DAC, csync, line_sync, frame_sync, fss, '
                   'field, active, blank).')

    heading(doc, '5.1  Block Diagram', 2)
    body(doc,
         'Think of pal_tv_bram_lite_v2 as a TV signal generator with these blocks:')
    rows = [
        ('pal_timing (inside)',   'Counts h_cnt (0-639) and v_cnt (0-624)'),
        ('pal_csync_il (inside)', 'Generates csync, field, active from counters'),
        ('Pattern generators',    '7 different test patterns (bars, gradients, BRAM)'),
        ('Pattern mux',           'Selects which pattern goes to the DAC based on sel input'),
        ('DAC output logic',      'Sync tip / active video / blank level priority'),
        ('Sync output logic',     'line_sync, frame_sync, fss, blank outputs'),
    ]
    tbl = doc.add_table(rows=len(rows)+1, cols=2)
    tbl.style = 'Table Grid'
    for ci, h_ in enumerate(['Block', 'Function']):
        set_cell_bg(tbl.rows[0].cells[ci], C_NAVY)
        cp(tbl.rows[0].cells[ci], h_, bold=True, color=C_WHITE)
    for i, (b, f) in enumerate(rows):
        r = tbl.rows[i+1]
        set_cell_bg(r.cells[0], C_LTBLUE)
        cp(r.cells[0], b, bold=True)
        cp(r.cells[1], f)
    doc.add_paragraph()

    heading(doc, '5.2  Entity (Ports and Generics)', 2)

    code_block_explain(doc, [
        (29,  'entity pal_tv_bram_lite_v2 is',
              'Start the interface definition for the main video core.'),
        (31,  '  H_FRONT    : integer := 16;',
              'Front porch width = 16 px = 1.6 µs.'),
        (32,  '  H_SYNC_W   : integer := 47;',
              'H-sync pulse width = 47 px = 4.7 µs. '
              '(Changed to 100 in some builds to match old tester 10 µs LS.)'),
        (33,  '  H_BACK     : integer := 57;',
              'Back porch = 57 px = 5.7 µs.'),
        (34,  '  H_ACTIVE   : integer := 520;',
              'Active pixels per line = 520 px = 52 µs.'),
        (35,  '  H_TOTAL    : integer := 640;',
              'Total pixels per line = 640 px = 64 µs.'),
        (36,  '  V_TOTAL    : integer := 625;',
              'Total lines per frame = 625 lines × 64 µs = 40 ms.'),
        (37,  '  LEVEL_SYNC : std_logic_vector(3 downto 0) := "0000";',
              'DAC code for sync tip = 0x0 = 0 V on the R-2R ladder.'),
        (38,  '  LEVEL_BLANK: std_logic_vector(3 downto 0) := "0100";',
              'DAC code for blanking level = 0x4 = approx 0.3 V.'),
        (40,  '  CLK_MHZ    : integer := 40;',
              'Board clock frequency. Default 40 MHz (common FPGA board speed). '
              'Internal divider keeps pixel rate at 10 MHz.'),
        (41,  '  STRIPE_W   : integer := 4;',
              'Width of stripes in the bar pattern (sel=0/1) in pixels.'),
        (42,  '  BRAM_DEPTH : integer := 299520',
              'Size of the frame buffer = 520 × 576 = 299,520 pixels. '
              '520 active pixels × 576 active lines = one full interlaced frame.'),
    ])

    code_block_explain(doc, [
        (45,  '  clk          : in  std_logic;',
              'INPUT: board clock (10/20/30/40 MHz).'),
        (46,  '  rst          : in  std_logic;',
              'INPUT: synchronous reset. \'1\' resets all counters to zero.'),
        (48,  '  sel          : in  std_logic_vector(7 downto 0);',
              'INPUT: 8-bit pattern select. Only bits [2:0] are used (values 0-6). '
              '0=V-bars, 1=H-bars, 2=H-gradient, 3=V-gradient, 4=BRAM, '
              '5=H-gradient+black-end, 6=V-gradient+black-end.'),
        (50,  '  brightness   : in  std_logic_vector(3 downto 0) := "1111";',
              'INPUT: white/peak brightness level for the pattern (0x0-0xF). '
              'Default 0xF = maximum white.'),
        (51,  '  black_lvl    : in  std_logic_vector(3 downto 0) := "0100";',
              'INPUT: black level for the pattern. Default 0x4 = blanking level.'),
        (53,  '  bram_wr_en   : in  std_logic                     := \'0\';',
              'INPUT: BRAM write enable. \'1\' = write one pixel to BRAM.'),
        (54,  '  bram_wr_addr : in  std_logic_vector(18 downto 0) := (others => \'0\');',
              'INPUT: BRAM write address (19 bits = can address up to 524288 locations).'),
        (55,  '  bram_wr_data : in  std_logic                     := \'0\';',
              'INPUT: pixel data to write (1 bit: 0=black, 1=white).'),
        (56,  '  bram_len     : in  std_logic_vector(18 downto 0) := (others => \'1\');',
              'INPUT: how many pixels are valid in BRAM. Read address wraps at this limit.'),
    ])

    code_block_explain(doc, [
        (58,  '  dac_out      : out std_logic_vector(3 downto 0);',
              'OUTPUT: 4-bit value to the R-2R DAC. This IS the video signal. '
              '0x0=sync, 0x4=blank, 0x5-0xF=video levels.'),
        (59,  '  csync_o      : out std_logic;',
              'OUTPUT: composite sync signal. \'1\' during sync pulses.'),
        (60,  '  line_sync_o  : out std_logic;',
              'OUTPUT: line sync (H-sync). \'1\' during the H-sync pulse on '
              'normal video lines. Goes to \'0\' during vertical sync period.'),
        (61,  '  frame_sync_o : out std_logic;',
              'OUTPUT: frame sync at 25 Hz. \'1\' during Field 1 vsync only '
              '(v_cnt 0-7). Fires once per complete frame.'),
        (62,  '  fss_o        : out std_logic;',
              'OUTPUT: Field Sync Signal at 50 Hz. \'1\' during broad-sync + '
              'post-equalising of BOTH fields. Used by avionics equipment.'),
        (63,  '  field_o      : out std_logic;',
              'OUTPUT: field indicator from pal_csync_il. \'0\'=Field1, \'1\'=Field2.'),
        (64,  '  active_o     : out std_logic;',
              'OUTPUT: active pixel flag. \'1\' when displaying picture pixels.'),
        (65,  '  blank_o      : out std_logic',
              'OUTPUT: composite blank. \'1\' during ALL blanking (H-blank + V-blank). '
              'Implemented as NOT active_s.'),
    ])

    heading(doc, '5.3  Architecture — Internal Signals', 2)

    code_block_explain(doc, [
        (71,  '  constant H_ACT_S : integer := H_FRONT + H_SYNC_W + H_BACK;',
              'Pixel position where active video starts in a line. '
              '= 16 + 47 + 57 = 120. Active pixels are h_cnt = 120 to 639.'),
        (74,  '  constant V_ACT_S_F1 : integer := 25;',
              'First active video line in Field 1 (v_cnt=25 = oscilloscope line 24). '
              'Was 24 in original code — shifted +1 to match old tester reference.'),
        (75,  '  constant V_ACT_E_F1 : integer := 311;',
              'Last active line in Field 1. Lines 25-311 = 287 active lines.'),
        (76,  '  constant V_ACT_S_F2 : integer := 337;',
              'First active line in Field 2 (v_cnt=337 = oscilloscope line 336 blank). '
              'Was 336 — shifted +1 to match old tester.'),
        (77,  '  constant V_ACT_E_F2 : integer := 623;',
              'Last active line in Field 2. Lines 337-623 = 287 active lines.'),
        (78,  '  constant V_FRAME_S  : integer := V_ACT_S_F1;',
              'Alias for V_ACT_S_F1 used in counter reset conditions. '
              'Updates automatically when V_ACT_S_F1 changes.'),
        (80,  '  constant V_ACTIVE_F : integer := 288;',
              'Lines per field used for zone-height calculations. '
              'Kept at 288 even though actual active lines is 287, to avoid '
              'changing zone boundary mathematics.'),
    ])

    code_block_explain(doc, [
        (86,  '  constant GZONES  : integer := 10;',
              'Number of gradient zones for sel=2/3 (10-step grey staircase).'),
        (87,  '  constant GZONE_W : integer := H_ACTIVE / GZONES;',
              'Width of each gradient zone = 520 ÷ 10 = 52 pixels.'),
        (88,  '  constant GZONE_H : integer := V_ACTIVE_F / GZONES;',
              'Height of each gradient zone = 288 ÷ 10 = 28 lines.'),
        (90,  '  constant GZONES_B  : integer := 11;',
              'Number of gradient zones for sel=5/6 (10 grey steps + 1 black end).'),
        (91,  '  constant GZONE_W_B : integer := H_ACTIVE / GZONES_B;',
              'Width per zone for 11-zone: 520 ÷ 11 = 47 pixels.'),
        (92,  '  constant GZONE_H_B : integer := V_ACTIVE_F / GZONES_B;',
              'Height per zone for 11-zone: 288 ÷ 11 = 26 lines.'),
    ])

    heading(doc, '5.4  Sub-Module Instantiations', 2)
    body(doc,
         'The architecture "instantiates" (connects) pal_timing and pal_csync_il '
         'as sub-modules. Think of it like plugging chips into a PCB.')

    code_block_explain(doc, [
        (183, '  u_timing : entity work.pal_timing',
              'Create an instance of pal_timing called u_timing. '
              'work refers to the current design library.'),
        (184, '    generic map (H_TOTAL => H_TOTAL, V_TOTAL => V_TOTAL, CLK_MHZ => CLK_MHZ)',
              'Pass the generic parameters to pal_timing. '
              'The values from our entity generics are forwarded.'),
        (185, '    port map (clk => clk, rst => rst, ce => ce_s,',
              'Connect our clk and rst inputs to pal_timing\'s clk and rst. '
              'The ce output of pal_timing feeds our internal ce_s signal.'),
        (186, '              h_cnt => h_cnt, v_cnt => v_cnt);',
              'Connect pal_timing\'s counter outputs to our internal h_cnt, v_cnt signals.'),
    ])

    code_block_explain(doc, [
        (191, '  u_csync : entity work.pal_csync_il',
              'Create an instance of pal_csync_il called u_csync.'),
        (192, '    generic map (H_FRONT => H_FRONT, H_SYNC_W => H_SYNC_W, ...',
              'Pass all timing parameters to pal_csync_il, including '
              'V_ACT_S_F1=25 and V_ACT_S_F2=337.'),
        (197, '    port map (h_cnt => h_cnt, v_cnt => v_cnt,',
              'Feed our internal h_cnt and v_cnt to pal_csync_il.'),
        (198, '              csync => csync_s, field => field_s, active => active_s);',
              'Receive csync, field, active outputs into our internal signals.'),
    ])

    heading(doc, '5.5  Pattern Generators', 2)
    body(doc,
         'Each pattern generator is a separate process (block of logic) that '
         'counts pixels and lines within the active video area. '
         'All pattern generators run in PARALLEL — they all count simultaneously. '
         'The pattern mux (sel input) chooses which one drives the DAC.')

    code_block_explain(doc, [
        (210, '  process(clk)  -- Vertical bar generator',
              'The V-bar generator (sel=0) process. Runs on every clock edge.'),
        (216, '    if h_cnt = H_ACT_S - 1 and in_any_active then',
              'When we reach the pixel just BEFORE the active area starts '
              '(h_cnt=119), and we are on an active line: reset zone counter '
              'to 0 so the pattern always starts from the left edge.'),
        (218, '    elsif active_s = \'1\' then',
              'While in the active pixel area: count pixels within zones.'),
        (219, '      if px_in_zone = ZONE_W - 1 then',
              'If we have filled one zone width (64 pixels for 8 zones)...'),
        (220, '        if zone_idx_v < NUM_ZONES - 1 then zone_idx_v <= zone_idx_v + 1;',
              '...move to the next zone (0-7). This advances the grey level.'),
    ])

    code_block_explain(doc, [
        (263, '  process(clk)  -- Horizontal gradient generator (sel=2)',
              'Generates a 10-step horizontal grey gradient. '
              'The zone index (gzx_idx) increases with each zone, '
              'and the grey level is calculated from that index.'),
        (305, '  process(clk)  -- Horizontal gradient-B generator (sel=5)',
              'Same as sel=2 but with 11 zones. Zone 10 outputs black_level.'),
    ])

    heading(doc, '5.6  BRAM Frame Buffer (sel=4)', 2)

    code_block_explain(doc, [
        (102, '  type bram_t is array (0 to BRAM_DEPTH - 1) of std_logic;',
              'Define a data type: an array of 299,520 single-bit values. '
              'Each element is one pixel (0=black, 1=white).'),
        (103, '  signal bram_mem : bram_t := (others => \'0\');',
              'Create the BRAM memory as an internal signal, initialised to all zeros '
              '(all black pixels). The synthesiser maps this to FPGA block RAM.'),
        (104, '  attribute ram_style : string;',
              'Declare a synthesis attribute (a hint to the FPGA tools).'),
        (105, '  attribute ram_style of bram_mem : signal is "block";',
              'Tell the FPGA synthesiser to implement bram_mem as Block RAM '
              '(dedicated hardware RAM tiles) not as flip-flops. Block RAM is '
              'much more efficient for large memories.'),
    ])

    code_block_explain(doc, [
        (354, '  process(clk)  -- BRAM write',
              'Synchronous write process: runs on every clock edge.'),
        (357, '    if bram_wr_en = \'1\' and',
              'If the host has asserted write enable...'),
        (358, '       to_integer(unsigned(bram_wr_addr)) < BRAM_DEPTH then',
              '...and the address is within bounds (< 299,520)...'),
        (359, '      bram_mem(to_integer(unsigned(bram_wr_addr))) <= bram_wr_data;',
              '...write the 1-bit pixel data into BRAM at the given address. '
              'to_integer(unsigned(...)) converts the std_logic_vector address '
              'to a plain integer for array indexing.'),
    ])

    code_block_explain(doc, [
        (376, '    if v_cnt = V_FRAME_S - 1 and h_cnt = H_TOTAL - 1 then',
              'At the very last pixel of the line BEFORE Field 1 active video '
              'starts (v_cnt=24, h_cnt=639): reset the BRAM read address to 0. '
              'This ensures BRAM always starts reading from pixel 0 at the top of F1.'),
        (378, '    elsif v_cnt = V_ACT_S_F2 - 1 and h_cnt = H_TOTAL - 1 then',
              'At the last pixel before Field 2 active video starts: '
              'reset base address to H_ACTIVE (520). '
              'F2 reads starting from image row 1 (interlaced even lines).'),
        (380, '    elsif in_any_active and h_cnt = H_TOTAL - 1 then',
              'At the end of each active line: advance the base address by '
              '2 × H_ACTIVE = 1040. The ×2 is because interlaced video skips '
              'every other line (F1 reads rows 0,2,4,...; F2 reads rows 1,3,5,...).'),
    ])

    heading(doc, '5.7  Brightness and Grey Level Calculation', 2)

    code_block_explain(doc, [
        (408, '  white_level_i <= 4 when unsigned(brightness) < 4',
              'Clamp brightness to minimum 4 (= blank level). '
              'This prevents the "white" level from going below blank, '
              'which would make pixels invisible.'),
        (422, '  process(white_level_i, black_level_i, gzx_idx, gzy_idx)',
              'Calculate the grey level for each gradient zone. '
              'This process runs whenever zone index or brightness changes.'),
        (426, '    rng := white_level_i - black_level_i;',
              'rng = the usable DAC range (e.g. 15 - 4 = 11 levels for full range).'),
        (430, '    lx := black_level_i + (gzx_idx * rng + 4) / 9;',
              'Calculate the grey level for horizontal zone gzx_idx. '
              'Divides the range into 9 equal steps (for 10 zones, steps 0-9). '
              'The "+4" rounds to nearest integer. '
              'Zone 0 = black_level, Zone 9 = white_level.'),
    ])

    heading(doc, '5.8  Pattern Multiplexer', 2)

    code_block_explain(doc, [
        (469, '  active_level <= bram_level  when sel_i = 4 else',
              'If sel=4, use BRAM pixel data as the video level.'),
        (470, '                  grad_x_s    when sel_i = 2 else',
              'If sel=2, use horizontal gradient (10 zones, ends white).'),
        (471, '                  grad_y_s    when sel_i = 3 else',
              'If sel=3, use vertical gradient (10 zones, ends white).'),
        (472, '                  grad_xb_s   when sel_i = 5 else',
              'If sel=5, use horizontal gradient with black end (11 zones).'),
        (473, '                  grad_yb_s   when sel_i = 6 else',
              'If sel=6, use vertical gradient with black end (11 zones).'),
        (474, '                  white_s     when sel_i = 0 and color_v = \'1\' else',
              'If sel=0 and we are in a white bar zone: output white.'),
        (475, '                  black_s     when sel_i = 0 else',
              'If sel=0 and we are in a black bar zone: output black.'),
        (476, '                  white_s     when sel_i = 1 and color_h = \'1\' else',
              'If sel=1 and we are in a white H-bar zone: output white.'),
        (477, '                  black_s;',
              'Otherwise (sel=1, black zone): output black level.'),
    ])

    heading(doc, '5.9  DAC Output Priority', 2)
    body(doc,
         'The DAC output has three priority levels. Sync always wins, '
         'then picture, then blank.')

    code_block_explain(doc, [
        (482, '  dac_out <= LEVEL_SYNC   when csync_s  = \'1\' else',
              'HIGHEST PRIORITY: if csync is active, output sync tip (0x0 = 0 V). '
              'Sync overrides everything — this is what creates the sync pulses '
              'in the composite video signal.'),
        (483, '             active_level when active_s = \'1\' else',
              'SECOND PRIORITY: if in active pixel area, output the pattern level. '
              'This is the actual picture content (0x4 to 0xF).'),
        (484, '             LEVEL_BLANK;',
              'LOWEST PRIORITY: all other times (blanking), output 0x4 (blank level). '
              'This covers: front porch, back porch, and vertical blanking lines.'),
    ], bg=C_ORANGE)

    heading(doc, '5.10  Sync Output Signals', 2)

    code_block_explain(doc, [
        (489, '  in_vsync_s <= \'1\' when (v_cnt <= 7) or (v_cnt >= 312 and v_cnt <= 319)',
              'in_vsync_s is TRUE during the entire vertical sync period of both fields: '
              'v_cnt 0-7 (Field 1 vsync) and v_cnt 312-319 (Field 2 vsync).'),
        (492, '  line_sync_s  <= \'1\' when h_cnt >= H_FRONT and',
              'line_sync_o fires when: we are at the H-sync position in the line...'),
        (493, '                          h_cnt < H_FRONT + H_SYNC_W and',
              '...and h_cnt is within the sync window (h=16 to 62)...'),
        (494, '                          in_vsync_s = \'0\'',
              '...and we are NOT in the vertical sync period. '
              'During vsync, line_sync is suppressed (the composite sync handles it).'),
        (497, '  frame_sync_s <= \'1\' when v_cnt <= 7 else \'0\';',
              'frame_sync fires only during Field 1 vsync (v_cnt 0-7). '
              'This gives a 25 Hz pulse — once per complete frame. '
              'Field 2 vsync (v_cnt 312-319) does NOT trigger frame_sync.'),
    ])

    code_block_explain(doc, [
        (500, '  fss_s <= \'1\' when (v_cnt >= 3 and v_cnt <= 7) or',
              'FSS Field 1: HIGH during v_cnt 3-7 (broad-sync + post-eq of Field 1). '
              'Lines 0-2 are pre-equalising — NOT part of FSS.'),
        (501, '                  (v_cnt = 315 and h_cnt >= 320) or',
              'FSS Field 2 START: at v_cnt=315, FSS goes HIGH only from h=320 '
              '(the second half of the line). This matches the half-line offset '
              'of Field 2 — the old tester shows FSS starting at scope line 314 '
              'last half, not first half.'),
        (502, '                  (v_cnt >= 316 and v_cnt <= 319) or',
              'FSS Field 2 MIDDLE: lines 316-319 are fully in FSS.'),
        (503, '                  (v_cnt = 320 and h_cnt < 320)',
              'FSS Field 2 END: at v_cnt=320, FSS stays HIGH until the midpoint '
              '(h=319) then goes LOW. This gives exactly 5 full lines = 320 µs. '
              'Together with the h>=320 start, the total F2 FSS is: '
              '(half of 315) + 316,317,318,319 + (half of 320) = 5 lines = 320 µs.'),
    ], bg=C_YELLOW)

    code_block_explain(doc, [
        (504, '  csync_o      <= csync_s;',
              'Connect internal csync to output port.'),
        (505, '  line_sync_o  <= line_sync_s;',
              'Connect line sync to output port.'),
        (506, '  frame_sync_o <= frame_sync_s;',
              'Connect frame sync (25 Hz) to output port.'),
        (507, '  fss_o        <= fss_s;',
              'Connect FSS (50 Hz) to output port.'),
        (508, '  field_o      <= field_s;',
              'Connect field indicator to output port.'),
        (509, '  active_o     <= active_s;',
              'Connect active-pixel flag to output port.'),
        (510, '  blank_o      <= not active_s;',
              'blank_o is the INVERSE of active_s. '
              'blank_o = \'1\' whenever we are NOT in the active picture area '
              '(= during H-blanking and V-blanking). '
              '"not" inverts a std_logic signal.'),
    ])

    doc.add_page_break()


# ===========================================================================
# Chapter 6 — Signal Summary
# ===========================================================================
def ch_summary(doc):
    heading(doc, 'Chapter 6 — Complete Signal Reference', 1)
    body(doc,
         'This table lists every output signal from pal_tv_bram_lite_v2 '
         'with its meaning, rate, and logic.')

    rows = [
        ('dac_out[3:0]', '4-bit',
         'Composite video to R-2R DAC. '
         '0x0=sync tip, 0x4=blank, 0x5-0xF=picture.'),
        ('csync_o', 'Composite sync',
         '\'1\' during sync pulses (H-sync, equalising, broad sync). '
         'Goes to DAC as 0V sync tip level.'),
        ('line_sync_o', '15,625 Hz',
         '\'1\' during H-sync pulse on normal video lines. '
         'Suppressed during vsync (v_cnt 0-7 and 312-319).'),
        ('frame_sync_o', '25 Hz',
         '\'1\' during Field 1 vsync only (v_cnt 0-7). '
         'Fires once per complete frame.'),
        ('fss_o', '50 Hz',
         '\'1\' during broad-sync + post-equalising of both fields. '
         'F1: v_cnt 3-7. F2: v_cnt 315(h>=320) to 320(h<320). '
         '320 µs per field. Used by avionics LRU for timing lock.'),
        ('field_o', 'Flag',
         '\'0\' = Field 1 (top half of frame), \'1\' = Field 2 (bottom half). '
         'Transitions at v_cnt=312, h=320.'),
        ('active_o', 'Flag',
         '\'1\' during active picture pixels. '
         'F1: v_cnt 25-311, h 120-639. F2: v_cnt 337-623, h 120-639.'),
        ('blank_o', 'Flag',
         '\'1\' during ALL blanking (H-blank + V-blank). '
         'Equals NOT active_o. HIGH for 12 µs H-blank + all V-blank lines.'),
    ]
    tbl = doc.add_table(rows=len(rows)+1, cols=3)
    tbl.style = 'Table Grid'
    tbl.columns[0].width = Inches(1.3)
    tbl.columns[1].width = Inches(1.2)
    tbl.columns[2].width = Inches(4.3)
    for ci, h_ in enumerate(['Signal', 'Rate / Type', 'Description']):
        set_cell_bg(tbl.rows[0].cells[ci], C_NAVY)
        cp(tbl.rows[0].cells[ci], h_, bold=True, color=C_WHITE)
    for i, (s, r, d) in enumerate(rows):
        row = tbl.rows[i+1]
        set_cell_bg(row.cells[0], C_LTBLUE)
        cp(row.cells[0], s, font='Courier New', size=9, bold=True)
        cp(row.cells[1], r, italic=True, size=9)
        cp(row.cells[2], d, size=9.5)
    doc.add_paragraph()

    heading(doc, '6.1  Oscilloscope Line Reference', 2)
    body(doc,
         'When measuring on an oscilloscope with 1-625 line numbering:')
    osc = [
        ('1-3',   'F1 pre-equalising pulses (5 half-lines in v_cnt 0-2)'),
        ('4-7',   'F1 broad sync + post-eq — FSS HIGH (F1 FSS = 320 µs)'),
        ('8-24',  'F1 back porch / guard lines (all blank)'),
        ('24',    'F1 last blank line (old tester reference)'),
        ('25-312','F1 active video (287 lines, 287 × 64 µs = 18.4 ms)'),
        ('313',   'F2 transition line (first half F1, second half F2 pre-eq)'),
        ('314-316','F2 pre-equalising + start of broad sync'),
        ('316-320','F2 FSS HIGH — starts at scope 314 last half (h=320)'),
        ('321-337','F2 back porch / guard lines (all blank)'),
        ('337',   'F2 last blank line — scope line 336 is blank on old tester'),
        ('338-624','F2 active video (287 lines)'),
        ('625',   'Last line of frame — wraps to scope line 1 of next frame'),
    ]
    tbl2 = doc.add_table(rows=len(osc)+1, cols=2)
    tbl2.style = 'Table Grid'
    for ci, h_ in enumerate(['Scope lines (1-625 ref)', 'Content']):
        set_cell_bg(tbl2.rows[0].cells[ci], C_MID)
        cp(tbl2.rows[0].cells[ci], h_, bold=True, color=C_WHITE)
    for i, (s, c) in enumerate(osc):
        r = tbl2.rows[i+1]
        set_cell_bg(r.cells[0], C_LTBLUE)
        cp(r.cells[0], s, font='Courier New', size=9, bold=True)
        cp(r.cells[1], c, size=9.5)
    doc.add_paragraph()


# ===========================================================================
# Main
# ===========================================================================
def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    doc = Document()
    for sec in doc.sections:
        sec.top_margin    = Inches(0.9)
        sec.bottom_margin = Inches(0.9)
        sec.left_margin   = Inches(1.0)
        sec.right_margin  = Inches(1.0)

    make_title(doc)
    ch_pal_concepts(doc)
    ch_vhdl_intro(doc)
    ch_timing(doc)
    ch_csync(doc)
    ch_bram_lite(doc)
    ch_summary(doc)

    doc.save(OUT_FILE)
    print(f'Saved: {OUT_FILE}  ({os.path.getsize(OUT_FILE):,} bytes)')


if __name__ == '__main__':
    main()
