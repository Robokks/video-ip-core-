#!/usr/bin/env python3
"""Generate PAL_Signal_Analysis.xlsx — Old tester vs New tester (v3) comparison.

NEW tester constants taken directly from tv/bram/pal_tv_bram_lite_v3.vhd generics.
OLD tester constants derived from oscilloscope comparison notes.

Cell values:
  Full     — signal active full line (both halves)
  1st Half — h_cnt 0..319 only
  2nd Half — h_cnt 320..639 only
  NA       — not active
"""

import openpyxl
from openpyxl.styles import PatternFill, Font, Alignment, Border, Side
from openpyxl.utils import get_column_letter

# ---------------------------------------------------------------------------
# NEW tester — from pal_tv_bram_lite_v3.vhd generic defaults
# ---------------------------------------------------------------------------
H_FRONT    = 16
H_SYNC_W   = 47
H_BACK     = 57
H_ACT_S_NEW = H_FRONT + H_SYNC_W + H_BACK   # = 120
H_HALF      = 320
H_TOTAL     = 640

V_ACT_S_F1_NEW = 25    # v_cnt → scope line 26
V_ACT_E_F1     = 311
V_ACT_S_F2_NEW = 337   # v_cnt → scope line 338
V_ACT_E_F2     = 623

FSS_F1_S = 3;  FSS_F1_E = 7
FSS_F2_SV = 315; FSS_F2_SH = 320; FSS_F2_EV = 320; FSS_F2_EH = 320

# ---------------------------------------------------------------------------
# OLD tester — from oscilloscope comparison (before v3 fix)
# Line 22 Old=Blank  Line 23 Old=1st Half Blank / 2nd Half Video
# F2: Old blank 319-335, Old video starts scope 336
# ---------------------------------------------------------------------------
H_ACT_S_OLD    = 320   # video started at midpoint only (2nd half)
V_ACT_S_F1_OLD = 22    # v_cnt → scope line 23 (1st half blank, 2nd half video)
V_ACT_S_F2_OLD = 335   # v_cnt → scope line 336


def classify(v, v_act_s_f1, v_act_s_f2, h_act_s):
    """Return signal dict for v_cnt=v with given active-start constants."""
    in_f1     = v_act_s_f1 <= v <= V_ACT_E_F1
    in_f2     = v_act_s_f2 <= v <= V_ACT_E_F2
    act       = in_f1 or in_f2

    # LS: absent during F1 sync (v=0-7) and F2 sync (v=313-319)
    if v <= 7 or (313 <= v <= 319):
        ls = 'NA'
    else:
        ls = '1st Half'   # H-sync at h_cnt 16..62, always in 1st half

    # FSS F1 plain range; FSS F2 sub-line boundaries
    if FSS_F1_S <= v <= FSS_F1_E:         fss = 'Full'
    elif v == FSS_F2_SV:                   fss = '2nd Half'   # starts at h>=320
    elif FSS_F2_SV < v < FSS_F2_EV:       fss = 'Full'
    elif v == FSS_F2_EV:                   fss = '1st Half'   # ends at h<320
    else:                                  fss = 'NA'

    # CB (Composite Blank)
    if not act:
        cb = 'Full'
    elif h_act_s <= H_HALF:
        cb = '1st Half'        # blank h_cnt 0..h_act_s-1, within 1st half
    else:
        cb = 'Full'            # h_act_s=320 → blank spans entire 1st half + starts 2nd

    # Video
    if not act:
        video = 'NA'
    elif h_act_s < H_HALF:
        video = 'Full'         # starts before midpoint → spans both halves
    else:
        video = '2nd Half'     # h_act_s=320: video starts exactly at midpoint (2nd half only)

    # Blank
    if not act:
        blank = 'Full'
    elif h_act_s < H_HALF:
        blank = 'NA'
    else:
        blank = '1st Half'     # h_cnt 0..319 still blanked (h_act_s >= 320)

    # Pre-equalising (F1: v=0,1 full, v=2 1st half; F2: v=312 2nd half, v=313,314 full)
    if v in (0, 1):            pre = 'Full'
    elif v == 2:               pre = '1st Half'
    elif v == 312:             pre = '2nd Half'
    elif v in (313, 314):      pre = 'Full'
    else:                      pre = 'NA'

    # Broad sync (F1: v=2 2nd half, v=3,4 full; F2: v=315,316 full, v=317 1st half)
    if v == 2:                 broad = '2nd Half'
    elif v in (3, 4):          broad = 'Full'
    elif v in (315, 316):      broad = 'Full'
    elif v == 317:             broad = '1st Half'
    else:                      broad = 'NA'

    # Post-equalising (F1: v=5,6 full, v=7 1st half; F2: v=317 2nd half, v=318,319 full)
    if v in (5, 6):            post = 'Full'
    elif v == 7:               post = '1st Half'
    elif v == 317:             post = '2nd Half'
    elif v in (318, 319):      post = 'Full'
    else:                      post = 'NA'

    return {'LS': ls, 'FSS': fss, 'CB': cb, 'Video': video,
            'Blank': blank, 'Post': post, 'Broad': broad, 'Pre': pre}


