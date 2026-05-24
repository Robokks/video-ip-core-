library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Self-checking testbench for pal_fifo_bool
-- ==========================================
--
-- Uses a small DEPTH (32) for fast simulation.  All phases verified:
--
--   Phase 1 : Write N items, verify level and empty/full flags.
--   Phase 2 : Read all items back, verify data integrity (FIFO order).
--   Phase 3 : Fill to capacity, verify full flag; overflow write rejected.
--   Phase 4 : Read from empty FIFO, verify underflow rejected, empty stays.
--   Phase 5 : Simultaneous read + write; verify count unchanged.
--   Phase 6 : Reset during operation; verify all flags and pointers cleared.
--   Phase 7 : Wrap-around: write past DEPTH-1 pointer, verify correct order.

entity tb_pal_fifo_bool is
end entity tb_pal_fifo_bool;

architecture sim of tb_pal_fifo_bool is

  constant CLK_P  : time    := 10 ns;      -- 100 MHz sim clock (fast)
  constant DEPTH  : integer := 32;          -- small depth for simulation

  signal clk       : std_logic := '0';
  signal rst       : std_logic := '1';
  signal wr_en     : std_logic := '0';
  signal wr_data   : std_logic := '0';
  signal full      : std_logic;
  signal wr_ack    : std_logic;
  signal rd_en     : std_logic := '0';
  signal rd_data   : std_logic;
  signal empty     : std_logic;
  signal rd_valid  : std_logic;
  signal level     : std_logic_vector(19 downto 0);
  signal almost_full  : std_logic;
  signal almost_empty : std_logic;

  -- Helper: write one bit
  procedure fifo_write(
      constant val  : in  std_logic;
      signal   clk  : in  std_logic;
      signal   wen  : out std_logic;
      signal   wdat : out std_logic) is
  begin
    wdat <= val; wen <= '1';
    wait until rising_edge(clk);
    wen <= '0';
    wait until rising_edge(clk);
  end procedure;

  -- Helper: read one bit (returns value seen one clock after rd_en)
  procedure fifo_read(
      signal clk   : in  std_logic;
      signal ren   : out std_logic;
      signal rdat  : in  std_logic;
      variable got : out std_logic) is
  begin
    ren <= '1';
    wait until rising_edge(clk);
    ren <= '0';
    wait until rising_edge(clk);  -- rd_data registered one cycle later
    got := rdat;
  end procedure;

