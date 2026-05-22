# PAL B&W Video IP Core (Xilinx Vivado)

Generates a PAL composite black-and-white video signal from a 1-bit-per-pixel BRAM.

## Specifications

| Parameter | Value |
|---|---|
| Standard | PAL (625 lines, 25 fps) |
| Colour | Black & white only |
| Clock | **10 MHz** (100 ns period) |
| DAC output | **4-bit** (16 levels, 0–15) |
| Pixel input | 1-bit BRAM (Boolean: 1=white, 0=black) |
| Active resolution | 520 × 576 pixels |
| BRAM size needed | 520 × 576 = 299,520 bits ≈ 37 KB |

## PAL Timing (10 MHz)

```
  ←────────────────── 640 clocks (64 µs) ──────────────────→
  ┌──────┬───────────┬──────────────┬────────────────────────┐
  │Front │  H-sync   │  Back porch  │    Active pixels        │
  │ 16   │    47     │      57      │          520            │
  └──────┴───────────┴──────────────┴────────────────────────┘

Frame: 625 lines total
  Lines  0–4   : broad vsync (5 lines)
  Lines  5–24  : V back porch (20 lines)
  Lines 25–600 : active picture (576 lines)
  Lines 601–624: V front porch (24 lines)
```

## 4-bit DAC Levels

| Region | Value | Voltage (1 Vpp) |
|---|---|---|
| Sync tip | 0 (`0000`) | 0.00 V |
| Blank / black | 4 (`0100`) | 0.27 V |
| White | 15 (`1111`) | 1.00 V |

## Which DAC to Use?

**Recommended — R-2R resistor ladder (no extra IC):**

```
dac_out[3] ──┬── 75 Ω ──┬── 75 Ω ──┬── 75 Ω ──┬──── video out ──┬── 75 Ω load
             │           │           │           │                  │
dac_out[2] ──┤ 150 Ω    │ 150 Ω    │ 150 Ω    │                 GND
dac_out[1] ──┤           │           │           │
dac_out[0] ──┘ ...       GND         GND         GND
```

Use R = 75 Ω, 2R = 150 Ω (1% metal film). The output drives a 75 Ω
coaxial composite video line (standard BNC or RCA connector).

**IC alternative:** TLC7524C or AD7524 (8-bit parallel DAC, use 4 MSBs).
Connect dac_out to D7–D4, tie D3–D0 low. Add a unity-gain buffer op-amp.

## File Structure

```
rtl/
  pal_timing.vhd      H/V counters (640 × 625)
  pal_sync_gen.vhd    Decode counters → hsync / vsync / active / blank
  pal_dac_mux.vhd     Select 4-bit DAC level from region + pixel data
  pal_bw_top.vhd      Top-level: BRAM interface + sub-module wiring
sim/
  tb_pal_bw_top.vhd   Self-checking testbench (10 lines, all-white BRAM)
constraints/
  pal_bw.xdc          Timing constraints + commented pin assignments
tcl/
  create_project.tcl  Vivado batch project creation
```

## Quick Start

### 1. Create the Vivado project

```bash
vivado -mode batch -source tcl/create_project.tcl
vivado vivado_project/pal_bw_video.xpr
```

Update the `-part` inside `create_project.tcl` for your FPGA device.

### 2. Connect your BRAM

The IP core exposes these BRAM signals:

| Port | Direction | Description |
|---|---|---|
| `bram_clk` | out | Clock for BRAM port (= `clk`) |
| `bram_en` | out | Read enable |
| `bram_we` | out | Write enable (always `'0'`) |
| `bram_addr[18:0]` | out | Row-major pixel address |
| `bram_din` | in | 1-bit pixel data from BRAM |

Connect these to Port A of a Xilinx Block Memory Generator IP configured as:
- Simple Dual Port RAM or Single Port ROM
- Width: 1 bit, Depth: 299520 (or next power-of-2: 524288)
- Latency: 1 clock cycle (register output)

### 3. Update pin assignments

Edit the commented-out `set_property PACKAGE_PIN` lines in
`constraints/pal_bw.xdc` for your board.

### 4. Run simulation

In the Vivado GUI: Flow → Run Simulation → Run Behavioral Simulation.
Or in batch mode after creating the project, add to the TCL:
```tcl
launch_simulation
run all
```

## BRAM Address Map

```
address = line_number * 520 + pixel_x
```
- `line_number` = 0..575 (top to bottom)
- `pixel_x`     = 0..519 (left to right)
- `address` range: 0..299519 (fits in 19 bits)

## Generics

All timing and level values are exposed as generics on `pal_bw_top`:

| Generic | Default | Description |
|---|---|---|
| `H_FRONT` | 16 | Front porch clocks |
| `H_SYNC_W` | 47 | H-sync width clocks |
| `H_BACK` | 57 | Back porch clocks |
| `H_ACTIVE` | 520 | Active pixel clocks |
| `H_TOTAL` | 640 | Total clocks per line |
| `V_SYNC_L` | 5 | Vsync lines |
| `V_BACK_L` | 20 | V back porch lines |
| `V_ACTIVE_L` | 576 | Active picture lines |
| `V_TOTAL` | 625 | Total lines per frame |
| `LEVEL_SYNC` | `"0000"` | DAC value for sync tip |
| `LEVEL_BLANK` | `"0100"` | DAC value for blanking/black |
| `LEVEL_WHITE` | `"1111"` | DAC value for white pixel |
