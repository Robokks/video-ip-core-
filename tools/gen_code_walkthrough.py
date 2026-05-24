#!/usr/bin/env python3
"""
gen_code_walkthrough.py
Generate docs/CODE_WALKTHROUGH.docx  —  line-by-line / block-by-block explanation
of every VHDL source file in the PAL/NTSC Video IP Core project.
"""

import os
from docx import Document
from docx.shared import Pt, Inches, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn
from docx.oxml import OxmlElement

OUT_DIR  = os.path.join(os.path.dirname(__file__), '..', 'docs')
OUT_FILE = os.path.join(OUT_DIR, 'CODE_WALKTHROUGH.docx')

# ---------------------------------------------------------------------------
# Colour palette
# ---------------------------------------------------------------------------
C_NAVY   = RGBColor(0x00, 0x27, 0x5A)
C_MID    = RGBColor(0x00, 0x5B, 0x96)
C_STEEL  = RGBColor(0x4A, 0x7C, 0xB4)
C_LTBLUE = RGBColor(0xD6, 0xE4, 0xF7)
C_CODEBG = RGBColor(0xF2, 0xF2, 0xF2)
C_WHITE  = RGBColor(0xFF, 0xFF, 0xFF)
C_BLACK  = RGBColor(0x00, 0x00, 0x00)
C_AMBER  = RGBColor(0xFF, 0xC0, 0x00)


def set_cell_bg(cell, rgb):
    tc   = cell._tc
    tcPr = tc.get_or_add_tcPr()
    shd  = OxmlElement('w:shd')
    shd.set(qn('w:val'),   'clear')
    shd.set(qn('w:color'), 'auto')
    shd.set(qn('w:fill'),  f'{rgb[0]:02X}{rgb[1]:02X}{rgb[2]:02X}')
    tcPr.append(shd)


def cp(cell, text, bold=False, italic=False, size=10, color=C_BLACK,
       font='Calibri', align=WD_ALIGN_PARAGRAPH.LEFT):
    para = cell.paragraphs[0] if cell.paragraphs else cell.add_paragraph()
    para.alignment = align
    run = para.add_run(text)
    run.bold   = bold
    run.italic = italic
    run.font.size  = Pt(size)
    run.font.color.rgb = color
    run.font.name  = font
    return para


def heading(doc, text, level=1):
    styles = {1: ('Heading 1', C_NAVY, 16, True),
              2: ('Heading 2', C_MID,  13, True),
              3: ('Heading 3', C_STEEL, 11, True)}
    _, color, size, bold = styles.get(level, styles[1])
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(10 if level == 1 else 6)
    p.paragraph_format.space_after  = Pt(4)
    run = p.add_run(text)
    run.bold = bold
    run.font.color.rgb = color
    run.font.size = Pt(size)
    run.font.name = 'Calibri'
    return p


def body(doc, text, italic=False, space_after=4):
    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(space_after)
    run = p.add_run(text)
    run.italic = italic
    run.font.size = Pt(10)
    run.font.name = 'Calibri'
    return p


def code_block(doc, lines, note=None):
    """Render a code excerpt in a shaded monospace box."""
    text = lines if isinstance(lines, str) else '\n'.join(lines)
    tbl = doc.add_table(rows=1, cols=1)
    tbl.style = 'Table Grid'
    cell = tbl.rows[0].cells[0]
    set_cell_bg(cell, C_CODEBG)
    para = cell.paragraphs[0]
    para.paragraph_format.space_before = Pt(2)
    para.paragraph_format.space_after  = Pt(2)
    run = para.add_run(text)
    run.font.name = 'Courier New'
    run.font.size = Pt(8.5)
    run.font.color.rgb = RGBColor(0x1A, 0x1A, 0x1A)
    if note:
        np = doc.add_paragraph()
        np.paragraph_format.space_before = Pt(1)
        np.paragraph_format.space_after  = Pt(5)
        nr = np.add_run(f'  ▶  {note}')
        nr.italic = True
        nr.font.size = Pt(9)
        nr.font.color.rgb = C_STEEL
    return tbl


def file_banner(doc, filepath, purpose):
    tbl = doc.add_table(rows=1, cols=1)
    tbl.style = 'Table Grid'
    cell = tbl.rows[0].cells[0]
    set_cell_bg(cell, C_NAVY)
    para = cell.paragraphs[0]
    r1 = para.add_run(f'FILE:  {filepath}\n')
    r1.bold = True
    r1.font.color.rgb = C_AMBER
    r1.font.name = 'Courier New'
    r1.font.size = Pt(10)
    r2 = para.add_run(purpose)
    r2.font.color.rgb = C_WHITE
    r2.font.name = 'Calibri'
    r2.font.size = Pt(10)
    doc.add_paragraph()


def expl(doc, text):
    """Explanation paragraph — standard body with bullet indent."""
    p = doc.add_paragraph(style='Normal')
    p.paragraph_format.left_indent  = Inches(0.15)
    p.paragraph_format.space_after  = Pt(5)
    run = p.add_run(text)
    run.font.size = Pt(10)
    run.font.name = 'Calibri'
    return p


# ===========================================================================
# Title page
# ===========================================================================
def make_title(doc):
    doc.add_paragraph()
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.add_run('PAL / NTSC Video IP Core')
    r.bold = True; r.font.size = Pt(26); r.font.color.rgb = C_NAVY
    r.font.name = 'Calibri'

    p2 = doc.add_paragraph()
    p2.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r2 = p2.add_run('VHDL Source Code Walkthrough')
    r2.bold = True; r2.font.size = Pt(18); r2.font.color.rgb = C_MID
    r2.font.name = 'Calibri'

    doc.add_paragraph()
    p3 = doc.add_paragraph()
    p3.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r3 = p3.add_run(
        'A detailed block-by-block explanation of every VHDL source file.\n'
        'Covers entity declarations, architecture constants, every sequential\n'
        'process and combinational statement, and testbench structure.')
    r3.font.size = Pt(11); r3.font.color.rgb = C_STEEL; r3.font.name = 'Calibri'

    doc.add_paragraph()
    meta = [('Project', 'PAL/NTSC B&W Video IP Core'),
            ('Branch',  'claude/xilinx-pal-video-ip-RIDhJ'),
            ('Date',    '2026-05-24'),
            ('Version', '1.0')]
    tbl = doc.add_table(rows=len(meta), cols=2)
    tbl.style = 'Table Grid'
    for i, (k, v) in enumerate(meta):
        lc = tbl.rows[i].cells[0]; rc = tbl.rows[i].cells[1]
        set_cell_bg(lc, C_LTBLUE)
        cp(lc, k, bold=True)
        cp(rc, v)
    doc.add_page_break()


# ===========================================================================
# Section 1 — Project overview
# ===========================================================================
def sec_overview(doc):
    heading(doc, '1  Project Overview', 1)
    body(doc,
         'The Video IP Core is a VHDL-2008 design that generates PAL-625/50 or '
         'NTSC-525/60 interlaced analogue video via a 4-bit R-2R DAC ladder. '
         'It supports ten selectable test patterns, a BRAM frame-buffer with '
         'tear-free double-buffering, a bouncing ball animation, crosshatch grid, '
         'and a centre cross overlay.')

    heading(doc, '1.1  Source File Map', 2)
    files = [
        ('tv/pal_timing.vhd',
         'Free-running H/V raster counter shared by all variants. '
         'Generates clock-enable (ce) for 10 MHz pixel rate from 10/20/30/40 MHz input.'),
        ('tv/opt2_interlaced/pal_csync_il.vhd',
         'Purely combinational PAL composite sync + field + active generator. '
         'Implements the full equalising/broad-sync/post-eq PAL interlaced sequence.'),
        ('tv/bram/pal_tv_bram_top.vhd',
         'Top-level PAL-only BRAM video IP. Instantiates pal_timing + pal_csync_il, '
         'adds all 10 pattern generators and BRAM double-buffer.'),
        ('tv/bram/video_bram_top.vhd',
         'Runtime PAL/NTSC selectable variant (ntsc_mode port). '
         'Inlines timing and sync logic; adapts all counters to format at runtime.'),
        ('tv/bram/tb_bram_double_buf.vhd',
         'Self-checking VHDL-2008 testbench for the double-buffer.  '
         'Four phases verify initial state, swap, alternating pattern, '
         'and single-swap-per-V-blank enforcement.'),
    ]
    tbl = doc.add_table(rows=1 + len(files), cols=2)
    tbl.style = 'Table Grid'
    for i, (h_, t) in enumerate(['File', 'Purpose']), \
            enumerate(zip(['File', 'Purpose'], ['', ''])):
        pass
    hdr = tbl.rows[0].cells
    set_cell_bg(hdr[0], C_NAVY); set_cell_bg(hdr[1], C_NAVY)
    cp(hdr[0], 'File', bold=True, color=C_WHITE)
    cp(hdr[1], 'Purpose', bold=True, color=C_WHITE)
    for i, (fp, desc) in enumerate(files):
        r = tbl.rows[i + 1]
        set_cell_bg(r.cells[0], C_LTBLUE)
        cp(r.cells[0], fp, font='Courier New', size=9)
        cp(r.cells[1], desc)
    doc.add_paragraph()

    heading(doc, '1.2  Module Hierarchy', 2)
    body(doc,
         'pal_tv_bram_top  instantiates  pal_timing  (for ce/h_cnt/v_cnt) and '
         'pal_csync_il  (for csync/field/active).  video_bram_top is a standalone '
         'module that inlines equivalent logic and adds ntsc_mode switching.  '
         'tb_bram_double_buf instantiates pal_tv_bram_top as the device under test.')

    heading(doc, '1.3  DAC Level Encoding', 2)
    body(doc,
         'The 4-bit dac_out maps to analogue voltage via an R-2R ladder. '
         'Three standard levels are used:')
    lvl = [('0x0 (0000)', 'LEVEL_SYNC',  'Sync tip  — most negative voltage'),
           ('0x4 (0100)', 'LEVEL_BLANK', 'Blanking pedestal  — 0 V reference'),
           ('0xF (1111)', 'LEVEL_WHITE', 'Peak white  — maximum voltage')]
    tbl2 = doc.add_table(rows=1 + len(lvl), cols=3)
    tbl2.style = 'Table Grid'
    hdr2 = tbl2.rows[0].cells
    for ci, hd in enumerate(['DAC Value', 'Constant', 'Meaning']):
        set_cell_bg(hdr2[ci], C_MID)
        cp(hdr2[ci], hd, bold=True, color=C_WHITE)
    for i, (v, c, m) in enumerate(lvl):
        r = tbl2.rows[i + 1]
        cp(r.cells[0], v, font='Courier New')
        cp(r.cells[1], c, font='Courier New')
        cp(r.cells[2], m)
    doc.add_page_break()


