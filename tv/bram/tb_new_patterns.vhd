library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Self-checking testbench for sel 6-9, ball control ports, and crosshatch
-- Tests:
--   Chk1  sel=6  full white  : every active pixel = brightness (LEVEL_WHITE)
--   Chk2  sel=7  full black  : every active pixel = black_lvl  (LEVEL_BLANK)
--   Chk3  sel=8  crosshatch  : pixel 0 and pixel 52 of each active line = white
--                              pixel 26 (mid-zone) = black
--   Chk4  sel=9  centre cross: pixel H_ACTIVE/2 = 260 white; pixel 0 = black
--   Chk5  ball ports          : ball_w=100, ball_h=80, spd_h=5, spd_v=4;
--                               first 100 px of line 0 = white
entity tb_new_patterns is
end entity tb_new_patterns;

architecture sim of tb_new_patterns is

  constant CLK_MHZ : integer := 10;
  constant H_FRONT  : integer := 16;
  constant H_SYNC_W : integer := 47;
  constant H_BACK   : integer := 57;
  constant H_ACTIVE : integer := 520;
  constant H_ACT_S  : integer := H_FRONT + H_SYNC_W + H_BACK;  -- 120
  constant H_TOTAL  : integer := 640;
  constant V_ACT_S_F1 : integer := 24;
  constant V_ACT_E_F1 : integer := 311;
  constant CLK_P    : time := 100 ns;

  signal clk         : std_logic := '0';
  signal rst         : std_logic := '1';
  signal sel         : std_logic_vector(7 downto 0) := x"06";
  signal dac_out     : std_logic_vector(3 downto 0);
  signal csync_o     : std_logic;
  signal line_sync_o : std_logic;
  signal frame_sync_o: std_logic;
  signal field_o     : std_logic;
  signal active_o    : std_logic;
  signal blank_o     : std_logic;
  signal ball_spd_h  : std_logic_vector(3 downto 0) := "0011";  -- 3
  signal ball_spd_v  : std_logic_vector(3 downto 0) := "0010";  -- 2
  signal ball_w_i    : std_logic_vector(9 downto 0) := "0000111100";  -- 60
  signal ball_h_i    : std_logic_vector(9 downto 0) := "0000110010";  -- 50
  signal cross_h_i   : std_logic_vector(9 downto 0) := "0000110100";  -- 52
  signal cross_v_i   : std_logic_vector(9 downto 0) := "0000111010";  -- 58

  constant LEVEL_WHITE : std_logic_vector(3 downto 0) := "1111";
  constant LEVEL_BLANK : std_logic_vector(3 downto 0) := "0100";

  -- Land on pixel 0 of the next F1 active line.
  -- If currently inside an active window, drains it first so the
  -- next time active_o rises we are guaranteed to be at px 0.
  procedure next_f1_line(
      signal clk      : in std_logic;
      signal active_o : in std_logic;
      signal field_o  : in std_logic) is
  begin
    -- drain any current active window
    while active_o = '1' loop
      wait until rising_edge(clk);
    end loop;
    -- wait for the next F1 active window (= px 0 of an F1 line)
    while not (active_o = '1' and field_o = '0') loop
      wait until rising_edge(clk);
    end loop;
  end procedure;

