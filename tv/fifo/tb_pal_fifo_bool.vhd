library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Self-checking testbench for pal_fifo_bool (wide-write / single-bit-read)
-- =========================================================================
--
-- Write port : WR_WIDTH=8 bits per clock (std_logic_vector)
-- Read  port : 1 bit per clock (std_logic), LSB of each word first
--
-- Uses DEPTH=32, WR_WIDTH=8 -> MEM_DEPTH=4 words for fast simulation.
--
--   Phase 1 : Write 2 words, verify level=16 and empty/full flags.
--   Phase 2 : Read all 16 bits back, verify LSB-first order per word.
--   Phase 3 : Fill to capacity (4 words = 32 bits), verify full flag;
--             overflow write rejected.
--   Phase 4 : Drain all 32 bits, verify empty; underflow read rejected.
--   Phase 5 : Simultaneous word-write + bit-read; verify level grows by
--             WR_WIDTH-1 = 7 per cycle.
--   Phase 6 : Reset during operation; verify all flags/pointers cleared.
--   Phase 7 : Wrap-around: fill MEM_DEPTH-1 words, drain them, then write
--             2 more words that wrap both wr_ptr and rd_ptr past MEM_DEPTH-1.
--
-- BRAM fetch latency note
-- -----------------------
--   The DUT has a 2-cycle BRAM fetch gap between words (Cycle A: need_fetch,
--   Cycle B: rd_buf loaded). An rd_en pulse landing during Cycle B
--   (rd_bits_rem=0, fetching='1') is silently ignored and rd_valid stays '0'.
--   fifo_read() uses rd_valid to detect this and retries automatically.

entity tb_pal_fifo_bool is
end entity tb_pal_fifo_bool;

architecture sim of tb_pal_fifo_bool is

  constant CLK_P    : time    := 10 ns;
  constant DEPTH    : integer := 32;
  constant WR_WIDTH : integer := 8;
  constant MEM_DEPTH: integer := DEPTH / WR_WIDTH;   -- 4 words

  signal clk          : std_logic := '0';
  signal rst          : std_logic := '1';
  signal wr_en        : std_logic := '0';
  signal wr_data      : std_logic_vector(WR_WIDTH - 1 downto 0) := (others => '0');
  signal full         : std_logic;
  signal wr_ack       : std_logic;
  signal rd_en        : std_logic := '0';
  signal rd_data      : std_logic;
  signal empty        : std_logic;
  signal rd_valid     : std_logic;
  signal level        : std_logic_vector(19 downto 0);
  signal almost_full  : std_logic;
  signal almost_empty : std_logic;

  -- -------------------------------------------------------------------------
  -- Helper: write one WR_WIDTH-bit word (2-clock transaction)
  -- -------------------------------------------------------------------------
  procedure fifo_write(
      constant val  : in  std_logic_vector(WR_WIDTH - 1 downto 0);
      signal   clk  : in  std_logic;
      signal   wen  : out std_logic;
      signal   wdat : out std_logic_vector(WR_WIDTH - 1 downto 0)) is
  begin
    wdat <= val;
    wen  <= '1';
    wait until rising_edge(clk);
    wen  <= '0';
    wait until rising_edge(clk);
  end procedure;

  -- -------------------------------------------------------------------------
  -- Helper: read one bit, retry until rd_valid='1'.
  --
  -- The DUT has a 2-cycle BRAM fetch gap at word boundaries. An rd_en pulse
  -- that lands when rd_bits_rem=0 (Cycle B in progress) is silently ignored
  -- and rd_valid stays '0'. This procedure retries so the caller never needs
  -- to know about fetch timing.
  -- -------------------------------------------------------------------------
  procedure fifo_read(
      signal   clk    : in  std_logic;
      signal   ren    : out std_logic;
      signal   rdat   : in  std_logic;
      signal   rvalid : in  std_logic;
      variable got    : out std_logic) is
  begin
    loop
      ren <= '1';
      wait until rising_edge(clk);
      ren <= '0';
      wait until rising_edge(clk);   -- rd_data and rd_valid registered here
      exit when rvalid = '1';        -- retry if rd_en was ignored during fetch
    end loop;
    got := rdat;
  end procedure;

  -- -------------------------------------------------------------------------
  -- Helper: drain bits until empty='1', up to max_iter rd_en pulses.
  -- -------------------------------------------------------------------------
  procedure drain(
      signal   clk      : in  std_logic;
      signal   ren      : out std_logic;
      signal   is_empty : in  std_logic;
      constant max_iter : in  integer) is
  begin
    for i in 0 to max_iter - 1 loop
      exit when is_empty = '1';
      ren <= '1';
      wait until rising_edge(clk);
      ren <= '0';
      wait until rising_edge(clk);
    end loop;
  end procedure;

