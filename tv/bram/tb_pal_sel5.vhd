library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Testbench for pal_tv_bram_top  sel = 5  (bouncing ball, interlaced PAL)
--
-- Ball initial state: ball_x=0, ball_y=0, BALL_W=60, BALL_H=50, ball_vx=3, ball_vy=2
--
-- Checker 1 – F1 frame 0, line 0  (screen_y = 0)
--   screen_y=0 is in [0,50)  and  screen_x ∈ [0,60)  → WHITE
--   px   0.. 59  = WHITE (ball)
--   px  60..519  = BLACK
--
-- Checker 2 – F2 frame 0, line 0  (screen_y = 1)
--   screen_y=1 is in [0,50) → same WHITE/BLACK split at x=60
--
-- Checker 3 – F1 frame 1, line 0  (screen_y = 0)
--   After frame 0: ball_x=3, ball_y=2.  screen_y=0 < ball_y=2 → ball_on='0'
--   Expected: ALL 520 pixels BLACK
--
-- Checker 4 – F1 frame 1, line 1  (screen_y = 2)
--   screen_y=2 ∈ [2,52) → ball_on='1' for screen_x ∈ [3,63)
--   px  0.. 2   = BLACK
--   px  3..62   = WHITE
--   px 63..519  = BLACK
entity tb_pal_sel5 is
end entity tb_pal_sel5;

architecture sim of tb_pal_sel5 is

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';
  signal dac : std_logic_vector(3 downto 0);
  signal ac  : std_logic;
  signal fld : std_logic;

  constant CLK_PERIOD : time    := 100 ns;   -- 10 MHz
  constant H_TOTAL    : integer := 640;
  constant V_TOTAL    : integer := 625;
  constant H_ACTIVE   : integer := 520;
  constant BALL_W     : integer := 60;
  constant BALL_H     : integer := 50;

  constant BLANK : std_logic_vector(3 downto 0) := "0100";
  constant WHITE : std_logic_vector(3 downto 0) := "1111";

