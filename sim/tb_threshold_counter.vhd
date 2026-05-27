library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.threshold_counter_pkg.all;

-- Testbench: threshold_counter (4-channel, flat std_logic_vector ports)
--
-- CLK_MHZ=1  →  CLK_PER_MS=1000 cycles  (fast simulation)
-- Clock period = 10 ns
--
-- Q4.12 constants:
--   T1 = 2.0  = x"2000"    T2 = 1.0  = x"1000"
--   ABOVE_T1  = 3.0 = x"3000"
--   BETWEEN   = 1.5 = x"1800"  (T2 < value < T1)
--   BELOW_T2  = 0.5 = x"0800"

entity tb_threshold_counter is
end entity;

architecture sim of tb_threshold_counter is

  -- DUT ports (all std_logic / std_logic_vector — LabVIEW-compatible)
  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  signal data_in_0, data_in_1, data_in_2, data_in_3         : std_logic_vector(15 downto 0) := x"1800";
  signal threshold_1_0, threshold_1_1,
         threshold_1_2, threshold_1_3                         : std_logic_vector(15 downto 0) := x"2000";
  signal threshold_2_0, threshold_2_1,
         threshold_2_2, threshold_2_3                         : std_logic_vector(15 downto 0) := x"1000";
  signal delay_ms_0, delay_ms_1,
         delay_ms_2, delay_ms_3                               : std_logic_vector(15 downto 0) := x"0005";
  signal counter_o_0, counter_o_1, counter_o_2, counter_o_3 : std_logic_vector(15 downto 0);
  signal bit_a_0, bit_a_1, bit_a_2, bit_a_3                 : std_logic;
  signal bit_b_0, bit_b_1, bit_b_2, bit_b_3                 : std_logic;

  constant CLK_P    : time := 10 ns;
  constant MS       : time := 1000 * CLK_P;

  constant ABOVE_T1 : std_logic_vector(15 downto 0) := x"3000";
  constant BETWEEN  : std_logic_vector(15 downto 0) := x"1800";
  constant BELOW_T2 : std_logic_vector(15 downto 0) := x"0800";

  -- Helpers
  procedure chk16(signal   actual   : in std_logic_vector(15 downto 0);
                  constant expected : in integer;
                  constant msg      : in string) is
  begin
    if to_integer(unsigned(actual)) = expected then
      report "PASS: " & msg severity note;
    else
      report "FAIL: " & msg
           & "  exp=" & integer'image(expected)
           & "  got=" & integer'image(to_integer(unsigned(actual)))
        severity error;
    end if;
  end procedure;

  procedure chkbit(signal   actual   : in std_logic;
                   constant expected : in std_logic;
                   constant msg      : in string) is
  begin
    if actual = expected then
      report "PASS: " & msg severity note;
    else
      report "FAIL: " & msg
           & "  exp=" & std_logic'image(expected)
           & "  got=" & std_logic'image(actual)
        severity error;
    end if;
  end procedure;

