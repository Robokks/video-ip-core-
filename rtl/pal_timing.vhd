library ieee;
use ieee.std_logic_1164.all;

-- Free-running H/V line counters for PAL video timing.
-- Supports 10 / 20 / 30 / 40 MHz input clocks via CLK_MHZ generic.
-- An internal clock-enable divider (CLK_MHZ/10) keeps the effective
-- pixel rate at exactly 10 MHz regardless of the input clock chosen.
--
-- CLK_MHZ | CLK_DIV | Input clock | Source (cRIO-9056 base clocks)
-- --------+---------+-------------+-------------------------------
--   10    |    1    |   10 MHz    | 10 MHz base clock
--   20    |    2    |   20 MHz    | 20 MHz base clock
--   30    |    3    |   30 MHz    | external / PLL
--   40    |    4    |   40 MHz    | 40 MHz primary clock
entity pal_timing is
  generic (
    H_TOTAL : integer := 640;   -- effective clocks per line at 10 MHz pixel rate
    V_TOTAL : integer := 625;   -- lines per frame
    CLK_MHZ : integer := 10     -- input clock frequency: 10, 20, 30, or 40
  );
  port (
    clk   : in  std_logic;
    rst   : in  std_logic;       -- synchronous reset, active-high
    ce    : out std_logic;       -- clock enable: high once per 10 MHz pixel period
    h_cnt : out integer range 0 to 639;
    v_cnt : out integer range 0 to 624
  );
end entity pal_timing;

architecture rtl of pal_timing is

  constant CLK_DIV : integer := CLK_MHZ / 10;  -- 1, 2, 3, or 4

  -- div_cnt range covers the largest divisor (4-1=3)
  signal div_cnt : integer range 0 to 3 := 0;

  -- Combinational CE: high when it is time to advance the pixel counters
  signal ce_c : std_logic;

  signal h : integer range 0 to H_TOTAL - 1 := 0;
  signal v : integer range 0 to V_TOTAL - 1 := 0;

begin

  assert CLK_MHZ = 10 or CLK_MHZ = 20 or CLK_MHZ = 30 or CLK_MHZ = 40
    report "CLK_MHZ must be 10, 20, 30, or 40" severity failure;

  assert H_TOTAL > 0 and V_TOTAL > 0
    report "H_TOTAL and V_TOTAL must be positive" severity failure;

  -- CE fires on every cycle when CLK_DIV=1, otherwise when div_cnt reaches its top
  ce_c <= '1' when (CLK_DIV = 1) or (div_cnt = CLK_DIV - 1) else '0';

  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        div_cnt <= 0;
        h       <= 0;
        v       <= 0;
      else
        -- Advance the clock divider (synthesiser removes this when CLK_DIV=1)
        if CLK_DIV > 1 then
          if div_cnt = CLK_DIV - 1 then
            div_cnt <= 0;
          else
            div_cnt <= div_cnt + 1;
          end if;
        end if;

        -- H/V pixel counters advance only on CE
        if ce_c = '1' then
          if h = H_TOTAL - 1 then
            h <= 0;
            if v = V_TOTAL - 1 then
              v <= 0;
            else
              v <= v + 1;
            end if;
          else
            h <= h + 1;
          end if;
        end if;

      end if;
    end if;
  end process;

  ce    <= ce_c;
  h_cnt <= h;
  v_cnt <= v;

end architecture rtl;
