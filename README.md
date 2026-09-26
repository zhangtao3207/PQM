# PQM2

PQM 的重建工程：以正点原子官方例程 `37_zynq_lvgl` 为基线，只把 PQM 的**界面布局、交互和显示效果**按其规格重新实现，不复用原 PQM 的代码结构。

## 与旧工程的边界

旧工程 `../PQM` 的 PS 端整体绑定在它自己的 PL 硬件清单上（共享 BRAM、AXI DMA、16 位双缓冲 VDMA），无法直接搬到本工程使用的官方比特流上。因此本工程只把旧工程的界面当作**设计规格**：布局、配色、交互行为要求等价，C 代码全部按官方例程的结构与风格重写。

旧工程里 `../PQM/ARM/export/fb0.png`（旧界面真实帧缓存还原图）是本工程界面等价性的对照基准。

## 目录

`app/` 的层级与官方例程的 `src/` 保持一致，便于与上游比对。

| 路径 | 内容 | 是否可改 |
| --- | --- | --- |
| `hw/system_wrapper.xsa` | 官方硬件描述，比特流与 `ps7_init.tcl` 均由它生成 | 只读基线 |
| `app/display_ctrl/` `vdma_api/` `clk_wiz/` `timer/` `TOUCH/` `emio_iic_cfg/` `APP/` | 官方板级驱动，原文件、原编码 | 只读基线 |
| `app/LVGL/GUI/lvgl/` | 官方自带的 LVGL 8.2.0（`src` + `lvgl.h` + `lv_conf.h`） | 只读基线 |
| `app/port/` | LVGL 到板级的显示与触摸适配层 | 可改 |
| `app/pqmui/` | 界面层：页面总控、时域页、频域页、样式、工程量格式化 | 可改 |
| `app/demo/` | 阶段 1 的内置假数据源，阶段 3 整目录删除 | 可改 |
| `app/main.c` `app/main.h` | 应用入口与全局声明 | 可改 |
| `scripts/` | 工作区生成、编译、烧录、帧缓存还原 | 可改 |
| `build/` `export/` | 生成物与日志（已 gitignore） | 不要手改 |

## 基线来源

- 官方例程：`zynq7020-examples/alientek-zynq7020-examples-main/ZYNQ_Vitis_7020/37_zynq_lvgl`
- 官方构建工作区（驱动源码取自此处）：`lvgl_example_work/vitis_ws/zynq_lvgl/src`
- `hw/system_wrapper.xsa` SHA256：`ABAD58C56D59C26B36A80085ED7036FE5A5B33DDD22F6AEB467B500BE075A69C`
- LVGL 版本：8.2.0

## 相对官方基线的改动

1. **`app/LVGL/GUI/lvgl/` 不含 `examples/`**：官方把 port 模板放在 `lvgl/examples/porting/`，本工程在 `app/port/` 提供自己的版本；若同时编进去会重复定义 `lv_port_disp_init` 与 `lv_port_indev_init`。
2. **官方源文件多为 GBK 编码**（中文注释）。本工程需要修改的文件（`app/main.c`、`app/port/`）已重写为 UTF-8，逻辑保持一致，只改 include 路径、界面入口和命名风格；`app/` 下的官方驱动保持原文件、原编码，一字未动。
3. **`app/main.c`** 的初始化顺序与官方一致；界面入口由 `lv_demo_music()` 换成 `PQMUI_Init()`，主循环里追加一次 `PQMUI_DemoPoll()`；示例中未被引用的绘图辅助函数声明与配色表已删除。
4. **界面入口换了**：官方用 LVGL 自带的 music demo，本工程用 `app/pqmui/`，因此不需要 `LVGL/GUI_APP/` 那几十 MB 的示例图片数组。

## 构建与烧录

```powershell
# 1. 从 XSA 生成 Vitis 工作区与应用并编译（产物在 build/，已 gitignore）
powershell -ExecutionPolicy Bypass -File scripts\build_app.ps1

# 2. 烧录并运行：系统复位 -> 编程 PL -> 上电 PS -> 下载 ELF -> 回读校验
& xsct.bat scripts\flash_and_run.tcl

# 3. 导出帧缓存并还原成 PNG，和 ../PQM/ARM/export/fb0.png 对照
& xsct.bat scripts\dump_fb.tcl
python scripts\render_fb.py export\fb_dump.txt export\fb.png
```

USB 线接开发板 JTAG 口，板子供电；运行前需确保没有别的进程占着 hw_target。

## 构建上的两个坑

这两条是实际踩到过的，改构建脚本时别踩回去：

1. **`app build` 不会编译**，它只重新生成 `Debug/` 下的 makefile。之前只调 `app build` 的结果是
   日志里写着 "app build finished"、但一个 ELF 都没有。真正的编译必须直接调 Vitis 自带的
   `gnuwin/bin/make.exe --no-print-directory main-build`。
2. **生成的 `subdir.mk` 里只有 BSP 的 include 路径**，应用自己的头文件目录不会被写进去，
   现象是 `timer.c:2:10: fatal error: lvgl.h: No such file or directory`。`create_workspace.tcl`
   用 GCC 认的 `CPATH` 把 `app/src` 下所有目录补进搜索路径，同时把 `gnuwin/bin` 加进 `PATH`
   ——链接后的 size 步骤会调 `tee`，缺了它就报 `'tee' is not recognized`。
