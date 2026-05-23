library ieee;
use ieee.std_logic_1164.all;

-- Combinational decode of H/V counters into PAL timing region flags.
-- Shared by opt1_crt50 and opt3_prog25.  opt2_interlaced uses pal_csync_il instead.
entity pal_sync_gen is
  generic (
    H_FRONT    : integer := 16;
    H_SYNC_W   : integer := 47;
    H_BACK     : integer := 57;
    H_ACTIVE   : integer := 520;
    H_TOTAL    : integer := 640;
    V_SYNC_L   : integer := 5;
    V_BACK_L   : integer := 20;
    V_ACTIVE_L : integer := 576;
    V_TOTAL    : integer := 625
  );
  port (
    h_cnt  : in  integer range 0 to 639;
    v_cnt  : in  integer range 0 to 624;
    hsync  : out std_logic;
    vsync  : out std_logic;
    active : out std_logic;
    blank  : out std_logic
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
