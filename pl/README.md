# PQM2 · PL 端

PL 端以官方例程 `37_zynq_lvgl` 的显示通路为基线，把旧工程 PQM 的采集与测量链逐步接进来。

## 目录约定

```
pl/
├─ rtl/<组>/<模块>.v        # 自研 RTL，组名与 sim 侧一致
├─ sim/<组>/tb_<模块>.v     # 单元测试平台
├─ sim/models/              # 行为级 IP 仿真模型 + 它们要读的数据文件
├─ sim/build/               # 仿真生成物（已 gitignore）
├─ data/                    # 约束与查找表
├─ ip/                      # 用到的 IP（xci）
├─ scripts/                 # Vivado 工程与构建脚本
└─ scripts/coe_to_mem.ps1   # COE -> $readmemh 用的 .mem
```

`scripts/run_xsim.ps1` 按这个约定自动配对：给定用例名 `<模块>`，它去 `pl/sim/*/tb_<模块>.v` 找测试平台、去同组名的 `pl/rtl/<组>/<模块>.v` 找被测模块。**所以新增模块时，两边的组名必须一致。**

## 来源

`pl/rtl/` 与 `pl/sim/` 下的文件取自旧工程：

- 源：`../PQM/FPGA/rtl/PSInterface/`、`../PQM/FPGA/sim/PSInterface/`
- `pl/rtl/ADC_PARALLEL/` + `pl/sim/ADC_PARALLEL/`：AD7606 并行采集通路（`AD7606_Parallel_DRIVER` 与它内嵌的 `ad7606_parallel_ctrl`）及其测试平台；另有自研的采样节拍发生器 `pqm_adc_pacer`（25.6 kHz，见交接文件 §3.1）。
- `pl/rtl/DataProcessor/` + `pl/sim/DataProcessor/`：测量算法，**保留旧工程的分层目录**（`BasicMath/`、`SignalProcessing/TimeAnalysis/...`），所以运行脚本按递归方式找被测模块并整组编译。

**喂数据的约定**：测量算法用的是**单调码值**。AD7606 输出是二进制补码，`pqm_pl_core` 先把它 XOR `0x8000` 转成偏移二进制（0x8000 为零点）才送进测量核心；`p2p_measure` 这类模块内部用无符号比较求最大/最小，必须按这个前提写激励。
- 只搬了 PQM2 需要的部分，以下两个模块**有意不搬**：
  - `pqm_touch_iobuf.v`：旧设计里触摸经 PL 转发；PQM2 的触摸是 PS EMIO IIC 直连，已验证可用。
  - `pqm_axis_rgb565_to_rgb888.v`：旧 VDMA 是 16 位 RGB565 才需要它；官方 VDMA 是 24 位。

