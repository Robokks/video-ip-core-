library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- PAL B&W Zone-Bar Test Pattern Generator (no BRAM required)
--
-- The active picture is split into NUM_ZONES equal zones.  Each zone is one
-- of three kinds, set by the editable ZONE_TABLE below:
--   Z_BLACK  -> solid black bar
--   Z_WHITE  -> solid white bar
--   Z_STRIPE -> fine alternating black/white stripes (width = STRIPE_W)
--
-- orient selects the bar direction at runtime (wire to a Boolean / 0-1 control):
--   orient = '0' : VERTICAL   bars  - zones run left->right across the 520 px,
--                                     stripe zones alternate every STRIPE_W px
--   orient = '1' : HORIZONTAL bars  - zones run top->bottom across the 576 lines,
--                                     stripe zones alternate every STRIPE_W lines
--
-- Default layout (8 zones), in order:
--   STRIPE, WHITE, STRIPE, WHITE, BLACK, STRIPE, WHITE, STRIPE
--   vertical   : zone width  = H_ACTIVE/NUM_ZONES = 520/8 = 65 px
--   horizontal : zone height = V_ACTIVE_L/NUM_ZONES = 576/8 = 72 lines
--
-- To change the pattern: edit ZONE_TABLE (and NUM_ZONES if you add/remove
-- zones).  Change STRIPE_W to make the striped bars finer or coarser.
--
-- Pixel-path arithmetic is incremental counters + a constant-table lookup.
-- There is NO runtime divide or multiply, so it closes timing in a single
-- SCTL cycle at 40 MHz.  Each zone restarts black at its leading edge; the
-- vertical pattern restarts every active line and the horizontal pattern
-- restarts every frame.
--
-- Reuses unchanged sub-modules:
--   pal_timing   -- H/V counters + CE divider
--   pal_sync_gen -- region flags
--   pal_dac_mux  -- 4-bit DAC level mux
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
    STRIPE_W    : integer := 4    -- pixels (vertical) or lines (horizontal) per stripe
  );
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;

    -- Bar direction: '0' = vertical, '1' = horizontal
    orient   : in  std_logic;

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

  -- ----- Zone layout (edit here to change the pattern) -----
  constant NUM_ZONES : integer := 8;
  constant ZONE_W    : integer := H_ACTIVE   / NUM_ZONES;  -- 65 px   (compile-time)
  constant ZONE_H    : integer := V_ACTIVE_L / NUM_ZONES;  -- 72 lines (compile-time)

  type zone_kind    is (Z_BLACK, Z_WHITE, Z_STRIPE);
  type zone_table_t is array (0 to NUM_ZONES - 1) of zone_kind;

  constant ZONE_TABLE : zone_table_t := (
    0 => Z_STRIPE,
    1 => Z_WHITE,
    2 => Z_STRIPE,
    3 => Z_WHITE,
    4 => Z_BLACK,
    5 => Z_STRIPE,
    6 => Z_WHITE,
    7 => Z_STRIPE
  );
  -- ---------------------------------------------------------

  signal h_cnt : integer range 0 to H_TOTAL - 1;
  signal v_cnt : integer range 0 to V_TOTAL - 1;
  signal ce_s  : std_logic;

  signal hsync_s  : std_logic;
  signal vsync_s  : std_logic;
  signal active_s : std_logic;
  signal blank_s  : std_logic;

  -- Vertical generator state (advances per active pixel, resets each line)
  signal zone_idx_v   : integer range 0 to NUM_ZONES - 1 := 0;
  signal px_in_zone   : integer range 0 to ZONE_W - 1     := 0;
  signal stripe_cnt_v : integer range 0 to STRIPE_W - 1   := 0;
  signal stripe_ph_v  : std_logic                         := '0';

  -- Horizontal generator state (advances per active line, resets each frame)
  signal zone_idx_h   : integer range 0 to NUM_ZONES - 1 := 0;
  signal line_in_zone : integer range 0 to ZONE_H - 1     := 0;
  signal stripe_cnt_h : integer range 0 to STRIPE_W - 1   := 0;
  signal stripe_ph_h  : std_logic                         := '0';

  signal color_v     : std_logic;
  signal color_h     : std_logic;
  signal pixel_color : std_logic;