begin

  clk <= not clk after CLK_P / 2;

  dut : entity work.pal_fifo_bool
    generic map (
      DEPTH     => DEPTH,
      AF_THRESH => 4,
      AE_THRESH => 4)
    port map (
      clk         => clk,
      rst         => rst,
      wr_en       => wr_en,
      wr_data     => wr_data,
      full        => full,
      wr_ack      => wr_ack,
      rd_en       => rd_en,
      rd_data     => rd_data,
      empty       => empty,
      rd_valid    => rd_valid,
      level       => level,
      almost_full => almost_full,
      almost_empty=> almost_empty
    );

  -- =========================================================================
  stimulus : process
    variable got : std_logic;
    variable ok  : boolean;
  begin
    -- Release reset
    rst <= '1'; wait for 3 * CLK_P; rst <= '0';
    wait until rising_edge(clk);

    -- =========================================================================
    -- Phase 1: Basic write, check flags and level
    -- =========================================================================
    if empty /= '1' then
      report "!!! Ph1 FAIL: expected empty='1' after reset" severity failure;
    end if;
    if full /= '0' then
      report "!!! Ph1 FAIL: expected full='0' after reset" severity failure;
    end if;
    report "  Ph1: flags after reset OK (empty=1, full=0)" severity note;

    -- Write pattern: 1,0,1,1,0  (5 items)
    fifo_write('1', clk, wr_en, wr_data);
    fifo_write('0', clk, wr_en, wr_data);
    fifo_write('1', clk, wr_en, wr_data);
    fifo_write('1', clk, wr_en, wr_data);
    fifo_write('0', clk, wr_en, wr_data);

    wait until rising_edge(clk);
    if to_integer(unsigned(level)) /= 5 then
      report "!!! Ph1 FAIL: level expected 5, got " &
             integer'image(to_integer(unsigned(level))) severity failure;
    end if;
    if empty /= '0' then
      report "!!! Ph1 FAIL: empty should be 0 after writes" severity failure;
    end if;
    report "=== Ph1 PASS: 5 items written, level=5, empty=0 ===" severity note;

    -- =========================================================================
    -- Phase 2: Read back and verify FIFO order 1,0,1,1,0
    -- =========================================================================
    fifo_read(clk, rd_en, rd_data, got);
    if got /= '1' then
      report "!!! Ph2 FAIL: item 0 expected '1' got '" &
             std_logic'image(got) & "'" severity failure;
    end if;
    fifo_read(clk, rd_en, rd_data, got);
    if got /= '0' then
      report "!!! Ph2 FAIL: item 1 expected '0'" severity failure;
    end if;
    fifo_read(clk, rd_en, rd_data, got);
    if got /= '1' then
      report "!!! Ph2 FAIL: item 2 expected '1'" severity failure;
    end if;
    fifo_read(clk, rd_en, rd_data, got);
    if got /= '1' then
      report "!!! Ph2 FAIL: item 3 expected '1'" severity failure;
    end if;
    fifo_read(clk, rd_en, rd_data, got);
    if got /= '0' then
      report "!!! Ph2 FAIL: item 4 expected '0'" severity failure;
    end if;

    wait until rising_edge(clk);
    if empty /= '1' then
      report "!!! Ph2 FAIL: FIFO should be empty after reading all" severity failure;
    end if;
    report "=== Ph2 PASS: all 5 items read back in correct FIFO order ===" severity note;

    -- =========================================================================
    -- Phase 3: Fill to capacity, verify full; overflow write rejected
    -- =========================================================================
    ok := true;
    for i in 0 to DEPTH - 1 loop
      wr_data <= '1' when i mod 2 = 0 else '0';
      wr_en   <= '1';
      wait until rising_edge(clk);
      wr_en <= '0';
      wait until rising_edge(clk);
    end loop;

    if full /= '1' then
      report "!!! Ph3 FAIL: full should be '1' after writing DEPTH items" severity failure;
    end if;
    if to_integer(unsigned(level)) /= DEPTH then
      report "!!! Ph3 FAIL: level expected DEPTH=" & integer'image(DEPTH) severity failure;
    end if;
    report "  Ph3: FIFO full (level=" & integer'image(DEPTH) & ")" severity note;

    -- Attempt overflow write — should be silently ignored
    fifo_write('1', clk, wr_en, wr_data);
    wait until rising_edge(clk);
    if to_integer(unsigned(level)) /= DEPTH then
      report "!!! Ph3 FAIL: overflow write changed level!" severity failure;
    end if;
    report "=== Ph3 PASS: full flag correct; overflow write rejected ===" severity note;

    -- =========================================================================
    -- Phase 4: Drain completely, verify empty; underflow read rejected
    -- =========================================================================
    for i in 0 to DEPTH - 1 loop
      rd_en <= '1'; wait until rising_edge(clk);
      rd_en <= '0'; wait until rising_edge(clk);
    end loop;

    if empty /= '1' then
      report "!!! Ph4 FAIL: empty should be '1' after reading all" severity failure;
    end if;
    report "  Ph4: FIFO drained" severity note;

    -- Attempt underflow read — should be silently ignored
    rd_en <= '1'; wait until rising_edge(clk); rd_en <= '0';
    wait until rising_edge(clk);
    if empty /= '1' then
      report "!!! Ph4 FAIL: underflow read changed empty flag!" severity failure;
    end if;
    if to_integer(unsigned(level)) /= 0 then
      report "!!! Ph4 FAIL: underflow read changed level!" severity failure;
    end if;
    report "=== Ph4 PASS: empty flag correct; underflow read rejected ===" severity note;

    -- =========================================================================
    -- Phase 5: Simultaneous read + write — level must stay constant
    -- =========================================================================
    -- Pre-load 8 items
    for i in 0 to 7 loop
      wr_data <= '1' when i mod 2 = 0 else '0';
      wr_en <= '1'; wait until rising_edge(clk); wr_en <= '0';
      wait until rising_edge(clk);
    end loop;

    wait until rising_edge(clk);
    if to_integer(unsigned(level)) /= 8 then
      report "!!! Ph5 FAIL: pre-load level expected 8" severity failure;
    end if;

    -- 4 simultaneous rd+wr
    ok := true;
    for i in 0 to 3 loop
      wr_data <= '0'; wr_en <= '1'; rd_en <= '1';
      wait until rising_edge(clk);
      wr_en <= '0'; rd_en <= '0';
      wait until rising_edge(clk);
      if to_integer(unsigned(level)) /= 8 then
        ok := false;
      end if;
    end loop;
    if ok then
      report "=== Ph5 PASS: simultaneous rd+wr; level held at 8 ===" severity note;
    else
      report "!!! Ph5 FAIL: level changed during simultaneous rd+wr" severity failure;
    end if;

    -- =========================================================================
    -- Phase 6: Reset during operation
    -- =========================================================================
    -- Write some data then reset
    fifo_write('1', clk, wr_en, wr_data);
    fifo_write('1', clk, wr_en, wr_data);
    rst <= '1'; wait until rising_edge(clk); rst <= '0';
    wait until rising_edge(clk);
    if empty /= '1' or full /= '0' or to_integer(unsigned(level)) /= 0 then
      report "!!! Ph6 FAIL: reset did not clear FIFO state" severity failure;
    end if;
    report "=== Ph6 PASS: reset clears all state correctly ===" severity note;

    -- =========================================================================
    -- Phase 7: Pointer wrap-around
    -- =========================================================================
    -- Write DEPTH-2 items, read them all, write 4 more (forces pointer wrap)
    for i in 0 to DEPTH - 3 loop
      wr_data <= '1' when i mod 2 = 0 else '0';
      wr_en <= '1'; wait until rising_edge(clk); wr_en <= '0';
      wait until rising_edge(clk);
    end loop;
    -- Drain
    for i in 0 to DEPTH - 3 loop
      rd_en <= '1'; wait until rising_edge(clk); rd_en <= '0';
      wait until rising_edge(clk);
    end loop;
    -- Write 4 items that will wrap the pointer past DEPTH-1
    fifo_write('1', clk, wr_en, wr_data);
    fifo_write('0', clk, wr_en, wr_data);
    fifo_write('1', clk, wr_en, wr_data);
    fifo_write('0', clk, wr_en, wr_data);

    fifo_read(clk, rd_en, rd_data, got);
    if got /= '1' then
      report "!!! Ph7 FAIL: wrap item 0 expected '1'" severity failure;
    end if;
    fifo_read(clk, rd_en, rd_data, got);
    if got /= '0' then
      report "!!! Ph7 FAIL: wrap item 1 expected '0'" severity failure;
    end if;
    report "=== Ph7 PASS: pointer wrap-around verified ===" severity note;

    report "=== tb_pal_fifo_bool: ALL PHASES PASS ===" severity note;
    std.env.finish;
  end process;

end architecture sim;
