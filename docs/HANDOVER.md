# PQM2 交接文件

> 更新：2026-09-27 · 仓库 `C:\Users\zhangtao\Desktop\PQM2` · 提交 28 次 · 最新 `9ce670b`
> 本文件写给"下一个会话"。先读它，再读 `pl/README.md`（PL 约定与踩坑）与 `.dsh/MEMORY.md`（长期记忆四域）。

## 0 一句话现状

PS 端界面已按官方 `37_zynq_lvgl` 基线搭好并做到像素级等价；PL 测量链**已连成系统并通过系统级仿真**（`pqm_pl_top` + `tb_pqm_pl_top`，`-All` 共 27 个用例全绿），**频域链已从 Xilinx xfft 完全切到自研 RFG**，**ADC 采样控速（`pqm_adc_pacer`，25.6 kHz）已做完并有用例**，**谐波 ABI/UI 已收敛为 64 条（0..63）+ 4 页 × 16 条**。尚未做：Vivado 集成与上板（板子断电）。

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
INFO: 3 harm_frames=8 items=512 max_index=63 last=63 h1_present=1 h1_ratio=7138
INFO: 3in  RFG 输入前 24 点不符 0 个
INFO: 4 commit=9 u_rms=812（期望约 762）bram_wr=2798 harm_wr=2016
INFO: 5abi  从共享内存解出：1次u=7138 3次u=2861 present=1 最大index=63
PASS: pqm_pl_top
```

要点：
- 谐波 1 次 u 占比 7138、3 次 2861（解析 7142.9 / 2857.1），与频域链单模块验收一致。
- 共享内存 ABI 回读与核心输出逐项一致（bank0 基址 word `0x400`、bank1 `0x800`，每条 4 word）。RFG 取点 `C_K=64`，
  所以 RFG 算出的频点里最大是 64；但 ABI 只暴露 0..63 共 64 条，帧尾 index 与最大 present index 都是 63（64 次以上不再进共享内存）。
- 谐波 ABI 为 64 条（0..63），每帧 64 项（日志 `items=8×64=512`，帧尾 `last=63`）。注意 `harmonic_stats`
  内部的谐波缓存仍按 **bin 号**索引（FUND_BIN=1 时最大 bin=500），深度必须保持 501，与输出条目数无关。
- 快照提交 9 次，`u_rms` 字段 812（TB 期望 762，偏 +6.6%，在 ±20% 判据内；偏差来源未查证）。
- 采样侧：帧间隔只有 1953/1954 拍、`adc_tick_pending` 恒 0 ⇒ 25.6 kHz 无丢样本。
- 本轮同时删除了一处死逻辑：`pqm_rfg_sample_pump`（其 `o_sample_valid/u/i` 在全链里没有任何消费者），
  删除前后 `pqm_pl_top` 用例的全部数值逐项不变。

## 3.3 Vivado 集成（2026-09-27，已完成）

工程在 `vivado/`（`build/` 已 gitignore），一键构建：`cd vivado/build; D:\zt\Xilinx\Vivado\2022.2\bin\vivado.bat -mode batch -source ..\scripts\build.tcl`（约 25–30 分钟）。

- 构成：官方视频段 BD（`vivado/src/bd/pqm_ps/`，从参考工程 `PQM_SOC` **原样复制并冻结**，逐条参数未改）+ PQM2 测量段（`pl/rtl` 全部）。顶层 `vivado/src/pqm2_top.v`。
- **参考工程的 BD/IP 就是 2022.2 原生的，不需要 `upgrade_ip`**（`PQM_SOC.xpr` 头即 v2022.2，`.cache/ip/2022.2/` 存在）。交接文件旧文里“2018.3 定制、2022.2 下 locked、必须 upgrade_ip”的说法**作废**。
- 结果：synth + impl + write_bitstream + XSA 全部成功，**0 Critical Warning / 0 Error**，DRC 0 Error。
- 资源（post-impl，Fully Routed，`vivado/reports/post_impl_utilization.rpt`）：LUT 20464/53200 = 38.47%、寄存器 23994/106400 = 22.55%、Block RAM Tile 29/140 = 20.71%、DSP48E1 86/220 = 39.09%、IOB 66/125 = 52.80%、BUFGCTRL 5/32、MMCME2_ADV 2/4。
- 对比旧工程基线（同为 xc7z020clg400-2，旧测量链含 xfft）：LUT 37.06%→38.47%（+1.4pt）、BRAM 42→29 Tile（**−13**）、DSP 94→86（**−8**）——自研 RFG 省下 BRAM 与 DSP，代价是约 750 个 LUT。
- 时序（`vivado/reports/post_impl_timing_summary.rpt`）：WNS **+1.185** / TNS 0.000（失败端点 0 / 56690）、WHS +0.022 / THS 0.000、WPWS +3.000 / TPWS 0.000，**“All user specified timing constraints are met”**。
- 产物：`vivado/system.bit`（4045668 B）、`vivado/pqm2_system.xsa`（1042967 B，内嵌 bit + `pqm_ps.hwh` + `ps7_init.*`）。
- 构建脚本必须改写复制过来的 `pqm_ps.bd` 与各 `ip/*/*.xci` 里的 `gen_directory`/`OUTPUTDIR`（否则会在源码根重建 `PQM_SOC.gen/`），且 Vivado 要以 cwd=`vivado/build` 启动（PS7 的 `PCW_UIPARAM_GENERATE_SUMMARY="NA"` 会往进程 cwd 写 `NA/`）。两处已在 `build.tcl` 处理。

## 3.4 上板（2026-09-27，**未打通**）

- 板子可用：JTAG = Digilent JTAG-HS1，链上 `arm_dap` + `xc7z020`（idcode 23727093）。上板脚本 `scripts/board_run.tcl`（烧 `vivado/system.bit`）、`scripts/board_restore.tcl`（回退到旧组合）。
- **黑屏事故与根因**：把 `vivado/system.bit` 烧上去后屏幕全背光。根因是**板上 ELF 与比特流不配套**——`build/vitis_ws/pqm2_app/Debug/pqm2_app.elf` 是按 `hw/system_wrapper.xsa`（2026-09-02，**只有视频段、无测量链**）编译的，它要访问 `axi_gpio_0`(0x41200000)、`clk_wiz_0`(0x43C00000) 这些**新 BD 里不存在**的外设，app 一访问就挂死，VDMA/VTC 永远配不上 ⇒ 无像素数据、只剩 `lcd_bl=1'b1` 常开的背光。
- **已回退**：烧 `build/vitis_ws/pqm2_hw/hw/system_wrapper.bit`（旧版，4045674 B，MD5 `7B6020EE...`，与 XSA 内嵌一致）+ 旧 ELF，画面已恢复。回读与 2026-09-26 成功基线**逐项一致**：`vdma CR=0001400B`、`SR=00011000`、`addr=01100000`、`v_tc st=00013000`、`clk_wiz_0=00000A01`。
- **打通上板还缺**：用 `vivado/pqm2_system.xsa` 重建 Vitis 平台 → 重编 ELF → 再烧。另外 `vivado/system.bit` 构建于 20:19，**不含 20:26 的 ROM 修复**，必须重跑构建才与当前 RTL 一致。
- 两个比特流的硬件不同：旧的（`system_wrapper.bit`）有 `axi_gpio_0`/`clk_wiz_0`；新的（`system.bit`）没有这两个，但多了 `blk_mem_gen_shared`、`axi_bram_ctrl`、`axis_sample_cdc/slice`。**换比特流必须同时换 ELF。**
- 已确认的通道映射：`pqm_pl_top.v:211-212` ⇒ **U = AD7606 CH1，I = CH3**（用户 2026-09-27 接线：U 3 Vpp、I 4 Vpp、50 Hz、相差 30°）。

## 3.5 本轮新发现的真实缺陷与风险

**a) ROM 读握手两拍缺陷（已修，两个模块）**
`rom_atan_lut_1024` 的 `ena`→`douta` 需要**两拍**：`.xci` 为 `C_HAS_MEM_OUTPUT_REGS_A=1` + `C_READ_LATENCY_A=1` + `C_HAS_REGCEA=0`，故 `blk_mem_gen_v8_4.v` 的 `NUM_OUTPUT_STAGES_A=2`，且 `regce_i = (C_HAS_REGCE==0) && EN`，**`ena` 同时是存储器与输出寄存器的 CE**。旧设计两个状态机都按**一拍**取数 ⇒ 每次拿到上一次查表的值 ⇒ **相位与功率因数是错的**（幅值类不受影响）。旧的**手写行为级模型恰好是一拍，把该缺陷掩盖了**；旧工程 `PQM/FPGA/ip/rom_atan_lut_1024` 参数完全相同，**这是旧设计在真实硬件上一直存在的缺陷**。
修法：`ena` 拉宽到 REQ/WAIT 两拍，取数挪到新增的 `ST_ROM_CAP`(`phase_deg_lut_calc.v`，3'd6) / `ST_PHASE_ROM_CAP`(`time_x100_normalizer.v`，5'd16)；后者 `state` 由 `[3:0]` 加宽到 `[4:0]`（原编码 0~15 已用满）。**改动是等价的**：修复前后全部数值逐项相同（`h1_ratio=7138`、`3次u=2861`、`u_rms=812`、`harm_wr=2048`、`ph=-9000`）。
回归保护：`tb_time_x100_normalizer.v:172` 的 `check32(phase_x100, ...)` 能抓住时域链；本轮又给 `tb_pqm_pl_top.v` 新增了频域 1 次谐波相位断言（**-9100 ~ -8900**，即 -90.00°±1.00°）。两条都做过“回退即 FAIL、恢复即 PASS”的实测验证。

**b) `pqm_pl_top.command_response_valid` 多驱动（未修）**
`pqm_pl_top.v:62` 把它声明为 `input`，`:388` 接给 `pqm_shared_memory_bridge` 的输入，`:409` 又接到 `pqm_range_command_controller.response_valid`（**`output reg`**）——同一网络两个驱动源。命令响应本来就**没有外部来源**（响应由 PL 内部控制器产生），声明成 `input` 本身就是错的，应是内部 wire。TB 用 `.command_response_valid(1'b0)`（`tb_pqm_pl_top.v:238`）把它盖住了，所以**桥的命令响应通路在仿真里从未被验证过**。新建的 `pqm2_top.v` 索性不接该端口，综合才干净（0 Critical Warning）。**待修。**

**c) 共享内存异步双口无 CDC 保护（未修，真风险）**
逐原语查实的证据：`blk_mem_gen_shared` 是 `True_Dual_Port_RAM`，PORTA 归 AXI（`clk_fpga_0` = PS FCLK_CLK0 100 MHz），PORTB 归 PL（`clk_out1_clk_wiz_0` = 板载 U18 晶振经 clk_wiz 50 MHz）；**16 个 RAMB36 全部** `CLKARDCLK: clk_fpga_0` / `CLKBWRCLK: clk_out1_clk_wiz_0`。两时钟来自不同晶振，`report_cdc` 明写 **“CDC Type: No Common Primary Clock”**，而该时钟对在 `report_cdc` 里**除官方 `axis_sample_cdc` 外一条记录都没有**——这个跨域对 CDC/STA 完全不可见（`report_clock_interaction` 判为 Ignored / False Path / Max Delay Datapath Only）。
风险：① 同址读写冲突（PL 轮询命令序号时 PS 可能正在写同一字，UG473 规定结果未定义）；② PS 先写 REQUEST 再写 SEQUENCE，PL 隔 2 个 PORTB 周期读 REQUEST，可见性无屏障约束；③ `PL_SHARED_BRAM_rst` 是异步板级复位而 BRAM 声明 `Reset_Type: SYNC`，且 `sys_rst_n` 无时钟⇒recovery/removal 未被分析（整条 PL 链的 `negedge pl_resetn` 同病）；④ 3 条 PL→PS 中断无同步器。
**处理建议（未实施）**：XDC 显式声明异步时钟组；把标志轮询换成单比特 req/ack 两级同步握手；最低成本兜底是要求 SEQUENCE 连续两次读到相同值才受理命令；给 `pl_resetn` 加复位同步器。构建时**故意没加 `set_clock_groups -asynchronous`**，以便跨域路径继续在报告里可见。

**d) 相位符号约定（已查清，非缺陷）**
仿真里 1 次谐波相位实测 **-9000**（x100），而解析值按标准 DFT 是 **+9000**，差 180°。根因已坐实：RFG 引擎 `pl/rtl/RFG/e01_rfg_direct_bin_engine.sv` 用的是 **`phase_negative_sine_q24`**（第 184–216 行），即虚部按 **−sin** 定义、等价 **e^{-jωt}**（与标准 DFT 的 e^{+jωt} 共轭）。U、I 走同一个引擎、同一约定，故**相对相位差是可信的**，只是整体取反：用户给的 30° 相差，板上应显示 **−30°（−3000）**。接 UI 时必须处理这个符号，否则会显示成 150°/−30°。

**e) 遗留告警（如实记录）**
- DRC `REQP-1839/1840` 共 24 条落在 PQM2 测量链（`u_freq_harmonic_iir_filter/state_mem_reg*`，async reset 驱动 RAMB 地址脚，复位断言期间不被 STA 分析；运行期无害）。
- methodology 2 条 TIMING-4/TIMING-27 Critical Warning 在 `u_pqm_ps/clk_wiz_pixel/inst/clk_in1`，**参考工程里完全相同**，属冻结 BD 继承。
- `pl_adc_tick_pending` 观测抽头即便加 `(* keep = "true" *)` 仍被优化掉（0 net）；测量链本身不受影响（`bram_*` 接进 BD、`alarm_active` 接 LED）。
- `S_AXIS_SAMPLES` 无源：`pqm_pl_top` 不导出逐样本数据，`pqm_axis_sample_stream.v` 存在但未被实例化，DMA 样本路径空置。

## 4 未完成（下一步就在这里面挑）
1. ~~ADC 控速到 25.6 kHz~~ **已完成**（`pqm_adc_pacer` + `tb_pqm_adc_pacer`，见 §3.1）。
   ~~剩下的是接线：pacer 的 `o_tick` 接 `AD7606_Parallel_DRIVER.start`~~ **已完成**：`pqm_pl_top` 已接线；
   忙闲取舍已定 —— tick 撞上驱动忙时置粘滞标志 `adc_tick_pending`，正常时序下恒为 0（一帧约占 700 拍 < 周期 1953 拍）。
   代价要记住：采样率降 8 倍后，时域链过零分辨率变成 39 µs ⇒ 频率 ±0.1 Hz、相位 ±0.7°（PF 在 φ≈0 处二阶不敏感）。若不够，退回"102.4 kSPS 采 + 4 倍抽取给 RFG"。
2. ~~ABI/UI 收敛~~ **已完成**（PL + PS 两侧；PL 侧 `-Test pqm_pl_top` 与 `-All` 都重跑全绿）。
   - PL：`harmonic_stats.MAX_ORDER` 500→64→63、`PQM_SHM_HARMONIC_LAST_INDEX` `0x1F4`→`0x40`(=64)→`0x3F`(=63)，最终每帧 **64 条（0..63）**；桥侧帧尾判定用宏、条目地址 = 基址 + (9 bit 索引 << 2)，64 条下无需改代码。
   - 用例同步：`tb_pqm_pl_top`（帧尾 500→64→63、`items` 65→64）、`tb_harmonic_stats`（`MAX_ORDER` 64→63）、`tb_pqm_rfg_chain`（`HARM_ORDERS` 65→64、帧尾 order 恰为 63）、`tb_pqm_freq_analysis_rfg`（`HARM_ORDERS` 65→64）、`tb_pqm_shared_memory_bridge`（发 0..63，bank1 末条校验 `(63<<2)+3 = 0x4000003F`）都按 64 条重新基线；**顶层阈值判据一个没放宽**。
   - PS：`PQMUI_HARMONIC_ENTRIES` 501→65→**64**，`POINTS=16` / `STEP=16` / `MAX_START=48` 不变；窗口起点初值为 **0**。
   - 分页语义为**直接索引制**：窗口起点 s∈{0,16,32,48} 就是本页首条，本页画 H(s)..H(s+15)，4 页 = H0–H15 / H16–H31 / H32–H47 / H48–H63（无重复、无空洞），页码标签由 `H(s) - H(s+15)` 生成。
   - **H0 在图上是不画柱的（空槽）**：H0 的 4 个 word 会写进共享内存（帧头缺陷已修，实测 `harm_wr=2048=64×4×8`、共享内存 k=0..63 齐全），但其 `flags` present 位为 0（直流幅值≈0，未过 `harmonic_stats` 的 present 阈值），PS 侧因此画 `LV_CHART_POINT_NONE`。这是用户 2026-09-27 确认的口径：**H0 保持空槽，不强制画 0 高度柱**。
   - PS 侧**未编译**（本机无 ARM 工具链），只做了静态核对；4 页槽数都是 16，柱宽与折线间距不随翻页变化。
3. ~~`pqm_sample_fifo` 的写满/溢出路径没有独立用例~~ **已完成**：`tb_pqm_sample_fifo_overflow`（7 个场景，`-Test pqm_sample_fifo_overflow` 约 8 秒）。
4. ~~把仿真的相位查表从行为级模型换成真 IP 生成的 `sim/rom_atan_lut_1024.v`~~ **已完成**：`pl/sim/models/rom_atan_lut_1024/` 放真 IP 网表 + `blk_mem_gen_v8_4.v` + 初始化文件。**注意初始化文件是 `.mif` 不是 `.mem`**：网表传 `C_INIT_FILE_NAME("rom_atan_lut_1024.mif")`，blk_mem_gen 走 `$fopen`+`$fscanf("%b")`；`C_INIT_FILE("...mem")` 那条 `$readmemh` 包在 `C_USE_BRAM_BLOCK` 里、本 IP 该参数为 0，永不执行。放错文件名会在 0 时刻 `WARNING: file ... could not be opened` 后 `$finish`。
5. **Vivado 集成已完成**（`vivado/`，见 §3.3）：综合+实现+比特流+XSA 全部产出，时序全满足，0 Critical Warning。**但下一条是硬缺口。**
6. **上板未打通（下一块工作，见 §3.4）**：`vivado/system.bit` 烧上板会黑屏，因为板上 ELF 是按旧 XSA（`hw/system_wrapper.xsa`，只有视频段）编的，访问 `axi_gpio_0`/`clk_wiz_0` 等新 BD 里不存在的外设 → app 挂死。**必须用 `vivado/pqm2_system.xsa` 重建 Vitis 平台并重编 ELF**，光烧 PL 不行。另：`vivado/system.bit` 构建于 20:19，**不含当晚 20:26 的 ROM 修复**，要匹配当前 RTL 需重跑构建（`cd vivado/build; vivado.bat -mode batch -source ..\scripts\build.tcl`，约 25–30 分钟）。
7. ~~死代码：老 `divider_signed.v` 无人实例化（未清理）~~ **本条为误记，已核实作废**：`divider_signed.v` 在 `ui_rms_measure.v:195` 被实例化为 `u_active_p_mean_divider`（有功功率均值的有符号除法），输出 `active_p_div_quotient` 被 `ui_rms_measure.v:237-240` 的溢出判据与 `:368` 的 `active_p_raw` 消费，而 `ui_rms_measure` 又被 `time_parameters_initiator.v:227` 实例化——**是活代码，不能删**；该文件由本工程 `afb4bbd` 引入，旧工程 PQM 中并无此文件。真死代码 `pqm_rfg_sample_pump` 已于本轮删除。
8. ~~建 PL 测量链顶层并做系统级联调~~ **已完成**（`pqm_pl_top` + `tb_pqm_pl_top`，见 §3.2）。
9. **两个新发现的真实 RTL 缺陷/风险（见 §3.5）**：a) ROM 读握手两拍缺陷（已修）；b) `pqm_pl_top.command_response_valid` 多驱动（未修）；c) 共享内存异步双口无 CDC 保护（未修）。

## 5 约定与坑

- 仿真入口：`powershell -ExecutionPolicy Bypass -File scripts\run_xsim.ps1 -All`（27 例约 5 分钟，其中系统级用例 `pqm_pl_top` 单独占约 95 秒）；单例 `-Test <模块>`（7~12 秒）。
- 约定：`pl/rtl/<组>/<模块>.v` ↔ `pl/sim/<组>/tb_<模块>.v`，**组名必须一致**；判定必须看日志里的 `PASS: <用例名>`（`xsim -runall` 遇 `$fatal` 仍返回 0）。
- 用例需要额外源/向量时，在 `pl/sim/<组>/tb_<用例>.models.txt` 里逐行列目录（**按用例独立，漏建会让 readmemh 静默留 X**）。
- 数值检查必须带 `^actual === 1'bx` 守卫（Verilog 里 `if(X)` 为假，范围比较会静默放行）。
- 其它坑（BOM、`fork` 共用变量、单拍脉冲锁存、厂商握手时序等）见 `pl/README.md` 与 `.dsh/MEMORY.md` 的"坑与陷阱"。

## 6 本文件的维护

每完成一个增量就更新 §2/§3/§4，并在 `.dsh/PROGRESS.md` 追加一条。**不要**把"待办/进行中"写进 `.dsh/memory/` 的卡片（那是长期记忆，只管跨会话仍成立的事实与偏好）。