begin

  clk <= not clk after CLK_PERIOD / 2;

  uut : entity work.pal_tv_bram_top
    generic map (CLK_MHZ => 10, BRAM_DEPTH => 1040)
    port map (
      clk      => clk,
      rst      => rst,
      sel      => x"05",
      dac_out  => dac,
      hsync_o  => open,
      vsync_o  => fld,
      active_o => ac,
      blank_o  => open
    );

  -- -----------------------------------------------------------------------
  -- Reset and simulation control
  -- -----------------------------------------------------------------------
  process
  begin
    rst <= '1';
    wait for 5 * CLK_PERIOD;
    rst <= '0';
    -- Run two full frames (F1+F2 each = 625 lines) + margin
    wait for 2 * V_TOTAL * H_TOTAL * CLK_PERIOD;
    report "=== tb_pal_sel5 simulation complete ===" severity note;
    std.env.finish;
  end process;

  -- -----------------------------------------------------------------------
  -- Helper: wait for the rising edge of ac, then sample all 520 pixels
  -- on falling edges while ac='1', return pixel count.
  -- Asserts each pixel against expected WHITE/BLACK.
  -- label is just used in messages.
  -- -----------------------------------------------------------------------

  -- -----------------------------------------------------------------------
  -- Checker 1 – F1 frame 0, line 0  (screen_y=0)
  --   px 0..59 = WHITE, px 60..519 = BLACK
  -- -----------------------------------------------------------------------
  process
    variable px  : integer;
    variable exp : std_logic_vector(3 downto 0);
  begin
    wait until rst = '0';
    wait until rising_edge(ac);          -- first active line (F1 line 0)
    px := 0;
    loop
      wait until falling_edge(clk);
      exit when ac = '0';
      if px < BALL_W then exp := WHITE; else exp := BLANK; end if;
      assert dac = exp
        report "FAIL [Chk1 F1-L0] px=" & integer'image(px) &
               " exp=" & integer'image(to_integer(unsigned(exp))) &
               " got=" & integer'image(to_integer(unsigned(dac)))
        severity error;
      px := px + 1;
    end loop;
    assert px = H_ACTIVE
      report "FAIL [Chk1] pixel count=" & integer'image(px) & " want 520"
      severity error;
    report "=== Chk1 PASS: F1 frame-0 line-0 (screen_y=0)  px0-59=WHITE  px60-519=BLACK ===" severity note;
    wait;
  end process;

  -- -----------------------------------------------------------------------
  -- Checker 2 – F2 frame 0, line 0  (screen_y=1)
  --   px 0..59 = WHITE (1 < 50), px 60..519 = BLACK
  -- -----------------------------------------------------------------------
  process
    variable px  : integer;
    variable exp : std_logic_vector(3 downto 0);
  begin
    wait until rst = '0';
    wait until rising_edge(fld);         -- fld='1' marks F2 field
    wait until rising_edge(ac);          -- first active line of F2
    px := 0;
    loop
      wait until falling_edge(clk);
      exit when ac = '0';
      if px < BALL_W then exp := WHITE; else exp := BLANK; end if;
      assert dac = exp
        report "FAIL [Chk2 F2-L0] px=" & integer'image(px) &
               " exp=" & integer'image(to_integer(unsigned(exp))) &
               " got=" & integer'image(to_integer(unsigned(dac)))
        severity error;
      px := px + 1;
    end loop;
    assert px = H_ACTIVE
      report "FAIL [Chk2] pixel count=" & integer'image(px) & " want 520"
      severity error;
    report "=== Chk2 PASS: F2 frame-0 line-0 (screen_y=1)  px0-59=WHITE  px60-519=BLACK ===" severity note;
    wait;
  end process;

  -- -----------------------------------------------------------------------
  -- Checker 3 – F1 frame 1, line 0  (screen_y=0)
  --   After frame 0 update: ball_x=3, ball_y=2.
  --   screen_y=0 < ball_y=2  →  ball_on='0'  →  ALL BLACK
  -- -----------------------------------------------------------------------
  process
    variable px  : integer;
  begin
    wait until rst = '0';
    -- Skip frame 0 (F1+F2)
    wait until rising_edge(fld);         -- F2 of frame 0 starts
    wait until fld = '0';               -- F2 ends, back to F1 (frame 1)
    wait until rising_edge(ac);          -- F1 frame 1, line 0 (screen_y=0)
    px := 0;
    loop
      wait until falling_edge(clk);
      exit when ac = '0';
      assert dac = BLANK
        report "FAIL [Chk3 F1-1-L0] px=" & integer'image(px) &
               " exp=BLANK got=" & integer'image(to_integer(unsigned(dac)))
        severity error;
      px := px + 1;
    end loop;
    assert px = H_ACTIVE
      report "FAIL [Chk3] pixel count=" & integer'image(px) & " want 520"
      severity error;
    report "=== Chk3 PASS: F1 frame-1 line-0 (screen_y=0)  all BLACK (ball_y=2) ===" severity note;
    wait;
  end process;

  -- -----------------------------------------------------------------------
  -- Checker 4 – F1 frame 1, line 1  (screen_y=2)
  --   ball_x=3, ball_y=2: screen_y=2 in [2,52) → ball_on for x in [3,63)
  --   px  0.. 2  = BLACK
  --   px  3..62  = WHITE
  --   px 63..519 = BLACK
  -- -----------------------------------------------------------------------
  process
    variable px  : integer;
    variable exp : std_logic_vector(3 downto 0);
  begin
    wait until rst = '0';
    -- Skip frame 0
    wait until rising_edge(fld);
    wait until fld = '0';
    -- Skip first line of F1 frame 1 (screen_y=0, already checked above)
    wait until rising_edge(ac); wait until ac = '0';
    -- Second active line: screen_y=2
    wait until rising_edge(ac);
    px := 0;
    loop
      wait until falling_edge(clk);
      exit when ac = '0';
      if px >= 3 and px < 3 + BALL_W then
        exp := WHITE;
      else
        exp := BLANK;
      end if;
      assert dac = exp
        report "FAIL [Chk4 F1-1-L1] px=" & integer'image(px) &
               " exp=" & integer'image(to_integer(unsigned(exp))) &
               " got=" & integer'image(to_integer(unsigned(dac)))
        severity error;
      px := px + 1;
    end loop;
    assert px = H_ACTIVE
      report "FAIL [Chk4] pixel count=" & integer'image(px) & " want 520"
      severity error;
    report "=== Chk4 PASS: F1 frame-1 line-1 (screen_y=2)  px3-62=WHITE ===" severity note;
    wait;
  end process;

end architecture sim;
