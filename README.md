# PQM2

PQM 的重建工程：以正点原子官方例程 `37_zynq_lvgl` 为**硬件与板级驱动基线**，PS 界面按旧工程 `../PQM` 的规格严格等价重实现，PL 端是**自研测量链**（频域不再用 xfft）。不复用旧工程的代码结构。

## 硬约束

1. 旧工程 `C:\Users\zhangtao\Desktop\PQM` **只读参考**，不修改；当前工程是 `C:\Users\zhangtao\Desktop\PQM2`。
2. 另外三个只读目录：`C:\Users\zhangtao\Desktop\B-20260803`、`C:\Users\zhangtao\Desktop\zynq7020-examples`、`D:\zt\DeepSeek-Harness`。
3. PS 界面按**严格像素级等价**翻译旧界面：只改代码层面，画面不动。用户明确指定的可见改动除外（例如模拟市电倍率带来的纵轴刻度与量程按钮文案）。
4. 数值正确性靠**仿真**证明，不拿板上的数当验收 —— 信号源可换、波形由用户控制。

## 与旧工程的边界

旧工程 `../PQM` 的 PS 端整体绑定在它自己的 PL 硬件清单上（共享 BRAM、AXI DMA、16 位双缓冲 VDMA），无法直接搬到本工程使用的比特流上。因此本工程只把旧工程的界面当作**设计规格**：布局、配色、交互行为要求等价，C 代码全部按官方例程的结构与风格重写。

旧工程里 `../PQM/ARM/export/fb0.png`（旧界面真实帧缓存还原图）是本工程界面等价性的对照基准。

## 目录

`app/` 的层级与官方例程的 `src/` 保持一致，便于与上游比对。

| 路径 | 内容 | 是否可改 |
| --- | --- | --- |
| `hw/system_wrapper.xsa` | 官方只读基线的硬件描述（2026-09-02，**只有视频段、不含测量链**）；测量版不走它，见 `vivado/` | 只读基线 |
| `app/display_ctrl/` `vdma_api/` `clk_wiz/` `timer/` `TOUCH/` `emio_iic_cfg/` `APP/` | 官方板级驱动，原文件、原编码 | 只读基线 |
| `app/LVGL/GUI/lvgl/` | 官方自带的 LVGL 8.2.0（`src` + `lvgl.h` + `lv_conf.h`） | 只读基线 |
| `app/port/` | LVGL 到板级的显示与触摸适配层 | 可改 |
| `app/pqmshm/` | **数据源**：读 PS/PL 共享内存 `0x40000000`；ABI 宏在 `pqm_shared_memory_map.h` | 可改 |
| `app/pqmui/` | 界面层：页面总控、时域页、频域页、样式、工程量格式化与模拟市电换算 | 可改 |
| `app/main.c` `app/main.h` | 应用入口与全局声明 | 可改 |
| `pl/rtl/` | PL 自研测量链（`ADC_PARALLEL` / `DataProcessor` / `RFG` / `PSInterface` / `PQM_TOP`） | 可改 |
| `pl/sim/` | 仿真测试平台与行为级 IP 模型（分组与 `pl/rtl` 一一对应） | 可改 |
| `pl/README.md` | PL 侧约定与踩坑 | 可改 |
| `vivado/` | Vivado 工程源：BD、约束、IP、`ip_repo`、构建脚本与实现报告 | 可改 |
| `scripts/` | 工作区生成、编译、烧录、仿真、上板诊断 | 可改 |
| `docs/` | 交接文件、上板验证清单、设计文档 | 可改 |
| `build/` `export/` `vivado/build*/` | 生成物与日志（已 gitignore） | 不要手改 |

## 基线来源

