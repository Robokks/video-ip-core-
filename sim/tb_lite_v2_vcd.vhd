library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Testbench: pal_tv_bram_lite_v2 — generates VCD for GTKWave
-- Runs 2 complete PAL frames (625 lines × 640 pixels × 4 CLK_DIV clocks)
-- at CLK_MHZ=10 so 1 clock = 1 pixel (fastest sim, VCD stays small).
entity tb_lite_v2_vcd is
end entity tb_lite_v2_vcd;

architecture sim of tb_lite_v2_vcd is

  constant CLK_PERIOD : time    := 100 ns;  -- 10 MHz
  constant H_TOTAL    : integer := 640;
  constant V_TOTAL    : integer := 625;
  constant FRAMES     : integer := 2;
  constant SIM_CYCLES : integer := H_TOTAL * V_TOTAL * FRAMES + 100;

  signal clk         : std_logic := '0';
  signal rst         : std_logic := '1';
  signal sel         : std_logic_vector(7 downto 0) := x"01";  -- H-bars

  signal dac_out     : std_logic_vector(3 downto 0);
  signal csync_o     : std_logic;
  signal line_sync_o : std_logic;
  signal frame_sync_o: std_logic;
  signal fss_o       : std_logic;
  signal field_o     : std_logic;
  signal active_o    : std_logic;
  signal blank_o     : std_logic;

  signal ce_probe    : std_logic;

begin

  clk <= not clk after CLK_PERIOD / 2;

  -- Release reset after 5 clocks
  rst <= '0' after CLK_PERIOD * 5;

  uut : entity work.pal_tv_bram_lite_v2
    generic map (
      CLK_MHZ    => 10,
      BRAM_DEPTH => 1040
    )
    port map (
      clk          => clk,
      rst          => rst,
      sel          => sel,
      brightness   => "1111",
      black_lvl    => "0100",
      bram_wr_en   => '0',
      bram_wr_addr => (others => '0'),
      bram_wr_data => '0',
      bram_len     => (others => '1'),
      dac_out      => dac_out,
      csync_o      => csync_o,
      line_sync_o  => line_sync_o,
      frame_sync_o => frame_sync_o,
      fss_o        => fss_o,
      field_o      => field_o,
      active_o     => active_o,
      blank_o      => blank_o
    );

  -- Stop after 2 frames
  process
  begin
    wait for CLK_PERIOD * SIM_CYCLES;
    report "Simulation complete - 2 PAL frames captured." severity note;
    std.env.stop;
  end process;

end architecture sim;
