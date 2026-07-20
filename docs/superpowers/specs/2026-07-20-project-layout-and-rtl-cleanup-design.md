# PQM双项目目录与RTL清理设计

日期：2026-07-20

## 目标

将旧PL工程完整保存在`C:/Users/zhangtao/Desktop/PQM/backup_pl`，将当前
PS/FreeRTOS工程保存在`C:/Users/zhangtao/Desktop/PQM/project`。新工程不再
保留ARM已经替代的PL显示、触摸、UART和文字格式化逻辑。

## 目录边界

- `backup_pl`保持`main`分支和旧Vivado工程，不做RTL删减。
- `project`保持`codex/ps-freertos-migration`分支，作为后续唯一开发工程。
- 两个目录继续共享同一个Git对象数据库，但各自有独立工作树和分支。
- LVGL子模块固定在`project/ARM/third_party/lvgl`。

## 新工程保留内容

- AD7606采集与PL时钟。
- 时域RMS、峰峰值、频率、相位和功率测量。
- FFT、谐波、THD、直流分量及告警。
- AXI DMA采样流、AXI BRAM共享内存、量程命令。
- VDMA视频格式转换和PS触摸IOBUF。
- ARM FreeRTOS、LVGL、驱动、服务、测试和启动脚本。

## 新工程删除内容

- `LEGACY_PL_DISPLAY`参数及全部兼容分支。
- `FPGA/rtl/lcd`纯PL LCD和触摸代码。
- `FPGA/rtl/uart`纯PL测量串口代码。
- `DataProcessor/GraphicsLoad`显示预处理和波形绘制代码。
- 只为PL文字显示服务的拆位、格式化、取模和旧谐波缓存模块。
- 新工程中的旧Vivado目录`FPGA/prj`。
- 双模式综合脚本和旧PL UART协议文档。

## IP与约束

新工程不能依赖`backup_pl`路径。需要从旧Vivado工程提取并保留：

- `clk_wiz_0`
- `blk_mem_gen_fft_fifo_ram`
- `xfft_0`
- `rom_atan_lut_1024`
- `PQM.xdc`

IP配置放在`FPGA/ip`，约束放在`FPGA/data/PQM.xdc`。SoC创建脚本只从
这些新位置读取文件。

## 验证

清理完成后必须通过：

- Verilog模块依赖扫描，不允许引用已删除模块。
- 四项PS接口XSim测试。
- ARM四组主机测试。
- Vivado完整综合、实现、时序门限、Bitstream和HDF导出。
- 最新HDF对应的FreeRTOS ELF重新编译。
- 文档与实际文件路径一致性检查。
