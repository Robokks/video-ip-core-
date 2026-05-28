library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ============================================================================
-- PAL Composite Video Decoder  (625-line, 25 fps, B&W luminance path)
-- ============================================================================
--
-- Takes the digital output of an external ADC connected to a PAL composite
-- video source and recovers:
--   • HSYNC / VSYNC pulses
--   • Field polarity (odd / even)
--   • Luminance (Y) byte-stream during active video
--   • Horizontal and vertical position counters
--
-- ADC level assumptions (8-bit, 0–255):
--   Sync tip  : ~  0  (–300 mV of composite = 0 V into ADC)
--   Blanking  : ~ 77  (   0 mV IRE)
--   White     :  255  ( 700 mV IRE)
--   Sync threshold SYNC_THRESH default = 50
--     → signal below 50 = inside a sync pulse
--
-- PAL line timing (64 µs) at CLK_MHZ:
--   ┌──────────┬──────────┬────────────────────────────────┬──────────┐
--   │  H-SYNC  │ Back     │      Active Video              │  Front   │
--   │  4.7 µs  │ porch    │      ~52.0 µs                  │  porch   │
--   │          │ 5.8 µs   │                                │  1.5 µs  │
--   └──────────┴──────────┴────────────────────────────────┴──────────┘
--   h_count=0 on the clock cycle AFTER the last sync sample.
--
-- Vertical timing (625 lines):
--   Lines  0– 21 : top blanking + VSYNC interval
--   Lines 22–622 : active video  (601 lines visible)
--   Lines 623–624: bottom blanking
--
-- VSYNC detection:
--   PAL vsync contains 5 "broad" pulses (~27.3 µs each).
--   The FIRST broad pulse triggers vsync_o and resets v_count to 0.
--   Equalizing pulses (~2.35 µs) are narrower than HSYNC and ignored.
--
-- Sync pulse classification (by measured width):
--   Equalizing : < C_HSYNC_MIN  → ignored
--   H-SYNC     : C_HSYNC_MIN .. C_HSYNC_MAX (3–9 µs window)
--   Broad      : > C_BROAD_MIN (> 15 µs)
--
-- CLK_MHZ generic: 10 / 20 / 30 / 40  (must match board clock)
-- ============================================================================

entity pal_decoder is
  generic (
    CLK_MHZ     : integer := 40;   -- board clock frequency (10/20/30/40)
    ADC_BITS    : integer := 8;    -- ADC resolution (typically 8 or 10)
    SYNC_THRESH : integer := 50    -- ADC value below which = sync region
  );
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;      -- synchronous reset, active-high

    -- ADC input: raw composite PAL signal (unsigned, unsigned-binary)
    adc_data : in  std_logic_vector(ADC_BITS - 1 downto 0);

    -- Recovered sync
    hsync_o  : out std_logic;      -- '1' for one cycle per HSYNC event
    vsync_o  : out std_logic;      -- '1' for one cycle per VSYNC event
    field_o  : out std_logic;      -- toggles each frame: 0=even, 1=odd

    -- Luminance output
    y_data   : out std_logic_vector(ADC_BITS - 1 downto 0);  -- ADC during active video
    y_valid  : out std_logic;      -- '1' during active video window

    -- Position counters (for downstream processing / debug)
    h_count_o : out std_logic_vector(11 downto 0);  -- 0 .. C_LINE-1
    v_count_o : out std_logic_vector(9  downto 0)   -- 0 .. 624
  );
end entity pal_decoder;

architecture rtl of pal_decoder is

  -- -------------------------------------------------------------------------
  -- PAL timing constants (clock cycles at CLK_MHZ)
  -- -------------------------------------------------------------------------
  constant C_LINE      : integer := CLK_MHZ * 64;          -- 2560 @ 40 MHz
  constant C_SYNC_W    : integer := CLK_MHZ * 47 / 10;     -- 4.7 µs  = 188
  constant C_BACK      : integer := CLK_MHZ * 58 / 10;     -- 5.8 µs  = 232
  constant C_FRONT     : integer := CLK_MHZ * 15 / 10;     -- 1.5 µs  =  60
  constant C_ACTIVE    : integer := CLK_MHZ * 520 / 10;    -- 52.0 µs = 2080
  -- h_count is 0 at the sample JUST AFTER the sync pulse ends (back porch start)
  constant C_ACT_START : integer := C_BACK;                 -- 232
  constant C_ACT_END   : integer := C_ACT_START + C_ACTIVE - 1; -- 2311

  -- Sync pulse width limits (clock cycles)
  constant C_HSYNC_MIN : integer := CLK_MHZ * 3;           -- 3 µs  = 120
  constant C_HSYNC_MAX : integer := CLK_MHZ * 9;           -- 9 µs  = 360
  constant C_BROAD_MIN : integer := CLK_MHZ * 15;          -- 15 µs = 600

  -- Vertical timing (line numbers)
  constant C_LINES     : integer := 625;
  constant C_VACT_S    : integer := 22;    -- first active line
  constant C_VACT_E    : integer := 622;   -- last  active line

  -- -------------------------------------------------------------------------
  -- Stage 1 — sync level comparator (combinational)
  -- -------------------------------------------------------------------------
  signal in_sync   : std_logic;

  -- -------------------------------------------------------------------------
  -- Stage 2 — sync pulse width counter
  -- -------------------------------------------------------------------------
  signal prev_sync   : std_logic := '0';
  signal sync_cnt    : integer range 0 to 131071 := 0;
  signal pulse_done  : std_logic := '0';   -- '1' for 1 cycle on pulse end
  signal pulse_len   : integer range 0 to 131071 := 0;

  -- -------------------------------------------------------------------------
  -- Stage 3 — pulse classifier
  -- -------------------------------------------------------------------------
  signal is_hsync    : std_logic := '0';   -- normal H-sync pulse
  signal is_broad    : std_logic := '0';   -- broad V-sync pulse

  -- -------------------------------------------------------------------------
  -- Stage 4 — horizontal counter
  -- -------------------------------------------------------------------------
  signal h_cnt       : integer range 0 to C_LINE - 1 := 0;
  signal hsync_r     : std_logic := '0';

  -- -------------------------------------------------------------------------
  -- Stage 5 — vertical counter, field, VSYNC
  -- -------------------------------------------------------------------------
  signal v_cnt       : integer range 0 to C_LINES - 1 := 0;
  signal broad_seen  : std_logic := '0';
  signal vsync_r     : std_logic := '0';
  signal field_r     : std_logic := '0';

  -- -------------------------------------------------------------------------
  -- Stage 6 — active video gate + Y output
  -- -------------------------------------------------------------------------
  signal h_active    : std_logic;
  signal v_active    : std_logic;
  signal valid_r     : std_logic := '0';
  signal y_r         : std_logic_vector(ADC_BITS - 1 downto 0) := (others => '0');

