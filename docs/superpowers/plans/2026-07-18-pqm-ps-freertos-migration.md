# PQM PS FreeRTOS Display Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a reproducible Zynq-7020 SoC project in which PL retains deterministic acquisition and power-quality measurement while FreeRTOS and LVGL on PS render the 800x480 LCD and process touch input.

**Architecture:** PS accesses coherent measurements through an AXI BRAM window, receives raw U/I frames through AXI DMA and HP1, and renders RGB565 double framebuffers read by AXI VDMA through HP0. A versioned legacy-display build option keeps the existing PL renderer available until the PS path passes hardware acceptance.

**Tech Stack:** Vivado/SDK 2018.3, XC7Z020-CLG400-2, Verilog-2001, Xilinx AXI DMA/VDMA/VTC/Video Out/BRAM Controller IP, FreeRTOS 10 Xilinx, LVGL v8.3.11, C11, XSim, MinGW GCC host tests.

---

## File Map

The migration adds these focused ownership units:

- `FPGA/scripts/create_pqm_soc_project.tcl`: creates a clean SoC Vivado project from repository sources.
- `FPGA/scripts/create_pqm_ps_bd.tcl`: creates the PS7, AXI, DMA, VDMA, video, BRAM, reset, clock, and interrupt block design.
- `FPGA/scripts/build_pqm_soc.tcl`: validates, synthesizes, implements, reports, writes the bitstream, and exports the HDF.
- `FPGA/rtl/PSInterface/pqm_axis_sample_stream.v`: loss-isolated 64-bit U/I sample stream with sequence and TLAST.
- `FPGA/rtl/PSInterface/pqm_shared_memory_bridge.v`: serializes coherent scalar and harmonic snapshots into dual-port BRAM.
- `FPGA/rtl/PSInterface/pqm_axis_rgb565_to_rgb888.v`: expands VDMA RGB565 AXI stream data to RGB888.
- `FPGA/rtl/PSInterface/pqm_touch_iobuf.v`: connects PS I2C/GPIO EMIO signals to the existing touch pins.
- `FPGA/rtl/pqm_legacy_core.v`: the former PL-only `main` logic, retained as the migration fallback.
- `FPGA/rtl/main.v`: the SoC top that connects the block-design wrapper, PL measurement core, and physical pins.
- `FPGA/sim/PSInterface/`: self-checking RTL tests for every new handwritten module.
- `ARM/scripts/create_workspace.tcl`: regenerates the SDK hardware, FreeRTOS BSP, and application projects.
- `ARM/app/src/platform/`: Xilinx BSP adapters and startup.
- `ARM/app/src/drivers/`: AXI shared-memory, DMA, VDMA, and touch drivers.
- `ARM/app/src/services/`: measurement conversion and waveform resampling.
- `ARM/app/src/ui/`: LVGL port, styles, screens, and bindings.
- `ARM/app/src/lv_conf.h`: fixed LVGL 16-bit configuration.
- `ARM/tests/`: native tests for platform-independent C modules.
- `ARM/third_party/lvgl`: git submodule pinned to LVGL v8.3.11.

### Task 1: Establish Reproducible Build Boundaries

**Files:**
- Modify: `.gitignore`
- Create: `FPGA/scripts/run_xsim.ps1`
- Create: `FPGA/scripts/run_vivado.ps1`
- Create: `ARM/scripts/run_xsct.ps1`
- Create: `ARM/README.md`

- [x] **Step 1: Write the failing toolchain smoke test**

Create `FPGA/scripts/run_vivado.ps1` so it rejects a missing Tcl script and returns Vivado's exit code:

```powershell
param([Parameter(Mandatory=$true)][string]$Script)
$vivado = 'D:/zt/Xilinx/Vivado/2018.3/bin/vivado.bat'
if (-not (Test-Path -LiteralPath $vivado)) { throw "Vivado 2018.3 not found: $vivado" }
if (-not (Test-Path -LiteralPath $Script)) { throw "Tcl script not found: $Script" }
& $vivado -mode batch -nojournal -nolog -source $Script
exit $LASTEXITCODE
```

Run: `powershell -ExecutionPolicy Bypass -File FPGA/scripts/run_vivado.ps1 -Script missing.tcl`

Expected: nonzero exit with `Tcl script not found`.

- [x] **Step 2: Add the SDK and XSim wrappers**

`ARM/scripts/run_xsct.ps1` invokes `D:/zt/Xilinx/SDK/2018.3/bin/xsct.bat`; `FPGA/scripts/run_xsim.ps1` invokes `xvlog.bat`, `xelab.bat`, and `xsim.bat` in a per-test build directory and fails on any nonzero exit.

- [x] **Step 3: Isolate generated output**

Append these exact ignore rules:

