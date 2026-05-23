# PAL B&W Video IP — TV-Compatible Variants

Three self-contained variants addressing the TV compatibility issues of the
base 25 Hz progressive design in `rtl/`.

---

## Quick Comparison

| | opt1_crt50 | opt2_interlaced | opt3_prog25 |
|---|---|---|---|
| **Frame rate** | 50 Hz progressive | 50 Hz field / 25 Hz frame | 25 Hz progressive |
| **Lines/frame** | 312 (50.08 Hz) | 625 (true interlaced) | 625 (25 Hz) |
| **Active lines** | 288 | 576 (288/field) | 576 |
| **Vsync type** | 3 broad lines | Eq + Broad + Post-eq (PAL std) | 5 broad lines (simplified) |
| **CRT TV** | ✅ Locks reliably | ✅ Standard PAL | ⚠️ Usually no (25 Hz) |
| **Modern LCD/plasma** | ✅ Usually accepts | ✅ Standard PAL | ⚠️ Some models only |
| **Complexity** | Low | High | Low |

**Recommendation:** use **opt1_crt50** for CRT monitors, **opt2_interlaced** for
any TV with a composite input connector.

---

## File Structure

```
tv/
  pal_timing.vhd          -- Shared H/V counter (CLK_MHZ generic: 10/20/30/40)
  pal_sync_gen.vhd        -- Shared sync region decoder (used by opt1 & opt3)

  opt1_crt50/
    pal_tv_crt50_top.vhd  -- 50 Hz non-interlaced top (V_TOTAL=312)
    tb_pal_tv_crt50_top.vhd

  opt2_interlaced/
    pal_csync_il.vhd           -- Interlaced composite sync (combinational)
    pal_tv_interlaced_top.vhd  -- Full PAL interlaced top (V_TOTAL=625)
    tb_pal_tv_interlaced_top.vhd

  opt3_prog25/
    pal_tv_prog25_top.vhd  -- 25 Hz progressive reference (same as rtl/)
    tb_pal_tv_prog25_top.vhd
```

---

## GHDL Simulation

Each variant compiles independently.  Run from the variant's folder:

### opt1_crt50
```bash
cd tv/opt1_crt50
mkdir -p work
ghdl -a --std=08 --workdir=work ../pal_timing.vhd ../pal_sync_gen.vhd \
     pal_tv_crt50_top.vhd tb_pal_tv_crt50_top.vhd
ghdl -r --std=08 --workdir=work tb_pal_tv_crt50_top --assert-level=error
```

### opt2_interlaced
```bash
cd tv/opt2_interlaced
mkdir -p work
ghdl -a --std=08 --workdir=work ../pal_timing.vhd \
     pal_csync_il.vhd pal_tv_interlaced_top.vhd tb_pal_tv_interlaced_top.vhd
ghdl -r --std=08 --workdir=work tb_pal_tv_interlaced_top --assert-level=error
```

### opt3_prog25
```bash
cd tv/opt3_prog25
mkdir -p work
ghdl -a --std=08 --workdir=work ../pal_timing.vhd ../pal_sync_gen.vhd \
     pal_tv_prog25_top.vhd tb_pal_tv_prog25_top.vhd
ghdl -r --std=08 --workdir=work tb_pal_tv_prog25_top --assert-level=error
```

---

## Timing Details

### PAL H timing (all three variants, 10 MHz pixel clock)
| Region | Clocks | Time |
|---|---|---|
| H front porch | 16 | 1.6 µs |
| H sync (low) | 47 | 4.7 µs |
| H back porch | 57 | 5.7 µs |
| H active | 520 | 52.0 µs |
| **H total** | **640** | **64.0 µs → 15 625 Hz** |

### V timing per variant
| | opt1_crt50 | opt2_interlaced | opt3_prog25 |
|---|---|---|---|
| V sync lines | 3 | 7.5 (eq+broad+eq) | 5 |
| V back porch | 18 | 16 (per field) | 20 |
| V active | **288** | **288/field** | **576** |
| V front porch | 3 | 0.5 (per field) | 24 |
| **V total** | **312** | **625** | **625** |
| **Field rate** | **50.08 Hz** | **50 Hz** | **25 Hz** |

### opt2_interlaced vsync sequence
Each field (both F1 and F2) generates exactly 15 half-lines of sync:

| Half-lines | Duration | Type | Waveform |
|---|---|---|---|
| 5 | 5 × 32 µs | Pre-equalization | LOW 2.3 µs, HIGH 29.7 µs |
| 5 | 5 × 32 µs | Broad sync | LOW 27.3 µs, HIGH 4.7 µs |
| 5 | 5 × 32 µs | Post-equalization | LOW 2.3 µs, HIGH 29.7 µs |

Field 2 vsync starts exactly 0.5 line (32 µs) after field 1 ends — the
standard half-line offset that makes true interlacing possible.

---

## Selectable Patterns (sel port, all variants)

| sel | Pattern | Description |
|---|---|---|
| 0x00 | Vertical bars | 8 zones across 520 px: STRIPE/WHITE/STRIPE/WHITE/BLACK/STRIPE/WHITE/STRIPE |
| 0x01 | Horizontal bars | Same 8 zones repeated down the active lines |
| 0x02 | Horizontal gradient | 10 grey steps left→right (black→white, 52 px/zone) |
| 0x03 | Vertical gradient | 10 grey steps top→bottom |

All patterns are generated with incremental counters — no runtime division or
multiplication, so they close timing inside a single 40 MHz SCTL cycle on
the NI cRIO-9056 (Artix-7 XC7A75T).

---

## DAC Levels (4-bit R-2R output)

| Signal | 4-bit | ~Voltage (1 Vpp) |
|---|---|---|
| Sync tip | `0000` | 0.00 V |
| Blank / black | `0100` | 0.267 V |
| White | `1111` | 1.000 V |

R-2R ladder: R = 270 Ω, 2R = 560 Ω (for 5 V NI-9401 outputs into 75 Ω load).
Outputs: DIO0 (LSB) … DIO3 (MSB).

---

## LabVIEW FPGA Integration

Load files for the chosen variant in Vivado / LabVIEW FPGA in dependency order:

**opt1_crt50:**  `pal_timing.vhd` → `pal_sync_gen.vhd` → `pal_tv_crt50_top.vhd`

**opt2_interlaced:**  `pal_timing.vhd` → `pal_csync_il.vhd` → `pal_tv_interlaced_top.vhd`

**opt3_prog25:**  `pal_timing.vhd` → `pal_sync_gen.vhd` → `pal_tv_prog25_top.vhd`

Set the top-level entity to the chosen `*_top` entity.
Wire ports: `clk` → 40 MHz SCTL clock, `rst` → FALSE (or FPGA reset),
`sel[7:0]` → U8 constant/control, `dac_out[3:0]` → DIO0–DIO3.
