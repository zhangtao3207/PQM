# PQM代码文件功能总览

更新时间：2026-07-20

本文用于快速说明PQM工程中项目自有代码的职责。第三方LVGL、Vivado生成工程、
SDK生成BSP、编译中间文件和早期MATLAB测试不在本文范围内。

## 1. 总体数据流

```text
AD7606采样
  -> PL时域/频域测量
  -> AXI BRAM标量与谐波 -> PS measurement任务 -> LVGL
  -> AXI4-Stream原始样本 -> AXI DMA -> PS dma_rx任务 -> 波形重采样 -> LVGL

LVGL RGB565双帧缓存 -> AXI VDMA -> RGB888转换 -> 800x480 LCD
触摸控制器 -> PS I2C/GPIO -> touch任务 -> LVGL输入
LVGL量程按钮 -> measurement任务 -> AXI BRAM命令 -> PL量程控制
```

## 2. ARM应用代码

### 2.1 应用入口和配置

| 文件 | 简要作用 |
|---|---|
| `ARM/app/src/main.c` | PS端程序入口；创建五个FreeRTOS静态任务、五个最新值队列，并协调DMA、触摸、测量、UI和系统监控。 |
| `ARM/app/src/lv_conf.h` | LVGL裁剪配置；规定RGB565、内存池、刷新周期、字体、断言和启用控件。 |

### 2.2 平台层

| 文件 | 简要作用 |
|---|---|
| `ARM/app/src/platform/pqm_platform.c` | 开启CPU缓存、绑定共享内存、校验PS/PL接口；致命错误时输出原因并启动看门狗复位。 |
| `ARM/app/src/platform/pqm_platform.h` | 平台层公开函数声明。 |

### 2.3 AXI共享内存驱动

| 文件 | 简要作用 |
|---|---|
| `ARM/app/src/drivers/pqm_axi/pqm_shared_memory_map.h` | 定义PS/PL共用ABI，包括字偏移、状态位、能力位、量程命令和谐波缓冲区布局。 |
| `ARM/app/src/drivers/pqm_axi/pqm_axi.c` | 校验ABI，一致性读取标量/谐波快照，发送命令并等待PL应答。 |
| `ARM/app/src/drivers/pqm_axi/pqm_axi.h` | AXI驱动对象、原始测量结构及公开接口声明。 |

### 2.4 DMA采样驱动

| 文件 | 简要作用 |
|---|---|
| `ARM/app/src/drivers/pqm_dma/pqm_dma.c` | 配置AXI DMA SG接收环和四个缓冲区；处理中断、缓存一致性、描述符回收和波形帧提交。 |
| `ARM/app/src/drivers/pqm_dma/pqm_dma.h` | DMA驱动状态结构、缓冲区数量及公开接口声明。 |

### 2.5 触摸驱动

| 文件 | 简要作用 |
|---|---|
| `ARM/app/src/drivers/pqm_touch/pqm_touch.c` | 使用PS I2C和GPIO访问FT/GT触摸控制器，处理复位、探测、中断、坐标读取和自动恢复。 |
| `ARM/app/src/drivers/pqm_touch/pqm_touch.h` | 触摸硬件对象和公开接口声明。 |
| `ARM/app/src/drivers/pqm_touch/pqm_touch_protocol.c` | 解析FT/GT数据包、转换800x480坐标，并实现连续失败恢复状态机。 |
| `ARM/app/src/drivers/pqm_touch/pqm_touch_protocol.h` | 触摸控制器类型、触点结构和故障状态定义。 |

### 2.6 视频驱动

| 文件 | 简要作用 |
|---|---|
| `ARM/app/src/drivers/pqm_video/pqm_video.c` | 配置AXI VDMA读通道，管理RGB565双帧缓存、park换帧、缓存清理和错误重启。 |
| `ARM/app/src/drivers/pqm_video/pqm_video.h` | LCD尺寸、帧缓存地址、颜色值、视频状态和公开接口声明。 |

### 2.7 测量和波形服务

| 文件 | 简要作用 |
|---|---|
| `ARM/app/src/services/measurement/pqm_measurement.c` | 把PL的乘100定点原始值转换为UI测量模型，处理有效位、范围限制、告警和文本格式。 |
| `ARM/app/src/services/measurement/pqm_measurement.h` | 测量字段、显示值结构和转换接口定义。 |
| `ARM/app/src/services/waveform/pqm_waveform.c` | 检查2048点DMA帧序号连续性，并重采样为400列电压/电流最小值和最大值包络。 |
| `ARM/app/src/services/waveform/pqm_waveform.h` | DMA采样格式、显示列结构和波形状态定义。 |

### 2.8 LVGL界面

| 文件 | 简要作用 |
|---|---|
| `ARM/app/src/ui/pqm_lvgl_port.c` | 将LVGL显示缓冲绑定到VDMA，将触摸点绑定到LVGL输入设备，并处理换帧超时。 |
| `ARM/app/src/ui/pqm_lvgl_port.h` | LVGL硬件适配层状态和公开接口声明。 |
| `ARM/app/src/ui/pqm_ui.c` | 界面总控；创建顶层页面和公共按钮，处理页面切换、冻结、告警和数据分发。 |
| `ARM/app/src/ui/pqm_ui.h` | UI对象、样式、图表缓存、页面状态和公开更新接口。 |
| `ARM/app/src/ui/pqm_ui_internal.h` | UI子模块内部接口，不供驱动和服务层使用。 |
| `ARM/app/src/ui/pqm_ui_style.c` | 初始化页面、面板、按钮、标题、正文和告警公共样式。 |
| `ARM/app/src/ui/pqm_ui_time.c` | 创建并刷新时域页面，显示RMS、峰峰值、频率、相位、波形和量程按钮。 |
| `ARM/app/src/ui/pqm_ui_frequency.c` | 创建并刷新频域页面，显示功率、THD以及分窗口谐波幅值和相位。 |

