library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.threshold_counter_pkg.all;

-- Threshold Counter IP  —  4-channel version
--
-- Each of the TC_NUM_CH (=4) channels operates independently with its own
-- data_in, threshold_1, threshold_2, delay_ms, counter_o, bit_a and bit_b.
--
-- Per-channel rules (priority: Rule 3 > Rule 2 > Rule 1):
--
--   Rule 1 (INCREMENT):
--     When data_in crosses from above threshold_1 to below threshold_1
--     (falling edge), counter increments by 1.  At 65535 it wraps to 0.
--
--   Rule 2 (TIMEOUT RESET):
--     If data_in stays continuously above threshold_1 for more than
--     delay_ms milliseconds, counter resets to 0.
--
--   Rule 3 (T2 RESET — highest priority):
--     Whenever data_in < threshold_2, counter resets to 0 and bit_a is
--     latched '1' (stays high until rst).
--
--   bit_b = '1' when counter /= 0,  '0' when counter = 0.
--
-- Fixed-point format: Q4.12 signed  (1 sign + 3 integer + 12 fractional bits)
-- Generic: CLK_MHZ  — input clock frequency (10 / 20 / 30 / 40)

entity threshold_counter is
  generic (
    CLK_MHZ : integer := 40
  );
  port (
    clk         : in  std_logic;
    rst         : in  std_logic;   -- synchronous reset, active-high

    -- Per-channel inputs (Q4.12 signed fixed-point)
    data_in     : in  word16_array_t;   -- signal values
    threshold_1 : in  word16_array_t;   -- upper threshold
    threshold_2 : in  word16_array_t;   -- lower threshold
    delay_ms    : in  word16_array_t;   -- timeout (integer ms, 0-65535)

    -- Per-channel outputs
    counter_o   : out word16_array_t;                         -- 16-bit counters
    bit_a       : out std_logic_vector(TC_NUM_CH-1 downto 0); -- T2 latch flags
    bit_b       : out std_logic_vector(TC_NUM_CH-1 downto 0)  -- counter-nonzero flags
  );
end entity threshold_counter;

architecture rtl of threshold_counter is

  constant CLK_PER_MS : integer := CLK_MHZ * 1000;   -- cycles per ms (40 000 at 40 MHz)

  -- -------------------------------------------------------------------------
  -- Per-channel internal signal arrays
  -- -------------------------------------------------------------------------
  type bool_array_t   is array (0 to TC_NUM_CH-1) of boolean;
  type uint16_array_t is array (0 to TC_NUM_CH-1) of unsigned(15 downto 0);
  type pre_array_t    is array (0 to TC_NUM_CH-1) of integer range 0 to CLK_PER_MS-1;
  type sl_array_t     is array (0 to TC_NUM_CH-1) of std_logic;

  signal above_t1   : bool_array_t;   -- data_in > threshold_1  (combinational)
  signal below_t2   : bool_array_t;   -- data_in < threshold_2  (combinational)
  signal ms_tick_c  : sl_array_t;     -- '1' once per ms while above_t1 (combinational)

  signal prescaler  : pre_array_t    := (others => 0);
  signal ms_counter : uint16_array_t := (others => (others => '0'));
  signal prev_above : std_logic_vector(TC_NUM_CH-1 downto 0) := (others => '0');
  signal counter_s  : uint16_array_t := (others => (others => '0'));
  signal bit_a_s    : std_logic_vector(TC_NUM_CH-1 downto 0) := (others => '0');

begin

  -- -------------------------------------------------------------------------
  -- Combinational: per-channel comparisons, ms tick, and output wiring
  -- -------------------------------------------------------------------------
  gen_comb : for i in 0 to TC_NUM_CH-1 generate
    above_t1(i)  <= signed(data_in(i)) > signed(threshold_1(i));
    below_t2(i)  <= signed(data_in(i)) < signed(threshold_2(i));
    ms_tick_c(i) <= '1' when (above_t1(i) and prescaler(i) = CLK_PER_MS-1) else '0';

    counter_o(i) <= std_logic_vector(counter_s(i));
    bit_a(i)     <= bit_a_s(i);
    bit_b(i)     <= '1' when counter_s(i) /= 0 else '0';
  end generate;

  -- -------------------------------------------------------------------------
  -- Clocked process — all 4 channels in a for-loop
  -- -------------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        prev_above  <= (others => '0');
        prescaler   <= (others => 0);
        ms_counter  <= (others => (others => '0'));
        counter_s   <= (others => (others => '0'));
        bit_a_s     <= (others => '0');

      else

        for i in 0 to TC_NUM_CH-1 loop

          -- Register above_t1 for falling-edge detection next cycle
          if above_t1(i) then
            prev_above(i) <= '1';
          else
            prev_above(i) <= '0';
          end if;

          -- Prescaler: counts while above_t1, resets otherwise
          if above_t1(i) then
            if prescaler(i) = CLK_PER_MS-1 then
              prescaler(i) <= 0;
            else
              prescaler(i) <= prescaler(i) + 1;
            end if;
          else
            prescaler(i) <= 0;
          end if;

          -- ---------------------------------------------------------------
          -- Rule priority: Rule 3 > Rule 2 > Rule 1
          -- ---------------------------------------------------------------
          if below_t2(i) then
            -- Rule 3: data_in < threshold_2
            counter_s(i)  <= (others => '0');
            bit_a_s(i)    <= '1';
            ms_counter(i) <= (others => '0');

          elsif above_t1(i) then
            -- data_in > threshold_1: run timeout timer
            if ms_tick_c(i) = '1' then
              if ms_counter(i) + 1 >= unsigned(delay_ms(i)) then
                -- Rule 2: timeout → reset counter
                counter_s(i)  <= (others => '0');
                ms_counter(i) <= (others => '0');
              else
                ms_counter(i) <= ms_counter(i) + 1;
              end if;
            end if;

          else
            -- data_in between threshold_2 and threshold_1
            ms_counter(i) <= (others => '0');   -- clear timer

            -- Rule 1: falling crossing
            if prev_above(i) = '1' then
              counter_s(i) <= counter_s(i) + 1;  -- wraps 65535 → 0
            end if;

          end if;

        end loop;

      end if;
    end if;
  end process;

end architecture rtl;
