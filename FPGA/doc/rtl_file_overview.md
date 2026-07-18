# RTL 文件总览

更新时间：2026-04-23

## 文档职责

本文档只做 `rtl/` 目录下模块/文件的结构化总览，不再记录按日期展开的开发日志。

- 项目进度与历史变更请看 `doc/project_progress_summary.md`
- UART 协议请看 `doc/uart_measurement_stream_protocol.md`

## 顶层链路

```text
main
  -> ADC_PARALLEL
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

## 顶层

| 路径 | 模块 | 简要说明 |
|---|---|---|
| `rtl/main.v` | `main` | 系统顶层，连接 AD7606、时域/频域处理、LCD、触控、UART、`key0` 量程切换和 LED/蜂鸣器告警输出。 |

## ADC_PARALLEL

| 路径 | 模块 | 简要说明 |
|---|---|---|
| `rtl/ADC_PARALLEL/ad7606_parallel_ctrl.v` | `ad7606_parallel_ctrl` | AD7606 并行接口底层控制模块，负责转换启动、忙信号处理和并行读数时序。 |
| `rtl/ADC_PARALLEL/AD7606_Parallel_DRIVER.v` | `AD7606_Parallel_DRIVER` | AD7606 并行驱动封装，向上层提供多通道采样值、有效脉冲和状态信号。 |

## DataProcessor/BasicMath

| 路径 | 模块 | 简要说明 |
|---|---|---|
| `rtl/DataProcessor/BasicMath/divider_signed.v` | `divider_signed` | 有符号除法基础模块，供比例、角度和符号量计算复用。 |
| `rtl/DataProcessor/BasicMath/divider_unsigned.v` | `divider_unsigned` | 无符号除法基础模块，供百分比、频率和显示归一化计算复用。 |
| `rtl/DataProcessor/BasicMath/modulo_signed.v` | `modulo_signed` | 有符号取模模块，用于需要保留符号余数的数值规整场景。 |
| `rtl/DataProcessor/BasicMath/modulo_unsigned.v` | `modulo_unsigned` | 无符号取模模块，用于拆位和余数类计算。 |
| `rtl/DataProcessor/BasicMath/multiplier_signed.v` | `multiplier_signed` | 有符号乘法封装，统一项目中的乘法资源使用方式。 |
| `rtl/DataProcessor/BasicMath/signed_code_to_x100.v` | `signed_code_to_x100` | 将有符号采样码换算为 `x100` 量纲值。 |
| `rtl/DataProcessor/BasicMath/sqrt_unsigned.v` | `sqrt_unsigned` | 无符号开方模块，供 RMS 和幅值类计算复用。 |
| `rtl/DataProcessor/BasicMath/value_x100_to_digits.v` | `value_x100_to_digits` | 将 `x100` 数值拆成整数位和小数位，供显示链路使用。 |

## DataProcessor/SignalProcessing/TimeAnalysis/RawDataCal

| 路径 | 模块 | 简要说明 |
|---|---|---|
| `rtl/DataProcessor/SignalProcessing/TimeAnalysis/RawDataCal/cos_lookup_raw_x10000.v` | `cos_lookup_raw_x10000` | 余弦查表模块，辅助相位与功率相关运算。 |
| `rtl/DataProcessor/SignalProcessing/TimeAnalysis/RawDataCal/frequency_measure.v` | `frequency_measure` | 根据波形过零或周期信息测量频率。 |
| `rtl/DataProcessor/SignalProcessing/TimeAnalysis/RawDataCal/p2p_measure.v` | `p2p_measure` | 统计采样窗口内的峰峰值。 |
| `rtl/DataProcessor/SignalProcessing/TimeAnalysis/RawDataCal/phase_diff_calc.v` | `phase_diff_calc` | 计算电压与电流通道的时域相位差。 |
| `rtl/DataProcessor/SignalProcessing/TimeAnalysis/RawDataCal/power_metrics_calc.v` | `power_metrics_calc` | 根据 RMS、平均瞬时功率和相位信息计算 `P/Q/S/PF`。 |
| `rtl/DataProcessor/SignalProcessing/TimeAnalysis/RawDataCal/ui_rms_measure.v` | `ui_rms_measure` | 在统一采样窗口内累计 `u^2`、`i^2` 和 `ui`，输出真实时域 RMS 和平均有功 raw 值。 |

## DataProcessor/SignalProcessing/TimeAnalysis/DataReprocessor

| 路径 | 模块 | 简要说明 |
|---|---|---|
| `rtl/DataProcessor/SignalProcessing/TimeAnalysis/DataReprocessor/time_data_separator.v` | `time_data_separator` | 将时域 `x100` 指标拆成 LCD 文本显示需要的数字位与符号位。 |
| `rtl/DataProcessor/SignalProcessing/TimeAnalysis/DataReprocessor/time_parameters_initiator.v` | `time_parameters_initiator` | 组织时域测量调度，使 `p2p`、`phase`、`frequency`、`RMS` 和 `P/Q/S/PF` 在同窗采样结果上工作。 |
| `rtl/DataProcessor/SignalProcessing/TimeAnalysis/DataReprocessor/time_x100_normalizer.v` | `time_x100_normalizer` | 将时域 raw 测量值换算到 `x100` 显示量纲；当前已支持运行时量程输入。 |
| `rtl/DataProcessor/SignalProcessing/TimeAnalysis/DataReprocessor/time_zero_code_tracker.v` | `time_zero_code_tracker` | 跟踪电压/电流采样零点，供去直流与测量链路复用。 |

## DataProcessor/SignalProcessing/FreqAnalysis/BasicFunctions

| 路径 | 模块 | 简要说明 |
|---|---|---|
| `rtl/DataProcessor/SignalProcessing/FreqAnalysis/BasicFunctions/data_fifo.v` | `data_fifo` | 频域采样到 FFT 输入之间的 FIFO 缓冲模块。 |
| `rtl/DataProcessor/SignalProcessing/FreqAnalysis/BasicFunctions/fft_harmonic_stats.v` | `fft_harmonic_stats` | 以基波 bin 为参考统计谐波幅值、占比和总幅值。 |
| `rtl/DataProcessor/SignalProcessing/FreqAnalysis/BasicFunctions/fft_magnitude_calc.v` | `fft_magnitude_calc` | 根据 FFT 复数结果计算电压/电流幅值与平方和。 |
| `rtl/DataProcessor/SignalProcessing/FreqAnalysis/BasicFunctions/fft_phase_vector_calc.v` | `fft_phase_vector_calc` | 依据 U/I 复数频点生成 `atan2` 所需的 `dot/cross` 向量。 |
| `rtl/DataProcessor/SignalProcessing/FreqAnalysis/BasicFunctions/fft_result_receiver.v` | `fft_result_receiver` | 接收 FFT 输出并筛选后续分析所需的频点区间。 |
| `rtl/DataProcessor/SignalProcessing/FreqAnalysis/BasicFunctions/fft_stream_adapter.v` | `fft_stream_adapter` | 将 U/I 采样转换成 FFT IP 输入流，处理 FIFO、去零点和接口握手。 |
| `rtl/DataProcessor/SignalProcessing/FreqAnalysis/BasicFunctions/freq_analysis_top.v` | `freq_analysis_top` | 频域分析顶层，串接 FFT 输入、结果接收、谐波统计、相位计算和统一滤波输出。 |
| `rtl/DataProcessor/SignalProcessing/FreqAnalysis/BasicFunctions/phase_deg_lut_calc.v` | `phase_deg_lut_calc` | 通过查表把 `dot/cross` 结果转换为相位差角度。 |

## DataProcessor/SignalProcessing/FreqAnalysis/RawDataCal

| 路径 | 模块 | 简要说明 |
|---|---|---|
| `rtl/DataProcessor/SignalProcessing/FreqAnalysis/RawDataCal/fft_fundamental_freq_tracker.v` | `fft_fundamental_freq_tracker` | 跟踪 FFT 基波频率结果并做平滑。 |
| `rtl/DataProcessor/SignalProcessing/FreqAnalysis/RawDataCal/freq_harmonic_iir_filter.v` | `freq_harmonic_iir_filter` | 对频域谐波流做统一 IIR 平滑，作为后续频域模块的主谐波数据接口。 |
| `rtl/DataProcessor/SignalProcessing/FreqAnalysis/RawDataCal/freq_metrics_raw_calc.v` | `freq_metrics_raw_calc` | 从滤波后的谐波结果中提取 `THD`、基波幅值/相位、`DC` 等 raw 指标。 |
| `rtl/DataProcessor/SignalProcessing/FreqAnalysis/RawDataCal/freq_thd_raw_calc.v` | `freq_thd_raw_calc` | 计算电压/电流总谐波畸变率 raw 值。 |

## DataProcessor/SignalProcessing/FreqAnalysis/DataReprocessor

| 路径 | 模块 | 简要说明 |
|---|---|---|
| `rtl/DataProcessor/SignalProcessing/FreqAnalysis/DataReprocessor/freq_text_data_separator.v` | `freq_text_data_separator` | 将频域 `x100` 指标拆成 LCD 文本显示所需的数字位与符号位。 |
| `rtl/DataProcessor/SignalProcessing/FreqAnalysis/DataReprocessor/freq_text_x100_normalizer.v` | `freq_text_x100_normalizer` | 将频域 raw 指标规整到文本显示使用的 `x100` 范围。 |

## DataProcessor/SignalProcessing/FreqAnalysis

| 路径 | 模块 | 简要说明 |
|---|---|---|
| `rtl/DataProcessor/SignalProcessing/FreqAnalysis/fft_harmonic_result_buffer.v` | `fft_harmonic_result_buffer` | 缓存 `0..500` 次谐波结果，支持按阶次读取。 |

## DataProcessor/GraphicsLoad/TimeDomain

| 路径 | 模块 | 简要说明 |
|---|---|---|
| `rtl/DataProcessor/GraphicsLoad/TimeDomain/time_text_display_preprocess.v` | `time_text_display_preprocess` | 组织时域文本计算、规整、拆位和提交；当前也负责 sharp alarm 检测与量程切档后的基线处理。 |
| `rtl/DataProcessor/GraphicsLoad/TimeDomain/time_wave_display_capture.v` | `time_wave_display_capture` | 捕获时域波形显示帧并协调触发、冻结和显示 bank 切换。 |
| `rtl/DataProcessor/GraphicsLoad/TimeDomain/time_wave_display_resampler.v` | `time_wave_display_resampler` | 将采样点重采样为 LCD 波形宽度对应的数据并换算屏幕 `Y` 坐标。 |
| `rtl/DataProcessor/GraphicsLoad/TimeDomain/time_wave_frame_writer.v` | `time_wave_frame_writer` | 将重采样后的时域波形写入显示 RAM。 |
| `rtl/DataProcessor/GraphicsLoad/TimeDomain/time_wave_history_buffer.v` | `time_wave_history_buffer` | 缓存时域采样历史，为触发显示提供前后样本。 |
| `rtl/DataProcessor/GraphicsLoad/TimeDomain/time_wave_trigger_core.v` | `time_wave_trigger_core` | 时域波形触发核心，检测触发点并给出显示快照位置。 |

## DataProcessor/GraphicsLoad/FreqDomain

| 路径 | 模块 | 简要说明 |
|---|---|---|
| `rtl/DataProcessor/GraphicsLoad/FreqDomain/freq_display_adapter.v` | `freq_display_adapter` | 将滤波后的谐波幅值占比和相位角转换为 LCD 频谱/相位柱图高度。 |
| `rtl/DataProcessor/GraphicsLoad/FreqDomain/freq_text_display_preprocess.v` | `freq_text_display_preprocess` | 组织频域文本指标的规整、拆位和 LCD 文本提交。 |

## lcd/display

| 路径 | 模块 | 简要说明 |
|---|---|---|
| `rtl/lcd/display/binary2bcd.v` | `binary2bcd` | 二进制到 BCD 转换模块，供触控坐标等数字显示使用。 |
| `rtl/lcd/display/clk_div.v` | `clk_div` | LCD 相关时钟分频模块。 |
| `rtl/lcd/display/lcd_display.v` | `lcd_display` | LCD 显示主模块，整合背景、文本、波形、频谱、双缓冲、告警和 UART 测量串流。 |
| `rtl/lcd/display/lcd_display_bg.v` | `lcd_display_bg` | 绘制页面背景、按钮和基础色块区域。 |
| `rtl/lcd/display/lcd_display_text.v` | `lcd_display_text` | 绘制时域/频域文本、按钮文字、告警文本和纵轴刻度。 |
| `rtl/lcd/display/lcd_driver.v` | `lcd_driver` | 生成 LCD 行场同步、数据使能、像素坐标和 RGB 时序。 |
| `rtl/lcd/display/lcd_rgb_char.v` | `lcd_rgb_char` | LCD 显示封装模块，连接像素时钟、ID 识别、显示内容与顶层接口。 |
| `rtl/lcd/display/rd_id.v` | `rd_id` | LCD ID 读取/识别辅助模块。 |
| `rtl/lcd/display/text_packet_double_buffer.v` | `text_packet_double_buffer` | 跨时钟域文本数据双缓冲，支持 LCD 前台稳定显示和冻结锁存。 |
| `rtl/lcd/display/wave_pixel_detector.v` | `wave_pixel_detector` | 根据波形 RAM 数据判断当前像素是否落在波形线上。 |

## lcd/touch

| 路径 | 模块 | 简要说明 |
|---|---|---|
| `rtl/lcd/touch/i2c_dri.v` | `i2c_dri` | 触控芯片 I2C 底层驱动。 |
| `rtl/lcd/touch/touch_dri.v` | `touch_dri` | 触控数据读取驱动，解析坐标和触摸状态。 |
| `rtl/lcd/touch/touch_state.v` | `touch_state` | 将触控坐标转换成页面按钮、冻结和谐波切换等事件。 |
| `rtl/lcd/touch/touch_top.v` | `touch_top` | 触控模块顶层，封装 I2C、触摸读取和状态输出。 |

## uart

| 路径 | 模块 | 简要说明 |
|---|---|---|
| `rtl/uart/uart.v` | `uart` | UART 顶层封装，整合收发子模块。 |
| `rtl/uart/uart_measurement_streamer.v` | `uart_measurement_streamer` | 复用显示链路快照与完整谐波帧，按固定 ASCII 协议输出 `p2p/rms/pa/p/THD/Mag/Ph` 七行串口文本。 |
| `rtl/uart/uart_rx.v` | `uart_rx` | UART 接收模块。 |
| `rtl/uart/uart_tx.v` | `uart_tx` | UART 发送模块，当前配置为 `115200 8N1`。 |

## 维护规则

1. 新增或删除 `rtl/` 模块时，只在本文档增删对应条目。
2. 条目说明应聚焦模块职责，不要写按日期展开的开发日志。
3. 版本演进、变更原因、验证记录统一写入 `doc/project_progress_summary.md`。
