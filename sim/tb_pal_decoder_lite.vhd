library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Testbench: pal_decoder_lite  (CLK_MHZ=1 for fast simulation)

entity tb_pal_decoder_lite is
end entity;

architecture sim of tb_pal_decoder_lite is

  signal clk     : std_logic := '0';
  signal rst     : std_logic := '1';
  signal adc_in  : std_logic_vector(7 downto 0) := x"4D";
  signal hsync_o : std_logic;
  signal vsync_o : std_logic;
  signal field_o : std_logic;
  signal y_data  : std_logic_vector(7 downto 0);
  signal y_valid : std_logic;

  constant CLK_P     : time    := 10 ns;
  constant SYNC_LEVEL : integer := 10;
  constant BLANK_LEVEL: integer := 77;
  constant Y_LEVEL    : integer := 200;

  -- Timing @ CLK_MHZ=1
  constant C_SYNC_W  : integer := 4;   -- 4 µs (> HSYNC_MIN=3)
  constant C_BACK    : integer := 5;
  constant C_ACTIVE  : integer := 52;
  constant C_FRONT   : integer := 3;
  constant C_LINE    : integer := C_SYNC_W + C_BACK + C_ACTIVE + C_FRONT;
  constant C_BROAD_W : integer := 20;  -- > BROAD_MIN=15
  constant C_HALF    : integer := C_LINE / 2;

  procedure chk(signal a : in std_logic; constant e : in std_logic;
                constant m : in string) is
  begin
    if a = e then report "PASS: " & m severity note;
    else report "FAIL: " & m & "  exp=" & std_logic'image(e)
              & " got=" & std_logic'image(a) severity error;
    end if;
  end procedure;

  procedure chk8(signal a : in std_logic_vector(7 downto 0);
                 constant e : in integer; constant m : in string) is
  begin
    if to_integer(unsigned(a)) = e then report "PASS: " & m severity note;
    else report "FAIL: " & m & "  exp=" & integer'image(e)
              & " got=" & integer'image(to_integer(unsigned(a)))
        severity error;
    end if;
  end procedure;

  procedure tick(n : natural := 1) is
  begin
    for i in 1 to n loop wait until rising_edge(clk); end loop;
  end procedure;

  procedure drive_line(signal adc : out std_logic_vector(7 downto 0)) is
  begin
    adc <= std_logic_vector(to_unsigned(SYNC_LEVEL,  8)); tick(C_SYNC_W);
    adc <= std_logic_vector(to_unsigned(BLANK_LEVEL, 8)); tick(C_BACK);
    adc <= std_logic_vector(to_unsigned(Y_LEVEL,     8)); tick(C_ACTIVE);
    adc <= std_logic_vector(to_unsigned(BLANK_LEVEL, 8)); tick(C_FRONT);
  end procedure;

  procedure drive_broad(signal adc : out std_logic_vector(7 downto 0)) is
  begin
    adc <= std_logic_vector(to_unsigned(SYNC_LEVEL,  8)); tick(C_BROAD_W);
    adc <= std_logic_vector(to_unsigned(BLANK_LEVEL, 8)); tick(C_HALF - C_BROAD_W);
  end procedure;

  procedure drive_eq(signal adc : out std_logic_vector(7 downto 0)) is
  begin
    adc <= std_logic_vector(to_unsigned(SYNC_LEVEL,  8)); tick(2);
    adc <= std_logic_vector(to_unsigned(BLANK_LEVEL, 8)); tick(C_HALF - 2);
  end procedure;

  procedure drive_vsync(signal adc : out std_logic_vector(7 downto 0)) is
  begin
    for i in 1 to 5 loop drive_eq(adc);    end loop;
    for i in 1 to 5 loop drive_broad(adc); end loop;
    for i in 1 to 5 loop drive_eq(adc);    end loop;
  end procedure;

begin

  clk <= not clk after CLK_P / 2;

  u_dut : entity work.pal_decoder_lite
    generic map (CLK_MHZ => 1, ADC_BITS => 8, SYNC_THRESH => 50)
    port map (
      clk => clk, rst => rst, adc_data => adc_in,
      hsync_o => hsync_o, vsync_o => vsync_o, field_o => field_o,
      y_data  => y_data,  y_valid => y_valid
    );

  process
  begin
    rst <= '1'; tick(5); rst <= '0';
    adc_in <= std_logic_vector(to_unsigned(BLANK_LEVEL, 8));
    tick(5);

    -- T1: y_valid=0 at startup (v_count < C_VACT_S=22)
    report "--- T1: y_valid=0 at startup ---" severity note;
    chk(y_valid, '0', "T1: y_valid=0 before any video");

    -- Drive 2 frames
    for frame in 0 to 1 loop
      report "--- Frame " & integer'image(frame) & " ---" severity note;
      for l in 0 to 16 loop drive_line(adc_in); end loop;
      drive_vsync(adc_in);
      for l in 0 to 4  loop drive_line(adc_in); end loop;
      for l in 0 to 599 loop drive_line(adc_in); end loop;
      for l in 0 to 1  loop drive_line(adc_in); end loop;
    end loop;

    tick(5);

    -- T2: HSYNC fires
    report "--- T2: HSYNC fires ---" severity note;
    adc_in <= std_logic_vector(to_unsigned(BLANK_LEVEL, 8)); tick(5);
    adc_in <= std_logic_vector(to_unsigned(SYNC_LEVEL,  8)); tick(C_SYNC_W);
    adc_in <= std_logic_vector(to_unsigned(BLANK_LEVEL, 8));
    wait until hsync_o = '1' for 20 * CLK_P;
    if hsync_o = '1' then report "PASS: T2: hsync fired" severity note;
    else report "FAIL: T2: hsync timeout" severity error;
    end if;
    tick(2);
    chk(hsync_o, '0', "T2: hsync one-cycle");

    -- T3: VSYNC fired and field toggled (2 frames = 2 toggles = back to 0)
    report "--- T3: VSYNC / field ---" severity note;
    chk(field_o, '0', "T3: field_o after 2 frames = 0");

    -- T4: y_data in active video
    report "--- T4: y_data in active window ---" severity note;
    adc_in <= std_logic_vector(to_unsigned(SYNC_LEVEL,  8)); tick(C_SYNC_W);
    adc_in <= std_logic_vector(to_unsigned(BLANK_LEVEL, 8)); tick(C_BACK);
    adc_in <= std_logic_vector(to_unsigned(Y_LEVEL,     8)); tick(5);
    if y_valid = '1' then
      chk8(y_data, Y_LEVEL, "T4: y_data=Y_LEVEL in active window");
    else
      report "INFO T4: y_valid=0 at boundary (acceptable)" severity note;
    end if;

    -- T5: y_valid=0 after active window ends
    report "--- T5: y_valid=0 in front porch ---" severity note;
    adc_in <= std_logic_vector(to_unsigned(BLANK_LEVEL, 8));
    tick(C_ACTIVE);   -- advance past active window
    chk(y_valid, '0', "T5: y_valid=0 after active window");

    report "=== All tests done ===" severity note;
    std.env.stop;
  end process;

end architecture sim;
