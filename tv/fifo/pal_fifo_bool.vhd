library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Standalone Boolean FIFO: array write, single-bit read
-- ======================================================
--
-- WRITE port: WR_WIDTH bits per clock  (std_logic_vector array)
-- READ  port: 1 bit per clock          (std_logic)
--
-- One wr_en pulse writes WR_WIDTH bits atomically.
-- One rd_en pulse reads exactly 1 bit.
--
-- Internal storage
-- ----------------
--   Memory array: MEM_DEPTH = DEPTH / WR_WIDTH words, each WR_WIDTH bits wide.
--   Xilinx ram_style="block" → Block RAM inference.
--   For DEPTH=600000, WR_WIDTH=8: 75000 words × 8 bits → 19 BRAM36 tiles.
--
-- Read path
-- ---------
--   The read side maintains a shift register (rd_buf) loaded from BRAM.
--   Two-cycle fetch latency (1 detect + 1 registered BRAM read).
--   rd_data is registered; valid ONE clock after rd_en is asserted.
--   rd_valid strobes HIGH for that one clock.
--
-- Pointer ordering
-- ----------------
--   rd_buf is read LSB first: bit 0 of wr_data comes out first.
--
-- Full flag
-- ---------
--   full_s accounts for rd_buf occupancy. rd_buf holds a fetched word (not
--   counted in word_count). Total capacity = MEM_DEPTH words. Full when:
--     (rd_bits_rem = 0 and word_count = MEM_DEPTH)  OR
--     (rd_bits_rem > 0 and word_count = MEM_DEPTH-1)
--   Implemented via: word_count + rd_buf_occ >= MEM_DEPTH
--   where rd_buf_occ = 1 when rd_bits_rem > 0, else 0.
--
-- Constraints / requirements
-- --------------------------
--   DEPTH must be divisible by WR_WIDTH.
--   WR_WIDTH  must be >= 1.
--   AF_THRESH : almost-full distance from top (in words).
--   AE_THRESH : almost-empty distance from bottom (in bits).
--
-- This module is STANDALONE — no connection to pal_tv_bram_top or video_bram_top.

entity pal_fifo_bool is
  generic (
    DEPTH     : integer := 600000;  -- total capacity in bits (must be divisible by WR_WIDTH)
    WR_WIDTH  : integer := 8;       -- bits written per clock
    AF_THRESH : integer := 4;       -- almost-full threshold  (words from full)
    AE_THRESH : integer := 4        -- almost-empty threshold (bits  from empty)
  );
  port (
    clk          : in  std_logic;
    rst          : in  std_logic;

    -- Write port  (WR_WIDTH bits per clock)
    wr_en        : in  std_logic;
    wr_data      : in  std_logic_vector(WR_WIDTH - 1 downto 0);
    full         : out std_logic;
    wr_ack       : out std_logic;    -- 1-clock strobe when write accepted

    -- Read port   (1 bit per clock)
    rd_en        : in  std_logic;
    rd_data      : out std_logic;    -- registered; valid 1 clock after rd_en
    empty        : out std_logic;
    rd_valid     : out std_logic;    -- 1-clock strobe when rd_data updated

    -- Status
    level        : out std_logic_vector(19 downto 0);  -- fill in bits
    almost_full  : out std_logic;
    almost_empty : out std_logic
  );
end entity pal_fifo_bool;

architecture rtl of pal_fifo_bool is

  constant MEM_DEPTH : integer := DEPTH / WR_WIDTH;

  -- WR_WIDTH-bit wide BRAM array
  type mem_t is array (0 to MEM_DEPTH - 1) of std_logic_vector(WR_WIDTH - 1 downto 0);
  signal mem : mem_t := (others => (others => '0'));
  attribute ram_style              : string;
  attribute ram_style of mem       : signal is "block";

  -- Write side
  signal wr_ptr     : integer range 0 to MEM_DEPTH - 1 := 0;
  signal word_count : integer range 0 to MEM_DEPTH     := 0;
  signal full_s     : std_logic;
  signal wr_ack_s   : std_logic := '0';

  -- Read side
  signal rd_ptr      : integer range 0 to MEM_DEPTH - 1 := 0;
  signal rd_buf      : std_logic_vector(WR_WIDTH - 1 downto 0) := (others => '0');
  signal rd_bit      : integer range 0 to WR_WIDTH - 1  := 0;
  signal rd_bits_rem : integer range 0 to WR_WIDTH      := 0;
  signal fetching    : std_logic := '0';  -- BRAM fetch in flight
  signal empty_s     : std_logic;
  signal rd_valid_s  : std_logic := '0';

  -- Combinational fetch trigger
  signal need_fetch  : std_logic;

  -- rd_buf occupancy: 1 when rd_buf holds valid bits, 0 otherwise.
  -- Used in full_s to correctly account for the word held in rd_buf.
  signal rd_buf_occ  : integer range 0 to 1 := 0;