## 运行仿真

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_xsim.ps1 -All
powershell -ExecutionPolicy Bypass -File scripts\run_xsim.ps1 -Test pqm_shared_memory_bridge
```
用例通过时打印 `PASS: <模块>`；日志写到 `export/xsim_<模块>.log`，并在结尾报告耗时。

`run_xsim.ps1` 默认把 `pl/sim/models/` **根目录**下的模型编给所有用例（只编译、不强制实例化，`xelab` 只拉真正用到的层次），并把同一目录下的非源码文件（如 `.mem`）复制到每个用例的 build 目录，供 `$readmemh` 读取。

更重的 IP 仿真源由用例按需引入：在 `pl/sim/<组>/tb_<用例>.models.txt` 里逐行写仓库相对目录（递归收集），例如

```
pl/ip/xfft_0/sim
pl/ip/xfft_0/hdl
```

这样 12 MB 的加密 VHDL 只会进到真正需要它的用例（实测 `tb_xfft_probe` 编译+运行约 63 秒，其余用例仍为 8~10 秒）。

### IP 仿真源怎么来

| 来源 | 做法 |
| --- | --- |
| `rom_atan_lut_1024` | 写行为级等价模型 `pl/sim/models/rom_atan_lut_1024.v`（1025x14、读延迟 1 拍），数据由 `pl/scripts/coe_to_mem.ps1` 从旧工程 COE 机械转换 |
| `xfft_0` | **用真实仿真源**：`pl/scripts/gen_xfft_sim_model.tcl` 只生成 simulation target，产物落 `pl/ip/xfft_0/{sim,hdl}/`（已 gitignore，xci 本身提交） |

`pl/ip/xfft_0/xfft_0.xci` 是从旧工程拷来的副本（旧工程定制于 **Vivado 2018.3**，在 2022.2 下是 locked 状态，必须先 `upgrade_ip`）。升级只动版本元数据：升级前后的 26 条用户参数已逐行比对，**零差异**（脚本会把快照存到 `export/xfft_params_before/after.txt`）。

行为级模型只用于仿真，**不得加进综合源集**；用它们跑出来的结论只能说到“接口与时序对齐、IP 外围的数字逻辑正确”。用真实仿真源跑的结论可以说到 IP 自己的行为（例如 `tb_xfft_probe` 就是在测 xfft 输出的语义）。

## 坑与陷阱

**注意**：`.ps1` 必须带 UTF-8 BOM。Windows PowerShell 5.1 对无 BOM 的脚本按 ANSI（本机 GBK）解码，中文注释里的多字节字符会吃掉换行符，导致脚本报 `Unexpected token` 之类的语法错误。

**另一个坑**：`xsim -runall` **即使碰到 `$fatal` 也返回退出码 0**。只看退出码会把失败的用例报成通过（已实际发生一次）。`run_xsim.ps1` 因此改为检查日志内容：既要求没有 `FAIL:` / `Fatal:`，也要求确实打印了 `PASS: <模块>`。

**写激励时避开竞争**：testbench 里驱动 `start` 这类单拍脉冲，要在**时钟低电平期间**翻转（`@(negedge clk)` 之后赋值），否则脉冲和 posedge 采样撞在同一个时间步里会被采到 0。第一次写 AD7606 用例时就踩了这个，表现为控制器一直停在空闲。

**`fork` 里的两个并发任务不能共用循环变量**：驱动任务和消费任务在 `fork ... join` 里并行，如果都用同一个 `integer k` 做下标，两边会互相踩，现象是检查项整体错位（`fft_phase_vector_calc` 用例踩过一次）。驱动用 `m`、消费用 `k`。

**给初始清 RAM 的模块留足等待窗口**：`fft_harmonic_stats`、`freq_harmonic_iir_filter` 复位后要 501 拍把状态 RAM 清零才拉高 ready。若消费侧或驱动侧的等待循环只等 400 拍，第一帧就会整帧错位一项（两个用例各踩过一次）。现在这些用例先等 ready 拉高再开帧，等待上限也放到 800~1200 拍。

**9 bit 字段的越界激励会被截断**：`s_harmonic_order` 只有 9 bit，本想用 600 当“超范围”输入，实际被截成 88（反而在范围内）。要越界就用 501。

**TB 别直接拿非阻塞赋值的变量当拍号**：监视器里 `last_cyc <= cyc` 之后，同一拍读它得到的是旧值。写 `pqm_adc_pacer` 用例时因此把 1786 个间隔的跨度少算了 2452 拍（恰好是窗口前那段），看起来像“平均频率不精确”。要么多等一拍再读，要么把要参与判定的计时变量改成阻塞赋值。同一用例还踩了两次计数器的坑：间隔计数的首项没加守卫（`last_cyc` 初值 0，首项变成“从 0 到第一个脉冲”，凭空多出一个超界间隔）；以及监视器的“复位释放后首脉冲相位”计数器在**复位保持期间**没解除武装，把复位期的 200 拍也数进去（D 项因此测出 101 拍而不是 1954）。

**判“平均频率严格等于某值”时要选对判据**：`2^W / INC` 在周期是 5^n 的分数时不可能精确（二进制模数约不掉因子 5），别去凑单个周期的比值，改判“整数拍窗口内脉冲数恰好为整数”（`pqm_adc_pacer` 的 A2 项：15625 拍内恰好 8 个脉冲）。

### PL 测量链系统级集成（`pqm_pl_top` + `tb_pqm_pl_top`，2026-10）

1. **AD7606 引脚是二进制补码**：TB 的 ADC 行为模型必须往引脚上放补码（`u_code_c` 本身），不是偏移二进制（`CENTER + u_code_c`）。放错会让 RTL 的 `XOR 0x8000` 再翻一次，送进测量链的变成 `x = u − 32768·sgn(u)` ≈ 方波，现象是「奇次频点严格 1/n 衰减」、时域 RMS 涨到 3 万多。
2. **验证样本的取样点必须取在「核心去直流之后」**：取 `u_measurement_core.freq_sample_u`（有符号），不要取 ADC 原始码——那是偏移二进制原码，与中心化的期望值不同形，比了不说明问题。
3. **组合逻辑读寄存器晚一拍**：任何「用寄存器做组合运算」的地方读到的是上一拍的值。要一起用的信号（码值、零点码、valid）必须放在同一个 always 块、同一级寄存产出，否则核心的组合减法会拿到不同格的两个量。
4. **`scripts/run_xsim.ps1` 由 Windows PowerShell 5.1 执行**：5.1 下 `Get-ChildItem -Path <dir>\* -Recurse -Include` 不深入子目录且**静默少找**（DataProcessor 的 21 个文件只找到 1 个）。已改为「递归 + `Where-Object` 过滤」，不要改回去。
5. **`.models.txt` 必须 CRLF 行尾**：5.1 的 `Get-Content` 对纯 LF 文件会把整个文件当一行读，静默吞掉第一条目录。
6. **共享内存 ABI 的取值**：谐波 bank0 基址 word `0x400`、bank1 `0x800`，每条 4 个 word（U 占比 / I 占比 / 相位(有符号 32 位) / flags[0]=present）。RFG 取点 `C_K=64`，所以**有值的最大频点是 64**，65..500 按设计 present=0（不要误判成 500）。

## xfft 实测结论（2026-09-27）

用真实仿真源（`pl/sim/xfft_probe/`，配置与设计用的常量完全一致）测出来的事实：

| 事项 | 实测结果 |
| --- | --- |
| 输出序 | 流位置 p 上放的是**自然频点 bitrev11(p)**（bin 8 出现在位置 128、bin 16 出现在位置 64）⇒ 确实是 `bit_reversed_order` |
| `m_axis_data_tuser[10:0]` | 报的是**自然频点号**（bin 8 那项 tuser=8、bin 16 那项 tuser=16，范围 0..2047） ⇒ `fft_stream_adapter` 的 `fft_bin_index = tuser[10:0]` **假设成立，不是缺陷** |
| 缩放调度 `22'h155555` | 每级 1 bit、共 11 级 = 总缩放 1/2048，正好抵消 2048 点 FFT 的增长；实测方波基波幅度与理论值吻合（通道 0 峰值 |-5095| ≈ (4A/π)·1024/2048 = 5093），且无 OVFLO |
| 自检 | 幅度±8000/±4000 的两路方波共 192 条谱线，实测非零频点数正好 192 |

