library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- PAL B&W BRAM Video IP (interlaced PAL, 625 lines, 50 Hz field rate)
--
-- Extends pal_tv_interlaced_top with a fifth pattern source (sel = 4):
-- pixels are read from an internal 1-bit BRAM written by the host.
--
-- sel 0  Vertical bars        (8 zones, STRIPE/WHITE/...)
-- sel 1  Horizontal bars      (8 zones per field)
-- sel 2  Horizontal gradient  (10 grey steps)
-- sel 3  Vertical gradient    (10 grey steps)
-- sel 4  BRAM pixel source    (Boolean: 0 = black_lvl, 1 = brightness)
-- sel 5  Bouncing ball        (white rectangle on black background, no BRAM needed)
--
-- BRAM write port (host side, independent of pixel clock):
--   bram_wr_en   pulse '1' for one clock to write one pixel
--   bram_wr_addr address (0 .. BRAM_DEPTH-1), 19-bit
--   bram_wr_data 1-bit pixel value
--
-- bram_len (runtime input):
--   Number of valid pixels stored in BRAM.  The read address wraps at this boundary.
--   bram_len = 520    one row, repeated on every active line (simple test card)
--   bram_len = 1040   two rows (one row-pair), repeated every row-pair
--   bram_len = 299520 full frame  (520 * 576 = all 576 image rows)
--
-- BRAM address layout (sel = 4) — natural sequential row order:
--   Write image rows 0, 1, 2, … 575 into BRAM sequentially;
--   the hardware automatically routes each row to the correct interlaced field.
--
--   addr       0 ..     519   image row  0  (F1 line 0,  screen row  0)
--   addr     520 ..    1039   image row  1  (F2 line 0,  screen row  1)
--   addr    1040 ..    1559   image row  2  (F1 line 1,  screen row  2)
--   addr    1560 ..    2079   image row  3  (F2 line 1,  screen row  3)
--   ...
--   addr k*1040      .. k*1040+519   image row 2k   (F1 line k, screen row 2k)
--   addr k*1040+520  .. k*1040+1039  image row 2k+1 (F2 line k, screen row 2k+1)
--   ...
--   addr 299000 .. 299519  image row 575 (F2 line 287, screen row 575)
--
-- Address generator: bram_rd_line_base + bram_px_cnt.
--   bram_rd_line_base advances by 2*H_ACTIVE after each active line (interlace stride).
--   F2 field starts with bram_rd_line_base = H_ACTIVE (image row 1).
--
-- Xilinx BRAM inference:
--   The bram_mem signal carries a "ram_style = block" attribute so Vivado
--   infers Block RAM.  BRAM_DEPTH = 299520 needs ~10 x BRAM36 on Artix-7.
--   Set BRAM_DEPTH to a power-of-two for most efficient packing.
entity pal_tv_bram_top is
  generic (
    H_FRONT    : integer := 16;
    H_SYNC_W   : integer := 47;
    H_BACK     : integer := 57;
    H_ACTIVE   : integer := 520;
    H_TOTAL    : integer := 640;
    V_TOTAL    : integer := 625;
    LEVEL_SYNC  : std_logic_vector(3 downto 0) := "0000";
    LEVEL_BLANK : std_logic_vector(3 downto 0) := "0100";
    LEVEL_WHITE : std_logic_vector(3 downto 0) := "1111";
    CLK_MHZ     : integer := 40;
    STRIPE_W    : integer := 4;
    BRAM_DEPTH  : integer := 299520   -- 520 * 576; set to 524288 (2^19) for power-of-2
  );
  port (
    clk          : in  std_logic;
    rst          : in  std_logic;
    sel          : in  std_logic_vector(7 downto 0);
    brightness   : in  std_logic_vector(3 downto 0) := "1111";  -- white level
    black_lvl    : in  std_logic_vector(3 downto 0) := "0100";  -- black/floor level
    -- BRAM write port (synchronous; write at any time, gated only by bram_wr_en)
    bram_wr_en   : in  std_logic                     := '0';
    bram_wr_addr : in  std_logic_vector(18 downto 0) := (others => '0');
    bram_wr_data : in  std_logic                     := '0';
    -- Number of valid pixels in BRAM (address wraps here)
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
end entity pal_tv_bram_top;

architecture rtl of pal_tv_bram_top is

  constant H_ACT_S    : integer := H_FRONT + H_SYNC_W + H_BACK;  -- 120

  constant V_ACT_S_F1 : integer := 24;
  constant V_ACT_E_F1 : integer := 311;
  constant V_ACT_S_F2 : integer := 336;
  constant V_ACT_E_F2 : integer := 623;
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

  -- Bouncing ball (sel = 5)
  constant BALL_W  : integer := 60;   -- ball width  (pixels)
  constant BALL_H  : integer := 50;   -- ball height (screen rows)


  -- -----------------------------------------------------------------------
  -- 1-bit BRAM  (Vivado: infer Block RAM via ram_style attribute)
  -- -----------------------------------------------------------------------
  type bram_t is array (0 to BRAM_DEPTH - 1) of std_logic;
  signal bram_mem     : bram_t := (others => '0');
  attribute ram_style          : string;
  attribute ram_style of bram_mem : signal is "block";

  signal bram_rd_line_base : integer := 0;               -- BRAM start addr of current active line
  signal bram_px_cnt  : integer range 0 to H_ACTIVE - 1 := 0;  -- pixel offset within line
  signal bram_rd_sum  : integer := 0;                    -- line_base + px_cnt (combinational)
  signal bram_rd_addr : integer range 0 to BRAM_DEPTH - 1 := 0;
  signal bram_pixel   : std_logic;
  signal bram_len_i   : integer range 1 to BRAM_DEPTH;
  signal bram_level   : std_logic_vector(3 downto 0);

  -- Animation: bouncing ball (sel = 5)
  signal screen_x : integer := 0;   -- pixel column within active line (0..H_ACTIVE-1)
  signal screen_y : integer := 0;   -- screen row (0..575; even = F1, odd = F2)
  signal ball_x   : integer := 0;   -- ball left  edge (0 .. H_ACTIVE - BALL_W)
  signal ball_y   : integer := 0;   -- ball top   edge (0 .. 576 - BALL_H)
  signal ball_vx  : integer := 3;   -- horizontal velocity (pixels / frame)
  signal ball_vy  : integer := 2;   -- vertical   velocity (rows   / frame)
  signal ball_on  : std_logic := '0';


  -- H/V counters
  signal h_cnt : integer range 0 to 639;
  signal v_cnt : integer range 0 to 624;
  signal ce_s  : std_logic;

  -- Interlaced composite sync
  signal csync_s      : std_logic;
  signal field_s      : std_logic;
  signal active_s     : std_logic;
  -- Separate line / frame sync
  signal in_vsync_s   : std_logic;   -- HIGH during vsync broad-sync region
  signal line_sync_s  : std_logic;   -- H sync pulse, suppressed during vsync
  signal frame_sync_s : std_logic;   -- V sync = in_vsync_s

  signal in_f1_active  : boolean;
  signal in_f2_active  : boolean;
  signal in_any_active : boolean;

  -- Pattern generator state
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

  -- Brightness / black level
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

  u_timing : entity work.pal_timing
    generic map (H_TOTAL => H_TOTAL, V_TOTAL => V_TOTAL, CLK_MHZ => CLK_MHZ)
    port map (clk => clk, rst => rst, ce => ce_s,
              h_cnt => h_cnt, v_cnt => v_cnt);

  u_csync : entity work.pal_csync_il
    generic map (
      H_FRONT => H_FRONT, H_SYNC_W => H_SYNC_W,
      H_BACK  => H_BACK,  H_ACTIVE => H_ACTIVE, H_TOTAL => H_TOTAL,
      V_ACT_S_F1 => V_ACT_S_F1, V_ACT_E_F1 => V_ACT_E_F1,
      V_ACT_S_F2 => V_ACT_S_F2, V_ACT_E_F2 => V_ACT_E_F2)
    port map (h_cnt => h_cnt, v_cnt => v_cnt,
              csync => csync_s, field => field_s, active => active_s);

  in_f1_active  <= (v_cnt >= V_ACT_S_F1 and v_cnt <= V_ACT_E_F1);
  in_f2_active  <= (v_cnt >= V_ACT_S_F2 and v_cnt <= V_ACT_E_F2);
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
            else
              stripe_cnt_v <= stripe_cnt_v + 1;
            end if;
          end if;
        end if;
      end if;
    end if;
  end process;

  -- -----------------------------------------------------------------------
  -- Horizontal bar generator
  -- -----------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        zone_idx_h <= 0; line_in_zone <= 0; stripe_cnt_h <= 0; stripe_ph_h <= '0';
      elsif ce_s = '1' then
        if (v_cnt = V_ACT_S_F1 - 1 or v_cnt = V_ACT_S_F2 - 1) and
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
            else
              stripe_cnt_h <= stripe_cnt_h + 1;
            end if;
          end if;
        end if;
      end if;
    end if;
  end process;

  -- -----------------------------------------------------------------------
  -- Horizontal gradient generator
  -- -----------------------------------------------------------------------
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
          else
            gpx_in <= gpx_in + 1;
          end if;
        end if;
      end if;
    end if;
  end process;

  -- -----------------------------------------------------------------------
  -- Vertical gradient generator
  -- -----------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        gzy_idx <= 0; gln_in <= 0;
      elsif ce_s = '1' then
        if (v_cnt = V_ACT_S_F1 - 1 or v_cnt = V_ACT_S_F2 - 1) and
           h_cnt = H_TOTAL - 1 then
          gzy_idx <= 0; gln_in <= 0;
        elsif in_any_active and h_cnt = H_TOTAL - 1 then
          if gln_in = GZONE_H - 1 then
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
  -- Animation: screen pixel-X counter
  --   Resets to 0 at the clock before the first active pixel on each line.
  --   Holds current column index while active_s = '1'.
  -- -----------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        screen_x <= 0;
      elsif ce_s = '1' then
        if h_cnt = H_ACT_S - 1 and in_any_active then
          screen_x <= 0;          -- pre-load: next clock is first active pixel
        elsif active_s = '1' then
          screen_x <= screen_x + 1;
        end if;
      end if;
    end if;
  end process;

  -- -----------------------------------------------------------------------
  -- Animation: screen row-Y counter
  --   F1 line k → screen row 2k (even), F2 line k → screen row 2k+1 (odd).
  --   Pre-loaded one line before the first active line of each field so that
  --   screen_y = 0 during F1 line 0 and screen_y = 1 during F2 line 0.
  -- -----------------------------------------------------------------------
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        screen_y <= 0;
      elsif ce_s = '1' then
        if v_cnt = V_ACT_S_F1 - 1 and h_cnt = H_TOTAL - 1 then
          screen_y <= 0;              -- F1 line 0 = screen row 0
        elsif v_cnt = V_ACT_S_F2 - 1 and h_cnt = H_TOTAL - 1 then
          screen_y <= 1;              -- F2 line 0 = screen row 1
        elsif in_any_active and h_cnt = H_TOTAL - 1 then
          screen_y <= screen_y + 2;   -- interlace: skip one row per active line
        end if;
      end if;
    end if;
  end process;

  -- -----------------------------------------------------------------------
  -- Animation: ball physics  (updated once per frame at end of F2)
  --   Position is clamped by elastic bounce: reflect velocity on wall contact.
  -- -----------------------------------------------------------------------
  process(clk)
    variable nx, ny, nvx, nvy : integer;
  begin
    if rising_edge(clk) then
      if rst = '1' then
        ball_x  <= 0;
        ball_y  <= 0;
        ball_vx <= 3;
        ball_vy <= 2;
      elsif ce_s = '1' and v_cnt = V_ACT_E_F2 and h_cnt = H_TOTAL - 1 then
        nx  := ball_x + ball_vx;
        ny  := ball_y + ball_vy;
        nvx := ball_vx;
        nvy := ball_vy;
        -- Right wall
        if nx > H_ACTIVE - BALL_W then
          nx  := 2 * (H_ACTIVE - BALL_W) - nx;
          nvx := -nvx;
        end if;
        -- Left wall
        if nx < 0 then
          nx  := -nx;
          nvx := -nvx;
        end if;
        -- Bottom wall
        if ny > 576 - BALL_H then
          ny  := 2 * (576 - BALL_H) - ny;
          nvy := -nvy;
        end if;
        -- Top wall
        if ny < 0 then
          ny  := -ny;
          nvy := -nvy;
        end if;
        ball_x  <= nx;
        ball_y  <= ny;
        ball_vx <= nvx;
        ball_vy <= nvy;
      end if;
    end if;
  end process;

  -- '1' when the current pixel lies inside the ball rectangle
  ball_on <= '1' when screen_x >= ball_x and
                      screen_x <  ball_x + BALL_W and
                      screen_y >= ball_y and
                      screen_y <  ball_y + BALL_H
             else '0';


  -- -----------------------------------------------------------------------
  -- BRAM: synchronous write, asynchronous read
  -- -----------------------------------------------------------------------
  -- Clamp bram_len to [1 .. BRAM_DEPTH]; 0 or overflow → use full depth
  bram_len_i <= BRAM_DEPTH
                  when to_integer(unsigned(bram_len)) = 0 or
                       to_integer(unsigned(bram_len)) > BRAM_DEPTH
                  else to_integer(unsigned(bram_len));

  -- Write port (host writes pixel data; bounds-checked)
  process(clk)
  begin
    if rising_edge(clk) then
      if bram_wr_en = '1' and
         to_integer(unsigned(bram_wr_addr)) < BRAM_DEPTH then
        bram_mem(to_integer(unsigned(bram_wr_addr))) <= bram_wr_data;
      end if;
    end if;
  end process;

  -- Natural sequential row address generator.
  --   F1 reads even image rows (0, 2, 4, …);  F2 reads odd rows (1, 3, 5, …).
  --   bram_rd_line_base: BRAM start address of the current active line.
  --   bram_px_cnt:       pixel offset within the active line (0 .. H_ACTIVE-1).
  process(clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        bram_rd_line_base <= 0;
        bram_px_cnt       <= 0;
      elsif ce_s = '1' then
        -- F1 frame start: line 0 → image row 0 (addr 0)
        if v_cnt = V_ACT_S_F1 - 1 and h_cnt = H_TOTAL - 1 then
          bram_rd_line_base <= 0;
          bram_px_cnt       <= 0;
        -- F2 field start: line 0 → image row 1 (addr H_ACTIVE = 520)
        elsif v_cnt = V_ACT_S_F2 - 1 and h_cnt = H_TOTAL - 1 then
          bram_rd_line_base <= H_ACTIVE;
          bram_px_cnt       <= 0;
        -- End of any other active line: stride by 2 rows (interlace step)
        elsif in_any_active and h_cnt = H_TOTAL - 1 then
          bram_rd_line_base <= bram_rd_line_base + 2 * H_ACTIVE;
          bram_px_cnt       <= 0;
        -- Within active region: advance pixel counter
        elsif active_s = '1' then
          bram_px_cnt <= bram_px_cnt + 1;
        end if;
      end if;
    end if;
  end process;

  -- Combinational address: sum clamped to [0, bram_len_i)
  bram_rd_sum  <= bram_rd_line_base + bram_px_cnt;
  bram_rd_addr <= bram_rd_sum when bram_rd_sum < bram_len_i else 0;

  -- Asynchronous read (1-bit pixel)
  bram_pixel <= bram_mem(bram_rd_addr);
  bram_level <= white_s when bram_pixel = '1' else black_s;

  -- -----------------------------------------------------------------------
  -- Brightness / black-level control (same as interlaced_top)
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
  -- Active-level mux and DAC output
  -- -----------------------------------------------------------------------
  with ZONE_TABLE(zone_idx_v) select
    color_v <= '0' when Z_BLACK, '1' when Z_WHITE, stripe_ph_v when Z_STRIPE;
  with ZONE_TABLE(zone_idx_h) select
    color_h <= '0' when Z_BLACK, '1' when Z_WHITE, stripe_ph_h when Z_STRIPE;

  active_level <= bram_level when sel_i = 4 else
                  white_s    when sel_i = 5 and ball_on  = '1' else
                  black_s    when sel_i = 5 else
                  grad_x_s   when sel_i = 2 else
                  grad_y_s   when sel_i = 3 else
                  white_s    when (sel_i = 0 and color_v = '1') or
                                  (sel_i = 1 and color_h = '1') else
                  black_s;

  -- -----------------------------------------------------------------------
  -- Separate line sync and frame sync
  --
  --  in_vsync_s  : HIGH during the PAL broad-sync (vsync) region
  --     F1: v =  0.. 7   (5 pre-eq + 5 broad + 5 post-eq half-lines ≈ lines 0–7)
  --     F2: v = 312..319
  --
  --  line_sync_s : H sync pulse only, suppressed during vsync lines
  --  frame_sync_s: HIGH for the entire vsync region (one pulse per field)
  -- -----------------------------------------------------------------------
  in_vsync_s   <= '1' when (v_cnt <= 7) or (v_cnt >= 312 and v_cnt <= 319)
                  else '0';

  line_sync_s  <= '1' when h_cnt >= H_FRONT and
                            h_cnt < H_FRONT + H_SYNC_W and
                            in_vsync_s = '0'
                  else '0';

  frame_sync_s <= in_vsync_s;

  -- Blanking pedestal is always LEVEL_BLANK (TV standard; unaffected by black_lvl)
  dac_out       <= LEVEL_SYNC   when csync_s = '1' else
                   active_level when active_s = '1' else
                   LEVEL_BLANK;

  csync_o      <= csync_s;
  line_sync_o  <= line_sync_s;
  frame_sync_o <= frame_sync_s;
  field_o      <= field_s;
  active_o     <= active_s;
  blank_o      <= not csync_s and not active_s;

end architecture rtl;
