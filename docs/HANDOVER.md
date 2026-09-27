# PQM2 交接文件

> 更新：2026-09-27 · 仓库 `C:\Users\zhangtao\Desktop\PQM2` · 提交 28 次 · 最新 `9ce670b`
> 本文件写给"下一个会话"。先读它，再读 `pl/README.md`（PL 约定与踩坑）与 `.dsh/MEMORY.md`（长期记忆四域）。

## 0 一句话现状

PS 端界面已按官方 `37_zynq_lvgl` 基线搭好并做到像素级等价；PL 测量链**已连成系统并通过系统级仿真**（`pqm_pl_top` + `tb_pqm_pl_top`，`-All` 共 26 个用例全绿），**频域链已从 Xilinx xfft 完全切到自研 RFG**，**ADC 采样控速（`pqm_adc_pacer`，25.6 kHz）已做完并有用例**。尚未做：Vivado 集成与上板（板子断电）、ABI/UI 收敛。

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
| ADC 采样控速 25.6 kHz | ✅ 单模块验证 | `pqm_adc_pacer`（26 位累加器、INC=34361）：平均严格 25.6 kHz，相邻间隔 1953/1954 拍。用例 `tb_pqm_adc_pacer`，详见 §3.1 |
| PL 测量链系统级验证 | ✅ 系统级仿真通过 | `pl/rtl/PQM_TOP/pqm_pl_top.v` + `pl/sim/PQM_TOP/tb_pqm_pl_top.v`：全链逐环判据（pacer → AD7606 驱动 → 补码转偏移码 → 零点跟踪×2 → 测量核心 → 共享内存桥）；谐波 1 次占比 7138 / 3 次 2861、共享内存 ABI 回读一致、快照提交 9 次且 `u_rms`=812、采样 25.6 kHz 无丢样本（gap 1953/1954、`adc_tick_pending`=0）。详见 §3.2 |
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

## 3.1 ADC 采样控速（`pqm_adc_pacer`）

模块：`pl/rtl/ADC_PARALLEL/pqm_adc_pacer.v`，用例 `pl/sim/ADC_PARALLEL/tb_pqm_adc_pacer.v`。

背景：一帧 RFG 取 N=512 点 = 一个 50 Hz 周期，要求采样率就是 **25.6 kHz**；旧工程“idle 即再启动”
的自由跑与它不符（百 kSPS 量级），因此必须显式控速。

做法：26 位累加器小数分频，每个 50 MHz 时钟加 `INC = 34361`，进位即输出一个 1 拍宽的 `o_tick`。

- **增量不是 1953125**。旧交接文件里写的 `1953125 = 1953.125 × 1024` 是“把周期乘了 1024”，
  量纲不对；它在 26 位下得 34.36 拍/脉冲（1.455 MHz），与 25.6 kHz 差 57 倍。
  正确的频率字只能是 `周期拍数 = 2^W / INC` 的反解：`INC = 2^26 / 1953.125 = 34359.738 → 34361`。
- 为什么“平均严格”能成立：`1953.125 = 15625/8`，而 `15625 = 5^6` 与 2 互素，
  所以 `2^W / INC` **不可能**精确等于 1953.125（增量只能取整）。真正的判据是
  **整数拍窗口内脉冲数恰好为一个整数**：15625 拍内恰好 8000 个脉冲 → 平均 1953.125 拍/脉冲。
  残余量化误差 ≈ 3 ppm（约 0.08 Hz），根因是 5^6 无法被二进制模数约掉。
- 相邻间隔只取 1953 或 1954 拍（Bresenham），抖动 ±1 拍（±20 ns @50 MHz），长时无累积误差。
- 选 34361 而不是更接近 34359.738 的 34360：后者会让间隔退化成恒定 1953 拍
  （`2^25 × 34360` 整除 `2^26`），每 8 个脉冲漂移 -1 拍；34361 给出标准交替。
- 纯时基：不看 ADC 忙闲（25.6 kHz 周期 1953 拍，一次采样约占 700 拍）；
  重触发策略已在 `pqm_pl_top` 里定案：tick 撞上驱动忙时不重触发，只置粘滞标志 `adc_tick_pending`。

验收（`-Test pqm_adc_pacer`，日志 `export/xsim_pqm_adc_pacer.log`）：

| 项 | 实测 | 期望 |
| --- | --- | --- |
| A 窗口 1786 个间隔跨拍数 | 3488153 | 3488153（`1786×2^26/34361`，容差 ±1 拍） |
| A 核账 | 1787 脉冲 / 1786 间隔，min_gap 1953、max_gap 1954 | — |
| A2 标定窗口 15625 拍内脉冲数 | 8 | 8 ±1 |
| B 越界间隔 / C 宽脉冲 | 0 / 0 | 0 |
| D 复位释放到首个脉冲 | 1954 拍 | 1954（`ceil(2^26/34361)`） |