begin

  -- =========================================================================
  -- Stage 1: sync level comparator
  -- =========================================================================
  in_sync <= '1' when to_integer(unsigned(adc_data)) < SYNC_THRESH else '0';

  -- =========================================================================
  -- Stage 2: sync pulse width measurement
  --
  --   pulse_done = '1' for exactly one clock after each sync pulse ends.
  --   pulse_len  = total clock cycles the pulse was low (sync tip duration).
  -- =========================================================================
  process(clk)
  begin
    if rising_edge(clk) then
      prev_sync  <= in_sync;
      pulse_done <= '0';

      if in_sync = '1' then
        if sync_cnt < 131071 then
          sync_cnt <= sync_cnt + 1;
        end if;
      else
        if prev_sync = '1' then      -- rising edge: pulse just finished
          pulse_done <= '1';
          pulse_len  <= sync_cnt;
        end if;
        sync_cnt <= 0;
      end if;
    end if;
  end process;

  -- =========================================================================
  -- Stage 3: classify completed pulse (registered, 1 cycle after pulse_done)
  -- =========================================================================
  process(clk)
  begin
    if rising_edge(clk) then
      is_hsync <= '0';
      is_broad <= '0';
      if pulse_done = '1' then
        if pulse_len >= C_HSYNC_MIN and pulse_len <= C_HSYNC_MAX then
          is_hsync <= '1';            -- normal H-sync (3–9 µs)
        elsif pulse_len > C_BROAD_MIN then
          is_broad <= '1';            -- broad vsync pulse (> 15 µs)
        end if;
        -- Equalizing pulses (< 3 µs) are ignored
      end if;
    end if;
  end process;

  -- =========================================================================
  -- Stage 4: horizontal counter
  --   h_cnt = 0 on the clock cycle where is_hsync or is_broad fires,
  --   representing the start of the back-porch / sync-end boundary.
  -- =========================================================================
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        h_cnt   <= 0;
        hsync_r <= '0';
      elsif is_hsync = '1' or is_broad = '1' then
        h_cnt   <= 0;
        hsync_r <= is_hsync;         -- hsync pulse only on normal H-sync
      else
        hsync_r <= '0';
        if h_cnt < C_LINE - 1 then
          h_cnt <= h_cnt + 1;
        end if;
      end if;
    end if;
  end process;

  -- =========================================================================
  -- Stage 5: vertical counter, field detection, VSYNC
  -- =========================================================================
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        v_cnt     <= 0;
        broad_seen <= '0';
        vsync_r   <= '0';
        field_r   <= '0';
      else
        vsync_r <= '0';

        if is_broad = '1' then
          if broad_seen = '0' then
            -- First broad pulse of vsync interval
            broad_seen <= '1';
            vsync_r    <= '1';       -- one-cycle vsync strobe
            v_cnt      <= 0;
            field_r    <= not field_r;
          end if;
          -- Subsequent broad pulses in same vsync interval: ignored

        elsif is_hsync = '1' then
          broad_seen <= '0';         -- clear once normal HSYNCs resume
          if v_cnt < C_LINES - 1 then
            v_cnt <= v_cnt + 1;
          end if;
        end if;
      end if;
    end if;
  end process;

  -- =========================================================================
  -- Stage 6: active video gating + luminance output
  -- =========================================================================
  h_active <= '1' when h_cnt >= C_ACT_START and h_cnt <= C_ACT_END else '0';
  v_active <= '1' when v_cnt >= C_VACT_S    and v_cnt <= C_VACT_E   else '0';

  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        valid_r <= '0';
        y_r     <= (others => '0');
      else
        valid_r <= h_active and v_active;
        if h_active = '1' and v_active = '1' then
          y_r <= adc_data;
        else
          y_r <= (others => '0');
        end if;
      end if;
    end if;
  end process;

  -- =========================================================================
  -- Output connections
  -- =========================================================================
  hsync_o   <= hsync_r;
  vsync_o   <= vsync_r;
  field_o   <= field_r;
  y_data    <= y_r;
  y_valid   <= valid_r;
  h_count_o <= std_logic_vector(to_unsigned(h_cnt, 12));
  v_count_o <= std_logic_vector(to_unsigned(v_cnt, 10));

end architecture rtl;
