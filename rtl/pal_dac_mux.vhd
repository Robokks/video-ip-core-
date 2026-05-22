library ieee;
use ieee.std_logic_1164.all;

-- Combinational 4-bit DAC level selector.
-- Priority: vsync > hsync > active pixel > blanking
--
-- PAL B&W composite levels (1 Vpp into 75 ohm):
--   Sync tip  = 0.00 V  -> 4'b0000 (0)
--   Black/blank = 0.27 V -> 4'b0100 (4)
--   White     = 1.00 V  -> 4'b1111 (15)
entity pal_dac_mux is
  generic (
    LEVEL_SYNC  : std_logic_vector(3 downto 0) := "0000";  -- 0  sync tip
    LEVEL_BLANK : std_logic_vector(3 downto 0) := "0100";  -- 4  blanking / black
    LEVEL_WHITE : std_logic_vector(3 downto 0) := "1111"   -- 15 white peak
  );
  port (
    vsync    : in  std_logic;  -- '1' = broad vsync line
    hsync    : in  std_logic;  -- '1' = H-sync pulse
    active   : in  std_logic;  -- '1' = active pixel window
    pixel_in : in  std_logic;  -- BRAM pixel: '1'=white, '0'=black
    dac_out  : out std_logic_vector(3 downto 0)
  );
end entity pal_dac_mux;

architecture rtl of pal_dac_mux is
begin

  dac_out <= LEVEL_SYNC  when vsync = '1'              else
             LEVEL_SYNC  when hsync = '1'              else
             LEVEL_WHITE when active = '1' and pixel_in = '1' else
             LEVEL_BLANK;  -- blanking or black pixel

end architecture rtl;
