# PQM2 交接文件

> 更新：2026-09-28 · 仓库 `C:\Users\zhangtao\Desktop\PQM2`
> 本文件写给"下一个会话"。先读它，再读 `pl/README.md`（PL 约定与踩坑）、`docs/BOARD_VERIFY.md`（上板验证清单）与 `.dsh/MEMORY.md`（长期记忆四域）。
> 提交计数与最新哈希**故意不写**（写这份文件时不允许执行 git 命令，写了就会过期）。以 `git log` 为准。

## 0 一句话现状

PS 界面按官方 `37_zynq_lvgl` 基线搭好并做到像素级等价；PL 测量链已连成系统、仿真回归 **30/30 全绿**；Vivado 集成（官方基线 BD + 共享内存 + 测量链）已产出比特流与 XSA；**上板已打通**——2026-09-28 实测显示通路寄存器与官方基线逐项吻合，DC 假偏置、THD 回绕、频率乱跳、相位图错误等缺陷全部消除。当前挂着的只有"还没看的验证项"（见 `docs/BOARD_VERIFY.md` §5），不是已知缺陷。

## 1 硬约束（不可违反）

1. 旧工程 `C:\Users\zhangtao\Desktop\PQM` **只读参考**，不修改；当前工程是 `PQM2`。另外三个只读目录：`C:\Users\zhangtao\Desktop\B-20260803`、`C:\Users\zhangtao\Desktop\zynq7020-examples`、`D:\zt\DeepSeek-Harness`。
2. PS 界面按**严格像素级等价**翻译旧界面：只改代码，画面不动。用户明确指定的可见改动除外（例如模拟市电倍率带来的纵轴刻度与量程按钮文案）。
3. 数值正确性靠**仿真**证明，不拿板上的数当验收 —— 信号源可换、波形由用户控制。板子现在是可用的，烧录与连板都不再受限，但"板上读到某个数"仍然不等于验收通过。

## 2 已完成（带证据）

| 块 | 状态 | 证据 |
| --- | --- | --- |
| PS 端（LVGL 界面 + 触摸 + 显示通路） | ✅ 完成并上板 | 以官方例程为基线；界面/交互/显示等价；修了厂商 `ft5206` 驱动宽高互换缺陷（右侧按钮点不到）；`LV_USE_PERF_MONITOR` 关闭。偏离项记在 `README.md` |
| 数据源 | ✅ 完成 | `app/pqmshm/` 读 PS/PL 共享内存 `0x40000000`；阶段 1 的假数据源 `app/demo/` **已整目录删除** |
| PL 时域链 | ✅ 单模块 + 系统级 | `AD7606_Parallel_DRIVER`、`p2p_measure`、`ui_rms_measure`、`power_metrics_calc`、`phase_diff_calc`、`frequency_measure`、`time_zero_code_tracker`、`time_x100_normalizer`、`time_parameters_initiator` 均有用例 |
| PL 频域链 | ✅ 单模块 + 整链 | 见 §3 |
| ADC 采样控速 25.6 kHz | ✅ | `pqm_adc_pacer`（26 位累加器、INC=34361），见 §3.1 |
| PL 测量链系统级验证 | ✅ | `pqm_pl_top` + `tb_pqm_pl_top`，见 §3.2 |
| Vivado 集成 | ✅ | 官方基线 BD + 共享内存 + 测量链；综合/实现/比特流/XSA 全部产出，时序全满足，0 Error / 0 Critical Warning，见 §3.3 |
| 上板 | ✅ 打通 | 见 §3.4 |
| 仿真基础设施 | ✅ | `scripts/run_xsim.ps1`：`-Test <模块>` / `-All`；支持 `.v` 与 `.sv`、行为级 IP 模型、用例级额外源清单。当前 **30/30 全绿** |
| 长期记忆 | ✅ | `.dsh/MEMORY.md`（四域）+ `.dsh/memory/` 卡片 + `.dsh/PROGRESS.md` |

**已查实并修掉的真实缺陷**：PL 侧 4 项、PS/app 侧 4 项、脚本侧 2 项，逐条见 §3.5 与 §3.6。

## 3 频域链现状

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