# ===========================================================================
# Section 2 — pal_timing.vhd
# ===========================================================================
def sec_timing(doc):
    heading(doc, '2  pal_timing.vhd  —  H/V Raster Counter', 1)
    file_banner(doc,
                'tv/pal_timing.vhd',
                'Free-running horizontal and vertical raster counters. '
                'Shared by all three tv/ variants. Supports 10/20/30/40 MHz '
                'input clocks by dividing internally to 10 MHz pixel rate.')

    # --- Block 2.1 ---
    heading(doc, '2.1  Library Imports  (lines 1–2)', 2)
    code_block(doc, [
        'library ieee;',
        'use ieee.std_logic_1164.all;',
    ])
    expl(doc,
         'Every VHDL source file starts with these two lines. '
         '`library ieee` makes the IEEE standard library visible to the compiler. '
         '`use ieee.std_logic_1164.all` imports the std_logic type and all associated '
         'functions (and, or, not, xor, comparison operators). '
         'This package also defines std_logic_vector, used for multi-bit bus signals.')

    # --- Block 2.2 ---
    heading(doc, '2.2  Entity Declaration  (lines 10–23)', 2)
    code_block(doc, [
        'entity pal_timing is',
        '  generic (',
        '    H_TOTAL : integer := 640;   -- clocks per line at 10 MHz',
        '    V_TOTAL : integer := 625;   -- lines per frame',
        '    CLK_MHZ : integer := 10     -- input clock: 10, 20, 30 or 40',
        '  );',
        '  port (',
        '    clk   : in  std_logic;',
        '    rst   : in  std_logic;',
        '    ce    : out std_logic;',
        '    h_cnt : out integer range 0 to 639;',
        '    v_cnt : out integer range 0 to 624',
        '  );',
        'end entity pal_timing;',
    ])
    expl(doc,
         'The entity block defines the module\'s external interface — exactly like a '
         'function prototype in C.')
    expl(doc,
         'GENERICS are compile-time constants. H_TOTAL=640 means 640 pixel clocks '
         'per line; at 10 MHz that is 64 µs — exactly the PAL line period. '
         'V_TOTAL=625 gives 625 lines per frame (PAL standard). '
         'CLK_MHZ selects the board clock; the module divides it down to 10 MHz internally.')
    expl(doc,
         'PORTS are the wires connecting to the outside world. '
         'clk is the board clock input. rst is active-high synchronous reset. '
         'ce (clock-enable) pulses HIGH once every CLK_DIV cycles — downstream '
         'logic uses this to advance one pixel at a time. '
         'h_cnt counts 0..H_TOTAL-1 (horizontal position); '
         'v_cnt counts 0..V_TOTAL-1 (vertical line number).')

    # --- Block 2.3 ---
    heading(doc, '2.3  Architecture Constants and Signals  (lines 25–33)', 2)
    code_block(doc, [
        'constant CLK_DIV : integer := CLK_MHZ / 10;',
        '',
        'signal div_cnt : integer range 0 to 3 := 0;',
        'signal ce_c    : std_logic;',
        'signal h       : integer range 0 to H_TOTAL - 1 := 0;',
        'signal v       : integer range 0 to V_TOTAL - 1 := 0;',
    ])
    expl(doc,
         'CLK_DIV is integer division: 10/10=1 (no divide), 20/10=2, 40/10=4. '
         'This constant is evaluated at elaboration time; when it equals 1 the '
         'synthesiser removes the prescaler counter entirely.')
    expl(doc,
         'div_cnt is the prescaler — it counts 0..CLK_DIV-1 and wraps. '
         'Its range 0 to 3 covers the maximum case (CLK_MHZ=40, CLK_DIV=4). '
         'ce_c is the combinational clock-enable strobe computed from div_cnt. '
         'h and v are the internal H/V counters; they are named with a single '
         'letter internally and routed to ports h_cnt/v_cnt at the bottom.')

    # --- Block 2.4 ---
    heading(doc, '2.4  Compile-time Assertion  (line 36–37)', 2)
    code_block(doc, [
        'assert CLK_MHZ = 10 or CLK_MHZ = 20 or CLK_MHZ = 30 or CLK_MHZ = 40',
        '  report "CLK_MHZ must be 10, 20, 30, or 40" severity failure;',
    ])
    expl(doc,
         'VHDL assert statements run during simulation elaboration and can also '
         'be evaluated by Vivado synthesis. severity failure causes an immediate '
         'abort if the condition is false — this catches mis-configured instances '
         'before any simulation or bit-file generation takes place.')

    # --- Block 2.5 ---
    heading(doc, '2.5  Clock-Enable Combinational Logic  (line 39)', 2)
    code_block(doc, [
        'ce_c <= \'1\' when (CLK_DIV = 1) or (div_cnt = CLK_DIV - 1) else \'0\';',
    ])
    expl(doc,
         'This is a concurrent signal assignment (not inside a process). '
         'When CLK_DIV = 1 the first condition is a compile-time TRUE so ce_c '
         'is permanently \'1\' — every clock edge is a valid pixel clock. '
         'For higher input clocks, ce_c fires only on the last count of div_cnt. '
         'Because CLK_DIV is a constant, the entire expression simplifies at '
         'synthesis time to either a wire or a single comparator.')

    # --- Block 2.6 ---
    heading(doc, '2.6  Main Clocked Process  (lines 41–61)', 2)
    code_block(doc, [
        'process(clk)',
        'begin',
        '  if rising_edge(clk) then',
        '    if rst = \'1\' then',
        '      div_cnt <= 0; h <= 0; v <= 0;         -- synchronous reset',
        '    else',
        '      -- Step 1: advance prescaler',
        '      if CLK_DIV > 1 then',
        '        if div_cnt = CLK_DIV - 1 then div_cnt <= 0;',
        '        else div_cnt <= div_cnt + 1; end if;',
        '      end if;',
        '      -- Step 2: advance H/V counters on pixel clock edge',
        '      if ce_c = \'1\' then',
        '        if h = H_TOTAL - 1 then',
        '          h <= 0;',
        '          if v = V_TOTAL - 1 then v <= 0; else v <= v + 1; end if;',
        '        else',
        '          h <= h + 1;',
        '        end if;',
        '      end if;',
        '    end if;',
        '  end if;',
        'end process;',
    ])
    expl(doc,
         'This single process is the complete sequential logic of the module. '
         'All assignments use <= (non-blocking/registered) so they all take effect '
         'simultaneously on the next clock edge — standard VHDL flip-flop coding.')
    expl(doc,
         'RESET: On rst=1, all three counters are set to 0 synchronously. '
         'This guarantees the raster starts at the top-left corner of the frame '
         'regardless of power-up state.')
    expl(doc,
         'PRESCALER (Step 1): Only executes when CLK_DIV > 1. '
         'Counts up and wraps: 0 → 1 → ... → CLK_DIV-1 → 0. '
         'The if CLK_DIV > 1 guard is evaluated as a constant so the synthesiser '
         'removes this branch entirely for a 10 MHz clock.')
    expl(doc,
         'H/V COUNTERS (Step 2): Only advance when ce_c is high (one pixel tick). '
         'h increments each pixel and wraps at H_TOTAL-1 (639 for PAL). '
         'At the end of every line (h wraps), v increments. '
         'v wraps at V_TOTAL-1 (624 for PAL) — that completes one full frame.')

    # --- Block 2.7 ---
    heading(doc, '2.7  Output Assignments  (lines 63–65)', 2)
    code_block(doc, [
        'ce    <= ce_c;',
        'h_cnt <= h;',
        'v_cnt <= v;',
    ])
    expl(doc,
         'Concurrent assignments route internal signals to output ports. '
         'In VHDL-2008 an output port can be read directly; using internal '
         'signals h and v is good practice for pre-2008 compatibility and also '
         'keeps the process sensitive only to clk (not to its own output ports).')
    doc.add_page_break()


