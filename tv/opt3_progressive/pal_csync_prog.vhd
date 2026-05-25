library ieee;
use ieee.std_logic_1164.all;

-- Progressive composite sync generator  (V1.2)
-- =============================================
--
-- Generates composite sync compatible with progressive-scan displays,
-- PC monitors (sync-on-composite / SCART / RGBS), and frame-grabbers.
--
-- Same port interface as pal_csync_il so it can be swapped in by the
-- PROGRESSIVE generate block inside pal_tv_bram_top.
--
-- Timing (using default 640-pixel line / 625-line frame at 10 MHz):
--
--   H layout  (identical to interlaced):
--     [0 .. H_FRONT-1]                    front porch     (16 px)
--     [H_FRONT .. H_FRONT+H_SYNC_W-1]     H-sync tip      (47 px)
--     [H_FRONT+H_SYNC_W .. H_ACT_S-1]     back porch      (57 px)
--     [H_ACT_S .. H_TOTAL-1]              active pixels  (520 px)
--
--   V layout  (progressive — single active window, no field split):
--     [0 .. V_SYNC_W-1]                   V-sync lines     (3)
--     [V_SYNC_W .. V_ACT_S-1]             V back porch    (41)
--     [V_ACT_S .. V_ACT_E]               active lines    (576)
--     [V_ACT_E+1 .. V_TOTAL-1]            V front porch    (5)
--
--   csync encoding:
--     Normal lines  : '1' during H-sync window [H_FRONT, H_FRONT+H_SYNC_W)
--     V-sync lines  : '1' during broad pulse  [H_FRONT, H_TOTAL-H_FRONT)
--       (broad pulse = H_TOTAL - 2*H_FRONT = 608 px wide; gap at each end)
--     Sync tip = '1'  (same polarity as pal_csync_il)
--
--   field  : always '0'  (no field interleaving in progressive scan)
--   active : '1' inside the H and V active window simultaneously

entity pal_csync_prog is
  generic (
    H_FRONT  : integer := 16;
    H_SYNC_W : integer := 47;
    H_BACK   : integer := 57;
    H_ACTIVE : integer := 520;
    H_TOTAL  : integer := 640;
    V_ACT_S  : integer := 44;   -- first active line
    V_ACT_E  : integer := 619;  -- last  active line  (V_ACT_S + 576 - 1)
    V_SYNC_W : integer := 3     -- number of V-sync (broad-sync) lines
  );
  port (
    h_cnt  : in  integer range 0 to 639;
    v_cnt  : in  integer range 0 to 624;
    csync  : out std_logic;  -- composite sync (1 = sync tip)
    field  : out std_logic;  -- always '0' (no interlace fields)
    active : out std_logic   -- '1' during active picture window
  );
end entity pal_csync_prog;

architecture rtl of pal_csync_prog is
  constant H_ACT_S : integer := H_FRONT + H_SYNC_W + H_BACK;  -- 120
begin

  -- Purely combinational — all outputs settle in a single delta cycle.
  process(h_cnt, v_cnt)
    variable in_vsync  : boolean;
    variable in_hsync  : boolean;
    variable in_broad  : boolean;
    variable in_active : boolean;
  begin
    -- V-sync region (first V_SYNC_W lines of each frame)
    in_vsync := (v_cnt < V_SYNC_W);

    -- Standard H-sync window (positioned after front porch)
    in_hsync := (h_cnt >= H_FRONT) and (h_cnt < H_FRONT + H_SYNC_W);

    -- Broad V-sync pulse: fills the line except H_FRONT gaps at each end
    --   [H_FRONT .. H_TOTAL - H_FRONT - 1]  (= 608 px for default timing)
    in_broad := (h_cnt >= H_FRONT) and (h_cnt < H_TOTAL - H_FRONT);

    -- Active pixel window: both H and V windows must be open
    in_active := (v_cnt >= V_ACT_S) and (v_cnt <= V_ACT_E) and
                 (h_cnt >= H_ACT_S) and (h_cnt < H_ACT_S + H_ACTIVE);

    -- Composite sync
    if in_vsync then
      csync <= '1' when in_broad else '0';   -- broad pulse during V-sync lines
    else
      csync <= '1' when in_hsync else '0';   -- normal H-sync on every other line
    end if;

    field  <= '0';
    active <= '1' when in_active else '0';
  end process;

end architecture rtl;
