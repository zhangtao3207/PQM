# PQM PS Software

This directory contains the Cortex-A9 software for the PQM Zynq-7020 migration.

## Target

- Board: ALIENTEK Linghangzhe ZYNQ with XC7Z020-CLG400-2
- PS clock input: 33.333333 MHz
- CPU: 666.666667 MHz, Cortex-A9 core 0
- DDR3: 1 GB, 32-bit, compatible preset `MT41K256M16 RE-125`
- RTOS: Xilinx FreeRTOS 10 from SDK 2018.3
- UI: LVGL v8.3.11, RGB565, 800x480

## Generated Directories

`sdk_workspace`, `build`, and `test_build` are generated and intentionally ignored. Application source, scripts, tests, and the pinned LVGL dependency remain tracked.

## Tool Entry Points

Run the platform-neutral PS/PL ABI tests:

```powershell
powershell -ExecutionPolicy Bypass -File ARM/tests/run_tests.ps1
```

Run an XSCT script through the fixed SDK 2018.3 installation:

```powershell
powershell -ExecutionPolicy Bypass -File ARM/scripts/run_xsct.ps1 -Script ARM/scripts/create_workspace.tcl
```

Generate a fresh FSBL and package `FSBL + bitstream + FreeRTOS ELF`:

```powershell
powershell -ExecutionPolicy Bypass -File ARM/scripts/build_boot_image.ps1
```

The resulting image is written to `FPGA/ZYNQ固化脚本/BOOT.bin`. The script
only builds the image; it does not program QSPI or start a board session.

The hardware handoff is generated under `FPGA/export` by the Vivado build scripts. Do not edit generated BSP or workspace files by hand.

`create_workspace.tcl` recreates the FreeRTOS BSP and application, imports the
tracked application sources, and verifies that
`ARM/sdk_workspace/pqm_freertos/Release/pqm_freertos.elf` was produced.