```gitignore
FPGA/prj_soc/
FPGA/export/
ARM/sdk_workspace/
ARM/build/
ARM/test_build/
*.wdb
*.vcd
```

Do not ignore `ARM/app`, `ARM/scripts`, `ARM/tests`, `FPGA/scripts`, or block-design Tcl sources.

- [x] **Step 4: Verify wrapper behavior**

Run: `powershell -ExecutionPolicy Bypass -File FPGA/scripts/run_xsim.ps1 -Test missing`

Expected: nonzero exit naming the missing test, without creating files outside `FPGA/sim/build`.

- [x] **Step 5: Commit**

```bash
git add .gitignore FPGA/scripts ARM/scripts ARM/README.md
git commit -m "build: add reproducible PQM SoC tool wrappers"
```

### Task 2: Create the Processing-System Block Design

**Files:**
- Create: `FPGA/scripts/create_pqm_soc_project.tcl`
- Create: `FPGA/scripts/create_pqm_ps_bd.tcl`
- Create: `FPGA/scripts/check_pqm_ps_bd.tcl`
- Create: `FPGA/scripts/build_pqm_soc.tcl`

- [x] **Step 1: Write a failing block-design contract check**

`check_pqm_ps_bd.tcl` opens `FPGA/prj_soc/PQM_SOC.xpr`, opens `pqm_ps.bd`, and fails unless these cells and interfaces exist:

```tcl
set required_cells {
  processing_system7_0 axi_interconnect_ctrl axi_bram_ctrl_0 blk_mem_gen_shared
  axi_dma_0 axi_vdma_0 v_tc_0 v_axi4s_vid_out_0 clk_wiz_pixel
  rst_fclk0 rst_pixel xlconcat_irq
}
foreach cell $required_cells {
  if {[llength [get_bd_cells -quiet $cell]] == 0} {
    error "Missing required BD cell: $cell"
  }
}
set ps [get_bd_cells processing_system7_0]
if {[get_property CONFIG.PCW_UIPARAM_DDR_PARTNO $ps] ne {MT41K256M16 RE-125}} {
  error "Incorrect DDR compatibility part"
}
if {[get_property CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH $ps] ne {32 Bit}} {
  error "Incorrect DDR bus width"
}
```

Run before implementation:

`powershell -ExecutionPolicy Bypass -File FPGA/scripts/run_vivado.ps1 -Script FPGA/scripts/check_pqm_ps_bd.tcl`

Expected: FAIL because `PQM_SOC.xpr` does not exist.

- [x] **Step 2: Create the deterministic PS7 configuration**

`create_pqm_ps_bd.tcl` shall set:

```tcl
set_property -dict [list \
  CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41K256M16 RE-125} \
  CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH {32 Bit} \
  CONFIG.PCW_UIPARAM_DDR_FREQ_MHZ {533.333333} \
  CONFIG.PCW_CRYSTAL_PERIPHERAL_FREQMHZ {33.333333} \
  CONFIG.PCW_APU_PERIPHERAL_FREQMHZ {666.666667} \
  CONFIG.PCW_UART0_PERIPHERAL_ENABLE {1} \
  CONFIG.PCW_UART0_UART0_IO {MIO 14 .. 15} \
  CONFIG.PCW_QSPI_PERIPHERAL_ENABLE {1} \
  CONFIG.PCW_SD0_PERIPHERAL_ENABLE {1} \
  CONFIG.PCW_SD0_SD0_IO {MIO 40 .. 45} \
  CONFIG.PCW_I2C0_PERIPHERAL_ENABLE {1} \
  CONFIG.PCW_I2C0_I2C0_IO {EMIO} \
  CONFIG.PCW_USE_M_AXI_GP0 {1} \
  CONFIG.PCW_USE_S_AXI_HP0 {1} \
  CONFIG.PCW_USE_S_AXI_HP1 {1} \
  CONFIG.PCW_USE_FABRIC_INTERRUPT {1} \
  CONFIG.PCW_EN_CLK0_PORT {1} \
  CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100.000000} \
] [get_bd_cells processing_system7_0]
```

Enable GPIO EMIO bits for touch reset, touch interrupt, and the physical fallback key. Use HP0 only for VDMA reads and HP1 only for DMA writes.

- [x] **Step 3: Instantiate the Xilinx IP data paths**

Create and connect:

- AXI GP0 to AXI BRAM Controller, AXI DMA control, and AXI VDMA control through `axi_interconnect_ctrl`;
- VDMA MM2S master to HP0;
- DMA S2MM master to HP1;
- a 64 KiB true-dual-port 32-bit BRAM, AXI on port A and PL shared-memory bridge on port B;
- 100 MHz FCLK0 AXI clock and reset;
- 25 MHz clock wizard output for the video timing domain;
- VTC and AXI4-Stream-to-Video-Out for 800x480 active video;
- DMA, VDMA, video, and PL-event interrupts through `xlconcat_irq` into `IRQ_F2P`.