背景：一帧 RFG 取 N=512 点 = 一个 50 Hz 周期，要求采样率就是 **25.6 kHz**；旧工程"idle 即再启动"的自由跑与它不符（百 kSPS 量级），因此必须显式控速。

做法：26 位累加器小数分频，每个 50 MHz 时钟加 `INC = 34361`，进位即输出一个 1 拍宽的 `o_tick`。

- **增量不是 1953125**。旧交接文件里写的 `1953125 = 1953.125 × 1024` 是"把周期乘了 1024"，量纲不对；它在 26 位下得 34.36 拍/脉冲（1.455 MHz），与 25.6 kHz 差 57 倍。正确的频率字只能是 `周期拍数 = 2^W / INC` 的反解：`INC = 2^26 / 1953.125 = 34359.738 → 34361`。
- 为什么"平均严格"能成立：`1953.125 = 15625/8`，而 `15625 = 5^6` 与 2 互素，所以 `2^W / INC` **不可能**精确等于 1953.125（增量只能取整）。真正的判据是**整数拍窗口内脉冲数恰好为一个整数**：15625 拍内恰好 8000 个脉冲 → 平均 1953.125 拍/脉冲。残余量化误差 ≈ 3 ppm（约 0.08 Hz）。
- 相邻间隔只取 1953 或 1954 拍（Bresenham），抖动 ±1 拍（±20 ns @50 MHz），长时无累积误差。
- 选 34361 而不是更接近 34359.738 的 34360：后者会让间隔退化成恒定 1953 拍（`2^25 × 34360` 整除 `2^26`），每 8 个脉冲漂移 −1 拍；34361 给出标准交替。
- 纯时基：不看 ADC 忙闲（25.6 kHz 周期 1953 拍，一次采样约占 700 拍）；重触发策略已在 `pqm_pl_top` 里定案：tick 撞上驱动忙时不重触发，只置粘滞标志 `adc_tick_pending`。

验收（`-Test pqm_adc_pacer`）：

| 项 | 实测 | 期望 |
| --- | --- | --- |
| A 窗口 1786 个间隔跨拍数 | 3488153 | 3488153（`1786×2^26/34361`，容差 ±1 拍） |
| A 核账 | 1787 脉冲 / 1786 间隔，min_gap 1953、max_gap 1954 | — |
| A2 标定窗口 15625 拍内脉冲数 | 8 | 8 ±1 |
| B 越界间隔 / C 宽脉冲 | 0 / 0 | 0 |
| D 复位释放到首个脉冲 | 1954 拍 | 1954（`ceil(2^26/34361)`） |

## 3.2 PL 测量链系统级验收

用例 `pl/sim/PQM_TOP/tb_pqm_pl_top.v`，被测 `pl/rtl/PQM_TOP/pqm_pl_top.v`。激励：在 AD7606 引脚上挂芯片行为模型，喂代码级正弦 u = 1000·cos(ωn) + 400·cos(3ωn)、i = 800·sin(ωn)（滞后 90°）。TB 逐环判据：
1a 复位期无 tick ┊ 1b 每个 tick 都被消费（`adc_tick_pending`=0）┊ 1c 帧间隔 1953~1954 拍 ┊ 1d valid 与帧一一对应 ┊
2a 码值随正弦变化 ┊ 2b 零点收敛到 0x8000 ┊ 3in 送进 RFG 的前 24 点与解析值逐点相等 ┊ 3 谐波帧结构与 1 次占比 ┊
4 快照提交与 `u_rms` ┊ 5 桥写 BRAM 与共享内存 ABI 回读。

实测要点：

