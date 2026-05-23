library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- PAL / NTSC B&W BRAM Video IP  —  runtime format selection
-- ============================================================
--
-- ntsc_mode = '0'  →  PAL  625 lines / 50 Hz  (10 MHz pixel clock)
-- ntsc_mode = '1'  →  NTSC 525 lines / 59.94 Hz (10 MHz pixel clock)
--
-- Both formats use H_ACTIVE = 520 px.
-- NTSC achieves this by setting H_BACK = 53 (PAL uses H_BACK = 57).
--
-- Timing summary (10 MHz = 100 ns/pixel):
--
--               PAL  625/50        NTSC 525/60
--  H_TOTAL       640  (64.0 µs)     636  (63.6 µs)
--  H_FRONT        16   (1.6 µs)      16   (1.6 µs)
--  H_SYNC_W       47   (4.7 µs)      47   (4.7 µs)
--  H_BACK         57   (5.7 µs)      53   (5.3 µs)
--  H_ACTIVE      520  (52.0 µs)     520  (52.0 µs)
--  H_ACT_S       120              116
--  V_TOTAL       625              525
--  V_ACT_S_F1     24               21
--  V_ACT_E_F1    311              260   (288 / 240 lines per field)
--  V_ACT_S_F2    336              283
--  V_ACT_E_F2    623              522
--  V_ACTIVE      576              480   (total active screen rows)
--
-- BRAM layout (sel = 4) — natural sequential row order, row stride = 520:
--   addr         0 ..       519  image row  0  (F1 line 0,  screen row  0)
--   addr       520 ..      1039  image row  1  (F2 line 0,  screen row  1)
--   addr k*1040 .. k*1040+ 519  image row 2k  (F1 line k)
--   addr k*1040+520 .. k*1040+1039  image row 2k+1 (F2 line k)
--   PAL  full frame: 520 × 576 = 299 520 pixels
--   NTSC full frame: 520 × 480 = 249 600 pixels
--
-- Selections:
--   sel 0  Vertical bars        (8 × 65 px zones)
--   sel 1  Horizontal bars      (8 zones; zone height = V_ACTIVE_F / 8)
--   sel 2  Horizontal gradient  (10 grey steps, 52 px each)
--   sel 3  Vertical gradient    (10 grey steps; zone height adapts)
--   sel 4  BRAM pixel source    (interlaced natural sequential row order)
--   sel 5  Bouncing ball        (60×50 white rectangle, elastic bounce)
--   other  Black screen
entity video_bram_top is
  generic (
    CLK_MHZ    : integer := 40;
    STRIPE_W   : integer := 4;
    BRAM_DEPTH : integer := 299520   -- PAL full frame; covers NTSC (249 600)
  );
  port (
    clk        : in  std_logic;
    rst        : in  std_logic;
    ntsc_mode  : in  std_logic;   -- '0' = PAL 625/50,  '1' = NTSC 525/60
    sel        : in  std_logic_vector(7 downto 0);
    brightness : in  std_logic_vector(3 downto 0) := "1111";
    black_lvl  : in  std_logic_vector(3 downto 0) := "0100";
    -- BRAM write port (host side; independent of pixel clock)
    bram_wr_en   : in  std_logic                     := '0';
    bram_wr_addr : in  std_logic_vector(18 downto 0) := (others => '0');
    bram_wr_data : in  std_logic                     := '0';
    -- Number of valid BRAM pixels (wraps address at this boundary)
    bram_len     : in  std_logic_vector(18 downto 0) := (others => '1');
    -- Video outputs
    dac_out       : out std_logic_vector(3 downto 0);
    csync_o       : out std_logic;   -- composite sync (H+V merged; 1 = sync tip)
    line_sync_o   : out std_logic;   -- H sync only  (1 during hsync, never during vsync)
    frame_sync_o  : out std_logic;   -- V sync pulse (1 during vsync broad-sync region)
    field_o       : out std_logic;   -- field indicator (0 = F1, 1 = F2)
    active_o      : out std_logic;   -- 1 during active picture
    blank_o       : out std_logic    -- composite blanking (1 outside active + not sync)
  );
