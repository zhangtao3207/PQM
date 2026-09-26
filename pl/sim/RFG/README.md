# RFG 移植记录（来自 Goertzel_FPGA 研究项目）

## 来源

- 源工程：`C:\Users\zhangtao\Desktop\Goertzel_FPGA`
- 算法：RFG（基于 Goertzel 的折叠优化），主线入口 `e01_rfg_nkld_top`
- 逐文件对应：

| 本仓库 | 源 |
| --- | --- |
| `pl/rtl/RFG/*.sv` | `rtl/E01/rfg/*.sv`（12 个） |
| `pl/rtl/RFG/common/*.sv` | `rtl/E01/common/four_part_mul_dsp1.sv`、`twiddle_policy_q24.sv` |
| `pl/rtl/RFG/common/fft_twiddle_q24.sv` | `rtl/E01/fft/fft_twiddle_q24.sv`（共享 LUT，`e01_twiddle_policy_q24` 要用，不搬会 elaborate 失败） |
| `pl/sim/RFG/tb_e01_rfg_l4_optimization.sv` | `sim/E01/rfg/tb_e01_rfg_direct_l.sv`（模块名就是 `tb_e01_rfg_l4_optimization`） |
| `pl/sim/RFG/vectors/*.hex` | `data/E01/rfg_scan/N512/K64/L4/D1/{input,expected}_*.hex` |

## 移植时改了什么（只有这四处）

1. **向量路径前缀**：TB 原本 `$readmemh("vectors/xxx.hex")`，改成 `xxx.hex`；向量由
   `tb_<用例>.models.txt` 里的 `pl/sim/RFG/vectors` 平铺复制进 build 目录。
2. **TB 参数默认值**：`C_N 64→512`、`C_K 25→64`（PQM2 的取点：一帧 = 一个 50 Hz 周期，
   25.6 kHz 采样，只算前 64 次谐波）。`C_L=4`、`C_D=1` 沿用源默认。
3. **补一行通过标记**：`$display("PASS: e01_rfg_l4_optimization")`，因为 `run_xsim.ps1`
   的判定口径要求日志里出现 `PASS: <用例名>`。
4. **场景别名**：TB 的场景名 `tone_edge` 在扫描点里叫 `tone_kK`（K = 该点的目标频点数上限，
   N512/K64 就是 `tone_k64`），复制时改名。**注意 K 变了别名也要跟着变**：
   N64/K25 的点必须用 `tone_k25`，用错会出现"冻结向量位真比对"失败。

RTL 本身**一个字符都没改**。

## 怎么跑

```powershell
powershell -ExecutionPolicy Bypass -File scripts\run_xsim.ps1 -Test e01_rfg_l4_optimization
```

`run_xsim.ps1` 已支持 `.sv`（`xvlog -sv`）、`.sv` 测试平台、以及用例级
`tb_<用例>.models.txt`（列额外源目录与数据目录）。实测一次 10.6 秒。

## 在 PQM2 环境里的实测结果（N512/K64/L4/D1）

```
E01_RFG_FROZEN_VECTOR_PASS vector=0..4   cycles=83840/84048/84033/84046/84037
E01_COMMON_ACCURACY_RFG ... 占用 0% / 7.6% / 24.3% / 1.2% / 11.1%  verdict=PASS
E01_RFG_PROTOCOL_ALL_PASS
E01_RFG_ALL_CASES_PASS
```

`cycles=83840`（vector=0）与源工程归档 `data/E01/scan_archive/all_points.csv` 里
N512/K64/L4/D1 的 `frame_cycles=83840` **完全一致**，说明移植环境与原工程等价。