begin

  clk <= not clk after CLK_P / 2;

  u_dut : entity work.threshold_counter
    generic map (CLK_MHZ => 1)
    port map (
      clk => clk, rst => rst,
      -- ch0
      data_in_0 => data_in_0, threshold_1_0 => threshold_1_0,
      threshold_2_0 => threshold_2_0, delay_ms_0 => delay_ms_0,
      counter_o_0 => counter_o_0, bit_a_0 => bit_a_0, bit_b_0 => bit_b_0,
      -- ch1
      data_in_1 => data_in_1, threshold_1_1 => threshold_1_1,
      threshold_2_1 => threshold_2_1, delay_ms_1 => delay_ms_1,
      counter_o_1 => counter_o_1, bit_a_1 => bit_a_1, bit_b_1 => bit_b_1,
      -- ch2
      data_in_2 => data_in_2, threshold_1_2 => threshold_1_2,
      threshold_2_2 => threshold_2_2, delay_ms_2 => delay_ms_2,
      counter_o_2 => counter_o_2, bit_a_2 => bit_a_2, bit_b_2 => bit_b_2,
      -- ch3
      data_in_3 => data_in_3, threshold_1_3 => threshold_1_3,
      threshold_2_3 => threshold_2_3, delay_ms_3 => delay_ms_3,
      counter_o_3 => counter_o_3, bit_a_3 => bit_a_3, bit_b_3 => bit_b_3
    );

  process
  begin
    rst <= '1'; wait for 5 * CLK_P; rst <= '0'; wait for 2 * CLK_P;

    -- -----------------------------------------------------------------------
    -- Test 1: Rule 1 — ch0 & ch1 crossing → counter = 1
    -- -----------------------------------------------------------------------
    report "--- Test 1: Rule 1 falling crossing (ch0 & ch1) ---" severity note;
    data_in_0 <= ABOVE_T1; data_in_1 <= ABOVE_T1;
    wait for 10 * CLK_P;
    data_in_0 <= BETWEEN;  data_in_1 <= BETWEEN;
    wait for 5 * CLK_P;

    chk16(counter_o_0, 1, "T1 ch0: counter=1");
    chk16(counter_o_1, 1, "T1 ch1: counter=1");
    chk16(counter_o_2, 0, "T1 ch2: counter=0 (untouched)");
    chk16(counter_o_3, 0, "T1 ch3: counter=0 (untouched)");
    chkbit(bit_b_0, '1', "T1 ch0: bit_b='1'");
    chkbit(bit_b_2, '0', "T1 ch2: bit_b='0'");

    -- -----------------------------------------------------------------------
    -- Test 2: ch0 gets 3 more crossings → 4; ch1 stays at 1
    -- -----------------------------------------------------------------------
    report "--- Test 2: ch0 multiple crossings, ch1 idle ---" severity note;
    for i in 1 to 3 loop
      data_in_0 <= ABOVE_T1; wait for 10 * CLK_P;
      data_in_0 <= BETWEEN;  wait for 5  * CLK_P;
    end loop;

    chk16(counter_o_0, 4, "T2 ch0: counter=4");
    chk16(counter_o_1, 1, "T2 ch1: counter still 1");

    -- -----------------------------------------------------------------------
    -- Test 3: Rule 2 timeout on ch0 only
    -- -----------------------------------------------------------------------
    report "--- Test 3: Rule 2 timeout (ch0 only) ---" severity note;
    data_in_0 <= ABOVE_T1;
    wait for 6 * MS; wait for 5 * CLK_P;

    chk16(counter_o_0, 0, "T3 ch0: counter=0 (timeout)");
    chkbit(bit_b_0, '0', "T3 ch0: bit_b='0'");
    chk16(counter_o_1, 1, "T3 ch1: counter still 1 (unaffected)");

    -- -----------------------------------------------------------------------
    -- Test 4: Rule 3 — below T2 on ch0 only
    -- -----------------------------------------------------------------------
    report "--- Test 4: Rule 3 below T2 (ch0 only) ---" severity note;
    rst <= '1'; wait for 5 * CLK_P; rst <= '0';
    data_in_0 <= BETWEEN; data_in_1 <= BETWEEN;
    wait for 5 * CLK_P;

    for i in 1 to 2 loop
      data_in_0 <= ABOVE_T1; wait for 10 * CLK_P;
      data_in_0 <= BETWEEN;  wait for 5  * CLK_P;
    end loop;
    chk16(counter_o_0, 2, "T4 setup: ch0 counter=2");

    data_in_0 <= BELOW_T2; wait for 5 * CLK_P;

    chk16(counter_o_0, 0,  "T4 ch0: counter=0 after below-T2");
    chkbit(bit_a_0,   '1', "T4 ch0: bit_a latched '1'");
    chkbit(bit_b_0,   '0', "T4 ch0: bit_b='0'");
    chk16(counter_o_1, 0,  "T4 ch1: counter unchanged (0)");
    chkbit(bit_a_1,   '0', "T4 ch1: bit_a not affected");

    -- -----------------------------------------------------------------------
    -- Test 5: bit_a stays latched
    -- -----------------------------------------------------------------------
    report "--- Test 5: bit_a latched after event ---" severity note;
    data_in_0 <= BETWEEN; wait for 20 * CLK_P;
    chkbit(bit_a_0, '1', "T5 ch0: bit_a still '1'");

    -- -----------------------------------------------------------------------
    -- Test 6: rst clears all channels
    -- -----------------------------------------------------------------------
    report "--- Test 6: rst clears all channels ---" severity note;
    rst <= '1'; wait for 5 * CLK_P; rst <= '0'; wait for 5 * CLK_P;

    chk16(counter_o_0, 0, "T6 ch0: counter=0");
    chk16(counter_o_1, 0, "T6 ch1: counter=0");
    chk16(counter_o_2, 0, "T6 ch2: counter=0");
    chk16(counter_o_3, 0, "T6 ch3: counter=0");
    chkbit(bit_a_0, '0', "T6 ch0: bit_a='0' after rst");
    chkbit(bit_b_0, '0', "T6 ch0: bit_b='0' after rst");

    -- -----------------------------------------------------------------------
    -- Test 7: ch2 and ch3 independent crossings
    -- -----------------------------------------------------------------------
    report "--- Test 7: ch2 and ch3 independent crossings ---" severity note;
    data_in_0 <= BETWEEN; data_in_1 <= BETWEEN;
    data_in_2 <= BETWEEN; data_in_3 <= BETWEEN;
    wait for 5 * CLK_P;

    data_in_2 <= ABOVE_T1; data_in_3 <= ABOVE_T1;
    wait for 10 * CLK_P;
    data_in_2 <= BETWEEN;  data_in_3 <= BETWEEN;
    wait for 5 * CLK_P;

    chk16(counter_o_0, 0, "T7 ch0: counter=0 (untouched)");
    chk16(counter_o_1, 0, "T7 ch1: counter=0 (untouched)");
    chk16(counter_o_2, 1, "T7 ch2: counter=1");
    chk16(counter_o_3, 1, "T7 ch3: counter=1");

    -- -----------------------------------------------------------------------
    report "=== All tests done ===" severity note;
    std.env.stop;
  end process;

end architecture sim;
