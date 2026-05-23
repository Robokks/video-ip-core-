library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- pal_bram_loader
-- ===========================================================================
-- Reads 1-bit pixels from a FIFO and writes them sequentially to the BRAM
-- write port of pal_tv_bram_top (addresses 0 .. TOTAL_PX-1).
--
-- Typical flow
-- ------------
--   1. Host dumps all TOTAL_PX pixels into the FIFO at any speed (Boolean
--      elements: 0=black, 1=white; row 0 first, row 575 last).
--   2. Host sets start = TRUE for at least one clock cycle.
--   3. This core drains the FIFO at full FPGA clock speed and writes every
--      pixel to pal_tv_bram_top's BRAM write port.
--        At 10 MHz : 299 520 pixels → ~60 ms   (1 pixel per 2 clocks)
--        At 40 MHz : 299 520 pixels → ~15 ms
--   4. done = TRUE when the last pixel has been written.
--      Set pal_tv_bram_top sel = x"04" and release rst to start playback.
--
-- Re-trigger: assert start again (while done is HIGH or after it) to reload.
-- Stall-safe: if FIFO runs empty mid-load, this core pauses and resumes
--             automatically when more data arrives.
--
-- FIFO timing
-- -----------
-- Assumes 1-clock read latency:
--   Cycle N   : fifo_rd = '1' (read request issued to FIFO)
--   Cycle N+1 : fifo_data = valid pixel (registered output of FIFO)
-- This matches the LabVIEW FPGA SCTL inter-node pipeline delay for a
-- Target-Scoped or DMA FIFO accessed inside a Single-Cycle Timed Loop.
--
-- LabVIEW FPGA wiring (inside SCTL)
-- -----------------------------------
--   fifo_rd   (output, Boolean) ─► FIFO "Read"    terminal
--   fifo_data (input,  Boolean) ◄─ FIFO "Element" terminal   (1-cycle latency)
--   fifo_empty(input,  Boolean) ◄─ FIFO "Empty"   terminal
--
--   bram_wr_en   ─► pal_tv_bram_top  bram_wr_en
--   bram_wr_addr ─► pal_tv_bram_top  bram_wr_addr  (U32, lower 19 bits)
--   bram_wr_data ─► pal_tv_bram_top  bram_wr_data
--
--   start ◄─ host control register (Boolean)
--   done  ─► host status  register (Boolean)
--   busy  ─► host status  register (Boolean)
-- ===========================================================================

entity pal_bram_loader is
  generic (
    TOTAL_PX  : integer := 299520;  -- 520 * 576 pixels (full PAL frame)
    ADDR_BITS : integer := 19       -- address width  (2^19 = 524288 > 299520)
  );
  port (
    clk  : in  std_logic;
    rst  : in  std_logic;

    -- -----------------------------------------------------------------------
    -- Host control
    -- -----------------------------------------------------------------------
    start : in  std_logic;   -- hold HIGH ≥1 clock when FIFO is fully loaded
    done  : out std_logic;   -- HIGH when all TOTAL_PX pixels written to BRAM
    busy  : out std_logic;   -- HIGH while loading is in progress

    -- -----------------------------------------------------------------------
    -- FIFO read interface  (Boolean per pixel, 1-clock read latency)
    -- -----------------------------------------------------------------------
    fifo_data  : in  std_logic;  -- pixel (0=black, 1=white); valid 1 clk after fifo_rd
    fifo_empty : in  std_logic;  -- '1' when FIFO has no data
    fifo_rd    : out std_logic;  -- pulse '1' to consume one element (data valid next clk)

    -- -----------------------------------------------------------------------
    -- BRAM write port  ─►  connect directly to pal_tv_bram_top
    -- -----------------------------------------------------------------------
    bram_wr_en   : out std_logic;
    bram_wr_addr : out std_logic_vector(ADDR_BITS - 1 downto 0);
    bram_wr_data : out std_logic
  );
end entity pal_bram_loader;