begin

  assert NUM_ZONES * ZONE_W = H_ACTIVE
    report "NUM_ZONES * ZONE_W must equal H_ACTIVE" severity failure;
  assert NUM_ZONES * ZONE_H = V_ACTIVE_L
    report "NUM_ZONES * ZONE_H must equal V_ACTIVE_L" severity failure;

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

  u_mux : entity work.pal_dac_mux
    generic map (
      LEVEL_SYNC  => LEVEL_SYNC,
      LEVEL_BLANK => LEVEL_BLANK,
      LEVEL_WHITE => LEVEL_WHITE
    )
    port map (
      vsync    => vsync_s,
      hsync    => hsync_s,
      active   => active_s,
      pixel_in => pixel_color,
      dac_out  => dac_out
    );

  -- -----------------------------------------------------------------------
  -- Vertical generator: zone index walks across pixels in each active line.
  -- Pre-loaded one pixel-clock before the active window so pixel 0 of every
  -- line is zone 0, black.  Only counters + compares to compile-time
  -- constants -- no runtime divide or multiply.
  -- -----------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        zone_idx_v   <= 0;
        px_in_zone   <= 0;
        stripe_cnt_v <= 0;
        stripe_ph_v  <= '0';
      elsif ce_s = '1' then
        if h_cnt = H_ACT_S - 1 and
           v_cnt >= V_ACT_S and v_cnt < V_ACT_S + V_ACTIVE_L then
          zone_idx_v   <= 0;
          px_in_zone   <= 0;
          stripe_cnt_v <= 0;
          stripe_ph_v  <= '0';
        elsif active_s = '1' then
          if px_in_zone = ZONE_W - 1 then
            if zone_idx_v < NUM_ZONES - 1 then
              zone_idx_v <= zone_idx_v + 1;
            end if;
            px_in_zone   <= 0;
            stripe_cnt_v <= 0;
            stripe_ph_v  <= '0';
          else
            px_in_zone <= px_in_zone + 1;
            if stripe_cnt_v = STRIPE_W - 1 then
              stripe_cnt_v <= 0;
              stripe_ph_v  <= not stripe_ph_v;
            else
              stripe_cnt_v <= stripe_cnt_v + 1;
            end if;
          end if;
        end if;
      end if;
    end if;
  end process;

  -- -----------------------------------------------------------------------
  -- Horizontal generator: zone index walks down active lines in each frame.
  -- The colour is constant for a whole line and only updates at end-of-line.
  -- Pre-loaded at the end of the last blanking line so active line 0 is zone
  -- 0, black.  Only counters + compares to compile-time constants.
  -- -----------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        zone_idx_h   <= 0;
        line_in_zone <= 0;
        stripe_cnt_h <= 0;
        stripe_ph_h  <= '0';
      elsif ce_s = '1' then
        if v_cnt = V_ACT_S - 1 and h_cnt = H_TOTAL - 1 then
          zone_idx_h   <= 0;
          line_in_zone <= 0;
          stripe_cnt_h <= 0;
          stripe_ph_h  <= '0';
        elsif v_cnt >= V_ACT_S and v_cnt < V_ACT_S + V_ACTIVE_L and
              h_cnt = H_TOTAL - 1 then
          if line_in_zone = ZONE_H - 1 then
            if zone_idx_h < NUM_ZONES - 1 then
              zone_idx_h <= zone_idx_h + 1;
            end if;
            line_in_zone <= 0;
            stripe_cnt_h <= 0;
            stripe_ph_h  <= '0';
          else
            line_in_zone <= line_in_zone + 1;
            if stripe_cnt_h = STRIPE_W - 1 then
              stripe_cnt_h <= 0;
              stripe_ph_h  <= not stripe_ph_h;
            else
              stripe_cnt_h <= stripe_cnt_h + 1;
            end if;
          end if;
        end if;
      end if;
    end if;
  end process;

  -- Per-direction colour = constant-table lookup of the current zone kind.
  with ZONE_TABLE(zone_idx_v) select
    color_v <= '0'         when Z_BLACK,
               '1'         when Z_WHITE,
               stripe_ph_v when Z_STRIPE;

  with ZONE_TABLE(zone_idx_h) select
    color_h <= '0'         when Z_BLACK,
               '1'         when Z_WHITE,
               stripe_ph_h when Z_STRIPE;

  -- Select bar direction
  pixel_color <= color_h when orient = '1' else color_v;

  hsync_o  <= hsync_s;
  vsync_o  <= vsync_s;
  active_o <= active_s;

end architecture rtl;
