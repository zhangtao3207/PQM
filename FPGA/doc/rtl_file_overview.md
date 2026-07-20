# RTL文件总览

更新时间：2026-07-20

本文只列出当前ARM/FreeRTOS工程实际保留的RTL。旧PL显示工程请查看同级
`backup_pl`目录。

## 顶层

| 路径 | 模块 | 作用 |
|---|---|---|
| `rtl/main.v` | `main` | SoC顶层，连接PL测量、Zynq PS、DMA、VDMA、共享BRAM、LCD和触摸EMIO。 |
| `rtl/pqm_pl_core.v` | `pqm_pl_core` | AD7606采集、零点跟踪、测量调度、告警和PS数据导出。 |
| `rtl/DataProcessor/pqm_measurement_core.v` | `pqm_measurement_core` | 生成标量快照、谐波流、THD、直流分量和骤变告警。 |

## AD7606采集

| 路径 | 模块 | 作用 |
|---|---|---|
| `rtl/ADC_PARALLEL/ad7606_parallel_ctrl.v` | `ad7606_parallel_ctrl` | 产生转换、复位、片选和并行读取时序。 |
| `rtl/ADC_PARALLEL/AD7606_Parallel_DRIVER.v` | `AD7606_Parallel_DRIVER` | 封装八通道并行采样并输出帧有效和超时状态。 |

## 基础数学模块

| 路径 | 模块 | 作用 |
|---|---|---|
| `rtl/DataProcessor/BasicMath/divider_signed.v` | `divider_signed` | 有符号迭代除法。 |
| `rtl/DataProcessor/BasicMath/divider_unsigned.v` | `divider_unsigned` | 无符号迭代除法。 |
| `rtl/DataProcessor/BasicMath/multiplier_signed.v` | `multiplier_signed` | 统一的有符号乘法封装。 |
| `rtl/DataProcessor/BasicMath/signed_code_to_x100.v` | `signed_code_to_x100` | 将采样码换算为乘100工程量。 |
| `rtl/DataProcessor/BasicMath/sqrt_unsigned.v` | `sqrt_unsigned` | 无符号迭代开方。 |

## 时域分析

| 路径 | 模块 | 作用 |
|---|---|---|
| `rtl/DataProcessor/SignalProcessing/TimeAnalysis/RawDataCal/ui_rms_measure.v` | `ui_rms_measure` | 同窗累计电压、电流平方和及瞬时功率。 |
| `rtl/DataProcessor/SignalProcessing/TimeAnalysis/RawDataCal/p2p_measure.v` | `p2p_measure` | 测量采样窗口峰峰值。 |
| `rtl/DataProcessor/SignalProcessing/TimeAnalysis/RawDataCal/frequency_measure.v` | `frequency_measure` | 根据过零周期测量频率。 |
| `rtl/DataProcessor/SignalProcessing/TimeAnalysis/RawDataCal/phase_diff_calc.v` | `phase_diff_calc` | 计算电压和电流时域相位差。 |
| `rtl/DataProcessor/SignalProcessing/TimeAnalysis/RawDataCal/power_metrics_calc.v` | `power_metrics_calc` | 计算有功、无功、视在功率和功率因数。 |
| `rtl/DataProcessor/SignalProcessing/TimeAnalysis/DataReprocessor/time_zero_code_tracker.v` | `time_zero_code_tracker` | 跟踪采样零点。 |
| `rtl/DataProcessor/SignalProcessing/TimeAnalysis/DataReprocessor/time_parameters_initiator.v` | `time_parameters_initiator` | 调度同一采样窗口内的各项时域测量。 |
| `rtl/DataProcessor/SignalProcessing/TimeAnalysis/DataReprocessor/time_x100_normalizer.v` | `time_x100_normalizer` | 将原始结果换算为乘100工程量。 |

## 频域分析

| 路径 | 模块 | 作用 |
|---|---|---|
| `rtl/DataProcessor/SignalProcessing/FreqAnalysis/BasicFunctions/data_fifo.v` | `data_fifo` | 缓冲FFT输入样本和帧标志。 |
| `rtl/DataProcessor/SignalProcessing/FreqAnalysis/BasicFunctions/fft_stream_adapter.v` | `fft_stream_adapter` | 将电压/电流样本组织为FFT AXI流。 |
| `rtl/DataProcessor/SignalProcessing/FreqAnalysis/BasicFunctions/fft_result_receiver.v` | `fft_result_receiver` | 接收和筛选FFT输出频点。 |
| `rtl/DataProcessor/SignalProcessing/FreqAnalysis/BasicFunctions/fft_magnitude_calc.v` | `fft_magnitude_calc` | 计算复数频点幅值。 |
| `rtl/DataProcessor/SignalProcessing/FreqAnalysis/BasicFunctions/fft_harmonic_stats.v` | `fft_harmonic_stats` | 统计谐波阶次、幅值和占比。 |
| `rtl/DataProcessor/SignalProcessing/FreqAnalysis/BasicFunctions/fft_phase_vector_calc.v` | `fft_phase_vector_calc` | 生成相位差计算使用的点积和叉积。 |
| `rtl/DataProcessor/SignalProcessing/FreqAnalysis/BasicFunctions/phase_deg_lut_calc.v` | `phase_deg_lut_calc` | 查表计算相位差角度。 |
| `rtl/DataProcessor/SignalProcessing/FreqAnalysis/BasicFunctions/freq_analysis_top.v` | `freq_analysis_top` | 串接FFT、谐波和相位分析链。 |
| `rtl/DataProcessor/SignalProcessing/FreqAnalysis/RawDataCal/fft_fundamental_freq_tracker.v` | `fft_fundamental_freq_tracker` | 跟踪和平滑FFT基波频率。 |
| `rtl/DataProcessor/SignalProcessing/FreqAnalysis/RawDataCal/freq_harmonic_iir_filter.v` | `freq_harmonic_iir_filter` | 对谐波幅相流进行IIR平滑。 |
| `rtl/DataProcessor/SignalProcessing/FreqAnalysis/RawDataCal/freq_thd_raw_calc.v` | `freq_thd_raw_calc` | 计算电压和电流THD。 |
| `rtl/DataProcessor/SignalProcessing/FreqAnalysis/RawDataCal/freq_metrics_raw_calc.v` | `freq_metrics_raw_calc` | 聚合THD、基波相位和直流分量。 |

## PS接口

| 路径 | 模块 | 作用 |
|---|---|---|
| `rtl/PSInterface/pqm_axis_sample_stream.v` | `pqm_axis_sample_stream` | 发布64位原始样本AXI流并统计丢样。 |
| `rtl/PSInterface/pqm_shared_memory_bridge.v` | `pqm_shared_memory_bridge` | 发布一致性标量、双缓冲谐波和命令响应。 |
| `rtl/PSInterface/pqm_range_command_controller.v` | `pqm_range_command_controller` | 执行PS高低量程命令并回显状态。 |
| `rtl/PSInterface/pqm_axis_rgb565_to_rgb888.v` | `pqm_axis_rgb565_to_rgb888` | 将VDMA RGB565视频扩展为LCD RGB888。 |
| `rtl/PSInterface/pqm_touch_iobuf.v` | `pqm_touch_iobuf` | 连接PS I2C/GPIO EMIO与触摸和按键物理引脚。 |

## 维护规则

1. 每个Verilog文件只定义一个模块。
2. 算术模块优先复用`BasicMath`，不得直接新增`/`、`*`或`%`运算。
3. 新增、删除或重命名模块时同步更新本文。
4. PL不再增加LCD绘制、触摸协议、页面控制或测量UART逻辑。