architecture rtl of pal_bram_loader is

  type state_t is (S_IDLE, S_LOADING, S_DONE);
  signal state : state_t := S_IDLE;

  -- Number of pixels written to BRAM so far
  signal writes_done  : integer range 0 to TOTAL_PX := 0;

  -- '1' while a FIFO read is in flight (issued but data not yet received)
  signal read_pending : std_logic := '0';

  -- Internal drives
  signal fifo_rd_i : std_logic := '0';  -- drives fifo_rd port
  signal fifo_rd_r : std_logic := '0';  -- registered fifo_rd_i: '1' → data valid

begin

  fifo_rd <= fifo_rd_i;

  -- =========================================================================
  -- Main process
  -- Uses VARIABLES for read_pending and writes_done so that within a single
  -- clock cycle the "process response → issue next read" sequence can observe
  -- the just-updated values.  This prevents spurious reads at FIFO boundaries.
  -- =========================================================================
  process(clk)
    variable pend_v   : std_logic;
    variable writes_v : integer range 0 to TOTAL_PX;
  begin
    if rising_edge(clk) then

      -- Latch current signal values into working variables
      pend_v   := read_pending;
      writes_v := writes_done;

      -- Default pulse outputs
      fifo_rd_i  <= '0';
      bram_wr_en <= '0';

      -- Pipeline: '1' next cycle means fifo_data is valid
      fifo_rd_r <= fifo_rd_i;

      -- ----------------------------------------------------------------
      -- Reset
      -- ----------------------------------------------------------------
      if rst = '1' then
        state        <= S_IDLE;
        writes_done  <= 0;
        read_pending <= '0';
        done         <= '0';
        busy         <= '0';
        fifo_rd_r    <= '0';

      else
        case state is

          -- --------------------------------------------------------------
          -- IDLE: wait for host start signal
          -- --------------------------------------------------------------
          when S_IDLE =>
            done         <= '0';
            busy         <= '0';
            writes_v     := 0;
            pend_v       := '0';
            if start = '1' then
              state <= S_LOADING;
              busy  <= '1';
            end if;

          -- --------------------------------------------------------------
          -- LOADING: drain FIFO → write BRAM
          --
          -- Two steps execute within a SINGLE clock cycle using variables:
          --   Step 1: if fifo_rd_r='1', write the pixel that arrived this
          --           cycle; clear pending flag.
          --   Step 2: if no read pending, FIFO not empty, and pixels remain,
          --           issue the next read.
          -- This overlapping avoids stalls between consecutive reads.
          -- --------------------------------------------------------------
          when S_LOADING =>
            busy <= '1';

            -- Step 1 – process FIFO response (data valid this cycle)
            if fifo_rd_r = '1' then
              bram_wr_en   <= '1';
              bram_wr_data <= fifo_data;
              bram_wr_addr <= std_logic_vector(to_unsigned(writes_v, ADDR_BITS));
              writes_v     := writes_v + 1;   -- update variable immediately
              pend_v       := '0';            -- read_pending cleared
              if writes_v = TOTAL_PX then     -- uses UPDATED writes_v
                state <= S_DONE;
              end if;
            end if;

            -- Step 2 – issue next FIFO read if possible (uses UPDATED variables)
            if pend_v = '0' and fifo_empty = '0' and writes_v < TOTAL_PX then
              fifo_rd_i <= '1';
              pend_v    := '1';
            end if;

            -- Commit variables back to signals
            writes_done  <= writes_v;
            read_pending <= pend_v;

          -- --------------------------------------------------------------
          -- DONE: hold done flag; re-trigger supported
          -- --------------------------------------------------------------
          when S_DONE =>
            busy         <= '0';
            done         <= '1';
            pend_v       := '0';
            read_pending <= '0';
            if start = '1' then
              state       <= S_LOADING;
              done        <= '0';
              busy        <= '1';
              writes_v    := 0;
              writes_done <= 0;
            end if;

        end case;
      end if;
    end if;
  end process;

end architecture rtl;
