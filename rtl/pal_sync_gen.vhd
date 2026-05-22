library ieee;
use ieee.std_logic_1164.all;

-- Combinational decode of H/V counters into PAL timing region flags.
-- All outputs are purely combinational (change with h_cnt/v_cnt inputs).
--
-- H regions at 10 MHz (640 cycles per line):
--   [0 .. H_FRONT-1]                        : front porch
--   [H_FRONT .. H_FRONT+H_SYNC_W-1]         : H-sync pulse (low)
--   [H_FRONT+H_SYNC_W .. H_ACT_START-1]     : back porch
--   [H_ACT_START .. H_TOTAL-1]              : active pixels
--
-- V regions (625 lines per frame):
--   [0 .. V_SYNC_L-1]                        : broad vsync (lines 0..4)
--   [V_SYNC_L .. V_ACT_START-1]              : V back porch (lines 5..24)
--   [V_ACT_START .. V_ACT_START+V_ACTIVE-1] : active lines (lines 25..600)
--   remainder                                : V front porch
entity pal_sync_gen is
  generic (
    H_FRONT    : integer := 16;   -- front porch clocks
    H_SYNC_W   : integer := 47;   -- H-sync pulse width in clocks
    H_BACK     : integer := 57;   -- back porch clocks
    H_ACTIVE   : integer := 520;  -- active pixels per line
    H_TOTAL    : integer := 640;  -- must equal H_FRONT+H_SYNC_W+H_BACK+H_ACTIVE
    V_SYNC_L   : integer := 5;    -- broad vsync lines
    V_BACK_L   : integer := 20;   -- V back porch lines
    V_ACTIVE_L : integer := 576;  -- active lines
    V_TOTAL    : integer := 625   -- must equal V_SYNC_L+V_BACK_L+V_ACTIVE_L+V_FRONT_L
  );
  port (
    h_cnt  : in  integer range 0 to 639;
    v_cnt  : in  integer range 0 to 624;
    hsync  : out std_logic;  -- '1' during H-sync pulse
    vsync  : out std_logic;  -- '1' during broad vsync lines
    active : out std_logic;  -- '1' during active pixel region (H and V)
    blank  : out std_logic   -- '1' during blanking (not active, not sync)
  );
end entity pal_sync_gen;

architecture rtl of pal_sync_gen is

  constant H_SYNC_S : integer := H_FRONT;
  constant H_BACK_S : integer := H_FRONT + H_SYNC_W;
  constant H_ACT_S  : integer := H_FRONT + H_SYNC_W + H_BACK;
  constant V_ACT_S  : integer := V_SYNC_L + V_BACK_L;

  signal in_h_sync   : boolean;
  signal in_h_active : boolean;
  signal in_v_sync   : boolean;
  signal in_v_active : boolean;

begin

  assert H_FRONT + H_SYNC_W + H_BACK + H_ACTIVE = H_TOTAL
    report "H timing parameters do not sum to H_TOTAL" severity failure;

  assert V_SYNC_L + V_BACK_L + V_ACTIVE_L < V_TOTAL
    report "V active region overflows V_TOTAL" severity failure;

  in_h_sync   <= (h_cnt >= H_SYNC_S) and (h_cnt < H_BACK_S);
  in_h_active <= (h_cnt >= H_ACT_S);
  in_v_sync   <= (v_cnt < V_SYNC_L);
  in_v_active <= (v_cnt >= V_ACT_S) and (v_cnt < V_ACT_S + V_ACTIVE_L);

  hsync  <= '1' when in_h_sync   else '0';
  vsync  <= '1' when in_v_sync   else '0';
  active <= '1' when in_h_active and in_v_active else '0';
  blank  <= '1' when (not in_h_active or not in_v_active)
                 and not in_h_sync
                 and not in_v_sync else '0';

end architecture rtl;
