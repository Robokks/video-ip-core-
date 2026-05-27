library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ============================================================================
-- Testbench: threshold_counter  (combinational, no clk/rst ports)
--
-- Simulates the LabVIEW FPGA while-loop + shift-register pattern:
--   • A local 'clk' drives the testbench (not connected to DUT).
--   • On each rising edge the shift-register process latches DUT outputs
--     back into the DUT state inputs (_in ports), exactly as LabVIEW does.
--   • Stimulus is applied via data_in_N; checks happen after settling.
--
-- CLK_MHZ=1 → CLK_PER_MS=1000 cycles → prescaler threshold = 999
-- Clock period = 10 ns
--
-- Q4.12 word values used:
--   ABOVE_T1 = 3.0  = x"3000"
--   BETWEEN  = 1.5  = x"1800"   (T2 < val < T1)
--   BELOW_T2 = 0.5  = x"0800"
--   T1       = 2.0  = x"2000"
--   T2       = 1.0  = x"1000"
-- ============================================================================

entity tb_threshold_counter is
end entity;

architecture sim of tb_threshold_counter is

  -- DUT: all std_logic / std_logic_vector ports (LabVIEW-compatible)
  -- Control/data inputs
  signal data_in_0, data_in_1, data_in_2, data_in_3 : std_logic_vector(15 downto 0) := x"1800";
  signal t1_0, t1_1, t1_2, t1_3                     : std_logic_vector(15 downto 0) := x"2000";
  signal t2_0, t2_1, t2_2, t2_3                     : std_logic_vector(15 downto 0) := x"1000";
  signal dms_0, dms_1, dms_2, dms_3                 : std_logic_vector(15 downto 0) := x"0005";
  signal clr_0, clr_1, clr_2, clr_3                 : std_logic := '0';

  -- State inputs (shift-register outputs → DUT inputs)
  signal cnt_in_0, cnt_in_1, cnt_in_2, cnt_in_3     : std_logic_vector(15 downto 0) := x"0000";
  signal pre_in_0, pre_in_1, pre_in_2, pre_in_3     : std_logic_vector(15 downto 0) := x"0000";
  signal ms_in_0,  ms_in_1,  ms_in_2,  ms_in_3      : std_logic_vector(15 downto 0) := x"0000";
  signal pa_in_0,  pa_in_1,  pa_in_2,  pa_in_3      : std_logic := '0';
  signal ba_in_0,  ba_in_1,  ba_in_2,  ba_in_3      : std_logic := '0';

  -- State outputs (DUT outputs → shift-register inputs)
  signal cnt_out_0, cnt_out_1, cnt_out_2, cnt_out_3 : std_logic_vector(15 downto 0);
  signal pre_out_0, pre_out_1, pre_out_2, pre_out_3 : std_logic_vector(15 downto 0);
  signal ms_out_0,  ms_out_1,  ms_out_2,  ms_out_3  : std_logic_vector(15 downto 0);
  signal at1_0,     at1_1,     at1_2,     at1_3      : std_logic;
  signal ba_out_0,  ba_out_1,  ba_out_2,  ba_out_3  : std_logic;
  signal bb_0,      bb_1,      bb_2,      bb_3       : std_logic;

  -- Testbench clock (not a DUT port — drives shift-register feedback)
  signal clk : std_logic := '0';

  constant CLK_P  : time := 10 ns;
  constant MS     : time := 1000 * CLK_P;   -- CLK_MHZ=1 → 1ms = 1000 cycles

  constant ABOVE_T1 : std_logic_vector(15 downto 0) := x"3000";
  constant BETWEEN  : std_logic_vector(15 downto 0) := x"1800";
  constant BELOW_T2 : std_logic_vector(15 downto 0) := x"0800";

  -- Helpers
  procedure chk16(signal   a : in std_logic_vector(15 downto 0);
                  constant e : in integer;
                  constant m : in string) is
  begin
    if to_integer(unsigned(a)) = e then report "PASS: " & m severity note;
    else report "FAIL: " & m & "  exp=" & integer'image(e)
              & " got=" & integer'image(to_integer(unsigned(a))) severity error;
    end if;
  end procedure;

  procedure chkb(signal   a : in std_logic; constant e : in std_logic;
                 constant m : in string) is
  begin
    if a = e then report "PASS: " & m severity note;
    else report "FAIL: " & m & "  exp=" & std_logic'image(e)
              & " got=" & std_logic'image(a) severity error;
    end if;
  end procedure;

