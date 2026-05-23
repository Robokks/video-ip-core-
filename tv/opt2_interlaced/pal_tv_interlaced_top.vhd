library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- PAL B&W Zone Test Pattern -- Option 2: Full Interlaced PAL (standards-compliant)
--
-- Why this works on any TV with a composite input:
--   H frequency = 15,625 Hz  (standard PAL)
--   Field rate  = 50 Hz      (true interlaced, 312.5 lines per field)
--   Frame rate  = 25 Hz      (625 lines per frame)
--   Vsync uses proper PAL sequence: 5 equalizing + 5 broad + 5 post-eq half-lines
--   Composite sync carries both H and V information on a single wire
--
-- The picture content is identical in both fields (static test pattern),
-- so no interlace twitter -- the test card is stable.
--
-- Frame layout (at 10 MHz, 640 clk/line):
--   Field 1 vsync : v_cnt 0..7   (7.5-line sequence)
--   Field 1 blank : v_cnt 8..23  (16 lines)
--   Field 1 active: v_cnt 24..311 (288 lines)   <- ZONE_H=36, GZONE_H=28
--   Field 1 front : v_cnt 312    (first half only, 0.5 line)
--   Field 2 vsync : v_cnt 312 h>=320 .. v_cnt 319
--   Field 2 blank : v_cnt 320..335
--   Field 2 active: v_cnt 336..623 (288 lines)
--   Field 2 front : v_cnt 624    (0.5 line to end of frame)
--   Total         : 625 lines @ 25 Hz frame / 50 Hz field rate
--
-- Four selectable patterns (sel input, same encoding as all other tops):
--   0  VERTICAL bars      8 zones, STRIPE/WHITE/STRIPE/WHITE/BLACK/STRIPE/WHITE/STRIPE
--   1  HORIZONTAL bars    8 zones per field (288/8 = 36 lines/zone)
--   2  HORIZONTAL gradient 10 grey zones left-to-right (52 px/zone)
--   3  VERTICAL gradient  10 grey zones top-to-bottom (28 lines/zone per field)
--
-- Composite sync on dac_out pin:
--   LEVEL_SYNC  ("0000") during any sync pulse
--   active_level during active pixels
--   LEVEL_BLANK ("0100") otherwise
-- hsync_o carries composite sync (1 = sync tip); vsync_o = field indicator.
entity pal_tv_interlaced_top is
  generic (
    H_FRONT    : integer := 16;
    H_SYNC_W   : integer := 47;
    H_BACK     : integer := 57;
    H_ACTIVE   : integer := 520;
    H_TOTAL    : integer := 640;
    -- V timing -- standard PAL 625 lines
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
    dac_out  : out std_logic_vector(3 downto 0);
    hsync_o  : out std_logic;  -- composite sync (1=sync tip)
    vsync_o  : out std_logic;  -- field indicator (0=F1, 1=F2)
    active_o : out std_logic
  );
end entity pal_tv_interlaced_top;

architecture rtl of pal_tv_interlaced_top is

  constant H_ACT_S : integer := H_FRONT + H_SYNC_W + H_BACK;  -- 120

  -- Field active windows (288 lines per field)
  constant V_ACT_S_F1 : integer := 24;
  constant V_ACT_E_F1 : integer := 311;   -- 24+288-1
  constant V_ACT_S_F2 : integer := 336;
  constant V_ACT_E_F2 : integer := 623;   -- 336+288-1
  constant V_ACTIVE_F : integer := 288;   -- lines per field

  -- Pattern zone layout (based on 288 lines per field)
  constant NUM_ZONES : integer := 8;
  constant ZONE_W    : integer := H_ACTIVE  / NUM_ZONES;  -- 65
  constant ZONE_H    : integer := V_ACTIVE_F / NUM_ZONES;  -- 36

  type zone_kind    is (Z_BLACK, Z_WHITE, Z_STRIPE);
  type zone_table_t is array (0 to NUM_ZONES - 1) of zone_kind;
  constant ZONE_TABLE : zone_table_t := (
    0 => Z_STRIPE, 1 => Z_WHITE,  2 => Z_STRIPE, 3 => Z_WHITE,
    4 => Z_BLACK,  5 => Z_STRIPE, 6 => Z_WHITE,  7 => Z_STRIPE
  );

  constant GZONES   : integer := 10;
  constant GZONE_W  : integer := H_ACTIVE  / GZONES;   -- 52
  constant GZONE_H  : integer := V_ACTIVE_F / GZONES;   -- 28

  type grad_table_t is array (0 to GZONES - 1) of std_logic_vector(3 downto 0);
  constant GRAD_TABLE : grad_table_t := (
    0 => "0100", 1 => "0101", 2 => "0110", 3 => "1000", 4 => "1001",
    5 => "1010", 6 => "1011", 7 => "1101", 8 => "1110", 9 => "1111"
  );

  signal h_cnt : integer range 0 to 639;
  signal v_cnt : integer range 0 to 624;
  signal ce_s  : std_logic;

  signal csync_s  : std_logic;
  signal field_s  : std_logic;
  signal active_s : std_logic;

  -- Helper: is v_cnt in either field's active window?
  signal in_f1_active : boolean;
  signal in_f2_active : boolean;
  signal in_any_active : boolean;

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

