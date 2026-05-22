library ieee;
use ieee.std_logic_1164.all;

-- PAL B&W Video -- Stripe Pattern Generator (no BRAM required)
-- Revision 2: for simulation and hardware bring-up checks.
--
-- Generates vertical black/white stripes across the active picture area.
-- Each stripe is STRIPE_WIDTH pixels wide, alternating black then white.
-- All sync, blanking, and DAC level logic is identical to pal_bw_top.
-- Supports 10 / 20 / 30 / 40 MHz input clocks via CLK_MHZ generic.
--
-- Use this instead of pal_bw_top to verify:
--   - correct H/V sync timing on a scope or logic analyser
--   - correct DAC levels on the R-2R output
--   - NI-9401 wiring before connecting real BRAM pixel data
entity pal_bw_stripe_top is
  generic (
    -- PAL horizontal timing (clocks, must sum to H_TOTAL)
    H_FRONT    : integer := 16;
    H_SYNC_W   : integer := 47;
    H_BACK     : integer := 57;
    H_ACTIVE   : integer := 520;
    H_TOTAL    : integer := 640;
    -- PAL vertical timing (lines)
    V_SYNC_L   : integer := 5;
    V_BACK_L   : integer := 20;
    V_ACTIVE_L : integer := 576;
    V_TOTAL    : integer := 625;
    -- DAC levels (4-bit)
    LEVEL_SYNC  : std_logic_vector(3 downto 0) := "0000";
    LEVEL_BLANK : std_logic_vector(3 downto 0) := "0100";
    LEVEL_WHITE : std_logic_vector(3 downto 0) := "1111";
    -- Stripe width in pixels (default 40 px -> 13 stripes across 520 px)
    STRIPE_WIDTH : integer := 40;
    -- Input clock selection: 10, 20, 30, or 40 (MHz)
    CLK_MHZ      : integer := 10
  );
  port (
    clk      : in  std_logic;   -- 10 / 20 / 30 / 40 MHz (set CLK_MHZ)
    rst      : in  std_logic;   -- synchronous reset, active-high
    -- 4-bit DAC output
    dac_out  : out std_logic_vector(3 downto 0);
    -- Debug / sync outputs
    hsync_o  : out std_logic;
    vsync_o  : out std_logic;
    active_o : out std_logic
  );
end entity pal_bw_stripe_top;

architecture rtl of pal_bw_stripe_top is

  constant H_ACT_S  : integer := H_FRONT + H_SYNC_W + H_BACK;  -- 120
  constant V_ACT_S  : integer := V_SYNC_L + V_BACK_L;           -- 25

  signal h_cnt : integer range 0 to H_TOTAL - 1;
  signal v_cnt : integer range 0 to V_TOTAL - 1;

  signal ce_s     : std_logic;   -- 10 MHz pixel clock enable
  signal hsync_s  : std_logic;
  signal vsync_s  : std_logic;
  signal active_s : std_logic;
  signal blank_s  : std_logic;

  -- Stripe generator
  signal stripe_cnt   : integer range 0 to STRIPE_WIDTH - 1 := 0;
  signal stripe_color : std_logic := '0';  -- '0'=black, '1'=white

begin

  -- H/V counters with clock-enable divider
  u_timing : entity work.pal_timing
    generic map (H_TOTAL => H_TOTAL, V_TOTAL => V_TOTAL, CLK_MHZ => CLK_MHZ)
    port map (clk => clk, rst => rst, ce => ce_s, h_cnt => h_cnt, v_cnt => v_cnt);

  -- Sync / active / blank flags
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

  -- DAC level mux (reuses same entity as pal_bw_top)
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
      pixel_in => stripe_color,
      dac_out  => dac_out
    );

  -- Stripe counter: resets at the start of each active line,
  -- toggles stripe_color every STRIPE_WIDTH pixels.
  -- All updates gated on ce_s so the pattern is correct at any CLK_MHZ.
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        stripe_cnt   <= 0;
        stripe_color <= '0';

      elsif ce_s = '1' then

        -- One pixel-clock before active starts: pre-load so pixel 0 is correct
        if h_cnt = H_ACT_S - 1 and
           v_cnt >= V_ACT_S and
           v_cnt < V_ACT_S + V_ACTIVE_L then
          stripe_cnt   <= 0;
          stripe_color <= '0';  -- every line starts with a black stripe

        -- During active pixels: advance stripe counter
        elsif active_s = '1' then
          if stripe_cnt = STRIPE_WIDTH - 1 then
            stripe_cnt   <= 0;
            stripe_color <= not stripe_color;
          else
            stripe_cnt <= stripe_cnt + 1;
          end if;
        end if;

      end if;
    end if;
  end process;

  hsync_o  <= hsync_s;
  vsync_o  <= vsync_s;
  active_o <= active_s;

end architecture rtl;
