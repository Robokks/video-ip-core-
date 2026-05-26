library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Threshold Counter IP
-- Monitors a Q4.12 signed fixed-point input against two thresholds.
--
-- Rule 1 (INCREMENT):
--   When data_in crosses from above threshold_1 to below threshold_1
--   (falling edge), counter is incremented by 1.
--
-- Rule 2 (TIMEOUT RESET):
--   If data_in stays continuously above threshold_1 for more than
--   delay_ms milliseconds, counter is reset to 0.
--
-- Rule 3 (THRESHOLD-2 RESET — highest priority):
--   Whenever data_in < threshold_2, counter is reset to 0 and
--   bit_a is latched high (remains '1' until rst).
--
-- bit_b is a combinational flag:
--   bit_b = '1'  when counter /= 0
--   bit_b = '0'  when counter  = 0
--
-- Priority when rules overlap: Rule 3 > Rule 2 > Rule 1
--
-- Generics:
--   CLK_MHZ : input clock frequency (10 / 20 / 30 / 40)
--
-- Fixed-point format: Q4.12 signed
--   Bit 15        : sign
--   Bits 14..12   : integer part  (3 bits, range -8 to +7)
--   Bits 11..0    : fractional part (resolution = 1/4096 ≈ 0.000244)

entity threshold_counter is
  generic (
    CLK_MHZ : integer := 40          -- input clock frequency in MHz
  );
  port (
    clk         : in  std_logic;     -- input clock
    rst         : in  std_logic;     -- synchronous reset, active-high

    -- Signal input and thresholds (Q4.12 signed fixed-point)
    data_in     : in  std_logic_vector(15 downto 0);
    threshold_1 : in  std_logic_vector(15 downto 0);
    threshold_2 : in  std_logic_vector(15 downto 0);

    -- Timeout: counter resets if data_in stays > threshold_1 for this many ms
    delay_ms    : in  std_logic_vector(15 downto 0);

    -- Outputs
    counter_o   : out std_logic_vector(15 downto 0); -- 16-bit event counter
    bit_a       : out std_logic;  -- latched '1' when data_in < threshold_2
    bit_b       : out std_logic   -- '1' when counter /= 0
  );
end entity threshold_counter;

architecture rtl of threshold_counter is

  -- Clock cycles per millisecond
  constant CLK_PER_MS : integer := CLK_MHZ * 1000;

  -- -------------------------------------------------------------------------
  -- Combinational threshold comparisons (signed Q4.12)
  -- -------------------------------------------------------------------------
  signal above_t1 : boolean;   -- data_in >  threshold_1
  signal below_t2 : boolean;   -- data_in <  threshold_2

  -- -------------------------------------------------------------------------
  -- Millisecond tick generation
  -- Prescaler counts CLK_PER_MS cycles while above_t1; ms_tick_c pulses once
  -- per ms during that period.
  -- -------------------------------------------------------------------------
  signal prescaler  : integer range 0 to CLK_PER_MS - 1 := 0;
  signal ms_tick_c  : std_logic;   -- combinational: '1' for 1 clock each ms

  -- Elapsed-ms counter (counts how long data_in has been above threshold_1)
  signal ms_counter : unsigned(15 downto 0) := (others => '0');

  -- -------------------------------------------------------------------------
  -- Registered signals
  -- -------------------------------------------------------------------------
  signal prev_above : std_logic              := '0';  -- above_t1 one cycle ago
  signal counter_s  : unsigned(15 downto 0) := (others => '0');
  signal bit_a_s    : std_logic              := '0';

begin

  -- -------------------------------------------------------------------------
  -- Combinational
  -- -------------------------------------------------------------------------
  above_t1  <= signed(data_in) > signed(threshold_1);
  below_t2  <= signed(data_in) < signed(threshold_2);

  -- ms_tick fires once per ms when prescaler reaches its top while above_t1
  ms_tick_c <= '1' when (above_t1 and prescaler = CLK_PER_MS - 1) else '0';

  -- -------------------------------------------------------------------------
  -- Main clocked process
  -- -------------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        prev_above <= '0';
        prescaler  <= 0;
        ms_counter <= (others => '0');
        counter_s  <= (others => '0');
        bit_a_s    <= '0';

      else
        -- Register above_t1 for falling-edge detection in the next cycle
        if above_t1 then
          prev_above <= '1';
        else
          prev_above <= '0';
        end if;

        -- Prescaler: counts while above_t1, resets when not above_t1
        if above_t1 then
          if prescaler = CLK_PER_MS - 1 then
            prescaler <= 0;
          else
            prescaler <= prescaler + 1;
          end if;
        else
          prescaler <= 0;
        end if;

        -- -------------------------------------------------------------------
        -- Rule priority: Rule 3 > Rule 2 > Rule 1
        -- -------------------------------------------------------------------

        if below_t2 then
          -- Rule 3 (highest priority)
          -- data_in < threshold_2 → reset counter, latch bit_a, clear timer
          counter_s  <= (others => '0');
          bit_a_s    <= '1';
          ms_counter <= (others => '0');

        elsif above_t1 then
          -- data_in > threshold_1 → run timeout timer
          if ms_tick_c = '1' then
            if ms_counter + 1 >= unsigned(delay_ms) then
              -- Rule 2: timeout → reset counter, restart timer
              counter_s  <= (others => '0');
              ms_counter <= (others => '0');
            else
              ms_counter <= ms_counter + 1;
            end if;
          end if;

        else
          -- data_in is between threshold_2 and threshold_1 (inclusive)
          -- Clear elapsed-ms timer
          ms_counter <= (others => '0');

          -- Rule 1: falling crossing — was above T1, now below T1
          if prev_above = '1' then
            counter_s <= counter_s + 1;  -- wraps 65535 → 0
          end if;

        end if;

      end if;
    end if;
  end process;

  -- -------------------------------------------------------------------------
  -- Output drivers
  -- -------------------------------------------------------------------------
  counter_o <= std_logic_vector(counter_s);
  bit_a     <= bit_a_s;
  bit_b     <= '1' when counter_s /= 0 else '0';

end architecture rtl;
