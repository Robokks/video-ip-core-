library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.threshold_counter_pkg.all;

-- Testbench: threshold_counter (4-channel)
--
-- CLK_MHZ=1  →  CLK_PER_MS=1000 cycles  (fast simulation)
-- Clock period = 10 ns
--
-- Q4.12 constants:
--   T1 = 2.0  = x"2000"    T2 = 1.0  = x"1000"
--   ABOVE_T1  = 3.0 = x"3000"
--   BETWEEN   = 1.5 = x"1800"  (T2 < value < T1)
--   BELOW_T2  = 0.5 = x"0800"
--
-- Strategy:
--   Channel 0 — full Rule 1/2/3 / bit_a / bit_b / wrap sequence
--   Channel 1 — independent Rule 1 check (different thresholds, same time)
--   Channels 2,3 — held at BETWEEN (neutral), verify counter stays 0

entity tb_threshold_counter is
end entity;

architecture sim of tb_threshold_counter is

  signal clk         : std_logic := '0';
  signal rst         : std_logic := '1';
  signal data_in     : word16_array_t := (others => x"1800");
  signal threshold_1 : word16_array_t := (others => x"2000");
  signal threshold_2 : word16_array_t := (others => x"1000");
  signal delay_ms    : word16_array_t := (others => x"0005");
  signal counter_o   : word16_array_t;
  signal bit_a       : std_logic_vector(TC_NUM_CH-1 downto 0);
  signal bit_b       : std_logic_vector(TC_NUM_CH-1 downto 0);

  constant CLK_P    : time := 10 ns;
  constant MS       : time := 1000 * CLK_P;

  constant ABOVE_T1 : std_logic_vector(15 downto 0) := x"3000";
  constant BETWEEN  : std_logic_vector(15 downto 0) := x"1800";
  constant BELOW_T2 : std_logic_vector(15 downto 0) := x"0800";

  -- Helper: check a 16-bit counter value
  procedure chk16(
    signal   actual   : in std_logic_vector(15 downto 0);
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

  -- Helper: check a single std_logic bit
  procedure chkbit(
    signal   actual   : in std_logic;
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
      data_in     => data_in,
      threshold_1 => threshold_1,
      threshold_2 => threshold_2,
      delay_ms    => delay_ms,
      counter_o   => counter_o,
      bit_a       => bit_a,
      bit_b       => bit_b
    );

  process
  begin
    -- Reset
    rst <= '1'; wait for 5 * CLK_P; rst <= '0'; wait for 2 * CLK_P;

    -- All channels start at BETWEEN (neutral)

    -- -----------------------------------------------------------------------
    -- Test 1: Rule 1 — ch0 falling crossing → counter(0) = 1
    --         ch1 also crosses (same stimulus) → counter(1) = 1
    --         ch2,3 unchanged
    -- -----------------------------------------------------------------------
    report "--- Test 1: Rule 1 falling crossing (ch0 & ch1) ---" severity note;
    data_in(0) <= ABOVE_T1;  data_in(1) <= ABOVE_T1;
    wait for 10 * CLK_P;
    data_in(0) <= BETWEEN;   data_in(1) <= BETWEEN;
    wait for 5 * CLK_P;

    chk16(counter_o(0), 1, "T1 ch0: counter=1");
    chk16(counter_o(1), 1, "T1 ch1: counter=1");
    chk16(counter_o(2), 0, "T1 ch2: counter=0 (untouched)");
    chk16(counter_o(3), 0, "T1 ch3: counter=0 (untouched)");
    chkbit(bit_b(0), '1', "T1 ch0: bit_b='1'");
    chkbit(bit_b(2), '0', "T1 ch2: bit_b='0'");

    -- -----------------------------------------------------------------------
    -- Test 2: Rule 1 — ch0 gets 3 more crossings → counter(0) = 4
    --         ch1 kept at BETWEEN (no crossings) → counter(1) stays 1
    -- -----------------------------------------------------------------------
    report "--- Test 2: ch0 multiple crossings, ch1 idle ---" severity note;
    for i in 1 to 3 loop
      data_in(0) <= ABOVE_T1;
      wait for 10 * CLK_P;
      data_in(0) <= BETWEEN;
      wait for 5 * CLK_P;
    end loop;

    chk16(counter_o(0), 4, "T2 ch0: counter=4");
    chk16(counter_o(1), 1, "T2 ch1: counter still 1");

    -- -----------------------------------------------------------------------
    -- Test 3: Rule 2 — ch0 stays above T1 for 6 ms → timeout, counter=0
    --         ch1 unaffected
    -- -----------------------------------------------------------------------
    report "--- Test 3: Rule 2 timeout (ch0 only) ---" severity note;
    data_in(0) <= ABOVE_T1;
    wait for 6 * MS;
    wait for 5 * CLK_P;

    chk16(counter_o(0), 0, "T3 ch0: counter=0 (timeout)");
    chkbit(bit_b(0), '0', "T3 ch0: bit_b='0'");
    chk16(counter_o(1), 1, "T3 ch1: counter still 1 (unaffected)");

    -- -----------------------------------------------------------------------
    -- Test 4: Rule 3 — ch0: below T2 → counter=0, bit_a latched
    --         ch1: unaffected
    -- -----------------------------------------------------------------------
    report "--- Test 4: Rule 3 below T2 (ch0 only) ---" severity note;
    -- Reset to clean slate then build ch0 counter to 2
    rst <= '1'; wait for 5 * CLK_P; rst <= '0';
    data_in(0) <= BETWEEN; data_in(1) <= BETWEEN;
    wait for 5 * CLK_P;

    for i in 1 to 2 loop
      data_in(0) <= ABOVE_T1; wait for 10 * CLK_P;
      data_in(0) <= BETWEEN;  wait for 5  * CLK_P;
    end loop;
    chk16(counter_o(0), 2, "T4 setup: ch0 counter=2");

    data_in(0) <= BELOW_T2;
    wait for 5 * CLK_P;

    chk16(counter_o(0), 0,  "T4 ch0: counter=0 after below-T2");
    chkbit(bit_a(0),    '1', "T4 ch0: bit_a latched '1'");
    chkbit(bit_b(0),    '0', "T4 ch0: bit_b='0'");
    chk16(counter_o(1), 0,  "T4 ch1: counter unchanged (0)");
    chkbit(bit_a(1),    '0', "T4 ch1: bit_a not affected");

    -- -----------------------------------------------------------------------
    -- Test 5: bit_a stays latched after data moves away from T2 region
    -- -----------------------------------------------------------------------
    report "--- Test 5: bit_a latched after event ---" severity note;
    data_in(0) <= BETWEEN;
    wait for 20 * CLK_P;
    chkbit(bit_a(0), '1', "T5 ch0: bit_a still '1'");

    -- -----------------------------------------------------------------------
    -- Test 6: rst clears all channels
    -- -----------------------------------------------------------------------
    report "--- Test 6: rst clears all channels ---" severity note;
    rst <= '1'; wait for 5 * CLK_P; rst <= '0'; wait for 5 * CLK_P;

    chk16(counter_o(0), 0, "T6 ch0: counter=0");
    chk16(counter_o(1), 0, "T6 ch1: counter=0");
    chk16(counter_o(2), 0, "T6 ch2: counter=0");
    chk16(counter_o(3), 0, "T6 ch3: counter=0");
    chkbit(bit_a(0), '0', "T6 ch0: bit_a='0' after rst");
    chkbit(bit_b(0), '0', "T6 ch0: bit_b='0' after rst");

    -- -----------------------------------------------------------------------
    -- Test 7: independent channels — ch2 and ch3 cross while ch0/ch1 idle
    -- -----------------------------------------------------------------------
    report "--- Test 7: ch2 and ch3 independent crossings ---" severity note;
    data_in <= (others => BETWEEN);
    wait for 5 * CLK_P;

    data_in(2) <= ABOVE_T1; data_in(3) <= ABOVE_T1;
    wait for 10 * CLK_P;
    data_in(2) <= BETWEEN;  data_in(3) <= BETWEEN;
    wait for 5 * CLK_P;

    chk16(counter_o(0), 0, "T7 ch0: counter=0 (untouched)");
    chk16(counter_o(1), 0, "T7 ch1: counter=0 (untouched)");
    chk16(counter_o(2), 1, "T7 ch2: counter=1");
    chk16(counter_o(3), 1, "T7 ch3: counter=1");

    -- -----------------------------------------------------------------------
    report "=== All tests done ===" severity note;
    std.env.stop;
  end process;

end architecture sim;
