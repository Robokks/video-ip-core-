library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Testbench: threshold_counter
--
-- Uses CLK_MHZ=1 so CLK_PER_MS = 1000 cycles (fast simulation).
-- Clock period = 10 ns  (100 MHz, but treated as "1 MHz" by the DUT generic)
--
-- Q4.12 helper values used:
--   T1 = 2.0  = 2 * 4096 = 8192  = x"2000"
--   T2 = 1.0  = 1 * 4096 = 4096  = x"1000"
--   ABOVE_T1  = 3.0  = 12288 = x"3000"   (data_in > T1)
--   BETWEEN   = 1.5  =  6144 = x"1800"   (T2 < data_in < T1, crossing region)
--   BELOW_T2  = 0.5  =  2048 = x"0800"   (data_in < T2)
--
-- Tests:
--   1 — Rule 1  : falling crossing increments counter
--   2 — Rule 2  : timeout resets counter
--   3 — Rule 3  : below T2 resets counter + latches bit_a
--   4 — bit_b   : mirrors counter != 0
--   5 — bit_a   : stays latched after T2 event; clears only on rst

entity tb_threshold_counter is
end entity;

architecture sim of tb_threshold_counter is

  -- DUT ports
  signal clk         : std_logic := '0';
  signal rst         : std_logic := '1';
  signal data_in     : std_logic_vector(15 downto 0) := (others => '0');
  signal threshold_1 : std_logic_vector(15 downto 0) := x"2000";  -- 2.0
  signal threshold_2 : std_logic_vector(15 downto 0) := x"1000";  -- 1.0
  signal delay_ms    : std_logic_vector(15 downto 0) := x"0005";  -- 5 ms
  signal counter_o   : std_logic_vector(15 downto 0);
  signal bit_a       : std_logic;
  signal bit_b       : std_logic;

  -- Clock period (10 ns → "1 MHz" with CLK_MHZ=1 → CLK_PER_MS=1000)
  constant CLK_P     : time    := 10 ns;
  constant MS        : time    := 1000 * CLK_P;  -- 1 simulated ms = 1000 cycles

  -- Q4.12 test levels
  constant ABOVE_T1  : std_logic_vector(15 downto 0) := x"3000";  -- 3.0
  constant BETWEEN   : std_logic_vector(15 downto 0) := x"1800";  -- 1.5
  constant BELOW_T2  : std_logic_vector(15 downto 0) := x"0800";  -- 0.5

  -- Pass/fail tracking
  signal pass_count  : integer := 0;
  signal fail_count  : integer := 0;

  procedure check(
    signal   actual   : in std_logic_vector(15 downto 0);
    constant expected : in integer;
    constant msg      : in string) is
  begin
    if to_integer(unsigned(actual)) = expected then
      report "PASS: " & msg severity note;
    else
      report "FAIL: " & msg &
             "  expected=" & integer'image(expected) &
             "  got="      & integer'image(to_integer(unsigned(actual)))
        severity error;
    end if;
  end procedure;

  procedure check_bit(
    signal   actual   : in std_logic;
    constant expected : in std_logic;
    constant msg      : in string) is
  begin
    if actual = expected then
      report "PASS: " & msg severity note;
    else
      report "FAIL: " & msg &
             "  expected=" & std_logic'image(expected) &
             "  got="      & std_logic'image(actual)
        severity error;
    end if;
  end procedure;

begin

  clk <= not clk after CLK_P / 2;

  u_dut : entity work.threshold_counter
    generic map (CLK_MHZ => 1)
    port map (
      clk         => clk,
      rst         => rst,
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
    -- -----------------------------------------------------------------------
    -- Reset
    -- -----------------------------------------------------------------------
    rst <= '1';
    data_in <= BETWEEN;
    wait for 5 * CLK_P;
    rst <= '0';
    wait for 2 * CLK_P;

    -- -----------------------------------------------------------------------
    -- Test 1: Rule 1 — single falling crossing → counter becomes 1
    -- -----------------------------------------------------------------------
    report "--- Test 1: Rule 1 falling crossing ---" severity note;

    data_in <= ABOVE_T1;              -- go above T1
    wait for 10 * CLK_P;             -- short pulse, well under 5 ms delay
    data_in <= BETWEEN;              -- cross back below T1
    wait for 5 * CLK_P;

    check(counter_o, 1, "Test1: counter=1 after one crossing");
    check_bit(bit_b, '1', "Test1: bit_b='1' when counter=1");

    -- -----------------------------------------------------------------------
    -- Test 2: Rule 1 — three more crossings → counter = 4
    -- -----------------------------------------------------------------------
    report "--- Test 2: multiple crossings ---" severity note;

    for i in 1 to 3 loop
      data_in <= ABOVE_T1;
      wait for 10 * CLK_P;
      data_in <= BETWEEN;
      wait for 5 * CLK_P;
    end loop;

    check(counter_o, 4, "Test2: counter=4 after 4 crossings");

    -- -----------------------------------------------------------------------
    -- Test 3: Rule 2 — stay above T1 for > 5 ms → counter resets to 0
    -- -----------------------------------------------------------------------
    report "--- Test 3: Rule 2 timeout reset ---" severity note;

    data_in <= ABOVE_T1;
    wait for 6 * MS;                 -- 6 ms > delay_ms=5 ms → timeout
    wait for 5 * CLK_P;

    check(counter_o, 0, "Test3: counter=0 after timeout");
    check_bit(bit_b, '0', "Test3: bit_b='0' when counter=0");

    -- -----------------------------------------------------------------------
    -- Test 4: Rule 3 — below T2 resets counter + latches bit_a
    -- -----------------------------------------------------------------------
    report "--- Test 4: Rule 3 below T2 ---" severity note;

    -- Clean slate before building counter
    rst <= '1'; wait for 5 * CLK_P; rst <= '0';
    data_in <= BETWEEN;
    wait for 5 * CLK_P;
    for i in 1 to 2 loop
      data_in <= ABOVE_T1;
      wait for 10 * CLK_P;
      data_in <= BETWEEN;
      wait for 5 * CLK_P;
    end loop;
    check(counter_o, 2, "Test4 setup: counter=2");

    -- Now drop below T2
    data_in <= BELOW_T2;
    wait for 5 * CLK_P;

    check(counter_o, 0,  "Test4: counter=0 after below-T2 event");
    check_bit(bit_a, '1', "Test4: bit_a latched '1'");
    check_bit(bit_b, '0', "Test4: bit_b='0' (counter=0)");

    -- -----------------------------------------------------------------------
    -- Test 5: bit_a stays latched after data moves away from T2 region
    -- -----------------------------------------------------------------------
    report "--- Test 5: bit_a stays latched ---" severity note;

    data_in <= BETWEEN;              -- move away from below-T2 region
    wait for 20 * CLK_P;

    check_bit(bit_a, '1', "Test5: bit_a still '1' (latched)");

    -- -----------------------------------------------------------------------
    -- Test 6: rst clears bit_a and counter
    -- -----------------------------------------------------------------------
    report "--- Test 6: rst clears everything ---" severity note;

    rst <= '1';
    wait for 5 * CLK_P;
    rst <= '0';
    wait for 5 * CLK_P;

    check(counter_o, 0,  "Test6: counter=0 after rst");
    check_bit(bit_a, '0', "Test6: bit_a='0' after rst");
    check_bit(bit_b, '0', "Test6: bit_b='0' after rst");

    -- -----------------------------------------------------------------------
    report "=== All tests done ===" severity note;
    std.env.stop;
  end process;

end architecture sim;
