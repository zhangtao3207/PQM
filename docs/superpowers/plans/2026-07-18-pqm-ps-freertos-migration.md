# PQM PS端FreeRTOS显示迁移实施计划

> 本文记录迁移任务、涉及文件和验证方法。代码实施项已经完成，未勾选项需要
> 在目标开发板上执行。

**目标：** 将波形、LCD和触摸等非确定性显示工作迁移到Zynq PS端，在保持
PL测量链的前提下降低FPGA资源占用。

**技术组成：** Verilog、Vivado 2018.3、Zynq-7000、AXI DMA、AXI VDMA、
FreeRTOS 10、C语言和LVGL 8.3.11。

## 文件范围

- `FPGA/rtl/main.v`：SoC顶层和新旧模式选择。
- `FPGA/rtl/pqm_legacy_core.v`：原PL功能及兼容显示路径。
- `FPGA/rtl/DataProcessor/pqm_measurement_core.v`：默认PS模式测量核心。
- `FPGA/rtl/PSInterface`：PS/PL流、共享内存、量程和视频接口。
- `ARM/app/src`：FreeRTOS应用、驱动、服务和LVGL界面。
- `FPGA/scripts`：Vivado工程、仿真和报告门限检查。
- `ARM/scripts`：SDK工作区、FSBL和BOOT.bin生成。

## 任务1：固定可重复构建入口

- [x] 记录Vivado和SDK 2018.3固定安装位置。
- [x] 增加PowerShell包装脚本，统一批处理环境。
- [x] 将生成工程、报告、SDK工作区和测试输出加入忽略规则。
- [x] 保证脚本从仓库根目录或工作树目录均可运行。

验证：

```powershell
powershell -ExecutionPolicy Bypass -File FPGA/scripts/run_vivado.ps1 -Script FPGA/scripts/create_pqm_soc_project.tcl
```

## 任务2：创建Zynq PS硬件设计

- [x] 配置Cortex-A9核0、DDR3和固定PS时钟。
- [x] 建立AXI BRAM、AXI DMA、AXI VDMA和中断连接。
- [x] 通过I2C/GPIO EMIO引出触摸接口。
- [x] 从Vivado导出`pqm_soc.hdf`。

主要文件：

- `FPGA/scripts/create_pqm_soc_project.tcl`
- `FPGA/scripts/create_pqm_soc_bd.tcl`

## 任务3：建立原始样本AXI流

- [x] 将电压、电流和源序号封装为64位AXI4-Stream。
- [x] 每2048个样本产生一次`TLAST`。
- [x] DMA反压时丢弃显示样本，不反压ADC和测量链。
- [x] 增加丢弃计数和独立仿真。

主要文件：

- `FPGA/rtl/PSInterface/pqm_axis_sample_stream.v`
- `FPGA/sim/PSInterface/tb_pqm_axis_sample_stream.v`

## 任务4：建立共享内存ABI

- [x] 固定魔数、版本、能力位和字偏移。
- [x] 标量采用“负载先写、序号后写”的提交顺序。
- [x] 谐波采用双缓冲和代数检查。
- [x] 增加PS命令与PL响应区域。
- [x] 在C和Verilog两侧保持同一套常量。

主要文件：

- `FPGA/rtl/PSInterface/pqm_shared_memory_bridge.v`
- `ARM/app/src/drivers/pqm_axi/pqm_shared_memory_map.h`
- `ARM/app/src/drivers/pqm_axi/pqm_axi.c`

## 任务5：建立LCD视频通路

- [x] 配置两个800x480 RGB565 DDR帧缓存。
- [x] VDMA以park模式读取当前前台缓冲区。
- [x] 增加RGB565到RGB888转换和反压保持。
- [x] 增加帧完成、错误计数和100 ms恢复路径。

主要文件：

- `FPGA/rtl/PSInterface/pqm_axis_rgb565_to_rgb888.v`
- `ARM/app/src/drivers/pqm_video/pqm_video.c`
- `ARM/app/src/ui/pqm_lvgl_port.c`

## 任务6：拆分PL测量与显示

