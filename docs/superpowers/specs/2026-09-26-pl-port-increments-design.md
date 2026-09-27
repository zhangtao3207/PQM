# PL 端移植：仿真先行、按功能增量（设计）

日期：2026-09-26
工程：`C:\Users\zhangtao\Desktop\PQM2`

## 1 目标

把旧工程 PQM 的 PL 采集与测量链移植到 PQM2：显示通路继续用官方 `37_zynq_lvgl` 那套已经验证过的视频段，测量链按旧工程的 ABI 接进共享内存，最终让 PS 界面显示**真实测量数据**。

## 2 策略

**仿真先行**：每个测量模块先在 xsim 里用已知激励验证数值行为，再上板。理由是实测出来的成本差：

| 动作 | 实测耗时 |
| --- | --- |
| 单元仿真一个模块 | **8~14 秒** |
| 改顶层 RTL → 综合 → 增量实现 → 上板 | 10~12 分钟 |
| 动 IP/BD → 全量构建 | 20~25 分钟 |

仿真比"编译+上板"便宜约 20 倍。旧工程"越改越错"的根因之一是每次判定都要付 10~25 分钟，导致一轮迭代信息量极低；把大部分判定搬到仿真里是收益最大的手段。

**按功能增量**：每一步只引入一个可独立验证的功能点，通过后再进下一步。

## 3 增量表

| # | 功能 | 产物 | 验证判据 | 状态 |
| --- | --- | --- | --- | --- |
| 1 | 搭 xsim 环境，跑通已有的 `PSInterface` 三个 testbench | `pl/rtl/PSInterface/`、`pl/sim/PSInterface/`、`scripts/run_xsim.ps1` | 三个用例打印 `PASS: <模块>` | ✅ 已完成 |
| 2 | AD7606 并行驱动 | `pl/rtl/ADC_PARALLEL/` + `pl/sim/ADC_PARALLEL/tb_AD7606_Parallel_DRIVER.v` | 芯片行为模型只经引脚交互；三个场景：正常一帧（8 通道数据与整帧拼接正确、通道顺序 1~8、无超时）、FRSTDATA 缺失报超时、BUSY 始终不拉高报超时 | ✅ 已完成（7.5 秒） |
| 3 | 时域测量（按模块逐个验证，不再一次搬完） | `pl/rtl/DataProcessor/` 时域部分 + 逐个 testbench | 每个模块喂已知波形，与手算值比对 | ✅ 已完成：`p2p_measure`（修得一个缺陷）、`ui_rms_measure`（含 4 个基础数学模块）、`power_metrics_calc`、`phase_diff_calc`、`time_x100_normalizer`（含 atan ROM 行为级模型）、`time_parameters_initiator`（集成与调度）均已验证 |
| 4 | 频率测量与零点跟踪 | `frequency_measure`、`time_zero_code_tracker` + testbench | 峰值间隔与动态零点收敛值均与离线算出的定点期望值一致 | ✅ 已完成（均一次通过） |
| 5 | FFT + 谐波 + THD + 直流分量 | 同上 + `ip/xfft_0`、`ip/rom_atan_lut_1024` | 喂已知谐波成分，谱线位置与幅值正确 | ✅ 不依赖 xfft 的部分已完成：`fft_magnitude_calc`、`fft_harmonic_stats`、`fft_result_receiver`、`fft_phase_vector_calc`、`freq_harmonic_iir_filter`、`freq_thd_raw_calc`、`freq_metrics_raw_calc`。仍缺 `fft_stream_adapter`（xfft_0）、`data_fifo`（blk_mem_gen_fft_fifo_ram）、`fft_fundamental_freq_tracker`、`phase_deg_lut_calc`、`freq_analysis_top`——它们要么直接包 xfft，要么靠 xfft 才能产生有意义的结果，等增量 6 的 Vivado 工程用真实 IP 仿真源来验 |
| 6 | 集成进 Vivado 工程：官方视频段（参数逐条照抄官方 `.bd`，之后冻结）+ PQM 测量段 | `pl/scripts/`、`pl/data/PQM2.xdc`、比特流 | 上板：共享内存 magic/ABI 可读、标量快照在更新 | 待做 |
| 7 | PS 端从假数据切到真数据，删除 `app/demo/` | `app/pqm/…`（新写 PS 侧共享内存读取） | 上板：界面显示真实测量值，量程命令可用 | 待做 |

## 4 不搬的模块

| 模块 | 不搬的理由 |
| --- | --- |
| `pqm_touch_iobuf.v` | 旧设计里触摸经 PL 转发；PQM2 的触摸走 PS EMIO IIC 直连，已上板验证可用 |
| `pqm_axis_rgb565_to_rgb888.v` | 旧 VDMA 是 16 位 RGB565 才需要它；官方 VDMA 是 24 位，不需要 |

