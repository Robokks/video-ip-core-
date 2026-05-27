library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ============================================================================
-- Threshold Counter IP  —  4-channel, purely combinational
-- ============================================================================
-- Designed for LabVIEW FPGA *regular while loop* (no clock/reset ports).
-- Each loop iteration = one FPGA clock cycle.
--
-- The IP is a next-state function only.  State is stored in LabVIEW
-- shift registers and fed back to the _in ports every cycle:
--
--   ┌─────────────────────────────────────────────────────┐
--   │  LabVIEW While Loop                                 │
--   │                                                     │
--   │  counter_in ─────┐                                  │
--   │  prescaler_in ───┤                                  │
--   │  ms_cnt_in ──────┤   ┌──────────────────┐          │
--   │  prev_above ─────┼──►│ threshold_counter │──► bit_b │
--   │  bit_a_in ───────┤   │  (this IP, comb) │          │
--   │  data_in ────────┤   └────────┬─────────┘          │
--   │  threshold_1 ────┤            │                     │
--   │  threshold_2 ────┤   counter_out ──► [Shift Reg] ──┘
--   │  delay_ms ───────┘   prescaler_out ► [Shift Reg] ──┘
--   │  clear ──────────    ms_cnt_out ──► [Shift Reg] ──┘
--   │                      prev_above_out► [Shift Reg] ──┘
--   │                      bit_a_out ───► [Shift Reg] ──┘
--   └─────────────────────────────────────────────────────┘
--
-- Per-channel rules (priority: clear > Rule 3 > Rule 2 > Rule 1):
--
--   clear = '1'  →  counter = 0, bit_a = 0 (software reset)
--
--   Rule 1 (INCREMENT):
--     Falling edge of above_t1 (prev_above='1', data_in ≤ T1 now)
--     → counter increments by 1 (wraps 65535 → 0)
--
--   Rule 2 (TIMEOUT RESET):
--     data_in stays > threshold_1 for > delay_ms ms
--     → counter resets to 0
--
--   Rule 3 (T2 RESET — highest priority):
--     data_in < threshold_2  →  counter = 0, bit_a latched '1'
--
--   bit_b = '1' when counter /= 0
--
-- Fixed-point: Q4.12 signed  (1 sign + 3 integer + 12 fractional bits)
-- Generic CLK_MHZ sets the ms prescaler threshold (default 40 MHz)
-- ============================================================================

