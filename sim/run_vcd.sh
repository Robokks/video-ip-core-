#!/bin/bash
# Generate VCD waveform for GTKWave from pal_tv_bram_lite_v2
# Usage:  bash sim/run_vcd.sh
# Output: sim/pal_lite_v2.vcd  (open with: gtkwave sim/pal_lite_v2.vcd sim/pal_lite_v2.gtkw)

set -e
cd "$(dirname "$0")/.."

WORK=sim/work_vcd
mkdir -p "$WORK"

echo "[1/4] Analysing VHDL sources..."
ghdl -a --std=08 --workdir="$WORK" \
  tv/pal_timing.vhd \
  tv/opt2_interlaced/pal_csync_il.vhd \
  tv/bram/pal_tv_bram_lite_v2.vhd \
  sim/tb_lite_v2_vcd.vhd

echo "[2/4] Elaborating testbench..."
ghdl -e --std=08 --workdir="$WORK" tb_lite_v2_vcd

echo "[3/4] Running simulation (2 PAL frames)..."
ghdl -r --std=08 --workdir="$WORK" tb_lite_v2_vcd \
  --vcd=sim/pal_lite_v2.vcd \
  --stop-time=80100us

echo "[4/4] Done.  VCD saved to sim/pal_lite_v2.vcd"
echo "       Open with:  gtkwave sim/pal_lite_v2.vcd sim/pal_lite_v2.gtkw"
