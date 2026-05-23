library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- PAL B&W Zone Test Pattern -- Option 3: 25 Hz Progressive (reference design)
--
-- This is the same design as rtl/pal_bw_zonebar_top.vhd, placed here for
-- side-by-side comparison with opt1_crt50 and opt2_interlaced.
--
-- Why it may not work on all TVs:
--   Field rate = 25 Hz (625 lines @ 64 us/line = 40 ms/frame)
--   Standard PAL TVs expect 50 Hz field rate.
--   CRT vertical hold circuits will usually not lock at 25 Hz.
--   Some LCD/plasma TVs with composite input accept it; many do not.
--   Vsync uses 5 full lines of broad pulse (no equalizing/serration), which
--   simplified sync circuits may miss.
--
-- Use opt1_crt50 for CRT TVs, opt2_interlaced for all modern TVs.
--
-- Four selectable patterns (sel input):
--   0  VERTICAL bars    (8 zones, 520 px wide, 65 px/zone)
--   1  HORIZONTAL bars  (8 zones, 576 lines tall, 72 lines/zone)
--   2  HORIZONTAL gradient  (10 zones, 52 px/zone)
--   3  VERTICAL gradient    (10 zones, 57 lines/zone, last zone taller)
entity pal_tv_prog25_top is
  generic (
    H_FRONT    : integer := 16;
    H_SYNC_W   : integer := 47;
    H_BACK     : integer := 57;
    H_ACTIVE   : integer := 520;
    H_TOTAL    : integer := 640;
    V_SYNC_L   : integer := 5;
    V_BACK_L   : integer := 20;
    V_ACTIVE_L : integer := 576;
    V_TOTAL    : integer := 625;
    LEVEL_SYNC  : std_logic_vector(3 downto 0) := "0000";
    LEVEL_BLANK : std_logic_vector(3 downto 0) := "0100";
    LEVEL_WHITE : std_logic_vector(3 downto 0) := "1111";
    CLK_MHZ     : integer := 40;
    STRIPE_W    : integer := 4
  );
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;
    sel      : in  std_logic_vector(7 downto 0);
    brightness : in  std_logic_vector(3 downto 0) := "1111";  -- white level: x"6"=20%, x"F"=100%
    black_lvl  : in  std_logic_vector(3 downto 0) := "0100";  -- black level: x"4"=black, higher=gray
    dac_out  : out std_logic_vector(3 downto 0);
    hsync_o  : out std_logic;
    vsync_o  : out std_logic;
    active_o : out std_logic;
    blank_o  : out std_logic   -- HIGH during blanking pedestal (not sync, not active)
  );
end entity pal_tv_prog25_top;

architecture rtl of pal_tv_prog25_top is

  constant H_ACT_S   : integer := H_FRONT + H_SYNC_W + H_BACK;
  constant V_ACT_S   : integer := V_SYNC_L + V_BACK_L;

  constant NUM_ZONES : integer := 8;
  constant ZONE_W    : integer := H_ACTIVE   / NUM_ZONES;  -- 65
  constant ZONE_H    : integer := V_ACTIVE_L / NUM_ZONES;  -- 72

  type zone_kind    is (Z_BLACK, Z_WHITE, Z_STRIPE);
  type zone_table_t is array (0 to NUM_ZONES - 1) of zone_kind;
  constant ZONE_TABLE : zone_table_t := (
    0 => Z_STRIPE, 1 => Z_WHITE,  2 => Z_STRIPE, 3 => Z_WHITE,
    4 => Z_BLACK,  5 => Z_STRIPE, 6 => Z_WHITE,  7 => Z_STRIPE
  );

  constant GZONES   : integer := 10;
  constant GZONE_W  : integer := H_ACTIVE   / GZONES;  -- 52
  constant GZONE_H  : integer := V_ACTIVE_L / GZONES;  -- 57

  signal h_cnt : integer range 0 to 639;
  signal v_cnt : integer range 0 to 624;
  signal ce_s  : std_logic;

  signal hsync_s  : std_logic;
  signal vsync_s  : std_logic;
  signal active_s : std_logic;
  signal blank_s  : std_logic;

  signal zone_idx_v   : integer range 0 to NUM_ZONES - 1 := 0;
  signal px_in_zone   : integer range 0 to ZONE_W - 1     := 0;
  signal stripe_cnt_v : integer range 0 to STRIPE_W - 1   := 0;
  signal stripe_ph_v  : std_logic                         := '0';

  signal zone_idx_h   : integer range 0 to NUM_ZONES - 1 := 0;
  signal line_in_zone : integer range 0 to ZONE_H - 1     := 0;
  signal stripe_cnt_h : integer range 0 to STRIPE_W - 1   := 0;
  signal stripe_ph_h  : std_logic                         := '0';

  signal gzx_idx : integer range 0 to GZONES - 1  := 0;
  signal gpx_in  : integer range 0 to GZONE_W - 1 := 0;

  signal gzy_idx : integer range 0 to GZONES - 1  := 0;
  signal gln_in  : integer range 0 to GZONE_H - 1 := 0;

  signal color_v      : std_logic;
  signal color_h      : std_logic;
  signal sel_i        : integer range 0 to 255;
  signal active_level : std_logic_vector(3 downto 0);

  signal white_level_i : integer range 4 to 15;
  signal white_s       : std_logic_vector(3 downto 0);
  signal black_level_i : integer range 4 to 15;
  signal black_s       : std_logic_vector(3 downto 0);
  signal grad_x_s      : std_logic_vector(3 downto 0);
  signal grad_y_s      : std_logic_vector(3 downto 0);

