# PQM PS FreeRTOS Display Migration Design

## 1. Objective

Migrate the presentation and interaction workload from programmable logic (PL) to the Zynq-7020 processing system (PS), while preserving the deterministic ADC and power-quality measurement pipeline in PL.

The first migration milestone shall:

- run FreeRTOS and LVGL on Cortex-A9 core 0;
- render the 7-inch 800x480 RGB LCD from a DDR-backed RGB565 double framebuffer;
- move page composition, text formatting, waveform and spectrum drawing, touch handling, and system management to PS software;
- keep AD7606 acquisition, time-domain measurement, FFT, harmonic statistics, and alarms in PL;
- replace the external PL UART measurement stream as the internal data path with AXI interfaces;
- preserve the existing PL display path behind a build-time fallback until the new path passes integration testing.

## 2. Hardware Baseline

The active target is the Linghangzhe ZYNQ carrier and ZYNQ-CORE module:

- device: `XC7Z020-CLG400-2`;
- PS reference clock: 33.333333 MHz;
- DDR3: two `NT5CC256M16` devices on a 32-bit bus, 1 GB total;
- nonvolatile storage: `W25Q256FV` QSPI and 8 GB `KLM8G1GETF` eMMC;
- removable storage: SD card on MIO40 through MIO45;
- PS UART: MIO14 and MIO15;
- display: 800x480 RGB888 physical interface with touch I2C on PL pins;
- current Vivado project: 2018.3, top module `main`, part `xc7z020clg400-2`.

The placed baseline consumes 34,546 LUTs (64.94%), 25,820 registers (24.27%), 26.5 BRAM tiles (18.93%), 101 DSPs (45.91%), and 11,661 slices (87.68%).

## 3. Ownership Boundary

### 3.1 PL Responsibilities

PL retains:

- AD7606 conversion control and parallel read timing;
- voltage and current sample capture;
- zero tracking, RMS, peak-to-peak, frequency, phase, P/Q/S/PF, THD, FFT, and harmonic calculations;
- measurement and alarm state generation;
- coherent AXI measurement snapshots;
- raw U/I AXI-Stream generation;
- harmonic result double buffering;
- AXI VDMA stream conversion, pixel timing, RGB565-to-RGB888 expansion, and LCD pin drive.

PL shall not retain page layout, character rasterization, numeric-to-text conversion, graph coordinate scaling, touch gestures, or application navigation after the migration fallback is removed.

### 3.2 PS Responsibilities

PS software owns:

- FreeRTOS task scheduling and watchdog supervision;
- LVGL page and widget construction;
- fixed-point unit conversion and text formatting;
- waveform resampling and plotting;
- harmonic spectrum and phase plotting;
- touch-controller I2C transactions and gesture mapping;
- framebuffer lifecycle and synchronized VDMA buffer switching;
- configuration, logs, storage, and external communication;
- fault presentation and recovery commands.

FreeRTOS runs on Cortex-A9 core 0. Core 1 remains disabled in the first milestone.

## 4. PS-PL Architecture

### 4.1 AXI Ports

- `M_AXI_GP0`: PS master for AXI-Lite control, status, and measurement registers.
- `S_AXI_HP0`: VDMA memory reader access to DDR framebuffers.
- `S_AXI_HP1`: AXI DMA S2MM access to DDR sample buffers.
- `IRQ_F2P`: DMA, measurement snapshot, harmonic commit, and PL fault interrupts.

FCLK0 supplies the AXI/control clock. The existing 50 MHz PL sampling clock remains the acquisition timing reference. The 800x480 LCD keeps a 25 MHz pixel clock.

### 4.2 Video Path

LVGL uses `LV_COLOR_DEPTH=16` and two full-screen RGB565 framebuffers. Each framebuffer is 768,000 bytes and begins on a 64-byte boundary. AXI VDMA reads the active framebuffer through HP0. The PL video path expands RGB565 to RGB888 and drives the existing LCD timing and pins.

Buffer ownership is explicit:

1. VDMA scans the front buffer.
2. LVGL renders only into the back buffer.
3. PS cleans the modified DCache range.
4. PS requests a frame-store change.
5. VDMA applies the change at a frame boundary.
6. Front and back ownership swaps only after completion is acknowledged.

### 4.3 Sample Stream

Each accepted AXI-Stream item is 64 bits:

| Bits | Meaning |
|---|---|
| 15:0 | signed raw voltage sample from AD7606 channel 1 |
| 31:16 | signed raw current sample from AD7606 channel 3 |
| 63:32 | monotonic sample sequence number |

`TLAST` is asserted every 2,048 accepted items. One DMA frame is therefore 16 KiB. The display stream may apply backpressure, but it must never stall ADC acquisition or the PL measurement pipeline. When no stream buffer space is available, the stream adapter drops display samples, advances the source sequence counter, and increments a saturating drop counter. PS detects gaps from the sequence field.

AXI DMA uses a descriptor ring so that at least four receive buffers remain available. DMA completion ISRs only acknowledge hardware and notify the service task; cache maintenance and parsing run in task context.

### 4.4 Measurement Snapshot

Scalar measurements use a versioned AXI-Lite register block containing:

- protocol magic, ABI version, and capability bits;
- control, status, interrupt status, and interrupt acknowledge;
- snapshot sequence and validity flags;
- ADC timeout and sample timing counters;
- RMS, peak-to-peak, frequency, phase, P/Q/S/PF, THD, DC, and alarm results;
- DMA frame, drop, overflow, and recovery counters;
- command request, argument, sequence, response, and response sequence.

PL publishes a complete snapshot and increments `snapshot_seq` only after all fields are stable. PS reads the sequence before and after the payload and retries when the values differ.

### 4.5 Harmonic Window

Harmonics 0 through 500 use a dual-bank BRAM window. PL writes the inactive bank, commits its generation number after a complete FFT result set, then swaps banks atomically. PS reads only the committed bank and verifies the generation before and after copying the requested range.

## 5. FreeRTOS Software Structure

### 5.1 Tasks

| Task | Responsibility | Activation |
|---|---|---|
| `dma_rx_task` | recycle descriptors, invalidate cache, check sample continuity, publish latest waveform | DMA interrupt notification |
| `measurement_task` | copy scalar snapshot and committed harmonics into the application model | PL interrupt or 10 Hz timeout |
| `touch_task` | service touch interrupt, read the controller over PS I2C EMIO, publish LVGL input events | GPIO interrupt and recovery timer |
| `ui_task` | own all LVGL calls, update widgets, render and request buffer swaps | periodic, target 30 FPS |
| `system_task` | task heartbeat, watchdog, counters, PS UART logging, recovery policy | periodic, low priority |

No task other than `ui_task` may call LVGL. Inter-task transfer uses fixed-size queues, direct task notifications, or lock-free latest-value mailboxes. Runtime paths shall not allocate from the heap after initialization.

### 5.2 Software Modules

- `platform/`: BSP, cache, interrupt, timer, watchdog, and PS peripheral adapters.
- `drivers/pqm_axi/`: register ABI, snapshot reads, commands, and fault counters.
- `drivers/pqm_dma/`: descriptor ring and sample-frame ownership.
- `drivers/pqm_video/`: VDMA setup, framebuffer ownership, cache cleaning, and frame swaps.
- `drivers/pqm_touch/`: touch-controller I2C protocol and coordinate mapping.
- `services/measurement/`: fixed-point conversions and application data model.
- `services/waveform/`: discontinuity handling, min/max resampling, trigger view, and display scaling.
- `ui/`: LVGL screens, styles, widgets, and event bindings.

## 6. Startup and Recovery

Startup order is deterministic:

1. FSBL initializes PS clocks and DDR and loads the bitstream.
2. FreeRTOS initializes PS UART, GIC, timers, cache policy, and shared memory.
3. Software validates PL magic, ABI version, and capabilities.
4. VDMA starts on a cleared black framebuffer.
5. LVGL and touch initialize.
6. Sample DMA and measurement interrupts start.
7. The UI enters normal operation only after one valid measurement snapshot.

