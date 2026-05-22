library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Testbench for pal_bw_zonebar_top (vertical + horizontal orientation)
--
-- Two DUT instances run in parallel so both directions are verified inside the
-- first frame (fast):
--   uut_v : orient='0' VERTICAL   - checked pixel-by-pixel over one active line
--   uut_h : orient='1' HORIZONTAL - checked line-by-line over the first 150
--                                   active lines (covers zones 0,1 and into 2)
--
-- Default pattern (8 zones): STRIPE, WHITE, STRIPE, WHITE, BLACK, STRIPE, WHITE, STRIPE
--   vertical   zone width  = 65 px
--   horizontal zone height = 72 lines
--
-- Sampling note: dac_out is combinational off h_cnt, so checkers sample on the
-- falling edge (stable mid-pixel) to avoid the read/clock delta race.
entity tb_pal_bw_zonebar_top is
end entity tb_pal_bw_zonebar_top;

architecture sim of tb_pal_bw_zonebar_top is

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  signal dac_v, dac_h         : std_logic_vector(3 downto 0);
  signal hs_v, vs_v, act_v    : std_logic;
  signal hs_h, vs_h, act_h    : std_logic;

  constant CLK_PERIOD : time := 100 ns;  -- 10 MHz (CLK_MHZ=10 for sim speed)

  -- Mirror of the DUT zone layout
  constant NUM_ZONES : integer := 8;
  constant ZONE_W    : integer := 65;   -- px per vertical zone
  constant ZONE_H    : integer := 72;   -- lines per horizontal zone
  constant STRIPE_W  : integer := 4;
  constant NLINES_H  : integer := 150;  -- horizontal active lines to check

  constant BLACK : std_logic_vector(3 downto 0) := "0100";
  constant WHITE : std_logic_vector(3 downto 0) := "1111";

  type zone_kind    is (Z_BLACK, Z_WHITE, Z_STRIPE);
  type zone_table_t is array (0 to NUM_ZONES - 1) of zone_kind;
  constant ZONE_TABLE : zone_table_t := (
    0 => Z_STRIPE, 1 => Z_WHITE,  2 => Z_STRIPE, 3 => Z_WHITE,
    4 => Z_BLACK,  5 => Z_STRIPE, 6 => Z_WHITE,  7 => Z_STRIPE
  );

  -- Expected DAC value at zone offset 'local' for a given zone kind
  function zone_color(z : integer; local : integer) return std_logic_vector is
  begin
    case ZONE_TABLE(z) is
      when Z_BLACK  => return BLACK;
      when Z_WHITE  => return WHITE;
      when Z_STRIPE =>
        if (local / STRIPE_W) mod 2 = 0 then return BLACK; else return WHITE; end if;
    end case;
  end function;

  function expected_px(px : integer) return std_logic_vector is
  begin
    return zone_color(px / ZONE_W, px mod ZONE_W);
  end function;

  function expected_line(ln : integer) return std_logic_vector is
  begin
    return zone_color(ln / ZONE_H, ln mod ZONE_H);
  end function;

begin

  clk <= not clk after CLK_PERIOD / 2;

  uut_v : entity work.pal_bw_zonebar_top
    generic map (CLK_MHZ => 10, STRIPE_W => STRIPE_W)
    port map (clk => clk, rst => rst, orient => '0',
              dac_out => dac_v, hsync_o => hs_v, vsync_o => vs_v, active_o => act_v);

  uut_h : entity work.pal_bw_zonebar_top
    generic map (CLK_MHZ => 10, STRIPE_W => STRIPE_W)
    port map (clk => clk, rst => rst, orient => '1',
              dac_out => dac_h, hsync_o => hs_h, vsync_o => vs_h, active_o => act_h);

  -- -----------------------------------------------------------------------
  -- Stimulus
  -- -----------------------------------------------------------------------
  process
  begin
    rst <= '1';
    wait for 5 * CLK_PERIOD;
    rst <= '0';

    -- Enough for vertical (1 line) + horizontal (~175 lines into frame 0)
    wait for 200 * 640 * CLK_PERIOD;

    report "=== Simulation complete ===" severity note;
    std.env.finish;
  end process;

  -- -----------------------------------------------------------------------
  -- Checker A: DAC level validity on both instances (every clock)
  -- -----------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) and rst = '0' then
      if (hs_v = '1' or vs_v = '1') then
        assert dac_v = "0000" report "FAIL V: sync level" severity error;
      end if;
      if (act_v = '0' and hs_v = '0' and vs_v = '0') then
        assert dac_v = "0100" report "FAIL V: blank level" severity error;
      end if;
      if act_v = '1' then
        assert dac_v = "1111" or dac_v = "0100" report "FAIL V: active level" severity error;
      end if;
      if act_h = '1' then
        assert dac_h = "1111" or dac_h = "0100" report "FAIL H: active level" severity error;
      end if;
    end if;
  end process;

  -- -----------------------------------------------------------------------
  -- Checker B: VERTICAL pixel-exact over the first active line
  -- -----------------------------------------------------------------------
  process
    variable px  : integer;
    variable exp : std_logic_vector(3 downto 0);
  begin
    wait until rst = '0';
    wait until rising_edge(act_v);   -- enter first active line (pixel 0 period)

    px := 0;
    loop
      wait until falling_edge(clk);
      exit when act_v = '0';
      exp := expected_px(px);
      assert dac_v = exp
        report "FAIL vert: px=" & integer'image(px) &
               " zone=" & integer'image(px / ZONE_W) &
               " exp=" & integer'image(to_integer(unsigned(exp))) &
               " got=" & integer'image(to_integer(unsigned(dac_v)))
        severity error;
      px := px + 1;
    end loop;

    assert px = 520
      report "FAIL vert: expected 520 pixels, saw " & integer'image(px) severity error;
    report "=== VERTICAL check PASSED (" & integer'image(px) & " px) ===" severity note;
    wait;
  end process;

  -- -----------------------------------------------------------------------
  -- Checker C: HORIZONTAL line-by-line over the first NLINES_H active lines
  -- -----------------------------------------------------------------------
  process
    variable exp : std_logic_vector(3 downto 0);
  begin
    wait until rst = '0';
    wait until falling_edge(vs_h);   -- end of frame's vsync -> vback, then active

    for ln in 0 to NLINES_H - 1 loop
      wait until rising_edge(act_h);   -- start of active line 'ln'
      wait until falling_edge(clk);    -- sample within the active line
      exp := expected_line(ln);
      assert dac_h = exp
        report "FAIL horiz: line=" & integer'image(ln) &
               " zone=" & integer'image(ln / ZONE_H) &
               " exp=" & integer'image(to_integer(unsigned(exp))) &
               " got=" & integer'image(to_integer(unsigned(dac_h)))
        severity error;
    end loop;

    report "=== HORIZONTAL check PASSED (" & integer'image(NLINES_H) &
           " lines) ===" severity note;
    wait;
  end process;

end architecture sim;