begin

  -- -------------------------------------------------------------------------
  -- Elaboration checks
  -- -------------------------------------------------------------------------
  assert DEPTH mod WR_WIDTH = 0
    report "pal_fifo_bool: DEPTH must be divisible by WR_WIDTH" severity failure;
  assert DEPTH > 0 and WR_WIDTH >= 1
    report "pal_fifo_bool: DEPTH and WR_WIDTH must be > 0" severity failure;
  assert AF_THRESH >= 0 and AF_THRESH < MEM_DEPTH
    report "pal_fifo_bool: AF_THRESH out of range" severity failure;

  -- -------------------------------------------------------------------------
  -- Combinational flags
  -- -------------------------------------------------------------------------

  -- rd_buf_occ: 1 when shift register holds at least one valid bit
  rd_buf_occ <= 1 when rd_bits_rem > 0 else 0;

  -- Full: memory is at capacity accounting for the word held in rd_buf.
  -- word_count tracks words in BRAM only; rd_buf holds one additional word
  -- when rd_bits_rem > 0 (rd_buf_occ = 1). Total live words = word_count + rd_buf_occ.
  full_s     <= '1' when word_count + rd_buf_occ >= MEM_DEPTH else '0';

  -- Empty: no bits in shift register AND no words in memory AND not fetching
  empty_s    <= '1' when fetching = '0' and rd_bits_rem = 0 and word_count = 0
                else '0';

  -- Fetch needed: shift register empty, data in memory, no fetch in flight
  need_fetch <= '1' when fetching = '0' and rd_bits_rem = 0 and word_count > 0
                else '0';

  -- -------------------------------------------------------------------------
  -- Write process + word counter
  --   word_count tracks words stored in memory (NOT counting rd_buf).
  --   Incremented on write; decremented when a word is consumed for rd_buf.
  -- -------------------------------------------------------------------------
  process(clk)
    variable do_wr  : boolean;
    variable do_dec : boolean;
  begin
    if rising_edge(clk) then
      wr_ack_s <= '0';
      if rst = '1' then
        wr_ptr     <= 0;
        word_count <= 0;
      else
        do_wr  := (wr_en = '1') and (full_s = '0');
        do_dec := (need_fetch = '1');  -- one word leaves mem → rd_buf

        -- Synchronous BRAM write
        if do_wr then
          mem(wr_ptr) <= wr_data;
          if wr_ptr = MEM_DEPTH - 1 then wr_ptr <= 0;
          else wr_ptr <= wr_ptr + 1; end if;
          wr_ack_s <= '1';
        end if;

        -- Word counter update (write and fetch can happen simultaneously)
        if do_wr and not do_dec then
          word_count <= word_count + 1;
        elsif do_dec and not do_wr then
          word_count <= word_count - 1;
        -- simultaneous wr + dec: word_count unchanged
        end if;
      end if;
    end if;
  end process;

  -- -------------------------------------------------------------------------
  -- Read process: 2-cycle BRAM fetch then bit-serial output
  --
  --   Cycle A  (need_fetch = '1'):
  --     Set fetching = '1'.  word_count already decremented by write process.
  --
  --   Cycle B  (fetching = '1'):
  --     Registered BRAM read: rd_buf <= mem(rd_ptr).
  --     rd_ptr advances (uses current value for BRAM address; VHDL semantics
  --     guarantee BRAM reads current rd_ptr and rd_ptr update both take effect
  --     at end-of-cycle — registered read of the pre-advance address).
  --     rd_bits_rem set to WR_WIDTH; fetching cleared.
  --
  --   Cycle C  (rd_en = '1' and rd_bits_rem > 0):
  --     Output rd_buf(rd_bit) → rd_data (registered).
  --     rd_valid strobes for one clock.
  --     rd_bit advances; when exhausted, rd_bits_rem → 0 triggers next fetch.
  -- -------------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      rd_valid_s <= '0';
      if rst = '1' then
        rd_ptr      <= 0;
        rd_buf      <= (others => '0');
        rd_bit      <= 0;
        rd_bits_rem <= 0;
        fetching    <= '0';
        rd_data     <= '0';
      else

        -- Cycle A: latch fetch request
        if need_fetch = '1' then
          fetching <= '1';
        end if;

        -- Cycle B: complete BRAM fetch
        --   mem(rd_ptr) uses current (pre-advance) rd_ptr value.
        --   rd_ptr advances simultaneously; BRAM output registered to rd_buf.
        --   Cycle A and B are mutually exclusive (need_fetch requires fetching='0').
        if fetching = '1' then
          rd_buf      <= mem(rd_ptr);          -- registered BRAM read
          rd_bit      <= 0;
          rd_bits_rem <= WR_WIDTH;
          fetching    <= '0';
          if rd_ptr = MEM_DEPTH - 1 then rd_ptr <= 0;
          else rd_ptr <= rd_ptr + 1; end if;
        end if;

        -- Cycle C: shift out one bit
        --   Runs when rd_bits_rem > 0 (i.e., rd_buf has valid data).
        --   Mutually exclusive with Cycle B (Cycle B requires rd_bits_rem = 0
        --   via fetching='1' only when rd_bits_rem was 0).
        if rd_en = '1' and rd_bits_rem > 0 then
          rd_data    <= rd_buf(rd_bit);        -- registered output
          rd_valid_s <= '1';
          if rd_bit = WR_WIDTH - 1 then
            rd_bit      <= 0;
            rd_bits_rem <= 0;                  -- trigger next fetch on next cycle
          else
            rd_bit      <= rd_bit + 1;
            rd_bits_rem <= rd_bits_rem - 1;
          end if;
        end if;

      end if;
    end if;
  end process;

  -- -------------------------------------------------------------------------
  -- Output assignments
  -- -------------------------------------------------------------------------
  full         <= full_s;
  empty        <= empty_s;
  wr_ack       <= wr_ack_s;
  rd_valid     <= rd_valid_s;

  -- Level in bits: words in memory × WR_WIDTH + bits remaining in shift register.
  -- For WR_WIDTH = power-of-2 (e.g. 8), Vivado optimises × to a shift.
  level        <= std_logic_vector(to_unsigned(
                    word_count * WR_WIDTH + rd_bits_rem, 20));

  almost_full  <= '1' when word_count + rd_buf_occ >= MEM_DEPTH - AF_THRESH else '0';
  -- almost_empty: fires when only a few bits remain and no more words in memory
  almost_empty <= '1' when word_count = 0 and rd_bits_rem <= AE_THRESH else '0';

end architecture rtl;
