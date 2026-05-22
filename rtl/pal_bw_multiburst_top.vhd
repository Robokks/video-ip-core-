library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- PAL B&W Multiburst Test Pattern Generator (no BRAM required)
--
-- Generates a multi-frequency vertical stripe pattern identical to a standard
-- video resolution test card (multiburst).  520 active pixels are divided into
-- 8 equal zones of 65 pixels each.  The stripe width doubles in each zone:
--
--   Zone 0 (px   0- 64): stripe_w =   1  (finest, alternates every pixel)
--   Zone 1 (px  65-129): stripe_w =   2
--   Zone 2 (px 130-194): stripe_w =   4
--   Zone 3 (px 195-259): stripe_w =   8
--   Zone 4 (px 260-324): stripe_w =  16
--   Zone 5 (px 325-389): stripe_w =  32
--   Zone 6 (px 390-454): stripe_w =  64  (only 1 full black stripe fits)
--   Zone 7 (px 455-519): stripe_w = 128  (zone narrower than stripe -> solid black)
--
-- Each zone resets to black (color=0) at its left boundary.
-- Pattern is the same on every active line (all vertical stripes).
-- No runtime inputs -- pattern is fully fixed.
--
-- Reuses unchanged sub-modules:
--   pal_timing   -- H/V counters + CE divider
--   pal_sync_gen -- region flags
--   pal_dac_mux  -- 4-bit DAC level mux
entity pal_bw_multiburst_top is
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
    CLK_MHZ     : integer := 40;   -- 10 / 20 / 30 / 40
    -- Zone layout
    NUM_ZONES   : integer := 8;    -- number of frequency zones
    ZONE_W      : integer := 65    -- pixels per zone (H_ACTIVE / NUM_ZONES = 520/8)
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
end entity pal_bw_multiburst_top;

architecture rtl of pal_bw_multiburst_top is

  constant H_ACT_S  : integer := H_FRONT + H_SYNC_W + H_BACK;  -- 120
  constant V_ACT_S  : integer := V_SYNC_L + V_BACK_L;           -- 25

  signal h_cnt : integer range 0 to H_TOTAL - 1;
  signal v_cnt : integer range 0 to V_TOTAL - 1;
  signal ce_s  : std_logic;

  signal hsync_s  : std_logic;
  signal vsync_s  : std_logic;
  signal active_s : std_logic;
  signal blank_s  : std_logic;

  -- Multiburst pixel generator state
  signal zone_num    : integer range 0 to 7   := 0;  -- which zone (0..NUM_ZONES-1)
  signal px_in_zone  : integer range 0 to 64  := 0;  -- pixel offset within zone
  signal zone_px_cnt : integer range 0 to 127 := 0;  -- stripe counter within zone
  signal zone_color  : std_logic              := '0'; -- current stripe color

  signal pixel_color : std_logic;

begin

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
  -- Multiburst stripe pixel generator
  --
  -- Pre-loaded one pixel-clock before the active window so that the first
  -- pixel of each active line is always zone 0, stripe-color 0 (black).
  --
  -- During active_s:
  --   Zone boundary (px_in_zone = ZONE_W-1) has priority:
  --     -> move to next zone, reset px_in_zone and zone_px_cnt, start black.
  --   Stripe boundary within a zone (zone_px_cnt = zone_w-1):
  --     -> reset zone_px_cnt, toggle zone_color.
  --   Otherwise:
  --     -> increment counters.
  --
  -- zone_w is determined combinationally from zone_num via a case statement.
  -- -----------------------------------------------------------------------
  process(clk)
    variable zone_w : integer range 1 to 128;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        zone_num    <= 0;
        px_in_zone  <= 0;
        zone_px_cnt <= 0;
        zone_color  <= '0';
      elsif ce_s = '1' then

        -- Pre-load: one cycle before the active window opens on every active line
        if h_cnt = H_ACT_S - 1 and
           v_cnt >= V_ACT_S and v_cnt < V_ACT_S + V_ACTIVE_L then
          zone_num    <= 0;
          px_in_zone  <= 0;
          zone_px_cnt <= 0;
          zone_color  <= '0';

        elsif active_s = '1' then
          -- Resolve stripe width for current zone
          case zone_num is
            when 0      => zone_w := 1;
            when 1      => zone_w := 2;
            when 2      => zone_w := 4;
            when 3      => zone_w := 8;
            when 4      => zone_w := 16;
            when 5      => zone_w := 32;
            when 6      => zone_w := 64;
            when others => zone_w := 128;  -- zone 7: wider than zone -> solid black
          end case;

          if px_in_zone = ZONE_W - 1 then
            -- ---- Zone boundary ----
            -- Advance to next zone; wrap silently (last zone stays at 7).
            if zone_num < NUM_ZONES - 1 then
              zone_num <= zone_num + 1;
            end if;
            px_in_zone  <= 0;
            zone_px_cnt <= 0;
            zone_color  <= '0';           -- each zone starts black

          else
            -- ---- Within zone ----
            px_in_zone <= px_in_zone + 1;

            if zone_px_cnt = zone_w - 1 then
              -- Stripe boundary: toggle color
              zone_px_cnt <= 0;
              zone_color  <= not zone_color;
            else
              zone_px_cnt <= zone_px_cnt + 1;
            end if;
          end if;

        end if;  -- active_s
      end if;  -- ce_s
    end if;  -- rising_edge
  end process;

  pixel_color <= zone_color;

  hsync_o  <= hsync_s;
  vsync_o  <= vsync_s;
  active_o <= active_s;

end architecture rtl;