- 谐波 1 次 u 占比 7138、3 次 2861（解析 7142.9 / 2857.1），与频域链单模块验收一致。
- 共享内存 ABI 回读与核心输出逐项一致（`PQM_SHM_HARMONIC_BANK0_WORD = 0x400`、`BANK1 = 0xC00`，每条 `ENTRY_WORDS = 4` 字）。RFG 取点 `C_K=64`，所以 RFG 算出的频点里最大是 64；但 ABI 只暴露 0..63 共 64 条，`PQM_SHM_HARMONIC_LAST_INDEX = 0x3F`（=63），帧尾 index 与最大 present index 都是 63。
- 谐波 ABI 为 64 条（0..63），每帧 64 项（日志 `items=8×64=512`）。注意 `harmonic_stats` 内部的谐波缓存仍按 **bin 号**索引（`FUND_BIN=1` 时最大 bin=500），深度必须保持 501，与输出条目数无关。
- 采样侧：帧间隔只有 1953/1954 拍、`adc_tick_pending` 恒 0 ⇒ 25.6 kHz 无丢样本。
- `u_rms` 快照字段 812（TB 期望 23 ±20%；早前写的 762 是"把码域 RMS 当成工程量"的笔误，已按 ±20% 判据重新基线）。
- 本轮同时删除了一处死逻辑：`pqm_rfg_sample_pump`（其 `o_sample_valid/u/i` 在全链里没有任何消费者），删除前后用例全部数值逐项不变。

**大信号系统级用例**：`pl/sim/PQM_TOP/tb_pqm_pl_top_large.v`（本会话新增），断言相邻跳变上限、H1 下限、DC 上限、THD 上限，用来守住"大信号下不得饱和回绕"这条。

## 3.3 Vivado 集成

工程在 `vivado/`（`build_meas/` 已 gitignore）。构建脚本 `vivado/scripts/build_meas.tcl`，阶段由环境变量 `MEAS_STAGE` 控制（`bd` / `synth` / `all`，默认 `all`）。**进程工作目录必须是 `vivado/build_meas`**，否则 PS7 会把 `NA/` 写进源码根。

- 构成：官方 `37_zynq_lvgl` 的视频段 BD（`vivado/src/bd_official/system` → 复制到 `vivado/bd/meas/system`）+ 共享内存（`axi_bram_ctrl` + `blk_mem_gen_shared`）+ 顶层 `vivado/src/pqm2_meas_top.v`（内含 `clk_wiz_0` 与 `pqm_pl_top`）。
- 官方那份 BD 定制于 2020.2，构建脚本对它做 `upgrade_ip`。BD 不能放在 Vivado 工程目录里面（否则报 `[filemgmt 20-1381]` 重叠 CRITICAL WARNING），所以 `vivado/bd/meas/system` 与 `build_meas/` 是分开的。
- 复制过来的 `.bd` 与各 `ip/*/*.xci` 里内嵌的 `gen_directory` / `OUTPUTDIR` 必须改写成仓库内的绝对路径：不改会在源码根重建生成目录，甚至往只读参考工程里写 `zynq_lvgl.gen/`。两处已在 `build_meas.tcl` 处理。
- 结果：`vivado/pqm2_meas.bit`（4,045,673 B）与 `vivado/pqm2_meas.xsa` 全部产出；**0 Error / 0 Critical Warning**（DRC 414 条全是 Warning/Advisory，其中 `REQP-1839` 20 条 + `REQP-1840` 4 条落在测量链的 RAMB 异步控制脚，见 §3.5e）。
- 资源（post-impl，`vivado/reports_meas/post_impl_utilization.rpt`）：Slice LUTs 20513/53200 = **38.56%**、Slice Registers 23264/106400 = **21.86%**、Block RAM Tile 28/140 = **20.00%**、DSP 88/220 = **40.00%**、Bonded IOB 62/125 = **49.60%**、BUFGCTRL 5/32、MMCME2_ADV 2/4。
- 时序（`vivado/reports_meas/post_impl_timing_summary.rpt`）：WNS **+2.024** / TNS 0.000（失败端点 0 / 53846）；WHS **+0.046** / THS 0.000（0 / 53739）；WPWS +2.500 / TPWS 0.000（0 / 24127）。报告原文 **"All user specified timing constraints are met."**
- 对比旧工程基线（同为 xc7z020clg400-2，旧测量链含 xfft）：自研 RFG 省下 BRAM 与 DSP，代价是若干 LUT。

## 3.4 上板（2026-09-28，**已打通**）

三步链（每一步的完整命令见 `README.md` 的「构建 / 仿真 / 烧录」）：