begin
  clk <= not clk after CLK_P / 2;

  dut : entity work.pal_tv_bram_top
    generic map (CLK_MHZ => CLK_MHZ, BRAM_DEPTH => 1040)
    port map (
      clk          => clk,
      rst          => rst,
      sel          => sel,
      ball_spd_h   => ball_spd_h,
      ball_spd_v   => ball_spd_v,
      ball_w_i     => ball_w_i,
      ball_h_i     => ball_h_i,
      cross_h_i    => cross_h_i,
      cross_v_i    => cross_v_i,
      dac_out      => dac_out,
      csync_o      => csync_o,
      line_sync_o  => line_sync_o,
      frame_sync_o => frame_sync_o,
      field_o      => field_o,
      active_o     => active_o,
      blank_o      => blank_o
    );

  -- -------------------------------------------------------------------------
  stimulus : process
    variable ok : boolean;
  begin
    rst <= '1'; wait for 5 * CLK_P; rst <= '0';

    -- =======================================================================
    -- Chk1: sel=6 full white - all active pixels must equal LEVEL_WHITE
    -- =======================================================================
    sel <= x"06";
    next_f1_line(clk, active_o, field_o);
    ok := true;
    for p in 0 to H_ACTIVE - 1 loop
      if dac_out /= LEVEL_WHITE then ok := false; end if;
      wait until rising_edge(clk);
    end loop;
    if ok then
      report "=== Chk1 PASS: sel=6 full white - all 520 px = WHITE ===" severity note;
    else
      report "!!! Chk1 FAIL: sel=6 - some pixel not WHITE" severity failure;
    end if;

    -- =======================================================================
    -- Chk2: sel=7 full black - all active pixels must equal LEVEL_BLANK
    -- =======================================================================
    sel <= x"07";
    next_f1_line(clk, active_o, field_o);
    ok := true;
    for p in 0 to H_ACTIVE - 1 loop
      if dac_out /= LEVEL_BLANK then ok := false; end if;
      wait until rising_edge(clk);
    end loop;
    if ok then
      report "=== Chk2 PASS: sel=7 full black - all 520 px = BLANK ===" severity note;
    else
      report "!!! Chk2 FAIL: sel=7 - some pixel not BLANK" severity failure;
    end if;

    -- =======================================================================
    -- Chk3: sel=8 crosshatch, cross_h=52
    --   px 0  = white  (cross_x_cnt = 0 → grid line)
    --   px 26 = black  (mid-zone, cross_x_cnt = 26)
    --   px 52 = white  (cross_x_cnt wraps to 0 at 52)
    -- =======================================================================
    sel <= x"08";
    cross_h_i <= std_logic_vector(to_unsigned(52, 10));
    next_f1_line(clk, active_o, field_o);
    -- px 0
    if dac_out = LEVEL_WHITE then
      report "  Chk3a PASS: px0 = WHITE (crosshatch grid line)" severity note;
    else
      report "!!! Chk3a FAIL: px0 expected WHITE" severity failure;
    end if;
    -- advance to px 26
    for p in 1 to 26 loop wait until rising_edge(clk); end loop;
    if dac_out = LEVEL_BLANK then
      report "  Chk3b PASS: px26 = BLANK (crosshatch interior)" severity note;
    else
      report "!!! Chk3b FAIL: px26 expected BLANK" severity failure;
    end if;
    -- advance to px 52
    for p in 27 to 52 loop wait until rising_edge(clk); end loop;
    if dac_out = LEVEL_WHITE then
      report "=== Chk3 PASS: sel=8 crosshatch - px0=WHITE px26=BLANK px52=WHITE ===" severity note;
    else
      report "!!! Chk3c FAIL: px52 expected WHITE (second grid line)" severity failure;
    end if;
    -- Chk4 will drain the rest of this active window via next_f1_line

    -- =======================================================================
    -- Chk4: sel=9 centre cross
    --   px 259 = black
    --   px 260 = white  (H_ACTIVE/2 = 260)
    --   px 261 = black
    -- =======================================================================
    sel <= x"09";
    next_f1_line(clk, active_o, field_o);
    -- advance to px 259
    for p in 1 to 259 loop wait until rising_edge(clk); end loop;
    if dac_out = LEVEL_BLANK then
      report "  Chk4a PASS: px259 = BLANK (before centre)" severity note;
    else
      report "!!! Chk4a FAIL: px259 expected BLANK" severity failure;
    end if;
    wait until rising_edge(clk);   -- px 260
    if dac_out = LEVEL_WHITE then
      report "  Chk4b PASS: px260 = WHITE (centre column)" severity note;
    else
      report "!!! Chk4b FAIL: px260 expected WHITE" severity failure;
    end if;
    wait until rising_edge(clk);   -- px 261
    if dac_out = LEVEL_BLANK then
      report "=== Chk4 PASS: sel=9 centre cross - px260=WHITE flanked by BLANK ===" severity note;
    else
      report "!!! Chk4c FAIL: px261 expected BLANK" severity failure;
    end if;

    -- =======================================================================
    -- Chk5: ball ports - set ball 100×80, speed 5/4
    --        line 0 F1: pixels 0..99 = white, 100..519 = black
    -- =======================================================================
    sel        <= x"05";
    ball_w_i   <= std_logic_vector(to_unsigned(100, 10));
    ball_h_i   <= std_logic_vector(to_unsigned(80,  10));
    ball_spd_h <= "0101";   -- 5
    ball_spd_v <= "0100";   -- 4
    -- Reset to latch new ball params
    rst <= '1'; wait for 3 * CLK_P; rst <= '0';
    -- Wait for first active line of F1 in this frame
    next_f1_line(clk, active_o, field_o);
    ok := true;
    for p in 0 to 99 loop
      if dac_out /= LEVEL_WHITE then ok := false; end if;
      wait until rising_edge(clk);
    end loop;
    if not ok then
      report "!!! Chk5 FAIL: ball px 0..99 not all WHITE" severity failure;
    end if;
    for p in 100 to 519 loop
      if dac_out /= LEVEL_BLANK then ok := false; end if;
      wait until rising_edge(clk);
    end loop;
    if ok then
      report "=== Chk5 PASS: ball 100-wide - px0-99=WHITE  px100-519=BLACK ===" severity note;
    else
      report "!!! Chk5 FAIL: ball region boundary incorrect" severity failure;
    end if;

    report "=== tb_new_patterns: all checks complete ===" severity note;
    std.env.finish;
  end process;
end architecture sim;
