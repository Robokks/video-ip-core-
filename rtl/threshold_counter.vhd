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
--   │  counter_in   ──┐                                   │
--   │  prescaler_in ──┤  ┌──────────────────┐            │
--   │  ms_cnt_in    ──┼─►│ threshold_counter │──► bit_b  │
--   │  prev_above   ──┤  │  (comb only)     │            │
--   │  bit_a_in     ──┘  └──────┬───────────┘            │
--   │  data_in      ──►         │                         │
--   │  threshold_1  ──►  counter_out  ──►[Shift Reg]──┐  │
--   │  threshold_2  ──►  prescaler_out►[Shift Reg]──┐ │  │
--   │  delay_ms     ──►  ms_cnt_out  ──►[Shift Reg]─┤ │  │
--   │  clear        ──►  above_t1    ──►[Shift Reg]─┘ │  │
--   │                    bit_a_out   ──►[Shift Reg]───┘  │
--   └─────────────────────────────────────────────────────┘
--
-- Per-channel rules (priority: clear > Rule 3 > Rule 2 > Rule 1):
--
--   clear = '1'  →  counter = 0, bit_a = 0  (software reset)
--   Rule 1: falling edge of above_t1 → counter + 1 (wraps 65535→0)
--   Rule 2: data_in > T1 for > delay_ms ms → counter reset to 0
--   Rule 3: data_in < T2 → counter = 0, bit_a latched '1'
--   bit_b  = '1' when counter ≠ 0
--
-- Fixed-point: Q4.12 signed  (1 sign + 3 integer + 12 fractional bits)
-- Generic CLK_MHZ sets the ms prescaler threshold (10/20/30/40 supported)
-- ============================================================================