# ===========================================================================
# Section 3 — pal_csync_il.vhd
# ===========================================================================
def sec_csync(doc):
    heading(doc, '3  pal_csync_il.vhd  —  Composite Sync Generator', 1)
    file_banner(doc,
                'tv/opt2_interlaced/pal_csync_il.vhd',
                'Purely combinational PAL interlaced composite sync, field indicator, '
                'and active-pixel flag generator. All outputs resolve in one delta cycle '
                'using VHDL variables to avoid glitches.')

    heading(doc, '3.1  Why Purely Combinational?  (comment header)', 2)
    expl(doc,
         'The module\'s header comment explains the design decision: using VHDL '
         'variables (not signals) inside the process means all intermediate values '
         '(half-line position, field zone flags) are computed and the outputs are '
         'assigned in a single delta cycle whenever h_cnt or v_cnt change.')
    expl(doc,
         'If intermediate signals were used instead, each assignment would take '
         'one extra delta cycle. At the exact moment h_cnt wraps from 639 to 0 '
         'and v_cnt rolls over, there would be a one-delta window where old h_cnt '
         'and new v_cnt are visible simultaneously — producing a spurious glitch '
         'on the field output. This would break the testbench\'s falling_edge(field) '
         'edge anchor and could corrupt sync on real hardware.')

    heading(doc, '3.2  Entity Interface  (lines 26–48)', 2)
    code_block(doc, [
        'entity pal_csync_il is',
        '  generic (',
        '    H_FRONT  : integer := 16;   -- front porch clocks',
        '    H_SYNC_W : integer := 47;   -- H sync width (4.7 us)',
        '    H_BACK   : integer := 57;   -- back porch clocks',
        '    H_ACTIVE : integer := 520;  -- active pixels per line',
        '    H_TOTAL  : integer := 640;  -- total clocks per line',
        '    HALF     : integer := 320;  -- half-line = H_TOTAL / 2',
        '    EQ_W     : integer := 23;   -- equalising pulse width (2.3 us)',
        '    BROAD_W  : integer := 273;  -- broad-sync width (27.3 us)',
        '    V_ACT_S_F1 : integer := 24;   -- first active line, field 1',
        '    V_ACT_E_F1 : integer := 311;  -- last  active line, field 1',
        '    V_ACT_S_F2 : integer := 336;  -- first active line, field 2',
        '    V_ACT_E_F2 : integer := 623   -- last  active line, field 2',
        '  );',
        '  port (',
        '    h_cnt  : in  integer range 0 to 639;',
        '    v_cnt  : in  integer range 0 to 624;',
        '    csync  : out std_logic;   -- 1 = sync tip (active)',
        '    field  : out std_logic;   -- 0 = F1, 1 = F2',
        '    active : out std_logic    -- 1 = active picture region',
        '  );',
        'end entity pal_csync_il;',
    ])
    expl(doc,
         'This entity is purely combinational — it has no clock port. '
         'It receives h_cnt and v_cnt from pal_timing and immediately computes '
         'csync, field, and active in zero clock cycles.')
    expl(doc,
         'EQ_W=23 clocks = 2.3 µs (PAL equalising pulse spec: 2.35 µs, close enough). '
         'BROAD_W=273 clocks = 27.3 µs (PAL broad sync spec: 27.3 µs, exact). '
         'The mathematical relationship BROAD_W + H_SYNC_W = 320 = HALF ensures '
         'broad-sync fills a half-line with no dead time.')

    heading(doc, '3.3  H_ACT_S Constant and Assertions  (lines 51–57)', 2)
    code_block(doc, [
        'constant H_ACT_S : integer := H_FRONT + H_SYNC_W + H_BACK;  -- = 120',
        '',
        'assert H_FRONT + H_SYNC_W + H_BACK + H_ACTIVE = H_TOTAL',
        '  report "H timing parameters do not sum to H_TOTAL" severity failure;',
        'assert BROAD_W + H_SYNC_W = HALF',
        '  report "BROAD_W + H_SYNC_W must equal HALF" severity failure;',
    ])
    expl(doc,
         'H_ACT_S=120: active video begins at h_cnt=120 on every normal line '
         '(16 front + 47 sync + 57 back = 120 clocks from line start). '
         'The two assertions verify that the timing budget is self-consistent '
         'at elaboration time — protecting against accidental generic mis-configuration.')

    heading(doc, '3.4  Process Variable Declarations  (lines 62–66)', 2)
    code_block(doc, [
        'process(h_cnt, v_cnt)',
        '  variable hp      : integer range 0 to HALF - 1;',
        '  variable first_h : boolean;  -- true when h_cnt < 320',
        '  variable f1p, f1b, f1q : boolean;  -- F1 pre-eq / broad / post-eq',
        '  variable f2p, f2b, f2q : boolean;  -- F2 pre-eq / broad / post-eq',
        '  variable in_eq, in_brd  : boolean;',
        'begin',
    ])
    expl(doc,
         'VHDL variables are local to the process and update immediately (not on '
         'the next delta). The process is sensitive to h_cnt and v_cnt only — '
         'any time either counter changes, the entire combinational logic re-evaluates.')
    expl(doc,
         'hp is the half-line position: 0 at the start of a line, '
         'also 0 at h_cnt=320 (the exact half-line boundary). '
         'All pulse-width comparisons use hp so the same < EQ_W and < BROAD_W '
         'thresholds apply to both halves of any line.')

    heading(doc, '3.5  Half-Line Phase Calculation  (lines 68–69)', 2)
    code_block(doc, [
        'first_h := (h_cnt < HALF);',
        'if first_h then hp := h_cnt; else hp := h_cnt - HALF; end if;',
    ])
    expl(doc,
         'first_h is true for the first half of every line (h_cnt 0..319). '
         'hp maps both halves to 0..319 independently, providing a unified '
         'relative position within each half-line segment. '
         'This makes the equalising and broad-sync pulse width checks identical '
         'for both the first and second half of any line.')

    heading(doc, '3.6  Field 1 Vsync Zone Flags  (lines 77–79)', 2)
    code_block(doc, [
        '-- 5 pre-eq half-lines: v=0 (both), v=1 (both), v=2 (first half)',
        'f1p := (v_cnt = 0) or (v_cnt = 1) or (v_cnt = 2 and first_h);',
        '-- 5 broad half-lines: v=2 (second), v=3 (both), v=4 (both)',
        'f1b := (v_cnt = 2 and not first_h) or (v_cnt = 3) or (v_cnt = 4);',
        '-- 5 post-eq half-lines: v=5 (both), v=6 (both), v=7 (first)',
        'f1q := (v_cnt = 5) or (v_cnt = 6) or (v_cnt = 7 and first_h);',
    ])
    expl(doc,
         'PAL Field 1 vsync runs for 15 half-lines (7.5 full lines) starting at '
         'v=0 h=0 (frame boundary). Breaking 15 half-lines into the three groups: '
         '  Pre-eq:  v=0 full (2 HL) + v=1 full (2 HL) + v=2 first half (1 HL) = 5 HL. '
         '  Broad:   v=2 second half (1 HL) + v=3 full (2 HL) + v=4 full (2 HL) = 5 HL. '
         '  Post-eq: v=5 full (2 HL) + v=6 full (2 HL) + v=7 first half (1 HL) = 5 HL.')

    heading(doc, '3.7  Field 2 Vsync Zone Flags  (lines 87–89)', 2)
    code_block(doc, [
        '-- F2 pre-eq: v=312 second half, v=313 both, v=314 both',
        'f2p := (v_cnt = 312 and not first_h) or (v_cnt = 313) or (v_cnt = 314);',
        '-- F2 broad:  v=315 both, v=316 both, v=317 first half',
        'f2b := (v_cnt = 315) or (v_cnt = 316) or (v_cnt = 317 and first_h);',
        '-- F2 post-eq: v=317 second half, v=318 both, v=319 both',
        'f2q := (v_cnt = 317 and not first_h) or (v_cnt = 318) or (v_cnt = 319);',
    ])
    expl(doc,
         'Field 2 vsync starts at v=312 h=320 — a half-line offset from Field 1. '
         'This half-line shift is the essence of interlaced scanning: F2 lines '
         'land between F1 lines on the CRT screen. The vsync sequence is the same '
         '5+5+5 half-line structure but begins mid-line, hence the "and not first_h" '
         'condition on v=312.')

    heading(doc, '3.8  Composite Sync Output  (lines 91–104)', 2)
    code_block(doc, [
        'in_eq  := f1p or f1q or f2p or f2q;',
        'in_brd := f1b or f2b;',
        '',
        'if in_eq and hp < EQ_W then',
        '  csync <= \'1\';          -- equalising pulse: 23 clocks (2.3 us) low',
        'elsif in_brd and hp < BROAD_W then',
        '  csync <= \'1\';          -- broad sync: 273 clocks (27.3 us) low',
        'elsif not (in_eq or in_brd)',
        '      and h_cnt >= H_FRONT and h_cnt < H_FRONT + H_SYNC_W then',
        '  csync <= \'1\';          -- normal H sync: 47 clocks (4.7 us) low',
        'else',
        '  csync <= \'0\';',
        'end if;',
    ])
    expl(doc,
         'csync is active-high (1 = sync tip) in this design — the R-2R DAC '
         'output is highest at 0xF (white) and lowest at 0x0 (sync). '
         'Note: in standard TV convention sync is "negative" but the DAC inversion '
         'maps 0x0 → most negative analogue voltage, which is below blanking.')
    expl(doc,
         'The three cases are mutually exclusive. During vsync lines the normal '
         'H sync pulse is suppressed (the "not (in_eq or in_brd)" guard). '
         'Equalising pulses fire at the start of each half-line (hp < 23). '
         'Broad-sync fills the first 273 clocks of each broad-sync half-line; '
         'since 273 + 47 = 320 = HALF, the second half-line starts cleanly.')

    heading(doc, '3.9  Field Indicator  (lines 107–111)', 2)
    code_block(doc, [
        'if v_cnt > 312 or (v_cnt = 312 and not first_h) then',
        '  field <= \'1\';   -- Field 2',
        'else',
        '  field <= \'0\';   -- Field 1',
        'end if;',
    ])
    expl(doc,
         'field transitions from 0 (F1) to 1 (F2) at exactly the PAL half-line '
         'boundary: v_cnt=312, h_cnt=320. This is the moment when Field 2 vsync '
         'begins. Using "not first_h" (i.e. h_cnt >= 320) ensures no ambiguity '
         'at the line boundary itself.')

    heading(doc, '3.10  Active-Pixel Window  (lines 114–119)', 2)
    code_block(doc, [
        'if (v_cnt >= V_ACT_S_F1 and v_cnt <= V_ACT_E_F1 and h_cnt >= H_ACT_S) or',
        '   (v_cnt >= V_ACT_S_F2 and v_cnt <= V_ACT_E_F2 and h_cnt >= H_ACT_S) then',
        '  active <= \'1\';',
        'else',
        '  active <= \'0\';',
        'end if;',
    ])
    expl(doc,
         'active is high only when the raster is in the visible picture area of '
         'either field. F1 active rows: v=24..311 (288 lines). '
         'F2 active rows: v=336..623 (288 lines). '
         'Total: 576 active screen rows per frame — the PAL active raster. '
         'Horizontally, active starts at h=120 on every active line.')
    doc.add_page_break()