entity threshold_counter is
  generic (
    CLK_MHZ : integer := 40    -- board clock (10/20/30/40)
  );
  port (
    -- ==================================================================
    -- Channel 0
    -- ==================================================================
    -- Control / data inputs
    data_in_0      : in  std_logic_vector(15 downto 0);  -- Q4.12 sample
    threshold_1_0  : in  std_logic_vector(15 downto 0);  -- upper threshold
    threshold_2_0  : in  std_logic_vector(15 downto 0);  -- lower threshold
    delay_ms_0     : in  std_logic_vector(15 downto 0);  -- Rule-2 timeout (ms)
    clear_0        : in  std_logic;                       -- '1' = software reset

    -- State inputs  (wire from LabVIEW shift-register outputs)
    counter_in_0   : in  std_logic_vector(15 downto 0);
    prescaler_in_0 : in  std_logic_vector(15 downto 0);  -- ms prescaler
    ms_cnt_in_0    : in  std_logic_vector(15 downto 0);  -- ms elapsed counter
    prev_above_0   : in  std_logic;                       -- above_t1 last cycle
    bit_a_in_0     : in  std_logic;                       -- latched T2 flag

    -- Next-state outputs  (wire to LabVIEW shift-register inputs)
    counter_out_0   : out std_logic_vector(15 downto 0);
    prescaler_out_0 : out std_logic_vector(15 downto 0);
    ms_cnt_out_0    : out std_logic_vector(15 downto 0);
    above_t1_0      : out std_logic;   -- → feed back to prev_above_0
    bit_a_out_0     : out std_logic;   -- → feed back to bit_a_in_0
    bit_b_0         : out std_logic;   -- combinational display

    -- ==================================================================
    -- Channel 1
    -- ==================================================================
    data_in_1      : in  std_logic_vector(15 downto 0);
    threshold_1_1  : in  std_logic_vector(15 downto 0);
    threshold_2_1  : in  std_logic_vector(15 downto 0);
    delay_ms_1     : in  std_logic_vector(15 downto 0);
    clear_1        : in  std_logic;
    counter_in_1   : in  std_logic_vector(15 downto 0);
    prescaler_in_1 : in  std_logic_vector(15 downto 0);
    ms_cnt_in_1    : in  std_logic_vector(15 downto 0);
    prev_above_1   : in  std_logic;
    bit_a_in_1     : in  std_logic;
    counter_out_1   : out std_logic_vector(15 downto 0);
    prescaler_out_1 : out std_logic_vector(15 downto 0);
    ms_cnt_out_1    : out std_logic_vector(15 downto 0);
    above_t1_1      : out std_logic;
    bit_a_out_1     : out std_logic;
    bit_b_1         : out std_logic;

    -- ==================================================================
    -- Channel 2
    -- ==================================================================
    data_in_2      : in  std_logic_vector(15 downto 0);
    threshold_1_2  : in  std_logic_vector(15 downto 0);
    threshold_2_2  : in  std_logic_vector(15 downto 0);
    delay_ms_2     : in  std_logic_vector(15 downto 0);
    clear_2        : in  std_logic;
    counter_in_2   : in  std_logic_vector(15 downto 0);
    prescaler_in_2 : in  std_logic_vector(15 downto 0);
    ms_cnt_in_2    : in  std_logic_vector(15 downto 0);
    prev_above_2   : in  std_logic;
    bit_a_in_2     : in  std_logic;
    counter_out_2   : out std_logic_vector(15 downto 0);
    prescaler_out_2 : out std_logic_vector(15 downto 0);
    ms_cnt_out_2    : out std_logic_vector(15 downto 0);
    above_t1_2      : out std_logic;
    bit_a_out_2     : out std_logic;
    bit_b_2         : out std_logic;

    -- ==================================================================
    -- Channel 3
    -- ==================================================================
    data_in_3      : in  std_logic_vector(15 downto 0);
    threshold_1_3  : in  std_logic_vector(15 downto 0);
    threshold_2_3  : in  std_logic_vector(15 downto 0);
    delay_ms_3     : in  std_logic_vector(15 downto 0);
    clear_3        : in  std_logic;
    counter_in_3   : in  std_logic_vector(15 downto 0);
    prescaler_in_3 : in  std_logic_vector(15 downto 0);
    ms_cnt_in_3    : in  std_logic_vector(15 downto 0);
    prev_above_3   : in  std_logic;
    bit_a_in_3     : in  std_logic;
    counter_out_3   : out std_logic_vector(15 downto 0);
    prescaler_out_3 : out std_logic_vector(15 downto 0);
    ms_cnt_out_3    : out std_logic_vector(15 downto 0);
    above_t1_3      : out std_logic;
    bit_a_out_3     : out std_logic;
    bit_b_3         : out std_logic
  );
end entity threshold_counter;

architecture rtl of threshold_counter is

  constant CLK_PER_MS : integer := CLK_MHZ * 1000;
  constant PRE_MAX    : unsigned(15 downto 0) := to_unsigned(CLK_PER_MS - 1, 16);

  -- -------------------------------------------------------------------------
  -- Shared next-state procedure (called once per channel per iteration)
  -- All parameters are values (no signal class) so they work cleanly
  -- inside combinational processes.
  -- -------------------------------------------------------------------------
  procedure ch_next (
    -- inputs (constant class — read only inside procedure)
    data_in_p      : in  std_logic_vector(15 downto 0);
    threshold_1_p  : in  std_logic_vector(15 downto 0);
    threshold_2_p  : in  std_logic_vector(15 downto 0);
    delay_ms_p     : in  std_logic_vector(15 downto 0);
    clear_p        : in  std_logic;
    counter_in_p   : in  std_logic_vector(15 downto 0);
    prescaler_in_p : in  std_logic_vector(15 downto 0);
    ms_cnt_in_p    : in  std_logic_vector(15 downto 0);
    prev_above_p   : in  std_logic;
    bit_a_in_p     : in  std_logic;
    -- outputs declared as signal class so entity port signals can be passed
    signal counter_out_p   : out std_logic_vector(15 downto 0);
    signal prescaler_out_p : out std_logic_vector(15 downto 0);
    signal ms_cnt_out_p    : out std_logic_vector(15 downto 0);
    signal above_t1_p      : out std_logic;
    signal bit_a_out_p     : out std_logic;
    signal bit_b_p         : out std_logic
  ) is
    variable above   : boolean;
    variable below   : boolean;
    variable ms_tick : boolean;
    variable pre_v   : unsigned(15 downto 0);
    variable cnt_v   : unsigned(15 downto 0);
    variable ms_v    : unsigned(15 downto 0);
  begin
    -- Comparisons
    above   := signed(data_in_p) > signed(threshold_1_p);
    below   := signed(data_in_p) < signed(threshold_2_p);
    pre_v   := unsigned(prescaler_in_p);
    cnt_v   := unsigned(counter_in_p);
    ms_v    := unsigned(ms_cnt_in_p);
    ms_tick := above and (pre_v = PRE_MAX);

    -- above_t1 output (shift-register feedback for next cycle)
    if above then above_t1_p <= '1'; else above_t1_p <= '0'; end if;

    -- bit_b: combinational from current counter
    if cnt_v /= 0 then bit_b_p <= '1'; else bit_b_p <= '0'; end if;

    -- Prescaler next state
    if above then
      if pre_v = PRE_MAX then
        prescaler_out_p <= (others => '0');
      else
        prescaler_out_p <= std_logic_vector(pre_v + 1);
      end if;
    else
      prescaler_out_p <= (others => '0');
    end if;

    -- Rule priority: clear > Rule 3 > Rule 2 > Rule 1
    if clear_p = '1' then
      -- Software reset
      counter_out_p <= (others => '0');
      ms_cnt_out_p  <= (others => '0');
      bit_a_out_p   <= '0';

    elsif below then
      -- Rule 3: data_in < T2
      counter_out_p <= (others => '0');
      ms_cnt_out_p  <= (others => '0');
      bit_a_out_p   <= '1';

    elsif above then
      -- data_in > T1: run timeout timer (Rule 2)
      counter_out_p <= counter_in_p;
      bit_a_out_p   <= bit_a_in_p;
      if ms_tick then
        if ms_v + 1 >= unsigned(delay_ms_p) then
          -- Rule 2: timeout → reset counter
          counter_out_p <= (others => '0');
          ms_cnt_out_p  <= (others => '0');
        else
          ms_cnt_out_p <= std_logic_vector(ms_v + 1);
        end if;
      else
        ms_cnt_out_p <= ms_cnt_in_p;   -- hold timer
      end if;

    else
      -- T2 ≤ data_in ≤ T1
      ms_cnt_out_p <= (others => '0');   -- reset timer
      bit_a_out_p  <= bit_a_in_p;
      if prev_above_p = '1' then
        -- Rule 1: falling crossing → increment counter (wraps 65535→0)
        counter_out_p <= std_logic_vector(cnt_v + 1);
      else
        counter_out_p <= counter_in_p;
      end if;

    end if;
  end procedure ch_next;

