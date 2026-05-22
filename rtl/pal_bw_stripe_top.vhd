library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- PAL B&W Video -- Stripe Pattern Generator (no BRAM required)
-- Revision 3: runtime-controllable stripe width and direction.
--
-- stripe_width : U16 port -- pixels per stripe (vertical) or lines per stripe (horizontal)
-- stripe_dir   : Boolean  -- '0' = vertical stripes, '1' = horizontal stripes
--
-- Both inputs are sampled every frame so LabVIEW can change them live.
-- The change takes effect at the start of the next frame.
entity pal_bw_stripe_top is
  generic (
    H_FRONT    : integer := 16;
    H_SYNC_W   : integer := 47;
    H_BACK     : integer := 57;
    H_ACTIVE   : integer := 520;
    H_TOTAL    : integer := 640;
    V_SYNC_L   : integer := 5;
    V_BACK_L   : integer := 20;
    V_ACTIVE_L : integer := 576;
    V_TOTAL    : integer := 625;
    LEVEL_SYNC  : std_logic_vector(3 downto 0) := "0000";
    LEVEL_BLANK : std_logic_vector(3 downto 0) := "0100";
    LEVEL_WHITE : std_logic_vector(3 downto 0) := "1111";
    CLK_MHZ     : integer := 40   -- 10 / 20 / 30 / 40
  );
  port (
    clk          : in  std_logic;
    rst          : in  std_logic;

    -- Runtime stripe controls (from LabVIEW)
    stripe_width : in  std_logic_vector(15 downto 0);  -- U16: pixels or lines per stripe
    stripe_dir   : in  std_logic;   -- '0' = vertical, '1' = horizontal

    -- 4-bit DAC output -> NI-9401 DIO0-3
    dac_out      : out std_logic_vector(3 downto 0);

    -- Debug outputs
    hsync_o      : out std_logic;
    vsync_o      : out std_logic;
    active_o     : out std_logic
  );
end entity pal_bw_stripe_top;

architecture rtl of pal_bw_stripe_top is

  constant H_ACT_S  : integer := H_FRONT + H_SYNC_W + H_BACK;  -- 120
  constant V_ACT_S  : integer := V_SYNC_L + V_BACK_L;           -- 25

  signal h_cnt : integer range 0 to H_TOTAL - 1;
  signal v_cnt : integer range 0 to V_TOTAL - 1;
  signal ce_s  : std_logic;

  signal hsync_s  : std_logic;
  signal vsync_s  : std_logic;
  signal active_s : std_logic;
  signal blank_s  : std_logic;

  -- Vertical stripe counters (count pixels across each line)
  signal v_cnt_px    : unsigned(15 downto 0) := (others => '0');
  signal v_color     : std_logic := '0';  -- current vertical stripe colour

  -- Horizontal stripe counters (count active lines per frame)
  signal h_cnt_ln    : unsigned(15 downto 0) := (others => '0');
  signal h_color     : std_logic := '0';  -- current horizontal stripe colour

  -- Selected pixel colour fed to DAC mux
  signal pixel_color : std_logic;

begin

  u_timing : entity work.pal_timing
    generic map (H_TOTAL => H_TOTAL, V_TOTAL => V_TOTAL, CLK_MHZ => CLK_MHZ)
    port map (clk => clk, rst => rst, ce => ce_s, h_cnt => h_cnt, v_cnt => v_cnt);

  u_sync : entity work.pal_sync_gen
    generic map (
      H_FRONT    => H_FRONT,    H_SYNC_W   => H_SYNC_W,
      H_BACK     => H_BACK,     H_ACTIVE   => H_ACTIVE,
      H_TOTAL    => H_TOTAL,    V_SYNC_L   => V_SYNC_L,
      V_BACK_L   => V_BACK_L,  V_ACTIVE_L => V_ACTIVE_L,
      V_TOTAL    => V_TOTAL
    )
    port map (
      h_cnt  => h_cnt,   v_cnt  => v_cnt,
      hsync  => hsync_s, vsync  => vsync_s,
      active => active_s, blank => blank_s
    );

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
      pixel_in => pixel_color,
      dac_out  => dac_out
    );

  -- -----------------------------------------------------------------------
  -- Vertical stripe counter
  -- Counts pixels across each active line.
  -- Resets at the start of every active line (one pixel-clock before active).
  -- Toggles v_color every stripe_width pixels.
  -- -----------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        v_cnt_px <= (others => '0');
        v_color  <= '0';
      elsif ce_s = '1' then
        -- Pre-load: one cycle before the active window opens
        if h_cnt = H_ACT_S - 1 and
           v_cnt >= V_ACT_S and v_cnt < V_ACT_S + V_ACTIVE_L then
          v_cnt_px <= (others => '0');
          v_color  <= '0';                -- every line starts black
        elsif active_s = '1' then
          if v_cnt_px = unsigned(stripe_width) - 1 then
            v_cnt_px <= (others => '0');
            v_color  <= not v_color;
          else
            v_cnt_px <= v_cnt_px + 1;
          end if;
        end if;
      end if;
    end if;
  end process;

  -- -----------------------------------------------------------------------
  -- Horizontal stripe counter
  -- Counts active lines within each frame.
  -- Resets when the first active line begins (end of last V-back-porch line).
  -- Toggles h_color every stripe_width lines.
  -- -----------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        h_cnt_ln <= (others => '0');
        h_color  <= '0';
      elsif ce_s = '1' then
        -- Reset at end of the last blanking line before active region
        if v_cnt = V_ACT_S - 1 and h_cnt = H_TOTAL - 1 then
          h_cnt_ln <= (others => '0');
          h_color  <= '0';
        -- Increment once at the end of each active line
        elsif v_cnt >= V_ACT_S and v_cnt < V_ACT_S + V_ACTIVE_L and
              h_cnt = H_TOTAL - 1 then
          if h_cnt_ln = unsigned(stripe_width) - 1 then
            h_cnt_ln <= (others => '0');
            h_color  <= not h_color;
          else
            h_cnt_ln <= h_cnt_ln + 1;
          end if;
        end if;
      end if;
    end if;
  end process;

  -- Select stripe direction
  pixel_color <= h_color when stripe_dir = '1' else v_color;

  hsync_o  <= hsync_s;
  vsync_o  <= vsync_s;
  active_o <= active_s;

end architecture rtl;