# ===========================================================================
# Section 4 — pal_tv_bram_top.vhd
# ===========================================================================
def sec_pal_bram(doc):
    heading(doc, '4  pal_tv_bram_top.vhd  —  PAL BRAM Video Top Level', 1)
    file_banner(doc,
                'tv/bram/pal_tv_bram_top.vhd',
                'PAL-625/50 video IP with 10-pattern generator and BRAM double-buffer. '
                'Instantiates pal_timing + pal_csync_il. Supports sel 0-9 patterns, '
                'bouncing ball, crosshatch, centre cross and tear-free BRAM display.')

    heading(doc, '4.1  Entity Generics  (lines 64–78)', 2)
    code_block(doc, [
        'entity pal_tv_bram_top is',
        '  generic (',
        '    H_FRONT    : integer := 16;',
        '    H_SYNC_W   : integer := 47;',
        '    H_BACK     : integer := 57;',
        '    H_ACTIVE   : integer := 520;',
        '    H_TOTAL    : integer := 640;',
        '    V_TOTAL    : integer := 625;',
        '    LEVEL_SYNC  : std_logic_vector(3 downto 0) := "0000";',
        '    LEVEL_BLANK : std_logic_vector(3 downto 0) := "0100";',
        '    LEVEL_WHITE : std_logic_vector(3 downto 0) := "1111";',
        '    CLK_MHZ     : integer := 40;',
        '    STRIPE_W    : integer := 4;',
        '    BRAM_DEPTH  : integer := 299520',
        '  );',
    ])
    expl(doc,
         'Horizontal timing generics set the PAL line structure. '
         'H_FRONT=16, H_SYNC_W=47, H_BACK=57, H_ACTIVE=520 sum to H_TOTAL=640 — '
         'an assertion inside the module verifies this. LEVEL_* constants encode '
         'the three DAC output levels. CLK_MHZ defaults to 40 MHz (common FPGA '
         'oscillator); pal_timing divides it to 10 MHz pixels internally. '
         'STRIPE_W=4 controls the width of stripes in zone-pattern generators. '
         'BRAM_DEPTH=299520 = 520 * 576 pixels = one full PAL frame.')

    heading(doc, '4.2  Entity Ports  (lines 79–137)', 2)
    code_block(doc, [
        '  port (',
        '    clk, rst       : in  std_logic;',
        '    sel            : in  std_logic_vector(7 downto 0);   -- pattern 0-9',
        '    brightness     : in  std_logic_vector(3 downto 0);   -- white DAC level',
        '    black_lvl      : in  std_logic_vector(3 downto 0);   -- black DAC level',
        '    -- BRAM write port',
        '    bram_wr_en     : in  std_logic;',
        '    bram_wr_addr   : in  std_logic_vector(18 downto 0);',
        '    bram_wr_data   : in  std_logic;',
        '    bram_len       : in  std_logic_vector(18 downto 0);',
        '    -- Double-buffer control',
        '    buf_swap       : in  std_logic;   -- one-clock pulse = request swap',
        '    buf_swapped    : out std_logic;   -- one-clock strobe when swap done',
        '    back_buf_o     : out std_logic;   -- current back-buffer index',
        '    -- Ball animation (sel=5)',
        '    ball_spd_h, ball_spd_v : in std_logic_vector(3 downto 0);',
        '    ball_w_i, ball_h_i     : in std_logic_vector(9 downto 0);',
        '    -- Crosshatch control (sel=8)',
        '    cross_h_i, cross_v_i   : in std_logic_vector(9 downto 0);',
        '    -- Video outputs',
        '    dac_out, csync_o, line_sync_o, frame_sync_o,',
        '    field_o, active_o, blank_o : out std_logic',
        '  );',
    ])
    expl(doc,
         'sel is 8 bits allowing 256 pattern codes; only 0-9 are defined (others → black). '
         'brightness and black_lvl are 4-bit DAC values clamped to [4,15] internally. '
         'The BRAM write port is triple-signal: write-enable, 19-bit address (covers '
         '2^19=524288 pixels), and 1-bit pixel data. bram_len wraps the read address '
         'at a boundary less than BRAM_DEPTH — useful for tiling a single row. '
         'buf_swap must be pulsed ONE clock cycle to request a swap; '
         'buf_swapped strobes back ONE clock when the swap executes at V-blank. '
         'back_buf_o tells the host which bank index is currently the back buffer.')

    heading(doc, '4.3  Architecture Constants  (lines ~145–165)', 2)
    code_block(doc, [
        'constant H_ACT_S     : integer := H_FRONT + H_SYNC_W + H_BACK;  -- 120',
        'constant V_ACT_S_F1  : integer := 24;   -- first active v-count, field 1',
        'constant V_ACT_E_F1  : integer := 311;  -- last  active v-count, field 1',
        'constant V_ACT_S_F2  : integer := 336;  -- first active v-count, field 2',
        'constant V_ACT_E_F2  : integer := 623;  -- last  active v-count, field 2',
        '',
        'constant NUM_ZONES : integer := 8;',
        'constant ZONE_W    : integer := H_ACTIVE / NUM_ZONES;  -- 65 px',
        'constant ZONE_H    : integer := 288 / NUM_ZONES;       -- 36 lines',
        'constant GZONES    : integer := 10;',
        'constant GZONE_W   : integer := H_ACTIVE / GZONES;     -- 52 px',
        'constant GZONE_H   : integer := 288 / GZONES;          -- 28 lines',
    ])
    expl(doc,
         'H_ACT_S=120 is the h_cnt value at which active pixels begin. '
         'V_ACT_S_F1=24 / V_ACT_E_F1=311 bracket the 288 active lines of Field 1. '
         'V_ACT_S_F2=336 / V_ACT_E_F2=623 bracket Field 2. The 12-line gap between '
         '311 and 336 is the inter-field blanking interval.')
    expl(doc,
         'NUM_ZONES=8: both vertical-bar and horizontal-bar patterns use 8 zones '
         'of equal size. ZONE_W=65 px per horizontal zone (8*65=520=H_ACTIVE). '
         'ZONE_H=36 lines per vertical zone (8*36=288 active lines per field). '
         'Gradient patterns use 10 zones (GZONES): GZONE_W=52 px, GZONE_H=28 lines.')

    heading(doc, '4.4  Zone Table  (constant)', 2)
    code_block(doc, [
        'type zone_kind    is (Z_BLACK, Z_WHITE, Z_STRIPE);',
        'type zone_table_t is array (0 to NUM_ZONES - 1) of zone_kind;',
        'constant ZONE_TABLE : zone_table_t := (',
        '  0 => Z_STRIPE, 1 => Z_WHITE,  2 => Z_STRIPE, 3 => Z_WHITE,',
        '  4 => Z_BLACK,  5 => Z_STRIPE, 6 => Z_WHITE,  7 => Z_STRIPE',
        ');',
    ])
    expl(doc,
         'ZONE_TABLE defines the sequence of zone types for the vertical-bar and '
         'horizontal-bar test patterns. Z_STRIPE generates an alternating '
         'black/white sub-pattern (like a cross-hatch), Z_WHITE is solid white, '
         'Z_BLACK is solid black. The array is read via zone_idx_v (vertical bars) '
         'and zone_idx_h (horizontal bars) counters.')

    heading(doc, '4.5  BRAM Double-Buffer Signals', 2)
    code_block(doc, [
        'type bram_t is array (0 to BRAM_DEPTH - 1) of std_logic;',
        'signal bram_mem_0 : bram_t := (others => \'0\');',
        'signal bram_mem_1 : bram_t := (others => \'0\');',
        'attribute ram_style               : string;',
        'attribute ram_style of bram_mem_0 : signal is "block";',
        'attribute ram_style of bram_mem_1 : signal is "block";',
        '',
        'signal disp_buf      : std_logic := \'0\';  -- 0=bank0 on display',
        'signal swap_req      : std_logic := \'0\';  -- pending swap request',
        'signal buf_swapped_s : std_logic := \'0\';  -- internal strobe',
    ])
    expl(doc,
         'Two identical BRAM arrays implement the double-buffer. '
         'Each holds BRAM_DEPTH 1-bit pixels (299520 bits = ~37 KB = ~10 BRAM36 tiles). '
         'The ram_style="block" attribute directs Vivado to infer Block RAM primitives '
         'rather than distributed LUT-RAM. Both initialise to \'0\' = black.')
    expl(doc,
         'disp_buf selects which bank is currently displayed: 0 = bank0 front, 1 = bank1 front. '
         'swap_req is a sticky latch: set when buf_swap pulses, cleared when the swap executes. '
         'buf_swapped_s is the internal one-cycle strobe that feeds the buf_swapped output.')

    heading(doc, '4.6  Module Instantiations  (begin section)', 2)
    code_block(doc, [
        'timing_inst : entity work.pal_timing',
        '  generic map (H_TOTAL => H_TOTAL, V_TOTAL => V_TOTAL, CLK_MHZ => CLK_MHZ)',
        '  port map    (clk => clk, rst => rst, ce => ce_s, h_cnt => h_cnt, v_cnt => v_cnt);',
        '',
        'sync_inst : entity work.pal_csync_il',
        '  generic map (H_FRONT => H_FRONT, H_SYNC_W => H_SYNC_W, ...)',
        '  port map    (h_cnt => h_cnt, v_cnt => v_cnt,',
        '               csync => csync_s, field => field_s, active => active_s);',
    ])
    expl(doc,
         'pal_timing provides the clocked H/V counters and the pixel clock-enable (ce_s). '
         'pal_csync_il is purely combinational — it takes h_cnt/v_cnt and immediately '
         'outputs csync_s, field_s, active_s. These three signals drive everything else '
         'in the architecture.')

    heading(doc, '4.7  Active-Region Flags', 2)
    code_block(doc, [
        'in_f1_active  <= (v_cnt >= V_ACT_S_F1 and v_cnt <= V_ACT_E_F1);',
        'in_f2_active  <= (v_cnt >= V_ACT_S_F2 and v_cnt <= V_ACT_E_F2);',
        'in_any_active <= in_f1_active or in_f2_active;',
    ])
    expl(doc,
         'These boolean signals (VHDL boolean is a subtype of std_logic here) '
         'simplify conditions throughout the architecture. in_any_active is true '
         'for all v_cnt values in either field\'s active range, regardless of h_cnt. '
         'They are used as guards in the horizontal bar, gradient, BRAM address, '
         'and crosshatch counter processes.')

    heading(doc, '4.8  Vertical Bar Generator Process', 2)
    code_block(doc, [
        'process(clk)',
        'begin',
        '  if rising_edge(clk) then',
        '    if rst = \'1\' then',
        '      zone_idx_v <= 0; px_in_zone <= 0;',
        '      stripe_cnt_v <= 0; stripe_ph_v <= \'0\';',
        '    elsif ce_s = \'1\' then',
        '      -- Reset at line start (one clock before active begins)',
        '      if h_cnt = H_ACT_S - 1 and in_any_active then',
        '        zone_idx_v <= 0; px_in_zone <= 0;',
        '        stripe_cnt_v <= 0; stripe_ph_v <= \'0\';',
        '      elsif active_s = \'1\' then',
        '        -- End of zone: advance to next zone, reset stripe phase',
        '        if px_in_zone = ZONE_W - 1 then',
        '          zone_idx_v <= zone_idx_v + 1; px_in_zone <= 0;',
        '          stripe_cnt_v <= 0; stripe_ph_v <= \'0\';',
        '        else',
        '          px_in_zone   <= px_in_zone + 1;',
        '          -- Toggle stripe phase every STRIPE_W pixels',
        '          if stripe_cnt_v = STRIPE_W - 1 then',
        '            stripe_cnt_v <= 0; stripe_ph_v <= not stripe_ph_v;',
        '          else',
        '            stripe_cnt_v <= stripe_cnt_v + 1;',
        '          end if;',
        '        end if;',
        '      end if;',
        '    end if;',
        '  end if;',
        'end process;',
    ])
    expl(doc,
         'This process generates the X-axis counters for the 8-zone vertical-bar pattern. '
         'Resetting at h_cnt = H_ACT_S - 1 (one clock before active_s goes high) '
         'ensures zone_idx_v is 0 when the very first active pixel clock arrives.')
    expl(doc,
         'px_in_zone counts pixels within the current zone (0..64). '
         'When it reaches ZONE_W-1=64 the zone advances and px_in_zone resets. '
         'stripe_cnt_v counts pixels within a stripe period (0..STRIPE_W-1=3). '
         'stripe_ph_v toggles between 0 and 1 every STRIPE_W pixels — it becomes '
         'the output color for Z_STRIPE zones. The downstream mux selects '
         'ZONE_TABLE[zone_idx_v] and maps Z_STRIPE to stripe_ph_v.')

    heading(doc, '4.9  Horizontal Bar Generator Process', 2)
    code_block(doc, [
        '-- Reset at cycle before the first active line of each field',
        'if (v_cnt = V_ACT_S_F1 - 1 or v_cnt = V_ACT_S_F2 - 1)',
        '   and h_cnt = H_TOTAL - 1 then',
        '  zone_idx_h <= 0; line_in_zone <= 0; ...',
        '-- Advance once per active line at end-of-line',
        'elsif in_any_active and h_cnt = H_TOTAL - 1 then',
        '  if line_in_zone = ZONE_H - 1 then',
        '    zone_idx_h <= zone_idx_h + 1; line_in_zone <= 0; ...',
        '  else',
        '    line_in_zone <= line_in_zone + 1; ...',
        '  end if;',
        'end if;',
    ])
    expl(doc,
         'The horizontal-bar generator counts active lines instead of pixels. '
         'line_in_zone counts from 0 to ZONE_H-1=35 (36 lines per zone). '
         'The zone advances at the end of each 36-line block. '
         'stripe_ph_h toggles the stripe phase vertically, producing '
         'fine horizontal stripe patterns within Z_STRIPE zones.')
    expl(doc,
         'Note: the reset triggers at h_cnt = H_TOTAL - 1 on the line BEFORE '
         'the first active line (v = V_ACT_S_F1 - 1 = 23, and separately '
         'v = V_ACT_S_F2 - 1 = 335). This ensures zone_idx_h = 0 at the '
         'very first active line of each field.')

    heading(doc, '4.10  Gradient Generator Processes', 2)
    code_block(doc, [
        '-- Horizontal gradient: gzx_idx (zone 0..9), gpx_in (pixel in zone)',
        'if h_cnt = H_ACT_S - 1 and in_any_active then',
        '  gzx_idx <= 0; gpx_in <= 0;         -- reset at line start',
        'elsif active_s = \'1\' then',
        '  if gpx_in = GZONE_W - 1 then        -- end of 52-px zone',
        '    gzx_idx <= gzx_idx + 1; gpx_in <= 0;',
        '  else gpx_in <= gpx_in + 1;',
        '  end if;',
        'end if;',
        '',
        '-- Vertical gradient: gzy_idx (zone 0..9), gln_in (line in zone)',
        '-- resets at field starts; advances once per active line end-of-line',
    ])
    expl(doc,
         'gzx_idx (0..9) indexes the horizontal gradient zone. The brightness '
         'process converts this to a DAC level: zone 0 = black_level, zone 9 = '
         'white_level, with linear interpolation. This gives a 10-step grey ramp '
         'across the screen from left to right (sel=2). '
         'gzy_idx drives the same brightness formula vertically (sel=3).')

    heading(doc, '4.11  screen_x and screen_y Processes', 2)
    code_block(doc, [
        '-- screen_x: pixel column 0..519 within active area',
        'if h_cnt = H_ACT_S - 1 and in_any_active then screen_x <= 0;',
        'elsif active_s = \'1\' then screen_x <= screen_x + 1;',
        'end if;',
        '',
        '-- screen_y: absolute screen row (0..575), steps by 2 (interlaced)',
        'if v_cnt = V_ACT_S_F1 - 1 and h_cnt = H_TOTAL - 1 then',
        '  screen_y <= 0;        -- F1: rows 0, 2, 4, ...',
        'elsif v_cnt = V_ACT_S_F2 - 1 and h_cnt = H_TOTAL - 1 then',
        '  screen_y <= 1;        -- F2: rows 1, 3, 5, ...',
        'elsif in_any_active and h_cnt = H_TOTAL - 1 then',
        '  screen_y <= screen_y + 2;  -- interlace: skip one row per line',
        'end if;',
    ])
    expl(doc,
         'screen_x is the 0-based pixel column within the active picture. '
         'It resets one clock before active_s goes high so the first pixel '
         'has screen_x = 0.')
    expl(doc,
         'screen_y is the absolute screen row in the de-interlaced picture. '
         'Field 1 paints even rows (0, 2, 4, ...) so it starts at 0 and '
         'increments by 2. Field 2 paints odd rows (1, 3, 5, ...) so it '
         'starts at 1 and also increments by 2. screen_y is used for '
         'ball boundary checks and the centre-cross vertical midpoint calculation.')

    heading(doc, '4.12  Ball Physics Process  (lines 439–479)', 2)
    code_block(doc, [
        '-- Fires once per frame: at last pixel of last F2 active line',
        'elsif ce_s = \'1\' and v_cnt = V_ACT_E_F2 and h_cnt = H_TOTAL - 1 then',
        '  nx  := ball_x + ball_vx;   -- proposed new X',
        '  ny  := ball_y + ball_vy;   -- proposed new Y',
        '  nvx := ball_vx;  nvy := ball_vy;',
        '  -- Right wall elastic bounce',
        '  if nx > H_ACTIVE - ball_w_s then',
        '    nx  := 2 * (H_ACTIVE - ball_w_s) - nx;  -- reflect position',
        '    nvx := -nvx;                              -- reverse velocity',
        '  end if;',
        '  -- Left wall',
        '  if nx < 0 then nx := -nx; nvx := -nvx; end if;',
        '  -- Bottom wall',
        '  if ny > 576 - ball_h_s then',
        '    ny := 2 * (576 - ball_h_s) - ny; nvy := -nvy;',
        '  end if;',
        '  -- Top wall',
        '  if ny < 0 then ny := -ny; nvy := -nvy; end if;',
        '  ball_x <= nx; ball_y <= ny; ball_vx <= nvx; ball_vy <= nvy;',
        'end if;',
    ])
    expl(doc,
         'Ball physics runs exactly once per frame — at the last active pixel '
         'of Field 2 (v_cnt=623, h_cnt=639). This updates ball_x/y for the '
         'NEXT frame so the display sees a consistent position throughout each frame.')
    expl(doc,
         'The elastic bounce formula reflects the position around the wall. '
         'If nx overshoots the right wall at position W (= H_ACTIVE - ball_w_s), '
         'the reflected position is 2*W - nx (mirror image). The velocity reverses '
         'sign. This is applied to all four walls in sequence using VHDL variables '
         '(nx, ny, nvx, nvy) so multi-wall corner collisions are handled correctly '
         'in a single clock cycle.')

    heading(doc, '4.13  ball_on Combinational', 2)
    code_block(doc, [
        'ball_on <= \'1\' when screen_x >= ball_x and',
        '                    screen_x <  ball_x + ball_w_s and',
        '                    screen_y >= ball_y and',
        '                    screen_y <  ball_y + ball_h_s',
        '           else \'0\';',
    ])
    expl(doc,
         'ball_on is a pure combinational rectangle hit-test. It is high when '
         'the current pixel (screen_x, screen_y) falls within the ball\'s '
         'bounding rectangle. Since ball_x/y update only once per frame and '
         'screen_x/y track the raster scan in real time, every pixel of the '
         'ball lights up white while every other pixel is black.')

    heading(doc, '4.14  BRAM Write Port Process  (lines 499–511)', 2)
    code_block(doc, [
        'process(clk)',
        'begin',
        '  if rising_edge(clk) then',
        '    if bram_wr_en = \'1\' and',
        '       to_integer(unsigned(bram_wr_addr)) < BRAM_DEPTH then',
        '      -- Always write to the BACK buffer (NOT the displayed bank)',
        '      if disp_buf = \'0\' then',
        '        bram_mem_1(to_integer(unsigned(bram_wr_addr))) <= bram_wr_data;',
        '      else',
        '        bram_mem_0(to_integer(unsigned(bram_wr_addr))) <= bram_wr_data;',
        '      end if;',
        '    end if;',
        '  end if;',
        'end process;',
    ])
    expl(doc,
         'The write port is synchronous (registered on rising edge of clk, not ce_s). '
         'This means the host can write at the full board clock rate, independent '
         'of the pixel clock rate. bram_wr_addr is checked against BRAM_DEPTH to '
         'prevent out-of-bounds writes.')
    expl(doc,
         'The key line is "if disp_buf = \'0\' then write to bank 1 else write to bank 0". '
         'This automatically targets the back buffer without the host needing to '
         'track which bank is active. The host just writes to bram_wr_addr 0..N-1 '
         'and the hardware routes to the correct bank.')

    heading(doc, '4.15  Double-Buffer Swap Process  (lines 513–533)', 2)
    code_block(doc, [
        'process(clk)',
        'begin',
        '  if rising_edge(clk) then',
        '    if rst = \'1\' then',
        '      disp_buf <= \'0\'; swap_req <= \'0\'; buf_swapped_s <= \'0\';',
        '    elsif ce_s = \'1\' then',
        '      buf_swapped_s <= \'0\';               -- clear strobe every cycle',
        '      if buf_swap = \'1\' then',
        '        swap_req <= \'1\';                  -- latch the request',
        '      end if;',
        '      -- Execute swap at last pixel of last F2 active line',
        '      if v_cnt = V_ACT_E_F2 and h_cnt = H_TOTAL - 1 and swap_req = \'1\' then',
        '        disp_buf      <= not disp_buf;      -- flip display bank',
        '        swap_req      <= \'0\';              -- clear request',
        '        buf_swapped_s <= \'1\';              -- pulse strobe',
        '      end if;',
        '    end if;',
        '  end if;',
        'end process;',
    ])
    expl(doc,
         'This process implements the tear-free double-buffer handshake. '
         'swap_req is a sticky flag — once set by buf_swap it stays set until '
         'the V-blank window arrives. This means the host can pulse buf_swap '
         'at any time during the frame and the swap will always happen at the '
         'right moment.')
    expl(doc,
         'The swap condition fires at v_cnt=623, h_cnt=639: the very last active '
         'pixel of Field 2. This is the V-blank boundary — the display controller '
         'has just finished reading the last pixel of the current frame. Flipping '
         'disp_buf here means the next frame starts reading from the new bank '
         'without any visible tearing artifact.')
    expl(doc,
         'buf_swapped_s is cleared at the start of every ce_s cycle (line: '
         'buf_swapped_s <= \'0\') so the strobe is exactly one pixel clock wide. '
         'The host must sample buf_swapped on the rising edge within that one cycle, '
         'or use a wait statement as the testbench does.')

    heading(doc, '4.16  BRAM Address Generator  (lines 539–568)', 2)
    code_block(doc, [
        'process(clk)',
        'begin',
        '  if rising_edge(clk) then',
        '    if rst = \'1\' then',
        '      bram_rd_line_base <= 0; bram_px_cnt <= 0;',
        '    elsif ce_s = \'1\' then',
        '      -- F1 field start: image row 0 at address 0',
        '      if v_cnt = V_ACT_S_F1 - 1 and h_cnt = H_TOTAL - 1 then',
        '        bram_rd_line_base <= 0;          bram_px_cnt <= 0;',
        '      -- F2 field start: image row 1 at address H_ACTIVE = 520',
        '      elsif v_cnt = V_ACT_S_F2 - 1 and h_cnt = H_TOTAL - 1 then',
        '        bram_rd_line_base <= H_ACTIVE;   bram_px_cnt <= 0;',
        '      -- End of any active line: stride = 2 * H_ACTIVE (interlace skip)',
        '      elsif in_any_active and h_cnt = H_TOTAL - 1 then',
        '        bram_rd_line_base <= bram_rd_line_base + 2 * H_ACTIVE;',
        '        bram_px_cnt <= 0;',
        '      -- Within active region: advance pixel counter',
        '      elsif active_s = \'1\' then',
        '        bram_px_cnt <= bram_px_cnt + 1;',
        '      end if;',
        '    end if;',
        '  end if;',
        'end process;',
        '',
        '-- Combinational address with wrap-at-bram_len',
        'bram_rd_sum  <= bram_rd_line_base + bram_px_cnt;',
        'bram_rd_addr <= bram_rd_sum when bram_rd_sum < bram_len_i else 0;',
    ])
    expl(doc,
         'bram_rd_line_base is the BRAM start address of the current active line. '
         'bram_px_cnt is the pixel offset within that line (0..519). '
         'Their sum gives bram_rd_addr, which is clamped to bram_len_i to '
         'implement the wrap/tile feature.')
    expl(doc,
         'F1 starts with bram_rd_line_base = 0 (image row 0). After each F1 line, '
         'it advances by 2*H_ACTIVE = 1040 — skipping over the F2 row for that '
         'screen position. F2 starts with bram_rd_line_base = H_ACTIVE = 520 '
         '(image row 1). After each F2 line, it also advances by 1040. '
         'The result: F1 reads rows 0, 2, 4, ... (even); F2 reads rows 1, 3, 5, ... (odd). '
         'Storing the image row-by-row in natural order in BRAM is all the host needs to do.')

    heading(doc, '4.17  BRAM Read (Asynchronous)  (lines 570–577)', 2)
    code_block(doc, [
        '-- Asynchronous read from the front (display) bank',
        'bram_pixel <= bram_mem_0(bram_rd_addr) when disp_buf = \'0\' else',
        '              bram_mem_1(bram_rd_addr);',
        'bram_level <= white_s when bram_pixel = \'1\' else black_s;',
        '',
        '-- Double-buffer status outputs',
        'buf_swapped <= buf_swapped_s;',
        'back_buf_o  <= not disp_buf;',
    ])
    expl(doc,
         'The read is combinational (asynchronous) — the BRAM acts like a '
         'lookup table here, driven by the combinational bram_rd_addr. '
         'disp_buf selects which bank supplies pixels to the display. '
         'bram_pixel is the raw 1-bit value; bram_level maps it to a '
         '4-bit DAC level: \'1\' → white_s (brightness), \'0\' → black_s (black_lvl).')
    expl(doc,
         'back_buf_o = not disp_buf: if bank 0 is displayed (disp_buf=0), '
         'then the back buffer is bank 1 (back_buf_o=1). The host should '
         'always write to the back buffer at address bram_wr_addr without '
         'needing to know which physical bank that is.')

    heading(doc, '4.18  Brightness / Black-Level Control  (lines 582–611)', 2)
    code_block(doc, [
        '-- White level: clamp brightness to [4, 15]',
        'white_level_i <= 4 when unsigned(brightness) < 4',
        '                   else to_integer(unsigned(brightness));',
        'white_s <= std_logic_vector(to_unsigned(white_level_i, 4));',
        '',
        '-- Black level: clamp black_lvl to [4, white_level_i]',
        'process(black_lvl, white_level_i)',
        '  variable b : integer range 0 to 15;',
        'begin',
        '  b := to_integer(unsigned(black_lvl));',
        '  if b < 4             then b := 4;             end if;',
        '  if b > white_level_i then b := white_level_i; end if;',
        '  black_level_i <= b;',
        'end process;',
        '',
        '-- Gradient: interpolate between black and white over 9 steps',
        'lx := black_level_i + (gzx_idx * rng + 4) / 9;',
    ])
    expl(doc,
         'white_s is the "white" DAC level — the highest output the module will produce. '
         'Minimum is 4 (LEVEL_BLANK) to ensure white is always above blanking. '
         'black_s is the "black" DAC level — the floor for active-picture signal. '
         'It is clamped to [4, white_level_i] so black can never exceed white.')
    expl(doc,
         'The gradient formula `(gzx_idx * rng + 4) / 9` uses integer arithmetic '
         'to compute a rounded step. rng = white_level_i - black_level_i is the '
         'dynamic range in DAC steps. Adding 4 before dividing by 9 provides '
         'rounding (equivalent to +0.5 for 9 zones: 4 ≈ 9/2). '
         'This gives zone 0 = black, zone 9 = white, with 8 evenly-spaced steps.')

    heading(doc, '4.19  Crosshatch Counter Processes  (lines 618–656)', 2)
    code_block(doc, [
        '-- Horizontal crosshatch period counter (resets at line start)',
        'if h_cnt = H_ACT_S - 1 and in_any_active then',
        '  cross_x_cnt <= 0;',
        'elsif active_s = \'1\' then',
        '  if cross_x_cnt = cross_h_s - 1 then cross_x_cnt <= 0;',
        '  else cross_x_cnt <= cross_x_cnt + 1;',
        '  end if;',
        'end if;',
        '',
        '-- Vertical crosshatch period counter (resets at frame start)',
        'if v_cnt = V_ACT_S_F1 and h_cnt = 0 then',
        '  cross_y_cnt <= 0;',
        'elsif in_any_active and h_cnt = H_TOTAL - 1 then',
        '  if cross_y_cnt = cross_v_s - 1 then cross_y_cnt <= 0;',
        '  else cross_y_cnt <= cross_y_cnt + 1;',
        '  end if;',
        'end if;',
        '',
        'cross_on <= \'1\' when cross_x_cnt = 0 or cross_y_cnt = 0 else \'0\';',
    ])
    expl(doc,
         'The crosshatch is drawn using two modulo counters — no division hardware needed. '
         'cross_x_cnt counts pixels within each horizontal cell: 0..cross_h_s-1. '
         'cross_y_cnt counts lines within each vertical cell: 0..cross_v_s-1. '
         'cross_on fires whenever either counter is zero — that is, at the start '
         'of every H or V cell period, drawing a one-pixel-wide grid line.')
    expl(doc,
         'cross_h_i (default 52 px) and cross_v_i (default 58 lines) set the '
         'crosshatch pitch at runtime via input ports. Both are clamped to ≥1 '
         'to prevent divide-by-zero in simulation.')

    heading(doc, '4.20  Active-Level Mux  (lines 661–679)', 2)
    code_block(doc, [
        'with ZONE_TABLE(zone_idx_v) select',
        '  color_v <= \'0\' when Z_BLACK, \'1\' when Z_WHITE, stripe_ph_v when Z_STRIPE;',
        '',
        'active_level <= bram_level  when sel_i = 4 else',
        '                white_s     when sel_i = 5 and ball_on   = \'1\' else',
        '                black_s     when sel_i = 5 else',
        '                white_s     when sel_i = 6 else    -- full white',
        '                black_s     when sel_i = 7 else    -- full black',
        '                white_s     when sel_i = 8 and cross_on  = \'1\' else',
        '                black_s     when sel_i = 8 else',
        '                white_s     when sel_i = 9 and centre_on = \'1\' else',
        '                black_s     when sel_i = 9 else',
        '                grad_x_s    when sel_i = 2 else',
        '                grad_y_s    when sel_i = 3 else',
        '                white_s     when (sel_i = 0 and color_v = \'1\') or',
        '                                 (sel_i = 1 and color_h = \'1\') else',
        '                black_s;',
    ])
    expl(doc,
         'active_level is the 4-bit DAC value during active_s = 1. '
         'The conditional signal assignment (VHDL "when ... else") is synthesised '
         'as a priority-encoded multiplexer — later conditions have lower priority. '
         'sel_i = 4 is highest priority (BRAM image); unrecognised sel values '
         'fall through to the final black_s default.')
    expl(doc,
         'For sel=5 (ball): white if ball_on=1, else black — a white rectangle on black. '
         'For sel=8 (crosshatch): white on grid lines (cross_on=1), black elsewhere. '
         'For sel=9 (centre cross): white on the horizontal or vertical midline, black elsewhere. '
         'For sel=0 (vertical bars): color_v drives white/black via zone table. '
         'For sel=1 (horizontal bars): color_h does the same vertically.')

    heading(doc, '4.21  Sync Decode and DAC Output  (lines 682–713)', 2)
    code_block(doc, [
        '-- V-sync indicator: TRUE during broad-sync region of each field',
        'in_vsync_s <= \'1\' when (v_cnt <= 7) or (v_cnt >= 312 and v_cnt <= 319)',
        '              else \'0\';',
        '',
        '-- H sync: normal H pulse, suppressed during vsync',
        'line_sync_s  <= \'1\' when h_cnt >= H_FRONT and',
        '                          h_cnt < H_FRONT + H_SYNC_W and',
        '                          in_vsync_s = \'0\'',
        '                else \'0\';',
        '',
        '-- DAC output priority: sync > active picture > blanking pedestal',
        'dac_out <= LEVEL_SYNC   when csync_s = \'1\' else',
        '           active_level when active_s = \'1\' else',
        '           LEVEL_BLANK;',
        '',
        'blank_o <= not csync_s and not active_s;',
    ])
    expl(doc,
         'The final DAC output has three priority levels: sync tip (0x0) takes '
         'absolute priority, then active picture level, then blanking pedestal (0x4). '
         'This matches the standard composite video waveform: sync below blanking, '
         'active picture above blanking.')
    expl(doc,
         'line_sync_o and frame_sync_o are auxiliary outputs for systems that need '
         'separate H and V sync signals (e.g., an oscilloscope or external sync separator). '
         'blank_o is a composite blanking signal: high when outside active picture '
         'AND not in sync — useful for gating an external video switch.')
    doc.add_page_break()


