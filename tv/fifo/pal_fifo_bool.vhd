library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Standalone 1-bit (Boolean) synchronous FIFO
-- =============================================
--
-- Depth    : DEPTH generics entries (default 600 000)
-- Data     : 1-bit std_logic (Boolean pixel / flag value)
-- Clock    : single synchronous clock domain
-- Reset    : synchronous active-high
--
-- Write interface:
--   wr_en   pulse '1' to write wr_data into the FIFO
--   full    '1' when no room remains; wr_en is ignored while full = '1'
--   wr_ack  '1' for one clock when a write was accepted
--
-- Read interface:
--   rd_en   pulse '1' to advance the read pointer and register rd_data
--   rd_data registered output; valid one clock after rd_en = '1'
--   empty   '1' when no data is available; rd_en ignored while empty = '1'
--   rd_valid '1' for one clock when rd_data is updated
--
-- Status:
--   level   current fill count (0 = empty, DEPTH = full), 20-bit unsigned
--   almost_full  '1' when level >= DEPTH - AF_THRESH  (default 4)
--   almost_empty '1' when level <= AE_THRESH          (default 4)
--
-- BRAM inference:
--   The internal array carries ram_style = "block" so Vivado infers
--   Block RAM tiles.  600 000 bits requires ceil(600000/32768) = 19 BRAM36.
--   The read port is registered (one-cycle latency) for clean BRAM mapping.
--
-- This module is STANDALONE — it has no connection to pal_tv_bram_top
-- or video_bram_top.  It is a general-purpose FIFO IP.
--
-- Timing budget (Artix-7 75T @ 40 MHz / 25 ns):
--   All paths register-to-register; critical path ~2 ns.  Easily met.

entity pal_fifo_bool is
  generic (
    DEPTH     : integer := 600000;  -- number of 1-bit entries
    AF_THRESH : integer := 4;       -- almost-full  threshold (entries from full)
    AE_THRESH : integer := 4        -- almost-empty threshold (entries from empty)
  );
  port (
    clk        : in  std_logic;
    rst        : in  std_logic;

    -- Write port
    wr_en      : in  std_logic;
    wr_data    : in  std_logic;          -- 1-bit Boolean value
    full       : out std_logic;
    wr_ack     : out std_logic;          -- '1' for one clock when write accepted

    -- Read port
    rd_en      : in  std_logic;
    rd_data    : out std_logic;          -- registered; valid one clock after rd_en
    empty      : out std_logic;
    rd_valid   : out std_logic;          -- '1' for one clock when rd_data updated

    -- Status
    level       : out std_logic_vector(19 downto 0);  -- fill count 0..DEPTH
    almost_full : out std_logic;
    almost_empty: out std_logic
  );
end entity pal_fifo_bool;

architecture rtl of pal_fifo_bool is

  -- -------------------------------------------------------------------------
  -- Internal 1-bit BRAM array
  -- -------------------------------------------------------------------------
  type fifo_mem_t is array (0 to DEPTH - 1) of std_logic;
  signal fifo_mem : fifo_mem_t := (others => '0');
  attribute ram_style              : string;
  attribute ram_style of fifo_mem  : signal is "block";

  -- -------------------------------------------------------------------------
  -- Pointers and fill counter
  -- -------------------------------------------------------------------------
  signal wr_ptr : integer range 0 to DEPTH - 1 := 0;
  signal rd_ptr : integer range 0 to DEPTH - 1 := 0;
  signal count  : integer range 0 to DEPTH     := 0;

  -- Internal flag signals
  signal full_s        : std_logic := '0';
  signal empty_s       : std_logic := '1';
  signal wr_ack_s      : std_logic := '0';
  signal rd_valid_s    : std_logic := '0';

begin

  -- -------------------------------------------------------------------------
  -- Elaboration-time checks
  -- -------------------------------------------------------------------------
  assert DEPTH > 0
    report "pal_fifo_bool: DEPTH must be > 0" severity failure;
  assert AF_THRESH >= 0 and AF_THRESH < DEPTH
    report "pal_fifo_bool: AF_THRESH out of range" severity failure;
  assert AE_THRESH >= 0 and AE_THRESH < DEPTH
    report "pal_fifo_bool: AE_THRESH out of range" severity failure;

  -- -------------------------------------------------------------------------
  -- Combinational flag decoding
  -- -------------------------------------------------------------------------
  full_s        <= '1' when count = DEPTH else '0';
  empty_s       <= '1' when count = 0     else '0';

  -- -------------------------------------------------------------------------
  -- Write process  (synchronous write to BRAM array)
  -- -------------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      wr_ack_s <= '0';
      if rst = '1' then
        wr_ptr <= 0;
      elsif wr_en = '1' and full_s = '0' then
        fifo_mem(wr_ptr) <= wr_data;
        -- Circular pointer wrap (non-power-of-2 safe)
        if wr_ptr = DEPTH - 1 then
          wr_ptr <= 0;
        else
          wr_ptr <= wr_ptr + 1;
        end if;
        wr_ack_s <= '1';
      end if;
    end if;
  end process;

  -- -------------------------------------------------------------------------
  -- Read process  (registered BRAM read output — 1-cycle latency)
  -- -------------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      rd_valid_s <= '0';
      if rst = '1' then
        rd_ptr  <= 0;
        rd_data <= '0';
      elsif rd_en = '1' and empty_s = '0' then
        rd_data    <= fifo_mem(rd_ptr);
        -- Circular pointer wrap
        if rd_ptr = DEPTH - 1 then
          rd_ptr <= 0;
        else
          rd_ptr <= rd_ptr + 1;
        end if;
        rd_valid_s <= '1';
      end if;
    end if;
  end process;

  -- -------------------------------------------------------------------------
  -- Fill counter  (handles simultaneous read + write correctly)
  -- -------------------------------------------------------------------------
  process(clk)
    variable do_wr : boolean;
    variable do_rd : boolean;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        count <= 0;
      else
        do_wr := (wr_en = '1') and (full_s  = '0');
        do_rd := (rd_en = '1') and (empty_s = '0');
        if do_wr and not do_rd then
          count <= count + 1;
        elsif do_rd and not do_wr then
          count <= count - 1;
        -- simultaneous valid read + write: count unchanged
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
  level        <= std_logic_vector(to_unsigned(count, 20));
  almost_full  <= '1' when count >= DEPTH - AF_THRESH else '0';
  almost_empty <= '1' when count <= AE_THRESH         else '0';

end architecture rtl;
