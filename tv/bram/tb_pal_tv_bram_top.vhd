library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Testbench for pal_tv_bram_top -- 520 x 576 natural sequential row test
--
-- BRAM address layout (sel = 4, bram_len = 299520, natural row order):
--   addr       0 ..   519   image row 0  (F1 line 0, screen row 0)
--   addr     520 ..  1039   image row 1  (F2 line 0, screen row 1)
--   addr    1040 ..  1559   image row 2  (F1 line 1, screen row 2)
--   ...
--   addr 299000 .. 299519   image row 575 (F2 line 287)
--
-- Marker pixels written (rest stay '0' = BLANK):
--   addr    0 = '1'  -> F1 line 0 px   0 = WHITE
--   addr 1039 = '1'  -> F2 line 0 px 519 = WHITE  (unique F2 end marker)
--
-- Checks:
--   1. sel=0 vertical bars (baseline)
--   2. sel=4 F1 line 0:  px 0 = WHITE, px 1..519 = BLANK
--   3. sel=4 F2 line 0:  px 0 = BLANK, px 1..518 = BLANK, px 519 = WHITE
--        px 0 = BLANK PROVES counter did NOT reset (addr 0 = '1' would give WHITE)
--        px 519 = WHITE PROVES F2 reads addr 1039 (not addr 519 which is '0')
entity tb_pal_tv_bram_top is
end entity tb_pal_tv_bram_top;