end entity video_bram_top;

architecture rtl of video_bram_top is

  -- -----------------------------------------------------------------------
  -- Geometry constants (identical for both formats)
  -- -----------------------------------------------------------------------
  constant H_ACTIVE  : integer := 520;
  constant H_FRONT   : integer := 16;
  constant H_SYNC_W  : integer := 47;
  constant NUM_ZONES : integer := 8;
  constant ZONE_W    : integer := H_ACTIVE / NUM_ZONES;   -- 65 px per H zone
  constant GZONES    : integer := 10;
  constant GZONE_W   : integer := H_ACTIVE / GZONES;     -- 52 px per gradient zone
  constant BALL_W    : integer := 60;
  constant BALL_H    : integer := 50;

  -- -----------------------------------------------------------------------
  -- Runtime timing parameters (driven combinationally from ntsc_mode)
  -- -----------------------------------------------------------------------
  -- H timing
  signal h_total_m1 : integer range 0 to 639;   -- H_TOTAL − 1
  signal h_act_s    : integer range 0 to 639;   -- first active h_cnt

  -- V timing
  signal v_total_m1 : integer range 0 to 624;
  signal v_act_s_f1 : integer range 0 to 624;
  signal v_act_e_f1 : integer range 0 to 624;
  signal v_act_s_f2 : integer range 0 to 624;
  signal v_act_e_f2 : integer range 0 to 624;
  signal v_active   : integer range 0 to 576;   -- total active screen rows

  -- Zone heights (runtime)
  signal zone_h_s  : integer range 0 to 36;   -- PAL 36, NTSC 30
  signal gzone_h_s : integer range 0 to 28;   -- PAL 28, NTSC 24

  -- -----------------------------------------------------------------------
  -- H/V counters  (max range sized for PAL: 640×625)
  -- -----------------------------------------------------------------------
  signal h_cnt : integer range 0 to 639 := 0;
  signal v_cnt : integer range 0 to 624 := 0;
  signal ce_s  : std_logic;

  constant CLK_DIV : integer := CLK_MHZ / 10;
  signal div_cnt : integer range 0 to 3 := 0;

  -- -----------------------------------------------------------------------
  -- Sync / active flags
  -- -----------------------------------------------------------------------
  signal csync_s       : std_logic;
  signal field_s       : std_logic;
  signal active_s      : std_logic;
  signal in_vsync_s    : std_logic;   -- '1' during vsync broad-sync region
  signal line_sync_s   : std_logic;   -- H sync pulse, suppressed during vsync
  signal frame_sync_s  : std_logic;   -- V sync = in_vsync_s

  signal in_f1_active  : boolean;
  signal in_f2_active  : boolean;
  signal in_any_active : boolean;

  -- -----------------------------------------------------------------------
  -- Pattern generators
  -- -----------------------------------------------------------------------
  type zone_kind    is (Z_BLACK, Z_WHITE, Z_STRIPE);
  type zone_table_t is array (0 to NUM_ZONES - 1) of zone_kind;
  constant ZONE_TABLE : zone_table_t := (
    0 => Z_STRIPE, 1 => Z_WHITE,  2 => Z_STRIPE, 3 => Z_WHITE,
    4 => Z_BLACK,  5 => Z_STRIPE, 6 => Z_WHITE,  7 => Z_STRIPE
  );

  signal zone_idx_v   : integer range 0 to NUM_ZONES - 1 := 0;
  signal px_in_zone   : integer range 0 to ZONE_W - 1    := 0;
  signal stripe_cnt_v : integer range 0 to STRIPE_W - 1  := 0;
  signal stripe_ph_v  : std_logic                        := '0';

  signal zone_idx_h   : integer range 0 to NUM_ZONES - 1 := 0;
  signal line_in_zone : integer range 0 to 35             := 0;  -- max PAL 36-1
  signal stripe_cnt_h : integer range 0 to STRIPE_W - 1  := 0;
  signal stripe_ph_h  : std_logic                        := '0';

  signal gzx_idx : integer range 0 to GZONES - 1  := 0;
  signal gpx_in  : integer range 0 to GZONE_W - 1 := 0;
  signal gzy_idx : integer range 0 to GZONES - 1  := 0;
  signal gln_in  : integer range 0 to 27           := 0;  -- max PAL 28-1

  signal color_v      : std_logic;
  signal color_h      : std_logic;
  signal sel_i        : integer range 0 to 255;
  signal active_level : std_logic_vector(3 downto 0);

  -- -----------------------------------------------------------------------
  -- Bouncing ball (sel = 5)
  -- -----------------------------------------------------------------------
  signal screen_x : integer := 0;
  signal screen_y : integer := 0;
  signal ball_x   : integer := 0;
  signal ball_y   : integer := 0;
  signal ball_vx  : integer := 3;
  signal ball_vy  : integer := 2;
  signal ball_on  : std_logic := '0';

  -- -----------------------------------------------------------------------
  -- 1-bit BRAM (Vivado: infer Block RAM via ram_style attribute)
  -- -----------------------------------------------------------------------
  type bram_t is array (0 to BRAM_DEPTH - 1) of std_logic;
  signal bram_mem : bram_t := (others => '0');
  attribute ram_style          : string;
  attribute ram_style of bram_mem : signal is "block";

  signal bram_rd_line_base : integer := 0;
  signal bram_px_cnt       : integer range 0 to H_ACTIVE - 1 := 0;
  signal bram_rd_sum       : integer := 0;
  signal bram_rd_addr      : integer range 0 to BRAM_DEPTH - 1 := 0;
  signal bram_pixel        : std_logic;
  signal bram_len_i        : integer range 1 to BRAM_DEPTH;
  signal bram_level        : std_logic_vector(3 downto 0);

  -- -----------------------------------------------------------------------
  -- Brightness / black-level
  -- -----------------------------------------------------------------------
  signal white_level_i : integer range 4 to 15;
  signal white_s       : std_logic_vector(3 downto 0);
  signal black_level_i : integer range 4 to 15;
  signal black_s       : std_logic_vector(3 downto 0);
  signal grad_x_s      : std_logic_vector(3 downto 0);
  signal grad_y_s      : std_logic_vector(3 downto 0);

