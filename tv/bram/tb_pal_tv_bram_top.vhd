library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Testbench for pal_tv_bram_top
--
-- Checks:
--   1. sel=0  vertical bars (baseline, same as interlaced_top)
--   2. sel=4  BRAM pixel readout
--              pattern: pixel i = (i mod 2)  → alternating black/white
--              bram_len = 520  → wraps each line; second line identical to first
entity tb_pal_tv_bram_top is
end entity tb_pal_tv_bram_top;

architecture sim of tb_pal_tv_bram_top is

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  -- UUT0: sel=0 vertical bars
  signal dac0 : std_logic_vector(3 downto 0);
  signal cs0, fld0, ac0 : std_logic;

  -- UUT1: sel=4 BRAM
  signal dac1 : std_logic_vector(3 downto 0);
  signal cs1, fld1, ac1 : std_logic;

  -- Shared BRAM write bus (drives uut1 only)
  signal bram_wr_en   : std_logic                     := '0';
  signal bram_wr_addr : std_logic_vector(18 downto 0) := (others => '0');
  signal bram_wr_data : std_logic                     := '0';
  signal bram_len     : std_logic_vector(18 downto 0) := (others => '0');

  constant CLK_PERIOD : time    := 100 ns;
  constant H_TOTAL    : integer := 640;
  constant V_TOTAL    : integer := 625;
  constant STRIPE_W   : integer := 4;
  constant ZONE_W     : integer := 65;
  constant NUM_ZONES  : integer := 8;

  -- Use a small BRAM_DEPTH in simulation to keep elaboration fast
  constant SIM_DEPTH  : integer := 1040;   -- two lines (2 * 520)

  constant BLANK : std_logic_vector(3 downto 0) := "0100";
  constant WHITE : std_logic_vector(3 downto 0) := "1111";

  type zone_kind    is (Z_BLACK, Z_WHITE, Z_STRIPE);
  type zone_table_t is array (0 to NUM_ZONES - 1) of zone_kind;
  constant ZONE_TABLE : zone_table_t := (
    0 => Z_STRIPE, 1 => Z_WHITE,  2 => Z_STRIPE, 3 => Z_WHITE,
    4 => Z_BLACK,  5 => Z_STRIPE, 6 => Z_WHITE,  7 => Z_STRIPE
  );

  function bar_color(z : integer; local : integer)
      return std_logic_vector is
  begin
    case ZONE_TABLE(z) is
      when Z_BLACK  => return BLANK;
      when Z_WHITE  => return WHITE;
      when Z_STRIPE =>
        if (local / STRIPE_W) mod 2 = 0 then return BLANK; else return WHITE; end if;
    end case;
  end function;