Assign stable addresses:

```tcl
assign_bd_address -offset 0x40000000 -range 64K \
  [get_bd_addr_segs processing_system7_0/Data/SEG_axi_bram_ctrl_0_Mem0]
assign_bd_address -offset 0x40400000 -range 64K \
  [get_bd_addr_segs processing_system7_0/Data/SEG_axi_dma_0_Reg]
assign_bd_address -offset 0x43000000 -range 64K \
  [get_bd_addr_segs processing_system7_0/Data/SEG_axi_vdma_0_Reg]
```

- [x] **Step 4: Create the reproducible project script**

`create_pqm_soc_project.tcl` removes only `FPGA/prj_soc`, creates `PQM_SOC.xpr`, imports handwritten RTL, existing XCI files, and constraints, sources `create_pqm_ps_bd.tcl`, validates the design, creates the HDL wrapper, and sets top to `main`.

`build_pqm_soc.tcl` opens that project, resets and launches synthesis/implementation, checks run status, writes timing/utilization reports under `FPGA/export/reports`, writes `pqm_soc.bit`, and exports `pqm_soc.hdf` with the bitstream.

- [x] **Step 5: Run the block-design contract**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File FPGA/scripts/run_vivado.ps1 -Script FPGA/scripts/create_pqm_soc_project.tcl
powershell -ExecutionPolicy Bypass -File FPGA/scripts/run_vivado.ps1 -Script FPGA/scripts/check_pqm_ps_bd.tcl
```

Expected: both commands exit 0 and report all required cells and addresses.

- [x] **Step 6: Commit**

```bash
git add FPGA/scripts/create_pqm_soc_project.tcl FPGA/scripts/create_pqm_ps_bd.tcl FPGA/scripts/check_pqm_ps_bd.tcl FPGA/scripts/build_pqm_soc.tcl
git commit -m "feat(fpga): add reproducible Zynq PS block design"
```

### Task 3: Stream Raw Samples Without Coupling ADC Backpressure

**Files:**
- Create: `FPGA/rtl/PSInterface/pqm_axis_sample_stream.v`
- Create: `FPGA/sim/PSInterface/tb_pqm_axis_sample_stream.v`

- [x] **Step 1: Write the failing RTL test**

The test shall send 2,052 sample-valid pulses, hold `m_axis_tready=0` for four middle samples, and assert:

```verilog
if (accepted_count != 2048) $fatal(1, "accepted frame length mismatch");
if (tlast_count != 1) $fatal(1, "TLAST count mismatch");
if (drop_count != 4) $fatal(1, "drop counter mismatch");
if (last_sequence != 32'd2051) $fatal(1, "source sequence did not advance");
if (!gap_observed) $fatal(1, "accepted stream did not expose sequence gap");
```

Run: `powershell -ExecutionPolicy Bypass -File FPGA/scripts/run_xsim.ps1 -Test pqm_axis_sample_stream`

Expected: FAIL because the DUT is missing.

- [x] **Step 2: Implement the sample stream**

Use this interface exactly:

```verilog
module pqm_axis_sample_stream #(
    parameter integer FRAME_SAMPLES = 2048
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sample_valid,
    input  wire [15:0] u_sample,
    input  wire [15:0] i_sample,
    output reg  [31:0] source_sequence,
    output reg  [31:0] drop_count,
    output reg  [63:0] m_axis_tdata,
    output reg         m_axis_tvalid,
    input  wire        m_axis_tready,
    output reg         m_axis_tlast
);
```

Each source sample increments `source_sequence`. If the one-entry output register is occupied and not accepted, count the source sample as dropped. Count frame position only on `tvalid && tready`, and assert TLAST on accepted item 2,048. Saturate `drop_count` at `32'hFFFF_FFFF`.

