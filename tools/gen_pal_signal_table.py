#!/usr/bin/env python3
"""Generate PAL_Signal_Analysis.xlsx — scope-line signal state table."""

import openpyxl
from openpyxl.styles import PatternFill, Font, Alignment, Border, Side
from openpyxl.utils import get_column_letter

# ---------------------------------------------------------------------------
# PAL timing constants (must match VHDL generics)
# ---------------------------------------------------------------------------
H_TOTAL     = 640
H_ACT_S     = 144      # active video starts at pixel 144
V_TOTAL     = 625

# Active video window (v_cnt values, inclusive)
V_ACT_S_F1  = 25       # F1 active start
V_ACT_E_F1  = 311      # F1 active end
V_ACT_S_F2  = 337      # F2 active start
V_ACT_E_F2  = 623      # F2 active end

# Pre-equalising:  v_cnt 0, 1, and first half of 2
# Broad sync:      second half of 2, all of 3, all of 4
# Post-equalising: v_cnt 5, 6, and first half of 7
# FSS active:      v_cnt 3 .. 7  (F1)
FSS_F1_S    = 3
FSS_F1_E    = 7

# Line sync (H-sync): h_cnt 16 .. 62  (width 47)
LS_FRONT    = 16
LS_WIDTH    = 47


def classify_line(v: int):
    """Return signal states for a given v_cnt (0-based).

    Returns dict: {col_name: value_string}
    value_string is 'A', 'NA', or 'Half Signal'
    """
    scope = v + 1          # scope line number (1-based for F1)

    # ---- LS (horizontal line sync) ----------------------------------------
    # Standard H-sync is ABSENT during the entire sync pulse region (v_cnt 0-7):
    # pre-equalising, broad sync, and post-equalising ALL replace the normal LS.
    # Normal H-sync resumes from line 9 (v_cnt=8) onwards.
    if v <= 7:
        ls = 'NA'
    else:
        ls = 'A'

    # ---- FSS (Field Sync Signal) -------------------------------------------
    # VHDL uses a plain range check: v_cnt >= FSS_F1_S and v_cnt <= FSS_F1_E
    # so FSS is HIGH for the FULL LINE at every v_cnt in 3..7 (scope lines 4-8).
    if FSS_F1_S <= v <= FSS_F1_E:
        fss = 'A'
    else:
        fss = 'NA'

    # Composite Blank is HIGH (blanked) for ALL lines in the VBI and for the
    # H-blank portion of active lines.  For the scope-line granularity table
    # we mark it 'A' for all VBI lines (always blanked full line) and 'A' for
    # active lines too (CB goes low only within the active pixel window).
    cb = 'A'

    # ---- Video (active picture content) ------------------------------------
    in_active_f1 = (V_ACT_S_F1 <= v <= V_ACT_E_F1)
    in_active_f2 = (V_ACT_S_F2 <= v <= V_ACT_E_F2)
    video = 'A' if (in_active_f1 or in_active_f2) else 'NA'

    # ---- Blank (composite blank asserted — opposite of video) --------------
    blank = 'NA' if video == 'A' else 'A'

    # ---- Post-equalising ---------------------------------------------------
    # v_cnt 5, 6 = full; v_cnt 7 = first half only
    if v == 5 or v == 6:
        post = 'A'
    elif v == 7:
        post = 'Half Signal'
    else:
        post = 'NA'

    # ---- Broad sync --------------------------------------------------------
    # v_cnt 3, 4 = full; v_cnt 2 = second half only
    if v == 3 or v == 4:
        broad = 'A'
    elif v == 2:
        broad = 'Half Signal'
    else:
        broad = 'NA'

    # ---- Pre-equalising ----------------------------------------------------
    # v_cnt 0, 1 = full; v_cnt 2 = first half only
    if v == 0 or v == 1:
        pre = 'A'
    elif v == 2:
        pre = 'Half Signal'
    else:
        pre = 'NA'

    return {
        'Line':  scope,
        'LS':    ls,
        'FSS':   fss,
        'CB':    cb,
        'Video': video,
        'Blank': blank,
        'Post':  post,
        'Broad': broad,
        'Pre':   pre,
    }


# ---------------------------------------------------------------------------
# Lines to include (scope lines, 1-based)
# VBI: 1-24 (v_cnt 0-23), then a few active lines 25-28, then mid-field gap
# F1 active end  311-313, F2 start 337-339, F2 end 622-625
# ---------------------------------------------------------------------------
scope_lines = (
    list(range(1, 25))          +   # full VBI / sync region
    [25, 26, 27, 28]            +   # first active lines F1
    [310, 311, 312, 313]        +   # end of F1 active
    [336, 337, 338, 339]        +   # start of F2 active
    [622, 623, 624, 625]            # end of F2 active / frame end
)


# ---------------------------------------------------------------------------
# Colour palette
# ---------------------------------------------------------------------------
C_PRE    = 'FFB3C6'   # pink  — pre-equalising
C_BROAD  = 'FFCC99'   # orange — broad sync
C_POST   = 'CCB3FF'   # lavender — post-equalising
C_FSS    = 'FFFFB3'   # yellow — FSS active (overlaps sync)
C_BLANK  = 'D9D9D9'   # light grey — blanked non-sync
C_ACTIVE = 'B3FFB3'   # light green — active video
C_HALF   = 'FFE699'   # amber — Half Signal cells
C_HDR    = '1F4E79'   # dark blue — header row
C_HDR_FG = 'FFFFFF'   # white text in header
C_NA     = 'F2F2F2'   # very light grey for NA cells