- 官方例程：`zynq7020-examples/alientek-zynq7020-examples-main/ZYNQ_Vitis_7020/37_zynq_lvgl`
- 官方构建工作区（驱动源码取自此处）：`lvgl_example_work/vitis_ws/zynq_lvgl/src`
- `hw/system_wrapper.xsa` SHA256：`ABAD58C56D59C26B36A80085ED7036FE5A5B33DDD22F6AEB467B500BE075A69C`
- LVGL 版本：8.2.0

## 硬件与测量口径

- Zynq XC7Z020-CLG400-2；AD7606 八通道**电压** ADC，信号源直连 ±10 V（无衰减）。
- PL 时钟 50 MHz（`clk_50m`），采样率 **25.6 kHz**（帧间隔 1953/1954 拍）。
- 频域链是自研 RFG，取点 **N=512 / K=64**，不再用 xfft。
- PS/PL 共享内存：`0x40000000`，16384 字 × 32 bit。谐波 bank0 基址字 `0x400`、bank1 `0xC00`，每条 4 字（U1 占比 / U2 占比 / 相位 / 标志），共 64 条（0..63）。
- PL 只产出 **U1/U2 两路真实电压值**，固定满量程 10.00 V（x100 = 1000），不做量程切换；PL 里已不再区分 U/I。U2 由 PS 直接当电流显示，折算系数 1。
- 「大量程」不是真的量程，而是把真值乘 K 模拟市电：**K = 220√2 / 8 = 38.89**，K² = 1512.43；小量程 K = 1。由此 ADC ±10 V（峰值）满量程对应 ±388.90 V，满量程有效值恰为 275.00 V。
- 换算集中在 `PQMUI_ApplySimScale()`（`app/pqmui/pqmui_format.c`），是唯一的换算点。

## 相对官方基线的改动

1. **`app/LVGL/GUI/lvgl/` 不含 `examples/`**：官方把 port 模板放在 `lvgl/examples/porting/`，本工程在 `app/port/` 提供自己的版本；若同时编进去会重复定义 `lv_port_disp_init` 与 `lv_port_indev_init`。
2. **官方源文件多为 GBK 编码**（中文注释）。本工程需要修改的文件（`app/main.c`、`app/port/`）已重写为 UTF-8，逻辑保持一致，只改 include 路径、界面入口和命名风格；`app/` 下的官方驱动保持原文件、原编码，一字未动。
3. **`app/main.c`** 的初始化顺序与官方一致；界面入口由 `lv_demo_music()` 换成 `PQMUI_Init()`，主循环里追加一次 `PQMUI_ShmPoll()`（读 PL 实测结果）。示例中未被引用的绘图辅助函数声明与配色表已删除。
4. **数据源是 `app/pqmshm/`**，界面上的测量值全部来自 PL 实测经共享内存回读。阶段 1 的内置假数据源 `app/demo/` **已整目录删除**。
5. **界面入口换了**：官方用 LVGL 自带的 music demo，本工程用 `app/pqmui/`，因此不需要 `LVGL/GUI_APP/` 那几十 MB 的示例图片数组。
6. **`app/LVGL/GUI/lvgl/lv_conf.h` 里 `LV_USE_PERF_MONITOR` 由 1 改为 0**：官方开着它，会在屏幕右下角画一条 FPS/CPU 监视条（实测 50 FPS / 79% CPU）。旧 PQM 的 `lv_conf.h` 没有开，为了画面严格等价必须关掉。
7. **修了官方触摸驱动的一个 bug**（`app/TOUCH/ft5206.c`）：`FT5206_Scan` 里判断坐标越界时把宽高写反了——
   `if(tp_dev.x[0] > vd_mode.height || tp_dev.y[0] > vd_mode.width)`。横屏下 x 的范围是 0~799，
   而 `vd_mode.height` 是 480，于是**任何 x>480 的触摸都被当成非法数据丢掉**，右上角两个按钮
   （x=560~780）完全点不动；左半屏（如量程按钮 x=145~341）正常。已按横屏/竖屏分别取正确的限值。
   实测证据：按左半边时 `tp_dev.sta=0xFF01` 且坐标正常；按右上角时 `sta` 显示按下但 `x=y=0xFFFF`
   （被丢弃后恢复成上一次的值）。