begin

  assert NUM_ZONES * ZONE_W = H_ACTIVE   report "Zone W mismatch" severity failure;
  assert NUM_ZONES * ZONE_H = V_ACTIVE_L report "Zone H mismatch" severity failure;
  assert GZONES * GZONE_W   = H_ACTIVE   report "GZone W mismatch" severity failure;

  sel_i <= to_integer(unsigned(sel));

  -- Brightness: clamp white level to [4..15]
  white_level_i <= 4 when unsigned(brightness) < 4 else to_integer(unsigned(brightness));
  white_s        <= std_logic_vector(to_unsigned(white_level_i, 4));

  -- Black level: raise active-region black toward gray; clamped to [LEVEL_BLANK..white_level_i]
  process(black_lvl, white_level_i)
    variable b : integer range 0 to 15;
  begin
    b := to_integer(unsigned(black_lvl));
    if b < 4             then b := 4;             end if;
    if b > white_level_i then b := white_level_i; end if;
    black_level_i <= b;
  end process;
  black_s <= std_logic_vector(to_unsigned(black_level_i, 4));

  -- Gradient scaled from black_level_i to white_level_i
  process(white_level_i, black_level_i, gzx_idx, gzy_idx)
    variable rng    : integer range 0 to 11;
    variable lx, ly : integer range 0 to 15;
  begin
    rng := white_level_i - black_level_i;
    if rng = 0 then
      lx := black_level_i; ly := black_level_i;
    else
      lx := black_level_i + (gzx_idx * rng + 4) / 9;
      ly := black_level_i + (gzy_idx * rng + 4) / 9;
      if lx > 15 then lx := 15; end if;
      if ly > 15 then ly := 15; end if;
    end if;
    grad_x_s <= std_logic_vector(to_unsigned(lx, 4));
    grad_y_s <= std_logic_vector(to_unsigned(ly, 4));
  end process;

  u_timing : entity work.pal_timing
    generic map (H_TOTAL => H_TOTAL, V_TOTAL => V_TOTAL, CLK_MHZ => CLK_MHZ)
    port map (clk => clk, rst => rst, ce => ce_s,
              h_cnt => h_cnt, v_cnt => v_cnt);

  u_sync : entity work.pal_sync_gen
    generic map (
      H_FRONT => H_FRONT, H_SYNC_W => H_SYNC_W, H_BACK => H_BACK,
      H_ACTIVE => H_ACTIVE, H_TOTAL => H_TOTAL,
      V_SYNC_L => V_SYNC_L, V_BACK_L => V_BACK_L,
      V_ACTIVE_L => V_ACTIVE_L, V_TOTAL => V_TOTAL)
    port map (h_cnt => h_cnt, v_cnt => v_cnt,
              hsync => hsync_s, vsync => vsync_s,
              active => active_s, blank => blank_s);

  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        zone_idx_v <= 0; px_in_zone <= 0; stripe_cnt_v <= 0; stripe_ph_v <= '0';
      elsif ce_s = '1' then
        if h_cnt = H_ACT_S - 1 and
           v_cnt >= V_ACT_S and v_cnt < V_ACT_S + V_ACTIVE_L then
          zone_idx_v <= 0; px_in_zone <= 0; stripe_cnt_v <= 0; stripe_ph_v <= '0';
        elsif active_s = '1' then
          if px_in_zone = ZONE_W - 1 then
            if zone_idx_v < NUM_ZONES - 1 then zone_idx_v <= zone_idx_v + 1; end if;
            px_in_zone <= 0; stripe_cnt_v <= 0; stripe_ph_v <= '0';
          else
            px_in_zone <= px_in_zone + 1;
            if stripe_cnt_v = STRIPE_W - 1 then
              stripe_cnt_v <= 0; stripe_ph_v <= not stripe_ph_v;
            else
              stripe_cnt_v <= stripe_cnt_v + 1;
            end if;
          end if;
        end if;
      end if;
    end if;
  end process;

  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        zone_idx_h <= 0; line_in_zone <= 0; stripe_cnt_h <= 0; stripe_ph_h <= '0';
      elsif ce_s = '1' then
        if v_cnt = V_ACT_S - 1 and h_cnt = H_TOTAL - 1 then
          zone_idx_h <= 0; line_in_zone <= 0; stripe_cnt_h <= 0; stripe_ph_h <= '0';
        elsif v_cnt >= V_ACT_S and v_cnt < V_ACT_S + V_ACTIVE_L and
              h_cnt = H_TOTAL - 1 then
          if line_in_zone = ZONE_H - 1 then
            if zone_idx_h < NUM_ZONES - 1 then zone_idx_h <= zone_idx_h + 1; end if;
            line_in_zone <= 0; stripe_cnt_h <= 0; stripe_ph_h <= '0';
          else
            line_in_zone <= line_in_zone + 1;
            if stripe_cnt_h = STRIPE_W - 1 then
              stripe_cnt_h <= 0; stripe_ph_h <= not stripe_ph_h;
            else
              stripe_cnt_h <= stripe_cnt_h + 1;
            end if;
          end if;
        end if;
      end if;
    end if;
  end process;

  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        gzx_idx <= 0; gpx_in <= 0;
      elsif ce_s = '1' then
        if h_cnt = H_ACT_S - 1 and
           v_cnt >= V_ACT_S and v_cnt < V_ACT_S + V_ACTIVE_L then
          gzx_idx <= 0; gpx_in <= 0;
        elsif active_s = '1' then
          if gpx_in = GZONE_W - 1 then
            if gzx_idx < GZONES - 1 then gzx_idx <= gzx_idx + 1; end if;
            gpx_in <= 0;
          else
            gpx_in <= gpx_in + 1;
          end if;
        end if;
      end if;
    end if;
  end process;

  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        gzy_idx <= 0; gln_in <= 0;
      elsif ce_s = '1' then
        if v_cnt = V_ACT_S - 1 and h_cnt = H_TOTAL - 1 then
          gzy_idx <= 0; gln_in <= 0;
        elsif v_cnt >= V_ACT_S and v_cnt < V_ACT_S + V_ACTIVE_L and
              h_cnt = H_TOTAL - 1 then
          if gln_in = GZONE_H - 1 then
            if gzy_idx < GZONES - 1 then gzy_idx <= gzy_idx + 1; end if;
            gln_in <= 0;
          else
            gln_in <= gln_in + 1;
          end if;
        end if;
      end if;
    end if;
  end process;

  with ZONE_TABLE(zone_idx_v) select
    color_v <= '0' when Z_BLACK, '1' when Z_WHITE, stripe_ph_v when Z_STRIPE;
  with ZONE_TABLE(zone_idx_h) select
    color_h <= '0' when Z_BLACK, '1' when Z_WHITE, stripe_ph_h when Z_STRIPE;

  active_level <= grad_x_s when sel_i = 2 else
                  grad_y_s when sel_i = 3 else
                  white_s  when (sel_i = 0 and color_v = '1') or
                                (sel_i = 1 and color_h = '1') else
                  black_s;  -- active-region black (gray when black_lvl > x"4")

  dac_out <= LEVEL_SYNC   when vsync_s = '1' else
             LEVEL_SYNC   when hsync_s = '1' else
             active_level when active_s = '1' else
             LEVEL_BLANK;

  hsync_o  <= hsync_s;
  vsync_o  <= vsync_s;
  active_o <= active_s;
  blank_o  <= blank_s;

end architecture rtl;