- [x] **Step 3: Run the test and lint forbidden arithmetic**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File FPGA/scripts/run_xsim.ps1 -Test pqm_axis_sample_stream
rg -n "[/\*%]" FPGA/rtl/PSInterface/pqm_axis_sample_stream.v
```

Expected: XSim prints `PASS`; the `rg` output contains only comment delimiters, never arithmetic operators.

- [x] **Step 4: Commit**

```bash
git add FPGA/rtl/PSInterface/pqm_axis_sample_stream.v FPGA/sim/PSInterface/tb_pqm_axis_sample_stream.v
git commit -m "feat(fpga): stream sequenced ADC samples to PS"
```

### Task 4: Publish Coherent Shared-Memory Snapshots

**Files:**
- Create: `FPGA/rtl/PSInterface/pqm_shared_memory_map.vh`
- Create: `FPGA/rtl/PSInterface/pqm_shared_memory_bridge.v`
- Create: `FPGA/sim/PSInterface/tb_pqm_shared_memory_bridge.v`
- Create: `ARM/app/src/drivers/pqm_axi/pqm_shared_memory_map.h`

- [x] **Step 1: Define one ABI in Verilog and C**

Use these fixed word offsets:

```c
#define PQM_SHM_MAGIC_WORD          0x0000u
#define PQM_SHM_ABI_WORD            0x0001u
#define PQM_SHM_STATUS_WORD         0x0002u
#define PQM_SHM_SNAPSHOT_SEQ_WORD   0x0003u
#define PQM_SHM_SCALAR_BASE_WORD    0x0010u
#define PQM_SHM_COMMAND_BASE_WORD   0x0080u
#define PQM_SHM_COUNTER_BASE_WORD   0x00A0u
#define PQM_SHM_HARMONIC_BANK0_WORD 0x0400u
#define PQM_SHM_HARMONIC_BANK1_WORD 0x0C00u
#define PQM_SHM_MAGIC               0x50514D31u
#define PQM_SHM_ABI_VERSION         0x00010000u
```

Each harmonic entry is four words: U magnitude ratio, I magnitude ratio, signed phase, flags.

- [x] **Step 2: Write the failing coherence test**

The test changes all source metrics while a commit is active, then verifies that BRAM contains only the latched generation and that `SNAPSHOT_SEQ` is written last. It also writes a command word through the simulated PS BRAM port and verifies a single command pulse and matching response sequence.

Run: `powershell -ExecutionPolicy Bypass -File FPGA/scripts/run_xsim.ps1 -Test pqm_shared_memory_bridge`

Expected: FAIL because the bridge is missing.

- [x] **Step 3: Implement the serialized writer**

The bridge owns BRAM port B:

```verilog
output reg  [13:0] bram_addr,
output reg  [31:0] bram_wrdata,
output reg   [3:0] bram_we,
output wire        bram_en,
input  wire [31:0] bram_rddata
```

On `snapshot_commit`, latch all scalar inputs, write payload words, then write the incremented sequence. Harmonic data writes only to the inactive bank and publishes the active-bank bit plus generation after entry 500 is complete. Command polling shall not interrupt an active publish state; it runs when the writer is idle.

- [x] **Step 4: Verify RTL and ABI equality**

Run XSim, then run a PowerShell comparison that extracts hexadecimal constants from `.vh` and `.h` and fails on any mismatch.

Expected: XSim and ABI comparison both print `PASS`.

- [x] **Step 5: Commit**

```bash
git add FPGA/rtl/PSInterface/pqm_shared_memory_map.vh FPGA/rtl/PSInterface/pqm_shared_memory_bridge.v FPGA/sim/PSInterface/tb_pqm_shared_memory_bridge.v ARM/app/src/drivers/pqm_axi/pqm_shared_memory_map.h
git commit -m "feat: add coherent PS PL shared memory ABI"
```

### Task 5: Convert RGB565 AXI Video to RGB888

**Files:**
- Create: `FPGA/rtl/PSInterface/pqm_axis_rgb565_to_rgb888.v`
- Create: `FPGA/sim/PSInterface/tb_pqm_axis_rgb565_to_rgb888.v`

- [x] **Step 1: Write the failing color and handshake test**

Test black, white, red, green, blue, `16'h7BEF`, and randomized ready stalls. Require TUSER and TLAST to remain paired with their pixel while stalled.

- [x] **Step 2: Implement endpoint-preserving expansion**

```verilog
assign rgb888[23:16] = {rgb565[15:11], rgb565[15:13]};
assign rgb888[15:8]  = {rgb565[10:5],  rgb565[10:9]};
assign rgb888[7:0]   = {rgb565[4:0],   rgb565[4:2]};
```

Use an AXI register slice with `s_axis_tready = !valid_reg || m_axis_tready`; never alter sideband signals while `m_axis_tvalid && !m_axis_tready`.

- [x] **Step 3: Run XSim**

Run: `powershell -ExecutionPolicy Bypass -File FPGA/scripts/run_xsim.ps1 -Test pqm_axis_rgb565_to_rgb888`

Expected: `PASS` with all randomized stalls completed.

- [x] **Step 4: Commit**

```bash
git add FPGA/rtl/PSInterface/pqm_axis_rgb565_to_rgb888.v FPGA/sim/PSInterface/tb_pqm_axis_rgb565_to_rgb888.v
git commit -m "feat(fpga): add RGB565 AXI video conversion"
```

### Task 6: Refactor the PL Top and Integrate the SoC

