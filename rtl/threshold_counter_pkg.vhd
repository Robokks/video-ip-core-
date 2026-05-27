library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Package for threshold_counter array types
package threshold_counter_pkg is

  constant TC_NUM_CH : integer := 4;   -- number of channels

  -- 4-element array of 16-bit words (used for Q4.12 data and counters)
  type word16_array_t is array (0 to TC_NUM_CH - 1)
    of std_logic_vector(15 downto 0);

end package threshold_counter_pkg;
