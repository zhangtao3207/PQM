# PQM2 交接文件

> 更新：2026-09-27 · 仓库 `C:\Users\zhangtao\Desktop\PQM2` · 提交 28 次 · 最新 `9ce670b`
> 本文件写给"下一个会话"。先读它，再读 `pl/README.md`（PL 约定与踩坑）与 `.dsh/MEMORY.md`（长期记忆四域）。

## 0 一句话现状

PS 端界面已按官方 `37_zynq_lvgl` 基线搭好并做到像素级等价；PL 测量链的**时域链与频域链都已单模块仿真验证**（24 个用例全绿），**频域链已从 Xilinx xfft 完全切到自研 RFG**。尚未做：ADC 控速、ABI/UI 收敛、Vivado 集成与上板（板子断电）。

## 1 硬约束（不可违反）

1. **板子已断电：禁止烧录、禁止连板**。不跑 `scripts/flash_and_run.tcl`、`dump_fb.tcl`、`diag_touch.tcl`，不做任何 XSCT / hw_server 操作。综合与实现可以离线跑，不需要板子。
2. 旧工程 `C:\Users\zhangtao\Desktop\PQM` **只读参考**，不修改。新工程是 `PQM2`。
3. AD7606 插着但**没有输入信号**：板上数值无意义，测量正确性只能靠仿真证明。
4. PS 界面按**严格像素级等价**翻译：只改代码，画面不动。

## 2 已完成（带证据）

| 块 | 状态 | 证据 |
| --- | --- | --- |
| PS 端（LVGL 界面 + 触摸 + 显示通路） | ✅ 完成 | 以官方例程为基线；界面/交互/显示等价；修了厂商 `ft5206` 驱动宽高互换缺陷（右侧按钮点不到）；`LV_USE_PERF_MONITOR` 关闭。偏离项记在 `README.md` |
| PL 时域链 | ✅ 单模块验证 | `AD7606_Parallel_DRIVER`、`p2p_measure`、`ui_rms_measure`、`power_metrics_calc`、`phase_diff_calc`、`frequency_measure`、`time_zero_code_tracker`、`time_x100_normalizer`、`time_parameters_initiator` 均有用例 |
| PL 频域链 | ✅ 单模块 + 整链验证 | 见 §3 |
| 仿真基础设施 | ✅ | `scripts/run_xsim.ps1`：`-Test <模块>` / `-All`；支持 `.v` 与 `.sv`、`.sv` 测试平台、行为级 IP 模型、用例级额外源清单 |
| 长期记忆 | ✅ | `.dsh/MEMORY.md`（四域）+ `.dsh/memory/` 11 张卡片 + `.dsh/PROGRESS.md` |

**查实并修掉的真实 RTL 缺陷共 2 个**：`p2p_measure` 漏算窗口最后一个采样；`fft_result_receiver` 帧尾判定依赖输出序（位反转下提前拉高，已随 FFT 段一并移除）。

## 3 频域链现状（本次最大改动）

链路（全自研，无 xfft）：

```
ADC 采样流 → pqm_sample_fifo(每通道 64 深) → pqm_rfg_frontend(2×RFG + 2×直流累加器)
          → pqm_rfg_scale(>>10 四舍五入 → 16 位频点流) → magnitude_calc
          → harmonic_stats → phase_vector_calc → phase_deg_lut_calc
          → freq_harmonic_iir_filter        （后五个模块内容一字未改，直接复用）
```

取点：**N=512、K=64**（一帧 = 一个 50 Hz 周期 = **25.6 kHz** 采样），只算 1~64 次谐波。选 N=512 是因为研究项目只验到 N≤512。

验收（同一激励：u = 1 次 1000 + 3 次 400；i = 1 次 800 滞后 90°）：

| 量 | 实测 | 解析 |
| --- | --- | --- |
| 1 次 u 占比 | 7142（自由跑采样 7153） | 7142.9 |
| 3 次 u 占比 | 2857（2846） | 2857.1 |
| 1 次 i 占比 | 10000 | 10000 |
| 1 次 U-I 相位差 | 9000（9006） | 90.00° |