# ---------------------------------------------------------------------------
# Scope lines — covers all key transition regions for BOTH old and new
# ---------------------------------------------------------------------------
scope_lines = sorted(set(
    list(range(1, 26))      +   # F1 sync + VBI blank (same both)
    list(range(22, 30))     +   # OLD video start: scope 23  NEW: scope 26
    list(range(311, 322))   +   # end F1 active + full F2 sync
    list(range(334, 342))   +   # OLD F2 video: scope 336  NEW: scope 338
    [622, 623, 624, 625]        # end of frame
))

# ---------------------------------------------------------------------------
# Colours
# ---------------------------------------------------------------------------
C_PRE   = 'FFB3C6'; C_BROAD = 'FFCC99'; C_POST  = 'CCB3FF'
C_BLANK = 'D9D9D9'; C_ACT   = 'B3FFB3'
C_1ST   = 'FFE699'; C_2ND   = 'FFCC80'; C_NA    = 'F2F2F2'
C_DIFF  = 'FFFF80'   # yellow = changed between old and new
C_HDR   = '1F4E79'; C_OLDHDR = 'C00000'; C_NEWHDR = '375623'


def row_bg(v):
    if v <= 1:                              return C_PRE
    if v in (2, 3, 4):                    return C_BROAD
    if 5 <= v <= 7:                        return C_POST
    if V_ACT_S_F1_NEW <= v <= V_ACT_E_F1: return C_ACT
    if V_ACT_S_F2_NEW <= v <= V_ACT_E_F2: return C_ACT
    if v == 312:                            return C_BROAD
    if v in (313, 314):                    return C_PRE
    if v in (315, 316):                    return C_BROAD
    if v in (317, 318, 319):               return C_POST
    return C_BLANK


def mf(c): return PatternFill(fill_type='solid', fgColor=c)
def mb():
    s = Side(style='thin', color='AAAAAA')
    return Border(left=s, right=s, top=s, bottom=s)


def put(ws, row, col, val, bg, diff):
    if diff:                 fill = mf(C_DIFF)
    elif val == 'Full':      fill = mf(bg)
    elif val == '1st Half':  fill = mf(C_1ST)
    elif val == '2nd Half':  fill = mf(C_2ND)
    else:                    fill = mf(C_NA)
    bold  = val != 'NA'
    color = '000000' if val != 'NA' else '999999'
    size  = 9 if 'Half' in val else 10
    c = ws.cell(row=row, column=col, value=val)
    c.fill = fill
    c.font = Font(bold=bold, name='Calibri', size=size, color=color)
    c.alignment = Alignment(horizontal='center', vertical='center')
    c.border = mb()


# ---------------------------------------------------------------------------
# Build workbook
# ---------------------------------------------------------------------------
wb = openpyxl.Workbook()
ws = wb.active
ws.title = "Old vs New (v3)"

SIG = ['LS', 'FSS', 'CB', 'Video', 'Blank', 'Post', 'Broad', 'Pre']

ws.column_dimensions['A'].width = 7
for ci in range(2, 18):
    ws.column_dimensions[get_column_letter(ci)].width = 10

# Header
hf = Font(bold=True, color='FFFFFF', name='Calibri')
c = ws.cell(row=1, column=1, value='Line')
c.fill = mf(C_HDR); c.font = hf; c.border = mb()
c.alignment = Alignment(horizontal='center', vertical='center')

for ci, s in enumerate(SIG, 2):
    c = ws.cell(row=1, column=ci, value=f'OLD\n{s}')
    c.fill = mf(C_OLDHDR); c.font = Font(bold=True, color='FFFFFF', name='Calibri', size=9)
    c.alignment = Alignment(horizontal='center', vertical='center', wrap_text=True)
    c.border = mb()

for ci, s in enumerate(SIG, 10):
    c = ws.cell(row=1, column=ci, value=f'NEW v3\n{s}')
    c.fill = mf(C_NEWHDR); c.font = Font(bold=True, color='FFFFFF', name='Calibri', size=9)
    c.alignment = Alignment(horizontal='center', vertical='center', wrap_text=True)
    c.border = mb()

ws.row_dimensions[1].height = 30

