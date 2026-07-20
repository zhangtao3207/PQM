# PQM ARM/FreeRTOS工程

本目录是PQM当前开发工程，目标器件为`XC7Z020-CLG400-2`，显示屏为7英寸
800x480 RGB LCD，采样器件为AD7606。

## 软硬件分工

- PL：AD7606采集、时域/频域测量、FFT、谐波统计、告警、AXI采样流和共享内存。
- PS：FreeRTOS 10、LVGL 8.3.11、波形重采样、LCD合成、触摸、量程命令和监控。

ARM已经接管的PL显示、触摸、UART和文字格式化代码已从本工程删除。完整旧PL
工程保存在同级目录`../backup_pl`。

## 主要入口

- `FPGA/scripts/create_pqm_soc_project.tcl`：重建Vivado SoC工程。
- `FPGA/scripts/build_pqm_soc.tcl`：综合、实现并导出Bitstream和HDF。
- `FPGA/scripts/check_pqm_soc_reports.ps1`：检查时序、资源和旧层级残留。
- `ARM/scripts/create_workspace.tcl`：根据HDF重建FreeRTOS工程。
- `ARM/scripts/build_boot_image.ps1`：生成FSBL和BOOT.bin。

## 生成结果

- `FPGA/export/pqm_soc.bit`
- `FPGA/export/pqm_soc.hdf`
- `ARM/sdk_workspace/pqm_freertos/Release/pqm_freertos.elf`
- `FPGA/ZYNQ固化脚本/BOOT.bin`

详细接口见`FPGA/doc/ps_pl_interface.md`，代码文件职责见
`docs/code_file_overview.md`。实际LCD、触摸和长时间恢复仍需目标板验收。