1. `vivado/scripts/build_meas.tcl` → `vivado/pqm2_meas.xsa` + `vivado/pqm2_meas.bit`；
2. `scripts/build_app.ps1` → 从该 XSA 生成 Vitis 工作区并编译，产出
   `build/vitis_ws_meas/pqm2_hw/hw/pqm2_meas.bit`、`.../hw/ps7_init.tcl`、`build/vitis_ws_meas/pqm2_app/Debug/pqm2_app.elf`；
3. `scripts/flash_meas.tcl` → 复位系统 → 编程 PL → `ps7_init` → 下载 ELF → 等 10 s → 回读显示通路寄存器 → 抓共享内存。

实测：显示通路寄存器与官方基线**逐项吻合** —— VDMA CR `0001400B`、SR `00011000`、MM2S 起始地址 `01100000`、VTC `00013000`、`clk_wiz_0` `00000A01`、共享内存 magic `50514D31`。

**黑屏事故与根因（已解决）**：把某个比特流烧上去后屏幕全背光（只剩 `lcd_bl=1'b1` 常开的背光），`VDMA CR=00010002`、`VTC=0`。根因是**板上 ELF 与比特流不配套**——ELF 是按 `hw/system_wrapper.xsa`（2026-09-02，**只有视频段、无测量链**）编的，而它要访问 `axi_gpio_0`(0x41200000)、`clk_wiz_0`(0x43C00000)；app 一访问不存在的外设就挂死，VDMA/VTC 永远配不上 ⇒ 无像素数据。解决方式是把视频段改用官方 `37_zynq_lvgl` 的 BD（它带着应用需要的 `axi_gpio_0` 与 `clk_wiz_0`），并让 `build_app.ps1` 固定从 `vivado/pqm2_meas.xsa` 构建。**换比特流必须同时换 ELF。**

板上读值（信号源 CH1 18 Vpp / CH3 14 Vpp / 相差 −60°）与"修前"对照见 `docs/BOARD_VERIFY.md` 的判据表；要点：DC-U 28.67% → 0.02%、THD-U 180.67% → 0.03%、1 次谐波占比 10.99% → 99.64%、频率由乱跳的 52.46–85.05 Hz 收敛到 50.00 Hz。

## 3.5 已查实的真实缺陷与风险

**a) ROM 读握手两拍缺陷（已修，两个模块）**
`rom_atan_lut_1024` 的 `ena`→`douta` 需要**两拍**：`.xci` 为 `C_HAS_MEM_OUTPUT_REGS_A=1` + `C_READ_LATENCY_A=1` + `C_HAS_REGCEA=0`，故 `blk_mem_gen_v8_4.v` 的 `NUM_OUTPUT_STAGES_A=2`，且 `regce_i = (C_HAS_REGCE==0) && EN`，**`ena` 同时是存储器与输出寄存器的 CE**。旧设计两个状态机都按**一拍**取数 ⇒ 每次拿到上一次查表的值 ⇒ **相位与功率因数是错的**（幅值类不受影响）。旧的**手写行为级模型恰好是一拍，把该缺陷掩盖了**；旧工程 `PQM/FPGA/ip/rom_atan_lut_1024` 参数完全相同，**这是旧设计在真实硬件上一直存在的缺陷**。
修法：`ena` 拉宽到 REQ/WAIT 两拍，取数挪到新增的 `ST_ROM_CAP`(`phase_deg_lut_calc.v`，3'd6) / `ST_PHASE_ROM_CAP`(`time_x100_normalizer.v`，5'd16)；后者 `state` 由 `[3:0]` 加宽到 `[4:0]`（原编码 0~15 已用满）。
回归保护：`tb_time_x100_normalizer.v:172` 的 `check32(phase_x100, ...)` 能抓住时域链；`tb_pqm_pl_top.v` 有频域 1 次谐波相位断言（−9100 ~ −8900，即 −90.00°±1.00°）。两条都做过"回退即 FAIL、恢复即 PASS"的实测验证。

**b) `command_response_valid` 多驱动（已修）**
`pqm_pl_top.v` 里曾把它声明为 `input`，内部又接到 `pqm_range_command_controller.response_valid`（`output reg`），同一网络两个驱动源；命令响应本来就**没有外部来源**。已改为内部 `wire`。此前 TB 用 `.command_response_valid(1'b0)` 把它盖住，桥的命令响应通路在仿真里从未被验证过；这也是板上"RANGE ERROR"的根因。