# Data
for ri, scope in enumerate(scope_lines, start=2):
    v  = scope - 1
    bg = row_bg(v)
    do = classify(v, V_ACT_S_F1_OLD, V_ACT_S_F2_OLD, H_ACT_S_OLD)
    dn = classify(v, V_ACT_S_F1_NEW, V_ACT_S_F2_NEW, H_ACT_S_NEW)

    c = ws.cell(row=ri, column=1, value=scope)
    c.fill = mf(bg); c.font = Font(bold=True, name='Calibri', size=10)
    c.alignment = Alignment(horizontal='center', vertical='center'); c.border = mb()

    for ci, s in enumerate(SIG, 2):
        put(ws, ri, ci, do[s], bg, do[s] != dn[s])
    for ci, s in enumerate(SIG, 10):
        put(ws, ri, ci, dn[s], bg, do[s] != dn[s])

    ws.row_dimensions[ri].height = 16

ws.freeze_panes = 'B2'

# ---------------------------------------------------------------------------
# Legend
# ---------------------------------------------------------------------------
lg = wb.create_sheet("Legend")
lg.column_dimensions['A'].width = 14
lg.column_dimensions['B'].width = 65
rows = [
    ('Values',      '',                                                          C_HDR),
    ('Full',        'Signal active full line (both halves)',                     C_ACT),
    ('1st Half',    'Active h_cnt 0..319 (first half of line)',                 C_1ST),
    ('2nd Half',    'Active h_cnt 320..639 (second half of line)',              C_2ND),
    ('NA',          'Not active on this line',                                   C_NA),
    ('Yellow',      'Value DIFFERENT between OLD and NEW v3 tester',            C_DIFF),
    ('',            '',                                                          'FFFFFF'),
    ('Row colours', '',                                                          C_HDR),
    ('Pink',        'Pre-equalising pulses (F1 v=0-2, F2 v=312-314)',          C_PRE),
    ('Orange',      'Broad sync pulses    (F1 v=2-4, F2 v=315-316)',           C_BROAD),
    ('Lavender',    'Post-equalising      (F1 v=5-7, F2 v=317-319)',           C_POST),
    ('Light grey',  'VBI blank lines',                                          C_BLANK),
    ('Light green', 'Active video lines   (NEW v3)',                            C_ACT),
    ('',            '',                                                          'FFFFFF'),
    ('OLD tester',  'H_ACT_S=320  V_ACT_S_F1=22 (scope 23)  V_ACT_S_F2=335 (scope 336)',  'FFD9D9'),
    ('NEW v3',      'H_ACT_S=120  V_ACT_S_F1=25 (scope 26)  V_ACT_S_F2=337 (scope 338)',  'D9FFD9'),
    ('',            '',                                                          'FFFFFF'),
    ('Scope 23',    'OLD: 1st Half Blank + 2nd Half Video  |  NEW: Blank (VBI)',C_DIFF),
    ('Scope 26',    'OLD: Full Video (active 2 lines earlier)  |  NEW: Full Video start', C_DIFF),
    ('Scope 336',   'OLD: F2 Video start  |  NEW: Blank (VBI)',                C_DIFF),
    ('Scope 338',   'OLD: Video  |  NEW: F2 Video start (v3)',                 C_DIFF),
]
bdr = mb()
for ri, (a, b, col) in enumerate(rows, 1):
    hdr = a in ('Values', 'Row colours')
    ca  = lg.cell(row=ri, column=1, value=a)
    cb_ = lg.cell(row=ri, column=2, value=b)
    f   = mf(col)
    for cell in (ca, cb_):
        cell.fill = f; cell.border = bdr
        cell.font = Font(bold=hdr, color='FFFFFF' if hdr else '000000',
                         name='Calibri', size=10)
    ca.alignment  = Alignment(horizontal='center', vertical='center')
    cb_.alignment = Alignment(horizontal='left',   vertical='center')
    lg.row_dimensions[ri].height = 16

# ---------------------------------------------------------------------------
out_path = 'docs/PAL_Signal_Analysis.xlsx'
wb.save(out_path)
print(f"Saved: {out_path}")
print(f"Rows: {len(scope_lines)}  lines {scope_lines[0]}..{scope_lines[-1]}")
print(f"NEW v3: H_ACT_S={H_ACT_S_NEW}  V_ACT_S_F1={V_ACT_S_F1_NEW}  V_ACT_S_F2={V_ACT_S_F2_NEW}")
print(f"OLD:    H_ACT_S={H_ACT_S_OLD}  V_ACT_S_F1={V_ACT_S_F1_OLD}  V_ACT_S_F2={V_ACT_S_F2_OLD}")