begin

  clk <= not clk after CLK_P / 2;

  -- ==========================================================================
  -- DUT instantiation (no clk/rst ports)
  -- ==========================================================================
  u_dut : entity work.threshold_counter
    generic map (CLK_MHZ => 1)
    port map (
      -- ch0
      data_in_0 => data_in_0, threshold_1_0 => t1_0, threshold_2_0 => t2_0,
      delay_ms_0 => dms_0, clear_0 => clr_0,
      counter_in_0 => cnt_in_0, prescaler_in_0 => pre_in_0, ms_cnt_in_0 => ms_in_0,
      prev_above_0 => pa_in_0, bit_a_in_0 => ba_in_0,
      counter_out_0 => cnt_out_0, prescaler_out_0 => pre_out_0, ms_cnt_out_0 => ms_out_0,
      above_t1_0 => at1_0, bit_a_out_0 => ba_out_0, bit_b_0 => bb_0,
      -- ch1
      data_in_1 => data_in_1, threshold_1_1 => t1_1, threshold_2_1 => t2_1,
      delay_ms_1 => dms_1, clear_1 => clr_1,
      counter_in_1 => cnt_in_1, prescaler_in_1 => pre_in_1, ms_cnt_in_1 => ms_in_1,
      prev_above_1 => pa_in_1, bit_a_in_1 => ba_in_1,
      counter_out_1 => cnt_out_1, prescaler_out_1 => pre_out_1, ms_cnt_out_1 => ms_out_1,
      above_t1_1 => at1_1, bit_a_out_1 => ba_out_1, bit_b_1 => bb_1,
      -- ch2
      data_in_2 => data_in_2, threshold_1_2 => t1_2, threshold_2_2 => t2_2,
      delay_ms_2 => dms_2, clear_2 => clr_2,
      counter_in_2 => cnt_in_2, prescaler_in_2 => pre_in_2, ms_cnt_in_2 => ms_in_2,
      prev_above_2 => pa_in_2, bit_a_in_2 => ba_in_2,
      counter_out_2 => cnt_out_2, prescaler_out_2 => pre_out_2, ms_cnt_out_2 => ms_out_2,
      above_t1_2 => at1_2, bit_a_out_2 => ba_out_2, bit_b_2 => bb_2,
      -- ch3
      data_in_3 => data_in_3, threshold_1_3 => t1_3, threshold_2_3 => t2_3,
      delay_ms_3 => dms_3, clear_3 => clr_3,
      counter_in_3 => cnt_in_3, prescaler_in_3 => pre_in_3, ms_cnt_in_3 => ms_in_3,
      prev_above_3 => pa_in_3, bit_a_in_3 => ba_in_3,
      counter_out_3 => cnt_out_3, prescaler_out_3 => pre_out_3, ms_cnt_out_3 => ms_out_3,
      above_t1_3 => at1_3, bit_a_out_3 => ba_out_3, bit_b_3 => bb_3
    );

  -- ==========================================================================
  -- Shift-register feedback (simulates LabVIEW while-loop registers)
  -- On each rising edge: latch DUT outputs → DUT state inputs
  -- ==========================================================================
  process(clk)
  begin
    if rising_edge(clk) then
      -- ch0
      cnt_in_0 <= cnt_out_0;  pre_in_0 <= pre_out_0;
      ms_in_0  <= ms_out_0;   pa_in_0  <= at1_0;   ba_in_0 <= ba_out_0;
      -- ch1
      cnt_in_1 <= cnt_out_1;  pre_in_1 <= pre_out_1;
      ms_in_1  <= ms_out_1;   pa_in_1  <= at1_1;   ba_in_1 <= ba_out_1;
      -- ch2
      cnt_in_2 <= cnt_out_2;  pre_in_2 <= pre_out_2;
      ms_in_2  <= ms_out_2;   pa_in_2  <= at1_2;   ba_in_2 <= ba_out_2;
      -- ch3
      cnt_in_3 <= cnt_out_3;  pre_in_3 <= pre_out_3;
      ms_in_3  <= ms_out_3;   pa_in_3  <= at1_3;   ba_in_3 <= ba_out_3;
    end if;
  end process;

  -- ==========================================================================
  -- Stimulus and checks
  -- ==========================================================================
  process
    -- Wait N rising edges (= N LabVIEW while-loop iterations)
    procedure tick(n : natural := 1) is
    begin
      for i in 1 to n loop
        wait until rising_edge(clk);
        wait for 1 ns;   -- let combinational settle after feedback
      end loop;
    end procedure;
  begin
    tick(5);   -- let shift registers initialise

    -- -----------------------------------------------------------------------
    -- Test 1: Rule 1 — ch0 & ch1 crossing  → counter = 1
    -- -----------------------------------------------------------------------
    report "--- Test 1: Rule 1 falling crossing (ch0 & ch1) ---" severity note;
    data_in_0 <= ABOVE_T1;  data_in_1 <= ABOVE_T1;
    tick(5);                        -- stay above T1 for a few cycles
    data_in_0 <= BETWEEN;   data_in_1 <= BETWEEN;
    tick(3);                        -- let Rule 1 fire

    chk16(cnt_out_0, 1, "T1 ch0: counter=1");
    chk16(cnt_out_1, 1, "T1 ch1: counter=1");
    chk16(cnt_out_2, 0, "T1 ch2: counter=0 (untouched)");
    chk16(cnt_out_3, 0, "T1 ch3: counter=0 (untouched)");
    chkb (bb_0, '1', "T1 ch0: bit_b='1'");
    chkb (bb_2, '0', "T1 ch2: bit_b='0'");

    -- -----------------------------------------------------------------------
    -- Test 2: ch0 gets 3 more crossings → 4;  ch1 stays at 1
    -- -----------------------------------------------------------------------
    report "--- Test 2: ch0 multiple crossings, ch1 idle ---" severity note;
    for i in 1 to 3 loop
      data_in_0 <= ABOVE_T1;  tick(5);
      data_in_0 <= BETWEEN;   tick(3);
    end loop;

    chk16(cnt_out_0, 4, "T2 ch0: counter=4");
    chk16(cnt_out_1, 1, "T2 ch1: counter still 1");

    -- -----------------------------------------------------------------------
    -- Test 3: Rule 2 timeout on ch0 only  (delay_ms=5 → 5000 cycles @ 1 MHz)
    -- -----------------------------------------------------------------------
    report "--- Test 3: Rule 2 timeout (ch0 only) ---" severity note;
    data_in_0 <= ABOVE_T1;
    tick(6000);   -- 6 ms worth of cycles

    chk16(cnt_out_0, 0, "T3 ch0: counter=0 (timeout)");
    chkb (bb_0,   '0', "T3 ch0: bit_b='0'");
    chk16(cnt_out_1, 1, "T3 ch1: counter still 1");

    -- -----------------------------------------------------------------------
    -- Test 4: Rule 3 — below T2 on ch0 only
    -- -----------------------------------------------------------------------
    report "--- Test 4: Rule 3 below T2 (ch0 only) ---" severity note;
    -- Soft-reset both channels via clear
    clr_0 <= '1';  clr_1 <= '1';  tick(2);
    clr_0 <= '0';  clr_1 <= '0';  tick(2);

    -- Build ch0 counter to 2
    for i in 1 to 2 loop
      data_in_0 <= ABOVE_T1;  tick(5);
      data_in_0 <= BETWEEN;   tick(3);
    end loop;
    chk16(cnt_out_0, 2, "T4 setup: ch0 counter=2");

    data_in_0 <= BELOW_T2;  tick(3);

    chk16(cnt_out_0, 0,  "T4 ch0: counter=0 after below-T2");
    chkb (ba_out_0, '1', "T4 ch0: bit_a latched '1'");
    chkb (bb_0,     '0', "T4 ch0: bit_b='0'");
    chk16(cnt_out_1, 0,  "T4 ch1: counter unchanged (0)");
    chkb (ba_out_1, '0', "T4 ch1: bit_a not affected");

    -- -----------------------------------------------------------------------
    -- Test 5: bit_a stays latched
    -- -----------------------------------------------------------------------
    report "--- Test 5: bit_a latched after event ---" severity note;
    data_in_0 <= BETWEEN;  tick(10);
    chkb(ba_out_0, '1', "T5 ch0: bit_a still '1'");

    -- -----------------------------------------------------------------------
    -- Test 6: clear resets all channels
    -- -----------------------------------------------------------------------
    report "--- Test 6: clear resets all channels ---" severity note;
    clr_0 <= '1';  clr_1 <= '1';  clr_2 <= '1';  clr_3 <= '1';
    tick(2);
    clr_0 <= '0';  clr_1 <= '0';  clr_2 <= '0';  clr_3 <= '0';
    tick(2);

    chk16(cnt_out_0, 0, "T6 ch0: counter=0");
    chk16(cnt_out_1, 0, "T6 ch1: counter=0");
    chk16(cnt_out_2, 0, "T6 ch2: counter=0");
    chk16(cnt_out_3, 0, "T6 ch3: counter=0");
    chkb (ba_out_0, '0', "T6 ch0: bit_a='0' after clear");
    chkb (bb_0,     '0', "T6 ch0: bit_b='0' after clear");

    -- -----------------------------------------------------------------------
    -- Test 7: ch2 and ch3 cross independently
    -- -----------------------------------------------------------------------
    report "--- Test 7: ch2 and ch3 independent crossings ---" severity note;
    data_in_0 <= BETWEEN;  data_in_1 <= BETWEEN;
    data_in_2 <= ABOVE_T1; data_in_3 <= ABOVE_T1;
    tick(5);
    data_in_2 <= BETWEEN;  data_in_3 <= BETWEEN;
    tick(3);

    chk16(cnt_out_0, 0, "T7 ch0: counter=0 (untouched)");
    chk16(cnt_out_1, 0, "T7 ch1: counter=0 (untouched)");
    chk16(cnt_out_2, 1, "T7 ch2: counter=1");
    chk16(cnt_out_3, 1, "T7 ch3: counter=1");

    -- -----------------------------------------------------------------------
    report "=== All tests done ===" severity note;
    std.env.stop;
  end process;

end architecture sim;
