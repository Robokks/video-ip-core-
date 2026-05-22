# PAL B&W Video IP Core -- Timing Constraints
# Target: Xilinx 7-series / UltraScale (update PACKAGE_PIN for your board)
# Clock: 10 MHz pixel clock (100 ns period)

# --- Primary clock ---
# Replace [get_ports clk] with your actual clock net if it is an internal signal.
create_clock -period 100.000 -name clk_10mhz [get_ports clk]

set_clock_uncertainty 0.500 [get_clocks clk_10mhz]

# --- Output delays for 4-bit DAC bus ---
# Assumes external DAC (R-2R ladder / TLC7524) with:
#   - PCB trace delay:       ~2 ns
#   - DAC setup time:         5 ns  (conservative for passive R-2R)
#   - DAC hold requirement:   0 ns
set_output_delay -clock clk_10mhz -max  5.000 [get_ports {dac_out[*]}]
set_output_delay -clock clk_10mhz -min -2.000 [get_ports {dac_out[*]}]

# Optional: relax output delay on debug sync outputs (not timing-critical)
set_output_delay -clock clk_10mhz -max 10.000 [get_ports {hsync_o vsync_o active_o}]
set_output_delay -clock clk_10mhz -min  0.000 [get_ports {hsync_o vsync_o active_o}]

# --- Reset is asynchronous to clock domain (e.g. button) ---
set_false_path -from [get_ports rst]

# --- BRAM clock (pass-through, same net as clk) ---
# bram_clk is driven by the same clock source; no separate constraint needed.

# -----------------------------------------------------------------------
# Pin assignments -- EDIT FOR YOUR BOARD
# The example below uses Arty A7-35T (xc7a35ticsg324-1L).
# Uncomment and update pin numbers before running implementation.
# -----------------------------------------------------------------------

## 10 MHz clock input (example: external oscillator on Pmod or dedicated clock pin)
# set_property PACKAGE_PIN E3     [get_ports clk]
# set_property IOSTANDARD LVCMOS33 [get_ports clk]

## 4-bit DAC output (connect to Pmod or GPIO header)
# set_property PACKAGE_PIN G13    [get_ports {dac_out[3]}]   ; # MSB (2^3 * V_ref/R)
# set_property PACKAGE_PIN B11    [get_ports {dac_out[2]}]
# set_property PACKAGE_PIN A11    [get_ports {dac_out[1]}]
# set_property PACKAGE_PIN D12    [get_ports {dac_out[0]}]   ; # LSB
# set_property IOSTANDARD LVCMOS33 [get_ports {dac_out[*]}]

## Debug sync outputs
# set_property PACKAGE_PIN D13    [get_ports hsync_o]
# set_property PACKAGE_PIN B18    [get_ports vsync_o]
# set_property PACKAGE_PIN A18    [get_ports active_o]
# set_property IOSTANDARD LVCMOS33 [get_ports {hsync_o vsync_o active_o}]

## Active-high reset (e.g. push button)
# set_property PACKAGE_PIN C2     [get_ports rst]
# set_property IOSTANDARD LVCMOS33 [get_ports rst]