## 5 省时间的工程手段

按收益排序，增量 6 落地时一并实现：

1. **两个 Tcl 入口**：日常迭代只跑 `build_pqm2.tcl`，复用已完成的 IP/BD 检查点；只有换 IP/换机才用 `create_pqm2_project.tcl`。旧工程在这上面栽过——`create_pqm_soc_project.tcl` 无条件删整个工程、`build_pqm_soc.tcl` 又无条件 `reset_run`，26 个 run 每次都从头做。
2. **增量实现**：`place_design -incremental` + 上次成功实现的 `post_route.dcp`，实现阶段可省 30~50%。
3. **视频段冻结**：官方视频段的 IP 参数一次定死（逐条照抄官方 `.bd`），之后不再改动，那部分检查点永久复用。
4. **并行作业数**：OOC run 并行跑。
5. **改过 BD/IP 后删 `PQM2.cache` 与 `.gen`**：旧工程遇到过 `IPCACHE: runCacheChecks()` 处堆损坏崩溃，删这两个目录即可恢复。

## 6 纪律

1. **一次只改一处**，改之前先说清"这一轮结束后我读哪个寄存器、或看哪个仿真结果来判定它生效"。
2. **每轮构建/仿真日志全留存**，改动前后各归档一次。
3. **每次成功实现后把 `post_route.dcp` 存档**，供增量实现使用。
4. 不用包装脚本吞错误：构建与仿真都显式收集 stderr 再判退出码（旧工程被 `$ErrorActionPreference='Stop'` 吞过完整的编译失败）。

## 7 风险

1. **测量链从未验证过**：旧工程 `FPGA/sim/` 下只有 `PSInterface` 的 4 个 testbench，`DataProcessor/`（约 7000 行）与 `ADC_PARALLEL/` 一个仿真都没有。因此增量 2~5 的 testbench 不是"补文档"，而是**首次验证**。
   **已经应验两次**：
   - 增量 3 的 `p2p_measure`：窗口的最后一个采样若刷新了极值，`p2p_raw` 用的是刷新前的 `min_code`/`max_code`（寄存器），窗口长度为 1 时结果完全错（实测 65537）。已修并留下回归用例。
   - **增量 5（2026-09-27，未修）：正半谱帧尾判定依赖输出序。** 用真实 xfft 仿真源实测确认 xfft_0 是 `bit_reversed_order`（流位置 p 上放自然频点 bitrev11(p)），而 `fft_result_receiver` 用 `s_bin_index == LAST_BIN(1024)` 判帧尾，`freq_analysis_top` 给的就是 1024；位反转序下 bin 1024 出现在第 2 个选中频点，于是帧尾标志提前拉高，下游 `fft_harmonic_stats` 提前退出 `ST_CAPTURE`，一帧 1025 个正半谱频点里只有前 2 个被统计。已由 `pl/sim/xfft_probe/tb_fft_frame_end_binrev` 复现（带 `EXPECT_DEFECT=1` 先保证回归可运行）。
     可选修法：① 帧尾改为与顺序无关的计数判定（局部改动，不动 IP，推荐）；② 把 xfft 改成 `natural_order`（要动已冻结的 IP，且会多出重排 BRAM）。
   附带确认：`fft_bin_index = fft_output_tuser[10:0]` 的假设**成立**（XK_INDEX 报的就是自然频点号），不是缺陷。
2. **硬件前提**：AD7606 模块需实际插在扩展口上才能做增量 6/7 的上板验证。
3. **顶层 RTL 变大后综合时间会涨**：测量链并入顶层后，顶层综合可能明显超过 5 分钟。若确实如此，再考虑把测量链做成自研 OOC 模块——但要清楚代价是**切断跨边界优化**，时序可能变差。

## 8 命名变更（2026-09-27）

频域链切到 RFG 后，下面三个模块去掉了 `fft_` 前缀（纯改名，功能与内容未变，改名后全量回归 24/24 通过）：

| 旧名 | 新名 |
| --- | --- |
| `fft_magnitude_calc` | `magnitude_calc` |
| `fft_harmonic_stats` | `harmonic_stats` |
| `fft_phase_vector_calc` | `phase_vector_calc` |

本文档前面的增量表用的是**当时的名字**（记录当时验证了什么），不再回改；`pl/README.md` 记录当前状态。
另：`pl/rtl/RFG/common/fft_twiddle_q24.sv` 保留原名——它是 RFG 研究项目自带的共享旋转系数 LUT，名字里的 fft 指他们自己的 FFT 实现。
