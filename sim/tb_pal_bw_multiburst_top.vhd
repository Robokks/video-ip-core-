library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Testbench for pal_bw_multiburst_top
--
-- Runs 35 lines (enough to cover vsync + blanking + 10 active lines).
-- Three independent checkers:
--
--   Checker 1: DAC level validity
--     sync   region -> dac_out = "0000"
--     blanking region -> dac_out = "0100"
--     active region  -> dac_out = "0100" or "1111" only
--
--   Checker 2: Zone 0 pixel values (stripe_w=1, alternates every pixel)
--     Even pixels (0,2,4,...) = BLACK ("0100")
--     Odd  pixels (1,3,5,...) = WHITE ("1111")
--     Checks 65 pixels (full zone 0).
--
--   Checker 3: Zone 1 pixel values (stripe_w=2)
--     px 65-66 = BLACK, 67-68 = WHITE, 69-70 = BLACK, ...
--     Checks 65 pixels (full zone 1: px 65..129).
--
--   Checker 4: Zone 2 pixel values (stripe_w=4)
--     px 130-133 = BLACK, 134-137 = WHITE, ...
--     Checks 65 pixels (full zone 2: px 130..194).
entity tb_pal_bw_multiburst_top is
end entity tb_pal_bw_multiburst_top;

architecture sim of tb_pal_bw_multiburst_top is

  signal clk      : std_logic := '0';
  signal rst      : std_logic := '1';
  signal dac_out  : std_logic_vector(3 downto 0);
  signal hsync_o  : std_logic;
  signal vsync_o  : std_logic;
  signal active_o : std_logic;

  constant CLK_PERIOD : time := 100 ns;  -- 10 MHz (CLK_MHZ=10 for sim speed)

begin

  clk <= not clk after CLK_PERIOD / 2;

  uut : entity work.pal_bw_multiburst_top
    generic map (CLK_MHZ => 10)
    port map (
      clk      => clk,
      rst      => rst,
      dac_out  => dac_out,
      hsync_o  => hsync_o,
      vsync_o  => vsync_o,
      active_o => active_o
    );

  -- -----------------------------------------------------------------------
  -- Stimulus: release reset, run long enough for full check
  -- -----------------------------------------------------------------------
  process
  begin
    rst <= '1';
    wait for 5 * CLK_PERIOD;
    rst <= '0';

    -- Run 35 lines of clock (vsync=5 + vback=20 + 10 active lines)
    wait for 35 * 640 * CLK_PERIOD;

    report "=== Simulation complete ===" severity note;
    std.env.finish;
  end process;

  -- -----------------------------------------------------------------------
  -- Checker 1: DAC level validity (combinational, runs on every clock edge)
  -- -----------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) and rst = '0' then
      if hsync_o = '1' or vsync_o = '1' then
        assert dac_out = "0000"
          report "FAIL: sync region bad value " &
                 integer'image(to_integer(unsigned(dac_out))) severity error;
      end if;
      if active_o = '0' and hsync_o = '0' and vsync_o = '0' then
        assert dac_out = "0100"
          report "FAIL: blanking region bad value " &
                 integer'image(to_integer(unsigned(dac_out))) severity error;
      end if;
      if active_o = '1' then
        assert dac_out = "1111" or dac_out = "0100"
          report "FAIL: active region invalid value " &
                 integer'image(to_integer(unsigned(dac_out))) severity error;
      end if;
    end if;
  end process;

  -- -----------------------------------------------------------------------
  -- Checker 2: Zone 0 -- stripe_w=1 (alternates every pixel)
  --   Pixel 0: BLACK, pixel 1: WHITE, pixel 2: BLACK ...
  -- Checker 3: Zone 1 -- stripe_w=2
  --   Pixels 65-66: BLACK, 67-68: WHITE, 69-70: BLACK ...
  -- Checker 4: Zone 2 -- stripe_w=4
  --   Pixels 130-133: BLACK, 134-137: WHITE, ...
  --
  -- All three run sequentially within one active line.
  -- -----------------------------------------------------------------------
  process
    constant BLACK  : std_logic_vector(3 downto 0) := "0100";
    constant WHITE  : std_logic_vector(3 downto 0) := "1111";

    -- Zone boundaries and stripe widths
    constant ZONE0_START : integer := 0;
    constant ZONE1_START : integer := 65;
    constant ZONE2_START : integer := 130;
    constant ZONE_W_PX   : integer := 65;
    constant SW0         : integer := 1;
    constant SW1         : integer := 2;
    constant SW2         : integer := 4;

    variable px    : integer;
    variable exp   : std_logic_vector(3 downto 0);
    variable local_px : integer;
  begin
    wait until rst = '0';
    wait until rising_edge(active_o);   -- start of first active line

    -- Collect all 520 pixels of the first active line
    px := 0;
    loop
      wait until rising_edge(clk);
      exit when active_o = '0';

      -- Zone 0 check
      if px >= ZONE0_START and px < ZONE0_START + ZONE_W_PX then
        local_px := px - ZONE0_START;
        exp := BLACK when (local_px / SW0) mod 2 = 0 else WHITE;
        assert dac_out = exp
          report "FAIL zone0: px=" & integer'image(px) &
                 " exp=" & integer'image(to_integer(unsigned(exp))) &
                 " got=" & integer'image(to_integer(unsigned(dac_out)))
          severity error;
      end if;

      -- Zone 1 check
      if px >= ZONE1_START and px < ZONE1_START + ZONE_W_PX then
        local_px := px - ZONE1_START;
        exp := BLACK when (local_px / SW1) mod 2 = 0 else WHITE;
        assert dac_out = exp
          report "FAIL zone1: px=" & integer'image(px) &
                 " exp=" & integer'image(to_integer(unsigned(exp))) &
                 " got=" & integer'image(to_integer(unsigned(dac_out)))
          severity error;
      end if;

      -- Zone 2 check
      if px >= ZONE2_START and px < ZONE2_START + ZONE_W_PX then
        local_px := px - ZONE2_START;
        exp := BLACK when (local_px / SW2) mod 2 = 0 else WHITE;
        assert dac_out = exp
          report "FAIL zone2: px=" & integer'image(px) &
                 " exp=" & integer'image(to_integer(unsigned(exp))) &
                 " got=" & integer'image(to_integer(unsigned(dac_out)))
          severity error;
      end if;

      px := px + 1;
    end loop;

    report "First active line: " & integer'image(px) & " pixels sampled" severity note;
    report "Zone 0 (px 0-64, sw=1): checked" severity note;
    report "Zone 1 (px 65-129, sw=2): checked" severity note;
    report "Zone 2 (px 130-194, sw=4): checked" severity note;
    report "=== Multiburst pattern check PASSED ===" severity note;
    wait;
  end process;

end architecture sim;