begin

  clk <= not clk after CLK_P / 2;

  -- AF_THRESH=1: almost-full when word_count+rd_buf_occ >= MEM_DEPTH-1 = 3.
  -- AE_THRESH=4: almost-empty when <=4 bits remain and memory empty.
  dut : entity work.pal_fifo_bool
    generic map (
      DEPTH     => DEPTH,
      WR_WIDTH  => WR_WIDTH,
      AF_THRESH => 1,
      AE_THRESH => 4)
    port map (
      clk          => clk,
      rst          => rst,
      wr_en        => wr_en,
      wr_data      => wr_data,
      full         => full,
      wr_ack       => wr_ack,
      rd_en        => rd_en,
      rd_data      => rd_data,
      empty        => empty,
      rd_valid     => rd_valid,
      level        => level,
      almost_full  => almost_full,
      almost_empty => almost_empty
    );

  -- ===========================================================================
  stimulus : process
    variable got : std_logic;
  begin
    -- Release reset
    rst <= '1'; wait for 3 * CLK_P; rst <= '0';
    wait until rising_edge(clk);

    -- =========================================================================
    -- Phase 1: Write 2 words, verify level=16 and flags
    -- =========================================================================
    if empty /= '1' then
      report "!!! Ph1 FAIL: expected empty='1' after reset" severity failure;
    end if;
    if full /= '0' then
      report "!!! Ph1 FAIL: expected full='0' after reset" severity failure;
    end if;
    report "  Ph1: flags after reset OK (empty=1, full=0)" severity note;

    -- 0xA5 = 1010_0101 -> LSB-first: 1,0,1,0,0,1,0,1
    -- 0x3C = 0011_1100 -> LSB-first: 0,0,1,1,1,1,0,0
    fifo_write(x"A5", clk, wr_en, wr_data);
    fifo_write(x"3C", clk, wr_en, wr_data);

    wait until rising_edge(clk);
    if to_integer(unsigned(level)) /= 16 then
      report "!!! Ph1 FAIL: level expected 16, got " &
             integer'image(to_integer(unsigned(level))) severity failure;
    end if;
    if empty /= '0' then
      report "!!! Ph1 FAIL: empty should be 0 after writes" severity failure;
    end if;
    report "=== Ph1 PASS: 2 words written, level=16, empty=0 ===" severity note;

    -- =========================================================================
    -- Phase 2: Read back 16 bits LSB-first, verify FIFO order
    --
    -- 0xA5 = 1010_0101 : bit[0..7] = 1,0,1,0,0,1,0,1
    -- 0x3C = 0011_1100 : bit[0..7] = 0,0,1,1,1,1,0,0
    --
    -- fifo_read() retries automatically at the 2-cycle BRAM fetch boundary.
    -- =========================================================================

    -- word 0 : 0xA5
    fifo_read(clk, rd_en, rd_data, rd_valid, got);
    if got /= '1' then report "!!! Ph2 FAIL: w0b0 expected '1', got '"&std_logic'image(got)&"'" severity failure; end if;
    fifo_read(clk, rd_en, rd_data, rd_valid, got);
    if got /= '0' then report "!!! Ph2 FAIL: w0b1 expected '0'" severity failure; end if;
    fifo_read(clk, rd_en, rd_data, rd_valid, got);
    if got /= '1' then report "!!! Ph2 FAIL: w0b2 expected '1'" severity failure; end if;
    fifo_read(clk, rd_en, rd_data, rd_valid, got);
    if got /= '0' then report "!!! Ph2 FAIL: w0b3 expected '0'" severity failure; end if;
    fifo_read(clk, rd_en, rd_data, rd_valid, got);
    if got /= '0' then report "!!! Ph2 FAIL: w0b4 expected '0'" severity failure; end if;
    fifo_read(clk, rd_en, rd_data, rd_valid, got);
    if got /= '1' then report "!!! Ph2 FAIL: w0b5 expected '1'" severity failure; end if;
    fifo_read(clk, rd_en, rd_data, rd_valid, got);
    if got /= '0' then report "!!! Ph2 FAIL: w0b6 expected '0'" severity failure; end if;
    fifo_read(clk, rd_en, rd_data, rd_valid, got);
    if got /= '1' then report "!!! Ph2 FAIL: w0b7 expected '1'" severity failure; end if;

    -- word 1 : 0x3C
    fifo_read(clk, rd_en, rd_data, rd_valid, got);
    if got /= '0' then report "!!! Ph2 FAIL: w1b0 expected '0'" severity failure; end if;
    fifo_read(clk, rd_en, rd_data, rd_valid, got);
    if got /= '0' then report "!!! Ph2 FAIL: w1b1 expected '0'" severity failure; end if;
    fifo_read(clk, rd_en, rd_data, rd_valid, got);
    if got /= '1' then report "!!! Ph2 FAIL: w1b2 expected '1'" severity failure; end if;
    fifo_read(clk, rd_en, rd_data, rd_valid, got);
    if got /= '1' then report "!!! Ph2 FAIL: w1b3 expected '1'" severity failure; end if;
    fifo_read(clk, rd_en, rd_data, rd_valid, got);
    if got /= '1' then report "!!! Ph2 FAIL: w1b4 expected '1'" severity failure; end if;
    fifo_read(clk, rd_en, rd_data, rd_valid, got);
    if got /= '1' then report "!!! Ph2 FAIL: w1b5 expected '1'" severity failure; end if;
    fifo_read(clk, rd_en, rd_data, rd_valid, got);
    if got /= '0' then report "!!! Ph2 FAIL: w1b6 expected '0'" severity failure; end if;
    fifo_read(clk, rd_en, rd_data, rd_valid, got);
    if got /= '0' then report "!!! Ph2 FAIL: w1b7 expected '0'" severity failure; end if;

    wait until rising_edge(clk);
    if empty /= '1' then
      report "!!! Ph2 FAIL: FIFO should be empty after reading all 16 bits" severity failure;
    end if;
    report "=== Ph2 PASS: 16 bits read in correct LSB-first order ===" severity note;

    -- =========================================================================
    -- Phase 3: Fill to capacity (MEM_DEPTH=4 words = 32 bits)
    --
    -- First write causes simultaneous write+fetch: word goes to BRAM and is
    -- immediately fetched to rd_buf (word_count stays 0). After 4 writes:
    --   word_count=3, rd_bits_rem=8, rd_buf_occ=1 -> total=4=MEM_DEPTH -> full='1'
    -- =========================================================================
    for i in 0 to MEM_DEPTH - 1 loop
      fifo_write(std_logic_vector(to_unsigned(i * 16#11#, WR_WIDTH)), clk, wr_en, wr_data);
    end loop;

    wait until rising_edge(clk);
    if full /= '1' then
      report "!!! Ph3 FAIL: full should be '1' after writing " &
             integer'image(MEM_DEPTH) & " words" severity failure;
    end if;
    if to_integer(unsigned(level)) /= DEPTH then
      report "!!! Ph3 FAIL: level expected " & integer'image(DEPTH) &
             ", got " & integer'image(to_integer(unsigned(level))) severity failure;
    end if;
    report "  Ph3: FIFO full, level=" & integer'image(DEPTH) severity note;

    -- Overflow write must be silently rejected
    fifo_write(x"FF", clk, wr_en, wr_data);
    wait until rising_edge(clk);
    if to_integer(unsigned(level)) /= DEPTH then
      report "!!! Ph3 FAIL: overflow write changed level!" severity failure;
    end if;
    if full /= '1' then
      report "!!! Ph3 FAIL: overflow write cleared full flag!" severity failure;
    end if;
    report "=== Ph3 PASS: full flag correct; overflow write rejected ===" severity note;

    -- =========================================================================
    -- Phase 4: Drain all DEPTH=32 bits; verify empty; underflow read rejected
    -- =========================================================================
    drain(clk, rd_en, empty, 3 * DEPTH);

    wait until rising_edge(clk);
    if empty /= '1' then
      report "!!! Ph4 FAIL: empty should be '1' after draining" severity failure;
    end if;
    if to_integer(unsigned(level)) /= 0 then
      report "!!! Ph4 FAIL: level not 0 after drain, got " &
             integer'image(to_integer(unsigned(level))) severity failure;
    end if;
    report "  Ph4: FIFO drained to empty" severity note;

    -- Underflow read
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
    -- Phase 5: Simultaneous word-write (8 bits) + bit-read (1 bit)
    --   Net per cycle: +8 - 1 = +7 bits. Start with 1 pre-loaded word (8 bits).
    --   3 simultaneous cycles: level 8 -> 15 -> 22 -> 29.
    -- =========================================================================
    fifo_write(x"AA", clk, wr_en, wr_data);
    -- Two extra clocks needed: Cycle B fires on clock+1, rd_bits_rem settles
    -- on clock+2. Testbench reads registered values from the previous clock.
    wait until rising_edge(clk);   -- Cycle B fires: rd_bits_rem <= 8
    wait until rising_edge(clk);   -- level = 0*8+8 = 8 now visible

    if to_integer(unsigned(level)) /= 8 then
      report "!!! Ph5 FAIL: pre-load level expected 8, got " &
             integer'image(to_integer(unsigned(level))) severity failure;
    end if;

    for i in 0 to 2 loop
      wr_data <= x"55"; wr_en <= '1'; rd_en <= '1';
      wait until rising_edge(clk);
      wr_en <= '0'; rd_en <= '0';
      wait until rising_edge(clk);
    end loop;

    if to_integer(unsigned(level)) /= 29 then
      report "!!! Ph5 FAIL: after 3 sim cycles level expected 29, got " &
             integer'image(to_integer(unsigned(level))) severity failure;
    end if;
    report "=== Ph5 PASS: simultaneous word-wr + bit-rd; level 8->29 (net +7/cycle) ===" severity note;

    -- =========================================================================
    -- Phase 6: Reset during operation (Phase 5 data still present)
    -- =========================================================================
    rst <= '1'; wait until rising_edge(clk); rst <= '0';
    wait until rising_edge(clk);
    if empty /= '1' or full /= '0' or to_integer(unsigned(level)) /= 0 then
      report "!!! Ph6 FAIL: reset did not clear FIFO state" severity failure;
    end if;
    report "=== Ph6 PASS: reset clears all state ===" severity note;

    -- =========================================================================
    -- Phase 7: Pointer wrap-around
    --   After reset: wr_ptr=0, rd_ptr=0.
    --   Write MEM_DEPTH-1=3 words (wr_ptr reaches 3), drain them (rd_ptr=3).
    --   Write 0xB4 -> mem[3], wr_ptr wraps 3->0.
    --   Write 0x2D -> mem[0], wr_ptr -> 1.
    --   Fetch of 0xB4: rd_ptr wraps 3->0. Verify 8 LSB-first bits.
    --
    --   0xB4 = 1011_0100 : bit[0..7] = 0,0,1,0,1,1,0,1
    -- =========================================================================
    for i in 0 to MEM_DEPTH - 2 loop
      fifo_write(x"AA", clk, wr_en, wr_data);
    end loop;

    drain(clk, rd_en, empty, 3 * DEPTH);
    wait until rising_edge(clk);
    if empty /= '1' then
      report "!!! Ph7 FAIL: should be empty before wrap test" severity failure;
    end if;

    fifo_write(x"B4", clk, wr_en, wr_data);   -- mem[3], wr_ptr: 3->0
    fifo_write(x"2D", clk, wr_en, wr_data);   -- mem[0], wr_ptr: 0->1

    fifo_read(clk, rd_en, rd_data, rd_valid, got);
    if got /= '0' then report "!!! Ph7 FAIL: w_wrap b0 expected '0'" severity failure; end if;
    fifo_read(clk, rd_en, rd_data, rd_valid, got);
    if got /= '0' then report "!!! Ph7 FAIL: w_wrap b1 expected '0'" severity failure; end if;
    fifo_read(clk, rd_en, rd_data, rd_valid, got);
    if got /= '1' then report "!!! Ph7 FAIL: w_wrap b2 expected '1'" severity failure; end if;
    fifo_read(clk, rd_en, rd_data, rd_valid, got);
    if got /= '0' then report "!!! Ph7 FAIL: w_wrap b3 expected '0'" severity failure; end if;
    fifo_read(clk, rd_en, rd_data, rd_valid, got);
    if got /= '1' then report "!!! Ph7 FAIL: w_wrap b4 expected '1'" severity failure; end if;
    fifo_read(clk, rd_en, rd_data, rd_valid, got);
    if got /= '1' then report "!!! Ph7 FAIL: w_wrap b5 expected '1'" severity failure; end if;
    fifo_read(clk, rd_en, rd_data, rd_valid, got);
    if got /= '0' then report "!!! Ph7 FAIL: w_wrap b6 expected '0'" severity failure; end if;
    fifo_read(clk, rd_en, rd_data, rd_valid, got);
    if got /= '1' then report "!!! Ph7 FAIL: w_wrap b7 expected '1'" severity failure; end if;

    report "=== Ph7 PASS: wr_ptr and rd_ptr wrap-around verified ===" severity note;

    report "=== tb_pal_fifo_bool: ALL PHASES PASS ===" severity note;
    std.env.finish;
  end process;

end architecture sim;