**Files:**
- Move: `FPGA/rtl/main.v` to `FPGA/rtl/pqm_legacy_core.v`
- Create: `FPGA/rtl/main.v`
- Create: `FPGA/rtl/PSInterface/pqm_touch_iobuf.v`
- Modify: `FPGA/prj/PQM.xdc`
- Modify: `FPGA/scripts/create_pqm_soc_project.tcl`

- [x] **Step 1: Preserve the existing top behavior as a named fallback**

Rename the old module to `pqm_legacy_core`. Add outputs for signed channel-1/channel-3 samples, `adc_frame_valid`, ADC timeout, and the scalar/harmonic results needed by the shared-memory bridge. Keep executable behavior unchanged.

- [x] **Step 2: Write an elaboration test for both display modes**

The new `main` has parameter `LEGACY_PL_DISPLAY`. Run Vivado elaboration once with `1` and once with `0`; each run must have exactly one driver for every LCD and touch pin.

- [x] **Step 3: Implement the SoC top**

`main` instantiates:

- `pqm_legacy_core` for acquisition and measurements;
- generated `pqm_ps` block-design module with explicit EMIO I/O/T signals;
- `pqm_axis_sample_stream` into AXI DMA S2MM stream input;
- `pqm_shared_memory_bridge` into BRAM port B;
- `pqm_axis_rgb565_to_rgb888` between VDMA and Video Out;
- `pqm_touch_iobuf` for PS I2C EMIO and GPIO reset/interrupt;
- a generate-time LCD output mux selecting legacy or PS scanout.

The PS mode shall not instantiate PL font ROM, text preprocessing, background rendering, wave-pixel detection, or PL touch protocol logic once Task 12 removes the fallback dependency.

- [x] **Step 4: Validate and synthesize the transitional design**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File FPGA/scripts/run_vivado.ps1 -Script FPGA/scripts/create_pqm_soc_project.tcl
powershell -ExecutionPolicy Bypass -File FPGA/scripts/run_vivado.ps1 -Script FPGA/scripts/build_pqm_soc.tcl
```

Expected: synthesis completes with no critical warnings about unconstrained clocks, unconnected HP ports, multiple LCD drivers, or AXI width mismatch.

- [x] **Step 5: Commit**

```bash
git add FPGA/rtl/main.v FPGA/rtl/pqm_legacy_core.v FPGA/rtl/PSInterface/pqm_touch_iobuf.v FPGA/prj/PQM.xdc FPGA/scripts/create_pqm_soc_project.tcl
git commit -m "feat(fpga): integrate PS communication and video paths"
```

### Task 7: Generate the FreeRTOS Workspace and ABI Driver

**Files:**
- Create: `ARM/scripts/create_workspace.tcl`
- Create: `ARM/app/src/main.c`
- Create: `ARM/app/src/platform/pqm_platform.c`
- Create: `ARM/app/src/platform/pqm_platform.h`
- Create: `ARM/app/src/drivers/pqm_axi/pqm_axi.c`
- Create: `ARM/app/src/drivers/pqm_axi/pqm_axi.h`
- Create: `ARM/tests/test_pqm_axi.c`
- Modify: `.gitmodules`

- [ ] **Step 1: Add the pinned LVGL dependency**

Run:

```bash
git submodule add https://github.com/lvgl/lvgl.git ARM/third_party/lvgl
git -C ARM/third_party/lvgl checkout v8.3.11
```

Verify: `git submodule status` starts with commit `74d0a816a440eea53e030c4f1af842a94f7ce3d3`.

- [ ] **Step 2: Write the failing native ABI tests**

Use MinGW GCC at `D:/zt/Xilinx/Vivado/2018.3/msys64/mingw64/bin/gcc.exe`. Tests cover magic/version rejection, stable snapshot read, retry on changed sequence, signed field decoding, and command timeout.

Run: `powershell -ExecutionPolicy Bypass -File ARM/tests/run_tests.ps1`

Expected: compile fails because `pqm_axi.c` is missing.

- [ ] **Step 3: Implement the platform-neutral ABI reader**

Expose:

```c
typedef uint32_t (*pqm_read_word_fn)(void *context, uint32_t word_offset);
typedef void (*pqm_write_word_fn)(void *context, uint32_t word_offset, uint32_t value);

bool pqm_axi_validate(pqm_axi_t *axi);
bool pqm_axi_read_snapshot(pqm_axi_t *axi, pqm_measurement_raw_t *out);
bool pqm_axi_send_command(pqm_axi_t *axi, uint32_t command, uint32_t argument,
                          uint32_t timeout_polls, uint32_t *response);
