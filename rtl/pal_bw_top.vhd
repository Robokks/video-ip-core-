library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- PAL Black-and-White Composite Video IP Core
-- Clock  : 10 / 20 / 30 / 40 MHz selected via CLK_MHZ generic
-- Output : 4-bit DAC bus (drive an R-2R ladder or TLC7524 to get analog video)
-- Input  : single-port BRAM with 1-bit pixel data (1=white, 0=black)
-- The effective pixel rate is always 10 MHz; CLK_MHZ only selects the
-- input clock source.  All PAL timing and BRAM addressing are unchanged.
--
-- BRAM addressing: linear, row-major
--   address = (line * H_ACTIVE) + pixel_x
--   max address = (V_ACTIVE_L-1)*H_ACTIVE + (H_ACTIVE-1) = 299519 -> 19-bit address
--
-- BRAM read latency: 1 clock cycle.
-- The core issues the BRAM address one cycle ahead of the active window.
-- bram_en is asserted for h_cnt in [H_ACT_S-1, H_ACT_S+H_ACTIVE-2] during
-- active lines, which corresponds to pixels 0..519 fetched one cycle early.
--
-- DAC R-2R ladder (recommended):
--   Connect dac_out[3:0] to a 4-bit R-2R ladder (R=75ohm, 2R=150ohm).
--   The ladder output drives the composite video line through a 75 ohm series
--   resistor into a 75 ohm coax load.
entity pal_bw_top is
  generic (
    -- Horizontal timing (clocks, must sum to H_TOTAL)
    H_FRONT    : integer := 16;   -- front porch
    H_SYNC_W   : integer := 47;   -- H-sync pulse
    H_BACK     : integer := 57;   -- back porch
    H_ACTIVE   : integer := 520;  -- active pixels
    H_TOTAL    : integer := 640;  -- total clocks per line
    -- Vertical timing (lines, V_SYNC_L+V_BACK_L+V_ACTIVE_L+V_FRONT_L = V_TOTAL)
    V_SYNC_L   : integer := 5;    -- broad vsync lines
    V_BACK_L   : integer := 20;   -- V back porch lines
    V_ACTIVE_L : integer := 576;  -- active picture lines
    V_TOTAL    : integer := 625;  -- total lines per frame
    -- 4-bit DAC levels
    LEVEL_SYNC  : std_logic_vector(3 downto 0) := "0000";
    LEVEL_BLANK : std_logic_vector(3 downto 0) := "0100";
    LEVEL_WHITE : std_logic_vector(3 downto 0) := "1111";
    -- Input clock selection: 10, 20, 30, or 40 (MHz)
    -- 10 -> no division   (10 MHz clock input, e.g. cRIO-9056 10 MHz base)
    -- 20 -> divide by 2   (20 MHz clock input)
    -- 30 -> divide by 3   (30 MHz clock input)
    -- 40 -> divide by 4   (40 MHz primary clock, e.g. cRIO-9056 default)
    CLK_MHZ     : integer := 10
  );
  port (
    clk       : in  std_logic;   -- input clock: 10 / 20 / 30 / 40 MHz (set CLK_MHZ)
    rst       : in  std_logic;   -- synchronous reset, active-high

    -- BRAM interface (connect to user's BRAM port A)
    bram_clk  : out std_logic;                        -- = clk pass-through
    bram_en   : out std_logic;
    bram_we   : out std_logic;                        -- always '0' (read-only)
    bram_addr : out std_logic_vector(18 downto 0);    -- row-major pixel address
    bram_din  : in  std_logic;                        -- 1-bit pixel from BRAM

    -- 4-bit DAC output
    dac_out   : out std_logic_vector(3 downto 0);

    -- Debug / external sync outputs
    hsync_o   : out std_logic;   -- H-sync pulse (positive)
    vsync_o   : out std_logic;   -- V-sync pulse (positive)
    active_o  : out std_logic    -- active pixel window
  );
end entity pal_bw_top;

architecture rtl of pal_bw_top is

  -- Derived timing constants
  constant H_SYNC_S : integer := H_FRONT;
  constant H_BACK_S : integer := H_FRONT + H_SYNC_W;
  constant H_ACT_S  : integer := H_FRONT + H_SYNC_W + H_BACK;  -- 120
  constant V_ACT_S  : integer := V_SYNC_L + V_BACK_L;           -- 25

  -- H range for BRAM pre-fetch (one cycle early: [H_ACT_S-1, H_ACT_S+H_ACTIVE-2])
  constant H_BRAM_START : integer := H_ACT_S - 1;                -- 119
  constant H_BRAM_END   : integer := H_ACT_S + H_ACTIVE - 2;     -- 638

  signal h_cnt : integer range 0 to H_TOTAL - 1;
  signal v_cnt : integer range 0 to V_TOTAL - 1;
  signal ce_s  : std_logic;   -- 10 MHz pixel clock enable from pal_timing

  signal hsync_s  : std_logic;
  signal vsync_s  : std_logic;
  signal active_s : std_logic;
  signal blank_s  : std_logic;

  -- BRAM enable / address (combinational)
  signal bram_en_s   : std_logic;
  signal bram_addr_s : unsigned(18 downto 0);

begin

  assert H_FRONT + H_SYNC_W + H_BACK + H_ACTIVE = H_TOTAL
    report "H timing parameters must sum to H_TOTAL" severity failure;

  assert V_SYNC_L + V_BACK_L + V_ACTIVE_L < V_TOTAL
    report "V active region exceeds V_TOTAL" severity failure;

  -- H/V counter with clock-enable divider
  u_timing : entity work.pal_timing
    generic map (H_TOTAL => H_TOTAL, V_TOTAL => V_TOTAL, CLK_MHZ => CLK_MHZ)
    port map (clk => clk, rst => rst, ce => ce_s, h_cnt => h_cnt, v_cnt => v_cnt);

  -- Region flag decode
  u_sync : entity work.pal_sync_gen
    generic map (
      H_FRONT    => H_FRONT,    H_SYNC_W   => H_SYNC_W,
      H_BACK     => H_BACK,     H_ACTIVE   => H_ACTIVE,
      H_TOTAL    => H_TOTAL,    V_SYNC_L   => V_SYNC_L,
      V_BACK_L   => V_BACK_L,  V_ACTIVE_L => V_ACTIVE_L,
      V_TOTAL    => V_TOTAL
    )
    port map (
      h_cnt  => h_cnt,  v_cnt  => v_cnt,
      hsync  => hsync_s, vsync  => vsync_s,
      active => active_s, blank => blank_s
    );

  -- DAC level mux (combinational)
  u_mux : entity work.pal_dac_mux
    generic map (
      LEVEL_SYNC  => LEVEL_SYNC,
      LEVEL_BLANK => LEVEL_BLANK,
      LEVEL_WHITE => LEVEL_WHITE
    )
    port map (
      vsync    => vsync_s,
      hsync    => hsync_s,
      active   => active_s,
      pixel_in => bram_din,
      dac_out  => dac_out
    );

  -- BRAM address: linear row-major, issued one cycle before active window
  -- so BRAM read latency (1 cycle) is absorbed.
  -- address = line * H_ACTIVE + pixel_x_next
  -- where pixel_x_next = h_cnt - H_ACT_S + 1  (valid when h_cnt in [H_BRAM_START, H_BRAM_END])
  process(h_cnt, v_cnt)
    variable line    : integer;
    variable px_next : integer;
  begin
    bram_en_s   <= '0';
    bram_addr_s <= (others => '0');

    if (v_cnt >= V_ACT_S) and (v_cnt < V_ACT_S + V_ACTIVE_L) then
      if (h_cnt >= H_BRAM_START) and (h_cnt <= H_BRAM_END) then
        line    := v_cnt - V_ACT_S;
        px_next := h_cnt - H_ACT_S + 1;   -- +1 accounts for 1-cycle BRAM latency
        bram_en_s   <= '1';
        bram_addr_s <= to_unsigned(line * H_ACTIVE + px_next, 19);
      end if;
    end if;
  end process;

  -- Output drivers
  bram_clk  <= clk;
  bram_we   <= '0';
  bram_en   <= bram_en_s;
  bram_addr <= std_logic_vector(bram_addr_s);

  hsync_o  <= hsync_s;
  vsync_o  <= vsync_s;
  active_o <= active_s;

end architecture rtl;
