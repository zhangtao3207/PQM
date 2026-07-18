# PQM 项目进度总结

更新时间：2026-04-23

## 文档职责

本文档只记录项目目标、当前状态、里程碑更新、已知问题和后续建议。模块/文件级说明请看 `doc/rtl_file_overview.md`，UART 协议请看 `doc/uart_measurement_stream_protocol.md`。

## 项目目标

PQM 当前 RTL 的目标是基于 FPGA 实现电能质量测量链路。系统从 AD7606 并行 ADC 获取电压、电流采样，完成时域测量、频域分析、波形/频谱显示、触控交互以及 UART 数据输出。当前工程使用 Vivado 2018.3，工程文件为 `prj/PQM.xpr`，器件目标为 `xc7z020clg400-2`。

## 当前总体结构

```text
AD7606 ADC
  -> rtl/main.v
  -> DataProcessor
     -> TimeAnalysis
     -> FreqAnalysis
  -> GraphicsLoad
     -> TimeDomain
     -> FreqDomain
  -> lcd/display
  -> lcd/touch
  -> uart
```

`rtl/main.v` 是系统顶层，负责连接 ADC、测量处理、LCD、触控、告警和 UART。

## 当前状态

ADC 与顶层集成方面，当前已经具备 AD7606 并行采样控制与驱动链路；`main.v` 已连接主采样、显示、串口和告警输出；`key0` 现在可以在运行时切换两组时域量程。

时域分析方面，当前已经实现电压/电流零点跟踪、真 RMS、峰峰值、频率、相位差以及 `P/Q/S/PF` 计算，也已经完成 `raw -> x100 -> 数字位` 的显示预处理链路，并具备时域波形缓存、触发、重采样显示和 sharp rise/drop 告警机制。

频域分析方面，当前已经实现 ADC 采样到 FFT 输入的流适配、FFT 结果接收、幅值计算、相位向量计算、相位角换算，以及 `0..500` 次谐波统计和统一 IIR 滤波。`THD_U`、`THD_I`、`U1_Mag`、`I1_Mag`、`Phase1`、`DC_U`、`DC_I` 等频域指标已经接入显示链路。

LCD 与交互方面，当前已经实现 LCD 驱动、背景、文本层、波形层和频谱层，支持文本双缓冲、`freeze` 显示锁存、触控页面切换、冻结、谐波窗口切换，以及量程切换后的纵轴刻度同步刷新。

UART 输出方面，当前 UART 已经改回 ASCII 文本协议，不再发送二进制帧。串口参数仍为 `115200 8N1`。发送内容固定为 `p2p`、`rms`、`pa`、`p`、`THD`、`Mag`、`Ph` 七行。其中 `Mag` 行按 `1..500` 次谐波输出 U/I 幅值占比对，`Ph` 行按 `1..500` 次谐波输出 U-I 相位差。发送起点被约束为“完整谐波帧 + 已提交的文本快照”同时就绪之后。

## 里程碑更新

2026-04-18：完成文本处理资源优化，将 `time_data_separator`、`freq_text_data_separator` 从多实例并行拆位改为串行复用比较/减法链路，并把 `freq_text_x100_normalizer` 调整为串行字段规整，目的是缓解此前文本链路带来的 LUT 和切片压力。

2026-04-19：完成字体与频域显示链路整理，统一了 `10x20` 字库读取口径，修正部分字符显示错位，恢复 `%` 字符兼容处理，新增 DH 列表显示链路，并把频域文本刷新改为按 `lcd_frame_done_toggle` 节拍提交。频域统一谐波 IIR 平滑系数也在这一阶段从 `1/8` 调整为 `1/16`。

2026-04-20：完成 AC-only 输入、告警与 UART 初版。时域/频域链路改回基于动态 `zero_code` 去直流；时域显示量程更新为 `350.00V / 30.00A`；补齐 `U/I RMS`、`Upp/Ipp`、`P/Q/S` 百位显示；新增 sharp rise/drop 告警；UART 初版曾短暂采用 ASCII 文本流格式。

2026-04-21：UART 发送逻辑曾迁移为二进制帧版本。该阶段的 `uart_measurement_streamer.v` 使用帧头、长度、摘要区、`0..50` 次谐波表和 8 bit 累加和校验，旧版 `Dominant Harmonics U/I` 文本串口输出逻辑在这一阶段被二进制谐波表替代。

2026-04-21：完成时域波形居中修正。`lcd_display.v` 中用于波形显示的 `WAVE_FULL_SCALE_CODE` 恢复为 `32767`，`time_wave_display_capture.v` 的显示中心改为复用触发链路内部的慢速中心跟踪结果，从而减少复位后或零点刚建立时整条波形突跳的问题。

2026-04-23：完成 `key0` 运行时切量程。`main.v` 新增 `key0` 去抖和按下沿切换逻辑，默认量程为 `350.00V / 30.00A`，按键后切到 `10.00V / 3.00A`，再次按下切回。`time_x100_normalizer.v` 从编译期常量改为运行时输入，`time_text_display_preprocess.v` 在切档时清空 sharp alarm 的 RMS 基线，`lcd_display.v` 和 `lcd_display_text.v` 也已接入当前档位状态。

2026-04-23：完成 UART ASCII 协议重构。`uart_measurement_streamer.v` 从二进制帧发送重新改为 ASCII 文本发送；新协议固定输出 `p2p`、`rms`、`pa`、`p`、`THD`、`Mag`、`Ph` 七行；`Mag` 行扩展为 `1..500` 次谐波的 U/I 幅值占比对，总计 `1000` 个值；`Ph` 行扩展为 `1..500` 次谐波相位差，总计 `500` 个值；发送起点也调整为“完整谐波帧 + 已提交文本快照”。

2026-07-19：启动 Zynq PS/PL 重构。新增可由 Vivado 2018.3 批处理重建的 PS Block Design，固定 DDR、AXI BRAM、DMA、VDMA、800x480 视频和中断连接；新增 `pqm_axis_sample_stream`，以 64 位 `{序号, 电流, 电压}` 数据项向 PS 发送原始样本，DMA 反压时丢弃显示样本但不阻塞 ADC 与测量链路；新增 C/Verilog 共用的共享内存 ABI 与 `pqm_shared_memory_bridge`，按“负载先写、序号后写”发布标量和谐波代数。

## 当前已知问题

当前已确认 Vivado/XSim 2018.3 位于 `D:/zt/Xilinx`，PS Block Design 和新增 PS 接口 RTL 均使用仓库脚本执行本地检查。完整 SoC 综合与上板验证仍需在顶层集成完成后执行。

当前 UART ASCII 整包大约 `11610` 字节，在线发送时间约 `1.01 s`，发送周期明显长于旧二进制版本。

`doc/uart_measurement_stream_protocol.html` 仍是旧版二进制说明页，本轮只同步了 Markdown 文档。

## 后续建议

建议在有 Vivado 环境的机器上重新跑一次语法检查和综合，确认新的 ASCII 串口状态机没有引入时序问题。

建议上位机解析改为按 `\r\n` 分行、按逗号拆字段，不要再按 `55 AA` 二进制帧解析。

如果后续发现 1 秒级整包发送周期过长，可以再考虑做分页发送、命令触发发送或裁剪 `Mag/Ph` 输出规模。