entity threshold_counter is
  generic (
    CLK_MHZ : integer := 40
  );
  port (
    -- ==================================================================
    -- Channel 0
    -- ==================================================================
    data_in_0      : in  std_logic_vector(15 downto 0);
    threshold_1_0  : in  std_logic_vector(15 downto 0);
    threshold_2_0  : in  std_logic_vector(15 downto 0);
    delay_ms_0     : in  std_logic_vector(15 downto 0);
    clear_0        : in  std_logic;
    -- state inputs (from LabVIEW shift registers)
    counter_in_0   : in  std_logic_vector(15 downto 0);
    prescaler_in_0 : in  std_logic_vector(15 downto 0);
    ms_cnt_in_0    : in  std_logic_vector(15 downto 0);
    prev_above_0   : in  std_logic;
    bit_a_in_0     : in  std_logic;
    -- next-state outputs (to LabVIEW shift registers)
    counter_out_0   : out std_logic_vector(15 downto 0);
    prescaler_out_0 : out std_logic_vector(15 downto 0);
    ms_cnt_out_0    : out std_logic_vector(15 downto 0);
    above_t1_0      : out std_logic;   -- → prev_above_0 next cycle
    bit_a_out_0     : out std_logic;   -- → bit_a_in_0 next cycle
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

begin

  -- =========================================================================
  -- Channel 0 — fully inlined combinational process
  -- (Vivado-compatible: only local variables, signal assignments at end)
  -- =========================================================================
  process(data_in_0, threshold_1_0, threshold_2_0, delay_ms_0, clear_0,
          counter_in_0, prescaler_in_0, ms_cnt_in_0, prev_above_0, bit_a_in_0)
    variable above, below, ms_tick : boolean;
    variable pre_v, cnt_v, ms_v    : unsigned(15 downto 0);
    variable cnt_nxt, pre_nxt,
             ms_nxt                : std_logic_vector(15 downto 0);
    variable at1_nxt, ba_nxt,
             bb_nxt                : std_logic;
  begin
    above   := signed(data_in_0) > signed(threshold_1_0);
    below   := signed(data_in_0) < signed(threshold_2_0);
    pre_v   := unsigned(prescaler_in_0);
    cnt_v   := unsigned(counter_in_0);
    ms_v    := unsigned(ms_cnt_in_0);
    ms_tick := above and (pre_v = PRE_MAX);

    if above then at1_nxt := '1'; else at1_nxt := '0'; end if;
    if cnt_v /= 0 then bb_nxt := '1'; else bb_nxt := '0'; end if;

    if above then
      if pre_v = PRE_MAX then pre_nxt := (others => '0');
      else                    pre_nxt := std_logic_vector(pre_v + 1);
      end if;
    else
      pre_nxt := (others => '0');
    end if;

    if clear_0 = '1' then
      cnt_nxt := (others => '0');
      ms_nxt  := (others => '0');
      ba_nxt  := '0';
    elsif below then
      cnt_nxt := (others => '0');
      ms_nxt  := (others => '0');
      ba_nxt  := '1';
    elsif above then
      cnt_nxt := counter_in_0;
      ba_nxt  := bit_a_in_0;
      if ms_tick then
        if ms_v + 1 >= unsigned(delay_ms_0) then
          cnt_nxt := (others => '0');
          ms_nxt  := (others => '0');
        else
          ms_nxt := std_logic_vector(ms_v + 1);
        end if;
      else
        ms_nxt := ms_cnt_in_0;
      end if;
    else
      ms_nxt  := (others => '0');
      ba_nxt  := bit_a_in_0;
      if prev_above_0 = '1' then
        cnt_nxt := std_logic_vector(cnt_v + 1);
      else
        cnt_nxt := counter_in_0;
      end if;
    end if;

    counter_out_0   <= cnt_nxt;
    prescaler_out_0 <= pre_nxt;
    ms_cnt_out_0    <= ms_nxt;
    above_t1_0      <= at1_nxt;
    bit_a_out_0     <= ba_nxt;
    bit_b_0         <= bb_nxt;
  end process;

  -- =========================================================================
  -- Channel 1
  -- =========================================================================
  process(data_in_1, threshold_1_1, threshold_2_1, delay_ms_1, clear_1,
          counter_in_1, prescaler_in_1, ms_cnt_in_1, prev_above_1, bit_a_in_1)
    variable above, below, ms_tick : boolean;
    variable pre_v, cnt_v, ms_v    : unsigned(15 downto 0);
    variable cnt_nxt, pre_nxt,
             ms_nxt                : std_logic_vector(15 downto 0);
    variable at1_nxt, ba_nxt,
             bb_nxt                : std_logic;
  begin
    above   := signed(data_in_1) > signed(threshold_1_1);
    below   := signed(data_in_1) < signed(threshold_2_1);
    pre_v   := unsigned(prescaler_in_1);
    cnt_v   := unsigned(counter_in_1);
    ms_v    := unsigned(ms_cnt_in_1);
    ms_tick := above and (pre_v = PRE_MAX);

    if above then at1_nxt := '1'; else at1_nxt := '0'; end if;
    if cnt_v /= 0 then bb_nxt := '1'; else bb_nxt := '0'; end if;

    if above then
      if pre_v = PRE_MAX then pre_nxt := (others => '0');
      else                    pre_nxt := std_logic_vector(pre_v + 1);
      end if;
    else
      pre_nxt := (others => '0');
    end if;

    if clear_1 = '1' then
      cnt_nxt := (others => '0');
      ms_nxt  := (others => '0');
      ba_nxt  := '0';
    elsif below then
      cnt_nxt := (others => '0');
      ms_nxt  := (others => '0');
      ba_nxt  := '1';
    elsif above then
      cnt_nxt := counter_in_1;
      ba_nxt  := bit_a_in_1;
      if ms_tick then
        if ms_v + 1 >= unsigned(delay_ms_1) then
          cnt_nxt := (others => '0');
          ms_nxt  := (others => '0');
        else
          ms_nxt := std_logic_vector(ms_v + 1);
        end if;
      else
        ms_nxt := ms_cnt_in_1;
      end if;
    else
      ms_nxt  := (others => '0');
      ba_nxt  := bit_a_in_1;
      if prev_above_1 = '1' then
        cnt_nxt := std_logic_vector(cnt_v + 1);
      else
        cnt_nxt := counter_in_1;
      end if;
    end if;

    counter_out_1   <= cnt_nxt;
    prescaler_out_1 <= pre_nxt;
    ms_cnt_out_1    <= ms_nxt;
    above_t1_1      <= at1_nxt;
    bit_a_out_1     <= ba_nxt;
    bit_b_1         <= bb_nxt;
  end process;

  -- =========================================================================
  -- Channel 2
  -- =========================================================================
  process(data_in_2, threshold_1_2, threshold_2_2, delay_ms_2, clear_2,
          counter_in_2, prescaler_in_2, ms_cnt_in_2, prev_above_2, bit_a_in_2)
    variable above, below, ms_tick : boolean;
    variable pre_v, cnt_v, ms_v    : unsigned(15 downto 0);
    variable cnt_nxt, pre_nxt,
             ms_nxt                : std_logic_vector(15 downto 0);
    variable at1_nxt, ba_nxt,
             bb_nxt                : std_logic;
  begin
    above   := signed(data_in_2) > signed(threshold_1_2);
    below   := signed(data_in_2) < signed(threshold_2_2);
    pre_v   := unsigned(prescaler_in_2);
    cnt_v   := unsigned(counter_in_2);
    ms_v    := unsigned(ms_cnt_in_2);
    ms_tick := above and (pre_v = PRE_MAX);

    if above then at1_nxt := '1'; else at1_nxt := '0'; end if;
    if cnt_v /= 0 then bb_nxt := '1'; else bb_nxt := '0'; end if;

    if above then
      if pre_v = PRE_MAX then pre_nxt := (others => '0');
      else                    pre_nxt := std_logic_vector(pre_v + 1);
      end if;
    else
      pre_nxt := (others => '0');
    end if;

    if clear_2 = '1' then
      cnt_nxt := (others => '0');
      ms_nxt  := (others => '0');
      ba_nxt  := '0';
    elsif below then
      cnt_nxt := (others => '0');
      ms_nxt  := (others => '0');
      ba_nxt  := '1';
    elsif above then
      cnt_nxt := counter_in_2;
      ba_nxt  := bit_a_in_2;
      if ms_tick then
        if ms_v + 1 >= unsigned(delay_ms_2) then
          cnt_nxt := (others => '0');
          ms_nxt  := (others => '0');
        else
          ms_nxt := std_logic_vector(ms_v + 1);
        end if;
      else
        ms_nxt := ms_cnt_in_2;
      end if;
    else
      ms_nxt  := (others => '0');
      ba_nxt  := bit_a_in_2;
      if prev_above_2 = '1' then
        cnt_nxt := std_logic_vector(cnt_v + 1);
      else
        cnt_nxt := counter_in_2;
      end if;
    end if;

    counter_out_2   <= cnt_nxt;
    prescaler_out_2 <= pre_nxt;
    ms_cnt_out_2    <= ms_nxt;
    above_t1_2      <= at1_nxt;
    bit_a_out_2     <= ba_nxt;
    bit_b_2         <= bb_nxt;
  end process;

  -- =========================================================================
  -- Channel 3
  -- =========================================================================
  process(data_in_3, threshold_1_3, threshold_2_3, delay_ms_3, clear_3,
          counter_in_3, prescaler_in_3, ms_cnt_in_3, prev_above_3, bit_a_in_3)
    variable above, below, ms_tick : boolean;
    variable pre_v, cnt_v, ms_v    : unsigned(15 downto 0);
    variable cnt_nxt, pre_nxt,
             ms_nxt                : std_logic_vector(15 downto 0);
    variable at1_nxt, ba_nxt,
             bb_nxt                : std_logic;
  begin
    above   := signed(data_in_3) > signed(threshold_1_3);
    below   := signed(data_in_3) < signed(threshold_2_3);
    pre_v   := unsigned(prescaler_in_3);
    cnt_v   := unsigned(counter_in_3);
    ms_v    := unsigned(ms_cnt_in_3);
    ms_tick := above and (pre_v = PRE_MAX);

    if above then at1_nxt := '1'; else at1_nxt := '0'; end if;
    if cnt_v /= 0 then bb_nxt := '1'; else bb_nxt := '0'; end if;

    if above then
      if pre_v = PRE_MAX then pre_nxt := (others => '0');
      else                    pre_nxt := std_logic_vector(pre_v + 1);
      end if;
    else
      pre_nxt := (others => '0');
    end if;

    if clear_3 = '1' then
      cnt_nxt := (others => '0');
      ms_nxt  := (others => '0');
      ba_nxt  := '0';
    elsif below then
      cnt_nxt := (others => '0');
      ms_nxt  := (others => '0');
      ba_nxt  := '1';
    elsif above then
      cnt_nxt := counter_in_3;
      ba_nxt  := bit_a_in_3;
      if ms_tick then
        if ms_v + 1 >= unsigned(delay_ms_3) then
          cnt_nxt := (others => '0');
          ms_nxt  := (others => '0');
        else
          ms_nxt := std_logic_vector(ms_v + 1);
        end if;
      else
        ms_nxt := ms_cnt_in_3;
      end if;
    else
      ms_nxt  := (others => '0');
      ba_nxt  := bit_a_in_3;
      if prev_above_3 = '1' then
        cnt_nxt := std_logic_vector(cnt_v + 1);
      else
        cnt_nxt := counter_in_3;
      end if;
    end if;

    counter_out_3   <= cnt_nxt;
    prescaler_out_3 <= pre_nxt;
    ms_cnt_out_3    <= ms_nxt;
    above_t1_3      <= at1_nxt;
    bit_a_out_3     <= ba_nxt;
    bit_b_3         <= bb_nxt;
  end process;

end architecture rtl;