**c) 共享内存异步双口无 CDC 保护（已修）**
逐原语查实的证据：`blk_mem_gen_shared` 是 `True_Dual_Port_RAM`，PORTA 归 AXI（`clk_fpga_0` = PS FCLK_CLK0 100 MHz），PORTB 归 PL（板载晶振经 clk_wiz 50 MHz）；两时钟来自不同晶振，`report_cdc` 明写 "No Common Primary Clock"，且该时钟对在 CDC 报告里**除官方 `axis_sample_cdc` 外一条记录都没有**。
修法：命令通道改为经 `pqm_shm_command_capture.v` 做两趟一致性检查后再受理；桥侧修掉 `if (capture_busy) bram_addr = ...` 抢地址却不撤 `bram_we` 的缺陷。**残余风险**：3 条 PL→PS 中断仍无同步器；`pl_resetn` 已加复位同步器（`reset_sync_n.v`）。构建时**故意没加 `set_clock_groups -asynchronous`**，以便跨域路径继续在报告里可见。

**d) 相位符号约定（已查清，非缺陷）**
仿真里 1 次谐波相位实测 **−9000**（x100），而解析值按标准 DFT 是 **+9000**，差 180°。根因：RFG 引擎 `pl/rtl/RFG/e01_rfg_direct_bin_engine.sv` 用的是 **`phase_negative_sine_q24`**，即虚部按 **−sin** 定义、等价 **e^{-jωt}**（与标准 DFT 的 e^{+jωt} 共轭）。U、I 走同一个引擎、同一约定，故**相对相位差是可信的**，只是整体取反：用户给的 60° 相差，板上显示 **−59.98°**，这是对的。

**e) 遗留告警（如实记录）**
- DRC `REQP-1839/1840` 共 24 条落在 PQM2 测量链（async reset 驱动 RAMB 地址脚，复位断言期间不被 STA 分析；运行期无害）。
- methodology 的 TIMING-4/TIMING-27 类 Critical Warning 在 `clk_wiz_pixel` 的 `clk_in1`，**参考工程里完全相同**，属继承。
- `pl_adc_tick_pending` 观测抽头即便加 `(* keep = "true" *)` 仍被优化掉（0 net）；测量链本身不受影响。
- `S_AXIS_SAMPLES` 无源：`pqm_pl_top` 不导出逐样本数据，`pqm_axis_sample_stream.v` 存在但未被实例化，DMA 样本路径空置。

## 3.6 本会话（2026-09-28）的修复

### 倍率：K 由 27.5 改为 38.89

市电 220 V 是**有效值**，峰值 220√2 = 311.13 V；信号源给的 16 Vpp（峰值 8 V）代表市电 220 V，故 **K = 220√2 / 8 = 38.89**，K² = 1512.43。
旧口径 `220/8 = 27.5` 把 220 当成了峰值，同一路 16 Vpp 输入只显示 RMS 155.6 V。
新口径下 ADC ±10 V（峰值）满量程对应 ±388.90 V，**满量程有效值恰为 275.00 V**，16 Vpp 输入显示 RMS 220.00 V。
纵轴刻度与量程按钮的取整由截断改为四舍五入（388.90 → 389）。
换算仍集中在 `PQMUI_ApplySimScale()`（`app/pqmui/pqmui_format.c`），是唯一的换算点。

### 频域页四项（全在 `app/pqmui/pqmui_freq.c`）

1. **相位图整张图本来是错的**。`lv_chart.c` 的 `draw_series_bar()` 里 `col_a.y2` 恒等于 `obj->coords.y2` —— **LVGL 的条形图一律从图表对象的底边往上长，没有零基线的概念**。幅度图值域是 0..10000，底边恰好是 0，所以看不出问题；相位图值域是 −180..+180，底边对应 −180，于是每根柱都从自己的相位值一路拉到 −180，读出来的其实是"离 −180 还有多远"。
   修法：挂 `LV_EVENT_DRAW_PART_BEGIN`，在矩形绘制前把两端掰到 0 刻度线上；正相位动 `y2`、负相位**两端都要动**（只动 `y1` 会让柱子从 0 线一路铺到图表底边）。同时把正负两个 series 合成一个、颜色在回调里逐柱改，这样正负柱都占满同一个块宽、x 位置不再随符号左右跳半格。
