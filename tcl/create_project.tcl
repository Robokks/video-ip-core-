# create_project.tcl -- Vivado batch project creation for PAL B&W Video IP Core
#
# Usage (from repo root):
#   vivado -mode batch -source tcl/create_project.tcl
#
# This script creates a Vivado project, adds all RTL, sim, and constraint files,
# sets the correct top-level entities, and updates compile order.
# Synthesis and implementation are NOT launched automatically; open the .xpr
# in the GUI or add launch_runs commands as needed.

set project_name "pal_bw_video"
set project_dir  "./vivado_project"
# Update -part for your device (Artix-7 35T shown as default)
set part         "xc7a35ticsg324-1L"
set top_src      "pal_bw_top"
set top_sim      "tb_pal_bw_top"

# Resolve paths relative to script location so the project works from any CWD
set script_dir [file dirname [file normalize [info script]]]
set repo_root  [file normalize "$script_dir/.."]

puts "Repository root : $repo_root"
puts "Creating project: $project_dir/$project_name.xpr"
puts "Device part     : $part"

# Create project
create_project $project_name $project_dir -part $part -force

# Target / simulator language
set_property target_language    VHDL [current_project]
set_property simulator_language VHDL [current_project]

# --- RTL sources ---
add_files -fileset sources_1 [list \
  [file normalize "$repo_root/rtl/pal_timing.vhd"]   \
  [file normalize "$repo_root/rtl/pal_sync_gen.vhd"] \
  [file normalize "$repo_root/rtl/pal_dac_mux.vhd"]  \
  [file normalize "$repo_root/rtl/pal_bw_top.vhd"]   \
]

# --- Constraints ---
add_files -fileset constrs_1 \
  [file normalize "$repo_root/constraints/pal_bw.xdc"]

# --- Simulation sources ---
add_files -fileset sim_1 \
  [file normalize "$repo_root/sim/tb_pal_bw_top.vhd"]

# --- Set top-level entities ---
set_property top $top_src [get_filesets sources_1]
set_property top $top_sim [get_filesets sim_1]

# --- Update compile order (resolves entity dependencies) ---
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts ""
puts "Project created successfully."
puts "Open in Vivado GUI with:"
puts "  vivado $project_dir/$project_name.xpr"
puts ""
puts "Or run simulation in batch:"
puts "  vivado -mode batch -source tcl/create_project.tcl"
puts "  # then: launch_simulation"