**由此暴露的一个真实缺陷**（已用 `tb_fft_frame_end_binrev` 复现）：`fft_result_receiver` 用
`selected_last_input = selected_input && (s_bin_index == LAST_BIN)` 判定正半谱帧尾，而 `freq_analysis_top` 给的 `LAST_ANALYSIS_BIN = 1024`。在位反转输出序下位置 1 上就是 bin 1024，于是**帧尾标志在第 2 个（共 1025 个）选中频点上就拉高**（已复现：首次拉高那一项 bin=1024，`m_bin_last` 只拉高 1 次），下游 `fft_harmonic_stats` 会在 `ST_CAPTURE` 提前退出，该帧剩下的 1023 个频点不会被统计。

该用例当前带 `EXPECT_DEFECT = 1`（以 DEFECT-CONFIRMED 通过，保证全量回归可运行）；**修好 RTL 后要把它改成 0**，它就变成正式回归用例。


## 实测耗时（用于决定"这事儿值不值得编译一次"）

| 动作 | 实测 | 备注 |
| --- | --- | --- |
| 单元仿真一个模块 | **8~14 秒** | 2026-09-26 实测三个 PSInterface 用例 |
| 改 PS 端 + 编译 + 上板 | 约 2 分钟 | `build_app.ps1` + `flash_and_run.tcl` |
| 改顶层 RTL + 综合 + 增量实现 + 上板 | 10~12 分钟 | 顶层综合 5 分 04 秒、实现约 8 分钟 |
| 动 IP 或 BD 后全量构建 | 20~25 分钟 | 26 个 IP/BD 的 OOC 综合约 12 分钟是固定开销 |

## 频域链改用 RFG（xfft 已移除，2026-09-27）

频域链现在是**全自研、无厂商 IP**：

```
ADC 采样流 -> pqm_sample_fifo(每通道 64 深) -> pqm_rfg_frontend(2x RFG + 2x 直流累加器)
           -> pqm_rfg_scale(>>10，变成 16 位频点流) -> fft_magnitude_calc
           -> fft_harmonic_stats -> fft_phase_vector_calc -> phase_deg_lut_calc
           -> freq_harmonic_iir_filter
```

