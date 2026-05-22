library ieee;
use ieee.std_logic_1164.all;

-- Free-running H/V line counters for PAL video timing.
-- h_cnt wraps at H_TOTAL-1; v_cnt increments on each H wrap.
entity pal_timing is
  generic (
    H_TOTAL : integer := 640;   -- clocks per line  (64 us @ 10 MHz)
    V_TOTAL : integer := 625    -- lines per frame
  );
  port (
    clk   : in  std_logic;
    rst   : in  std_logic;      -- synchronous, active-high
    h_cnt : out integer range 0 to 639;
    v_cnt : out integer range 0 to 624
  );
end entity pal_timing;

architecture rtl of pal_timing is
  signal h : integer range 0 to H_TOTAL - 1 := 0;
  signal v : integer range 0 to V_TOTAL - 1 := 0;
begin

  assert H_TOTAL > 0 and V_TOTAL > 0
    report "H_TOTAL and V_TOTAL must be positive" severity failure;

  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        h <= 0;
        v <= 0;
      else
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
  end process;

  h_cnt <= h;
  v_cnt <= v;

end architecture rtl;