begin

  assert CLK_MHZ = 10 or CLK_MHZ = 20 or CLK_MHZ = 30 or CLK_MHZ = 40
    report "CLK_MHZ must be 10, 20, 30, or 40" severity failure;
  assert NUM_ZONES * ZONE_W = H_ACTIVE
    report "NUM_ZONES * ZONE_W /= H_ACTIVE" severity failure;
  assert GZONES * GZONE_W = H_ACTIVE
    report "GZONES * GZONE_W /= H_ACTIVE" severity failure;

  sel_i <= to_integer(unsigned(sel));

  -- -----------------------------------------------------------------------
  -- Runtime timing parameter selection (combinational)
  -- -----------------------------------------------------------------------
  process(ntsc_mode)
  begin
    if ntsc_mode = '1' then
      -- NTSC 525/60:  H_TOTAL=636  H_BACK=53  H_ACT_S=116
      h_total_m1 <= 635;
      h_act_s    <= H_FRONT + H_SYNC_W + 53;  -- 116
      v_total_m1 <= 524;
      v_act_s_f1 <= 21;
      v_act_e_f1 <= 260;   -- 240 active lines per field
      v_act_s_f2 <= 283;
      v_act_e_f2 <= 522;
      v_active   <= 480;   -- 240 × 2
      zone_h_s   <= 30;    -- 240 / 8
      gzone_h_s  <= 24;    -- 240 / 10
    else
      -- PAL 625/50:   H_TOTAL=640  H_BACK=57  H_ACT_S=120
      h_total_m1 <= 639;
      h_act_s    <= H_FRONT + H_SYNC_W + 57;  -- 120
      v_total_m1 <= 624;
      v_act_s_f1 <= 24;
      v_act_e_f1 <= 311;   -- 288 active lines per field
      v_act_s_f2 <= 336;
      v_act_e_f2 <= 623;
      v_active   <= 576;   -- 288 × 2
      zone_h_s   <= 36;    -- 288 / 8
      gzone_h_s  <= 28;    -- 288 / 10
    end if;
  end process;

  -- -----------------------------------------------------------------------
  -- Clock-enable divider  (CLK_MHZ / 10 → 10 MHz pixel rate)
  -- -----------------------------------------------------------------------
  ce_s <= '1' when (CLK_DIV = 1) or (div_cnt = CLK_DIV - 1) else '0';

  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then div_cnt <= 0;
      elsif CLK_DIV > 1 then
        if div_cnt = CLK_DIV - 1 then div_cnt <= 0;
        else div_cnt <= div_cnt + 1; end if;
      end if;
    end if;
  end process;

  -- -----------------------------------------------------------------------
  -- H / V counters  (runtime limits via h_total_m1 / v_total_m1)
  -- -----------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        h_cnt <= 0; v_cnt <= 0;
      elsif ce_s = '1' then
        if h_cnt = h_total_m1 then
          h_cnt <= 0;
          if v_cnt = v_total_m1 then v_cnt <= 0;
          else v_cnt <= v_cnt + 1; end if;
        else
          h_cnt <= h_cnt + 1;
        end if;
      end if;
    end if;
  end process;

  -- -----------------------------------------------------------------------
  -- Composite sync, field indicator, and active flag  (combinational)
  --
  -- PAL:  full equalising + broad-sync pulses (identical to pal_csync_il).
  -- NTSC: simplified — 5 full-line broad-sync per field, standard H sync
  --       on all other lines.  No equalising pulses (monitors still lock).
  -- -----------------------------------------------------------------------
  process(all)
    variable hp      : integer range 0 to 639;
    variable first_h : boolean;
    -- PAL eq/broad flags
    variable f1p, f1b, f1q : boolean;
    variable f2p, f2b, f2q : boolean;
    variable in_eq, in_brd  : boolean;
  begin
    -- Half-line phase (PAL HALF=320, NTSC HALF=318)
    if ntsc_mode = '0' then
      first_h := (h_cnt < 320);
      if first_h then hp := h_cnt; else hp := h_cnt - 320; end if;
    else
      first_h := (h_cnt < 318);
      if first_h then hp := h_cnt; else hp := h_cnt - 318; end if;
    end if;

    -- Default outputs
    csync_s  <= '0';
    field_s  <= '0';
    active_s <= '0';

    -- ------------------------------------------------------------------
    if ntsc_mode = '0' then
      -- ---- PAL: full equalising / broad-sync sequence ----
      -- Field 1 vsync (frame start, lines 0–7)
      f1p := (v_cnt = 0) or (v_cnt = 1) or (v_cnt = 2 and     first_h);
      f1b := (v_cnt = 2 and not first_h) or (v_cnt = 3) or (v_cnt = 4);
      f1q := (v_cnt = 5) or (v_cnt = 6) or (v_cnt = 7 and     first_h);

      -- Field 2 vsync (starts v=312 h=320)
      f2p := (v_cnt = 312 and not first_h) or (v_cnt = 313) or (v_cnt = 314);
      f2b := (v_cnt = 315) or (v_cnt = 316) or (v_cnt = 317 and     first_h);
      f2q := (v_cnt = 317 and not first_h) or (v_cnt = 318) or (v_cnt = 319);

      in_eq  := f1p or f1q or f2p or f2q;
      in_brd := f1b or f2b;

      if    in_eq  and hp < 23  then csync_s <= '1';   -- EQ_W   = 23
      elsif in_brd and hp < 273 then csync_s <= '1';   -- BROAD_W = 273
      elsif not (in_eq or in_brd)
            and h_cnt >= H_FRONT
            and h_cnt < H_FRONT + H_SYNC_W then csync_s <= '1';
      end if;

      -- PAL field indicator: F2 from v=312 h=320 onwards
      if v_cnt > 312 or (v_cnt = 312 and not first_h) then
        field_s <= '1';
      end if;

    else
      -- ---- NTSC: simplified vsync (5 full-line broad sync per field) ----
      -- F1 broad: v = 0..4    F2 broad: v = 263..267
      if (v_cnt <= 4) or (v_cnt >= 263 and v_cnt <= 267) then
        -- Entire vsync line → sync tip (monitors detect as vsync)
        csync_s <= '1';
      elsif h_cnt >= H_FRONT and h_cnt < H_FRONT + H_SYNC_W then
        csync_s <= '1';   -- normal H sync
      end if;

      -- NTSC field indicator: F2 from v=263 onwards
      if v_cnt >= 263 then field_s <= '1'; end if;
    end if;

    -- Active window (shared; uses runtime signals)
    if (v_cnt >= v_act_s_f1 and v_cnt <= v_act_e_f1 and h_cnt >= h_act_s) or
       (v_cnt >= v_act_s_f2 and v_cnt <= v_act_e_f2 and h_cnt >= h_act_s) then
      active_s <= '1';
    end if;
  end process;

  in_f1_active  <= (v_cnt >= v_act_s_f1 and v_cnt <= v_act_e_f1);
  in_f2_active  <= (v_cnt >= v_act_s_f2 and v_cnt <= v_act_e_f2);
  in_any_active <= in_f1_active or in_f2_active;

  -- -----------------------------------------------------------------------
  -- Vertical bar generator
  -- -----------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        zone_idx_v <= 0; px_in_zone <= 0; stripe_cnt_v <= 0; stripe_ph_v <= '0';
      elsif ce_s = '1' then
        if h_cnt = h_act_s - 1 and in_any_active then
          zone_idx_v <= 0; px_in_zone <= 0; stripe_cnt_v <= 0; stripe_ph_v <= '0';
        elsif active_s = '1' then
          if px_in_zone = ZONE_W - 1 then
            if zone_idx_v < NUM_ZONES - 1 then zone_idx_v <= zone_idx_v + 1; end if;
            px_in_zone <= 0; stripe_cnt_v <= 0; stripe_ph_v <= '0';
          else
            px_in_zone <= px_in_zone + 1;
            if stripe_cnt_v = STRIPE_W - 1 then
              stripe_cnt_v <= 0; stripe_ph_v <= not stripe_ph_v;
            else
              stripe_cnt_v <= stripe_cnt_v + 1;
            end if;
          end if;
        end if;
      end if;
    end if;
  end process;

  -- -----------------------------------------------------------------------
  -- Horizontal bar generator  (zone height adapts to format via zone_h_s)
  -- -----------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        zone_idx_h <= 0; line_in_zone <= 0; stripe_cnt_h <= 0; stripe_ph_h <= '0';
      elsif ce_s = '1' then
        if (v_cnt = v_act_s_f1 - 1 or v_cnt = v_act_s_f2 - 1) and
           h_cnt = h_total_m1 then
          zone_idx_h <= 0; line_in_zone <= 0; stripe_cnt_h <= 0; stripe_ph_h <= '0';
        elsif in_any_active and h_cnt = h_total_m1 then
          if line_in_zone = zone_h_s - 1 then
            if zone_idx_h < NUM_ZONES - 1 then zone_idx_h <= zone_idx_h + 1; end if;
            line_in_zone <= 0; stripe_cnt_h <= 0; stripe_ph_h <= '0';
          else
            line_in_zone <= line_in_zone + 1;
            if stripe_cnt_h = STRIPE_W - 1 then
              stripe_cnt_h <= 0; stripe_ph_h <= not stripe_ph_h;
            else
              stripe_cnt_h <= stripe_cnt_h + 1;
            end if;
          end if;
        end if;
      end if;
    end if;
  end process;

  -- -----------------------------------------------------------------------
  -- Horizontal gradient  (52 px per zone, format-independent)
  -- -----------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then gzx_idx <= 0; gpx_in <= 0;
      elsif ce_s = '1' then
        if h_cnt = h_act_s - 1 and in_any_active then
          gzx_idx <= 0; gpx_in <= 0;
        elsif active_s = '1' then
          if gpx_in = GZONE_W - 1 then
            if gzx_idx < GZONES - 1 then gzx_idx <= gzx_idx + 1; end if;
            gpx_in <= 0;
          else
            gpx_in <= gpx_in + 1;
          end if;
        end if;
      end if;
    end if;
  end process;

  -- -----------------------------------------------------------------------
  -- Vertical gradient  (zone height adapts to format via gzone_h_s)
  -- -----------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then gzy_idx <= 0; gln_in <= 0;
      elsif ce_s = '1' then
        if (v_cnt = v_act_s_f1 - 1 or v_cnt = v_act_s_f2 - 1) and
           h_cnt = h_total_m1 then
          gzy_idx <= 0; gln_in <= 0;
        elsif in_any_active and h_cnt = h_total_m1 then
          if gln_in = gzone_h_s - 1 then
            if gzy_idx < GZONES - 1 then gzy_idx <= gzy_idx + 1; end if;
            gln_in <= 0;
          else
            gln_in <= gln_in + 1;
          end if;
        end if;
      end if;
    end if;
  end process;

  -- -----------------------------------------------------------------------
  -- screen_x  (pixel column within active line, 0..519)
  -- -----------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then screen_x <= 0;
      elsif ce_s = '1' then
        if h_cnt = h_act_s - 1 and in_any_active then
          screen_x <= 0;
        elsif active_s = '1' then
          screen_x <= screen_x + 1;
        end if;
      end if;
    end if;
  end process;

  -- -----------------------------------------------------------------------
  -- screen_y  (screen row, interlaced: even = F1, odd = F2)
  --   PAL:  0..575;  NTSC: 0..479
  -- -----------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then screen_y <= 0;
      elsif ce_s = '1' then
        if v_cnt = v_act_s_f1 - 1 and h_cnt = h_total_m1 then
          screen_y <= 0;
        elsif v_cnt = v_act_s_f2 - 1 and h_cnt = h_total_m1 then
          screen_y <= 1;
        elsif in_any_active and h_cnt = h_total_m1 then
          screen_y <= screen_y + 2;
        end if;
      end if;
    end if;
  end process;

  -- -----------------------------------------------------------------------
  -- Ball physics  (once per frame at end of F2; wall bounds format-aware)
  -- -----------------------------------------------------------------------
  process(clk)
    variable nx, ny, nvx, nvy : integer;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        ball_x <= 0; ball_y <= 0; ball_vx <= 3; ball_vy <= 2;
      elsif ce_s = '1' and v_cnt = v_act_e_f2 and h_cnt = h_total_m1 then
        nx  := ball_x + ball_vx;
        ny  := ball_y + ball_vy;
        nvx := ball_vx;
        nvy := ball_vy;
        if nx > H_ACTIVE - BALL_W then
          nx  := 2 * (H_ACTIVE - BALL_W) - nx; nvx := -nvx;
        end if;
        if nx < 0 then
          nx  := -nx; nvx := -nvx;
        end if;
        if ny > v_active - BALL_H then
          ny  := 2 * (v_active - BALL_H) - ny; nvy := -nvy;
        end if;
        if ny < 0 then
          ny  := -ny; nvy := -nvy;
        end if;
        ball_x <= nx; ball_y <= ny; ball_vx <= nvx; ball_vy <= nvy;
      end if;
    end if;
  end process;

  ball_on <= '1' when screen_x >= ball_x and
                      screen_x <  ball_x + BALL_W and
                      screen_y >= ball_y and
                      screen_y <  ball_y + BALL_H
             else '0';

  -- -----------------------------------------------------------------------
  -- BRAM synchronous write
  -- -----------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if bram_wr_en = '1' and
         to_integer(unsigned(bram_wr_addr)) < BRAM_DEPTH then
        bram_mem(to_integer(unsigned(bram_wr_addr))) <= bram_wr_data;
      end if;
    end if;
  end process;

  -- BRAM address generator  (natural sequential row order, stride = 2×H_ACTIVE)
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        bram_rd_line_base <= 0; bram_px_cnt <= 0;
      elsif ce_s = '1' then
        if v_cnt = v_act_s_f1 - 1 and h_cnt = h_total_m1 then
          bram_rd_line_base <= 0;         bram_px_cnt <= 0;
        elsif v_cnt = v_act_s_f2 - 1 and h_cnt = h_total_m1 then
          bram_rd_line_base <= H_ACTIVE;  bram_px_cnt <= 0;
        elsif in_any_active and h_cnt = h_total_m1 then
          bram_rd_line_base <= bram_rd_line_base + 2 * H_ACTIVE;
          bram_px_cnt <= 0;
        elsif active_s = '1' then
          bram_px_cnt <= bram_px_cnt + 1;
        end if;
      end if;
    end if;
  end process;

  bram_len_i   <= BRAM_DEPTH
                    when to_integer(unsigned(bram_len)) = 0 or
                         to_integer(unsigned(bram_len)) > BRAM_DEPTH
                    else to_integer(unsigned(bram_len));
  bram_rd_sum  <= bram_rd_line_base + bram_px_cnt;
  bram_rd_addr <= bram_rd_sum when bram_rd_sum < bram_len_i else 0;
  bram_pixel   <= bram_mem(bram_rd_addr);
  bram_level   <= white_s when bram_pixel = '1' else black_s;

  -- -----------------------------------------------------------------------
  -- Brightness / black-level control
  -- -----------------------------------------------------------------------
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

  -- -----------------------------------------------------------------------
  -- Active-level mux
  -- -----------------------------------------------------------------------
  with ZONE_TABLE(zone_idx_v) select
    color_v <= '0' when Z_BLACK, '1' when Z_WHITE, stripe_ph_v when Z_STRIPE;
  with ZONE_TABLE(zone_idx_h) select
    color_h <= '0' when Z_BLACK, '1' when Z_WHITE, stripe_ph_h when Z_STRIPE;

  active_level <= bram_level when sel_i = 4 else
                  white_s    when sel_i = 5 and ball_on = '1' else
                  black_s    when sel_i = 5 else
                  grad_x_s   when sel_i = 2 else
                  grad_y_s   when sel_i = 3 else
                  white_s    when (sel_i = 0 and color_v = '1') or
                                  (sel_i = 1 and color_h = '1') else
                  black_s;

  -- -----------------------------------------------------------------------
  -- Separate line sync and frame sync
  --
  --  in_vsync_s  :  HIGH during the broad-sync (vsync) region of each field
  --     PAL  F1: v =  0.. 7   PAL  F2: v = 312..319
  --     NTSC F1: v =  0.. 4   NTSC F2: v = 263..267
  --
  --  line_sync_s :  H sync pulse, suppressed on vsync lines
  --  frame_sync_s:  HIGH for the entire vsync region (= in_vsync_s)
  -- -----------------------------------------------------------------------
  in_vsync_s <= '1' when ntsc_mode = '0' and
                          (v_cnt <= 7 or (v_cnt >= 312 and v_cnt <= 319))
           else '1' when ntsc_mode = '1' and
                          (v_cnt <= 4 or (v_cnt >= 263 and v_cnt <= 267))
           else '0';

  line_sync_s  <= '1' when h_cnt >= H_FRONT and
                            h_cnt < H_FRONT + H_SYNC_W and
                            in_vsync_s = '0'
                  else '0';

  frame_sync_s <= in_vsync_s;

  -- -----------------------------------------------------------------------
  -- DAC output
  -- -----------------------------------------------------------------------
  dac_out       <= "0000"       when csync_s  = '1' else
                   active_level when active_s = '1' else
                   "0100";

  csync_o      <= csync_s;
  line_sync_o  <= line_sync_s;
  frame_sync_o <= frame_sync_s;
  field_o      <= field_s;
  active_o     <= active_s;
  blank_o      <= not csync_s and not active_s;

end architecture rtl;