2. **零幅值谐波的相位是噪声**。实测：基波相位标准差 **0.0°**、峰峰值 **0.0°**；而占比 0.00% 的 H0/H2/H5/H7/H9/H11 标准差 3.5°~74°、峰峰值最大铺满 180°。抖动全部集中在零幅值谐波上 —— **不是"缺后级滤波"**，PL 的 `freq_harmonic_iir_filter` 本来就有 IIR，对噪声求平均得到的仍是无意义的数。加幅值门限 `PQMUI_HARMONIC_PHASE_MIN_RATIO_X100`（两路占比都不为 0 才画）。
3. **0 刻度线与底部横轴是两条线**。LVGL 主题给 chart 的默认上下内边距让绘图区比边框小一圈（实测 0 线在 y=296、对象边框在 y=307），而条形图又恒从对象底边起画，柱子会穿过 0 线扎到边框上。零掉频域两图的 `pad_top`/`pad_bottom`（并把柱子半径置 0）后，由 LVGL 自己合掉重复的那条。
4. **加横坐标刻度**：每根谐波都标绝对谐波号（第 1 页 `0..15`，第 2 页 `16..31`，依此类推），翻页跟着重排，位置按文字实际宽度重新居中。实测 16 个标签全部独立成组（无粘连），中心间距 24.9 px 与柱间距一致。

### 两个脚本缺陷

5. **`scripts/flash_meas.tcl`**：原先只在 DAP 报错时才复位系统。DAP 健康时直接盖 `ps7_init`，会把上一次应用的 SCU 定时器与 GIC 使能位留给新应用 —— 新应用在 `timer_init()` 注册 `XIL_EXCEPTION_ID_INT` **之前**就吃到 IRQ，直接落进 `Xil_ExceptionNullHandler`（实测 PC = `0x001a0d1c`、CPSR 停在 IRQ 模式），显示通路一行都跑不到（`VDMA CR=0x00010002`、`VTC=0`）。已改为 `ps7_init` 前无条件复位系统、`dow` 前补 `rst -processor`，并给 `ps7_init` 加"失败→系统复位→重试"兜底。
6. **`scripts/build_app.ps1`**：原先指向 `create_workspace.tcl`，而那个脚本用的是旧 XSA `hw/system_wrapper.xsa`（纯 PS、没有 `clk_wiz_0`/`axi_gpio_0`），照文档命令编出来的是**错硬件的 BSP**，烧上去就是黑屏。已改为 `create_workspace_meas.tcl` 与 `vivado/pqm2_meas.xsa`。

### 新增工具

7. **`scripts/inject_touch.tcl`**：经 JTAG 注入触摸点击（把 `tp_dev.scan` 临时指向 `Xil_DCacheFlush()` 空操作，注入 `sta`/`x`/`y` 后还原），切页与按按钮不再需要手点。背景：`touchpad_is_pressed()` 每 30 ms 都调 `tp_dev.scan()`，直接写 `sta` 会被立刻覆盖。**注意文件顶部那三个符号地址随每次重新编译变化**，头部注释给了取值的 `nm` 命令。
8. 一批只读诊断脚本：`trace_phase.tcl`（连抓谐波表量化相位稳定性）、`check_app_vars.tcl` / `check_phase_points.tcl`（直接读运行中应用里的点数组与全局量）、`probe_app_state.tcl`、`probe_ps_access.tcl`、`probe_touch_inject.tcl`。

### PL 侧四项

