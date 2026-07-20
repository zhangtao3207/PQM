# PQM PS端软件说明

本目录保存PQM从纯PL显示迁移到Zynq Cortex-A9后的PS端软件。系统运行
FreeRTOS，由PL继续完成确定性采集和测量，由PS负责波形处理、触摸和LVGL界面。

## 目标平台

- 开发板：正点原子领航者ZYNQ
- 主芯片：`XC7Z020-CLG400-2`
- PS输入时钟：`33.333333 MHz`
- CPU：Cortex-A9核0，`666.666667 MHz`
- DDR3：1 GB、32位，兼容预设`MT41K256M16 RE-125`
- 实时系统：Xilinx SDK 2018.3附带的FreeRTOS 10
- 图形库：LVGL 8.3.11
- 显示格式：800x480、RGB565双帧缓存

## 目录结构

- `app/src`：项目自有C语言应用代码。
- `app/src/drivers`：AXI、DMA、VDMA和触摸硬件驱动。
- `app/src/services`：测量数据转换和波形重采样。
- `app/src/ui`：LVGL端口、公共界面及时域/频域页面。
- `scripts`：SDK工作区、FSBL和启动镜像自动生成脚本。
- `tests`：不依赖开发板的主机单元测试。
- `third_party/lvgl`：固定版本的LVGL第三方依赖，不应直接改写。

`sdk_workspace`、`build`和`test_build`均为自动生成目录，已加入忽略规则。
不要手工修改其中的BSP、Makefile或中间文件。

## 常用命令

运行PS/PL共享内存、测量、波形和触摸主机测试：

```powershell
powershell -ExecutionPolicy Bypass -File ARM/tests/run_tests.ps1
```

使用固定的SDK 2018.3环境重新生成FreeRTOS工作区：

```powershell
powershell -ExecutionPolicy Bypass -File ARM/scripts/run_xsct.ps1 -Script ARM/scripts/create_workspace.tcl
```

重新生成FSBL并打包“FSBL + Bitstream + FreeRTOS ELF”：

```powershell
powershell -ExecutionPolicy Bypass -File ARM/scripts/build_boot_image.ps1
```

最终镜像输出到`FPGA/ZYNQ固化脚本/BOOT.bin`。脚本只负责构建镜像，不会
自动烧写QSPI，也不会启动开发板调试会话。

硬件交付文件由Vivado脚本生成到`FPGA/export`。`create_workspace.tcl`会重新
创建FreeRTOS BSP和应用、导入`app/src`源码，并检查
`ARM/sdk_workspace/pqm_freertos/Release/pqm_freertos.elf`是否成功生成。