- [x] 将原顶层整理为`pqm_legacy_core`。
- [x] 新增不包含字体、像素和触摸显示逻辑的`pqm_measurement_core`。
- [x] 默认`LEGACY_PL_DISPLAY=0`，仅保留PS所需输出。
- [x] 保留`LEGACY_PL_DISPLAY=1`兼容路径。
- [x] 流水化功率归一化关键乘法路径。

结果：默认PS模式LUT使用率为36.03%，路由后WNS为`+0.929 ns`。

## 任务7：建立FreeRTOS应用骨架

- [x] 从HDF自动创建FreeRTOS BSP和应用。
- [x] 使用静态任务、静态栈和静态队列。
- [x] 建立`dma_rx`、`touch`、`ui`、`measurement`和`system`任务。
- [x] 规定只有`ui`任务能够调用LVGL。
- [x] 构建`pqm_freertos.elf`。

主要文件：

- `ARM/app/src/main.c`
- `ARM/app/src/platform/pqm_platform.c`
- `ARM/scripts/create_workspace.tcl`

## 任务8：实现DMA接收与波形重采样

- [x] 创建四个SG描述符和四个16 KiB对齐缓冲区。
- [x] 在中断中只确认状态并通知任务。
- [x] 在任务中执行缓存失效、帧检查和描述符回收。
- [x] 检测样本序号间断并重新建立锚点。
- [x] 将2048点压缩为400列最小值/最大值包络。

主要文件：

- `ARM/app/src/drivers/pqm_dma/pqm_dma.c`
- `ARM/app/src/services/waveform/pqm_waveform.c`

## 任务9：移植触摸控制

- [x] 支持FT `0x38`和GT `0x14`控制器。
- [x] 配置GPIO54复位和GPIO55下降沿中断。
- [x] 将坐标限制在800x480范围。
- [x] 连续三次I2C失败后进入500 ms重试恢复。
- [x] 将最新触点接入LVGL输入设备。

主要文件：

- `ARM/app/src/drivers/pqm_touch/pqm_touch.c`
- `ARM/app/src/drivers/pqm_touch/pqm_touch_protocol.c`

## 任务10：移植时域和频域页面

- [x] 实现时域RMS、峰峰值、频率、相位及双通道波形。
- [x] 实现P/Q/S/PF、THD和谐波幅相显示。
- [x] 实现页面切换和冻结。
- [x] 实现高低量程请求及PL回显确认。
- [x] 对每个测量字段执行有效位检查。

主要文件：

- `ARM/app/src/ui/pqm_ui.c`
- `ARM/app/src/ui/pqm_ui_time.c`
- `ARM/app/src/ui/pqm_ui_frequency.c`

## 任务11：自动验证与交付文件

- [x] 四项RTL仿真通过。
- [x] 四组ARM主机测试通过。
- [x] Vivado综合、实现和Bitstream生成成功。
- [x] 时序与资源门限脚本通过。
- [x] 使用最新HDF重建FreeRTOS ELF。
- [x] 生成新FSBL和`BOOT.bin`。

验证命令：

```powershell
powershell -ExecutionPolicy Bypass -File FPGA/scripts/run_xsim.ps1 -All
powershell -ExecutionPolicy Bypass -File ARM/tests/run_tests.ps1
powershell -ExecutionPolicy Bypass -File FPGA/scripts/check_pqm_soc_reports.ps1
powershell -ExecutionPolicy Bypass -File ARM/scripts/build_boot_image.ps1
```

## 任务12：开发板验收

- [ ] 检查LCD RGB色序、完整画面、刷新率和撕裂。
- [ ] 检查触摸四角坐标及全部页面按钮。
- [ ] 检查350 V/30 A与10 V/3 A实际量程换算。
- [ ] 注入DMA、VDMA和触摸故障并确认自动恢复。
- [ ] 执行至少30分钟稳定运行测试。
- [ ] 根据最终启动方式写入SD卡或QSPI。

## 完成判定

代码侧完成判定为：测试通过、Vivado时序收敛、资源低于门限、ELF和BOOT.bin
可重复生成。产品侧完成判定还需要任务12全部通过，并记录开发板型号、Bitstream
版本、测试时间和异常计数。