关键事实（细节见模块头注释与 `.dsh/MEMORY.md`）：
- RFG 输出标度 = `2 × (Q2.14 整数序列的原始 DFT 求和)`（用其自带向量标定）。
- RFG **不输出 bin 0**；直流由 `pqm_rfg_dc_sum` 补（一个加法器 + 寄存器 + 左移 1 位），标度与各 bin 严格一致。
- `pqm_rfg_scale` 必须**四舍五入**而非截断：截断的负偏置会抬高总幅值、把所有占比整体压低（实测 1 次 u 由 7142 掉到 6979）。
- **RFG 只认样本序列、不认时间**：前面必须有 FIFO，否则计算期丢的采样会让帧跨多个周期、谱泄漏（实测 1 次 u 占比崩到 2508 并冒假谱线）。
- 已删除：`fft_stream_adapter`、`fft_result_receiver`、`data_fifo`、`fft_fundamental_freq_tracker`、`freq_analysis_top`、`pl/ip/xfft_0/`（含 12 MB 生成物）、3 个探针用例。
- 频域链唯一剩下的厂商 IP 是 `rom_atan_lut_1024`（相位查表）：仓库放真 xci + COE（**供综合**），仿真用等价行为级模型 `pl/sim/models/`。

## 4 未完成（下一步就在这里面挑）

1. **ADC 控速到 25.6 kHz（欠账，建议先做）**。现状：PQM2 还没有 PL 顶层，AD7606 驱动的 `start` 由谁给尚未确定；旧工程是"驱动 idle 就立刻再启动"＝自由跑（约 172 kSPS），与 N=512=一个周期不符。
   做法：写一个 26 位累加器小数分频（50 MHz / 25.6 kHz = 1953.125 拍，平均严格 25.6 kHz，抖动 ±1 拍），输出 CONVST 启动脉冲；配一个 TB 验证平均频率与抖动。
   代价要记住：采样率降 8 倍后，时域链过零分辨率变成 39 µs ⇒ 频率 ±0.1 Hz、相位 ±0.7°（PF 在 φ≈0 处二阶不敏感）。若不够，退回"102.4 kSPS 采 + 4 倍抽取给 RFG"。
2. **ABI/UI 收敛**：谐波条目 **501 → 65**（`pl/rtl/PSInterface/pqm_shared_memory_map.vh` + 共享内存桥 + PS 读侧 + UI），UI 谐波显示改成**每页 16 条、第 1 页额外带 0 次**（H0 + H1–H16，之后 H17–H32 / H33–H48 / H49–H64 共 4 页）。
   ⚠️ "每页 16 条"是我对用户原话的理解（频率页幅值图与相位图共用谐波窗口，我按两个图都改）——**动手前先跟用户确认一次**。
3. **`pqm_sample_fifo` 的写满/溢出路径没有独立用例**（现有用例只覆盖未满的正常流）。
4. **可选项**：把仿真的相位查表从行为级模型换成真 IP 生成的 `sim/rom_atan_lut_1024.v`（做法见 `pl/README.md`；同名的两个模块不能同时编译）。
5. **增量 6/7（大块）**：建 Vivado 工程（官方视频段参数逐条照抄官方 `.bd` 并冻结 + PQM 测量段），离线综合/实现拿资源与时序；上板验证等板子可用。旧工程 IP 照搬要先 `upgrade_ip`（2018.3 定制、2022.2 下 locked）。
6. 老 `divider_signed.v` 无人实例化（死代码）。

## 5 约定与坑

- 仿真入口：`powershell -ExecutionPolicy Bypass -File scripts\run_xsim.ps1 -All`（24 例约 4 分钟）；单例 `-Test <模块>`（8~14 秒）。
- 约定：`pl/rtl/<组>/<模块>.v` ↔ `pl/sim/<组>/tb_<模块>.v`，**组名必须一致**；判定必须看日志里的 `PASS: <用例名>`（`xsim -runall` 遇 `$fatal` 仍返回 0）。
- 用例需要额外源/向量时，在 `pl/sim/<组>/tb_<用例>.models.txt` 里逐行列目录（**按用例独立，漏建会让 readmemh 静默留 X**）。
- 数值检查必须带 `^actual === 1'bx` 守卫（Verilog 里 `if(X)` 为假，范围比较会静默放行）。
- 其它坑（BOM、`fork` 共用变量、单拍脉冲锁存、厂商握手时序等）见 `pl/README.md` 与 `.dsh/MEMORY.md` 的"坑与陷阱"。

## 6 本文件的维护

每完成一个增量就更新 §2/§3/§4，并在 `.dsh/PROGRESS.md` 追加一条。**不要**把"待办/进行中"写进 `.dsh/memory/` 的卡片（那是长期记忆，只管跨会话仍成立的事实与偏好）。
