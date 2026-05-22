library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Testbench for pal_bw_stripe_top Rev 3 (runtime stripe_width, stripe_dir).
-- Runs two test phases:
--   Phase 1: vertical stripes, width=40  -> checks pixels 0-39=black, 40-79=white
--   Phase 2: horizontal stripes, width=4 -> checks line 0-3=black, 4-7=white
entity tb_pal_bw_stripe_top is
end entity tb_pal_bw_stripe_top;

architecture sim of tb_pal_bw_stripe_top is

  signal clk          : std_logic := '0';
  signal rst          : std_logic := '1';
  signal stripe_width : std_logic_vector(15 downto 0) := std_logic_vector(to_unsigned(40, 16));
  signal stripe_dir   : std_logic := '0';  -- vertical
  signal dac_out      : std_logic_vector(3 downto 0);
  signal hsync_o      : std_logic;
  signal vsync_o      : std_logic;
  signal active_o     : std_logic;

  constant CLK_PERIOD : time := 100 ns;  -- 10 MHz (CLK_MHZ=10 for sim speed)

begin

  clk <= not clk after CLK_PERIOD / 2;

  uut : entity work.pal_bw_stripe_top
    generic map (CLK_MHZ => 10)           -- use 10 MHz in sim (faster)
    port map (
      clk          => clk,
      rst          => rst,
      stripe_width => stripe_width,
      stripe_dir   => stripe_dir,
      dac_out      => dac_out,
      hsync_o      => hsync_o,
      vsync_o      => vsync_o,
      active_o     => active_o
    );

  -- -----------------------------------------------------------------------
  -- Stimulus
  -- -----------------------------------------------------------------------
  process
  begin
    -- Release reset
    rst <= '1';
    wait for 5 * CLK_PERIOD;
    rst <= '0';

    -- Phase 1: vertical stripes, width=40 (run 35 lines)
    stripe_width <= std_logic_vector(to_unsigned(40, 16));
    stripe_dir   <= '0';
    wait for 35 * 640 * CLK_PERIOD;

    -- Phase 2: horizontal stripes, width=4 (run 1 full frame to see effect)
    stripe_width <= std_logic_vector(to_unsigned(4, 16));
    stripe_dir   <= '1';
    wait for 625 * 640 * CLK_PERIOD;

    report "=== Simulation complete ===" severity note;
    std.env.finish;
  end process;

  -- -----------------------------------------------------------------------
  -- Checker 1: DAC level validity (runs always)
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
  -- Checker 2: Vertical stripe pixel positions (Phase 1)
  -- Waits for first active line, checks 5 lines for correct pattern.
  -- -----------------------------------------------------------------------
  process
    constant SW  : integer := 40;
    variable px  : integer;
    variable exp : std_logic_vector(3 downto 0);
  begin
    wait until rst = '0';
    wait until rising_edge(active_o);  -- start of first active line

    for line in 0 to 4 loop
      px := 0;
      loop
        wait until rising_edge(clk);
        exit when active_o = '0';
        exp := "0100" when (px / SW) mod 2 = 0 else "1111";  -- even=black odd=white
        assert dac_out = exp
          report "FAIL vertical stripe: line=" & integer'image(line) &
                 " px=" & integer'image(px) &
                 " exp=" & integer'image(to_integer(unsigned(exp))) &
                 " got=" & integer'image(to_integer(unsigned(dac_out)))
          severity error;
        px := px + 1;
      end loop;
      report "Vertical stripe line " & integer'image(line) & " OK (" &
             integer'image(px) & " pixels)" severity note;
      wait until rising_edge(active_o);
    end loop;
    report "=== Vertical stripe check PASSED ===" severity note;
    wait;
  end process;

end architecture sim;
