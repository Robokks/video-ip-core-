library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- PAL B&W Zone Test Pattern Generator (no BRAM required)
--
-- One U8 'sel' input chooses the pattern at runtime:
--   sel = 0 : VERTICAL bars    - 8 zones across 520 px (per ZONE_TABLE)
--   sel = 1 : HORIZONTAL bars   - 8 zones down 576 lines (per ZONE_TABLE)
--   sel = 2 : HORIZONTAL gradient - 10 grey zones left->right (GRAD_TABLE)
--   sel = 3 : VERTICAL gradient   - 10 grey zones top->bottom (GRAD_TABLE)
--
-- BARS use ZONE_TABLE (each zone solid black / solid white / fine stripes):
--   STRIPE, WHITE, STRIPE, WHITE, BLACK, STRIPE, WHITE, STRIPE
--   vertical zone width = 520/8 = 65 px ; horizontal zone height = 576/8 = 72 lines
--
-- GRADIENTS step the 4-bit DAC through GRAD_TABLE (black->white staircase):
--   horizontal gradient zone width  = 520/10 = 52 px (exact)
--   vertical   gradient zone height = 576/10 = 57 lines (last zone takes the
--   remaining 63 lines, since 576 is not a multiple of 10)
--
-- Pixel-path arithmetic is incremental counters + constant-table lookups only.
-- There is NO runtime divide or multiply, so it closes timing in a single
-- SCTL cycle at 40 MHz.
--
-- Reuses pal_timing and pal_sync_gen unchanged.  The 4-bit DAC mux is built
-- in this file because gradients need full 4-bit levels (pal_dac_mux is 1-bit).
entity pal_bw_zonebar_top is
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
    CLK_MHZ     : integer := 40;  -- 10 / 20 / 30 / 40
    STRIPE_W    : integer := 4    -- pixels / lines per stripe inside a STRIPE bar
  );
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;

    -- Pattern select (U8): 0=Vbars 1=Hbars 2=Hgradient 3=Vgradient
    sel      : in  std_logic_vector(7 downto 0);

    -- 4-bit DAC output -> NI-9401 DIO0-3
    dac_out  : out std_logic_vector(3 downto 0);

    -- Debug outputs
    hsync_o  : out std_logic;
    vsync_o  : out std_logic;
    active_o : out std_logic
  );
end entity pal_bw_zonebar_top;

architecture rtl of pal_bw_zonebar_top is

  constant H_ACT_S : integer := H_FRONT + H_SYNC_W + H_BACK;  -- 120
  constant V_ACT_S : integer := V_SYNC_L + V_BACK_L;           -- 25

  -- ----- Bar layout (sel 0/1) -----
  constant NUM_ZONES : integer := 8;
  constant ZONE_W    : integer := H_ACTIVE   / NUM_ZONES;  -- 65 px
  constant ZONE_H    : integer := V_ACTIVE_L / NUM_ZONES;  -- 72 lines

  type zone_kind    is (Z_BLACK, Z_WHITE, Z_STRIPE);
  type zone_table_t is array (0 to NUM_ZONES - 1) of zone_kind;
  constant ZONE_TABLE : zone_table_t := (
    0 => Z_STRIPE, 1 => Z_WHITE,  2 => Z_STRIPE, 3 => Z_WHITE,
    4 => Z_BLACK,  5 => Z_STRIPE, 6 => Z_WHITE,  7 => Z_STRIPE
  );

  -- ----- Gradient layout (sel 2/3) -----
  constant GZONES   : integer := 10;
  constant GZONE_W  : integer := H_ACTIVE   / GZONES;  -- 52 px (exact)
  constant GZONE_H  : integer := V_ACTIVE_L / GZONES;  -- 57 lines (remainder -> last zone)

  type grad_table_t is array (0 to GZONES - 1) of std_logic_vector(3 downto 0);
  -- Black (blank level) -> white staircase, 10 steps
  constant GRAD_TABLE : grad_table_t := (
    0 => "0100", 1 => "0101", 2 => "0110", 3 => "1000", 4 => "1001",
    5 => "1010", 6 => "1011", 7 => "1101", 8 => "1110", 9 => "1111"
  );
  -- ---------------------------------------------------------

  signal h_cnt : integer range 0 to H_TOTAL - 1;
  signal v_cnt : integer range 0 to V_TOTAL - 1;
  signal ce_s  : std_logic;

  signal hsync_s  : std_logic;
  signal vsync_s  : std_logic;
  signal active_s : std_logic;
  signal blank_s  : std_logic;

  -- Vertical bar generator (per active pixel, resets each line)
  signal zone_idx_v   : integer range 0 to NUM_ZONES - 1 := 0;
  signal px_in_zone   : integer range 0 to ZONE_W - 1     := 0;
  signal stripe_cnt_v : integer range 0 to STRIPE_W - 1   := 0;
  signal stripe_ph_v  : std_logic                         := '0';

  -- Horizontal bar generator (per active line, resets each frame)
  signal zone_idx_h   : integer range 0 to NUM_ZONES - 1 := 0;
  signal line_in_zone : integer range 0 to ZONE_H - 1     := 0;
  signal stripe_cnt_h : integer range 0 to STRIPE_W - 1   := 0;
  signal stripe_ph_h  : std_logic                         := '0';

  -- Horizontal gradient generator (per active pixel, resets each line)
  signal gzx_idx : integer range 0 to GZONES - 1  := 0;
  signal gpx_in  : integer range 0 to GZONE_W - 1 := 0;

  -- Vertical gradient generator (per active line, resets each frame)
  signal gzy_idx : integer range 0 to GZONES - 1  := 0;
  signal gln_in  : integer range 0 to GZONE_H - 1 := 0;

  signal color_v      : std_logic;
  signal color_h      : std_logic;
  signal sel_i        : integer range 0 to 255;
  signal active_level : std_logic_vector(3 downto 0);