注：A2 窗口按“15625 拍 ÷ 1953.125 拍/脉冲 = 8 个脉冲”计数，不是 8000。

**接线已完成**：`pqm_pl_top` 已实例化 pacer，`o_tick` 接 `AD7606_Parallel_DRIVER.start`；
tick 撞上驱动忙时置粘滞标志 `adc_tick_pending`（丢样本这件事是可见的），正常时序下恒为 0。

## 3.2 PL 测量链系统级验收（2026-10）

用例 `pl/sim/PQM_TOP/tb_pqm_pl_top.v`，被测 `pl/rtl/PQM_TOP/pqm_pl_top.v`。激励：在 AD7606 引脚上挂芯片
行为模型，喂代码级正弦 u = 1000·cos(ωn) + 400·cos(3ωn)、i = 800·sin(ωn)（滞后 90°）。TB 逐环判据：
1a 复位期无 tick ┊ 1b 每个 tick 都被消费（`adc_tick_pending`=0）┊ 1c 帧间隔 1953~1954 拍 ┊ 1d valid 与帧一一对应 ┊
2a 码值随正弦变化 ┊ 2b 零点收敛到 0x8000 ┊ 3in 送进 RFG 的前 24 点与解析值逐点相等 ┊ 3 谐波帧结构与 1 次占比 ┊
4 快照提交与 `u_rms` ┊ 5 桥写 BRAM 与共享内存 ABI 回读。

实测日志（`export/xsim_pqm_pl_top.log`，`-Test pqm_pl_top`，TB 默认的缩短测量参数，约 90 秒）：

```
INFO: 1a 复位期间无 tick
INFO: 1b tick=4200 frame=4200 gap=[1953,1954] 标称 1953
INFO: 1c pending=0 sample=4200 ready=8204111
INFO: 2b zero_valid=1/1 zero_code=8000/8000 code_changed=4166
INFO: 3 harm_frames=8 items=520 max_index=64 last=64 h1_present=1 h1_ratio=7138
INFO: 3in  RFG 输入前 24 点不符 0 个
INFO: 4 commit=9 u_rms=812（期望约 762）bram_wr=2812 harm_wr=2048
INFO: 5abi  从共享内存解出：1次u=7138 3次u=2861 present=1 最大index=64
PASS: pqm_pl_top
```

要点：
- 谐波 1 次 u 占比 7138、3 次 2861（解析 7142.9 / 2857.1），与频域链单模块验收一致。
- 共享内存 ABI 回读与核心输出逐项一致（bank0 基址 word `0x400`、bank1 `0x800`，每条 4 word）。RFG 取点 `C_K=64`，
  所以**有值的最大频点是 64**。ABI 收敛为 0..64 共 65 条后，帧尾 index 与最大 present index 都是 64（65 次以上不再进共享内存）。
- 谐波 ABI 收敛为 65 条（0..64）后每帧 65 项（日志 `items=8×65=520`，帧尾 `last=64`）。注意 `harmonic_stats`
  内部的谐波缓存仍按 **bin 号**索引（FUND_BIN=1 时最大 bin=500），深度必须保持 501，与输出条目数无关。
- 快照提交 9 次，`u_rms` 字段 812（TB 期望 762，偏 +6.6%，在 ±20% 判据内；偏差来源未查证）。
- 采样侧：帧间隔只有 1953/1954 拍、`adc_tick_pending` 恒 0 ⇒ 25.6 kHz 无丢样本。
- 本轮同时删除了一处死逻辑：`pqm_rfg_sample_pump`（其 `o_sample_valid/u/i` 在全链里没有任何消费者），
  删除前后 `pqm_pl_top` 用例的全部数值逐项不变。

## 4 未完成（下一步就在这里面挑）

1. ~~ADC 控速到 25.6 kHz~~ **已完成**（`pqm_adc_pacer` + `tb_pqm_adc_pacer`，见 §3.1）。
   ~~剩下的是接线：pacer 的 `o_tick` 接 `AD7606_Parallel_DRIVER.start`~~ **已完成**：`pqm_pl_top` 已接线；
   忙闲取舍已定 —— tick 撞上驱动忙时置粘滞标志 `adc_tick_pending`，正常时序下恒为 0（一帧约占 700 拍 < 周期 1953 拍）。
   代价要记住：采样率降 8 倍后，时域链过零分辨率变成 39 µs ⇒ 频率 ±0.1 Hz、相位 ±0.7°（PF 在 φ≈0 处二阶不敏感）。若不够，退回"102.4 kSPS 采 + 4 倍抽取给 RFG"。