## 构建 / 仿真 / 烧录

```powershell
# 1. Vivado：官方基线 BD + 共享内存 + PL 测量链 -> 综合 + 实现 + 比特流 + XSA
#    产物是 vivado/pqm2_meas.xsa 与 vivado/pqm2_meas.bit（已 gitignore，不会进仓库）
#    进程工作目录必须是 vivado\build_meas，否则 PS7 会把 NA/ 写进源码根
New-Item -ItemType Directory -Force vivado\build_meas | Out-Null
cd vivado\build_meas
& 'D:\zt\Xilinx\Vivado\2022.2\bin\vivado.bat' -mode batch -source ..\scripts\build_meas.tcl
#    阶段由环境变量 MEAS_STAGE 控制：bd（只做 BD，快速失败）/ synth / all（默认）

# 2. 从 XSA 生成 Vitis 工作区并编译应用（产物在 build/，已 gitignore）
#    前提：上一步已产出 vivado/pqm2_meas.xsa
powershell -ExecutionPolicy Bypass -File scripts\build_app.ps1

# 3. 仿真回归（当前 30/30 全绿）
powershell -ExecutionPolicy Bypass -File scripts\run_xsim.ps1 -All

# 4. 烧录并读值（板子通电、JTAG 接着）
& 'D:\zt\Xilinx\Vitis\2022.2\bin\xsdb.bat' scripts\flash_meas.tcl

# 5. SD 卡启动镜像（可选）：FSBL + 比特流 + 应用 ELF -> BOOT.BIN
#    前提：1 与 2 都已产出（vivado/pqm2_meas.bit、平台自带的 fsbl.elf、pqm2_app.elf）
#    -CopyTo <盘符>\ 会把 BOOT.BIN 拷过去，并先备份同名旧文件、拷完校验 SHA256
powershell -ExecutionPolicy Bypass -File scripts\build_boot_image.ps1
powershell -ExecutionPolicy Bypass -File scripts\build_boot_image.ps1 -CopyTo F:\
```

USB 线接开发板 JTAG 口，板子供电；运行前需确保没有别的进程占着 hw_target。上板逐步验证清单见 `docs/BOARD_VERIFY.md`。

## 构建上的三个坑

这三条是实际踩到过的，改构建脚本时别踩回去：

1. **`app build` 不会编译**，它只重新生成 `Debug/` 下的 makefile。之前只调 `app build` 的结果是
   日志里写着 "app build finished"、但一个 ELF 都没有。真正的编译必须直接调 Vitis 自带的
   `gnuwin/bin/make.exe --no-print-directory main-build`。
2. **生成的 `subdir.mk` 里只有 BSP 的 include 路径**，应用自己的头文件目录不会被写进去，
   现象是 `timer.c:2:10: fatal error: lvgl.h: No such file or directory`。`create_workspace_meas.tcl`
   用 GCC 认的 `CPATH` 把 `app/src` 下所有目录补进搜索路径，同时把 `gnuwin/bin` 加进 `PATH`
   ——链接后的 size 步骤会调 `tee`，缺了它就报 `'tee' is not recognized`。
3. **应用必须按测量版的 XSA 编译**。`vivado/pqm2_meas.xsa` 对应的比特流才有 `axi_gpio_0`(0x41200000)、
   `clk_wiz_0`(0x43C00000) 这两个应用会访问的外设；拿旧 XSA（`hw/system_wrapper.xsa`，只有视频段）
   编出的 ELF 会去访问不存在的外设并挂死，屏幕全黑只剩背光。`scripts/build_app.ps1` 已固定走
   `create_workspace_meas.tcl` + `vivado/pqm2_meas.xsa`。**换比特流必须同时换 ELF。**
