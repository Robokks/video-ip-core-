library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- PAL B&W Zone-Bar Test Pattern Generator (no BRAM required)
--
-- The 520 active pixels are split into NUM_ZONES equal vertical zones.
-- Each zone is one of three kinds, set by the editable ZONE_TABLE below:
--   Z_BLACK  -> solid black bar
--   Z_WHITE  -> solid white bar
--   Z_STRIPE -> fine alternating black/white stripes (width = STRIPE_W pixels)
--
-- Default layout (8 zones x 65 px), left -> right:
--   zone 0 : STRIPE   (px   0- 64)
--   zone 1 : WHITE    (px  65-129)
--   zone 2 : STRIPE   (px 130-194)
--   zone 3 : WHITE    (px 195-259)
--   zone 4 : BLACK    (px 260-324)
--   zone 5 : STRIPE   (px 325-389)
--   zone 6 : WHITE    (px 390-454)
--   zone 7 : STRIPE   (px 455-519)
--
-- To change the pattern: edit ZONE_TABLE (and NUM_ZONES if you add/remove
-- zones -- NUM_ZONES * ZONE_W must equal H_ACTIVE).  Change STRIPE_W to make
-- the striped bars finer or coarser.
--
-- Pixel-path arithmetic is incremental counters + a constant-table lookup.
-- There is NO runtime divide or multiply, so it closes timing in a single
-- SCTL cycle at 40 MHz.  Each zone restarts black at its left edge, and the
-- whole pattern restarts at the start of every active line.
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
    STRIPE_W    : integer := 4    -- pixels per stripe inside a STRIPE zone
  );
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;

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
  constant ZONE_W    : integer := H_ACTIVE / NUM_ZONES;  -- 65 (compile-time)

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

  -- Pixel generator state (all hold the value for the pixel currently shown)
  signal zone_idx     : integer range 0 to NUM_ZONES - 1 := 0;  -- current zone
  signal px_in_zone   : integer range 0 to ZONE_W - 1    := 0;  -- offset within zone
  signal stripe_cnt   : integer range 0 to STRIPE_W - 1  := 0;  -- stripe sub-counter
  signal stripe_phase : std_logic                        := '0'; -- stripe colour

  signal pixel_color : std_logic;

begin

  assert NUM_ZONES * ZONE_W = H_ACTIVE
    report "NUM_ZONES * ZONE_W must equal H_ACTIVE" severity failure;

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
  -- Zone / stripe pixel generator.
  --
  -- The registers hold the state of the pixel currently being shown.  On each
  -- active pixel the process computes the state for the NEXT pixel.  A pre-load
  -- one pixel-clock before the active window sets up pixel 0 of every line.
  --
  -- Only counters, compares against compile-time constants, and a table index
  -- are used here -- no runtime divide or multiply.
  -- -----------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        zone_idx     <= 0;
        px_in_zone   <= 0;
        stripe_cnt   <= 0;
        stripe_phase <= '0';
      elsif ce_s = '1' then

        -- Pre-load: one cycle before the active window opens on every active line
        if h_cnt = H_ACT_S - 1 and
           v_cnt >= V_ACT_S and v_cnt < V_ACT_S + V_ACTIVE_L then
          zone_idx     <= 0;
          px_in_zone   <= 0;
          stripe_cnt   <= 0;
          stripe_phase <= '0';

        elsif active_s = '1' then
          if px_in_zone = ZONE_W - 1 then
            -- ---- Zone boundary: advance to next zone, restart black ----
            if zone_idx < NUM_ZONES - 1 then
              zone_idx <= zone_idx + 1;
            end if;
            px_in_zone   <= 0;
            stripe_cnt   <= 0;
            stripe_phase <= '0';

          else
            -- ---- Within zone ----
            px_in_zone <= px_in_zone + 1;
            if stripe_cnt = STRIPE_W - 1 then
              stripe_cnt   <= 0;
              stripe_phase <= not stripe_phase;
            else
              stripe_cnt <= stripe_cnt + 1;
            end if;
          end if;
        end if;  -- active_s
      end if;  -- ce_s
    end if;  -- rising_edge
  end process;

  -- Pixel colour = constant-table lookup of the current zone kind.
  -- Solid zones ignore stripe_phase; stripe zones follow it.
  with ZONE_TABLE(zone_idx) select
    pixel_color <= '0'          when Z_BLACK,
                   '1'          when Z_WHITE,
                   stripe_phase when Z_STRIPE;

  hsync_o  <= hsync_s;
  vsync_o  <= vsync_s;
  active_o <= active_s;

end architecture rtl;
