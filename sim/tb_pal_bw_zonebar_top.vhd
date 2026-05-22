library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Testbench for pal_bw_zonebar_top
--
-- Mirrors the DUT's zone layout (8 zones x 65 px, STRIPE_W=4) and checks the
-- first active line pixel-by-pixel, plus DAC level validity everywhere.
--
-- DUT default pattern, left -> right:
--   zone 0 STRIPE, 1 WHITE, 2 STRIPE, 3 WHITE, 4 BLACK, 5 STRIPE, 6 WHITE, 7 STRIPE
--
-- NOTE on sampling: active_o is combinational from h_cnt, so it rises one delta
-- after the clock edge that opens the active window.  dac_out is already valid
-- for pixel 0 at that point, so the checker samples pixel 0 BEFORE waiting for
-- the next clock edge, then advances one pixel per clock.  (Sampling after the
-- first clock edge would skip pixel 0 and shift every check by one.)
entity tb_pal_bw_zonebar_top is
end entity tb_pal_bw_zonebar_top;

architecture sim of tb_pal_bw_zonebar_top is

  signal clk      : std_logic := '0';
  signal rst      : std_logic := '1';
  signal dac_out  : std_logic_vector(3 downto 0);
  signal hsync_o  : std_logic;
  signal vsync_o  : std_logic;
  signal active_o : std_logic;

  constant CLK_PERIOD : time := 100 ns;  -- 10 MHz (CLK_MHZ=10 for sim speed)

  -- Mirror of the DUT zone layout
  constant NUM_ZONES : integer := 8;
  constant ZONE_W    : integer := 65;
  constant STRIPE_W  : integer := 4;

  constant BLACK : std_logic_vector(3 downto 0) := "0100";
  constant WHITE : std_logic_vector(3 downto 0) := "1111";

  type zone_kind    is (Z_BLACK, Z_WHITE, Z_STRIPE);
  type zone_table_t is array (0 to NUM_ZONES - 1) of zone_kind;
  constant ZONE_TABLE : zone_table_t := (
    0 => Z_STRIPE, 1 => Z_WHITE,  2 => Z_STRIPE, 3 => Z_WHITE,
    4 => Z_BLACK,  5 => Z_STRIPE, 6 => Z_WHITE,  7 => Z_STRIPE
  );

  -- Expected DAC value for active pixel px (0..519)
  function expected_px(px : integer) return std_logic_vector is
    variable zone  : integer;
    variable local : integer;
  begin
    zone  := px / ZONE_W;
    local := px mod ZONE_W;
    case ZONE_TABLE(zone) is
      when Z_BLACK  => return BLACK;
      when Z_WHITE  => return WHITE;
      when Z_STRIPE =>
        if (local / STRIPE_W) mod 2 = 0 then
          return BLACK;            -- each stripe zone starts black
        else
          return WHITE;
        end if;
    end case;
  end function;

begin

  clk <= not clk after CLK_PERIOD / 2;

  uut : entity work.pal_bw_zonebar_top
    generic map (CLK_MHZ => 10, STRIPE_W => STRIPE_W)
    port map (
      clk      => clk,
      rst      => rst,
      dac_out  => dac_out,
      hsync_o  => hsync_o,
      vsync_o  => vsync_o,
      active_o => active_o
    );

  -- -----------------------------------------------------------------------
  -- Stimulus
  -- -----------------------------------------------------------------------
  process
  begin
    rst <= '1';
    wait for 5 * CLK_PERIOD;
    rst <= '0';

    -- Run 35 lines (vsync 5 + vback 20 + ~10 active lines)
    wait for 35 * 640 * CLK_PERIOD;

    report "=== Simulation complete ===" severity note;
    std.env.finish;
  end process;

  -- -----------------------------------------------------------------------
  -- Checker 1: DAC level validity (runs every clock)
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
  -- Checker 2: pixel-exact zone pattern over the first active line
  -- -----------------------------------------------------------------------
  process
    variable px  : integer;
    variable exp : std_logic_vector(3 downto 0);
  begin
    wait until rst = '0';
    wait until rising_edge(active_o);   -- enter first active line (pixel 0 period)

    -- Sample on the falling edge: dac_out is stable mid-pixel, avoiding the
    -- read/clock race that occurs when sampling on the rising edge.
    px := 0;
    loop
      wait until falling_edge(clk);
      exit when active_o = '0';
      exp := expected_px(px);
      assert dac_out = exp
        report "FAIL zonebar: px=" & integer'image(px) &
               " zone=" & integer'image(px / ZONE_W) &
               " exp=" & integer'image(to_integer(unsigned(exp))) &
               " got=" & integer'image(to_integer(unsigned(dac_out)))
        severity error;
      px := px + 1;
    end loop;

    report "First active line sampled: " & integer'image(px) & " pixels" severity note;
    assert px = 520
      report "FAIL: expected 520 active pixels, saw " & integer'image(px)
      severity error;
    report "=== Zone-bar pattern check PASSED ===" severity note;
    wait;
  end process;

end architecture sim;