9. `time_zero_code_tracker.v`：移位用 floor 舍入使步长非奇数，纯 AC（零直流）下零点收敛到 28132 而非 `0x8000`，板上表现为 **28.67% 的假直流**；改为向零舍入（sign-magnitude）后残差 127 码，TB 补纯 AC 场景。
10. `pqm_measurement_core.v`：频率中心化量的 17 位乘积被截成 `[15:0]`，只要 `|sample-zero| > 32767` 就回绕，18 Vpp 正弦下 **THD-U 报 180.67%**；改为饱和，并把饱和/溢出粘滞位写进 validity bit12/13/14（新增 `PQM_SHM_VALIDITY_CENTER_SAT / RFG_OVERFLOW / FIFO_OVERFLOW` 与 `TRUST` 掩码）。
11. `pqm_freq_analysis_rfg.v`：帧边界重复发 `start_pulse`；新增 `o_center_sat` / `o_rfg_overflow` / `o_fifo_overflow`。
12. `pqm_rfg_dc_sum.v` / `pqm_rfg_frontend.v`：去直流的截断改为带符号相减后饱和（直接饱和会破坏补码重解释的直通，TB 里 DC 从 0% 跳到 95.95%）。

## 4 未完成（下一步就在这里面挑）

1. **补 `docs/BOARD_VERIFY.md` §5 里"还没看"的验证项**：小量程页、谐波翻页、`Freeze`/`Resume`（现已可用 `scripts/inject_touch.tcl` 自动点）；以及边界条件（阈值附近的小信号、上电瞬态、`drop_count` 在异常激励下的行为）。
2. **频率测量在畸变波形下的口径**。当前 `frequency_measure.v` 用零点穿越 + 迟滞 + 线性插值；纯正弦下稳定（板上 10 次采样 50.00~50.01 Hz）。但**当波形含强 5/7 次谐波时，一个基波周期内会多出几对零点，穿越计数给出的就是"穿越率"而不是基波频率**（实测一次强畸变输入下读到 249.96 Hz）。该次输入是用户自己改的波形、用户明确说不算缺陷，所以**没有改**；但它是一条真实的口径限制，若要覆盖畸变波形，应改用 RFG 的 1 号 bin 定频率，或加大迟滞/取主周期。
3. **`S_AXIS_SAMPLES` 样本流路径空置**（`pqm_axis_sample_stream.v` 未被实例化）。若要做原始波形上传/录波，需要接上这条路径。
4. **`pl_adc_tick_pending` 观测抽头被综合优化掉**，需要时用别的观测手段（例如导出到共享内存的保留字）。
5. **CDC 的残余项**：3 条 PL→PS 中断无同步器；`set_clock_groups -asynchronous` 故意未加。若哪天要正式收敛 STA，需要一并处理这几处（并接受跨域路径从报告里消失）。
6. **`vivado/pqm2_meas.xsa` / `.bit` 是 gitignore 的构建产物**，写这份文件时工作区里没有它们；要上板必须先跑一次 Vivado 构建（约 25–30 分钟），见 `README.md`。

## 5 约定与坑

- 仿真入口：`powershell -ExecutionPolicy Bypass -File scripts\run_xsim.ps1 -All`（当前 **30 例**，其中系统级用例 `pqm_pl_top` 单独占约 95 秒）；单例 `-Test <模块>`（7~12 秒）。
- 约定：`pl/rtl/<组>/<模块>.v` ↔ `pl/sim/<组>/tb_<模块>.v`，**组名必须一致**；判定必须看日志里的 `PASS: <用例名>`（`xsim -runall` 遇 `$fatal` 仍返回 0）。
- 用例需要额外源/向量时，在 `pl/sim/<组>/tb_<用例>.models.txt` 里逐行列目录（**按用例独立，漏建会让 readmemh 静默留 X**）。该文件必须用 **CRLF**：用 LF 时 Windows PowerShell 5.1 会把它读成一整行，吞掉第一项。
- 数值检查必须带 `^actual === 1'bx` 守卫（Verilog 里 `if(X)` 为假，范围比较会静默放行）。
- 其它坑（BOM、`fork` 共用变量、单拍脉冲锁存、厂商握手时序等）见 `pl/README.md` 与 `.dsh/MEMORY.md` 的"坑与陷阱"。

## 6 本文件的维护

每完成一个增量就更新 §2/§3/§3.6/§4，并在 `.dsh/PROGRESS.md` 追加一条。**不要**把"待办/进行中"写进 `.dsh/memory/` 的卡片（那是长期记忆，只管跨会话仍成立的事实与偏好）。
