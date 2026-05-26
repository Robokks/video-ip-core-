library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- PAL B&W BRAM Video IP  --  interlaced  (V1.3)
-- ================================================
--
-- Revision history
--   V1.0 : PAL interlaced BRAM IP (625/50, interlaced composite sync)
--   V1.1 : Added standalone boolean FIFO (pal_fifo_bool, no BRAM link)
--   V1.2 : PROGRESSIVE generic (removed in V1.3)
--   V1.3 : Removed PROGRESSIVE generic; interlaced-only.
--          Eliminates pal_csync_prog dependency for Vivado IP packager.
--
-- PAL 625/50 interlaced, two fields per frame.
--   F1 (even rows 0,2,4,...): lines V_ACT_S_F1 .. V_ACT_E_F1
--   F2 (odd  rows 1,3,5,...): lines V_ACT_S_F2 .. V_ACT_E_F2
--   Composite sync via pal_csync_il.
--
-- sel 0  Vertical bars
-- sel 1  Horizontal bars
-- sel 2  Horizontal gradient  (10 grey steps)
-- sel 3  Vertical gradient    (10 grey steps)
-- sel 4  BRAM pixel source    (0=black_lvl, 1=brightness)
-- sel 5  Bouncing ball
-- sel 6  Full white
-- sel 7  Full black
-- sel 8  Crosshatch grid
-- sel 9  Centre cross

entity pal_tv_bram_top is
  generic (
    H_FRONT      : integer := 16;
    H_SYNC_W     : integer := 47;
    H_BACK       : integer := 57;
    H_ACTIVE     : integer := 520;
    H_TOTAL      : integer := 640;
    V_TOTAL      : integer := 625;
    LEVEL_SYNC   : std_logic_vector(3 downto 0) := "0000";
    LEVEL_BLANK  : std_logic_vector(3 downto 0) := "0100";
    LEVEL_WHITE  : std_logic_vector(3 downto 0) := "1111";
    CLK_MHZ      : integer := 40;
    STRIPE_W     : integer := 4;
    BRAM_DEPTH   : integer := 299520
  );
  port (
    clk          : in  std_logic;
    rst          : in  std_logic;
    sel          : in  std_logic_vector(7 downto 0);
    brightness   : in  std_logic_vector(3 downto 0) := "1111";
    black_lvl    : in  std_logic_vector(3 downto 0) := "0100";
    bram_wr_en   : in  std_logic                     := '0';
    bram_wr_addr : in  std_logic_vector(18 downto 0) := (others => '0');
    bram_wr_data : in  std_logic                     := '0';
    bram_len     : in  std_logic_vector(18 downto 0) := (others => '1');
    buf_swap     : in  std_logic := '0';
    buf_swapped  : out std_logic;
    back_buf_o   : out std_logic;
    ball_spd_h   : in  std_logic_vector(3 downto 0) := "0011";
    ball_spd_v   : in  std_logic_vector(3 downto 0) := "0010";
    ball_w_i     : in  std_logic_vector(9 downto 0) := "0000111100";
    ball_h_i     : in  std_logic_vector(9 downto 0) := "0000110010";
    cross_h_i    : in  std_logic_vector(9 downto 0) := "0000110100";
    cross_v_i    : in  std_logic_vector(9 downto 0) := "0000111010";
    dac_out      : out std_logic_vector(3 downto 0);
    csync_o      : out std_logic;
    line_sync_o  : out std_logic;
    frame_sync_o : out std_logic;
    fss_o        : out std_logic;   -- Field Sync Signal 50 Hz (broad-sync + post-EQ of every field)
    field_o      : out std_logic;
    active_o     : out std_logic;
    blank_o      : out std_logic
  );
end entity pal_tv_bram_top;