## 3. ARM脚本与测试

| 文件 | 简要作用 |
|---|---|
| `ARM/scripts/run_xsct.ps1` | 在固定Xilinx SDK 2018.3环境中调用XSCT脚本。 |
| `ARM/scripts/create_workspace.tcl` | 根据最新HDF重建FreeRTOS BSP和应用，并编译ELF。 |
| `ARM/scripts/build_boot_image.tcl` | 在SDK中创建并编译新的Zynq FSBL。 |
| `ARM/scripts/build_boot_image.ps1` | 串联FSBL、Bitstream和FreeRTOS ELF，调用Bootgen生成BOOT.bin。 |
| `ARM/tests/run_tests.ps1` | 编译并执行全部ARM主机单元测试。 |
| `ARM/tests/test_pqm_axi.c` | 测试共享内存校验、一致性读取、谐波双缓冲和命令应答。 |
| `ARM/tests/test_pqm_waveform.c` | 测试采样序号连续性、丢帧重同步和波形重采样。 |
| `ARM/tests/test_pqm_touch.c` | 测试FT/GT坐标解析、边界裁剪和故障恢复状态机。 |
| `ARM/tests/test_pqm_measurement.c` | 测试测量字段有效性、定点值转换和显示格式化。 |

## 4. FPGA顶层和PS接口

| 文件 | 简要作用 |
|---|---|
| `FPGA/rtl/main.v` | SoC顶层；连接AD7606测量核心、Zynq PS、DMA、VDMA、共享BRAM、LCD和触摸EMIO。 |
| `FPGA/rtl/pqm_legacy_core.v` | 保存原测量链和兼容PL显示路径，并向新PS接口导出样本、标量和谐波。 |
| `FPGA/rtl/DataProcessor/pqm_measurement_core.v` | 默认PS模式测量核心，不实例化PL字体、像素合成、触摸和显示UART。 |
| `FPGA/rtl/PSInterface/pqm_axis_sample_stream.v` | 将电压、电流和源序号封装为64位AXI4-Stream采样流。 |
| `FPGA/rtl/PSInterface/pqm_shared_memory_bridge.v` | 向AXI BRAM发布一致性标量、双缓冲谐波、运行计数和命令响应。 |
| `FPGA/rtl/PSInterface/pqm_range_command_controller.v` | 接收PS量程命令，原子切换PL换算档位并返回确认。 |
| `FPGA/rtl/PSInterface/pqm_axis_rgb565_to_rgb888.v` | 将VDMA的RGB565视频流扩展为LCD使用的RGB888。 |
| `FPGA/rtl/PSInterface/pqm_touch_iobuf.v` | 实例化触摸I2C双向缓冲，并映射复位、中断和按键GPIO。 |

完整RTL逐文件职责见`FPGA/doc/rtl_file_overview.md`。其中：

- `DataProcessor/BasicMath`保存乘法、除法、开方、取模和数位转换基础模块。
- `TimeAnalysis`完成RMS、峰峰值、频率、相位和功率测量。
- `FreqAnalysis`完成FFT适配、幅相计算、谐波统计、滤波和THD。
- `GraphicsLoad`和`lcd`仅服务于`LEGACY_PL_DISPLAY=1`兼容模式。
- `ADC_PARALLEL`负责AD7606转换和并行采样时序。

## 5. FPGA构建与验证脚本

| 文件 | 简要作用 |
|---|---|
| `FPGA/scripts/run_vivado.ps1` | 在固定Vivado环境中执行指定Tcl脚本。 |
| `FPGA/scripts/run_xsim.ps1` | 编译并运行PS接口相关RTL仿真。 |
| `FPGA/scripts/create_pqm_ps_bd.tcl` | 创建Zynq PS、AXI、DMA、VDMA、BRAM和中断Block Design。 |
| `FPGA/scripts/create_pqm_soc_project.tcl` | 从源码重新创建完整SoC工程。 |
| `FPGA/scripts/build_pqm_soc.tcl` | 执行综合、实现、Bitstream生成和HDF导出。 |
| `FPGA/scripts/check_pqm_ps_bd.tcl` | 检查Block Design中的接口、地址和连接。 |
| `FPGA/scripts/check_pqm_top_modes.tcl` | 分别检查默认PS模式和兼容PL模式顶层。 |
| `FPGA/scripts/check_pqm_soc_reports.ps1` | 检查WNS、LUT门限和默认模式中是否残留旧显示层级。 |
| `FPGA/scripts/check_freq_metrics_synth.tcl` | 对频域指标关键模块执行独立综合检查。 |
| `FPGA/scripts/vivado_synth_pre.tcl` | 处理Vivado 2018.3在受管理目录中的已知临时文件删除问题。 |

## 6. 生成文件

以下文件是构建结果，不应手工修改：

- `FPGA/export/pqm_soc.bit`：FPGA配置位流。
- `FPGA/export/pqm_soc.hdf`：PS软件使用的硬件描述。
- `ARM/sdk_workspace/pqm_freertos/Release/pqm_freertos.elf`：FreeRTOS程序。
- `FPGA/ZYNQ固化脚本/zynq_fsbl.elf`：一级启动程序。
- `FPGA/ZYNQ固化脚本/BOOT.bin`：FSBL、Bitstream和应用的启动镜像。