2. ~~ABI/UI 收敛~~ **已完成**（PL + PS 两侧；PL 侧 `-Test pqm_pl_top` 与 `-All` 都重跑全绿）。
   - PL：`harmonic_stats.MAX_ORDER` 500→64、`PQM_SHM_HARMONIC_LAST_INDEX` `0x1F4`→`0x40`（=64），每帧 65 条；桥侧帧尾判定与 `harmonic_entry_addr`（9 bit 索引左移 2）在 65 条下无需改动。
   - 用例同步：`tb_pqm_pl_top`（帧尾 500→64）、`tb_harmonic_stats`、`tb_pqm_rfg_chain`、`tb_pqm_freq_analysis_rfg`、`tb_pqm_shared_memory_bridge` 都按 65 条重新基线；判据阈值一律未放宽。
   - PS：`PQMUI_HARMONIC_ENTRIES` 501→65、`POINTS` 26→16、`STEP` 25→16、`MAX_START` 475→48；窗口起点初值 1→**0**。
   - 分页语义按用户口径实现为**锚点制**：窗口起点 s∈{0,16,32,48} 是锚点，本页画 H(s+1)..H(s+16)（第 4 页 = H49–H64，正好到 ABI 末条 64）；第 1 页锚点 0 即 H0（直流，无占比含义），只在标签里体现为 `H0 - H16`，其余页标签 `H17 - H32`/`H33 - H48`/`H49 - H64`。
   - ⚠️ 用户原话「第 1 页 = H0 + H1–H16（共 17 条）」与显式宏 `PQMUI_HARMONIC_POINTS=16`（每页 16 个柱子）不能同时成立：本实现取 16 个柱子 + 标签带 H0。若确要让 H0 成为第 1 页的第 17 根柱子，需把 `PQMUI_HARMONIC_POINTS` 改 17 并让两图的 `lv_chart_set_point_count` 随之变化（柱宽会随之变）。
   - PS 侧**未编译**（本机无 ARM 工具链），只做了静态核对；柱子宽度因 16 点/页而由 LVGL 自动布局变化（414 px ÷ 16 槽）。
3. **`pqm_sample_fifo` 的写满/溢出路径没有独立用例**（现有用例只覆盖未满的正常流）。
4. **可选项**：把仿真的相位查表从行为级模型换成真 IP 生成的 `sim/rom_atan_lut_1024.v`（做法见 `pl/README.md`；同名的两个模块不能同时编译）。
5. **增量 6/7（大块）**：建 Vivado 工程（官方视频段参数逐条照抄官方 `.bd` 并冻结 + PQM 测量段），离线综合/实现拿资源与时序；上板验证等板子可用。旧工程 IP 照搬要先 `upgrade_ip`（2018.3 定制、2022.2 下 locked）。
6. 死代码：老 `divider_signed.v` 无人实例化（未清理）；`pqm_rfg_sample_pump`（取样缓冲，输出在全链里没有任何消费者）已于本轮删除。
7. ~~建 PL 测量链顶层并做系统级联调~~ **已完成**（`pqm_pl_top` + `tb_pqm_pl_top`，见 §3.2）；Vivado 集成见上面第 5 条。

## 5 约定与坑

- 仿真入口：`powershell -ExecutionPolicy Bypass -File scripts\run_xsim.ps1 -All`（26 例约 5 分钟，其中系统级用例 `pqm_pl_top` 单独占约 90 秒）；单例 `-Test <模块>`（7~12 秒）。
- 约定：`pl/rtl/<组>/<模块>.v` ↔ `pl/sim/<组>/tb_<模块>.v`，**组名必须一致**；判定必须看日志里的 `PASS: <用例名>`（`xsim -runall` 遇 `$fatal` 仍返回 0）。
- 用例需要额外源/向量时，在 `pl/sim/<组>/tb_<用例>.models.txt` 里逐行列目录（**按用例独立，漏建会让 readmemh 静默留 X**）。
- 数值检查必须带 `^actual === 1'bx` 守卫（Verilog 里 `if(X)` 为假，范围比较会静默放行）。
- 其它坑（BOM、`fork` 共用变量、单拍脉冲锁存、厂商握手时序等）见 `pl/README.md` 与 `.dsh/MEMORY.md` 的"坑与陷阱"。

## 6 本文件的维护

每完成一个增量就更新 §2/§3/§4，并在 `.dsh/PROGRESS.md` 追加一条。**不要**把"待办/进行中"写进 `.dsh/memory/` 的卡片（那是长期记忆，只管跨会话仍成立的事实与偏好）。