architecture rtl of pal_tv_bram_top is

  constant H_ACT_S    : integer := H_FRONT + H_SYNC_W + H_BACK;  -- 120

  -- -------------------------------------------------------------------------
  -- Interlaced V timing  (PAL 625/50 two-field)
  -- -------------------------------------------------------------------------
  constant V_ACT_S_F1 : integer := 24;
  constant V_ACT_E_F1 : integer := 311;
  constant V_ACT_S_F2 : integer := 336;
  constant V_ACT_E_F2 : integer := 623;

  -- Frame boundaries
  constant V_FRAME_S  : integer := V_ACT_S_F1;
  constant V_FRAME_E  : integer := V_ACT_E_F2;

  -- Active rows per field (288 lines per field, 576 total)
  constant V_ACTIVE_F : integer := 288;

  constant NUM_ZONES  : integer := 8;
  constant ZONE_W     : integer := H_ACTIVE  / NUM_ZONES;   -- 65
  constant ZONE_H     : integer := V_ACTIVE_F / NUM_ZONES;  -- 36

  type zone_kind    is (Z_BLACK, Z_WHITE, Z_STRIPE);
  type zone_table_t is array (0 to NUM_ZONES - 1) of zone_kind;
  constant ZONE_TABLE : zone_table_t := (
    0 => Z_STRIPE, 1 => Z_WHITE,  2 => Z_STRIPE, 3 => Z_WHITE,
    4 => Z_BLACK,  5 => Z_STRIPE, 6 => Z_WHITE,  7 => Z_STRIPE
  );

  constant GZONES  : integer := 10;
  constant GZONE_W : integer := H_ACTIVE  / GZONES;   -- 52
  constant GZONE_H : integer := V_ACTIVE_F / GZONES;  -- 28

  -- Ball
  signal ball_w_s      : integer range 1 to 520 := 60;
  signal ball_h_s      : integer range 1 to 576 := 50;
  signal ball_spd_h_s  : integer range 1 to 15  := 3;
  signal ball_spd_v_s  : integer range 1 to 15  := 2;

  -- Crosshatch
  signal cross_h_s     : integer range 1 to 520 := 52;
  signal cross_v_s     : integer range 1 to 576 := 58;
  signal cross_x_cnt   : integer range 0 to 519 := 0;
  signal cross_y_cnt   : integer range 0 to 575 := 0;
  signal cross_on      : std_logic;
  signal centre_on     : std_logic;

  -- BRAM double-buffer
  type bram_t is array (0 to BRAM_DEPTH - 1) of std_logic;
  signal bram_mem_0   : bram_t := (others => '0');
  signal bram_mem_1   : bram_t := (others => '0');
  attribute ram_style               : string;
  attribute ram_style of bram_mem_0 : signal is "block";
  attribute ram_style of bram_mem_1 : signal is "block";

  signal disp_buf      : std_logic := '0';
  signal swap_req      : std_logic := '0';
  signal buf_swapped_s : std_logic := '0';

  signal bram_rd_line_base : integer := 0;
  signal bram_px_cnt  : integer range 0 to H_ACTIVE - 1 := 0;
  signal bram_rd_sum  : integer := 0;
  signal bram_rd_addr : integer range 0 to BRAM_DEPTH - 1 := 0;
  signal bram_pixel   : std_logic;
  signal bram_len_i   : integer range 1 to BRAM_DEPTH;
  signal bram_level   : std_logic_vector(3 downto 0);

  -- Screen counters and ball
  signal screen_x : integer := 0;
  signal screen_y : integer := 0;
  signal ball_x   : integer := 0;
  signal ball_y   : integer := 0;
  signal ball_vx  : integer := 3;
  signal ball_vy  : integer := 2;
  signal ball_on  : std_logic := '0';

  -- H/V counters
  signal h_cnt : integer range 0 to 639;
  signal v_cnt : integer range 0 to 624;
  signal ce_s  : std_logic;

  -- Sync
  signal csync_s      : std_logic;
  signal field_s      : std_logic;
  signal active_s     : std_logic;

  -- Derived sync outputs
  signal in_vsync_s   : std_logic;
  signal fss_s        : std_logic;
  signal line_sync_s  : std_logic;
  signal frame_sync_s : std_logic;

  -- Active region flags
  signal in_f1_active  : boolean;
  signal in_f2_active  : boolean;
  signal in_any_active : boolean;

  -- Pattern state
  signal zone_idx_v   : integer range 0 to NUM_ZONES - 1 := 0;
  signal px_in_zone   : integer range 0 to ZONE_W - 1     := 0;
  signal stripe_cnt_v : integer range 0 to STRIPE_W - 1   := 0;
  signal stripe_ph_v  : std_logic                         := '0';

  signal zone_idx_h   : integer range 0 to NUM_ZONES - 1 := 0;
  signal line_in_zone : integer range 0 to ZONE_H - 1     := 0;
  signal stripe_cnt_h : integer range 0 to STRIPE_W - 1   := 0;
  signal stripe_ph_h  : std_logic                         := '0';

  signal gzx_idx : integer range 0 to GZONES - 1  := 0;
  signal gpx_in  : integer range 0 to GZONE_W - 1 := 0;
  signal gzy_idx : integer range 0 to GZONES - 1  := 0;
  signal gln_in  : integer range 0 to GZONE_H - 1 := 0;

  signal color_v      : std_logic;
  signal color_h      : std_logic;
  signal sel_i        : integer range 0 to 255;
  signal active_level : std_logic_vector(3 downto 0);

  signal white_level_i : integer range 4 to 15;
  signal white_s       : std_logic_vector(3 downto 0);
  signal black_level_i : integer range 4 to 15;
  signal black_s       : std_logic_vector(3 downto 0);
  signal grad_x_s      : std_logic_vector(3 downto 0);
  signal grad_y_s      : std_logic_vector(3 downto 0);