begin

  clk <= not clk after CLK_PERIOD / 2;

  -- sel=0: vertical bars, default brightness/black_lvl
  uut0 : entity work.pal_tv_bram_top
    generic map (CLK_MHZ => 10, STRIPE_W => STRIPE_W, BRAM_DEPTH => SIM_DEPTH)
    port map (clk => clk, rst => rst, sel => x"00",
              dac_out => dac0, hsync_o => cs0, vsync_o => fld0,
              active_o => ac0, blank_o => open);

  -- sel=4: BRAM source
  uut1 : entity work.pal_tv_bram_top
    generic map (CLK_MHZ => 10, STRIPE_W => STRIPE_W, BRAM_DEPTH => SIM_DEPTH)
    port map (clk => clk, rst => rst, sel => x"04",
              bram_wr_en   => bram_wr_en,
              bram_wr_addr => bram_wr_addr,
              bram_wr_data => bram_wr_data,
              bram_len     => bram_len,
              dac_out => dac1, hsync_o => cs1, vsync_o => fld1,
              active_o => ac1, blank_o => open);

  -- -----------------------------------------------------------------------
  -- Clock / reset / BRAM initialisation / sim end
  --
  -- BRAM is loaded during reset:
  --   pixel i = (i mod 2)   →  even addresses = '0' (black), odd = '1' (white)
  --   bram_len = 520  (one line; wraps every active line)
  -- -----------------------------------------------------------------------
  process
  begin
    rst <= '1';
    -- Set length before (or during) reset so it is stable on release
    bram_len <= std_logic_vector(to_unsigned(520, 19));

    -- Write 520-pixel alternating pattern while reset is held
    bram_wr_en <= '1';
    for i in 0 to 519 loop
      bram_wr_addr <= std_logic_vector(to_unsigned(i, 19));
      if i mod 2 = 0 then bram_wr_data <= '0'; else bram_wr_data <= '1'; end if;
      wait until rising_edge(clk);
    end loop;
    bram_wr_en <= '0';

    wait for 5 * CLK_PERIOD;
    rst <= '0';

    wait for (V_TOTAL + 100) * H_TOTAL * CLK_PERIOD;
    report "=== Simulation complete ===" severity note;
    std.env.finish;
  end process;

  -- -----------------------------------------------------------------------
  -- Checker 1: sel=0 vertical bars (Field-1, first active line)
  -- -----------------------------------------------------------------------
  process
    variable px  : integer;
    variable exp : std_logic_vector(3 downto 0);
  begin
    wait until rst = '0';
    wait until rising_edge(ac0);
    px := 0;
    loop
      wait until falling_edge(clk);
      exit when ac0 = '0';
      exp := bar_color(px / ZONE_W, px mod ZONE_W);
      assert dac0 = exp
        report "FAIL Vbar px="&integer'image(px)&
               " exp="&integer'image(to_integer(unsigned(exp)))&
               " got="&integer'image(to_integer(unsigned(dac0))) severity error;
      px := px + 1;
    end loop;
    assert px = 520
      report "FAIL Vbar count="&integer'image(px)&" (want 520)" severity error;
    report "=== sel=0 vertical bars PASSED ("&integer'image(px)&" px) ===" severity note;
    wait;
  end process;

  -- -----------------------------------------------------------------------
  -- Checker 2: sel=4 BRAM  -- Field-1 first active line
  --   Expected: pixel 0 = BLANK, pixel 1 = WHITE, alternating, 520 pixels
  -- -----------------------------------------------------------------------
  process
    variable px  : integer;
    variable exp : std_logic_vector(3 downto 0);
  begin
    wait until rst = '0';
    wait until rising_edge(ac1);    -- first active line of field 1
    px := 0;
    loop
      wait until falling_edge(clk);
      exit when ac1 = '0';
      if px mod 2 = 0 then exp := BLANK; else exp := WHITE; end if;
      assert dac1 = exp
        report "FAIL BRAM F1 px="&integer'image(px)&
               " exp="&integer'image(to_integer(unsigned(exp)))&
               " got="&integer'image(to_integer(unsigned(dac1))) severity error;
      px := px + 1;
    end loop;
    assert px = 520
      report "FAIL BRAM F1 count="&integer'image(px)&" (want 520)" severity error;
    report "=== sel=4 BRAM Field-1 line PASSED ("&integer'image(px)&" px) ===" severity note;
    wait;
  end process;

  -- -----------------------------------------------------------------------
  -- Checker 3: sel=4 BRAM  -- Field-1 second active line (wrap verification)
  --   bram_len=520 → address resets to 0; same pattern must repeat
  -- -----------------------------------------------------------------------
  process
    variable px  : integer;
    variable exp : std_logic_vector(3 downto 0);
  begin
    wait until rst = '0';
    wait until rising_edge(ac1);    -- first line (consume it)
    wait until falling_edge(ac1);   -- end of first line
    wait until rising_edge(ac1);    -- second active line
    px := 0;
    loop
      wait until falling_edge(clk);
      exit when ac1 = '0';
      if px mod 2 = 0 then exp := BLANK; else exp := WHITE; end if;
      assert dac1 = exp
        report "FAIL BRAM wrap px="&integer'image(px)&
               " exp="&integer'image(to_integer(unsigned(exp)))&
               " got="&integer'image(to_integer(unsigned(dac1))) severity error;
      px := px + 1;
    end loop;
    assert px = 520
      report "FAIL BRAM wrap count="&integer'image(px)&" (want 520)" severity error;
    report "=== sel=4 BRAM wrap (line 2) PASSED ("&integer'image(px)&" px) ===" severity note;
    wait;
  end process;

end architecture sim;