begin

  assert NUM_ZONES * ZONE_W = H_ACTIVE
    report "NUM_ZONES * ZONE_W /= H_ACTIVE" severity failure;
  assert NUM_ZONES * ZONE_H = V_ACTIVE_F
    report "NUM_ZONES * ZONE_H /= V_ACTIVE_F" severity failure;
  assert GZONES * GZONE_W = H_ACTIVE
    report "GZONES * GZONE_W /= H_ACTIVE" severity failure;

  sel_i <= to_integer(unsigned(sel));

  u_timing : entity work.pal_timing
    generic map (H_TOTAL => H_TOTAL, V_TOTAL => V_TOTAL, CLK_MHZ => CLK_MHZ)
    port map (clk => clk, rst => rst, ce => ce_s,
              h_cnt => h_cnt, v_cnt => v_cnt);

  u_csync : entity work.pal_csync_il
    generic map (
      H_FRONT => H_FRONT, H_SYNC_W => H_SYNC_W,
      H_BACK => H_BACK, H_ACTIVE => H_ACTIVE, H_TOTAL => H_TOTAL,
      V_ACT_S_F1 => V_ACT_S_F1, V_ACT_E_F1 => V_ACT_E_F1,
      V_ACT_S_F2 => V_ACT_S_F2, V_ACT_E_F2 => V_ACT_E_F2)
    port map (h_cnt => h_cnt, v_cnt => v_cnt,
              csync => csync_s, field => field_s, active => active_s);

  -- Convenience flags for process preloading
  in_f1_active  <= (v_cnt >= V_ACT_S_F1 and v_cnt <= V_ACT_E_F1);
  in_f2_active  <= (v_cnt >= V_ACT_S_F2 and v_cnt <= V_ACT_E_F2);
  in_any_active <= in_f1_active or in_f2_active;

  -- -----------------------------------------------------------------------
  -- Vertical bar generator: pixel counter resets at start of each active line
  -- (in both fields).
  -- -----------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        zone_idx_v <= 0; px_in_zone <= 0; stripe_cnt_v <= 0; stripe_ph_v <= '0';
      elsif ce_s = '1' then
        if h_cnt = H_ACT_S - 1 and in_any_active then
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

  -- -----------------------------------------------------------------------
  -- Horizontal bar generator: line counter resets at the start of each
  -- field's active window, then advances at end of each active line.
  -- -----------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        zone_idx_h <= 0; line_in_zone <= 0; stripe_cnt_h <= 0; stripe_ph_h <= '0';
      elsif ce_s = '1' then
        -- Reset at last clock of line before field 1 or field 2 active starts
        if (v_cnt = V_ACT_S_F1 - 1 or v_cnt = V_ACT_S_F2 - 1) and
           h_cnt = H_TOTAL - 1 then
          zone_idx_h <= 0; line_in_zone <= 0; stripe_cnt_h <= 0; stripe_ph_h <= '0';
        -- Advance at end of each active line (either field)
        elsif in_any_active and h_cnt = H_TOTAL - 1 then
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

  -- -----------------------------------------------------------------------
  -- Horizontal gradient generator: resets each active line
  -- -----------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        gzx_idx <= 0; gpx_in <= 0;
      elsif ce_s = '1' then
        if h_cnt = H_ACT_S - 1 and in_any_active then
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

  -- -----------------------------------------------------------------------
  -- Vertical gradient generator: resets at start of each field's active window
  -- -----------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        gzy_idx <= 0; gln_in <= 0;
      elsif ce_s = '1' then
        if (v_cnt = V_ACT_S_F1 - 1 or v_cnt = V_ACT_S_F2 - 1) and
           h_cnt = H_TOTAL - 1 then
          gzy_idx <= 0; gln_in <= 0;
        elsif in_any_active and h_cnt = H_TOTAL - 1 then
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

  active_level <= GRAD_TABLE(gzx_idx) when sel_i = 2 else
                  GRAD_TABLE(gzy_idx) when sel_i = 3 else
                  LEVEL_WHITE when (sel_i = 0 and color_v = '1') or
                                   (sel_i = 1 and color_h = '1') else
                  LEVEL_BLANK;

  -- Composite sync takes priority; no separate hsync/vsync paths
  dac_out <= LEVEL_SYNC   when csync_s = '1'  else
             active_level when active_s = '1'  else
             LEVEL_BLANK;

  hsync_o  <= csync_s;   -- composite sync out
  vsync_o  <= field_s;   -- field indicator (useful for scoping)
  active_o <= active_s;

end architecture rtl;
