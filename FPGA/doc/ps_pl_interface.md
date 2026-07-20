# PQM PS/PL 接口

更新时间：2026-07-20

## 职责边界

PL 保留 AD7606 采集、零点跟踪、时域测量、FFT、谐波统计、骤变告警以及确定性的 AXI 数据发布。PS 运行 FreeRTOS 10 与 LVGL 8.3.11，负责波形重采样、页面绘制、触摸、量程命令和系统监控。旧PL LCD、触摸、UART和文字格式化链路已从当前工程删除。

```text
AD7606 -> PL measurement/FFT -> AXI BRAM -> measurement task -> LVGL
       -> AXI4-Stream samples -> AXI DMA -> waveform task -> LVGL
PS DDR RGB565 framebuffer -> AXI VDMA -> RGB888 -> 800x480 LCD
PS I2C/GPIO EMIO -> touch controller
```

## AXI 地址

| 外设 | PS 地址 | 用途 |
|---|---:|---|
| AXI BRAM | `0x40000000` | 标量、谐波双 bank、命令与响应 |
| AXI DMA | `0x40400000` | PL 到 PS 的 64 位原始样本流，SG 接收 |
| AXI VDMA | `0x43000000` | PS DDR 到 LCD 的 RGB565 读通道 |
| framebuffer 0 | `0x3E000000` | 800x480 RGB565，768000 字节 |
| framebuffer 1 | `0x3E0BB800` | 800x480 RGB565，768000 字节 |

具体设备号和中断号由当前 HDF 生成的 `xparameters.h` 提供，软件不得硬编码中断向量。

## 原始样本流

`pqm_axis_sample_stream` 每个有效项为 64 位：

```text
bits 63:32  source_sequence
bits 31:16  current ADC code
bits 15:0   voltage ADC code
```

每 2048 个已接收样本产生一次 `TLAST`。DMA 反压时 PL 丢弃新显示样本并递增 `drop_count`，不会阻塞 ADC 或测量链。PS 使用 4 个 SG 描述符和 4 个 16 KiB、64 字节对齐的帧缓冲。

## 共享 BRAM ABI

下表地址均为相对 `0x40000000` 的 32 位 word offset；换算字节地址时左移 2 位。

| word 范围 | 内容 |
|---:|---|
| `0x0000..0x0005` | magic `PQM1`、ABI `0x00010000`、状态、快照序号、谐波代数、能力位 |
| `0x0010..0x001F` | 16 个标量：RMS、峰峰值、频率、相位、P/Q/S/PF、THD、DC、告警、有效位 |
| `0x0080..0x0084` | 命令码、参数、请求序号、响应、响应序号 |
| `0x00A0` | 样本丢弃计数 |
| `0x0400..` | 谐波 bank 0，501 项，每项 U/I/phase/flags 四个 word |
| `0x0C00..` | 谐波 bank 1，格式同 bank 0 |

标量采用“先写 16 个 payload word，最后写序号”的提交顺序。ARM 在读取前后比较序号。谐波采用双 bank，PL 写完非活动 bank 后再切换状态位和代数，ARM 在读取前后比较 bank、有效位与代数。

### 量程命令

命令 `0x00000001` 为 `SET_RANGE`，参数 `0` 表示 `350 V / 30 A`，参数 `1` 表示 `10 V / 3 A`。PL 成功时回显实际参数，非法命令或参数返回 `0xFFFFFFFF` 且保持原量程。ARM 只有收到匹配回显后才更新 LVGL 标签。

## FreeRTOS 所有权

| 任务 | 优先级关系 | 职责 |
|---|---|---|
| `dma_rx` | 最高 | AXI DMA ISR 通知、SG 回收、2048 点波形与 400 列 min/max 重采样 |
| `touch` | 次高 | I2C/GPIO EMIO 触摸服务与故障恢复 |
| `ui` | 中 | 唯一允许调用 LVGL 的任务；消费最新值队列并提交量程请求 |
| `measurement` | 次低 | 读取一致性标量/谐波快照，独占 BRAM 命令事务 |
| `system` | 最低 | 周期输出 DMA、VDMA、触摸运行计数 |

所有任务和队列均静态分配。测量、波形、谐波、量程请求与量程结果队列长度均为 1，使用覆盖写保持最新状态。

## 构建与验证

```powershell
powershell -ExecutionPolicy Bypass -File FPGA/scripts/run_xsim.ps1 -All
powershell -ExecutionPolicy Bypass -File ARM/tests/run_tests.ps1
powershell -ExecutionPolicy Bypass -File FPGA/scripts/run_vivado.ps1 -Script FPGA/scripts/create_pqm_soc_project.tcl
powershell -ExecutionPolicy Bypass -File ARM/scripts/run_xsct.ps1 -Script ARM/scripts/create_workspace.tcl
powershell -ExecutionPolicy Bypass -File ARM/scripts/build_boot_image.ps1
```

上板前还需校验 RGB 色序、VDMA 撕裂、触摸四角、量程实际换算和长时间错误计数。
