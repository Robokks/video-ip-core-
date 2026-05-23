library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Testbench for pal_bram_loader
-- ===========================================================================
-- Tests three scenarios:
--   Test 1 – Normal   : FIFO fully pre-loaded → start → done
--   Test 2 – Stall    : FIFO starts with 3 of 8 pixels; rest arrive mid-load
--   Test 3 – Retrigger: Second frame loaded after done, without reset
--
-- FIFO model: 1-clock read latency (registered output).
-- Checker verifies every BRAM write (address + data) across all three tests.
-- ===========================================================================

entity tb_pal_bram_loader is
end entity tb_pal_bram_loader;

architecture sim of tb_pal_bram_loader is

  -- Small frame for fast simulation (change to 299520/19 for full PAL)
  constant TOTAL_PX   : integer := 8;
  constant ADDR_BITS  : integer := 4;
  constant CLK_PERIOD : time    := 10 ns;

  signal clk        : std_logic := '0';
  signal rst        : std_logic := '1';
  signal start      : std_logic := '0';
  signal done       : std_logic;
  signal busy       : std_logic;
  signal fifo_data  : std_logic;
  signal fifo_empty : std_logic;
  signal fifo_rd    : std_logic;
  signal bram_wr_en   : std_logic;
  signal bram_wr_addr : std_logic_vector(ADDR_BITS - 1 downto 0);
  signal bram_wr_data : std_logic;

  -- -------------------------------------------------------------------------
  -- FIFO model  (depth 16, push from testbench, pop from loader)
  -- 1-clock read latency: data on fifo_out is valid ONE cycle after fifo_rd='1'
  -- -------------------------------------------------------------------------
  constant FIFO_DEPTH : integer := 16;
  type fifo_mem_t is array (0 to FIFO_DEPTH - 1) of std_logic;

  signal fifo_mem    : fifo_mem_t := (others => '0');
  signal fifo_wr_ptr : integer range 0 to FIFO_DEPTH - 1 := 0;
  signal fifo_rd_ptr : integer range 0 to FIFO_DEPTH - 1 := 0;
  signal fifo_count  : integer range 0 to FIFO_DEPTH     := 0;
  signal fifo_out    : std_logic := '0';  -- registered FIFO output

  -- Push interface driven by testbench stimulus
  signal tb_push_en   : std_logic := '0';
  signal tb_push_data : std_logic := '0';

  -- Test patterns (8 pixels each)
  type pattern_t is array (0 to TOTAL_PX - 1) of std_logic;
  constant PATTERN_A : pattern_t := ('1','0','1','0','1','1','0','1');
  constant PATTERN_B : pattern_t := ('0','1','0','1','0','0','1','0');  -- inverted A