# ===========================================================================
# Section 5 — video_bram_top.vhd
# ===========================================================================
def sec_video_bram(doc):
    heading(doc, '5  video_bram_top.vhd  —  PAL/NTSC Runtime-Selectable Variant', 1)
    file_banner(doc,
                'tv/bram/video_bram_top.vhd',
                'PAL/NTSC dual-format video IP. The ntsc_mode port switches all timing '
                'at runtime — no re-synthesis needed. Inlines pal_timing and pal_csync_il '
                'logic directly rather than instantiating sub-modules.')

    heading(doc, '5.1  Key Difference: Runtime Format Selection', 2)
    expl(doc,
         'pal_tv_bram_top uses compile-time constants for all timing values. '
         'video_bram_top replaces those constants with runtime signals '
         '(h_total_m1, v_act_s_f1, v_act_e_f2, etc.) driven from a combinational '
         'process that examines ntsc_mode. This means one synthesised bit-file '
         'can generate either format.')

    heading(doc, '5.2  Entity Port: ntsc_mode  (line 59)', 2)
    code_block(doc, [
        'ntsc_mode : in std_logic;  -- \'0\' = PAL 625/50,  \'1\' = NTSC 525/60',
    ])
    expl(doc,
         'Driving ntsc_mode=\'1\' selects NTSC 525/60: H_TOTAL=636, V_TOTAL=525, '
         'V_ACTIVE=480 (240 lines × 2 fields). '
         'H_ACTIVE remains 520 px for both formats; NTSC achieves this with '
         'H_BACK=53 (vs PAL\'s 57).')

    heading(doc, '5.3  Runtime Timing Signal Declarations  (lines 121–135)', 2)
    code_block(doc, [
        'signal h_total_m1 : integer range 0 to 639;  -- H_TOTAL - 1 (639 PAL / 635 NTSC)',
        'signal h_act_s    : integer range 0 to 639;  -- first active pixel h_cnt',
        'signal v_total_m1 : integer range 0 to 624;  -- V_TOTAL - 1',
        'signal v_act_s_f1 : integer range 0 to 624;',
        'signal v_act_e_f1 : integer range 0 to 624;',
        'signal v_act_s_f2 : integer range 0 to 624;',
        'signal v_act_e_f2 : integer range 0 to 624;',
        'signal v_active   : integer range 0 to 576;  -- 576 PAL / 480 NTSC',
        'signal zone_h_s   : integer range 0 to 36;   -- PAL 36 / NTSC 30',
        'signal gzone_h_s  : integer range 0 to 28;   -- PAL 28 / NTSC 24',
    ])
    expl(doc,
         'Every place in pal_tv_bram_top that uses a constant (V_ACT_E_F2, H_TOTAL-1, etc.) '
         'is replaced here by one of these runtime signals. The H/V counters, '
         'bar generators, gradient generators, ball physics, BRAM address generator, '
         'swap process, and crosshatch counters all reference these signals instead.')

    heading(doc, '5.4  Runtime Parameter Selection Process  (lines 273–300)', 2)
    code_block(doc, [
        'process(ntsc_mode)',
        'begin',
        '  if ntsc_mode = \'1\' then',
        '    h_total_m1 <= 635; h_act_s <= 116;',
        '    v_total_m1 <= 524;',
        '    v_act_s_f1 <= 21; v_act_e_f1 <= 260;  -- 240 lines',
        '    v_act_s_f2 <= 283; v_act_e_f2 <= 522;',
        '    v_active   <= 480;',
        '    zone_h_s   <= 30;  gzone_h_s <= 24;',
        '  else  -- PAL',
        '    h_total_m1 <= 639; h_act_s <= 120;',
        '    v_total_m1 <= 624;',
        '    v_act_s_f1 <= 24; v_act_e_f1 <= 311;  -- 288 lines',
        '    v_act_s_f2 <= 336; v_act_e_f2 <= 623;',
        '    v_active   <= 576;',
        '    zone_h_s   <= 36;  gzone_h_s <= 28;',
        '  end if;',
        'end process;',
    ])
    expl(doc,
         'This is a purely combinational process (no clk in sensitivity list). '
         'It fires whenever ntsc_mode changes and immediately drives all runtime '
         'timing signals. Because VHDL signals update on the next delta cycle, '
         'the registered processes (H/V counters etc.) pick up the new values '
         'on the following clock edge.')
    expl(doc,
         'NTSC H_ACT_S=116: H_FRONT(16) + H_SYNC_W(47) + H_BACK(53) = 116. '
         'PAL H_ACT_S=120: 16 + 47 + 57 = 120. '
         'The four extra back-porch clocks in PAL account for the longer line period '
         '(64 µs PAL vs 63.6 µs NTSC).')

    heading(doc, '5.5  Inlined H/V Counter Process  (lines 321–336)', 2)
    code_block(doc, [
        'process(clk)',
        'begin',
        '  if rising_edge(clk) then',
        '    if rst = \'1\' then h_cnt <= 0; v_cnt <= 0;',
        '    elsif ce_s = \'1\' then',
        '      if h_cnt = h_total_m1 then          -- use runtime signal',
        '        h_cnt <= 0;',
        '        if v_cnt = v_total_m1 then v_cnt <= 0;',
        '        else v_cnt <= v_cnt + 1; end if;',
        '      else h_cnt <= h_cnt + 1;',
        '      end if;',
        '    end if;',
        '  end if;',
        'end process;',
    ])
    expl(doc,
         'Structurally identical to pal_timing\'s counter but uses h_total_m1 '
         'and v_total_m1 (signals) instead of H_TOTAL-1 and V_TOTAL-1 (constants). '
         'This means the counter wrap point changes immediately when ntsc_mode toggles, '
         'adapting to the correct line and frame periods.')

    heading(doc, '5.6  Inlined Composite Sync Process  (lines 345–414)', 2)
    code_block(doc, [
        'process(all)',
        '  variable hp, first_h : ...',
        '  variable f1p, f1b, f1q, f2p, f2b, f2q, in_eq, in_brd : ...',
        'begin',
        '  -- Half-line phase (PAL HALF=320, NTSC HALF=318)',
        '  if ntsc_mode = \'0\' then',
        '    first_h := (h_cnt < 320); ...',
        '  else',
        '    first_h := (h_cnt < 318); ...',
        '  end if;',
        '',
        '  if ntsc_mode = \'0\' then',
        '    -- Full PAL eq/broad-sync sequence (same as pal_csync_il)',
        '    f1p := ...; f1b := ...; f1q := ...;',
        '    f2p := ...; f2b := ...; f2q := ...;',
        '    ...',
        '  else',
        '    -- NTSC: simplified -- 5 full-line broad-sync per field',
        '    if (v_cnt <= 4) or (v_cnt >= 263 and v_cnt <= 267) then',
        '      csync_s <= \'1\';   -- entire vsync line = sync tip',
        '    elsif h_cnt >= H_FRONT and h_cnt < H_FRONT + H_SYNC_W then',
        '      csync_s <= \'1\';   -- normal H sync on non-vsync lines',
        '    end if;',
        '  end if;',
        '',
        '  -- Active window: shared, uses runtime signals',
        '  if (v_cnt >= v_act_s_f1 and v_cnt <= v_act_e_f1 and h_cnt >= h_act_s) or',
        '     (v_cnt >= v_act_s_f2 and v_cnt <= v_act_e_f2 and h_cnt >= h_act_s) then',
        '    active_s <= \'1\';',
        '  end if;',
        'end process;',
    ])
    expl(doc,
         'For PAL the process replicates the full pal_csync_il logic including '
         'equalising and broad-sync pulses. For NTSC a simplified vsync is used: '
         '5 consecutive full-line broad-sync pulses (v=0..4 for F1, v=263..267 for F2). '
         'Consumer TV sets and monitors lock to this without requiring the '
         'PAL-style equalising pulses.')
    expl(doc,
         'NTSC half-line is 318 clocks (H_TOTAL=636 / 2) vs PAL\'s 320 (H_TOTAL=640 / 2). '
         'The process uses ntsc_mode to select the correct half-line boundary '
         'for the first_h variable. The active window check at the bottom uses '
         'runtime signals (v_act_s_f1, h_act_s) so it automatically adapts '
         'to whichever format is selected.')

    heading(doc, '5.7  Ball Physics: Format-Aware Boundary  (lines 568–588)', 2)
    code_block(doc, [
        '-- Bottom wall uses v_active (576 PAL / 480 NTSC)',
        'if ny > v_active - ball_h_s then',
        '  ny := 2 * (v_active - ball_h_s) - ny; nvy := -nvy;',
        'end if;',
        '',
        '-- Swap condition uses runtime v_act_e_f2 and h_total_m1',
        'elsif ce_s = \'1\' and v_cnt = v_act_e_f2 and h_cnt = h_total_m1 then',
    ])
    expl(doc,
         'In pal_tv_bram_top the bottom wall is hardcoded to 576. '
         'video_bram_top uses v_active (576 or 480) so the ball bounces within '
         'the correct screen height for the selected format. '
         'Similarly, the swap trigger and BRAM address generator use v_act_e_f2 '
         'and h_total_m1 instead of literal 623 and 639.')

    heading(doc, '5.8  DAC Output  (line 795–797)', 2)
    code_block(doc, [
        'dac_out <= "0000"       when csync_s  = \'1\' else',
        '           active_level when active_s = \'1\' else',
        '           "0100";',
    ])
    expl(doc,
         'Identical three-level priority to pal_tv_bram_top but the LEVEL_SYNC '
         'and LEVEL_BLANK constants are replaced with literal values "0000" and "0100". '
         'This avoids needing entity generics for these levels in the multi-format variant.')
    doc.add_page_break()