begin

  -- =========================================================================
  -- Channel 0
  -- =========================================================================
  process(data_in_0, threshold_1_0, threshold_2_0, delay_ms_0, clear_0,
          counter_in_0, prescaler_in_0, ms_cnt_in_0, prev_above_0, bit_a_in_0)
  begin
    ch_next(data_in_0, threshold_1_0, threshold_2_0, delay_ms_0, clear_0,
            counter_in_0, prescaler_in_0, ms_cnt_in_0, prev_above_0, bit_a_in_0,
            counter_out_0, prescaler_out_0, ms_cnt_out_0,
            above_t1_0, bit_a_out_0, bit_b_0);
  end process;

  -- =========================================================================
  -- Channel 1
  -- =========================================================================
  process(data_in_1, threshold_1_1, threshold_2_1, delay_ms_1, clear_1,
          counter_in_1, prescaler_in_1, ms_cnt_in_1, prev_above_1, bit_a_in_1)
  begin
    ch_next(data_in_1, threshold_1_1, threshold_2_1, delay_ms_1, clear_1,
            counter_in_1, prescaler_in_1, ms_cnt_in_1, prev_above_1, bit_a_in_1,
            counter_out_1, prescaler_out_1, ms_cnt_out_1,
            above_t1_1, bit_a_out_1, bit_b_1);
  end process;

  -- =========================================================================
  -- Channel 2
  -- =========================================================================
  process(data_in_2, threshold_1_2, threshold_2_2, delay_ms_2, clear_2,
          counter_in_2, prescaler_in_2, ms_cnt_in_2, prev_above_2, bit_a_in_2)
  begin
    ch_next(data_in_2, threshold_1_2, threshold_2_2, delay_ms_2, clear_2,
            counter_in_2, prescaler_in_2, ms_cnt_in_2, prev_above_2, bit_a_in_2,
            counter_out_2, prescaler_out_2, ms_cnt_out_2,
            above_t1_2, bit_a_out_2, bit_b_2);
  end process;

  -- =========================================================================
  -- Channel 3
  -- =========================================================================
  process(data_in_3, threshold_1_3, threshold_2_3, delay_ms_3, clear_3,
          counter_in_3, prescaler_in_3, ms_cnt_in_3, prev_above_3, bit_a_in_3)
  begin
    ch_next(data_in_3, threshold_1_3, threshold_2_3, delay_ms_3, clear_3,
            counter_in_3, prescaler_in_3, ms_cnt_in_3, prev_above_3, bit_a_in_3,
            counter_out_3, prescaler_out_3, ms_cnt_out_3,
            above_t1_3, bit_a_out_3, bit_b_3);
  end process;

end architecture rtl;