Recovery behavior:

- ADC timeout triggers a PL soft-reset command. Three consecutive failures latch an ADC fault while keeping the UI and communications alive.
- DMA overflow or sample gaps invalidate only the affected waveform. Scalar PL measurements remain valid.
- VDMA faults retain the last displayed buffer and restart only the video channel.
- Snapshot contention retries three times and otherwise preserves the last valid application model.
- Touch failures disable input temporarily and retry initialization without stopping display updates.
- FreeRTOS stack overflow and allocation failure hooks record the fault and force a watchdog reset.
- A protocol ABI mismatch prevents DMA startup and shows a diagnostic screen.

## 7. Migration Sequence

1. Add the PS block design, DDR/MIO configuration, AXI fabric, interrupts, VDMA, DMA, and a legacy-display build switch.
2. Add the AXI register ABI, sample stream adapter, and harmonic bank interface while leaving legacy LCD output active.
3. Create the FreeRTOS BSP/application and validate PS boot, AXI identity, scalar snapshots, and sample DMA through PS UART logs.
4. Add the RGB565 VDMA scanout and framebuffer test patterns.
5. Port touch I2C to PS and integrate LVGL input.
6. Port current time-domain and frequency-domain pages to LVGL and compare values against the legacy display/UART.
7. Make the PS framebuffer path the default and run extended integration tests.
8. Remove obsolete PL page composition, font ROM, display preprocessing, waveform pixel detection, and UART text formatting after fallback acceptance.
9. Regenerate bitstream, FSBL, FreeRTOS image, and boot artifacts; update project documentation and resource reports.

## 8. Verification

### 8.1 RTL Tests

- AXI sample words contain the correct signed U/I channels and sequence numbers.
- `TLAST` occurs after exactly 2,048 accepted samples.
- backpressure produces observable sequence gaps without stalling ADC-valid handling.
- scalar snapshots never expose mixed generations.
- harmonic bank commits are atomic.
- RGB565 expansion maps endpoint and representative colors correctly.
- reset and command handshakes recover from injected timeouts.

### 8.2 C Host Tests

- register decoding and fixed-point conversions;
- snapshot retry and ABI rejection;
- DMA sequence-gap detection;
- waveform min/max resampling and clipping;
- touch coordinate transforms;
- UI model formatting for positive, negative, zero, overflow, and invalid values.

### 8.3 Hardware Acceptance

- boots FreeRTOS reliably from the selected development boot path;
- displays 800x480 at a stable target of 30 FPS with no visible tearing;
- touch coordinates and page actions are correct across the panel;
- displayed measurements match the legacy implementation for identical ADC input;
- normal operation has no DMA errors or unexplained sample discontinuities;
- injected ADC, DMA, VDMA, and touch faults recover according to this design;
- 30-minute continuous operation shows no framebuffer corruption, task starvation, or watchdog reset;
- routed timing has no negative slack;
- final placed LUT utilization is below 55%, with the obsolete PL display hierarchy absent.

## 9. RTL Project Rules

All new or changed PQM RTL follows the project rules:

- one module per Verilog file;
- no direct `/`, `*`, or `%` operators in handwritten Verilog;
- reuse the existing `DataProcessor/BasicMath` modules for arithmetic;
- add concise Chinese module, port, always-block, assign, function, and instantiation comments;
- keep `FPGA/doc/rtl_file_overview.md` and `FPGA/doc/project_progress_summary.md` synchronized with major changes.

## 10. Out of Scope for the First Milestone

- moving RMS, power, FFT, or harmonic arithmetic from PL to PS;
- using Cortex-A9 core 1;
- Linux, Qt, or DRM/KMS;
- remote firmware update or QSPI multiboot;
- changing the ADC analog front end or channel mapping;
- redesigning the visual language beyond faithfully porting the existing pages.
