library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.threshold_counter_pkg.all;

-- Threshold Counter IP  —  4-channel version
--
-- LabVIEW FPGA IP Integration Node requires ALL ports to be std_logic or
-- std_logic_vector.  Array-type ports are therefore expanded into four
-- individual std_logic_vector(15 downto 0) signals per bus, named _0 .. _3.
-- Internally the architecture still uses word16_array_t for conciseness.
--
-- Port naming convention:
--   <signal>_<channel>   e.g.  data_in_0, counter_o_2, bit_a_1
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
    clk : in  std_logic;
    rst : in  std_logic;   -- synchronous reset, active-high

    -- Channel 0 (Q4.12 signed fixed-point)
    data_in_0     : in  std_logic_vector(15 downto 0);
    threshold_1_0 : in  std_logic_vector(15 downto 0);
    threshold_2_0 : in  std_logic_vector(15 downto 0);
    delay_ms_0    : in  std_logic_vector(15 downto 0);
    counter_o_0   : out std_logic_vector(15 downto 0);
    bit_a_0       : out std_logic;
    bit_b_0       : out std_logic;

    -- Channel 1
    data_in_1     : in  std_logic_vector(15 downto 0);
    threshold_1_1 : in  std_logic_vector(15 downto 0);
    threshold_2_1 : in  std_logic_vector(15 downto 0);
    delay_ms_1    : in  std_logic_vector(15 downto 0);
    counter_o_1   : out std_logic_vector(15 downto 0);
    bit_a_1       : out std_logic;
    bit_b_1       : out std_logic;

    -- Channel 2
    data_in_2     : in  std_logic_vector(15 downto 0);
    threshold_1_2 : in  std_logic_vector(15 downto 0);
    threshold_2_2 : in  std_logic_vector(15 downto 0);
    delay_ms_2    : in  std_logic_vector(15 downto 0);
    counter_o_2   : out std_logic_vector(15 downto 0);
    bit_a_2       : out std_logic;
    bit_b_2       : out std_logic;

    -- Channel 3
    data_in_3     : in  std_logic_vector(15 downto 0);
    threshold_1_3 : in  std_logic_vector(15 downto 0);
    threshold_2_3 : in  std_logic_vector(15 downto 0);
    delay_ms_3    : in  std_logic_vector(15 downto 0);
    counter_o_3   : out std_logic_vector(15 downto 0);
    bit_a_3       : out std_logic;
    bit_b_3       : out std_logic
  );
end entity threshold_counter;

architecture rtl of threshold_counter is

  constant CLK_PER_MS : integer := CLK_MHZ * 1000;   -- cycles per ms (40 000 at 40 MHz)

  -- -------------------------------------------------------------------------
  -- Gather flat ports into internal arrays (only std_logic_vector at the
  -- boundary; arrays are an implementation detail)
  -- -------------------------------------------------------------------------
  signal data_in_s     : word16_array_t;
  signal threshold_1_s : word16_array_t;
  signal threshold_2_s : word16_array_t;
  signal delay_ms_s    : word16_array_t;
  signal counter_s_slv : word16_array_t;
  signal bit_a_s_vec   : std_logic_vector(TC_NUM_CH-1 downto 0);
  signal bit_b_s_vec   : std_logic_vector(TC_NUM_CH-1 downto 0);

  -- -------------------------------------------------------------------------
  -- Per-channel internal signals
  -- -------------------------------------------------------------------------
  type bool_array_t   is array (0 to TC_NUM_CH-1) of boolean;
  type uint16_array_t is array (0 to TC_NUM_CH-1) of unsigned(15 downto 0);
  type pre_array_t    is array (0 to TC_NUM_CH-1) of integer range 0 to CLK_PER_MS-1;
  type sl_array_t     is array (0 to TC_NUM_CH-1) of std_logic;

  signal above_t1   : bool_array_t;
  signal below_t2   : bool_array_t;
  signal ms_tick_c  : sl_array_t;

  signal prescaler  : pre_array_t    := (others => 0);
  signal ms_counter : uint16_array_t := (others => (others => '0'));
  signal prev_above : std_logic_vector(TC_NUM_CH-1 downto 0) := (others => '0');
  signal counter_s  : uint16_array_t := (others => (others => '0'));
  signal bit_a_lat  : std_logic_vector(TC_NUM_CH-1 downto 0) := (others => '0');

