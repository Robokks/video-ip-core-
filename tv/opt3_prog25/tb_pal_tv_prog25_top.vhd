library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Testbench for pal_tv_prog25_top (25 Hz progressive, reference design).
-- Checks all four patterns.  Same structure as tb_pal_tv_crt50_top but
-- with V_ACTIVE_L=576 geometry.
entity tb_pal_tv_prog25_top is
end entity tb_pal_tv_prog25_top;

architecture sim of tb_pal_tv_prog25_top is

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  signal dac0, dac1, dac2, dac3 : std_logic_vector(3 downto 0);
  signal dac4                    : std_logic_vector(3 downto 0);
  signal hs0, vs0, ac0           : std_logic;
  signal hs1, vs1, ac1           : std_logic;
  signal hs2, vs2, ac2           : std_logic;
  signal hs3, vs3, ac3           : std_logic;
  signal hs4, vs4, ac4           : std_logic;

  constant CLK_PERIOD : time := 100 ns;

  constant NUM_ZONES : integer := 8;
  constant ZONE_W    : integer := 65;
  constant ZONE_H    : integer := 72;
  constant STRIPE_W  : integer := 4;
  constant GZONES    : integer := 10;
  constant GZONE_W   : integer := 52;
  constant GZONE_H   : integer := 57;
  constant NLINES    : integer := 150;

  constant BLACK : std_logic_vector(3 downto 0) := "0100";
  constant WHITE : std_logic_vector(3 downto 0) := "1111";

  type zone_kind    is (Z_BLACK, Z_WHITE, Z_STRIPE);
  type zone_table_t is array (0 to NUM_ZONES - 1) of zone_kind;
  constant ZONE_TABLE : zone_table_t := (
    0 => Z_STRIPE, 1 => Z_WHITE,  2 => Z_STRIPE, 3 => Z_WHITE,
    4 => Z_BLACK,  5 => Z_STRIPE, 6 => Z_WHITE,  7 => Z_STRIPE
  );

  type grad_table_t is array (0 to GZONES - 1) of std_logic_vector(3 downto 0);
  constant GRAD_TABLE : grad_table_t := (
    0 => "0100", 1 => "0101", 2 => "0110", 3 => "1000", 4 => "1001",
    5 => "1010", 6 => "1011", 7 => "1101", 8 => "1110", 9 => "1111"
  );

  function bar_color(z : integer; local : integer) return std_logic_vector is
  begin
    case ZONE_TABLE(z) is
      when Z_BLACK  => return BLACK;
      when Z_WHITE  => return WHITE;
      when Z_STRIPE =>
        if (local / STRIPE_W) mod 2 = 0 then return BLACK; else return WHITE; end if;
    end case;
  end function;

  function grad_idx(pos : integer; zsize : integer) return integer is
    variable z : integer;
  begin
    z := pos / zsize;
    if z > GZONES - 1 then z := GZONES - 1; end if;
    return z;
  end function;