```

The Xilinx backend uses volatile 32-bit reads/writes at `XPAR_AXI_BRAM_CTRL_0_S_AXI_BASEADDR`. Host tests inject an in-memory backend.

- [ ] **Step 4: Generate the SDK workspace**

`create_workspace.tcl` shall:

```tcl
setws ARM/sdk_workspace
createhw -name pqm_hw -hwspec FPGA/export/pqm_soc.hdf
createbsp -name pqm_bsp -hwproject pqm_hw -proc ps7_cortexa9_0 -os freertos10_xilinx
createapp -name pqm_freertos -hwproject pqm_hw -proc ps7_cortexa9_0 \
  -os freertos10_xilinx -lang C -app {Empty Application}
regenbsp -bsp pqm_bsp
```

Import `ARM/app/src` and `ARM/third_party/lvgl/src` as linked sources and set include paths for LVGL and the generated BSP.

- [ ] **Step 5: Build FreeRTOS boot smoke application**

`main.c` initializes the platform, prints PS/PL ABI identity on PS UART, creates `system_task`, then starts the scheduler. Stack/allocation hooks print the failing task and force watchdog reset.

Run:

```powershell
powershell -ExecutionPolicy Bypass -File ARM/scripts/run_xsct.ps1 -Script ARM/scripts/create_workspace.tcl
```

Expected: `pqm_freertos.elf` is produced with no unresolved LVGL or Xilinx driver symbols.

- [ ] **Step 6: Commit**

```bash
git add .gitmodules ARM/third_party/lvgl ARM/scripts ARM/app ARM/tests
git commit -m "feat(arm): bootstrap FreeRTOS and shared memory ABI"
```

### Task 8: Implement DMA Reception and Waveform Resampling

**Files:**
- Create: `ARM/app/src/drivers/pqm_dma/pqm_dma.c`
- Create: `ARM/app/src/drivers/pqm_dma/pqm_dma.h`
- Create: `ARM/app/src/services/waveform/pqm_waveform.c`
- Create: `ARM/app/src/services/waveform/pqm_waveform.h`
- Create: `ARM/tests/test_pqm_waveform.c`

- [ ] **Step 1: Write failing waveform tests**

Tests cover contiguous frames, wraparound sequence arithmetic, one and multiple dropped regions, 2,048-to-400-column min/max resampling, constant signals, signed endpoints, and clipping.

- [ ] **Step 2: Implement deterministic resampling**

Expose:

```c
bool pqm_waveform_accept_frame(pqm_waveform_t *state,
                               const pqm_dma_sample_t samples[2048]);
void pqm_waveform_resample(const pqm_waveform_t *state,
                           pqm_wave_column_t *columns, size_t column_count);