architecture sim of tb_pal_tv_bram_top is

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  -- UUT0: sel=0 vertical bars (small BRAM for speed)
  signal dac0 : std_logic_vector(3 downto 0);
  signal cs0, fld0, ac0 : std_logic;

  -- UUT1: sel=4 full 520x576 unique frame (BRAM_DEPTH = 299520)
  signal dac1 : std_logic_vector(3 downto 0);
  signal cs1, fld1, ac1 : std_logic;

  -- BRAM write bus (drives uut1)
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

  -- Full interlaced frame: 520 active pixels * 576 active lines
  constant H_ACTIVE      : integer := 520;
  constant F1_LINES      : integer := 288;   -- lines per field
  constant FRAME_PX      : integer := H_ACTIVE * F1_LINES * 2;   -- 299 520
  -- Natural sequential layout: row-pair stride = 2 * H_ACTIVE = 1040
  --   F2 line 0 = image row 1 → addr H_ACTIVE..2*H_ACTIVE-1 = 520..1039
  constant F2_ROW0_END   : integer := 2 * H_ACTIVE - 1;           -- 1039

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

  -- sel=0 vertical bars; small BRAM to keep elaboration fast
  uut0 : entity work.pal_tv_bram_top
    generic map (CLK_MHZ => 10, STRIPE_W => STRIPE_W, BRAM_DEPTH => 1040)
    port map (clk => clk, rst => rst, sel => x"00",
              dac_out => dac0, csync_o => cs0, line_sync_o => open,
              frame_sync_o => open, field_o => fld0,
              active_o => ac0, blank_o => open);

  -- sel=4 full 520x576 unique-pixel BRAM
  uut1 : entity work.pal_tv_bram_top
    generic map (CLK_MHZ => 10, STRIPE_W => STRIPE_W, BRAM_DEPTH => FRAME_PX)
    port map (clk => clk, rst => rst, sel => x"04",
              bram_wr_en   => bram_wr_en,
              bram_wr_addr => bram_wr_addr,
              bram_wr_data => bram_wr_data,
              bram_len     => bram_len,
              dac_out => dac1, csync_o => cs1, line_sync_o => open,
              frame_sync_o => open, field_o => fld1,
              active_o => ac1, blank_o => open);

  -- -----------------------------------------------------------------------
  -- Clock / reset / BRAM write / simulation end
  --
  -- Marker pixels written to uut1 BRAM (natural sequential row layout):
  --   addr    0 = '1'  -> image row 0 px   0 -> F1 line 0 first pixel = WHITE
  --   addr 1039 = '1'  -> image row 1 px 519 -> F2 line 0 last  pixel = WHITE
  --                        (addr 519 intentionally '0' so F2 px0=BLANK proves
  --                         F2 did NOT wrap back to addr 0)
  -- bram_len = 299520 (full frame, no premature wrap)
  -- -----------------------------------------------------------------------
  process
  begin
    rst <= '1';
    bram_len <= std_logic_vector(to_unsigned(FRAME_PX, 19));

    -- Write marker pixels while reset is held
    wait until rising_edge(clk);

    bram_wr_addr <= std_logic_vector(to_unsigned(0, 19));          -- row 0 px 0
    bram_wr_data <= '1'; bram_wr_en <= '1';
    wait until rising_edge(clk); bram_wr_en <= '0';

    bram_wr_addr <= std_logic_vector(to_unsigned(F2_ROW0_END, 19)); -- row 1 px 519 = addr 1039
    bram_wr_data <= '1'; bram_wr_en <= '1';
    wait until rising_edge(clk); bram_wr_en <= '0';

    wait for 5 * CLK_PERIOD;
    rst <= '0';

    -- Run long enough to see both fields (just over one full frame)
    wait for (V_TOTAL + 100) * H_TOTAL * CLK_PERIOD;
    report "=== Simulation complete ===" severity note;
    std.env.finish;
  end process;

  -- -----------------------------------------------------------------------
  -- Checker 1: sel=0 vertical bars (F1 first active line)
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
  -- Checker 2: sel=4 BRAM -- Field-1 line 0 (image row 0, addr 0..519)
  --   px 0     -> addr   0 = '1' -> WHITE
  --   px 1..519 -> addr 1..519 = '0' -> BLANK
  -- -----------------------------------------------------------------------
  process
    variable px  : integer;
    variable exp : std_logic_vector(3 downto 0);
  begin
    wait until rst = '0';
    wait until rising_edge(ac1);    -- F1 first active line
    px := 0;
    loop
      wait until falling_edge(clk);
      exit when ac1 = '0';
      if px = 0 then exp := WHITE; else exp := BLANK; end if;
      assert dac1 = exp
        report "FAIL BRAM F1-L0 px="&integer'image(px)&
               " exp="&integer'image(to_integer(unsigned(exp)))&
               " got="&integer'image(to_integer(unsigned(dac1))) severity error;
      px := px + 1;
    end loop;
    assert px = 520
      report "FAIL BRAM F1-L0 count="&integer'image(px)&" (want 520)" severity error;
    report "=== BRAM F1 line 0 (image row 0, addr 0..519) PASSED ===" severity note;
    wait;
  end process;

  -- -----------------------------------------------------------------------
  -- Checker 3: sel=4 BRAM -- Field-2 line 0 (image row 1, addr 520..1039)
  --
  --   px 0     -> addr  520 = '0' -> BLANK
  --   px 1..518 -> addr 521..1038 = '0' -> BLANK
  --   px 519   -> addr 1039 = '1' -> WHITE  (unique F2 end marker)
  --
  --   Two-way proof of correct natural-sequential addressing:
  --     px 0 = BLANK  -> counter did NOT reset to 0 (addr 0 = '1' → would be WHITE)
  --     px519 = WHITE -> F2 read addr 1039 (if wrong reset: reads addr 519='0'→BLANK FAIL)
  -- -----------------------------------------------------------------------
  process
    variable px  : integer;
    variable exp : std_logic_vector(3 downto 0);
  begin
    wait until rst = '0';
    wait until rising_edge(fld1);   -- field indicator goes '1' = F2 starts
    wait until rising_edge(ac1);    -- first active line of F2
    px := 0;
    loop
      wait until falling_edge(clk);
      exit when ac1 = '0';
      if px = 519 then exp := WHITE; else exp := BLANK; end if;
      assert dac1 = exp
        report "FAIL BRAM F2-L0 px="&integer'image(px)&
               " exp="&integer'image(to_integer(unsigned(exp)))&
               " got="&integer'image(to_integer(unsigned(dac1))) severity error;
      px := px + 1;
    end loop;
    assert px = 520
      report "FAIL BRAM F2-L0 count="&integer'image(px)&" (want 520)" severity error;
    report "=== BRAM F2 line 0 (image row 1, addr 520..1039) PASSED ===" severity note;
    report "    (px0=BLANK + px519=WHITE proves natural sequential row addressing)" severity note;
    wait;
  end process;

end architecture sim;
