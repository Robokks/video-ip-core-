# PAL B&W Video IP Core (Xilinx Vivado)

A family of PAL composite black-and-white video cores targeting the
**NI cRIO-9056** (Xilinx Artix-7) with a 4-bit DAC on an **NI-9401** DIO module.
Three top-level variants are provided:

| Variant | Top entity | BRAM? | Use case |
|---|---|---|---|
| BRAM pixel source | `pal_bw_top` | ✓ | Live image from LabVIEW FPGA memory |
| Stripe pattern | `pal_bw_stripe_top` | ✗ | DAC wiring bring-up, runtime width/direction |
| Multiburst pattern | `pal_bw_multiburst_top` | ✗ | DAC linearity / bandwidth test card |

All three share the same three sub-modules (`pal_timing`, `pal_sync_gen`,
`pal_dac_mux`) and accept a `CLK_MHZ` generic to select the input clock
frequency (10 / 20 / 30 / 40 MHz); the internal clock-enable divider keeps
the effective pixel rate at exactly **10 MHz** in all cases.

## Specifications

| Parameter | Value |
|---|---|
| Standard | PAL (625 lines, 25 fps) |
| Colour | Black & white only |
| Input clock | **10 / 20 / 30 / 40 MHz** (set `CLK_MHZ` generic) |
| Effective pixel rate | **10 MHz** (internal CE divider) |
| DAC output | **4-bit** (16 levels, 0–15) |
| Pixel input (`pal_bw_top`) | 1-bit BRAM (Boolean: 1=white, 0=black) |
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
  pal_timing.vhd             H/V counters (640 × 625) + CLK_MHZ CE divider
  pal_sync_gen.vhd           Decode counters → hsync / vsync / active / blank
  pal_dac_mux.vhd            Select 4-bit DAC level from region + pixel data
  pal_bw_top.vhd             Top-level: BRAM interface + sub-module wiring
  pal_bw_stripe_top.vhd      Stripe pattern generator (no BRAM, runtime width/dir)
  pal_bw_multiburst_top.vhd  Multiburst test pattern (no BRAM, 8 zones, fixed)
sim/
  tb_pal_bw_top.vhd              Testbench: 10 lines, all-white BRAM, self-checking
  tb_pal_bw_stripe_top.vhd       Testbench: vertical + horizontal stripe phases
  tb_pal_bw_multiburst_top.vhd   Testbench: zones 0-2 pixel-exact verification
constraints/
  pal_bw.xdc          Timing constraints (10 MHz clock, DAC output delays)
tcl/
  create_project.tcl  Vivado batch project creation (all sources included)
clip/
  pal_bw_clip.xml              LabVIEW FPGA CLIP: BRAM pixel source
  pal_bw_stripe_clip.xml       LabVIEW FPGA CLIP: stripe pattern (runtime controls)
  pal_bw_multiburst_clip.xml   LabVIEW FPGA CLIP: multiburst test pattern
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

All timing and level values are exposed as generics on every top-level entity.
`pal_bw_stripe_top` and `pal_bw_multiburst_top` share the same timing/level
generics as `pal_bw_top` plus `CLK_MHZ`.

| Generic | Default | Applies to | Description |
|---|---|---|---|
| `H_FRONT` | 16 | all | Front porch clocks |
| `H_SYNC_W` | 47 | all | H-sync pulse width clocks |
| `H_BACK` | 57 | all | Back porch clocks |
| `H_ACTIVE` | 520 | all | Active pixel clocks |
| `H_TOTAL` | 640 | all | Total clocks per line |
| `V_SYNC_L` | 5 | all | Vsync lines |
| `V_BACK_L` | 20 | all | V back porch lines |
| `V_ACTIVE_L` | 576 | all | Active picture lines |
| `V_TOTAL` | 625 | all | Total lines per frame |
| `LEVEL_SYNC` | `"0000"` | all | DAC value for sync tip |
| `LEVEL_BLANK` | `"0100"` | all | DAC value for blanking/black |
| `LEVEL_WHITE` | `"1111"` | all | DAC value for white pixel |
| `CLK_MHZ` | 10 | all | Input clock MHz: 10 / 20 / 30 / 40 |
| `NUM_ZONES` | 8 | multiburst | Number of frequency zones |
| `ZONE_W` | 65 | multiburst | Pixels per zone (`H_ACTIVE / NUM_ZONES`) |

## Clock Selection (CLK_MHZ Generic)

The `CLK_MHZ` generic selects the input clock frequency. An internal
clock-enable (`ce`) divides it back to a **10 MHz effective pixel rate**:

| `CLK_MHZ` | Divider | Typical source (cRIO-9056) |
|---|---|---|
| 10 | ÷1 | 10 MHz base clock |
| 20 | ÷2 | 20 MHz base clock |
| 30 | ÷3 | External / PLL |
| 40 | ÷4 | **40 MHz primary clock (recommended)** |

For LabVIEW FPGA / cRIO-9056 use `CLK_MHZ => 40` inside a **40 MHz
Single-Cycle Timed Loop**. All three CLIP XML files are configured for
40 MHz by default.

## Stripe Pattern Generator (`pal_bw_stripe_top`)

No BRAM required. Generates alternating black/white stripes whose width and
orientation are controlled at runtime from LabVIEW:

| Port | Type | Direction | Description |
|---|---|---|---|
| `stripe_width` | `std_logic_vector(15:0)` | in | Pixels per stripe (vertical) or lines per stripe (horizontal) |
| `stripe_dir` | `std_logic` | in | `'0'` = vertical stripes, `'1'` = horizontal stripes |

Both inputs are sampled every frame so LabVIEW can change them live.
Changes take effect at the start of the next frame.

**Example (40 MHz SCTL):**
```
stripe_width := 40;   -- 40-pixel vertical stripes
stripe_dir   := FALSE;
```

## Multiburst Test Pattern Generator (`pal_bw_multiburst_top`)

No BRAM, no runtime inputs. Generates a standard video resolution test card:
520 active pixels split into **8 zones of 65 pixels**, stripe width doubling
per zone:

| Zone | Pixels | Stripe width | Frequency |
|---|---|---|---|
| 0 | 0–64 | 1 px | 5 MHz (finest) |
| 1 | 65–129 | 2 px | 2.5 MHz |
| 2 | 130–194 | 4 px | 1.25 MHz |
| 3 | 195–259 | 8 px | 625 kHz |
| 4 | 260–324 | 16 px | 312 kHz |
| 5 | 325–389 | 32 px | 156 kHz |
| 6 | 390–454 | 64 px | 78 kHz |
| 7 | 455–519 | 128 px | solid black (zone narrower than stripe) |

Each zone resets to black at its left boundary. Pattern is identical on
every active line. Use to verify DAC linearity and measure the analogue
bandwidth of the output path.
