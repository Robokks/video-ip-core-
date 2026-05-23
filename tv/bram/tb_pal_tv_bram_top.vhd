library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Testbench for pal_tv_bram_top -- 520 x 576 unique-pixel interlaced test
--
-- BRAM address layout (sel = 4, bram_len = 299520):
--   addr 0         : F1 line 0 first pixel
--   addr 519       : F1 line 0 last pixel
--   addr 149759    : F1 line 287 last pixel  (288 * 520 - 1)
--   addr 149760    : F2 line 0 first pixel   (288 * 520)
--   addr 299519    : F2 line 287 last pixel  (576 * 520 - 1)
--
-- Checks:
--   1. sel=0 vertical bars (baseline)
--   2. sel=4 F1 line 0:  px 0 = WHITE, px 1..518 = BLANK, px 519 = WHITE
--   3. sel=4 F2 line 0:  px 0 = WHITE, px 1..519 = BLANK
--        Checker 3 PROVES field 2 reads from addr 149760 (not 0):
--        if the counter incorrectly reset, px 0 would be WHITE from addr 0 too,
--        but px 1 would be BLANK -- same as checker 2 and undetectable.
--        Therefore we also verify that addr 519 was NOT re-read (WHITE) at F2 px 519.
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
  constant H_ACTIVE   : integer := 520;
  constant F1_LINES   : integer := 288;   -- lines per field
  constant FRAME_PX   : integer := H_ACTIVE * F1_LINES * 2;   -- 299 520
  constant F2_START   : integer := H_ACTIVE * F1_LINES;        -- 149 760

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
              dac_out => dac0, hsync_o => cs0, vsync_o => fld0,
              active_o => ac0, blank_o => open);

  -- sel=4 full 520x576 unique-pixel BRAM
  uut1 : entity work.pal_tv_bram_top
    generic map (CLK_MHZ => 10, STRIPE_W => STRIPE_W, BRAM_DEPTH => FRAME_PX)
    port map (clk => clk, rst => rst, sel => x"04",
              bram_wr_en   => bram_wr_en,
              bram_wr_addr => bram_wr_addr,
              bram_wr_data => bram_wr_data,
              bram_len     => bram_len,
              dac_out => dac1, hsync_o => cs1, vsync_o => fld1,
              active_o => ac1, blank_o => open);

  -- -----------------------------------------------------------------------
  -- Clock / reset / BRAM write / simulation end
  --
  -- Marker pixels written to uut1 BRAM (rest stay '0' = black by default):
  --   addr 0       = '1'  -> F1 line 0 first pixel  = WHITE
  --   addr 519     = '1'  -> F1 line 0 last pixel   = WHITE
  --   addr 149760  = '1'  -> F2 line 0 first pixel  = WHITE
  --                          (if counter wrongly reset to 0, this would be wrong)
  -- bram_len = 299520 (full frame, no premature wrap)
  -- -----------------------------------------------------------------------
  process
  begin
    rst <= '1';
    bram_len <= std_logic_vector(to_unsigned(FRAME_PX, 19));

    -- Write marker pixels while reset is held
    wait until rising_edge(clk);

    bram_wr_addr <= std_logic_vector(to_unsigned(0, 19));
    bram_wr_data <= '1'; bram_wr_en <= '1';
    wait until rising_edge(clk); bram_wr_en <= '0';

    bram_wr_addr <= std_logic_vector(to_unsigned(519, 19));
    bram_wr_data <= '1'; bram_wr_en <= '1';
    wait until rising_edge(clk); bram_wr_en <= '0';

    bram_wr_addr <= std_logic_vector(to_unsigned(F2_START, 19));  -- 149760
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
  -- Checker 2: sel=4 BRAM -- Field-1 line 0 (addr 0..519)
  --   px 0   -> addr   0  = '1' -> WHITE
  --   px 1..518 -> addr 1..518 = '0' -> BLANK
  --   px 519  -> addr 519  = '1' -> WHITE
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
      if px = 0 or px = 519 then exp := WHITE; else exp := BLANK; end if;
      assert dac1 = exp
        report "FAIL BRAM F1-L0 px="&integer'image(px)&
               " exp="&integer'image(to_integer(unsigned(exp)))&
               " got="&integer'image(to_integer(unsigned(dac1))) severity error;
      px := px + 1;
    end loop;
    assert px = 520
      report "FAIL BRAM F1-L0 count="&integer'image(px)&" (want 520)" severity error;
    report "=== BRAM F1 line 0 (addr 0..519) PASSED ===" severity note;
    wait;
  end process;

  -- -----------------------------------------------------------------------
  -- Checker 3: sel=4 BRAM -- Field-2 line 0 (addr 149760..150279)
  --
  --   px 0   -> addr 149760 = '1' -> WHITE   (unique F2 marker)
  --   px 1..519 -> addr 149761..150279 = '0' -> BLANK
  --
  --   If the counter incorrectly resets to 0 at the F1/F2 boundary:
  --     px 0  would read addr 0 = '1' -> WHITE  (looks same -- see px 519 below)
  --     px 519 would read addr 519 = '1' -> WHITE  <- WOULD FAIL as expected BLANK
  --   So the px 519 = BLANK assertion is the definitive proof.
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
      if px = 0 then exp := WHITE; else exp := BLANK; end if;
      assert dac1 = exp
        report "FAIL BRAM F2-L0 px="&integer'image(px)&
               " exp="&integer'image(to_integer(unsigned(exp)))&
               " got="&integer'image(to_integer(unsigned(dac1))) severity error;
      px := px + 1;
    end loop;
    assert px = 520
      report "FAIL BRAM F2-L0 count="&integer'image(px)&" (want 520)" severity error;
    report "=== BRAM F2 line 0 (addr 149760..150279) PASSED ===" severity note;
    report "    (px519=BLANK proves addr did NOT reset to 0 at field boundary)" severity note;
    wait;
  end process;

end architecture sim;
