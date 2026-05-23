library ieee;
use ieee.std_logic_1164.all;

-- Interlaced PAL composite sync generator (purely combinational, glitch-free).
--
-- All intermediate values are computed as VARIABLES inside a single process so
-- every output (csync, field, active) settles in one delta cycle when h_cnt or
-- v_cnt change.  Using intermediate SIGNALS would cause a one-delta lag between
-- h_cnt and derived flags, producing spurious '0'->>'1'->>'0' glitches on field
-- at the exact clock when h_cnt wraps from 639 to 0 and v_cnt rolls to a new
-- line -- breaking the testbench's falling_edge(field) anchor.
--
-- PAL interlaced vsync sequence per field (15 half-lines = 7.5 lines):
--   Field 1: starts at v_cnt=0,   h_cnt=0   (frame boundary)
--   Field 2: starts at v_cnt=312, h_cnt=320 (half-line offset)
--
--   5 pre-equalizing  half-lines: csync LOW for EQ_W    = 23 clocks
--   5 broad-sync      half-lines: csync LOW for BROAD_W = 273 clocks
--   5 post-equalizing half-lines: csync LOW for EQ_W    = 23 clocks
--
-- Normal H sync (all other lines): csync LOW for H_SYNC_W = 47 clocks
-- starting at h_cnt = H_FRONT = 16.
--
-- Note: BROAD_W + H_SYNC_W = 273 + 47 = 320 = HALF
--       (broad sync fills the half-line with no dead time)
entity pal_csync_il is
  generic (
    H_FRONT  : integer := 16;
    H_SYNC_W : integer := 47;
    H_BACK   : integer := 57;
    H_ACTIVE : integer := 520;
    H_TOTAL  : integer := 640;
    HALF     : integer := 320;   -- half-line clocks
    EQ_W     : integer := 23;    -- equalizing pulse low width
    BROAD_W  : integer := 273;   -- broad sync low width
    V_ACT_S_F1 : integer := 24;
    V_ACT_E_F1 : integer := 311;
    V_ACT_S_F2 : integer := 336;
    V_ACT_E_F2 : integer := 623
  );
  port (
    h_cnt  : in  integer range 0 to 639;
    v_cnt  : in  integer range 0 to 624;
    csync  : out std_logic;   -- 1 = sync tip
    field  : out std_logic;   -- 0 = field 1, 1 = field 2
    active : out std_logic    -- 1 = active pixel region
  );
end entity pal_csync_il;

architecture rtl of pal_csync_il is
  constant H_ACT_S : integer := H_FRONT + H_SYNC_W + H_BACK;
begin

  assert H_FRONT + H_SYNC_W + H_BACK + H_ACTIVE = H_TOTAL
    report "H timing parameters do not sum to H_TOTAL" severity failure;
  assert BROAD_W + H_SYNC_W = HALF
    report "BROAD_W + H_SYNC_W must equal HALF" severity failure;

  -- Pure combinational process: all intermediate values are variables so
  -- all outputs resolve in a single delta cycle (no inter-signal delta races).
  process(h_cnt, v_cnt)
    variable hp      : integer range 0 to HALF - 1;
    variable first_h : boolean;  -- h_cnt is in first half of line
    variable f1p, f1b, f1q : boolean;  -- field 1: pre-eq, broad, post-eq
    variable f2p, f2b, f2q : boolean;  -- field 2: pre-eq, broad, post-eq
    variable in_eq, in_brd  : boolean;
  begin
    first_h := (h_cnt < HALF);
    if first_h then hp := h_cnt; else hp := h_cnt - HALF; end if;

    -- -----------------------------------------------------------------------
    -- Field 1 vsync (frame start, lines 0..7):
    --   Pre-eq  (5 HL): v=0 both + v=1 both + v=2 first
    --   Broad   (5 HL): v=2 second + v=3 both + v=4 both
    --   Post-eq (5 HL): v=5 both + v=6 both + v=7 first
    -- -----------------------------------------------------------------------
    f1p := (v_cnt = 0) or (v_cnt = 1) or (v_cnt = 2 and     first_h);
    f1b := (v_cnt = 2 and not first_h) or (v_cnt = 3) or (v_cnt = 4);
    f1q := (v_cnt = 5) or (v_cnt = 6) or (v_cnt = 7 and     first_h);

    -- -----------------------------------------------------------------------
    -- Field 2 vsync (starts at v=312 h=320, i.e. second half of line 312):
    --   Pre-eq  (5 HL): (v=312 second) + v=313 both + v=314 both
    --   Broad   (5 HL): v=315 both + v=316 both + (v=317 first)
    --   Post-eq (5 HL): (v=317 second) + v=318 both + v=319 both
    -- -----------------------------------------------------------------------
    f2p := (v_cnt = 312 and not first_h) or (v_cnt = 313) or (v_cnt = 314);
    f2b := (v_cnt = 315) or (v_cnt = 316) or (v_cnt = 317 and     first_h);
    f2q := (v_cnt = 317 and not first_h) or (v_cnt = 318) or (v_cnt = 319);

    in_eq  := f1p or f1q or f2p or f2q;
    in_brd := f1b or f2b;

    -- Composite sync
    if in_eq and hp < EQ_W then
      csync <= '1';    -- equalizing pulse (2.3 µs low)
    elsif in_brd and hp < BROAD_W then
      csync <= '1';    -- broad sync (27.3 µs low)
    elsif not (in_eq or in_brd)
          and h_cnt >= H_FRONT and h_cnt < H_FRONT + H_SYNC_W then
      csync <= '1';    -- normal H sync (4.7 µs low)
    else
      csync <= '0';
    end if;

    -- Field indicator: '1' from the start of field 2 (v=312 h>=320) onwards
    if v_cnt > 312 or (v_cnt = 312 and not first_h) then
      field <= '1';
    else
      field <= '0';
    end if;

    -- Active pixel windows
    if (v_cnt >= V_ACT_S_F1 and v_cnt <= V_ACT_E_F1 and h_cnt >= H_ACT_S) or
       (v_cnt >= V_ACT_S_F2 and v_cnt <= V_ACT_E_F2 and h_cnt >= H_ACT_S) then
      active <= '1';
    else
      active <= '0';
    end if;
  end process;

end architecture rtl;
