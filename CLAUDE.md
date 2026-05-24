# Claude Code — Project Conventions

## Standing Instructions

### Documentation Sync Rule ⚠️ ALWAYS FOLLOW
> **When any code change or feature addition is made, the relevant project
> documents must also be updated in the same commit.**

Specifically:
- **VHDL source change** → re-run `python3 tools/gen_code_walkthrough.py`
  and commit the new `docs/CODE_WALKTHROUGH.docx`
- **New feature / port added** → update:
  - `docs/ICD_Interface_Control_Document.docx` (via `gen_project_docs.py`)
  - `docs/SDD_Software_Design_Description.docx` (via `gen_project_docs.py`)
  - `docs/SRS_Software_Requirements_Specification.docx` (new requirements)
  - `docs/TM_Traceability_Matrix.docx` (new FR/NFR row)
- **Bug fixed** → add entry to `docs/BR_Bug_Report.docx`
- **Any change** → run `python3 tools/gen_change_log.py` to refresh
  `docs/CL_Change_Log.docx`

### Quick regeneration commands
```bash
# Regenerate ALL 11 formal documents
python3 tools/gen_project_docs.py

# Regenerate flowcharts (run before gen_project_docs if diagrams changed)
python3 tools/gen_flowcharts.py

# Regenerate code walkthrough document
python3 tools/gen_code_walkthrough.py

# Regenerate change log
python3 tools/gen_change_log.py

# Regenerate config summary
python3 tools/gen_config_summary.py
```

---

## Branch
All development: `claude/xilinx-pal-video-ip-RIDhJ`

## Project Summary
PAL/NTSC 625/525-line interlaced B&W video IP core.
- 4-bit R-2R DAC output (sync=0x0, blank=0x4, white=0xF)
- 10 selectable patterns (sel 0–9)
- BRAM frame-buffer with tear-free double-buffering
- Bouncing ball, crosshatch, centre-cross overlays
- Supports 10/20/30/40 MHz board clocks (CLK_MHZ generic)
- PAL-only: `pal_tv_bram_top.vhd`
- PAL+NTSC runtime: `video_bram_top.vhd`

## Document Folder
`docs/` contains 12 documents:

| File | Description |
|------|-------------|
| `CODE_WALKTHROUGH.docx` | Line-by-line VHDL explanation |
| `ICD_Interface_Control_Document.docx` | All ports, signal levels, timing |
| `SRS_Software_Requirements_Specification.docx` | FR/NFR requirements |
| `SDD_Software_Design_Description.docx` | Architecture, modules, state machines |
| `SDP_Software_Development_Plan.docx` | Dev phases, tools, strategy |
| `CM_Configuration_Management_Plan.docx` | Branch strategy, change control |
| `STP_Software_Test_Plan.docx` | Testbench descriptions, pass criteria |
| `STR_Software_Test_Report.docx` | Actual test results |
| `VC_Version_Control.docx` | Git workflow, commit history |
| `TM_Traceability_Matrix.docx` | Requirement → design → test trace |
| `BR_Bug_Report.docx` | Bug log (BUG-001..003 fixed) |
| `CL_Change_Log.docx` | Project change history |