# ===========================================================================
# Section 6 — tb_bram_double_buf.vhd
# ===========================================================================
def sec_testbench(doc):
    heading(doc, '6  tb_bram_double_buf.vhd  —  Double-Buffer Testbench', 1)
    file_banner(doc,
                'tv/bram/tb_bram_double_buf.vhd',
                'Self-checking VHDL-2008 testbench for the double-buffer mechanism. '
                'Runs four verification phases: initial state, first swap, alternating '
                'pattern, and double-swap-request collapse. All phases print PASS/FAIL '
                'and call std.env.finish when complete.')

    heading(doc, '6.1  Testbench Constants  (lines 24–40)', 2)
    code_block(doc, [
        'constant CLK_MHZ   : integer := 10;',
        'constant CLK_P     : time    := 100 ns;',
        'constant BRAM_D    : integer := 1040;  -- two rows (fast sim)',
        '',
        'constant H_ACTIVE  : integer := 520;',
        'constant H_TOTAL   : integer := 640;',
        'constant V_ACT_S_F1 : integer := 24;',
        'constant V_ACT_E_F2 : integer := 623;',
        '',
        'constant LEVEL_WHITE : std_logic_vector(3 downto 0) := "1111";',
        'constant LEVEL_BLACK : std_logic_vector(3 downto 0) := "0100";',
    ])
    expl(doc,
         'CLK_P=100 ns gives a 10 MHz simulation clock matching CLK_MHZ=10. '
         'BRAM_D=1040 is deliberately small (2 rows) so the simulation completes '
         'in seconds instead of minutes. Two rows cover one full row-pair, '
         'enough to test interlace addressing but short enough to write quickly.')
    expl(doc,
         'LEVEL_WHITE=0xF and LEVEL_BLACK=0x4 match the DUT\'s default brightness '
         'and black_lvl settings (brightness="1111", black_lvl="0100"). '
         'These constants are used in the assertion checks to compare dac_out.')

    heading(doc, '6.2  Helper Procedures  (lines 60–108)', 2)
    code_block(doc, [
        '-- Wait for start of F1 active region',
        'procedure next_f1_line(',
        '    signal clk, active_o, field_o : in std_logic) is',
        'begin',
        '  while active_o = \'1\' loop wait until rising_edge(clk); end loop;',
        '  while not (active_o = \'1\' and field_o = \'0\') loop',
        '    wait until rising_edge(clk);',
        '  end loop;',
        'end procedure;',
        '',
        '-- Write val to every address 0..count-1',
        'procedure fill_bram(count, val, ...) is',
        'begin',
        '  for i in 0 to count - 1 loop',
        '    wr_addr <= to_unsigned(i, 19); wr_data <= val;',
        '    wr_en <= \'1\'; wait until rising_edge(clk);',
        '  end loop;',
        '  wr_en <= \'0\'; wait until rising_edge(clk);',
        'end procedure;',
    ])
    expl(doc,
         'next_f1_line first drains any currently active line (waits while active=1), '
         'then waits for the next F1 active region (active=1 and field=0). '
         'This ensures the subsequent dac_out checks read a known field. '
         'The two-step approach avoids the procedure landing mid-active-line '
         '(a bug fixed early in development — documented in BR_Bug_Report.docx).')
    expl(doc,
         'fill_bram writes count pixels synchronously. Each iteration: set address '
         'and data, assert wr_en=1, then wait one clock. After the loop, wr_en=0 '
         'is registered with one final wait to ensure the last write completes. '
         'fill_bram_alt writes an alternating 1/0 pattern: address 0=1, 1=0, 2=1, etc.')

    heading(doc, '6.3  DUT Instantiation  (lines 114–136)', 2)
    code_block(doc, [
        'dut : entity work.pal_tv_bram_top',
        '  generic map (',
        '    CLK_MHZ    => CLK_MHZ,',
        '    BRAM_DEPTH => BRAM_D)',
        '  port map (',
        '    clk => clk, rst => rst, sel => sel,',
        '    bram_wr_en   => bram_wr_en,',
        '    bram_wr_addr => bram_wr_addr,',
        '    bram_wr_data => bram_wr_data,',
        '    bram_len     => bram_len,',
        '    buf_swap     => buf_swap,',
        '    buf_swapped  => buf_swapped,',
        '    back_buf_o   => back_buf_o,',
        '    dac_out      => dac_out, ...',
        '  );',
    ])
    expl(doc,
         'sel is driven as x"04" (sel=4: BRAM mode) throughout the testbench. '
         'bram_len is set to BRAM_D=1040 so the address generator wraps at the '
         'two-row boundary. The DUT is clocked at 10 MHz (CLK_P=100 ns).')

    heading(doc, '6.4  Phase 1 — Initial State Verification  (lines 144–172)', 2)
    code_block(doc, [
        'rst <= \'1\'; wait for 5 * CLK_P; rst <= \'0\';',
        '',
        '-- Verify back_buf_o = \'1\' (buf 0 is front, buf 1 is back)',
        'if back_buf_o = \'1\' then',
        '  report "Ph1 PASS: initial back_buf_o = 1" severity note;',
        'else',
        '  report "!!! Ph1 FAIL" severity failure;',
        'end if;',
        '',
        '-- Write ALL WHITE to back buffer (buf 1)',
        'fill_bram(BRAM_D, \'1\', clk, bram_wr_en, bram_wr_addr, bram_wr_data);',
        '',
        '-- Verify display still shows BLACK (buf 0 is front, unchanged)',
        'next_f1_line(clk, active_o, field_o);',
        'ok := true;',
        'for p in 0 to H_ACTIVE - 1 loop',
        '  if dac_out /= LEVEL_BLACK then ok := false; end if;',
        '  wait until rising_edge(clk);',
        'end loop;',
        'if ok then report "Ph1 PASS: display still BLACK" severity note; ...',
    ])
    expl(doc,
         'After reset, back_buf_o should be \'1\' (back buffer = bank 1). '
         'Writing all \'1\' (white) to the back buffer should NOT affect the display '
         'because the front buffer (bank 0, all-zero = black) is still being shown. '
         'The check reads one full active line (H_ACTIVE=520 pixels) and verifies '
         'every dac_out equals LEVEL_BLACK.')

    heading(doc, '6.5  Phase 2 — First Swap and White Display  (lines 175–202)', 2)
    code_block(doc, [
        '-- Pulse buf_swap for ONE clock',
        'buf_swap <= \'1\'; wait until rising_edge(clk); buf_swap <= \'0\';',
        '',
        '-- Wait for buf_swapped strobe (fires at next V-blank)',
        'wait until buf_swapped = \'1\';',
        '',
        '-- Verify back_buf_o changed to \'0\' (buf 1 now displayed, buf 0 is back)',
        'if back_buf_o = \'0\' then report "Ph2 PASS: back_buf_o = 0" ...',
        '',
        '-- Verify display now shows WHITE',
        'next_f1_line(clk, active_o, field_o);',
        'for p in 0 to H_ACTIVE - 1 loop',
        '  if dac_out /= LEVEL_WHITE then ok := false; end if;',
        '  wait until rising_edge(clk);',
        'end loop;',
        'if ok then report "=== Ph2 PASS: display shows WHITE after swap ===" ...',
    ])
    expl(doc,
         'buf_swap is pulsed exactly one clock — the standard protocol. '
         'wait until buf_swapped = \'1\' blocks until the DUT acknowledges the swap. '
         'The swap fires at v_cnt=623, h_cnt=639, then buf_swapped strobes for one '
         'pixel clock. After the swap, the previously-written white buffer is front. '
         'The pixel check on the next F1 line verifies 520 consecutive white pixels.')

    heading(doc, '6.6  Phase 3 — Alternating Pattern  (lines 205–239)', 2)
    code_block(doc, [
        '-- Write alternating 1/0 pattern to new back buffer (buf 0)',
        'fill_bram_alt(BRAM_D, clk, ...);',
        '',
        '-- Swap to show it',
        'buf_swap <= \'1\'; wait until rising_edge(clk); buf_swap <= \'0\';',
        'wait until buf_swapped = \'1\';',
        '',
        '-- Verify pixel-by-pixel: px0=WHITE(addr0=1), px1=BLACK(addr1=0), px2=WHITE',
        'next_f1_line(clk, active_o, field_o);',
        'if dac_out = LEVEL_WHITE then report "Ph3a PASS: px0 = WHITE" ...;',
        'wait until rising_edge(clk);   -- advance to px 1',
        'if dac_out = LEVEL_BLACK then report "Ph3b PASS: px1 = BLACK" ...;',
        'wait until rising_edge(clk);   -- advance to px 2',
        'if dac_out = LEVEL_WHITE then report "=== Ph3 PASS: alternating confirmed" ...;',
    ])
    expl(doc,
         'Phase 3 verifies that the BRAM address generator correctly reads sequential '
         'addresses and that the 1-bit pixel values translate to the correct DAC levels. '
         'Address 0 was written \'1\' (white), address 1 was \'0\' (black), address 2 \'1\' (white). '
         'The test checks the first three pixels of the first active line match this pattern.')

    heading(doc, '6.7  Phase 4 — Single Swap Per V-Blank  (lines 242–259)', 2)
    code_block(doc, [
        '-- Two swap requests before V-blank — only one swap must occur',
        'fill_bram(BRAM_D, \'1\', clk, ...);',
        'buf_swap <= \'1\'; wait until rising_edge(clk); buf_swap <= \'0\';',
        'wait until rising_edge(clk);',
        'buf_swap <= \'1\'; wait until rising_edge(clk); buf_swap <= \'0\';',
        '',
        '-- Expect exactly one strobe',
        'wait until buf_swapped = \'1\';',
        'report "Ph4: first swap strobe" severity note;',
        '',
        '-- Confirm NO second strobe within 10 clock periods',
        'wait for 10 * CLK_P;',
        'if buf_swapped = \'0\' then',
        '  report "=== Ph4 PASS: only one swap per V-blank ===" severity note;',
        'else',
        '  report "!!! Ph4 FAIL: unexpected second swap strobe" severity failure;',
        'end if;',
    ])
    expl(doc,
         'Two buf_swap pulses are sent within the same frame. The DUT should only '
         'execute one swap — because after the first swap executes, swap_req is cleared '
         'and the second pulse arrives AFTER the V-blank window has closed. '
         'The test confirms exactly one buf_swapped strobe fires; buf_swapped must be '
         '\'0\' for the 10 clocks immediately after the first strobe.')
    expl(doc,
         'This test would catch a bug where the swap logic fires multiple times '
         'in rapid succession. It also validates the "one swap per frame" guarantee '
         'that prevents double-swapping from corrupting the display.')

    heading(doc, '6.8  Simulation Completion  (line 262)', 2)
    code_block(doc, ['std.env.finish;'])
    expl(doc,
         'std.env.finish is a VHDL-2008 standard procedure that terminates the '
         'simulator cleanly (exit code 0). Without this, GHDL would run forever '
         'because the clk generator `clk <= not clk after CLK_P/2` never stops. '
         'All four phases must reach this line for a successful simulation run.')
    doc.add_page_break()