begin

  clk <= not clk after CLK_PERIOD / 2;

  -- -------------------------------------------------------------------------
  -- UUT
  -- -------------------------------------------------------------------------
  uut : entity work.pal_bram_loader
    generic map (TOTAL_PX => TOTAL_PX, ADDR_BITS => ADDR_BITS)
    port map (
      clk          => clk,
      rst          => rst,
      start        => start,
      done         => done,
      busy         => busy,
      fifo_data    => fifo_out,    -- registered FIFO output (1-cycle latency)
      fifo_empty   => fifo_empty,
      fifo_rd      => fifo_rd,
      bram_wr_en   => bram_wr_en,
      bram_wr_addr => bram_wr_addr,
      bram_wr_data => bram_wr_data
    );

  fifo_empty <= '1' when fifo_count = 0 else '0';

  -- -------------------------------------------------------------------------
  -- FIFO model: synchronous write (push) and registered read (pop)
  -- Uses a VARIABLE for count so simultaneous push+pop keeps count unchanged.
  -- -------------------------------------------------------------------------
  process(clk)
    variable count_v : integer range 0 to FIFO_DEPTH := 0;
  begin
    if rising_edge(clk) then
      count_v := fifo_count;

      -- Push (testbench → FIFO)
      if tb_push_en = '1' and count_v < FIFO_DEPTH then
        fifo_mem(fifo_wr_ptr) <= tb_push_data;
        fifo_wr_ptr           <= (fifo_wr_ptr + 1) mod FIFO_DEPTH;
        count_v               := count_v + 1;
      end if;

      -- Pop (loader → FIFO): latch current head, advance pointer
      -- Data appears on fifo_out ONE cycle after fifo_rd='1'
      if fifo_rd = '1' and count_v > 0 then
        fifo_out    <= fifo_mem(fifo_rd_ptr);
        fifo_rd_ptr <= (fifo_rd_ptr + 1) mod FIFO_DEPTH;
        count_v     := count_v - 1;
      end if;

      fifo_count <= count_v;
    end if;
  end process;

  -- =========================================================================
  -- Stimulus process
  -- =========================================================================
  process
    -- Push one pixel into FIFO, consume one clock
    procedure push(val : std_logic) is
    begin
      tb_push_data <= val;
      tb_push_en   <= '1';
      wait until rising_edge(clk);
      tb_push_en   <= '0';
    end procedure;

    -- Pulse start for one clock
    procedure trigger is
    begin
      start <= '1';
      wait until rising_edge(clk);
      start <= '0';
    end procedure;

  begin
    -- Release reset
    rst <= '1';
    wait for 5 * CLK_PERIOD;
    rst <= '0';
    wait until rising_edge(clk);

    -- =========================================================================
    -- Test 1: Normal load
    --   Fill FIFO with all 8 pixels, then trigger.
    -- =========================================================================
    report "--- Test 1: Normal load ---" severity note;
    for i in 0 to TOTAL_PX - 1 loop
      push(PATTERN_A(i));
    end loop;
    trigger;
    wait until done = '1';
    assert busy = '0'
      report "Test1: busy should be LOW when done" severity error;
    wait for CLK_PERIOD;
    report "--- Test 1 complete ---" severity note;

    -- =========================================================================
    -- Test 2: Stall — only first 3 pixels in FIFO at trigger time
    --   Loader will stall at pixel 3; remaining pixels arrive one by one.
    -- =========================================================================
    report "--- Test 2: Stall test ---" severity note;
    push(PATTERN_B(0));
    push(PATTERN_B(1));
    push(PATTERN_B(2));
    trigger;

    -- Wait a few clocks so the loader drains those 3 and stalls
    wait for 10 * CLK_PERIOD;

    -- Feed remaining pixels with gaps (simulating slow host)
    for i in 3 to TOTAL_PX - 1 loop
      push(PATTERN_B(i));
      wait for 4 * CLK_PERIOD;
    end loop;

    wait until done = '1';
    report "--- Test 2 complete (stall handled) ---" severity note;
    wait for CLK_PERIOD;

    -- =========================================================================
    -- Test 3: Re-trigger — load a new frame without reset
    -- =========================================================================
    report "--- Test 3: Re-trigger ---" severity note;
    for i in 0 to TOTAL_PX - 1 loop
      push(PATTERN_A(i));
    end loop;
    trigger;
    wait until done = '1';
    report "--- Test 3 complete ---" severity note;
    wait for 3 * CLK_PERIOD;

    report "=== All tests PASSED ===" severity note;
    std.env.finish;
  end process;

  -- =========================================================================
  -- Checker process: verifies EVERY BRAM write across all three tests
  -- Expected sequence: Test1=PATTERN_A, Test2=PATTERN_B, Test3=PATTERN_A
  -- =========================================================================
  process
    variable got_addr : integer;
    variable got_data : std_logic;

    type full_t is array (0 to 3 * TOTAL_PX - 1) of std_logic;
    constant EXPECTED : full_t := (
      -- Test 1: PATTERN_A
      '1','0','1','0','1','1','0','1',
      -- Test 2: PATTERN_B
      '0','1','0','1','0','0','1','0',
      -- Test 3: PATTERN_A
      '1','0','1','0','1','1','0','1'
    );
  begin
    wait until rst = '0';

    for i in 0 to 3 * TOTAL_PX - 1 loop
      wait until rising_edge(clk) and bram_wr_en = '1';
      got_addr := to_integer(unsigned(bram_wr_addr));
      got_data := bram_wr_data;

      assert got_addr = (i mod TOTAL_PX)
        report "FAIL write #" & integer'image(i) &
               " addr: exp=" & integer'image(i mod TOTAL_PX) &
               " got=" & integer'image(got_addr) severity error;

      assert got_data = EXPECTED(i)
        report "FAIL write #" & integer'image(i) &
               " addr=" & integer'image(got_addr) &
               ": exp=" & std_logic'image(EXPECTED(i)) &
               " got=" & std_logic'image(got_data) severity error;
    end loop;

    report "=== Checker: all " & integer'image(3 * TOTAL_PX) &
           " writes correct ===" severity note;
    wait;
  end process;

end architecture sim;
