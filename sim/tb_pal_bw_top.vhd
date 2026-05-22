library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Testbench for pal_bw_top.
-- Simulates a small in-process BRAM (all pixels white) and verifies:
--   * dac_out = "0000" during vsync lines
--   * dac_out = "0000" during H-sync pulses
--   * dac_out = "0100" during blanking
--   * dac_out = "1111" during active pixels (all-white BRAM)
-- Runs for 10 complete lines to cover blanking, first active lines, and timing checks.
entity tb_pal_bw_top is
end entity tb_pal_bw_top;

architecture sim of tb_pal_bw_top is

  -- DUT ports
  signal clk      : std_logic := '0';
  signal rst      : std_logic := '1';
  signal bram_clk : std_logic;
  signal bram_en  : std_logic;
  signal bram_we  : std_logic;
  signal bram_addr: std_logic_vector(18 downto 0);
  signal bram_din : std_logic := '1';   -- driven by BRAM model below
  signal dac_out  : std_logic_vector(3 downto 0);
  signal hsync_o  : std_logic;
  signal vsync_o  : std_logic;
  signal active_o : std_logic;

  constant CLK_PERIOD : time := 100 ns;  -- 10 MHz

  -- BRAM model: 299520 x 1-bit, all white
  constant BRAM_DEPTH : integer := 520 * 576;
  type bram_t is array (0 to BRAM_DEPTH - 1) of std_logic;
  signal mem : bram_t := (others => '1');

begin

  -- 10 MHz clock
  clk <= not clk after CLK_PERIOD / 2;

  -- 1-cycle-latency BRAM model (synchronous read, no write)
  process(bram_clk)
  begin
    if rising_edge(bram_clk) then
      if bram_en = '1' and bram_we = '0' then
        bram_din <= mem(to_integer(unsigned(bram_addr)));
      end if;
    end if;
  end process;

  -- DUT
  uut : entity work.pal_bw_top
    port map (
      clk      => clk,
      rst      => rst,
      bram_clk => bram_clk,
      bram_en  => bram_en,
      bram_we  => bram_we,
      bram_addr=> bram_addr,
      bram_din => bram_din,
      dac_out  => dac_out,
      hsync_o  => hsync_o,
      vsync_o  => vsync_o,
      active_o => active_o
    );

  -- Stimulus
  process
  begin
    rst <= '1';
    wait for 3 * CLK_PERIOD;
    rst <= '0';

    -- Run for 10 complete lines + a little extra
    wait for (10 * 640 + 50) * CLK_PERIOD;

    report "Simulation complete: 10 lines verified." severity note;
    std.env.finish;
  end process;

  -- Checker process: monitor dac_out vs sync flags
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '0' then
        -- During vsync the whole line must be at sync level
        if vsync_o = '1' then
          assert dac_out = "0000"
            report "FAIL: dac_out should be LEVEL_SYNC during vsync, got " &
                   integer'image(to_integer(unsigned(dac_out)))
            severity error;
        end if;

        -- During H-sync (and not vsync), output must be sync level
        if hsync_o = '1' and vsync_o = '0' then
          assert dac_out = "0000"
            report "FAIL: dac_out should be LEVEL_SYNC during hsync, got " &
                   integer'image(to_integer(unsigned(dac_out)))
            severity error;
        end if;

        -- During active with all-white BRAM, output must be white
        if active_o = '1' then
          assert dac_out = "1111"
            report "FAIL: dac_out should be LEVEL_WHITE during active pixel, got " &
                   integer'image(to_integer(unsigned(dac_out)))
            severity error;
        end if;

        -- During blanking (not active, not sync), output must be blank level
        if active_o = '0' and hsync_o = '0' and vsync_o = '0' then
          assert dac_out = "0100"
            report "FAIL: dac_out should be LEVEL_BLANK during blanking, got " &
                   integer'image(to_integer(unsigned(dac_out)))
            severity error;
        end if;
      end if;
    end if;
  end process;

end architecture sim;
