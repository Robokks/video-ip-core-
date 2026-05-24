library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Self-checking testbench for BRAM double-buffering
--
-- Sequence of events:
--   Phase 1: Write pattern A (all WHITE) to back buffer (buf 1).
--            Display shows buf 0 = all BLACK (initial state).
--   Phase 2: Pulse buf_swap; wait for buf_swapped strobe.
--            Verify displayed image is now all WHITE (buf 1 became front).
--            Verify back_buf_o = '1' -> '0' (back buffer is now buf 0).
--   Phase 3: Write pattern B (alternating by pixel: WHITE on even px) to new back (buf 0).
--            Pulse buf_swap; wait for strobe.
--            Verify first pixel of a line = WHITE (px 0 even), second = BLACK (px 1 odd).
--   Phase 4: Rapid successive swap requests -- only one swap per V-blank.
--            Write white to back; request swap twice before V-blank; only one swap occurs.

entity tb_bram_double_buf is
end entity tb_bram_double_buf;

architecture sim of tb_bram_double_buf is

  constant CLK_MHZ   : integer := 10;
  constant CLK_P     : time    := 100 ns;
  constant BRAM_D    : integer := 1040;    -- two rows (fast sim)

  constant H_FRONT   : integer := 16;
  constant H_SYNC_W  : integer := 47;
  constant H_BACK    : integer := 57;
  constant H_ACTIVE  : integer := 520;
  constant H_TOTAL   : integer := 640;
  constant V_ACT_S_F1: integer := 24;
  constant V_ACT_E_F1: integer := 311;
  constant V_ACT_S_F2: integer := 336;
  constant V_ACT_E_F2: integer := 623;

  constant LEVEL_WHITE : std_logic_vector(3 downto 0) := "1111";
  constant LEVEL_BLACK : std_logic_vector(3 downto 0) := "0100";

  signal clk          : std_logic := '0';
  signal rst          : std_logic := '1';
  signal sel          : std_logic_vector(7 downto 0) := x"04";
  signal bram_wr_en   : std_logic := '0';
  signal bram_wr_addr : std_logic_vector(18 downto 0) := (others => '0');
  signal bram_wr_data : std_logic := '0';
  signal bram_len     : std_logic_vector(18 downto 0) := std_logic_vector(to_unsigned(BRAM_D, 19));
  signal buf_swap     : std_logic := '0';
  signal buf_swapped  : std_logic;
  signal back_buf_o   : std_logic;
  signal dac_out      : std_logic_vector(3 downto 0);
  signal csync_o      : std_logic;
  signal line_sync_o  : std_logic;
  signal frame_sync_o : std_logic;
  signal field_o      : std_logic;
  signal active_o     : std_logic;
  signal blank_o      : std_logic;

  -- Wait until the start of a specific field's first active pixel (px 0, line 0)
  procedure next_f1_line(
      signal clk      : in std_logic;
      signal active_o : in std_logic;
      signal field_o  : in std_logic) is
  begin
    while active_o = '1' loop
      wait until rising_edge(clk);
    end loop;
    while not (active_o = '1' and field_o = '0') loop
      wait until rising_edge(clk);
    end loop;
  end procedure;

  -- Write val to every address in [0, count)
  procedure fill_bram(
      constant count     : in  integer;
      constant val       : in  std_logic;
      signal   clk       : in  std_logic;
      signal   wr_en     : out std_logic;
      signal   wr_addr   : out std_logic_vector(18 downto 0);
      signal   wr_data   : out std_logic) is
  begin
    for i in 0 to count - 1 loop
      wr_addr <= std_logic_vector(to_unsigned(i, 19));
      wr_data <= val;
      wr_en   <= '1';
      wait until rising_edge(clk);
    end loop;
    wr_en <= '0';
    wait until rising_edge(clk);
  end procedure;

  -- Write alternating 1/0 pattern: addr 0='1', addr 1='0', ...
  procedure fill_bram_alt(
      constant count     : in  integer;
      signal   clk       : in  std_logic;
      signal   wr_en     : out std_logic;
      signal   wr_addr   : out std_logic_vector(18 downto 0);
      signal   wr_data   : out std_logic) is
  begin
    for i in 0 to count - 1 loop
      wr_addr <= std_logic_vector(to_unsigned(i, 19));
      wr_data <= '1' when i mod 2 = 0 else '0';
      wr_en   <= '1';
      wait until rising_edge(clk);
    end loop;
    wr_en <= '0';
    wait until rising_edge(clk);
  end procedure;