取代了原来的 `freq_analysis_top`（其内部是 `fft_stream_adapter`(xfft_0 + data_fifo/
blk_mem_gen_fft_fifo_ram) -> `fft_result_receiver` -> ...）。已删除：`fft_stream_adapter`、
`fft_result_receiver`、`data_fifo`、`fft_fundamental_freq_tracker`、`freq_analysis_top`、
`pl/ip/xfft_0/`（含 12 MB 生成物）、`pl/scripts/gen_xfft_sim_model.tcl`，以及两个探针用例
`tb_xfft_probe`、`tb_fft_frame_end_binrev`。后级五个模块**一个字节都没改**，直接复用。

本站的取点：**N=512、K=64**（一帧 = 一个 50 Hz 周期 = 25.6 kHz 采样），只算 1~64 次谐波。
`pqm_rfg_scale` 的 >>10 是唯一的标度适配，依据是两条链的输出都只用于**比值与角度**
（占比 = mag*10000/total、THD = sqrt(Σ|X_h|²)/|X_1|、相位 = atan2），尺度无关。

**为什么前面必须有 FIFO**（本轮实测踩出来的）：RFG 只认**样本序列**、不认时间，它算的是
"连续 N 个采样点的 DFT"。若上游在它未就绪时把采样丢掉（计算期 `o_sample_ready` 为低），
一帧的 N 个点就不再连续、会跨多个周期，谱随之泄漏——实测自由跑激励下 1 次 u 占比从
7142 掉到 2508，并冒出 5 次 873 的假谱线；加了 FIFO 之后同一激励精确通过（7153 / 2846 /
10000 / 相位差 9006）。深度依据：25.6 kSPS 下 L4/D1 的计算期 83840 拍 ≈ 43 个采样；
若改用 L16/D8（3464 拍）只需几级。

历史说明：上面"IP 仿真源怎么来"与"xfft 实测结论"两节记录的是 xfft 路线在移除前查实的
结论（XK_INDEX 报自然频点号、位反转输出序会让原帧尾判定提前拉高等），保留作溯源；
对应的代码与 IP 已不在仓库里。

## rom_atan_lut_1024：从旧工程照搬（2026-09-27）

频域链里唯一剩下的厂商 IP 是 `rom_atan_lut_1024`（相位查表，被 `phase_deg_lut_calc`
用于频域、被 `time_x100_normalizer` 用于时域）。已按 xfft 那次的同一套路从旧工程照搬：

- 源：旧工程 `FPGA/ip/rom_atan_lut_1024/rom_atan_lut_1024.xci` + `FPGA/data/atan_lut_1024.coe`
- 落到 `pl/ip/rom_atan_lut_1024/`（xci + COE 提交，生成物忽略）
- **两个坑都要处理**（与 xfft 相同）：
  1. 旧 xci 是 Vivado 2018.3 定制的，在 2022.2 下 `IS_LOCKED=1`，必须先 `upgrade_ip`
     （实测 Block Memory Generator 8.4，revision 2 → 5，升级后 `IS_LOCKED=0`）；
  2. xci 里的 `Coe_File` 是相对旧工程目录的路径，照搬时必须同时拷 COE 并改写成
     同目录下的 `atan_lut_1024.coe`，否则生成时找不到初始化文件。
- 重新生成：`vivado -mode batch -source pl/scripts/gen_rom_sim_model.tcl`
  （产物 `sim/rom_atan_lut_1024.v`，**普通 Verilog**，不像 xfft 是加密 VHDL；
   它运行时读 `rom_atan_lut_1024.mif`）

**仿真仍用行为级模型 `pl/sim/models/rom_atan_lut_1024.v`**，理由：接口逐位一致
（`clka/ena/addra[10:0]/douta[13:0]`，1025×14、读延迟 1 拍，参数取自 xci），数据取自
同一份 COE，且不需要先跑 Vivado 生成。真 xci 放在仓库里是**为综合准备**的。

注意：行为级模型与生成的 `sim/rom_atan_lut_1024.v` **同名模块，不能同时编译**。
harness 只编 `pl/sim/models/` 根目录与各用例清单列出的目录、不会碰 `pl/ip/**`，
所以结构上不会撞；若要改用真模型，必须把 `pl/sim/models/rom_atan_lut_1024.v` 移出。
