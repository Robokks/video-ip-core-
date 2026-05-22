library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Testbench for pal_bw_stripe_top (Revision 2 - no BRAM).
--
-- Runs 35 complete lines to cover:
--   Lines  0- 4 : vsync    -> dac_out = "0000" on sync/vsync
--   Lines  5-24 : blanking -> dac_out = "0000" or "0100"
--   Lines 25-34 : active   -> dac_out alternates "0100"/"1111" in STRIPE_WIDTH blocks
--
-- Two checkers run in parallel:
--   1. Level checker  : verifies correct DAC value for each timing region
--   2. Stripe checker : waits for active_o rising edge, then counts pixels
--                       and asserts exact black/white pattern per stripe
entity tb_pal_bw_stripe_top is
end entity tb_pal_bw_stripe_top;

architecture sim of tb_pal_bw_stripe_top is

  signal clk      : std_logic := '0';
  signal rst      : std_logic := '1';
  signal dac_out  : std_logic_vector(3 downto 0);
  signal hsync_o  : std_logic;
  signal vsync_o  : std_logic;
  signal active_o : std_logic;

  constant CLK_PERIOD : time    := 100 ns;  -- 10 MHz
  constant STRIPE_W   : integer := 40;      -- pixels per stripe

begin

  clk <= not clk after CLK_PERIOD / 2;

  uut : entity work.pal_bw_stripe_top
    generic map (STRIPE_WIDTH => STRIPE_W)
    port map (
      clk      => clk,
      rst      => rst,
      dac_out  => dac_out,
      hsync_o  => hsync_o,
      vsync_o  => vsync_o,
      active_o => active_o
    );

  -- Main stimulus: release reset, run 35 lines, stop
  process
  begin
    rst <= '1';
    wait for 5 * CLK_PERIOD;
    rst <= '0';
    wait for 35 * 640 * CLK_PERIOD;
    report "=== Simulation complete: 35 lines ===" severity note;
    std.env.finish;
  end process;

  -- -----------------------------------------------------------------------
  -- Checker 1: Level correctness (every clock edge after reset)
  -- -----------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) and rst = '0' then

      -- Sync regions: must be sync tip
      if hsync_o = '1' or vsync_o = '1' then
        assert dac_out = "0000"
          report "FAIL [level] sync region: got " &
                 integer'image(to_integer(unsigned(dac_out)))
          severity error;
      end if;

      -- Blanking (not active, not sync): must be blank/black level
      if active_o = '0' and hsync_o = '0' and vsync_o = '0' then
        assert dac_out = "0100"
          report "FAIL [level] blanking region: got " &
                 integer'image(to_integer(unsigned(dac_out)))
          severity error;
      end if;

      -- Active region: must be white or black only, nothing else
      if active_o = '1' then
        assert dac_out = "1111" or dac_out = "0100"
          report "FAIL [level] active region has invalid value: " &
                 integer'image(to_integer(unsigned(dac_out)))
          severity error;
      end if;

    end if;
  end process;

  -- -----------------------------------------------------------------------
  -- Checker 2: Exact stripe pattern
  -- Synchronises on active_o rising edge (start of each active line),
  -- then counts pixels and checks expected black/white value.
  -- Checks 5 active lines.
  -- -----------------------------------------------------------------------
  process
    variable px     : integer;
    variable stripe : integer;
    variable exp    : std_logic_vector(3 downto 0);
  begin
    wait until rst = '0';

    -- Wait for the very first active_o rising edge (start of line 25)
    wait until rising_edge(active_o);

    for line in 0 to 4 loop
      px := 0;

      -- active_o just went high: we are at the first pixel of this active line
      loop
        -- Sample dac_out on each rising clock edge while active
        wait until rising_edge(clk);
        exit when active_o = '0';  -- end of active line

        stripe := px / STRIPE_W;
        if stripe mod 2 = 0 then
          exp := "0100";  -- even stripe = black
        else
          exp := "1111";  -- odd  stripe = white
        end if;

        assert dac_out = exp
          report "FAIL [stripe] line=" & integer'image(line) &
                 " px=" & integer'image(px) &
                 " stripe=" & integer'image(stripe) &
                 " expected=" & integer'image(to_integer(unsigned(exp))) &
                 " got=" & integer'image(to_integer(unsigned(dac_out)))
          severity error;

        px := px + 1;
      end loop;

      -- Verify we got exactly H_ACTIVE pixels
      assert px = 520
        report "FAIL [stripe] line=" & integer'image(line) &
               " pixel count=" & integer'image(px) & " expected 520"
        severity error;

      report "INFO: line " & integer'image(line) &
             " stripe check passed (" & integer'image(px) & " pixels)"
        severity note;

      -- Wait for next active_o rising edge (start of next active line)
      wait until rising_edge(active_o);
    end loop;

    report "=== Stripe pattern check PASSED for 5 active lines ===" severity note;
    wait;
  end process;

end architecture sim;
