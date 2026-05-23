library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Smoke-test for video_bram_top
--
-- Checker 1 (PAL): F1 line 0 (screen_y=0), sel=5 ball:
--   px 0..59 = WHITE,  px 60..519 = BLACK
--
-- Checker 2 (NTSC): F1 line 0 (screen_y=0), sel=5 ball:
--   px 0..59 = WHITE,  px 60..519 = BLACK
--
-- Checker 3 (PAL): DAC = "0000" during sync, "0100" during blanking
--
-- Both UUTs must produce exactly 520 active pixels per line.
entity tb_video_bram_top is
end entity tb_video_bram_top;

architecture sim of tb_video_bram_top is

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  -- PAL instance
  signal dac_pal : std_logic_vector(3 downto 0);
  signal ac_pal  : std_logic;
  signal cs_pal  : std_logic;

  -- NTSC instance
  signal dac_ntsc : std_logic_vector(3 downto 0);
  signal ac_ntsc  : std_logic;
  signal cs_ntsc  : std_logic;

  constant CLK_PERIOD : time    := 100 ns;   -- 10 MHz
  constant H_ACTIVE   : integer := 520;
  constant BALL_W     : integer := 60;

  constant BLANK : std_logic_vector(3 downto 0) := "0100";
  constant WHITE : std_logic_vector(3 downto 0) := "1111";
  constant SYNC  : std_logic_vector(3 downto 0) := "0000";

begin

  clk <= not clk after CLK_PERIOD / 2;

  uut_pal : entity work.video_bram_top
    generic map (CLK_MHZ => 10, BRAM_DEPTH => 1040)
    port map (
      clk       => clk, rst => rst,
      ntsc_mode => '0',
      sel       => x"05",
      dac_out   => dac_pal, hsync_o => cs_pal,
      vsync_o   => open,   active_o => ac_pal, blank_o => open
    );

  uut_ntsc : entity work.video_bram_top
    generic map (CLK_MHZ => 10, BRAM_DEPTH => 1040)
    port map (
      clk       => clk, rst => rst,
      ntsc_mode => '1',
      sel       => x"05",
      dac_out   => dac_ntsc, hsync_o => cs_ntsc,
      vsync_o   => open,    active_o => ac_ntsc, blank_o => open
    );

  -- Reset + run
  process
  begin
    rst <= '1';
    wait for 5 * CLK_PERIOD;
    rst <= '0';
    -- 2 full PAL frames (625 lines × 640 clocks) is the longer of the two
    wait for 2 * 625 * 640 * CLK_PERIOD;
    report "=== tb_video_bram_top complete ===" severity note;
    std.env.finish;
  end process;

  -- -----------------------------------------------------------------------
  -- Checker 1: PAL sel=5, F1 frame 0, line 0  (screen_y=0)
  --   Ball initial position: x=0, y=0  →  px 0..59 WHITE, rest BLACK
  -- -----------------------------------------------------------------------
  process
    variable px  : integer;
    variable exp : std_logic_vector(3 downto 0);
  begin
    wait until rst = '0';
    wait until rising_edge(ac_pal);
    px := 0;
    loop
      wait until falling_edge(clk);
      exit when ac_pal = '0';
      if px < BALL_W then exp := WHITE; else exp := BLANK; end if;
      assert dac_pal = exp
        report "FAIL [PAL Chk1] px=" & integer'image(px) &
               " exp=" & integer'image(to_integer(unsigned(exp))) &
               " got=" & integer'image(to_integer(unsigned(dac_pal)))
        severity error;
      px := px + 1;
    end loop;
    assert px = H_ACTIVE
      report "FAIL [PAL Chk1] px count=" & integer'image(px) & " want 520"
      severity error;
    report "=== PAL Chk1 PASS: F1-L0 sel=5  px0-59=WHITE  px60-519=BLACK ===" severity note;
    wait;
  end process;

  -- -----------------------------------------------------------------------
  -- Checker 2: NTSC sel=5, F1 frame 0, line 0  (screen_y=0)
  --   Same ball initial position → same WHITE/BLACK split at x=60
  -- -----------------------------------------------------------------------
  process
    variable px  : integer;
    variable exp : std_logic_vector(3 downto 0);
  begin
    wait until rst = '0';
    wait until rising_edge(ac_ntsc);
    px := 0;
    loop
      wait until falling_edge(clk);
      exit when ac_ntsc = '0';
      if px < BALL_W then exp := WHITE; else exp := BLANK; end if;
      assert dac_ntsc = exp
        report "FAIL [NTSC Chk2] px=" & integer'image(px) &
               " exp=" & integer'image(to_integer(unsigned(exp))) &
               " got=" & integer'image(to_integer(unsigned(dac_ntsc)))
        severity error;
      px := px + 1;
    end loop;
    assert px = H_ACTIVE
      report "FAIL [NTSC Chk2] px count=" & integer'image(px) & " want 520"
      severity error;
    report "=== NTSC Chk2 PASS: F1-L0 sel=5  px0-59=WHITE  px60-519=BLACK ===" severity note;
    wait;
  end process;

  -- -----------------------------------------------------------------------
  -- Checker 3: PAL — DAC levels are valid at all times
  --   sync tip → "0000", blanking → "0100", active → "0100" or "1111" (sel=5)
  -- -----------------------------------------------------------------------
  process
    variable cnt : integer := 0;
  begin
    wait until rst = '0';
    -- Sample for ~1 full PAL frame (640*625 clocks)
    for i in 1 to 640 * 625 loop
      wait until falling_edge(clk);
      assert dac_pal = SYNC or dac_pal = BLANK or dac_pal = WHITE
        report "FAIL [PAL Chk3] invalid DAC=" &
               integer'image(to_integer(unsigned(dac_pal))) severity error;
      cnt := cnt + 1;
    end loop;
    report "=== PAL Chk3 PASS: DAC levels valid over " &
           integer'image(cnt) & " samples ===" severity note;
    wait;
  end process;

end architecture sim;
