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

FSS_F1_S    = 3            # FSS F1 start (v_cnt)
FSS_F1_E    = 7            # FSS F1 end   (v_cnt)

LS_FRONT    = 16           # H-sync starts at h_cnt=16
LS_WIDTH    = 47           # H-sync width 47 pixels → ends at h_cnt=62


def classify_line(v: int) -> dict:
    """Classify all PAL signals for v_cnt=v.

    PAL half-line structure per region:
      Pre-eq  v_cnt 0,1 : 2 narrow pulses per line (at h=0 and h=320) → Full
      Pre-eq  v_cnt 2   : 1 narrow pulse in 1st half only              → 1st Half
      Broad   v_cnt 2   : 1 wide   pulse in 2nd half only              → 2nd Half
      Broad   v_cnt 3,4 : 2 wide   pulses per line (at h=0 and h=320) → Full
      Post-eq v_cnt 5,6 : 2 narrow pulses per line (at h=0 and h=320) → Full
      Post-eq v_cnt 7   : 1 narrow pulse in 1st half only              → 1st Half

      LS (H-sync) present on all lines EXCEPT v_cnt 0-7 (special pulses replace it).
      H-sync is a narrow pulse at h_cnt=16..62 → always 1st Half when present.

      FSS: VHDL plain range check v_cnt 3..7 → Full for those lines.

      CB (Composite Blank):
        VBI lines : asserted for entire line     → Full
        Active    : asserted during H-blank only (h_cnt 0..119) → 1st Half

      Video (active picture, starts at h_cnt=120):
        Active lines : h_cnt 120..639 crosses midpoint → Full
        VBI lines    : NA

      Blank (is this line a VBI/blank line?):
        VBI lines    : Full
        Active lines : NA
    """
    in_f1 = (V_ACT_S_F1 <= v <= V_ACT_E_F1)
    in_f2 = (V_ACT_S_F2 <= v <= V_ACT_E_F2)
    in_active = in_f1 or in_f2

    # LS
    if v <= 7:
        ls = 'NA'
    else:
        ls = '1st Half'          # H-sync at h_cnt 16..62, always 1st half

    # FSS
    if FSS_F1_S <= v <= FSS_F1_E:
        fss = 'Full'
    else:
        fss = 'NA'

    # CB
    if in_active:
        cb = '1st Half'          # H-blank h_cnt 0..119 only
    else:
        cb = 'Full'              # entire VBI line is blanked

    # Video
    video = 'Full' if in_active else 'NA'
    # (active picture spans h_cnt 120..639, crosses midpoint 320 → both halves)

    # Blank
    blank = 'NA' if in_active else 'Full'

    # Pre-equalising
    if v == 0 or v == 1:
        pre = 'Full'             # pulse at h=0 AND pulse at h=320
    elif v == 2:
        pre = '1st Half'         # 5th (final) pre-eq pulse in 1st half only
    else:
        pre = 'NA'

    # Broad sync
    if v == 2:
        broad = '2nd Half'       # 1st broad pulse starts at h=320
    elif v == 3 or v == 4:
        broad = 'Full'           # pulse at h=0 AND pulse at h=320
    else:
        broad = 'NA'

    # Post-equalising
    if v == 5 or v == 6:
        post = 'Full'            # pulse at h=0 AND pulse at h=320
    elif v == 7:
        post = '1st Half'        # 5th (final) post-eq pulse in 1st half only
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
    list(range(1, 26))          +   # scope lines 1-25  (full VBI + first active transition)
    [26, 27, 28, 29]            +   # first active F1 lines
    [311, 312, 313, 314]        +   # end of F1 active → F2 VBI
    [337, 338, 339, 340]        +   # start of F2 active
    [623, 624, 625]                 # end of frame
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
    if v <= 1:                          return C_PRE
    if v == 2:                          return C_BROAD   # mixed line, use broad colour
    if v == 3 or v == 4:               return C_BROAD
    if 5 <= v <= 7:                    return C_POST
    if V_ACT_S_F1 <= v <= V_ACT_E_F1: return C_ACTIVE
    if V_ACT_S_F2 <= v <= V_ACT_E_F2: return C_ACTIVE
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
