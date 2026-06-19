#!/usr/bin/env python3
"""Generate PAL_Signal_Analysis.xlsx — per-half-line signal state table.

Values per cell:
  Full     — signal active for the entire line (both halves)
  1st Half — active only in h_cnt 0..319
  2nd Half — active only in h_cnt 320..639
  NA       — not active
"""

import openpyxl
from openpyxl.styles import PatternFill, Font, Alignment, Border, Side
from openpyxl.utils import get_column_letter

# ---------------------------------------------------------------------------
# PAL timing constants (must match VHDL generics)
# H_ACT_S = H_FRONT(16) + H_SYNC_W(47) + H_BACK(57) = 120
# ---------------------------------------------------------------------------
H_TOTAL     = 640
H_HALF      = 320          # half-line boundary
H_ACT_S     = 120          # active video starts at pixel 120
V_TOTAL     = 625

V_ACT_S_F1  = 25           # F1 active start (v_cnt)
V_ACT_E_F1  = 311          # F1 active end   (v_cnt)
V_ACT_S_F2  = 337          # F2 active start (v_cnt)
V_ACT_E_F2  = 623          # F2 active end   (v_cnt)

# F1 sync region (v_cnt 0-7)
FSS_F1_S    = 3            # FSS F1 start (v_cnt)
FSS_F1_E    = 7            # FSS F1 end   (v_cnt)

# F2 sync region (half-line offset — starts at 2nd half of v_cnt=312)
# Pre-eq:  v_cnt=312 2nd half, v_cnt=313 full, v_cnt=314 full
# Broad:   v_cnt=315 full,     v_cnt=316 full,  v_cnt=317 1st half
# Post-eq: v_cnt=317 2nd half, v_cnt=318 full,  v_cnt=319 full
FSS_F2_SV   = 315          # FSS F2 starts at this v_cnt, h >= FSS_F2_SH
FSS_F2_SH   = 320          # FSS F2 h_cnt start (2nd half of scope line 316)
FSS_F2_EV   = 320          # FSS F2 ends at this v_cnt, h < FSS_F2_EH
FSS_F2_EH   = 320          # FSS F2 h_cnt end   (1st half of scope line 321)

LS_FRONT    = 16           # H-sync starts at h_cnt=16
LS_WIDTH    = 47           # H-sync width 47 pixels → ends at h_cnt=62