begin

  assert NUM_ZONES * ZONE_W = H_ACTIVE
    report "NUM_ZONES * ZONE_W must equal H_ACTIVE" severity failure;
  assert NUM_ZONES * ZONE_H = V_ACTIVE_L
    report "NUM_ZONES * ZONE_H must equal V_ACTIVE_L" severity failure;
  assert GZONES * GZONE_W = H_ACTIVE
    report "GZONES * GZONE_W must equal H_ACTIVE" severity failure;

  sel_i <= to_integer(unsigned(sel));

  u_timing : entity work.pal_timing
    generic map (H_TOTAL => H_TOTAL, V_TOTAL => V_TOTAL, CLK_MHZ => CLK_MHZ)
    port map (clk => clk, rst => rst, ce => ce_s, h_cnt => h_cnt, v_cnt => v_cnt);

  u_sync : entity work.pal_sync_gen
    generic map (
      H_FRONT    => H_FRONT,    H_SYNC_W   => H_SYNC_W,
      H_BACK     => H_BACK,     H_ACTIVE   => H_ACTIVE,
      H_TOTAL    => H_TOTAL,    V_SYNC_L   => V_SYNC_L,
      V_BACK_L   => V_BACK_L,  V_ACTIVE_L => V_ACTIVE_L,
      V_TOTAL    => V_TOTAL
    )
    port map (
      h_cnt  => h_cnt,   v_cnt  => v_cnt,
      hsync  => hsync_s, vsync  => vsync_s,
      active => active_s, blank => blank_s
    );

  -- -----------------------------------------------------------------------
  -- Vertical bar generator: zone walks across pixels, resets each line.
  -- -----------------------------------------------------------------------
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

  -- -----------------------------------------------------------------------
  -- Horizontal bar generator: zone walks down active lines, resets each frame.
  -- -----------------------------------------------------------------------
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

  -- -----------------------------------------------------------------------
  -- Horizontal gradient generator: grey zone walks across pixels per line.
  -- -----------------------------------------------------------------------
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

  -- -----------------------------------------------------------------------
  -- Vertical gradient generator: grey zone walks down active lines per frame.
  -- -----------------------------------------------------------------------
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

  -- Bar colours from the zone-kind table
  with ZONE_TABLE(zone_idx_v) select
    color_v <= '0' when Z_BLACK, '1' when Z_WHITE, stripe_ph_v when Z_STRIPE;
  with ZONE_TABLE(zone_idx_h) select
    color_h <= '0' when Z_BLACK, '1' when Z_WHITE, stripe_ph_h when Z_STRIPE;

  -- 4-bit level shown during the active window, chosen by sel
  active_level <= GRAD_TABLE(gzx_idx) when sel_i = 2 else
                  GRAD_TABLE(gzy_idx) when sel_i = 3 else
                  LEVEL_WHITE when (sel_i = 0 and color_v = '1') or
                                   (sel_i = 1 and color_h = '1') else
                  LEVEL_BLANK;

  -- Final DAC mux: sync > active level > blanking
  dac_out <= LEVEL_SYNC   when vsync_s = '1' else
             LEVEL_SYNC   when hsync_s = '1' else
             active_level when active_s = '1' else
             LEVEL_BLANK;

  hsync_o  <= hsync_s;
  vsync_o  <= vsync_s;
  active_o <= active_s;

end architecture rtl;