begin

  assert NUM_ZONES * ZONE_W = H_ACTIVE
    report "NUM_ZONES * ZONE_W /= H_ACTIVE" severity failure;
  assert NUM_ZONES * ZONE_H = V_ACTIVE_F
    report "NUM_ZONES * ZONE_H /= V_ACTIVE_F" severity failure;
  assert GZONES * GZONE_W = H_ACTIVE
    report "GZONES * GZONE_W /= H_ACTIVE" severity failure;

  sel_i <= to_integer(unsigned(sel));

  -- -------------------------------------------------------------------------
  -- Runtime parameter clamping
  -- -------------------------------------------------------------------------
  ball_w_s     <= 1 when to_integer(unsigned(ball_w_i))   = 0 else to_integer(unsigned(ball_w_i));
  ball_h_s     <= 1 when to_integer(unsigned(ball_h_i))   = 0 else to_integer(unsigned(ball_h_i));
  ball_spd_h_s <= 1 when to_integer(unsigned(ball_spd_h)) = 0 else to_integer(unsigned(ball_spd_h));
  ball_spd_v_s <= 1 when to_integer(unsigned(ball_spd_v)) = 0 else to_integer(unsigned(ball_spd_v));
  cross_h_s    <= 1 when to_integer(unsigned(cross_h_i))  = 0 else to_integer(unsigned(cross_h_i));
  cross_v_s    <= 1 when to_integer(unsigned(cross_v_i))  = 0 else to_integer(unsigned(cross_v_i));

  centre_on <= '1' when screen_x = H_ACTIVE / 2 or screen_y = 288 else '0';
  cross_on  <= '1' when cross_x_cnt = 0 or cross_y_cnt = 0 else '0';

  -- -------------------------------------------------------------------------
  -- Shared free-running H/V counters
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
      H_BACK     => H_BACK,     H_ACTIVE   => H_ACTIVE,  H_TOTAL => H_TOTAL,
      V_ACT_S_F1 => V_ACT_S_F1, V_ACT_E_F1 => V_ACT_E_F1,
      V_ACT_S_F2 => V_ACT_S_F2, V_ACT_E_F2 => V_ACT_E_F2)
    port map (h_cnt => h_cnt, v_cnt => v_cnt,
              csync => csync_s, field => field_s, active => active_s);

  -- -------------------------------------------------------------------------
  -- Active region flags
  -- -------------------------------------------------------------------------
  in_f1_active  <= (v_cnt >= V_ACT_S_F1 and v_cnt <= V_ACT_E_F1);
  in_f2_active  <= (v_cnt >= V_ACT_S_F2 and v_cnt <= V_ACT_E_F2);
  in_any_active <= in_f1_active or in_f2_active;

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
        if (v_cnt = V_FRAME_S - 1 or v_cnt = V_ACT_S_F2 - 1) and
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
        if (v_cnt = V_FRAME_S - 1 or v_cnt = V_ACT_S_F2 - 1) and
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
  -- Screen X counter
  -- -------------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        screen_x <= 0;
      elsif ce_s = '1' then
        if h_cnt = H_ACT_S - 1 and in_any_active then screen_x <= 0;
        elsif active_s = '1' then screen_x <= screen_x + 1; end if;
      end if;
    end if;
  end process;

  -- -------------------------------------------------------------------------
  -- Screen Y counter  (image row 0..575)
  --   F1 line k -> row 2k (even rows)   pre-loaded at V_ACT_S_F1 - 1
  --   F2 line k -> row 2k+1 (odd rows)  pre-loaded at V_ACT_S_F2 - 1
  --   Each active line advances by 2 (interlace stride).
  -- -------------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        screen_y <= 0;
      elsif ce_s = '1' then
        if v_cnt = V_ACT_S_F1 - 1 and h_cnt = H_TOTAL - 1 then
          screen_y <= 0;                        -- F1 frame start: row 0
        elsif v_cnt = V_ACT_S_F2 - 1 and h_cnt = H_TOTAL - 1 then
          screen_y <= 1;                        -- F2 field start: row 1
        elsif in_any_active and h_cnt = H_TOTAL - 1 then
          screen_y <= screen_y + 2;             -- interlace: skip one row
        end if;
      end if;
    end if;
  end process;

  -- -------------------------------------------------------------------------
  -- Ball physics  (updated once per frame at end of F2 last active line)
  -- -------------------------------------------------------------------------
  process(clk)
    variable nx, ny, nvx, nvy : integer;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        ball_x <= 0; ball_y <= 0;
        ball_vx <= ball_spd_h_s; ball_vy <= ball_spd_v_s;
      elsif ce_s = '1' and v_cnt = V_FRAME_E and h_cnt = H_TOTAL - 1 then
        nx := ball_x + ball_vx;  ny := ball_y + ball_vy;
        nvx := ball_vx;          nvy := ball_vy;
        if nx > H_ACTIVE - ball_w_s then
          nx := 2 * (H_ACTIVE - ball_w_s) - nx; nvx := -nvx;
        end if;
        if nx < 0 then nx := -nx; nvx := -nvx; end if;
        if ny > 576 - ball_h_s then
          ny := 2 * (576 - ball_h_s) - ny; nvy := -nvy;
        end if;
        if ny < 0 then ny := -ny; nvy := -nvy; end if;
        ball_x <= nx; ball_y <= ny; ball_vx <= nvx; ball_vy <= nvy;
      end if;
    end if;
  end process;

  ball_on <= '1' when screen_x >= ball_x and screen_x < ball_x + ball_w_s and
                      screen_y >= ball_y and screen_y < ball_y + ball_h_s
             else '0';

  -- -------------------------------------------------------------------------
  -- BRAM: synchronous write (back buffer), asynchronous read (front buffer)
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
        if disp_buf = '0' then
          bram_mem_1(to_integer(unsigned(bram_wr_addr))) <= bram_wr_data;
        else
          bram_mem_0(to_integer(unsigned(bram_wr_addr))) <= bram_wr_data;
        end if;
      end if;
    end if;
  end process;

  -- -------------------------------------------------------------------------
  -- Double-buffer swap  (at end of last active line of F2, i.e. V_FRAME_E)
  -- -------------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        disp_buf <= '0'; swap_req <= '0'; buf_swapped_s <= '0';
      elsif ce_s = '1' then
        buf_swapped_s <= '0';
        if buf_swap = '1' then swap_req <= '1'; end if;
        if v_cnt = V_FRAME_E and h_cnt = H_TOTAL - 1 and swap_req = '1' then
          disp_buf <= not disp_buf; swap_req <= '0'; buf_swapped_s <= '1';
        end if;
      end if;
    end if;
  end process;

  -- -------------------------------------------------------------------------
  -- BRAM address generator  (interlaced stride = 2*H_ACTIVE)
  --   F1 start  -> addr 0          (image row 0)
  --   F2 start  -> addr H_ACTIVE   (image row 1)
  --   Each active line: base += 2*H_ACTIVE  (reads rows 0,2,4,... or 1,3,5,...)
  -- -------------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        bram_rd_line_base <= 0; bram_px_cnt <= 0;
      elsif ce_s = '1' then

        -- F1 / frame start: address 0
        if v_cnt = V_FRAME_S - 1 and h_cnt = H_TOTAL - 1 then
          bram_rd_line_base <= 0;
          bram_px_cnt       <= 0;

        -- F2 field start: address H_ACTIVE (image row 1)
        elsif v_cnt = V_ACT_S_F2 - 1 and h_cnt = H_TOTAL - 1 then
          bram_rd_line_base <= H_ACTIVE;
          bram_px_cnt       <= 0;

        -- End of active line: advance by 2 rows
        elsif in_any_active and h_cnt = H_TOTAL - 1 then
          bram_rd_line_base <= bram_rd_line_base + 2 * H_ACTIVE;
          bram_px_cnt <= 0;

        -- Within active region: advance pixel counter
        elsif active_s = '1' then
          bram_px_cnt <= bram_px_cnt + 1;
        end if;

      end if;
    end if;
  end process;

  bram_rd_sum  <= bram_rd_line_base + bram_px_cnt;
  bram_rd_addr <= bram_rd_sum when bram_rd_sum < bram_len_i else 0;

  -- Synchronous BRAM read -- REQUIRED for block RAM inference.
  -- Vivado cannot map asynchronous (combinational) reads to RAMB36/RAMB18;
  -- without this the tool falls back to distributed RAM (RAMD64E/LUT-RAM)
  -- which exhausts LUT resources on any device for a 300 Kbit buffer.
  -- The registered output introduces a 1-pixel pipeline delay (imperceptible).
  process(clk)
  begin
    if rising_edge(clk) then
      if ce_s = '1' then
        if disp_buf = '0' then
          bram_pixel <= bram_mem_0(bram_rd_addr);
        else
          bram_pixel <= bram_mem_1(bram_rd_addr);
        end if;
      end if;
    end if;
  end process;

  bram_level <= white_s when bram_pixel = '1' else black_s;

  buf_swapped <= buf_swapped_s;
  back_buf_o  <= not disp_buf;

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

  -- -------------------------------------------------------------------------
  -- Crosshatch counters
  -- -------------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then cross_x_cnt <= 0;
      elsif ce_s = '1' then
        if h_cnt = H_ACT_S - 1 and in_any_active then
          cross_x_cnt <= 0;
        elsif active_s = '1' then
          if cross_x_cnt = cross_h_s - 1 then cross_x_cnt <= 0;
          else cross_x_cnt <= cross_x_cnt + 1; end if;
        end if;
      end if;
    end if;
  end process;

  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then cross_y_cnt <= 0;
      elsif ce_s = '1' then
        if v_cnt = V_FRAME_S and h_cnt = 0 then
          cross_y_cnt <= 0;
        elsif in_any_active and h_cnt = H_TOTAL - 1 then
          if cross_y_cnt = cross_v_s - 1 then cross_y_cnt <= 0;
          else cross_y_cnt <= cross_y_cnt + 1; end if;
        end if;
      end if;
    end if;
  end process;

  -- -------------------------------------------------------------------------
  -- Active-level mux and DAC output
  -- -------------------------------------------------------------------------
  with ZONE_TABLE(zone_idx_v) select
    color_v <= '0' when Z_BLACK, '1' when Z_WHITE, stripe_ph_v when Z_STRIPE;
  with ZONE_TABLE(zone_idx_h) select
    color_h <= '0' when Z_BLACK, '1' when Z_WHITE, stripe_ph_h when Z_STRIPE;

  active_level <= bram_level when sel_i = 4 else
                  white_s    when sel_i = 5 and ball_on   = '1' else
                  black_s    when sel_i = 5 else
                  white_s    when sel_i = 6 else
                  black_s    when sel_i = 7 else
                  white_s    when sel_i = 8 and cross_on  = '1' else
                  black_s    when sel_i = 8 else
                  white_s    when sel_i = 9 and centre_on = '1' else
                  black_s    when sel_i = 9 else
                  grad_x_s   when sel_i = 2 else
                  grad_y_s   when sel_i = 3 else
                  white_s    when (sel_i = 0 and color_v = '1') or
                                  (sel_i = 1 and color_h = '1') else
                  black_s;

  -- -------------------------------------------------------------------------
  -- Line sync / frame sync / V-sync outputs
  -- -------------------------------------------------------------------------
  in_vsync_s <= '1' when (v_cnt <= 7) or (v_cnt >= 312 and v_cnt <= 319)
                else '0';

  line_sync_s  <= '1' when h_cnt >= H_FRONT and
                            h_cnt < H_FRONT + H_SYNC_W and
                            in_vsync_s = '0'
                  else '0';

  frame_sync_s <= '1' when v_cnt <= 7 else '0';   -- 25 Hz, F1 start only

  -- FSS: broad-sync + post-equalising only (excludes pre-eq lines 0-2 / 312-314)
  fss_s <= '1' when (v_cnt >= 3 and v_cnt <= 7) or
                    (v_cnt >= 315 and v_cnt <= 319)
           else '0';

  dac_out      <= LEVEL_SYNC   when csync_s = '1' else
                  active_level when active_s = '1' else
                  LEVEL_BLANK;

  csync_o      <= csync_s;
  line_sync_o  <= line_sync_s;
  frame_sync_o <= frame_sync_s;
  fss_o        <= fss_s;
  field_o      <= field_s;
  active_o     <= active_s;
  blank_o      <= not active_s;   -- HIGH for full 12 µs H-blank + V-blank

end architecture rtl;
