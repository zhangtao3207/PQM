# PQM2

PQM 的重建工程：以正点原子官方例程 `37_zynq_lvgl` 为基线，只把 PQM 的**界面布局、交互和显示效果**按其规格重新实现，不复用原 PQM 的代码结构。

## 与旧工程的边界

旧工程 `../PQM` 的 PS 端整体绑定在它自己的 PL 硬件清单上（共享 BRAM、AXI DMA、16 位双缓冲 VDMA），无法直接搬到本工程使用的官方比特流上。因此本工程只把旧工程的界面当作**设计规格**：布局、配色、交互行为要求等价，C 代码全部按官方例程的结构与风格重写。

旧工程里 `ARM/export/fb0.png`（旧界面真实帧缓存还原图）是本工程界面等价性的对照基准。

## 目录

| 路径 | 内容 | 是否可改 |
| --- | --- | --- |
| `hw/system_wrapper.xsa` | 官方硬件描述，比特流与 `ps7_init.tcl` 均由此生成 | 只读基线 |
| `app/board/` | 官方板级驱动：`display_ctrl` `vdma_api` `clk_wiz` `timer` `TOUCH` `emio_iic_cfg` `APP` | 只读基线 |
| `app/third_party/lvgl/lvgl/` | 官方自带的 LVGL 8.2.0（`src` + `lvgl.h` + `lv_conf.h`） | 只读基线 |
| `app/port/` | LVGL 到板级的适配层，基于官方 port 模板重写 | 可改 |
| `app/pqmui/` | 界面层：页面、样式、工程量格式化 | 可改 |
| `app/demo/` | 阶段 1 的内置假数据源，阶段 3 整目录删除 | 可改 |
| `app/main.c` | 应用入口 | 可改 |
| `scripts/` | 工作区生成、编译、烧录脚本 | 可改 |

## 基线来源

- 官方例程：`zynq7020-examples/alientek-zynq7020-examples-main/ZYNQ_Vitis_7020/37_zynq_lvgl`
- 官方构建工作区（驱动源码取自此处）：`lvgl_example_work/vitis_ws/zynq_lvgl/src`
- `hw/system_wrapper.xsa` SHA256：`ABAD58C56D59C26B36A80085ED7036FE5A5B33DDD22F6AEB467B500BE075A69C`
- LVGL 版本：8.2.0

## 相对官方基线的改动

1. **`app/third_party/lvgl/lvgl/` 不含 `examples/`**：官方把 port 模板放在 `lvgl/examples/porting/`，本工程在 `app/port/` 提供自己的版本，若同时编进去会重复定义 `lv_port_disp_init` / `lv_port_indev_init`。
2. **官方源文件多为 GBK 编码**（中文注释）。本工程需要修改的文件（`main.c`、port 层）已重写为 UTF-8，逻辑保持一致，仅改 include 路径、界面入口和命名风格；`app/board/` 下的驱动保持官方原文件、原编码，一字未动。
3. `main.c` 的初始化顺序与官方一致，只把界面入口从 `lv_demo_music()` 换成 PQM 界面，并在主循环追加一次假数据源轮询。

## 构建与烧录

```powershell
# 1. 从 XSA 生成 Vitis 工作区与应用（产物在 build/，已 gitignore）
powershell -ExecutionPolicy Bypass -File scripts\build_app.ps1

# 2. 烧录并运行：编程 PL -> 上电 PS -> 下载 ELF -> 回读校验
& xsct.bat scripts\flash_and_run.tcl
```

USB 线接开发板 JTAG 口，板子供电；运行前需确保没有别的进程占着 hw_target。
