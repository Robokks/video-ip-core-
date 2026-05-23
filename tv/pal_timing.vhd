library ieee;
use ieee.std_logic_1164.all;

-- Free-running H/V line counters for PAL video timing.
-- Supports 10 / 20 / 30 / 40 MHz input clocks via CLK_MHZ generic.
-- An internal clock-enable divider (CLK_MHZ/10) keeps the effective
-- pixel rate at exactly 10 MHz regardless of the input clock chosen.
--
-- Shared by all three tv/ variants (opt1_crt50, opt2_interlaced, opt3_prog25).
entity pal_timing is
  generic (
    H_TOTAL : integer := 640;   -- effective clocks per line at 10 MHz pixel rate
    V_TOTAL : integer := 625;   -- lines per frame
    CLK_MHZ : integer := 10     -- input clock frequency: 10, 20, 30, or 40
  );
  port (
    clk   : in  std_logic;
    rst   : in  std_logic;
    ce    : out std_logic;
    h_cnt : out integer range 0 to 639;
    v_cnt : out integer range 0 to 624
  );
end entity pal_timing;

architecture rtl of pal_timing is

  constant CLK_DIV : integer := CLK_MHZ / 10;

  signal div_cnt : integer range 0 to 3 := 0;
  signal ce_c    : std_logic;
  signal h       : integer range 0 to H_TOTAL - 1 := 0;
  signal v       : integer range 0 to V_TOTAL - 1 := 0;

begin

  assert CLK_MHZ = 10 or CLK_MHZ = 20 or CLK_MHZ = 30 or CLK_MHZ = 40
    report "CLK_MHZ must be 10, 20, 30, or 40" severity failure;

  ce_c <= '1' when (CLK_DIV = 1) or (div_cnt = CLK_DIV - 1) else '0';

  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        div_cnt <= 0; h <= 0; v <= 0;
      else
        if CLK_DIV > 1 then
          if div_cnt = CLK_DIV - 1 then div_cnt <= 0;
          else div_cnt <= div_cnt + 1; end if;
        end if;
        if ce_c = '1' then
          if h = H_TOTAL - 1 then
            h <= 0;
            if v = V_TOTAL - 1 then v <= 0; else v <= v + 1; end if;
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