# ===========================================================================
# Section 7 — Signal flow summary
# ===========================================================================
def sec_signal_flow(doc):
    heading(doc, '7  Signal Flow Summary', 1)
    body(doc,
         'The following table traces the complete signal path from input clock '
         'to final DAC output in pal_tv_bram_top:')
    rows = [
        ('clk (board)',       'Input port',
         'Board oscillator input, 10/20/30/40 MHz'),
        ('div_cnt, ce_s',     'pal_timing',
         'Clock prescaler. ce_s pulses at 10 MHz pixel rate'),
        ('h_cnt, v_cnt',      'pal_timing',
         'Raster position. h: 0..639, v: 0..624'),
        ('csync_s, field_s,\nactive_s',
         'pal_csync_il',
         'Composite sync, field indicator, active-pixel flag'),
        ('screen_x, screen_y','pal_tv_bram_top',
         'De-interlaced pixel coordinates for ball/cross'),
        ('bram_rd_addr',      'pal_tv_bram_top',
         'BRAM read address computed from line_base + px_cnt'),
        ('bram_pixel',        'BRAM array',
         'Asynchronous 1-bit read from front bank'),
        ('bram_level',        'Combinational',
         'Maps 1→white_s, 0→black_s'),
        ('active_level',      'Priority mux',
         'Selects pattern output based on sel_i'),
        ('dac_out',           'Output port',
         'Sync > active_level > LEVEL_BLANK priority'),
    ]
    tbl = doc.add_table(rows=1 + len(rows), cols=3)
    tbl.style = 'Table Grid'
    hdr = tbl.rows[0].cells
    for ci, h_ in enumerate(['Signal', 'Source', 'Description']):
        set_cell_bg(hdr[ci], C_NAVY)
        cp(hdr[ci], h_, bold=True, color=C_WHITE)
    for i, (sig, src, desc) in enumerate(rows):
        r = tbl.rows[i + 1]
        set_cell_bg(r.cells[0], C_LTBLUE)
        cp(r.cells[0], sig, font='Courier New', size=9)
        cp(r.cells[1], src, font='Courier New', size=9)
        cp(r.cells[2], desc)
    doc.add_paragraph()

    heading(doc, '7.1  Clock Domain Summary', 2)
    clk_rows = [
        ('clk (board)',    'All flip-flops in pal_tv_bram_top and video_bram_top',
         'Single clock domain; ce_s gates pixel-rate logic'),
        ('ce_s = 1',       'H/V counters, pattern generators, BRAM address, swap',
         'Advances one pixel per assertion of ce_s'),
        ('async (comb)',   'pal_csync_il, bram_pixel read, active_level mux',
         'Combinational; settles within one clock cycle'),
    ]
    tbl2 = doc.add_table(rows=1 + len(clk_rows), cols=3)
    tbl2.style = 'Table Grid'
    hdr2 = tbl2.rows[0].cells
    for ci, h_ in enumerate(['Clock domain', 'Logic affected', 'Notes']):
        set_cell_bg(hdr2[ci], C_MID)
        cp(hdr2[ci], h_, bold=True, color=C_WHITE)
    for i, (cd, la, nt) in enumerate(clk_rows):
        r = tbl2.rows[i + 1]
        set_cell_bg(r.cells[0], C_LTBLUE)
        cp(r.cells[0], cd, font='Courier New', size=9)
        cp(r.cells[1], la)
        cp(r.cells[2], nt, italic=True)
    doc.add_paragraph()


# ===========================================================================
# Main
# ===========================================================================
def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    doc = Document()

    # Page margins
    for sec in doc.sections:
        sec.top_margin    = Inches(0.9)
        sec.bottom_margin = Inches(0.9)
        sec.left_margin   = Inches(1.0)
        sec.right_margin  = Inches(1.0)

    make_title(doc)
    sec_overview(doc)
    sec_timing(doc)
    sec_csync(doc)
    sec_pal_bram(doc)
    sec_video_bram(doc)
    sec_testbench(doc)
    sec_signal_flow(doc)

    doc.save(OUT_FILE)
    print(f'Saved: {OUT_FILE}')


if __name__ == '__main__':
    main()
