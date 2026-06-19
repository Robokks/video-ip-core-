library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- PAL B&W BRAM Video IP  --  Lite v4
-- =====================================
--
-- Based on Lite v2. Timing generic defaults updated to match
-- NEW tester oscilloscope observations (FSS issue fixed).
--
-- sel 0  Vertical bars
-- sel 1  Horizontal bars
-- sel 2  Horizontal gradient  (10 grey steps, ends white)
-- sel 3  Vertical gradient    (10 grey steps, ends white)
-- sel 4  BRAM pixel source    (0=black_lvl, 1=brightness)
-- sel 5  Horizontal gradient, black end  (10 grey steps + 1 black zone = 11 zones)
-- sel 6  Vertical gradient,   black end  (10 grey steps + 1 black zone = 11 zones)
--
-- BRAM pixel layout (sel 4):
--   Write image rows 0,1,2,...,575 sequentially into the BRAM.
--   Interlaced stride: F1 reads rows 0,2,4,...  F2 reads rows 1,3,5,...
--   Host writes are live-mapped; no buf_swap or back-buffer.
--
-- Dependencies (3 files only):
--   tv/pal_timing.vhd
--   tv/opt2_interlaced/pal_csync_il.vhd
--   tv/bram/pal_tv_bram_lite_v4.vhd  (this file)

entity pal_tv_bram_lite_v4 is
  generic (
    H_FRONT    : integer := 16;
    H_SYNC_W   : integer := 47;
    H_BACK     : integer := 57;
    H_ACTIVE   : integer := 520;
    H_TOTAL    : integer := 640;
    V_TOTAL    : integer := 625;
    LEVEL_SYNC : std_logic_vector(3 downto 0) := "0000";
    LEVEL_BLANK: std_logic_vector(3 downto 0) := "0100";
    LEVEL_WHITE: std_logic_vector(3 downto 0) := "1111";
    CLK_MHZ    : integer := 40;
    STRIPE_W   : integer := 4;
    BRAM_DEPTH : integer := 299520;
    -- Active video / composite blank boundaries (PAL standard: F1=lines 23-310, F2=lines 336-623)
    V_ACT_S_F1 : integer := 22;
    V_ACT_E_F1 : integer := 309;
    V_ACT_S_F2 : integer := 335;
    V_ACT_E_F2 : integer := 622;
    -- FSS boundaries (Field Sync Signal, override without recompile)
    FSS_F1_S   : integer := 3;    -- F1 FSS start v_cnt
    FSS_F1_E   : integer := 7;    -- F1 FSS end v_cnt
    FSS_F2_SV  : integer := 315;  -- F2 FSS start v_cnt
    FSS_F2_SH  : integer := 320;  -- F2 FSS start h_cnt threshold (h >= this)
    FSS_F2_EV  : integer := 320;  -- F2 FSS end v_cnt
    FSS_F2_EH  : integer := 320   -- F2 FSS end h_cnt threshold (h < this)
  );
  port (
    clk          : in  std_logic;
    rst          : in  std_logic;
    -- Pattern select: 0=V-bars 1=H-bars 2=H-grad 3=V-grad 4=BRAM 5=H-grad-Bend 6=V-grad-Bend
    sel          : in  std_logic_vector(7 downto 0);
    -- DAC levels
    brightness   : in  std_logic_vector(3 downto 0) := "1111";
    black_lvl    : in  std_logic_vector(3 downto 0) := "0100";
    -- BRAM write port (sel=4 only)
    bram_wr_en   : in  std_logic                     := '0';
    bram_wr_addr : in  std_logic_vector(18 downto 0) := (others => '0');
    bram_wr_data : in  std_logic                     := '0';
    bram_len     : in  std_logic_vector(18 downto 0) := (others => '1');
    -- Runtime timing control (write from CRIO/host at runtime; 0 = use generic default)
    -- Active video / composite blank window
    v_act_s_f1_p : in  std_logic_vector(9 downto 0) := (others => '0');
    v_act_e_f1_p : in  std_logic_vector(9 downto 0) := (others => '0');
    v_act_s_f2_p : in  std_logic_vector(9 downto 0) := (others => '0');
    v_act_e_f2_p : in  std_logic_vector(9 downto 0) := (others => '0');
    -- FSS (Field Sync Signal) boundaries
    fss_f1_s_p   : in  std_logic_vector(9 downto 0) := (others => '0');
    fss_f1_e_p   : in  std_logic_vector(9 downto 0) := (others => '0');
    fss_f2_sv_p  : in  std_logic_vector(9 downto 0) := (others => '0');
    fss_f2_sh_p  : in  std_logic_vector(9 downto 0) := (others => '0');
    fss_f2_ev_p  : in  std_logic_vector(9 downto 0) := (others => '0');
    fss_f2_eh_p  : in  std_logic_vector(9 downto 0) := (others => '0');
    -- Video outputs
    dac_out      : out std_logic_vector(3 downto 0);
    csync_o      : out std_logic;
    line_sync_o  : out std_logic;
    frame_sync_o : out std_logic;
    fss_o        : out std_logic;   -- Field Sync Signal 50 Hz (broad-sync + post-EQ of every field)
    field_o      : out std_logic;
    active_o     : out std_logic;
    blank_o      : out std_logic
  );