begin

  clk <= not clk after CLK_P / 2;

  dut : entity work.pal_tv_bram_top
    generic map (
      CLK_MHZ    => CLK_MHZ,
      BRAM_DEPTH => BRAM_D)
    port map (
      clk          => clk,
      rst          => rst,
      sel          => sel,
      bram_wr_en   => bram_wr_en,
      bram_wr_addr => bram_wr_addr,
      bram_wr_data => bram_wr_data,
      bram_len     => bram_len,
      buf_swap     => buf_swap,
      buf_swapped  => buf_swapped,
      back_buf_o   => back_buf_o,
      dac_out      => dac_out,
      csync_o      => csync_o,
      line_sync_o  => line_sync_o,
      frame_sync_o => frame_sync_o,
      field_o      => field_o,
      active_o     => active_o,
      blank_o      => blank_o
    );

  -- -------------------------------------------------------------------------
  stimulus : process
    variable ok : boolean;
  begin
    rst <= '1'; wait for 5 * CLK_P; rst <= '0';

    -- =========================================================================
    -- Phase 1:  Back buffer (buf 1) starts empty (BLACK).
    --           Write ALL WHITE to back buffer.
    --           Display (buf 0) is still all BLACK.
    -- =========================================================================
    -- Verify initial back_buf_o = '1'  (buf 0 is front, buf 1 is back)
    wait until rising_edge(clk);
    if back_buf_o = '1' then
      report "  Ph1 PASS: initial back_buf_o = 1 (buf 0 displayed)" severity note;
    else
      report "!!! Ph1 FAIL: expected back_buf_o=1 after reset" severity failure;
    end if;

    -- Write all WHITE to back buffer (buf 1, addresses 0..BRAM_D-1)
    fill_bram(BRAM_D, '1', clk, bram_wr_en, bram_wr_addr, bram_wr_data);
    report "  Ph1: back buffer filled with WHITE" severity note;

    -- Verify display is still BLACK (buf 0 unchanged)
    next_f1_line(clk, active_o, field_o);
    ok := true;
    for p in 0 to H_ACTIVE - 1 loop
      if dac_out /= LEVEL_BLACK then ok := false; end if;
      wait until rising_edge(clk);
    end loop;
    if ok then
      report "  Ph1 PASS: display still BLACK before swap (buf 0 = initial)" severity note;
    else
      report "!!! Ph1 FAIL: display should be BLACK (buf 0 not yet swapped)" severity failure;
    end if;

    -- =========================================================================
    -- Phase 2:  Pulse buf_swap; wait for buf_swapped strobe at next V-blank.
    --           After swap: buf 1 is front (WHITE), buf 0 is back.
    -- =========================================================================
    buf_swap <= '1'; wait until rising_edge(clk); buf_swap <= '0';

    -- Wait for buf_swapped strobe
    wait until buf_swapped = '1';
    report "  Ph2: buf_swapped strobe received" severity note;

    -- Verify back_buf_o is now '0'  (buf 1 is displayed, buf 0 is back)
    if back_buf_o = '0' then
      report "  Ph2 PASS: back_buf_o = 0 after swap (buf 1 now displayed)" severity note;
    else
      report "!!! Ph2 FAIL: expected back_buf_o=0 after swap" severity failure;
    end if;

    -- Verify display is now WHITE
    next_f1_line(clk, active_o, field_o);
    ok := true;
    for p in 0 to H_ACTIVE - 1 loop
      if dac_out /= LEVEL_WHITE then ok := false; end if;
      wait until rising_edge(clk);
    end loop;
    if ok then
      report "=== Ph2 PASS: display shows WHITE after swap ===" severity note;
    else
      report "!!! Ph2 FAIL: display should be WHITE after swap" severity failure;
    end if;

    -- =========================================================================
    -- Phase 3:  Write alternating pattern to new back buffer (buf 0).
    --           Swap and verify pixel-by-pixel.
    -- =========================================================================
    fill_bram_alt(BRAM_D, clk, bram_wr_en, bram_wr_addr, bram_wr_data);
    report "  Ph3: back buffer filled with alternating pattern" severity note;

    buf_swap <= '1'; wait until rising_edge(clk); buf_swap <= '0';
    wait until buf_swapped = '1';
    report "  Ph3: swap strobe received" severity note;

    if back_buf_o = '1' then
      report "  Ph3 PASS: back_buf_o = 1 (buf 0 now displayed)" severity note;
    else
      report "!!! Ph3 FAIL: expected back_buf_o=1 after second swap" severity failure;
    end if;

    next_f1_line(clk, active_o, field_o);
    -- px 0 = addr 0 = WHITE
    if dac_out = LEVEL_WHITE then
      report "  Ph3a PASS: px0 = WHITE (addr 0 = 1)" severity note;
    else
      report "!!! Ph3a FAIL: px0 expected WHITE" severity failure;
    end if;
    wait until rising_edge(clk);  -- px 1
    if dac_out = LEVEL_BLACK then
      report "  Ph3b PASS: px1 = BLACK (addr 1 = 0)" severity note;
    else
      report "!!! Ph3b FAIL: px1 expected BLACK" severity failure;
    end if;
    wait until rising_edge(clk);  -- px 2
    if dac_out = LEVEL_WHITE then
      report "=== Ph3 PASS: alternating pattern confirmed after second swap ===" severity note;
    else
      report "!!! Ph3c FAIL: px2 expected WHITE" severity failure;
    end if;

    -- =========================================================================
    -- Phase 4:  Two swap requests before V-blank -- only one swap occurs.
    -- =========================================================================
    -- Write WHITE to new back buffer (buf 1)
    fill_bram(BRAM_D, '1', clk, bram_wr_en, bram_wr_addr, bram_wr_data);
    -- Request swap twice in quick succession
    buf_swap <= '1'; wait until rising_edge(clk); buf_swap <= '0';
    wait until rising_edge(clk);
    buf_swap <= '1'; wait until rising_edge(clk); buf_swap <= '0';
    -- Expect exactly one strobe
    wait until buf_swapped = '1';
    report "  Ph4: first swap strobe" severity note;
    -- Confirm no second strobe within the same frame
    wait for 10 * CLK_P;
    if buf_swapped = '0' then
      report "=== Ph4 PASS: only one swap per V-blank (no second strobe) ===" severity note;
    else
      report "!!! Ph4 FAIL: unexpected second swap strobe" severity failure;
    end if;

    report "=== tb_bram_double_buf: all phases complete ===" severity note;
    std.env.finish;
  end process;

end architecture sim;
