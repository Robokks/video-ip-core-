library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Testbench for pal_tv_interlaced_top.
--
-- Checks:
--   1. Sync pulse shapes in field-1 vsync (event-based, immune to clock-delta
--      off-by-one issues):
--        a. Early eq pulse (h<23, v=0): dac = SYNC
--        b. Eq gap (h~29, v=0):         dac = BLANK
--        c. 2nd eq pulse (rising_edge cs0 at h=320, v=0): dac = SYNC
--        d. Broad sync  (rising_edge cs0 at h=320, v=2):  dac = SYNC
--        e. Broad notch (falling_edge cs0 at h=593, v=2): dac = BLANK
--   2. Field-1 active first line: pixel-exact VERTICAL bars (sel=0)
--   3. Field-2 active first line: same pixel-exact VERTICAL bars
entity tb_pal_tv_interlaced_top is
end entity tb_pal_tv_interlaced_top;

architecture sim of tb_pal_tv_interlaced_top is

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  signal dac0 : std_logic_vector(3 downto 0);
  signal cs0  : std_logic;   -- composite sync (hsync_o)
  signal fld0 : std_logic;   -- field indicator (vsync_o)
  signal ac0  : std_logic;
  signal dac1_lo : std_logic_vector(3 downto 0);
  signal cs1_lo  : std_logic;
  signal fld1_lo : std_logic;
  signal ac1_lo  : std_logic;

  constant CLK_PERIOD : time := 100 ns;

  constant H_TOTAL   : integer := 640;
  constant V_TOTAL   : integer := 625;
  constant STRIPE_W  : integer := 4;
  constant NUM_ZONES : integer := 8;
  constant ZONE_W    : integer := 65;

  constant BLANK : std_logic_vector(3 downto 0) := "0100";
  constant SYNC  : std_logic_vector(3 downto 0) := "0000";
  constant WHITE : std_logic_vector(3 downto 0) := "1111";

  type zone_kind    is (Z_BLACK, Z_WHITE, Z_STRIPE);
  type zone_table_t is array (0 to NUM_ZONES - 1) of zone_kind;
  constant ZONE_TABLE : zone_table_t := (
    0 => Z_STRIPE, 1 => Z_WHITE,  2 => Z_STRIPE, 3 => Z_WHITE,
    4 => Z_BLACK,  5 => Z_STRIPE, 6 => Z_WHITE,  7 => Z_STRIPE
  );

  function bar_color(z : integer; local : integer) return std_logic_vector is
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

  uut0 : entity work.pal_tv_interlaced_top
    generic map (CLK_MHZ => 10, STRIPE_W => STRIPE_W)
    port map (clk => clk, rst => rst, sel => x"00",
              dac_out => dac0, hsync_o => cs0, vsync_o => fld0, active_o => ac0,
              blank_o => open);
  uut1 : entity work.pal_tv_interlaced_top
    generic map (CLK_MHZ => 10, STRIPE_W => STRIPE_W)
    port map (clk => clk, rst => rst, sel => x"00", contrast => x"6",
              dac_out => dac1_lo, hsync_o => cs1_lo, vsync_o => fld1_lo, active_o => ac1_lo,
              blank_o => open);

  process
  begin
    rst <= '1';
    wait for 5 * CLK_PERIOD;
    rst <= '0';
    wait for (V_TOTAL + 100) * H_TOTAL * CLK_PERIOD;
    report "=== Simulation complete ===" severity note;
    std.env.finish;
  end process;

  -- -----------------------------------------------------------------------
  -- Checker 1: interlaced sync pulse shapes (event-based).
  --
  -- Anchor: falling_edge(fld0) = frame start (v=0, h=0).
  -- At h=0, v=0: pre-eq pulse is active, cs0='1'.
  --
  -- Rising edges of cs0 in vsync:
  --   #0 (initial):  h=0   v=0 (pre-eq start -- already '1' at frame start)
  --   #1: h=320 v=0  (2nd pre-eq half-line)
  --   #2: h=0   v=1  (3rd pre-eq half-line)
  --   #3: h=320 v=1  (4th pre-eq half-line)
  --   #4: h=0   v=2  (5th pre-eq half-line)
  --   #5: h=320 v=2  (1st broad-sync half-line)
  -- Falling edge of cs0 after #5: hp=273 at h=593, v=2 -> notch (BLANK).
  -- -----------------------------------------------------------------------
  process
  begin
    wait until rst = '0';
    -- Wait for frame boundary: fld0 '1'->'0' when v_cnt wraps 624->0
    wait until falling_edge(fld0);   -- now at v=0, h=0, cs0='1' (eq pulse)

    -- (a) Eq pulse: cs0='1' here, ~5 cycles in (hp=4 or 5)
    wait for 5 * CLK_PERIOD;
    assert dac0 = SYNC
      report "FAIL (a) eq pulse v=0 early: expected SYNC, got "&
             integer'image(to_integer(unsigned(dac0))) severity error;

    -- (b) Eq gap: 25 more cycles past the eq pulse boundary
    wait for 25 * CLK_PERIOD;
    assert dac0 = BLANK
      report "FAIL (b) eq gap v=0: expected BLANK, got "&
             integer'image(to_integer(unsigned(dac0))) severity error;

    -- (c) 2nd eq pulse: wait for cs0 to rise again (h=320, v=0)
    wait until rising_edge(cs0);
    assert dac0 = SYNC
      report "FAIL (c) 2nd eq pulse (v=0, h=320): expected SYNC, got "&
             integer'image(to_integer(unsigned(dac0))) severity error;

    -- (d) Broad sync start: 4 more rising edges reach v=2 h=320
    for i in 1 to 4 loop
      wait until rising_edge(cs0);
    end loop;
    assert dac0 = SYNC
      report "FAIL (d) broad sync start (v=2, h=320): expected SYNC, got "&
             integer'image(to_integer(unsigned(dac0))) severity error;

    -- (e) Broad notch: falling_edge of cs0 = hp reaches BROAD_W=273 at h=593
    wait until falling_edge(cs0);
    assert dac0 = BLANK
      report "FAIL (e) broad notch (v=2, h=593): expected BLANK, got "&
             integer'image(to_integer(unsigned(dac0))) severity error;

    report "=== Interlaced sync pulse shapes PASSED ===" severity note;
    wait;
  end process;

  -- -----------------------------------------------------------------------
  -- Checker 2: Field-1 active first line -- pixel-exact vertical bars
  -- -----------------------------------------------------------------------
  process
    variable px  : integer;
    variable exp : std_logic_vector(3 downto 0);
  begin
    wait until rst = '0';
    wait until rising_edge(ac0);   -- first active edge (field 1, v=24)
    px := 0;
    loop
      wait until falling_edge(clk);
      exit when ac0 = '0';
      exp := bar_color(px / ZONE_W, px mod ZONE_W);
      assert dac0 = exp
        report "FAIL F1 Vbar px="&integer'image(px)&
               " exp="&integer'image(to_integer(unsigned(exp)))&
               " got="&integer'image(to_integer(unsigned(dac0))) severity error;
      px := px + 1;
    end loop;
    assert px = 520
      report "FAIL F1 Vbar count="&integer'image(px)&" (want 520)" severity error;
    report "=== Field-1 vertical bars PASSED ("&integer'image(px)&" px) ===" severity note;
    wait;
  end process;

  -- -----------------------------------------------------------------------
  -- Checker 3: Field-2 active first line -- same pixel-exact vertical bars
  -- -----------------------------------------------------------------------
  process
    variable px  : integer;
    variable exp : std_logic_vector(3 downto 0);
  begin
    wait until rst = '0';
    wait until rising_edge(fld0);    -- field 2 begins (v=312, h=320)
    wait until rising_edge(ac0);     -- first active line of field 2 (v=336)
    px := 0;
    loop
      wait until falling_edge(clk);
      exit when ac0 = '0';
      exp := bar_color(px / ZONE_W, px mod ZONE_W);
      assert dac0 = exp
        report "FAIL F2 Vbar px="&integer'image(px)&
               " exp="&integer'image(to_integer(unsigned(exp)))&
               " got="&integer'image(to_integer(unsigned(dac0))) severity error;
      px := px + 1;
    end loop;
    assert px = 520
      report "FAIL F2 Vbar count="&integer'image(px)&" (want 520)" severity error;
    report "=== Field-2 vertical bars PASSED ("&integer'image(px)&" px) ===" severity note;
    wait;
  end process;

  -- Checker 4: 20% contrast Field-1 vertical bars
  process
    variable px  : integer;
    variable exp : std_logic_vector(3 downto 0);
  begin
    wait until rst = '0';
    wait until rising_edge(ac1_lo);
    px := 0;
    loop
      wait until falling_edge(clk);
      exit when ac1_lo = '0';
      exp := bar_color(px / ZONE_W, px mod ZONE_W);
      if exp = WHITE then exp := x"6"; end if;
      assert dac1_lo = exp
        report "FAIL 20% F1 Vbar px="&integer'image(px)&
               " exp="&integer'image(to_integer(unsigned(exp)))&
               " got="&integer'image(to_integer(unsigned(dac1_lo))) severity error;
      px := px + 1;
    end loop;
    assert px = 520
      report "FAIL 20% F1 Vbar count="&integer'image(px)&" (want 520)" severity error;
    report "=== 20% contrast Field-1 vertical bars PASSED ("&integer'image(px)&" px) ===" severity note;
    wait;
  end process;

end architecture sim;
