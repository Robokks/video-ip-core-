library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Testbench: pal_tv_bram_lite_v4 - verifies PAL standard active line boundaries
-- Scope line = v_cnt + 1 (scope starts at 1)
entity tb_lite_v4_verify is
end entity tb_lite_v4_verify;

architecture sim of tb_lite_v4_verify is

  constant CLK_PERIOD : time    := 100 ns;
  constant H_TOTAL    : integer := 640;
  constant V_TOTAL    : integer := 625;

  signal clk         : std_logic := '0';
  signal rst         : std_logic := '1';
  signal sel         : std_logic_vector(7 downto 0) := x"00";

  signal dac_out     : std_logic_vector(3 downto 0);
  signal csync_o     : std_logic;
  signal line_sync_o : std_logic;
  signal frame_sync_o: std_logic;
  signal fss_o       : std_logic;
  signal field_o     : std_logic;
  signal active_o    : std_logic;
  signal blank_o     : std_logic;

  signal pass : boolean := true;

begin

  clk <= not clk after CLK_PERIOD / 2;
  rst <= '0' after CLK_PERIOD * 5;

  uut : entity work.pal_tv_bram_lite_v4
    generic map (CLK_MHZ => 10, BRAM_DEPTH => 1040)
    port map (
      clk => clk, rst => rst, sel => sel,
      brightness => "1111", black_lvl => "0100",
      bram_wr_en => '0', bram_wr_addr => (others => '0'),
      bram_wr_data => '0', bram_len => (others => '1'),
      v_act_s_f1_p => (others => '0'), v_act_e_f1_p => (others => '0'),
      v_act_s_f2_p => (others => '0'), v_act_e_f2_p => (others => '0'),
      fss_f1_s_p   => (others => '0'), fss_f1_e_p   => (others => '0'),
      fss_f2_sv_p  => (others => '0'), fss_f2_sh_p  => (others => '0'),
      fss_f2_ev_p  => (others => '0'), fss_f2_eh_p  => (others => '0'),
      dac_out => dac_out, csync_o => csync_o,
      line_sync_o => line_sync_o, frame_sync_o => frame_sync_o,
      fss_o => fss_o, field_o => field_o,
      active_o => active_o, blank_o => blank_o
    );

  process
    -- All checks in frame 2 to avoid reset transients.
    -- Pixel (V,H) in frame 2 is at absolute cycle: 5 + V_TOTAL*H_TOTAL + V*H_TOTAL + H
    constant BASE : integer := 5 + V_TOTAL * H_TOTAL;
    constant P1 : integer := BASE + 21  * H_TOTAL + 200;
    constant P2 : integer := BASE + 22  * H_TOTAL + 120;
    constant P3 : integer := BASE + 309 * H_TOTAL + 400;
    constant P4 : integer := BASE + 310 * H_TOTAL + 200;
    constant P5 : integer := BASE + 334 * H_TOTAL + 200;
    constant P6 : integer := BASE + 335 * H_TOTAL + 120;
    constant P7 : integer := BASE + 622 * H_TOTAL + 400;
    constant P8 : integer := BASE + 623 * H_TOTAL + 200;
  begin
    wait for CLK_PERIOD * P1;
    wait until rising_edge(clk);
    if active_o = '1' then
      report "FAIL: scope line 22 (v_cnt=21) ACTIVE - must be BLANK" severity error;
      pass <= false;
    else
      report "PASS: scope line 22 (v_cnt=21) is BLANK" severity note;
    end if;

    wait for CLK_PERIOD * (P2 - P1);
    wait until rising_edge(clk);
    if active_o /= '1' then
      report "FAIL: scope line 23 (v_cnt=22, h=120) NOT active - F1 must start here" severity error;
      pass <= false;
    else
      report "PASS: scope line 23 (v_cnt=22) ACTIVE - F1 starts correctly" severity note;
    end if;

    wait for CLK_PERIOD * (P3 - P2);
    wait until rising_edge(clk);
    if active_o /= '1' then
      report "FAIL: scope line 310 (v_cnt=309, h=639) NOT active - F1 last line wrong" severity error;
      pass <= false;
    else
      report "PASS: scope line 310 (v_cnt=309) ACTIVE - F1 last line correct" severity note;
    end if;

    wait for CLK_PERIOD * (P4 - P3);
    wait until rising_edge(clk);
    if active_o = '1' then
      report "FAIL: scope line 311 (v_cnt=310) ACTIVE - must be BLANK after F1" severity error;
      pass <= false;
    else
      report "PASS: scope line 311 (v_cnt=310) is BLANK - F1 ends correctly" severity note;
    end if;

    wait for CLK_PERIOD * (P5 - P4);
    wait until rising_edge(clk);
    if active_o = '1' then
      report "FAIL: scope line 335 (v_cnt=334) ACTIVE - must be BLANK before F2" severity error;
      pass <= false;
    else
      report "PASS: scope line 335 (v_cnt=334) is BLANK - F2 VBI correct" severity note;
    end if;

    wait for CLK_PERIOD * (P6 - P5);
    wait until rising_edge(clk);
    if active_o /= '1' then
      report "FAIL: scope line 336 (v_cnt=335, h=120) NOT active - F2 must start here" severity error;
      pass <= false;
    else
      report "PASS: scope line 336 (v_cnt=335) ACTIVE - F2 starts correctly" severity note;
    end if;

    wait for CLK_PERIOD * (P7 - P6);
    wait until rising_edge(clk);
    if active_o /= '1' then
      report "FAIL: scope line 623 (v_cnt=622, h=639) NOT active - F2 last line wrong" severity error;
      pass <= false;
    else
      report "PASS: scope line 623 (v_cnt=622) ACTIVE - F2 last line correct" severity note;
    end if;

    wait for CLK_PERIOD * (P8 - P7);
    wait until rising_edge(clk);
    if active_o = '1' then
      report "FAIL: scope line 624 (v_cnt=623) ACTIVE - must be BLANK after F2" severity error;
      pass <= false;
    else
      report "PASS: scope line 624 (v_cnt=623) is BLANK - F2 ends correctly" severity note;
    end if;

    if pass then
      report "ALL 8 CHECKS PASSED - v4 PAL timing correct" severity note;
      report "F1: scope lines 23-310  v_cnt 22-309  = 288 lines" severity note;
      report "F2: scope lines 336-623 v_cnt 335-622 = 288 lines" severity note;
    else
      report "ONE OR MORE CHECKS FAILED" severity error;
    end if;

    assert false report "sim done" severity failure;
  end process;

end architecture sim;
