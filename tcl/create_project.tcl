# create_project.tcl -- Vivado batch project creation for PAL B&W Video IP Core
#
# Usage (from repo root):
#   vivado -mode batch -source tcl/create_project.tcl
#
# Creates a Vivado project with all RTL, sim, and constraint sources.
# All three top-level variants are added to sources_1; the default synthesis
# top is pal_bw_top (BRAM pixel source).  Change set_top below to select
# pal_bw_stripe_top or pal_bw_multiburst_top if preferred.
#
# Simulation top defaults to tb_pal_bw_top.  Change set_top_sim to switch
# to tb_pal_bw_stripe_top or tb_pal_bw_multiburst_top.
#
# Synthesis and implementation are NOT launched automatically; open the .xpr
# in the Vivado GUI or add launch_runs commands as needed.

set project_name "pal_bw_video"
set project_dir  "./vivado_project"
# Update -part for your device:
#   NI cRIO-9056 = Artix-7 75T  -> xc7a75tcsg324-1L
#   Artix-7 35T  -> xc7a35ticsg324-1L  (default, matches free WebPACK licence)
set part         "xc7a35ticsg324-1L"

# Select which top-level to synthesise (all three are in the project)
# Options: pal_bw_top | pal_bw_stripe_top | pal_bw_multiburst_top
set top_src      "pal_bw_top"

# Select which testbench to simulate
# Options: tb_pal_bw_top | tb_pal_bw_stripe_top | tb_pal_bw_multiburst_top
set top_sim      "tb_pal_bw_top"

# Resolve paths relative to script location so the project works from any CWD
set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize "$script_dir/.."]

puts "Repository root : $repo_root"
puts "Creating project: $project_dir/$project_name.xpr"
puts "Device part     : $part"
puts "Synthesis top   : $top_src"
puts "Simulation top  : $top_sim"

# Create project
create_project $project_name $project_dir -part $part -force

# Target / simulator language
set_property target_language    VHDL [current_project]
set_property simulator_language VHDL [current_project]

# ---------------------------------------------------------------------------
# RTL sources
# Sub-modules first (shared by all three top-levels), then top-levels.
# ---------------------------------------------------------------------------
add_files -fileset sources_1 [list \
  [file normalize "$repo_root/rtl/pal_timing.vhd"]            \
  [file normalize "$repo_root/rtl/pal_sync_gen.vhd"]          \
  [file normalize "$repo_root/rtl/pal_dac_mux.vhd"]           \
  [file normalize "$repo_root/rtl/pal_bw_top.vhd"]            \
  [file normalize "$repo_root/rtl/pal_bw_stripe_top.vhd"]     \
  [file normalize "$repo_root/rtl/pal_bw_multiburst_top.vhd"] \
]

# ---------------------------------------------------------------------------
# Constraints
# ---------------------------------------------------------------------------
add_files -fileset constrs_1 \
  [file normalize "$repo_root/constraints/pal_bw.xdc"]

# ---------------------------------------------------------------------------
# Simulation sources (all three testbenches)
# ---------------------------------------------------------------------------
add_files -fileset sim_1 [list \
  [file normalize "$repo_root/sim/tb_pal_bw_top.vhd"]             \
  [file normalize "$repo_root/sim/tb_pal_bw_stripe_top.vhd"]      \
  [file normalize "$repo_root/sim/tb_pal_bw_multiburst_top.vhd"]  \
]

# ---------------------------------------------------------------------------
# Set top-level entities
# ---------------------------------------------------------------------------
set_property top $top_src [get_filesets sources_1]
set_property top $top_sim [get_filesets sim_1]

# ---------------------------------------------------------------------------
# Update compile order (resolves entity dependencies)
# ---------------------------------------------------------------------------
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts ""
puts "Project created successfully."
puts ""
puts "Open in Vivado GUI with:"
puts "  vivado $project_dir/$project_name.xpr"
puts ""
puts "To switch synthesis top (e.g. stripe pattern, no BRAM):"
puts "  set_property top pal_bw_stripe_top \[get_filesets sources_1\]"
puts "  set_property top tb_pal_bw_stripe_top \[get_filesets sim_1\]"
puts ""
puts "To switch synthesis top (multiburst test card, no BRAM):"
puts "  set_property top pal_bw_multiburst_top \[get_filesets sources_1\]"
puts "  set_property top tb_pal_bw_multiburst_top \[get_filesets sim_1\]"
puts ""
puts "To run simulation in batch after creating the project:"
puts "  launch_simulation"
puts "  run all"