# Row background based on region
def row_fill(v: int) -> str:
    if v == 0 or v == 1:         return C_PRE
    if v == 2:                   return C_BROAD  # mixed, use broad colour
    if v == 3 or v == 4:         return C_BROAD
    if 5 <= v <= 7:              return C_POST
    if V_ACT_S_F1 <= v <= V_ACT_E_F1: return C_ACTIVE
    if V_ACT_S_F2 <= v <= V_ACT_E_F2: return C_ACTIVE
    return C_BLANK


def make_fill(hex_color: str) -> PatternFill:
    return PatternFill(fill_type='solid', fgColor=hex_color)


def make_border() -> Border:
    thin = Side(style='thin', color='AAAAAA')
    return Border(left=thin, right=thin, top=thin, bottom=thin)


# ---------------------------------------------------------------------------
# Build workbook
# ---------------------------------------------------------------------------
wb = openpyxl.Workbook()
ws = wb.active
ws.title = "PAL F1 Signal States"

COLUMNS = ['Line', 'LS', 'FSS', 'CB', 'Video', 'Blank', 'Post', 'Broad', 'Pre']
COL_WIDTHS = [8, 8, 8, 8, 8, 8, 8, 8, 8]

# Header row
hdr_font  = Font(bold=True, color=C_HDR_FG, name='Calibri', size=11)
hdr_fill  = make_fill(C_HDR)
hdr_align = Alignment(horizontal='center', vertical='center')
bdr       = make_border()

for ci, (col, width) in enumerate(zip(COLUMNS, COL_WIDTHS), start=1):
    cell = ws.cell(row=1, column=ci, value=col)
    cell.font      = hdr_font
    cell.fill      = hdr_fill
    cell.alignment = hdr_align
    cell.border    = bdr
    ws.column_dimensions[get_column_letter(ci)].width = width

ws.row_dimensions[1].height = 20

# Data rows
for row_idx, scope in enumerate(scope_lines, start=2):
    v = scope - 1    # v_cnt (0-based)
    d = classify_line(v)
    bg = row_fill(v)

    for ci, col in enumerate(COLUMNS, start=1):
        val = d[col]
        cell = ws.cell(row=row_idx, column=ci, value=val)
        cell.alignment = Alignment(horizontal='center', vertical='center')
        cell.border    = bdr

        if col == 'Line':
            cell.fill = make_fill(bg)
            cell.font = Font(bold=True, name='Calibri', size=10)
        elif val == 'A':
            cell.fill = make_fill(bg)
            cell.font = Font(bold=True, name='Calibri', size=10, color='000000')
        elif val == 'Half Signal':
            cell.fill = make_fill(C_HALF)
            cell.font = Font(bold=True, name='Calibri', size=9, color='7F4F00')
        else:  # NA
            cell.fill = make_fill(C_NA)
            cell.font = Font(name='Calibri', size=10, color='999999')

    ws.row_dimensions[row_idx].height = 16

# Freeze header row
ws.freeze_panes = 'A2'

# ---------------------------------------------------------------------------
# Legend sheet
# ---------------------------------------------------------------------------
ls = wb.create_sheet("Legend")
legend_items = [
    ('A',           'Applicable — signal is fully active this line',    'B3FFB3'),
    ('NA',          'Not applicable — signal is inactive',              'F2F2F2'),
    ('Half Signal', 'Active for approx half the line (sub-line event)', C_HALF),
    ('',            '',                                                  'FFFFFF'),
    ('Row colours', '',                                                  C_HDR),
    ('Pink',        'Pre-equalising pulses (v_cnt 0-2 first half)',     C_PRE),
    ('Orange',      'Broad sync pulses (v_cnt 2 second half – 4)',      C_BROAD),
    ('Lavender',    'Post-equalising pulses (v_cnt 5-7 first half)',    C_POST),
    ('Light grey',  'Blanked non-sync lines (VBI lines 8-24)',          C_BLANK),
    ('Light green', 'Active video lines (F1 25-311, F2 337-623)',       C_ACTIVE),
]

ls.column_dimensions['A'].width = 16
ls.column_dimensions['B'].width = 52
hdr2 = make_fill(C_HDR)
for ri, (symbol, desc, colour) in enumerate(legend_items, start=1):
    ca = ls.cell(row=ri, column=1, value=symbol)
    cb_ = ls.cell(row=ri, column=2, value=desc)
    if symbol == 'Row colours':
        ca.fill = hdr2
        cb_.fill = hdr2
        ca.font = Font(bold=True, color='FFFFFF', name='Calibri')
        cb_.font = Font(bold=True, color='FFFFFF', name='Calibri')
    else:
        ca.fill = make_fill(colour)
        cb_.fill = make_fill(colour)
        ca.font = Font(name='Calibri', size=10)
        cb_.font = Font(name='Calibri', size=10)
    ca.border = bdr
    cb_.border = bdr
    ca.alignment = Alignment(horizontal='center', vertical='center')

# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------
out_path = 'docs/PAL_Signal_Analysis.xlsx'
wb.save(out_path)
print(f"Saved: {out_path}")
print(f"Rows: {len(scope_lines)} data rows  +  1 header  =  {len(scope_lines)+1} total")