def classify_line(v: int) -> dict:
    """Classify all PAL signals for v_cnt=v (0-based).

    F1 sync (v_cnt 0-7, starts at h=0 of v_cnt=0):
      Pre-eq  v=0,1 : Full  (pulse at h=0  AND h=320 each line)
      Pre-eq  v=2   : 1st Half  (5th pre-eq pulse, 1st half only)
      Broad   v=2   : 2nd Half  (1st broad pulse, 2nd half only)
      Broad   v=3,4 : Full
      Post-eq v=5,6 : Full
      Post-eq v=7   : 1st Half  (5th post-eq pulse, 1st half only)

    F2 sync (v_cnt 312-319, starts at h=320 of v_cnt=312 — half-line offset):
      Pre-eq  v=312 : 2nd Half  (1st pre-eq pulse, 2nd half only)
      Pre-eq  v=313,314 : Full
      Broad   v=315,316 : Full
      Broad   v=317 : 1st Half  (5th broad pulse, 1st half only)
      Post-eq v=317 : 2nd Half  (1st post-eq pulse, 2nd half only)
      Post-eq v=318,319 : Full

    FSS F2 (VHDL: v=315 h>=320, v=316-319 full, v=320 h<320):
      v=315 : 2nd Half
      v=316-319 : Full
      v=320 : 1st Half

    LS absent during all special-pulse lines (F1: v=0-7, F2: v=313-319).
    v=312 is a mixed line: normal H-sync in 1st half, pre-eq pulse in 2nd half.
    """
    in_f1     = (V_ACT_S_F1 <= v <= V_ACT_E_F1)
    in_f2     = (V_ACT_S_F2 <= v <= V_ACT_E_F2)
    in_active = in_f1 or in_f2

    # ---- LS ------------------------------------------------------------------
    # F1 sync region: v=0..7  → NA (special pulses replace H-sync)
    # F2 mixed line:  v=312   → 1st Half (H-sync still fires in 1st half)
    # F2 sync region: v=313..319 → NA (special pulses in both halves)
    # All other lines (incl. v=320+) → 1st Half
    if v <= 7 or (313 <= v <= 319):
        ls = 'NA'
    else:
        ls = '1st Half'

    # ---- FSS -----------------------------------------------------------------
    # F1: plain range v=3..7 → Full
    # F2: v=315 2nd half, v=316-319 full, v=320 1st half (matches VHDL h_cnt conditions)
    if FSS_F1_S <= v <= FSS_F1_E:
        fss = 'Full'
    elif v == FSS_F2_SV:          # v=315, FSS starts at h>=320 → 2nd Half
        fss = '2nd Half'
    elif FSS_F2_SV < v < FSS_F2_EV:   # v=316..319 → Full
        fss = 'Full'
    elif v == FSS_F2_EV:          # v=320, FSS active for h<320 → 1st Half
        fss = '1st Half'
    else:
        fss = 'NA'

    # ---- CB ------------------------------------------------------------------
    cb = '1st Half' if in_active else 'Full'

    # ---- Video ---------------------------------------------------------------
    video = 'Full' if in_active else 'NA'

    # ---- Blank ---------------------------------------------------------------
    blank = 'NA' if in_active else 'Full'

    # ---- Pre-equalising ------------------------------------------------------
    # F1: v=0,1 → Full;  v=2 → 1st Half
    # F2: v=312 → 2nd Half;  v=313,314 → Full
    if v == 0 or v == 1:
        pre = 'Full'
    elif v == 2:
        pre = '1st Half'
    elif v == 312:
        pre = '2nd Half'
    elif v == 313 or v == 314:
        pre = 'Full'
    else:
        pre = 'NA'

    # ---- Broad sync ----------------------------------------------------------
    # F1: v=2 → 2nd Half;  v=3,4 → Full
    # F2: v=315,316 → Full;  v=317 → 1st Half
    if v == 2:
        broad = '2nd Half'
    elif v == 3 or v == 4:
        broad = 'Full'
    elif v == 315 or v == 316:
        broad = 'Full'
    elif v == 317:
        broad = '1st Half'
    else:
        broad = 'NA'

    # ---- Post-equalising -----------------------------------------------------
    # F1: v=5,6 → Full;  v=7 → 1st Half
    # F2: v=317 → 2nd Half;  v=318,319 → Full
    if v == 5 or v == 6:
        post = 'Full'
    elif v == 7:
        post = '1st Half'
    elif v == 317:
        post = '2nd Half'
    elif v == 318 or v == 319:
        post = 'Full'
    else:
        post = 'NA'

    return {
        'Line':  v + 1,
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
# Scope lines to include
# ---------------------------------------------------------------------------
scope_lines = (
    list(range(1, 26))              +   # scope lines 1-25  (F1 VBI sync + blank)
    [26, 27, 28, 29]                +   # first active F1 lines
    list(range(311, 322))           +   # end F1 active → full F2 sync region (311-321)
    [337, 338, 339, 340]            +   # start of F2 active
    [623, 624, 625]                     # end of frame
)


# ---------------------------------------------------------------------------
# Colour palette
# ---------------------------------------------------------------------------
C_PRE     = 'FFB3C6'   # pink       — pre-equalising rows
C_BROAD   = 'FFCC99'   # orange     — broad sync rows
C_POST    = 'CCB3FF'   # lavender   — post-equalising rows
C_BLANK   = 'D9D9D9'   # light grey — VBI blank rows
C_ACTIVE  = 'B3FFB3'   # light green— active video rows
C_FULL    = None        # inherit row background  (bold)
C_1ST     = 'FFE699'   # amber      — 1st Half cells
C_2ND     = 'FFCC80'   # light orange — 2nd Half cells
C_NA      = 'F2F2F2'   # pale grey  — NA cells
C_HDR     = '1F4E79'   # dark blue  — header
C_HDR_FG  = 'FFFFFF'


def row_bg(v: int) -> str:
    # F1 sync region
    if v <= 1:                          return C_PRE
    if v == 2:                          return C_BROAD   # mixed: pre 1st half, broad 2nd half
    if v == 3 or v == 4:               return C_BROAD
    if 5 <= v <= 7:                    return C_POST
    # Active video
    if V_ACT_S_F1 <= v <= V_ACT_E_F1: return C_ACTIVE
    if V_ACT_S_F2 <= v <= V_ACT_E_F2: return C_ACTIVE
    # F2 sync region (half-line offset: starts at 2nd half of v=312)
    if v == 312:                        return C_BROAD   # mixed: LS 1st half, pre 2nd half
    if v == 313 or v == 314:           return C_PRE
    if v == 315 or v == 316:           return C_BROAD
    if v == 317:                        return C_POST    # mixed: broad 1st, post 2nd
    if v == 318 or v == 319:           return C_POST
    return C_BLANK


def make_fill(hex_color: str) -> PatternFill:
    return PatternFill(fill_type='solid', fgColor=hex_color)


def make_border() -> Border:
    s = Side(style='thin', color='AAAAAA')
    return Border(left=s, right=s, top=s, bottom=s)


# ---------------------------------------------------------------------------
# Build workbook
# ---------------------------------------------------------------------------
wb  = openpyxl.Workbook()
ws  = wb.active
ws.title = "PAL Signal States"

COLUMNS    = ['Line', 'LS', 'FSS', 'CB', 'Video', 'Blank', 'Post', 'Broad', 'Pre']
COL_WIDTHS = [7, 10, 10, 10, 10, 10, 10, 10, 10]

bdr = make_border()

# Header row
hdr_font  = Font(bold=True, color=C_HDR_FG, name='Calibri', size=11)
hdr_fill  = make_fill(C_HDR)
hdr_align = Alignment(horizontal='center', vertical='center')

for ci, (col, width) in enumerate(zip(COLUMNS, COL_WIDTHS), start=1):
    cell = ws.cell(row=1, column=ci, value=col)
    cell.font      = hdr_font
    cell.fill      = hdr_fill
    cell.alignment = hdr_align
    cell.border    = bdr
    ws.column_dimensions[get_column_letter(ci)].width = width

ws.row_dimensions[1].height = 22

# Data rows
for row_idx, scope in enumerate(scope_lines, start=2):
    v  = scope - 1
    d  = classify_line(v)
    bg = row_bg(v)

    for ci, col in enumerate(COLUMNS, start=1):
        val  = d[col]
        cell = ws.cell(row=row_idx, column=ci, value=val)
        cell.alignment = Alignment(horizontal='center', vertical='center', wrap_text=False)
        cell.border    = bdr

        if col == 'Line':
            cell.fill = make_fill(bg)
            cell.font = Font(bold=True, name='Calibri', size=10)
        elif val == 'Full':
            cell.fill = make_fill(bg)
            cell.font = Font(bold=True, name='Calibri', size=10, color='000000')
        elif val == '1st Half':
            cell.fill = make_fill(C_1ST)
            cell.font = Font(bold=True, name='Calibri', size=9, color='5C3D00')
        elif val == '2nd Half':
            cell.fill = make_fill(C_2ND)
            cell.font = Font(bold=True, name='Calibri', size=9, color='7F3300')
        else:  # NA
            cell.fill = make_fill(C_NA)
            cell.font = Font(name='Calibri', size=10, color='999999')

    ws.row_dimensions[row_idx].height = 17

ws.freeze_panes = 'A2'

# ---------------------------------------------------------------------------
# Legend sheet
# ---------------------------------------------------------------------------
lg = wb.create_sheet("Legend")
legend = [
    ('Value',       'Meaning',                                              C_HDR),
    ('Full',        'Signal active for entire line (both halves)',          C_ACTIVE),
    ('1st Half',    'Signal active in 1st half only  (h_cnt 0..319)',      C_1ST),
    ('2nd Half',    'Signal active in 2nd half only  (h_cnt 320..639)',    C_2ND),
    ('NA',          'Signal not active on this line',                       C_NA),
    ('',            '',                                                     'FFFFFF'),
    ('Row colour',  'Meaning',                                              C_HDR),
    ('Pink',        'Pre-equalising region  (v_cnt 0-1, first half of 2)', C_PRE),
    ('Orange',      'Broad sync region      (v_cnt 2 2nd half, 3, 4)',    C_BROAD),
    ('Lavender',    'Post-equalising region (v_cnt 5-6, first half of 7)',C_POST),
    ('Light grey',  'VBI blank lines        (v_cnt 8 .. V_ACT_S_F1-1)',   C_BLANK),
    ('Light green', 'Active video lines     (F1 v25-311, F2 v337-623)',   C_ACTIVE),
]

lg.column_dimensions['A'].width = 14
lg.column_dimensions['B'].width = 54

for ri, (sym, desc, colour) in enumerate(legend, start=1):
    is_hdr = (sym in ('Value', 'Row colour'))
    ca  = lg.cell(row=ri, column=1, value=sym)
    cb_ = lg.cell(row=ri, column=2, value=desc)
    fill = make_fill(colour)
    ca.fill  = fill;  cb_.fill  = fill
    ca.border = bdr;  cb_.border = bdr
    ca.alignment = Alignment(horizontal='center', vertical='center')
    cb_.alignment = Alignment(horizontal='left', vertical='center')
    if is_hdr:
        ca.font  = Font(bold=True, color='FFFFFF', name='Calibri', size=10)
        cb_.font = Font(bold=True, color='FFFFFF', name='Calibri', size=10)
    else:
        ca.font  = Font(bold=(sym not in ('', 'NA')), name='Calibri', size=10)
        cb_.font = Font(name='Calibri', size=10)
    lg.row_dimensions[ri].height = 17

# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------
out_path = 'docs/PAL_Signal_Analysis.xlsx'
wb.save(out_path)
print(f"Saved: {out_path}")
print(f"Total rows: {len(scope_lines)} data + 1 header = {len(scope_lines)+1}")
