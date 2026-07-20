PQM - Zynq-7020 Power Quality Monitor

Target:
  - XC7Z020-CLG400-2
  - 7-inch 800x480 RGB LCD
  - AD7606 parallel ADC

Final ownership:
  - PL: ADC acquisition, time/frequency measurement, FFT, harmonic statistics,
    alarms, AXI sample stream, and shared-memory publication.
  - PS: FreeRTOS 10, LVGL 8.3.11, waveform resampling, LCD composition,
    touch input, range commands, and runtime supervision.

The default build uses LEGACY_PL_DISPLAY=0. Set it to 1 only when the old
PL-rendered LCD path is required for recovery.

Main entry points:
  FPGA/scripts/build_pqm_soc.tcl
  FPGA/scripts/check_pqm_soc_reports.ps1
  ARM/scripts/create_workspace.tcl
  ARM/scripts/build_boot_image.ps1

Generated deliverables:
  FPGA/export/pqm_soc.bit
  FPGA/export/pqm_soc.hdf
  ARM/sdk_workspace/pqm_freertos/Release/pqm_freertos.elf
  FPGA/ZYNQ固化脚本/BOOT.bin

See FPGA/doc/ps_pl_interface.md and ARM/README.md for interface and build
details. Physical LCD, touch and long-duration recovery tests still require
the target board.