end entity pal_tv_bram_lite_v4;

architecture rtl of pal_tv_bram_lite_v4 is

  constant H_ACT_S    : integer := H_FRONT + H_SYNC_W + H_BACK;  -- 120
  constant V_ACTIVE_F : integer := 288;   -- active lines per field

  -- Runtime timing integers (resolved from port; falls back to generic if port = 0)
  signal v_act_s_f1_i : integer range 0 to 624 := V_ACT_S_F1;
  signal v_act_e_f1_i : integer range 0 to 624 := V_ACT_E_F1;
  signal v_act_s_f2_i : integer range 0 to 624 := V_ACT_S_F2;
  signal v_act_e_f2_i : integer range 0 to 624 := V_ACT_E_F2;
  signal fss_f1_s_i   : integer range 0 to 624 := FSS_F1_S;
  signal fss_f1_e_i   : integer range 0 to 624 := FSS_F1_E;
  signal fss_f2_sv_i  : integer range 0 to 624 := FSS_F2_SV;
  signal fss_f2_sh_i  : integer range 0 to 639 := FSS_F2_SH;
  signal fss_f2_ev_i  : integer range 0 to 624 := FSS_F2_EV;
  signal fss_f2_eh_i  : integer range 0 to 639 := FSS_F2_EH;

  -- Zone / gradient constants
  constant NUM_ZONES  : integer := 8;
  constant ZONE_W     : integer := H_ACTIVE  / NUM_ZONES;   -- 65
  constant ZONE_H     : integer := V_ACTIVE_F / NUM_ZONES;  -- 36
  constant GZONES     : integer := 10;
  constant GZONE_W    : integer := H_ACTIVE  / GZONES;      -- 52
  constant GZONE_H    : integer := V_ACTIVE_F / GZONES;     -- 28
  -- sel 5/6: 11-zone gradient (10 grey + 1 black end)
  constant GZONES_B   : integer := 11;
  constant GZONE_W_B  : integer := H_ACTIVE  / GZONES_B;   -- 47
  constant GZONE_H_B  : integer := V_ACTIVE_F / GZONES_B;  -- 26

  type zone_kind    is (Z_BLACK, Z_WHITE, Z_STRIPE);
  type zone_table_t is array (0 to NUM_ZONES - 1) of zone_kind;
  constant ZONE_TABLE : zone_table_t := (
    0 => Z_STRIPE, 1 => Z_WHITE,  2 => Z_STRIPE, 3 => Z_WHITE,
    4 => Z_BLACK,  5 => Z_STRIPE, 6 => Z_WHITE,  7 => Z_STRIPE
  );

  -- Single BRAM frame buffer (no double-buffer)
  type bram_t is array (0 to BRAM_DEPTH - 1) of std_logic;
  signal bram_mem     : bram_t := (others => '0');
  attribute ram_style             : string;
  attribute ram_style of bram_mem : signal is "block";

  signal bram_rd_line_base : integer := 0;
  signal bram_px_cnt  : integer range 0 to H_ACTIVE - 1 := 0;
  signal bram_rd_sum  : integer := 0;
  signal bram_rd_addr : integer range 0 to BRAM_DEPTH - 1 := 0;
  signal bram_pixel   : std_logic := '0';
  signal bram_len_i   : integer range 1 to BRAM_DEPTH;
  signal bram_level   : std_logic_vector(3 downto 0);

  -- H/V counters and pixel clock enable
  signal h_cnt : integer range 0 to 639;
  signal v_cnt : integer range 0 to 624;
  signal ce_s  : std_logic;

  -- Sync signals from pal_csync_il
  signal csync_s   : std_logic;
  signal field_s   : std_logic;
  signal active_s  : std_logic;

  -- Derived sync
  signal in_vsync_s   : std_logic;
  signal fss_s        : std_logic;
  signal line_sync_s  : std_logic;
  signal frame_sync_s : std_logic;

  -- Active region flags
  signal in_f1_active  : boolean;
  signal in_f2_active  : boolean;
  signal in_any_active : boolean;

  -- Vertical bar counters
  signal zone_idx_v   : integer range 0 to NUM_ZONES - 1 := 0;
  signal px_in_zone   : integer range 0 to ZONE_W - 1    := 0;
  signal stripe_cnt_v : integer range 0 to STRIPE_W - 1  := 0;
  signal stripe_ph_v  : std_logic                        := '0';

  -- Horizontal bar counters
  signal zone_idx_h   : integer range 0 to NUM_ZONES - 1 := 0;
  signal line_in_zone : integer range 0 to ZONE_H - 1    := 0;
  signal stripe_cnt_h : integer range 0 to STRIPE_W - 1  := 0;
  signal stripe_ph_h  : std_logic                        := '0';

  -- Gradient counters (sel 2/3, 10 zones)
  signal gzx_idx : integer range 0 to GZONES - 1  := 0;
  signal gpx_in  : integer range 0 to GZONE_W - 1 := 0;
  signal gzy_idx : integer range 0 to GZONES - 1  := 0;
  signal gln_in  : integer range 0 to GZONE_H - 1 := 0;
  -- Gradient-B counters (sel 5/6, 11 zones)
  signal gbzx_idx : integer range 0 to GZONES_B - 1 := 0;
  signal gbpx_in  : integer range 0 to GZONE_W_B - 1 := 0;
  signal gbzy_idx : integer range 0 to GZONES_B - 1 := 0;
  signal gbln_in  : integer range 0 to GZONE_H_B - 1 := 0;

  -- Pattern outputs
  signal color_v      : std_logic;
  signal color_h      : std_logic;
  signal sel_i        : integer range 0 to 255;
  signal active_level : std_logic_vector(3 downto 0);

  -- Brightness / black-level
  signal white_level_i : integer range 4 to 15;
  signal white_s       : std_logic_vector(3 downto 0);
  signal black_level_i : integer range 4 to 15;
  signal black_s       : std_logic_vector(3 downto 0);
  signal grad_x_s      : std_logic_vector(3 downto 0);
  signal grad_y_s      : std_logic_vector(3 downto 0);
  -- sel 5/6 gradient levels (zones 0-9 = grey steps, zone 10 = black)
  signal grad_xb_s     : std_logic_vector(3 downto 0);
  signal grad_yb_s     : std_logic_vector(3 downto 0);