begin

  -- -------------------------------------------------------------------------
  -- Port fan-in: flat ports → internal arrays
  -- -------------------------------------------------------------------------
  data_in_s(0)     <= data_in_0;     data_in_s(1)     <= data_in_1;
  data_in_s(2)     <= data_in_2;     data_in_s(3)     <= data_in_3;

  threshold_1_s(0) <= threshold_1_0; threshold_1_s(1) <= threshold_1_1;
  threshold_1_s(2) <= threshold_1_2; threshold_1_s(3) <= threshold_1_3;

  threshold_2_s(0) <= threshold_2_0; threshold_2_s(1) <= threshold_2_1;
  threshold_2_s(2) <= threshold_2_2; threshold_2_s(3) <= threshold_2_3;

  delay_ms_s(0)    <= delay_ms_0;    delay_ms_s(1)    <= delay_ms_1;
  delay_ms_s(2)    <= delay_ms_2;    delay_ms_s(3)    <= delay_ms_3;

  -- -------------------------------------------------------------------------
  -- Port fan-out: internal arrays → flat ports
  -- -------------------------------------------------------------------------
  counter_o_0 <= counter_s_slv(0);  counter_o_1 <= counter_s_slv(1);
  counter_o_2 <= counter_s_slv(2);  counter_o_3 <= counter_s_slv(3);

  bit_a_0 <= bit_a_s_vec(0);  bit_a_1 <= bit_a_s_vec(1);
  bit_a_2 <= bit_a_s_vec(2);  bit_a_3 <= bit_a_s_vec(3);

  bit_b_0 <= bit_b_s_vec(0);  bit_b_1 <= bit_b_s_vec(1);
  bit_b_2 <= bit_b_s_vec(2);  bit_b_3 <= bit_b_s_vec(3);

  -- -------------------------------------------------------------------------
  -- Combinational: per-channel comparisons, ms tick, output wiring
  -- -------------------------------------------------------------------------
  gen_comb : for i in 0 to TC_NUM_CH-1 generate
    above_t1(i)      <= signed(data_in_s(i)) > signed(threshold_1_s(i));
    below_t2(i)      <= signed(data_in_s(i)) < signed(threshold_2_s(i));
    ms_tick_c(i)     <= '1' when (above_t1(i) and prescaler(i) = CLK_PER_MS-1) else '0';
    counter_s_slv(i) <= std_logic_vector(counter_s(i));
    bit_a_s_vec(i)   <= bit_a_lat(i);
    bit_b_s_vec(i)   <= '1' when counter_s(i) /= 0 else '0';
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
        bit_a_lat   <= (others => '0');

      else

        for i in 0 to TC_NUM_CH-1 loop

          -- Register above_t1 for falling-edge detection next cycle
          if above_t1(i) then prev_above(i) <= '1';
          else                 prev_above(i) <= '0';
          end if;

          -- Prescaler: counts while above_t1, resets otherwise
          if above_t1(i) then
            if prescaler(i) = CLK_PER_MS-1 then prescaler(i) <= 0;
            else                                 prescaler(i) <= prescaler(i) + 1;
            end if;
          else
            prescaler(i) <= 0;
          end if;

          -- Rule priority: Rule 3 > Rule 2 > Rule 1
          if below_t2(i) then
            -- Rule 3: data_in < threshold_2
            counter_s(i)  <= (others => '0');
            bit_a_lat(i)  <= '1';
            ms_counter(i) <= (others => '0');

          elsif above_t1(i) then
            -- data_in > threshold_1: run timeout timer
            if ms_tick_c(i) = '1' then
              if ms_counter(i) + 1 >= unsigned(delay_ms_s(i)) then
                counter_s(i)  <= (others => '0');   -- Rule 2: timeout
                ms_counter(i) <= (others => '0');
              else
                ms_counter(i) <= ms_counter(i) + 1;
              end if;
            end if;

          else
            -- data_in between threshold_2 and threshold_1
            ms_counter(i) <= (others => '0');
            if prev_above(i) = '1' then
              counter_s(i) <= counter_s(i) + 1;     -- Rule 1: falling crossing
            end if;

          end if;

        end loop;

      end if;
    end if;
  end process;

end architecture rtl;
