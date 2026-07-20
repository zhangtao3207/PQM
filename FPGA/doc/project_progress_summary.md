# PQM项目进度总结

更新时间：2026-07-20

## 项目目标

PQM使用Zynq-7020实现电能质量测量。PL负责确定性采集、测量和PS数据发布，
PS运行FreeRTOS与LVGL，负责800x480显示、触摸、量程命令和系统监控。

## 当前结构

```text
AD7606 -> pqm_pl_core -> 时域测量/FFT/谐波/告警
                      -> AXI4-Stream -> AXI DMA -> PS波形服务
                      -> AXI BRAM -> PS测量服务
PS DDR RGB565双帧缓存 -> AXI VDMA -> RGB888 -> LCD
PS I2C/GPIO EMIO -> 触摸控制器与按键
```

`rtl/main.v`是唯一SoC顶层，`rtl/pqm_pl_core.v`负责采集和测量，
`rtl/DataProcessor/pqm_measurement_core.v`负责标量、谐波和告警计算。

## 已完成

- AD7606八通道并行采集、超时检测和零点跟踪。
- RMS、峰峰值、频率、相位及`P/Q/S/PF`时域测量。
- FFT、0至500次谐波、THD、直流分量及相位差。
- AXI DMA 64位原始采样流和丢样计数。
- AXI BRAM一致性标量快照、谐波双缓冲和量程命令。
- FreeRTOS五任务、LVGL时域/频域页面、触摸和VDMA双缓冲。
- PS模式完整综合、实现、Bitstream、HDF、ELF、FSBL和BOOT.bin构建。
- 路由后WNS `+1.469 ns`，LUT使用率`36.03%`。

## 2026-07-20目录与RTL清理

- 旧完整工程保存到`C:/Users/zhangtao/Desktop/PQM/backup_pl`。
- 当前工程保存到`C:/Users/zhangtao/Desktop/PQM/project`。
- PL核心由`pqm_legacy_core`改名为`pqm_pl_core`。
- 删除`LEGACY_PL_DISPLAY`及所有兼容生成分支。
- 删除ARM已替代的PL LCD、触摸、UART、GraphicsLoad和文字格式化模块。
- 从旧Vivado工程提取四个必要XCI到`FPGA/ip`，约束移到`FPGA/data/PQM.xdc`。
- 从当前工程删除旧`FPGA/prj`副本，旧项目仍由`backup_pl`完整保存。

## 2026-07-20验证结果

- 重新创建Vivado SoC工程并完成综合、实现、Bitstream和HDF导出。
- 时序与资源门限检查通过：WNS `+1.469 ns`，LUT `19166`，使用率`36.03%`。
- 四项PS接口XSim仿真全部通过。
- 四项ARM主机单元测试全部通过。
- 使用最新HDF重新生成FreeRTOS ELF、FSBL和`BOOT.bin`。

## 当前待办

- 在目标板检查LCD色序、撕裂和刷新稳定性。
- 校准触摸四角并检查全部页面按钮。
- 验证350 V/30 A与10 V/3 A实际量程换算。
- 注入DMA、VDMA和触摸故障，检查自动恢复。
- 执行不少于30分钟的稳定运行测试。