begin

  sel_i <= to_integer(unsigned(sel));

  -- -------------------------------------------------------------------------
  -- Runtime port resolver: port value of 0 means "use generic default"
  -- CRIO host writes non-zero values to override at runtime without recompile
  -- -------------------------------------------------------------------------
  v_act_s_f1_i <= to_integer(unsigned(v_act_s_f1_p)) when unsigned(v_act_s_f1_p) /= 0 else V_ACT_S_F1;
  v_act_e_f1_i <= to_integer(unsigned(v_act_e_f1_p)) when unsigned(v_act_e_f1_p) /= 0 else V_ACT_E_F1;
  v_act_s_f2_i <= to_integer(unsigned(v_act_s_f2_p)) when unsigned(v_act_s_f2_p) /= 0 else V_ACT_S_F2;
  v_act_e_f2_i <= to_integer(unsigned(v_act_e_f2_p)) when unsigned(v_act_e_f2_p) /= 0 else V_ACT_E_F2;
  fss_f1_s_i   <= to_integer(unsigned(fss_f1_s_p))   when unsigned(fss_f1_s_p)   /= 0 else FSS_F1_S;
  fss_f1_e_i   <= to_integer(unsigned(fss_f1_e_p))   when unsigned(fss_f1_e_p)   /= 0 else FSS_F1_E;
  fss_f2_sv_i  <= to_integer(unsigned(fss_f2_sv_p))  when unsigned(fss_f2_sv_p)  /= 0 else FSS_F2_SV;
  fss_f2_sh_i  <= to_integer(unsigned(fss_f2_sh_p))  when unsigned(fss_f2_sh_p)  /= 0 else FSS_F2_SH;
  fss_f2_ev_i  <= to_integer(unsigned(fss_f2_ev_p))  when unsigned(fss_f2_ev_p)  /= 0 else FSS_F2_EV;
  fss_f2_eh_i  <= to_integer(unsigned(fss_f2_eh_p))  when unsigned(fss_f2_eh_p)  /= 0 else FSS_F2_EH;

  -- -------------------------------------------------------------------------
  -- H/V free-running counters
  -- -------------------------------------------------------------------------
  u_timing : entity work.pal_timing
    generic map (H_TOTAL => H_TOTAL, V_TOTAL => V_TOTAL, CLK_MHZ => CLK_MHZ)
    port map (clk => clk, rst => rst, ce => ce_s,
              h_cnt => h_cnt, v_cnt => v_cnt);

  -- -------------------------------------------------------------------------
  -- PAL interlaced composite sync
  -- -------------------------------------------------------------------------
  u_csync : entity work.pal_csync_il
    generic map (
      H_FRONT    => H_FRONT,    H_SYNC_W   => H_SYNC_W,
      H_BACK     => H_BACK,     H_ACTIVE   => H_ACTIVE,  H_TOTAL    => H_TOTAL,
      V_ACT_S_F1 => V_ACT_S_F1, V_ACT_E_F1 => V_ACT_E_F1,
      V_ACT_S_F2 => V_ACT_S_F2, V_ACT_E_F2 => V_ACT_E_F2)
    port map (h_cnt => h_cnt, v_cnt => v_cnt,
              csync => csync_s, field => field_s, active => open);

  -- -------------------------------------------------------------------------
  -- Active region flags (use runtime integer signals, not pal_csync_il active)
  -- -------------------------------------------------------------------------
  in_f1_active  <= (v_cnt >= v_act_s_f1_i and v_cnt <= v_act_e_f1_i);
  in_f2_active  <= (v_cnt >= v_act_s_f2_i and v_cnt <= v_act_e_f2_i);
  in_any_active <= in_f1_active or in_f2_active;
  active_s      <= '1' when in_any_active and h_cnt >= H_ACT_S else '0';

  -- -------------------------------------------------------------------------
  -- Vertical bar generator
  -- -------------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        zone_idx_v <= 0; px_in_zone <= 0; stripe_cnt_v <= 0; stripe_ph_v <= '0';
      elsif ce_s = '1' then
        if h_cnt = H_ACT_S - 1 and in_any_active then
          zone_idx_v <= 0; px_in_zone <= 0; stripe_cnt_v <= 0; stripe_ph_v <= '0';
        elsif active_s = '1' then
          if px_in_zone = ZONE_W - 1 then
            if zone_idx_v < NUM_ZONES - 1 then zone_idx_v <= zone_idx_v + 1; end if;
            px_in_zone <= 0; stripe_cnt_v <= 0; stripe_ph_v <= '0';
          else
            px_in_zone <= px_in_zone + 1;
            if stripe_cnt_v = STRIPE_W - 1 then
              stripe_cnt_v <= 0; stripe_ph_v <= not stripe_ph_v;
            else stripe_cnt_v <= stripe_cnt_v + 1; end if;
          end if;
        end if;
      end if;
    end if;
  end process;

  -- -------------------------------------------------------------------------
  -- Horizontal bar generator
  -- -------------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        zone_idx_h <= 0; line_in_zone <= 0; stripe_cnt_h <= 0; stripe_ph_h <= '0';
      elsif ce_s = '1' then
        if (v_cnt = v_act_s_f1_i - 1 or v_cnt = v_act_s_f2_i - 1) and
           h_cnt = H_TOTAL - 1 then
          zone_idx_h <= 0; line_in_zone <= 0; stripe_cnt_h <= 0; stripe_ph_h <= '0';
        elsif in_any_active and h_cnt = H_TOTAL - 1 then
          if line_in_zone = ZONE_H - 1 then
            if zone_idx_h < NUM_ZONES - 1 then zone_idx_h <= zone_idx_h + 1; end if;
            line_in_zone <= 0; stripe_cnt_h <= 0; stripe_ph_h <= '0';
          else
            line_in_zone <= line_in_zone + 1;
            if stripe_cnt_h = STRIPE_W - 1 then
              stripe_cnt_h <= 0; stripe_ph_h <= not stripe_ph_h;
            else stripe_cnt_h <= stripe_cnt_h + 1; end if;
          end if;
        end if;
      end if;
    end if;
  end process;

  -- -------------------------------------------------------------------------
  -- Horizontal gradient generator
  -- -------------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        gzx_idx <= 0; gpx_in <= 0;
      elsif ce_s = '1' then
        if h_cnt = H_ACT_S - 1 and in_any_active then
          gzx_idx <= 0; gpx_in <= 0;
        elsif active_s = '1' then
          if gpx_in = GZONE_W - 1 then
            if gzx_idx < GZONES - 1 then gzx_idx <= gzx_idx + 1; end if;
            gpx_in <= 0;
          else gpx_in <= gpx_in + 1; end if;
        end if;
      end if;
    end if;
  end process;

  -- -------------------------------------------------------------------------
  -- Vertical gradient generator
  -- -------------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        gzy_idx <= 0; gln_in <= 0;
      elsif ce_s = '1' then
        if (v_cnt = v_act_s_f1_i - 1 or v_cnt = v_act_s_f2_i - 1) and
           h_cnt = H_TOTAL - 1 then
          gzy_idx <= 0; gln_in <= 0;
        elsif in_any_active and h_cnt = H_TOTAL - 1 then
          if gln_in = GZONE_H - 1 then
            if gzy_idx < GZONES - 1 then gzy_idx <= gzy_idx + 1; end if;
            gln_in <= 0;
          else gln_in <= gln_in + 1; end if;
        end if;
      end if;
    end if;
  end process;

  -- -------------------------------------------------------------------------
  -- Horizontal gradient-B generator (11 zones, sel 5)
  -- -------------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        gbzx_idx <= 0; gbpx_in <= 0;
      elsif ce_s = '1' then
        if h_cnt = H_ACT_S - 1 and in_any_active then
          gbzx_idx <= 0; gbpx_in <= 0;
        elsif active_s = '1' then
          if gbpx_in = GZONE_W_B - 1 then
            if gbzx_idx < GZONES_B - 1 then gbzx_idx <= gbzx_idx + 1; end if;
            gbpx_in <= 0;
          else gbpx_in <= gbpx_in + 1; end if;
        end if;
      end if;
    end if;
  end process;

  -- -------------------------------------------------------------------------
  -- Vertical gradient-B generator (11 zones, sel 6)
  -- -------------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        gbzy_idx <= 0; gbln_in <= 0;
      elsif ce_s = '1' then
        if (v_cnt = v_act_s_f1_i - 1 or v_cnt = v_act_s_f2_i - 1) and
           h_cnt = H_TOTAL - 1 then
          gbzy_idx <= 0; gbln_in <= 0;
        elsif in_any_active and h_cnt = H_TOTAL - 1 then
          if gbln_in = GZONE_H_B - 1 then
            if gbzy_idx < GZONES_B - 1 then gbzy_idx <= gbzy_idx + 1; end if;
            gbln_in <= 0;
          else gbln_in <= gbln_in + 1; end if;
        end if;
      end if;
    end if;
  end process;

  -- -------------------------------------------------------------------------
  -- BRAM write (synchronous, single buffer)
  -- -------------------------------------------------------------------------
  bram_len_i <= BRAM_DEPTH
                  when to_integer(unsigned(bram_len)) = 0 or
                       to_integer(unsigned(bram_len)) > BRAM_DEPTH
                  else to_integer(unsigned(bram_len));

  process(clk)
  begin
    if rising_edge(clk) then
      if bram_wr_en = '1' and
         to_integer(unsigned(bram_wr_addr)) < BRAM_DEPTH then
        bram_mem(to_integer(unsigned(bram_wr_addr))) <= bram_wr_data;
      end if;
    end if;
  end process;

  -- -------------------------------------------------------------------------
  -- BRAM address generator  (interlaced stride = 2 * H_ACTIVE)
  --   F1 start -> addr 0          (image row 0)
  --   F2 start -> addr H_ACTIVE   (image row 1)
  --   Each active line: base += 2 * H_ACTIVE
  -- -------------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        bram_rd_line_base <= 0; bram_px_cnt <= 0;
      elsif ce_s = '1' then
        if v_cnt = v_act_s_f1_i - 1 and h_cnt = H_TOTAL - 1 then
          bram_rd_line_base <= 0; bram_px_cnt <= 0;
        elsif v_cnt = v_act_s_f2_i - 1 and h_cnt = H_TOTAL - 1 then
          bram_rd_line_base <= H_ACTIVE; bram_px_cnt <= 0;
        elsif in_any_active and h_cnt = H_TOTAL - 1 then
          bram_rd_line_base <= bram_rd_line_base + 2 * H_ACTIVE;
          bram_px_cnt <= 0;
        elsif active_s = '1' then
          bram_px_cnt <= bram_px_cnt + 1;
        end if;
      end if;
    end if;
  end process;

  bram_rd_sum  <= bram_rd_line_base + bram_px_cnt;
  bram_rd_addr <= bram_rd_sum when bram_rd_sum < bram_len_i else 0;

  -- Synchronous BRAM read (required for block RAM inference)
  process(clk)
  begin
    if rising_edge(clk) then
      if ce_s = '1' then
        bram_pixel <= bram_mem(bram_rd_addr);
      end if;
    end if;
  end process;

  bram_level <= white_s when bram_pixel = '1' else black_s;

  -- -------------------------------------------------------------------------
  -- Brightness / black-level control
  -- -------------------------------------------------------------------------
  white_level_i <= 4 when unsigned(brightness) < 4
                     else to_integer(unsigned(brightness));
  white_s <= std_logic_vector(to_unsigned(white_level_i, 4));

  process(black_lvl, white_level_i)
    variable b : integer range 0 to 15;
  begin
    b := to_integer(unsigned(black_lvl));
    if b < 4             then b := 4;             end if;
    if b > white_level_i then b := white_level_i; end if;
    black_level_i <= b;
  end process;
  black_s <= std_logic_vector(to_unsigned(black_level_i, 4));

  process(white_level_i, black_level_i, gzx_idx, gzy_idx)
    variable rng    : integer range 0 to 11;
    variable lx, ly : integer range 0 to 15;
  begin
    rng := white_level_i - black_level_i;
    if rng = 0 then
      lx := black_level_i; ly := black_level_i;
    else
      lx := black_level_i + (gzx_idx * rng + 4) / 9;
      ly := black_level_i + (gzy_idx * rng + 4) / 9;
      if lx > 15 then lx := 15; end if;
      if ly > 15 then ly := 15; end if;
    end if;
    grad_x_s <= std_logic_vector(to_unsigned(lx, 4));
    grad_y_s <= std_logic_vector(to_unsigned(ly, 4));
  end process;

  -- sel 5/6: zones 0-9 use the 10-step gradient formula; zone 10 = black
  process(white_level_i, black_level_i, gbzx_idx, gbzy_idx)
    variable rng    : integer range 0 to 11;
    variable lx, ly : integer range 0 to 15;
  begin
    rng := white_level_i - black_level_i;
    if gbzx_idx >= GZONES or rng = 0 then
      lx := black_level_i;
    else
      lx := black_level_i + (gbzx_idx * rng + 4) / 9;
      if lx > 15 then lx := 15; end if;
    end if;
    if gbzy_idx >= GZONES or rng = 0 then
      ly := black_level_i;
    else
      ly := black_level_i + (gbzy_idx * rng + 4) / 9;
      if ly > 15 then ly := 15; end if;
    end if;
    grad_xb_s <= std_logic_vector(to_unsigned(lx, 4));
    grad_yb_s <= std_logic_vector(to_unsigned(ly, 4));
  end process;

  -- -------------------------------------------------------------------------
  -- Active-level mux  (sel 0..6; anything else -> black)
  -- -------------------------------------------------------------------------
  with ZONE_TABLE(zone_idx_v) select
    color_v <= '0' when Z_BLACK, '1' when Z_WHITE, stripe_ph_v when Z_STRIPE;
  with ZONE_TABLE(zone_idx_h) select
    color_h <= '0' when Z_BLACK, '1' when Z_WHITE, stripe_ph_h when Z_STRIPE;

  active_level <= bram_level  when sel_i = 4 else
                  grad_x_s    when sel_i = 2 else
                  grad_y_s    when sel_i = 3 else
                  grad_xb_s   when sel_i = 5 else
                  grad_yb_s   when sel_i = 6 else
                  white_s     when sel_i = 0 and color_v = '1' else
                  black_s     when sel_i = 0 else
                  white_s     when sel_i = 1 and color_h = '1' else
                  black_s;

  -- -------------------------------------------------------------------------
  -- DAC output
  -- -------------------------------------------------------------------------
  dac_out <= LEVEL_SYNC   when csync_s  = '1' else
             active_level when active_s = '1' else
             LEVEL_BLANK;

  -- -------------------------------------------------------------------------
  -- Sync outputs
  -- -------------------------------------------------------------------------
  in_vsync_s <= '1' when (v_cnt <= 7) or (v_cnt >= 312 and v_cnt <= 319)
                else '0';

  line_sync_s  <= '1' when h_cnt >= H_FRONT and
                            h_cnt < H_FRONT + H_SYNC_W and
                            in_vsync_s = '0'
                  else '0';

  frame_sync_s <= '1' when v_cnt <= 7 else '0';   -- 25 Hz, F1 start only

  -- FSS: runtime-configurable via fss_f*_* ports (CRIO writes these at runtime)
  -- Defaults: F1 v=3-7, F2 v=315 h>=320 to v=320 h<320
  fss_s <= '1' when (v_cnt >= fss_f1_s_i and v_cnt <= fss_f1_e_i) or
                    (v_cnt = fss_f2_sv_i and h_cnt >= fss_f2_sh_i) or
                    (v_cnt > fss_f2_sv_i and v_cnt < fss_f2_ev_i) or
                    (v_cnt = fss_f2_ev_i and h_cnt < fss_f2_eh_i)
           else '0';

  csync_o      <= csync_s;
  line_sync_o  <= line_sync_s;
  frame_sync_o <= frame_sync_s;
  fss_o        <= fss_s;
  field_o      <= field_s;
  active_o     <= active_s;
  blank_o      <= not active_s;   -- HIGH for full 12 µs H-blank + V-blank

end architecture rtl;
