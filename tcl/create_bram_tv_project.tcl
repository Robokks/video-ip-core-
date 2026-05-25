# create_bram_tv_project.tcl -- Vivado batch project for PAL/TV BRAM IP core
#
# Usage (from repo root):
#   vivado -mode batch -source tcl/create_bram_tv_project.tcl
#
# Top-level entity : pal_tv_bram_top  (supports PROGRESSIVE generic)
# Dependencies     :
#   tv/pal_timing.vhd
#   tv/opt2_interlaced/pal_csync_il.vhd
#   tv/opt3_progressive/pal_csync_prog.vhd   ← required even when PROGRESSIVE=false
#   tv/bram/pal_tv_bram_top.vhd
#
# Optional dual-standard top (PAL + NTSC runtime select):
#   tv/bram/video_bram_top.vhd
#
# Simulation testbench:
#   tv/bram/tb_pal_tv_bram_top.vhd

set project_name "pal_tv_bram"
set project_dir  "./vivado_bram_project"
# Update -part for your device (Artix-7 35T shown as default)
set part         "xc7a35ticsg324-1L"
set top_src      "pal_tv_bram_top"
set top_sim      "tb_pal_tv_bram_top"

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
# NOTE: pal_csync_prog.vhd MUST be included even when PROGRESSIVE=false.
# pal_tv_bram_top uses a conditional generate block that references BOTH
# pal_csync_il and pal_csync_prog; Vivado elaborates both branches.
add_files -fileset sources_1 [list \
  [file normalize "$repo_root/tv/pal_timing.vhd"]                       \
  [file normalize "$repo_root/tv/opt2_interlaced/pal_csync_il.vhd"]     \
  [file normalize "$repo_root/tv/opt3_progressive/pal_csync_prog.vhd"]  \
  [file normalize "$repo_root/tv/bram/pal_tv_bram_top.vhd"]             \
]

# --- Optional: dual PAL+NTSC top (uncomment if needed) ---
# add_files -fileset sources_1 \
#   [file normalize "$repo_root/tv/bram/video_bram_top.vhd"]

# --- Simulation sources ---
add_files -fileset sim_1 \
  [file normalize "$repo_root/tv/bram/tb_pal_tv_bram_top.vhd"]

# --- Set top-level entities ---
set_property top $top_src [get_filesets sources_1]
set_property top $top_sim [get_filesets sim_1]

# --- Update compile order (resolves entity dependencies) ---
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts ""
puts "Project created successfully."
puts ""
puts "Files added to sources_1:"
puts "  tv/pal_timing.vhd"
puts "  tv/opt2_interlaced/pal_csync_il.vhd"
puts "  tv/opt3_progressive/pal_csync_prog.vhd"
puts "  tv/bram/pal_tv_bram_top.vhd"
puts ""
puts "PROGRESSIVE generic (default false = interlaced):"
puts "  false : PAL 625/50 interlaced  -- uses pal_csync_il"
puts "  true  : Progressive 576p-style -- uses pal_csync_prog"
puts ""
puts "Open in Vivado GUI with:"
puts "  vivado $project_dir/$project_name.xpr"
puts ""
puts "Or run simulation in batch mode:"
puts "  open_project $project_dir/$project_name.xpr"
puts "  launch_simulation"