```

Each output column contains U-min/U-max/I-min/I-max. Use integer bucket boundaries derived from cumulative indices so all 2,048 inputs are consumed exactly once. A sequence discontinuity marks the frame invalid and preserves the previous valid display frame.

- [ ] **Step 3: Implement the AXI DMA SG ring**

Allocate four 16 KiB, 64-byte-aligned buffers and descriptors in a linker section outside the framebuffer region. The ISR acknowledges only IOC/error bits and notifies `dma_rx_task`. The task invalidates cache for the completed buffer, validates sample sequences, publishes the latest valid frame, then returns the descriptor to hardware.

- [ ] **Step 4: Run native tests and ARM build**

Expected: all native tests pass; SDK build has no pointer-width, alignment, or volatile warnings.

- [ ] **Step 5: Commit**

```bash
git add ARM/app/src/drivers/pqm_dma ARM/app/src/services/waveform ARM/tests
git commit -m "feat(arm): receive and resample ADC DMA frames"
```

### Task 9: Bring Up VDMA and the LVGL Display Port

**Files:**
- Create: `ARM/app/src/drivers/pqm_video/pqm_video.c`
- Create: `ARM/app/src/drivers/pqm_video/pqm_video.h`
- Create: `ARM/app/src/ui/pqm_lvgl_port.c`
- Create: `ARM/app/src/ui/pqm_lvgl_port.h`
- Create: `ARM/app/src/lv_conf.h`
- Create: `ARM/app/src/lscript.ld`

- [ ] **Step 1: Add compile-time framebuffer assertions**

```c
#define PQM_LCD_WIDTH 800u
#define PQM_LCD_HEIGHT 480u
#define PQM_FB_BYTES (PQM_LCD_WIDTH * PQM_LCD_HEIGHT * sizeof(uint16_t))
_Static_assert(PQM_FB_BYTES == 768000u, "unexpected RGB565 framebuffer size");
_Static_assert((PQM_FB0_ADDR & 63u) == 0u, "framebuffer 0 alignment");
_Static_assert((PQM_FB1_ADDR & 63u) == 0u, "framebuffer 1 alignment");
```

- [ ] **Step 2: Configure and test VDMA with solid frames**

Initialize two frame stores at 800 pixels, 480 lines, stride 1,600 bytes. Fill front/back with alternating red, green, blue, white, and black. Clean cache before requesting a frame switch. Count frame-done and VDMA error interrupts.

- [ ] **Step 3: Configure LVGL v8.3.11**

Set `LV_COLOR_DEPTH 16`, `LV_COLOR_16_SWAP 0`, custom allocator disabled, logging enabled through PS UART in debug builds, and full-refresh double buffering. `ui_task` is the only LVGL caller and runs `lv_timer_handler()` at a 5 ms minimum wake interval.

- [ ] **Step 4: Implement synchronized buffer ownership**

The flush callback cleans only the rendered area, records the pending frame store, and completes `lv_disp_flush_ready()` after VDMA confirms the frame-boundary switch. A 100 ms timeout restarts only VDMA and retains the current front buffer.

- [ ] **Step 5: Build and run the framebuffer hardware smoke test**

Expected: stable 800x480 color sequence, correct RGB channel order, no tearing, and zero VDMA errors for 10 minutes.

- [ ] **Step 6: Commit**

```bash
git add ARM/app/src/drivers/pqm_video ARM/app/src/ui/pqm_lvgl_port.* ARM/app/src/lv_conf.h ARM/app/src/lscript.ld
git commit -m "feat(arm): drive LVGL through double-buffered VDMA"
```

### Task 10: Port Touch Control to PS I2C EMIO

**Files:**
- Create: `ARM/app/src/drivers/pqm_touch/pqm_touch.c`
- Create: `ARM/app/src/drivers/pqm_touch/pqm_touch.h`
- Create: `ARM/tests/test_pqm_touch.c`
- Modify: `ARM/app/src/ui/pqm_lvgl_port.c`

- [ ] **Step 1: Write failing coordinate and packet tests**

Use captured Goodix/FT touch register packets from the existing `touch_dri.v` behavior. Test no-touch, press, move, release, malformed point count, I2C timeout, and panel-edge coordinates.

- [ ] **Step 2: Implement the PS touch driver**

Use `XIicPs` through I2C0 EMIO and `XGpioPs` EMIO bits for reset/interrupt. Probe the supported controller addresses used by the existing RTL, perform the controller-specific reset sequence, read at most one primary point for LVGL, and clear the controller status register after each read.

- [ ] **Step 3: Add fault isolation**

After three consecutive I2C failures, disable the GPIO interrupt and retry initialization every 500 ms. Never block `ui_task`; publish the last state as released during recovery.

- [ ] **Step 4: Verify native tests and hardware corners**

Expected: native tests pass and physical touches at all four corners map within `[0,799] x [0,479]`.

- [ ] **Step 5: Commit**

```bash
git add ARM/app/src/drivers/pqm_touch ARM/app/src/ui/pqm_lvgl_port.c ARM/tests/test_pqm_touch.c
git commit -m "feat(arm): port LCD touch input to PS"
```

### Task 11: Port the Existing Time and Frequency Pages

**Files:**
- Create: `ARM/app/src/services/measurement/pqm_measurement.c`
- Create: `ARM/app/src/services/measurement/pqm_measurement.h`
- Create: `ARM/app/src/ui/pqm_ui.c`
- Create: `ARM/app/src/ui/pqm_ui.h`
- Create: `ARM/app/src/ui/pqm_ui_style.c`
- Create: `ARM/app/src/ui/pqm_ui_time.c`
- Create: `ARM/app/src/ui/pqm_ui_frequency.c`
- Create: `ARM/tests/test_pqm_measurement.c`

- [ ] **Step 1: Write failing fixed-point formatting tests**

Cover zero, positive, negative, minimum/maximum raw inputs, invalid flags, saturation, signed P/Q/phase, PF, THD, and frequency. Expected strings must match the legacy screen units and decimal precision.

- [ ] **Step 2: Implement measurement conversion**

Keep raw-to-engineering scale constants in one table. Return typed values plus validity, never preformatted global strings. Formatting helpers accept caller-owned buffers and always terminate them.

- [ ] **Step 3: Recreate the two current pages**

Use LVGL objects for:

- title/status bar and alarm state;
- time-domain U/I waveform with grid and range labels;
- RMS, peak-to-peak, frequency, phase, P/Q/S/PF values;
- frequency magnitude and phase plots for selectable harmonic windows;
- freeze, page selection, and range controls.

Do not place feature-description or help text on screen. Use the existing `FPGA/rtl/lcd/lcd.html` only as the layout reference.

- [ ] **Step 4: Integrate the FreeRTOS tasks**

Create `dma_rx_task`, `measurement_task`, `touch_task`, `ui_task`, and `system_task` with static stacks and queues. Measurement and waveform producers publish immutable latest-value messages; only `ui_task` mutates LVGL objects.

- [ ] **Step 5: Compare against legacy output**

For the MATLAB Q15 input fixture, log PS measurements and compare them with the current PL UART/legacy page values. Every displayed field must match the agreed scale and sign; waveform shape and harmonic ordering must match.

- [ ] **Step 6: Commit**

```bash
git add ARM/app/src/services/measurement ARM/app/src/ui ARM/tests/test_pqm_measurement.c
git commit -m "feat(arm): port PQM measurement pages to LVGL"
```

### Task 12: Remove Obsolete PL Display Work and Update Documentation

**Files:**
- Create: `FPGA/rtl/DataProcessor/pqm_measurement_core.v`
- Modify: `FPGA/rtl/pqm_legacy_core.v`
- Modify: `FPGA/rtl/main.v`
- Remove after comparison: obsolete render-only modules under `FPGA/rtl/lcd/display`
- Remove after comparison: display-only modules under `FPGA/rtl/DataProcessor/GraphicsLoad`
- Remove after comparison: `FPGA/rtl/uart/uart_measurement_streamer.v`
- Remove after comparison: `FPGA/rtl/uart/uart_value_x100_formatter.v`
- Modify: `FPGA/doc/rtl_file_overview.md`
- Modify: `FPGA/doc/project_progress_summary.md`
- Create: `FPGA/doc/ps_pl_interface.md`
- Modify: `README.txt`

- [ ] **Step 1: Extract measurement ownership before deleting rendering**

Move time/frequency measurement instances and outputs from `lcd_display.v` into `pqm_measurement_core.v`. Keep one module per file and preserve existing clocks, reset polarity, bit widths, and result-valid timing.

- [ ] **Step 2: Run legacy-vs-extracted simulation**

Feed both implementations the same recorded ADC samples and assert equality for scalar results and all committed harmonics. Do not delete legacy modules until this test passes.

- [ ] **Step 3: Switch PS display mode to the default**

Set `LEGACY_PL_DISPLAY=0`, remove the legacy renderer from the synthesized hierarchy, and keep only the minimal LCD physical video path. Remove font ROMs, text formatting, background composition, wave-pixel detection, and PL touch protocol logic when they have no remaining references.

- [ ] **Step 4: Update project documentation**

Document the final ownership boundary, shared-memory word map, sample stream, addresses, interrupts, boot steps, build commands, measured resource deltas, known limitations, and next work.

- [ ] **Step 5: Commit**

```bash
git add -A FPGA/rtl FPGA/doc README.txt
git commit -m "refactor(fpga): remove PL display composition after PS migration"
```

### Task 13: Final Build, Boot Artifacts, and Acceptance

**Files:**
- Modify: `FPGA/scripts/build_pqm_soc.tcl`
- Create: `ARM/scripts/build_boot_image.tcl`
- Update: `FPGA/ZYNQ固化脚本/bootbin.bif`
- Update generated deliverables only after successful build: `FPGA/ZYNQ固化脚本/BOOT.bin`

- [ ] **Step 1: Run all automated tests**

```powershell
powershell -ExecutionPolicy Bypass -File FPGA/scripts/run_xsim.ps1 -All
powershell -ExecutionPolicy Bypass -File ARM/tests/run_tests.ps1
powershell -ExecutionPolicy Bypass -File FPGA/scripts/run_vivado.ps1 -Script FPGA/scripts/build_pqm_soc.tcl
powershell -ExecutionPolicy Bypass -File ARM/scripts/run_xsct.ps1 -Script ARM/scripts/create_workspace.tcl
```

Expected: every test passes, Vivado reports no critical warnings, and SDK produces `pqm_freertos.elf`.

- [ ] **Step 2: Enforce timing and resource gates**

Parse the routed reports and fail unless WNS is nonnegative, LUT utilization is below 55%, and the obsolete PL display hierarchy is absent.

- [ ] **Step 3: Generate boot artifacts**

Build a fresh FSBL from the exported HDF, then run Bootgen with FSBL, bitstream, and `pqm_freertos.elf`. Keep the pre-migration `448cc00` commit as the recovery baseline.

- [ ] **Step 4: Run hardware acceptance**

Verify PS UART boot identity, 30 FPS target, no visible tearing, touch corners, measurement comparison, induced ADC/DMA/VDMA/touch recovery, and a 30-minute soak with zero watchdog resets.

- [ ] **Step 5: Review generated-file scope and commit**

Do not commit transient Vivado/SDK output. Commit only reproducible scripts, source, documentation, the final requested boot artifact, and the updated BIF.

```bash
git add FPGA/scripts ARM/scripts FPGA/ZYNQ固化脚本/bootbin.bif FPGA/ZYNQ固化脚本/BOOT.bin
git commit -m "build: produce PS FreeRTOS PQM boot image"
```

- [ ] **Step 6: Push the migration branch after final verification**

Run `git status --short`, verify only intended files are cleanly committed, then push the active `codex/` migration branch.
