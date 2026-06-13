library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- ============================================================================
-- PAL Composite Video Decoder — Lite
-- ============================================================================
-- Stripped-down version of pal_decoder for minimal resource use.
--
-- Removed vs full version:
--   • h_count_o / v_count_o debug ports gone
--   • 6-stage pipeline collapsed to 3 stages
--   • Classifier merged into the counter process (one process fewer)
--
-- Kept:
--   clk, rst, adc_data
--   hsync_o  — one-cycle pulse per HSYNC
--   vsync_o  — one-cycle pulse per VSYNC
--   field_o  — toggles each frame (0=even, 1=odd)
--   y_data   — luminance during active video
--   y_valid  — '1' during active video window
--
-- ADC levels (8-bit default):
--   sync tip = 0, blanking = 77, white = 255
--   SYNC_THRESH generic = 50 (below this = inside sync pulse)
--
-- PAL 625-line, 64 µs/line:
--   HSYNC  3–9 µs   (classified by pulse width)
--   BROAD >15 µs   (vsync broad pulse)
--   EQ    <3 µs   (equalizing, ignored)
-- ============================================================================

entity pal_decoder_lite is
  generic (
    CLK_MHZ     : integer := 40;
    ADC_BITS    : integer := 8;
    SYNC_THRESH : integer := 50
  );
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;
    adc_data : in  std_logic_vector(ADC_BITS - 1 downto 0);
    hsync_o  : out std_logic;
    vsync_o  : out std_logic;
    field_o  : out std_logic;
    y_data   : out std_logic_vector(ADC_BITS - 1 downto 0);
    y_valid  : out std_logic
  );
end entity pal_decoder_lite;

architecture rtl of pal_decoder_lite is

  -- PAL timing constants
  constant C_LINE      : integer := CLK_MHZ * 64;
  constant C_BACK      : integer := CLK_MHZ * 58 / 10;      -- 5.8 µs back porch
  constant C_ACTIVE    : integer := CLK_MHZ * 520 / 10;     -- 52.0 µs active
  constant C_ACT_START : integer := C_BACK;
  constant C_ACT_END   : integer := C_ACT_START + C_ACTIVE - 1;
  constant C_HSYNC_MIN : integer := CLK_MHZ * 3;
  constant C_HSYNC_MAX : integer := CLK_MHZ * 9;
  constant C_BROAD_MIN : integer := CLK_MHZ * 15;
  constant C_LINES     : integer := 625;
  constant C_VACT_S    : integer := 22;
  constant C_VACT_E    : integer := 622;

  -- -------------------------------------------------------------------------
  -- Stage 1 — sync detector + pulse width counter
  --   Combines comparator, edge detection, and pulse measurement.
  --   Outputs: is_hsync, is_broad (one-cycle strobes)
  -- -------------------------------------------------------------------------
  signal in_sync    : std_logic;
  signal prev_sync  : std_logic := '0';
  signal sync_cnt   : integer range 0 to 131071 := 0;
  signal is_hsync   : std_logic := '0';
  signal is_broad   : std_logic := '0';

  -- -------------------------------------------------------------------------
  -- Stage 2 — horizontal + vertical counters, field, sync outputs
  -- -------------------------------------------------------------------------
  signal h_cnt      : integer range 0 to C_LINE  - 1 := 0;
  signal v_cnt      : integer range 0 to C_LINES - 1 := 0;
  signal broad_seen : std_logic := '0';
  signal hsync_r    : std_logic := '0';
  signal vsync_r    : std_logic := '0';
  signal field_r    : std_logic := '0';

  -- -------------------------------------------------------------------------
  -- Stage 3 — active video gate + Y output
  -- -------------------------------------------------------------------------
  signal h_active   : std_logic;
  signal v_active   : std_logic;
  signal valid_r    : std_logic := '0';
  signal y_r        : std_logic_vector(ADC_BITS - 1 downto 0) := (others => '0');

begin

  -- =========================================================================
  -- Stage 1: sync detection + pulse classification (single process)
  -- =========================================================================
  in_sync <= '1' when to_integer(unsigned(adc_data)) < SYNC_THRESH else '0';

  process(clk)
  begin
    if rising_edge(clk) then
      prev_sync <= in_sync;
      is_hsync  <= '0';
      is_broad  <= '0';

      if in_sync = '1' then
        if sync_cnt < 131071 then
          sync_cnt <= sync_cnt + 1;
        end if;
      else
        if prev_sync = '1' then        -- rising edge: pulse ended
          -- Classify and strobe output in the same cycle
          if sync_cnt >= C_HSYNC_MIN and sync_cnt <= C_HSYNC_MAX then
            is_hsync <= '1';
          elsif sync_cnt > C_BROAD_MIN then
            is_broad <= '1';
          end if;
        end if;
        sync_cnt <= 0;
      end if;
    end if;
  end process;

  -- =========================================================================
  -- Stage 2: H/V counters + sync outputs
  -- =========================================================================
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        h_cnt      <= 0;
        v_cnt      <= 0;
        broad_seen <= '0';
        hsync_r    <= '0';
        vsync_r    <= '0';
        field_r    <= '0';
      else
        hsync_r <= '0';
        vsync_r <= '0';

        if is_hsync = '1' or is_broad = '1' then
          h_cnt   <= 0;
          hsync_r <= is_hsync;
        else
          if h_cnt < C_LINE - 1 then
            h_cnt <= h_cnt + 1;
          end if;
        end if;

        if is_broad = '1' then
          if broad_seen = '0' then
            broad_seen <= '1';
            vsync_r    <= '1';
            v_cnt      <= 0;
            field_r    <= not field_r;
          end if;
        elsif is_hsync = '1' then
          broad_seen <= '0';
          if v_cnt < C_LINES - 1 then
            v_cnt <= v_cnt + 1;
          end if;
        end if;
      end if;
    end if;
  end process;

  -- =========================================================================
  -- Stage 3: active video gate + Y output
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
  -- Outputs
  -- =========================================================================
  hsync_o <= hsync_r;
  vsync_o <= vsync_r;
  field_o <= field_r;
  y_data  <= y_r;
  y_valid <= valid_r;

end architecture rtl;
