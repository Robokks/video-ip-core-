# PAL B&W Video IP Core -- Timing Constraints
# Target: NI cRIO-9056 -- Xilinx Artix-7 XC7A75T
# Clock: 10 MHz pixel clock (100 ns period)
# NOTE: When used as a LabVIEW CLIP, pin assignments are managed by
#       LabVIEW FPGA / NI-RIO driver -- only timing constraints are needed here.

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
# cRIO-9056 + NI-9401 module connection
# -----------------------------------------------------------------------
# Pin assignments are NOT set here for LabVIEW CLIP usage.
# LabVIEW FPGA wires dac_out[3:0] to NI-9401 DIO0-DIO3 in the block diagram.
#
# NI-9401 DIO mapping (configure lower nibble as OUTPUT in LabVIEW):
#   dac_out[3]  ->  NI-9401 DIO0   (MSB, weight 8)
#   dac_out[2]  ->  NI-9401 DIO1   (weight 4)
#   dac_out[1]  ->  NI-9401 DIO2   (weight 2)
#   dac_out[0]  ->  NI-9401 DIO3   (LSB, weight 1)
#
# R-2R DAC circuit (5 V output from NI-9401):
#   Use R = 270 ohm, 2R = 560 ohm (standard E24 values).
#   Output into 75 ohm coax gives ~0-1 V composite video.
#   See clip/pal_bw_clip.xml and README for full wiring diagram.
# -----------------------------------------------------------------------
