# PQM2 · PL 端

PL 端以官方例程 `37_zynq_lvgl` 的显示通路为基线，把旧工程 PQM 的采集与测量链逐步接进来。

## 目录约定

```
pl/
├─ rtl/<组>/<模块>.v        # 自研 RTL，组名与 sim 侧一致
├─ sim/<组>/tb_<模块>.v     # 单元测试平台
├─ sim/build/               # 仿真生成物（已 gitignore）
├─ data/                    # 约束与查找表
├─ ip/                      # 用到的 IP（xci）
└─ scripts/                 # Vivado 工程与构建脚本
```

`scripts/run_xsim.ps1` 按这个约定自动配对：给定用例名 `<模块>`，它去 `pl/sim/*/tb_<模块>.v` 找测试平台、去同组名的 `pl/rtl/<组>/<模块>.v` 找被测模块。**所以新增模块时，两边的组名必须一致。**

## 来源

`pl/rtl/PSInterface/` 与 `pl/sim/PSInterface/` 下的文件取自旧工程：

- 源：`../PQM/FPGA/rtl/PSInterface/`、`../PQM/FPGA/sim/PSInterface/`
- 只搬了 PQM2 需要的部分，以下两个模块**有意不搬**：
  - `pqm_touch_iobuf.v`：旧设计里触摸经 PL 转发；PQM2 的触摸是 PS EMIO IIC 直连，已验证可用。
  - `pqm_axis_rgb565_to_rgb888.v`：旧 VDMA 是 16 位 RGB565 才需要它；官方 VDMA 是 24 位。

## 运行仿真

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_xsim.ps1 -All
powershell -ExecutionPolicy Bypass -File scripts\run_xsim.ps1 -Test pqm_shared_memory_bridge
```

用例通过时打印 `PASS: <模块>`；日志写到 `export/xsim_<模块>.log`，并在结尾报告耗时。

**注意**：`.ps1` 必须带 UTF-8 BOM。Windows PowerShell 5.1 对无 BOM 的脚本按 ANSI（本机 GBK）解码，中文注释里的多字节字符会吃掉换行符，导致脚本报 `Unexpected token` 之类的语法错误。

## 实测耗时（用于决定"这事儿值不值得编译一次"）

| 动作 | 实测 | 备注 |
| --- | --- | --- |
| 单元仿真一个模块 | **8~14 秒** | 2026-09-26 实测三个 PSInterface 用例 |
| 改 PS 端 + 编译 + 上板 | 约 2 分钟 | `build_app.ps1` + `flash_and_run.tcl` |
| 改顶层 RTL + 综合 + 增量实现 + 上板 | 10~12 分钟 | 顶层综合 5 分 04 秒、实现约 8 分钟 |
| 动 IP 或 BD 后全量构建 | 20~25 分钟 | 26 个 IP/BD 的 OOC 综合约 12 分钟是固定开销 |