begin

  clk <= not clk after CLK_PERIOD / 2;

  uut0 : entity work.pal_tv_prog25_top
    generic map (CLK_MHZ => 10, STRIPE_W => STRIPE_W)
    port map (clk=>clk, rst=>rst, sel=>x"00",
              dac_out=>dac0, hsync_o=>hs0, vsync_o=>vs0, active_o=>ac0, blank_o=>open);
  uut1 : entity work.pal_tv_prog25_top
    generic map (CLK_MHZ => 10, STRIPE_W => STRIPE_W)
    port map (clk=>clk, rst=>rst, sel=>x"01",
              dac_out=>dac1, hsync_o=>hs1, vsync_o=>vs1, active_o=>ac1, blank_o=>open);
  uut2 : entity work.pal_tv_prog25_top
    generic map (CLK_MHZ => 10, STRIPE_W => STRIPE_W)
    port map (clk=>clk, rst=>rst, sel=>x"02",
              dac_out=>dac2, hsync_o=>hs2, vsync_o=>vs2, active_o=>ac2, blank_o=>open);
  uut3 : entity work.pal_tv_prog25_top
    generic map (CLK_MHZ => 10, STRIPE_W => STRIPE_W)
    port map (clk=>clk, rst=>rst, sel=>x"03",
              dac_out=>dac3, hsync_o=>hs3, vsync_o=>vs3, active_o=>ac3, blank_o=>open);
  uut4 : entity work.pal_tv_prog25_top
    generic map (CLK_MHZ => 10, STRIPE_W => STRIPE_W)
    port map (clk=>clk, rst=>rst, sel=>x"00", brightness=>x"6",
              dac_out=>dac4, hsync_o=>hs4, vsync_o=>vs4, active_o=>ac4, blank_o=>open);

  process
  begin
    rst <= '1';
    wait for 5 * CLK_PERIOD;
    rst <= '0';
    wait for 200 * 640 * CLK_PERIOD;
    report "=== Simulation complete ===" severity note;
    std.env.finish;
  end process;

  process(clk)
    procedure chk(signal d : std_logic_vector(3 downto 0);
                  signal hs, vs, ac : std_logic; tag : string) is
    begin
      if hs = '1' or vs = '1' then
        assert d = "0000" report "FAIL "&tag&": sync level" severity error;
      end if;
      if ac = '0' and hs = '0' and vs = '0' then
        assert d = "0100" report "FAIL "&tag&": blank level" severity error;
      end if;
    end procedure;
  begin
    if rising_edge(clk) and rst = '0' then
      chk(dac0, hs0, vs0, ac0, "0");
      chk(dac1, hs1, vs1, ac1, "1");
      chk(dac2, hs2, vs2, ac2, "2");
      chk(dac3, hs3, vs3, ac3, "3");
    end if;
  end process;

  process
    variable px : integer; variable exp : std_logic_vector(3 downto 0);
  begin
    wait until rst = '0';
    wait until rising_edge(ac0);
    px := 0;
    loop
      wait until falling_edge(clk);
      exit when ac0 = '0';
      exp := bar_color(px / ZONE_W, px mod ZONE_W);
      assert dac0 = exp report "FAIL Vbar px="&integer'image(px)&
        " exp="&integer'image(to_integer(unsigned(exp)))&
        " got="&integer'image(to_integer(unsigned(dac0))) severity error;
      px := px + 1;
    end loop;
    assert px = 520 report "FAIL Vbar px count="&integer'image(px) severity error;
    report "=== VERTICAL bars PASSED ("&integer'image(px)&" px) ===" severity note;
    wait;
  end process;

  process
    variable exp : std_logic_vector(3 downto 0);
  begin
    wait until rst = '0';
    wait until falling_edge(vs1);
    for ln in 0 to NLINES - 1 loop
      wait until rising_edge(ac1);
      wait until falling_edge(clk);
      exp := bar_color(ln / ZONE_H, ln mod ZONE_H);
      assert dac1 = exp report "FAIL Hbar line="&integer'image(ln)&
        " exp="&integer'image(to_integer(unsigned(exp)))&
        " got="&integer'image(to_integer(unsigned(dac1))) severity error;
    end loop;
    report "=== HORIZONTAL bars PASSED ("&integer'image(NLINES)&" lines) ===" severity note;
    wait;
  end process;

  process
    variable px : integer; variable exp : std_logic_vector(3 downto 0);
  begin
    wait until rst = '0';
    wait until rising_edge(ac2);
    px := 0;
    loop
      wait until falling_edge(clk);
      exit when ac2 = '0';
      exp := GRAD_TABLE(grad_idx(px, GZONE_W));
      assert dac2 = exp report "FAIL Hgrad px="&integer'image(px)&
        " exp="&integer'image(to_integer(unsigned(exp)))&
        " got="&integer'image(to_integer(unsigned(dac2))) severity error;
      px := px + 1;
    end loop;
    assert px = 520 report "FAIL Hgrad px count="&integer'image(px) severity error;
    report "=== HORIZONTAL gradient PASSED ("&integer'image(px)&" px) ===" severity note;
    wait;
  end process;

  process
    variable exp : std_logic_vector(3 downto 0);
  begin
    wait until rst = '0';
    wait until falling_edge(vs3);
    for ln in 0 to NLINES - 1 loop
      wait until rising_edge(ac3);
      wait until falling_edge(clk);
      exp := GRAD_TABLE(grad_idx(ln, GZONE_H));
      assert dac3 = exp report "FAIL Vgrad line="&integer'image(ln)&
        " exp="&integer'image(to_integer(unsigned(exp)))&
        " got="&integer'image(to_integer(unsigned(dac3))) severity error;
    end loop;
    report "=== VERTICAL gradient PASSED ("&integer'image(NLINES)&" lines) ===" severity note;
    wait;
  end process;

  -- Checker: 20% contrast vertical bars
  process
    variable px  : integer;
    variable exp : std_logic_vector(3 downto 0);
  begin
    wait until rst = '0';
    wait until rising_edge(ac4);
    px := 0;
    loop
      wait until falling_edge(clk);
      exit when ac4 = '0';
      exp := bar_color(px / ZONE_W, px mod ZONE_W);
      if exp = WHITE then exp := x"6"; end if;
      assert dac4 = exp
        report "FAIL 20% Vbar px="&integer'image(px)&
               " exp="&integer'image(to_integer(unsigned(exp)))&
               " got="&integer'image(to_integer(unsigned(dac4))) severity error;
      px := px + 1;
    end loop;
    assert px = 520
      report "FAIL 20% Vbar count="&integer'image(px)&" (want 520)" severity error;
    report "=== 20% contrast vertical bars PASSED ("&integer'image(px)&" px) ===" severity note;
    wait;
  end process;

end architecture sim;
