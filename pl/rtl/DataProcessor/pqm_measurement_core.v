`timescale 1ns / 1ps

/*
 * 模块: pqm_measurement_core
 * 功能:
 *   在 PS 显示模式下保留确定性的时域测量、频域谐波统计和骤变告警，
 *   直接生成共享内存标量快照与谐波流，不实例化任何 PL 显示或文本格式化逻辑。
 * 输入:
 *   clk: 采样、时域测量与频域分析共用的 50 MHz 工作时钟。
 *   rst_n: 低有效异步复位。
 *   full_scale_low_range_active: 历史量程选择端口。阶段 1 起 PL 固定使用真实（小量程）满量程，
 *     本端口不再参与任何换算；为不牵动顶层 pqm_pl_top 与 BD 端口表暂时保留（未使用）。
 *   u1_sample_valid: U1样本有效脉冲。
 *   u1_sample_code: U1 ADC 原始采样码。
 *   u1_zero_code: U1零点跟踪码。
 *   u1_zero_valid: U1零点跟踪结果有效标志。
 *   u2_sample_valid: U2样本有效脉冲。
 *   u2_sample_code: U2 ADC 原始采样码。
 *   u2_zero_code: U2零点跟踪码。
 *   u2_zero_valid: U2零点跟踪结果有效标志。
 *   ps_harmonic_ready: 共享内存桥允许接收当前谐波条目。
 * 输出:
 *   alarm_active: U1或U2 RMS 骤升、骤降告警有效标志。
 *   ps_snapshot_words: 按共享内存 ABI word15 到 word0 排列的标量快照。
 *   ps_snapshot_commit_toggle: 标量或频域指标更新后的提交 toggle。
 *   ps_harmonic_valid: 当前谐波条目有效标志。
 *   ps_harmonic_last: 当前条目为谐波帧最后一项。
 *   ps_harmonic_index: 当前谐波阶次。
 *   ps_harmonic_u1_ratio: 当前谐波U1幅值占比 x100。
 *   ps_harmonic_u2_ratio: 当前谐波U2幅值占比 x100。
 *   ps_harmonic_phase: 当前谐波 U1-U2 相位差 x100。
 *   ps_harmonic_flags: 当前谐波存在和相位有效标志。
 * 双向: 无。
 */
module pqm_measurement_core #(
    parameter integer MEASUREMENT_INTERVAL_CYCLES = 1_000_000,
    parameter integer MEASURE_FRAME_SAMPLES        = 6144
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         full_scale_low_range_active,
    input  wire         u1_sample_valid,
    input  wire [15:0]  u1_sample_code,
    input  wire [15:0]  u1_zero_code,
    input  wire         u1_zero_valid,
    input  wire         u2_sample_valid,
    input  wire [15:0]  u2_sample_code,
    input  wire [15:0]  u2_zero_code,
    input  wire         u2_zero_valid,
    input  wire         ps_harmonic_ready,
    output wire         alarm_active,
    output wire [511:0] ps_snapshot_words,
    output reg          ps_snapshot_commit_toggle,
    output wire         ps_harmonic_valid,
    output wire         ps_harmonic_last,
    output wire [8:0]   ps_harmonic_index,
    output wire [31:0]  ps_harmonic_u1_ratio,
    output wire [31:0]  ps_harmonic_u2_ratio,
    output wire [31:0]  ps_harmonic_phase,
    output wire [31:0]  ps_harmonic_flags,
    output wire         freq_sample_ready   // RFG 取样口：供前置缓冲使用
);

localparam [2:0] ST_INTERVAL   = 3'd0;
localparam [2:0] ST_WAIT_RAW   = 3'd1;
localparam [2:0] ST_START_X100 = 3'd2;
localparam [2:0] ST_WAIT_X100  = 3'd3;
// 信号源直连 AD7606 输入、无衰减：AD7606 为 ±10 V 满量程，U1/U2 接的是同一颗
// ADC 的两路电压输入，前端完全相同 → 两路真实满量程相同 = 10.00 V（x100 = 1000）。
// PL 固定使用这一组，不再做量程选择（用户确认口径：PS 侧把 U2 电压直接当电流显示，折算系数 = 1）。
localparam integer U1_FULL_SCALE_X100 = 1000;        // U1 = 10.00 V
// U2 原为 300（3.00 V），那是从旧"电流"档（30 A 量程）继承下来的错值；
// 两路前端相同，若沿用 300 会让 U2 读数偏大 1000/300 = 3.333 倍，故改为 1000。
localparam integer U2_FULL_SCALE_X100 = 1000;        // U2 = 10.00 V（修正前为 3.00 V）
// 以下大量程常量仅供 PS 侧显示换算参考，PL 不再使用。
localparam integer U1_FULL_SCALE_HIGH_X100 = 35000;  // 350.00 V（PS 参考）
localparam integer U2_FULL_SCALE_HIGH_X100 = 3000;   // 30.00（PS 参考）
localparam integer SHARP_MONITOR_WINDOW_CYCLES = 50_000_000;
localparam [2:0] SHARP_ALARM_NONE   = 3'd0;
localparam [2:0] SHARP_ALARM_U1_RISE = 3'd1;
localparam [2:0] SHARP_ALARM_U1_DROP = 3'd2;
localparam [2:0] SHARP_ALARM_U2_RISE = 3'd3;
localparam [2:0] SHARP_ALARM_U2_DROP = 3'd4;

reg [2:0] state;
reg [31:0] interval_counter;
reg [25:0] sharp_window_counter;
reg parameters_start;
reg x100_start;
reg rms_valid_latched;
reg u1_pp_valid_latched;
reg u2_pp_valid_latched;
reg phase_valid_latched;
reg freq_valid_latched;
reg power_metrics_valid_latched;
reg signed [31:0] u1_rms_raw_pending;
reg signed [31:0] u2_rms_raw_pending;
reg signed [31:0] u1_pp_raw_pending;
reg signed [31:0] u2_pp_raw_pending;
reg signed [31:0] phase_offset_raw_pending;
reg signed [31:0] phase_period_raw_pending;
reg signed [31:0] freq_period_raw_pending;
reg signed [31:0] active_p_raw_pending;
reg signed [31:0] reactive_q_raw_pending;
reg signed [31:0] apparent_s_raw_pending;
reg signed [31:0] power_factor_raw_pending;
reg [31:0] u1_full_scale_x100_pending;
reg [31:0] u2_full_scale_x100_pending;
reg signed [31:0] u1_rms_x100_reg;
reg signed [31:0] u2_rms_x100_reg;
reg signed [31:0] u1_pp_x100_reg;
reg signed [31:0] u2_pp_x100_reg;
reg signed [31:0] phase_x100_reg;
reg signed [31:0] freq_x100_reg;
reg signed [31:0] active_p_x100_reg;
reg signed [31:0] reactive_q_x100_reg;
reg signed [31:0] apparent_s_x100_reg;
reg signed [31:0] power_factor_x100_reg;
reg rms_valid_reg;
reg u1_pp_valid_reg;
reg u2_pp_valid_reg;
reg phase_valid_reg;
reg freq_valid_reg;
reg power_metrics_valid_reg;
reg [2:0] sharp_alarm_code;
reg sharp_alarm_active;
reg sharp_latest_valid;
reg sharp_window_valid;
reg signed [31:0] u1_rms_x100_latest;
reg signed [31:0] u2_rms_x100_latest;
reg signed [31:0] u1_rms_x100_baseline;
reg signed [31:0] u2_rms_x100_baseline;
reg [31:0] u1_full_scale_x100_previous;
reg [31:0] u2_full_scale_x100_previous;
reg freq_metrics_commit_d1;

wire [31:0] u1_full_scale_x100;
wire [31:0] u2_full_scale_x100;
wire parameters_done;
wire signed [31:0] u1_rms_raw_wire;
wire signed [31:0] u2_rms_raw_wire;
wire rms_valid_wire;
wire signed [31:0] u1_pp_raw_wire;
wire u1_pp_valid_wire;
wire signed [31:0] u2_pp_raw_wire;
wire u2_pp_valid_wire;
wire signed [31:0] phase_offset_raw_wire;
wire signed [31:0] phase_period_raw_wire;
wire phase_valid_wire;
wire signed [31:0] freq_period_raw_wire;
wire freq_valid_wire;
wire signed [31:0] active_p_raw_wire;
wire signed [31:0] reactive_q_raw_wire;
wire signed [31:0] apparent_s_raw_wire;
wire signed [31:0] power_factor_raw_wire;
wire power_metrics_valid_wire;
wire x100_done;
wire signed [31:0] u1_rms_x100_wire;
wire signed [31:0] u2_rms_x100_wire;
wire signed [31:0] u1_pp_x100_wire;
wire signed [31:0] u2_pp_x100_wire;
wire signed [31:0] phase_x100_wire;
wire signed [31:0] freq_x100_wire;
wire signed [31:0] active_p_x100_wire;
wire signed [31:0] reactive_q_x100_wire;
wire signed [31:0] apparent_s_x100_wire;
wire signed [31:0] power_factor_x100_wire;
wire [31:0] reactive_q_raw_abs_wire;
wire signed [31:0] reactive_q_raw_phase_signed;
wire freq_harmonic_valid;
wire freq_harmonic_last;
wire [8:0] freq_harmonic_order;
wire freq_harmonic_present;
wire [16:0] freq_harmonic_u1_mag;
wire [16:0] freq_harmonic_u2_mag;
wire [15:0] freq_harmonic_u1_pct_x100;
wire [15:0] freq_harmonic_u2_pct_x100;
wire freq_phase_diff_valid;
wire signed [15:0] freq_phase_diff_deg_x100;
wire freq_harmonic_fire;
wire freq_metrics_commit_toggle;
wire freq_metrics_commit_edge;
wire [31:0] freq_thd_u1_x100;
wire [31:0] freq_thd_u2_x100;
wire freq_thd_u1_valid;
wire freq_thd_u2_valid;
wire signed [31:0] freq_phase1_x100;
wire freq_phase1_valid;
wire [31:0] freq_dc_u1_x100;
wire [31:0] freq_dc_u2_x100;
wire freq_dc_u1_valid;
wire freq_dc_u2_valid;
wire freq_metrics_valid;
wire [31:0] u1_rms_abs;
wire [31:0] u2_rms_abs;
wire [31:0] u1_rms_baseline_abs;
wire [31:0] u2_rms_baseline_abs;
wire [31:0] u1_rms_delta_abs;
wire [31:0] u2_rms_delta_abs;
wire [35:0] u1_rms_delta_x10;
wire [35:0] u2_rms_delta_x10;
wire u1_alarm_hit;
wire u2_alarm_hit;
wire [2:0] sharp_alarm_code_next;
wire full_scale_changed;

// PL 固定使用真实（小量程）满量程：不再由 full_scale_low_range_active 选择量程。
assign u1_full_scale_x100 = U1_FULL_SCALE_X100;
assign u2_full_scale_x100 = U2_FULL_SCALE_X100;

// 频域链的样本契约：pqm_freq_analysis_rfg 只接受**已去直流的中心化样本**
// （核心把它的零码硬编码为 0，说明样本必须已经是 centered 形式）。
// 踩过的坑：直接送原始码会让整条频域链骑在一个 ~32768 的直流台阶上，
// 表现为 bin0 巨大（实测 20362）以及奇次频点严格按 1/n 泄漏（直流台阶的频谱）。
//
// 17 位差值 → 16 位必须**饱和**（钳到 ±32767），不能取低 16 位。
// 取低 16 位的后果：一旦 |sample - zero_code| > 32767 就回绕成反号，
// 样本序列出现 ~65536 的跳变，频谱变成"每个谐波都有份、平缓衰减"的冲击谱
//（同一纯正弦，板上实测 18.06 Vpp：H1 10.99%、H2 11.10%、H3 9.77%、THD-U 180.67%；
//  未越界的 14.05 Vpp：H1 70.97%、THD-U 0.06%）。
// 越界条件 = 去零点后的峰值 = 幅值 + 零点估计残差 > 32767：
//   - 零点跟踪器取整偏差修好之前，残差 ≈ 0.2×幅值，越界起点 ≈15.5 Vpp；
//   - 修好之后残差只剩 ~1 个码，正常 10 V 满量程内不越界，但 ADC 削顶、
//     输入直流/幅度突变（跟踪器 τ≈0.64 s 追不上）依旧会越界，
//     所以这层饱和必须保留，并用 freq_center_sat 把它变成可见标志。
wire signed [16:0] freq_u1_centered_ext = $signed({1'b0, u1_sample_code}) - $signed({1'b0, u1_zero_code});
wire signed [16:0] freq_u2_centered_ext = $signed({1'b0, u2_sample_code}) - $signed({1'b0, u2_zero_code});
localparam signed [16:0] FREQ_CENTER_MAX =  17'sd32767;
localparam signed [16:0] FREQ_CENTER_MIN = -17'sd32767;
wire freq_u1_center_sat = (freq_u1_centered_ext > FREQ_CENTER_MAX) || (freq_u1_centered_ext < FREQ_CENTER_MIN);
wire freq_u2_center_sat = (freq_u2_centered_ext > FREQ_CENTER_MAX) || (freq_u2_centered_ext < FREQ_CENTER_MIN);
wire signed [15:0] freq_u1_centered = freq_u1_center_sat
                                   ? (freq_u1_centered_ext[16] ? -16'sd32767 : 16'sd32767)
                                   : freq_u1_centered_ext[15:0];
wire signed [15:0] freq_u2_centered = freq_u2_center_sat
                                   ? (freq_u2_centered_ext[16] ? -16'sd32767 : 16'sd32767)
                                   : freq_u2_centered_ext[15:0];

// 仅在 U1/U2 同拍有效时把样本送入频域分析，保持通道帧严格对齐。
wire freq_sample_valid_raw = u1_sample_valid && u2_sample_valid;
reg  freq_sample_valid;
reg  signed [15:0] freq_sample_u1;
reg  signed [15:0] freq_sample_u2;

// 缺陷 3：饱和/溢出必须可见。三个都做成粘滞位（置 1 后保持到复位），
// 语义 = "自复位以来发生过"，与 RFG 内部 o_overflow 的粘滞约定一致。
reg  freq_center_sat_sticky;
reg  freq_rfg_overflow_sticky;
reg  freq_fifo_overflow_sticky;
wire freq_center_sat;       // 核心自己这层去零点饱和（u1|u2），见下方 assign
wire freq_fe_center_sat;    // 来自 pqm_freq_analysis_rfg.o_center_sat
wire freq_rfg_overflow;     // 来自 pqm_freq_analysis_rfg.o_rfg_overflow（RFG 内部溢出粘滞）
wire freq_fifo_overflow;    // 来自 pqm_freq_analysis_rfg.o_fifo_overflow

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        freq_sample_valid        <= 1'b0;
        freq_sample_u1           <= 16'sd0;
        freq_sample_u2           <= 16'sd0;
        freq_center_sat_sticky   <= 1'b0;
        freq_rfg_overflow_sticky <= 1'b0;
        freq_fifo_overflow_sticky<= 1'b0;
    end else begin
        freq_sample_valid <= freq_sample_valid_raw;
        freq_sample_u1    <= freq_u1_centered;
        freq_sample_u2    <= freq_u2_centered;

        // 与样本同拍记录：本拍的去零点饱和来自核心自己的钳位，
        // fe_center_sat 来自 RFG 顶层内部的同一处钳位（当前零码给 0，恒为 0）。
        if (freq_sample_valid_raw && (freq_center_sat | freq_fe_center_sat))
            freq_center_sat_sticky <= 1'b1;
        if (freq_rfg_overflow)
            freq_rfg_overflow_sticky <= 1'b1;
        if (freq_fifo_overflow)
            freq_fifo_overflow_sticky <= 1'b1;
    end
end
assign freq_center_sat = freq_u1_center_sat | freq_u2_center_sat;

// 用频域基波相位的符号修正无功功率方向，同时保持其绝对值不变。
assign reactive_q_raw_abs_wire = reactive_q_raw_wire[31]
                               ? (~reactive_q_raw_wire + 32'd1)
                               : reactive_q_raw_wire[31:0];
assign reactive_q_raw_phase_signed =
    (freq_phase1_valid && (reactive_q_raw_abs_wire != 32'd0))
        ? (freq_phase1_x100[31]
            ? (~reactive_q_raw_abs_wire + 32'd1)
            : {1'b0, reactive_q_raw_abs_wire[30:0]})
        : reactive_q_raw_wire;

// 当前谐波被共享内存桥接收时，同拍推进频域指标聚合器。
assign freq_harmonic_fire = freq_harmonic_valid && ps_harmonic_ready;

// 频域指标提交 toggle 的变化沿触发一次标量快照发布。
assign freq_metrics_commit_edge = freq_metrics_commit_toggle
                                ^ freq_metrics_commit_d1;

// 对 RMS 当前值、基线和差值取绝对值，供 10% 骤变门限比较复用。
assign u1_rms_abs = u1_rms_x100_wire[31]
                 ? (~u1_rms_x100_wire + 32'd1) : u1_rms_x100_wire[31:0];
assign u2_rms_abs = u2_rms_x100_wire[31]
                 ? (~u2_rms_x100_wire + 32'd1) : u2_rms_x100_wire[31:0];
assign u1_rms_baseline_abs = u1_rms_x100_baseline[31]
                          ? (~u1_rms_x100_baseline + 32'd1)
                          : u1_rms_x100_baseline[31:0];
assign u2_rms_baseline_abs = u2_rms_x100_baseline[31]
                          ? (~u2_rms_x100_baseline + 32'd1)
                          : u2_rms_x100_baseline[31:0];
assign u1_rms_delta_abs = (u1_rms_abs >= u1_rms_baseline_abs)
                       ? (u1_rms_abs - u1_rms_baseline_abs)
                       : (u1_rms_baseline_abs - u1_rms_abs);
assign u2_rms_delta_abs = (u2_rms_abs >= u2_rms_baseline_abs)
                       ? (u2_rms_abs - u2_rms_baseline_abs)
                       : (u2_rms_baseline_abs - u2_rms_abs);
assign u1_rms_delta_x10 = ({4'd0, u1_rms_delta_abs} << 3)
                       + ({4'd0, u1_rms_delta_abs} << 1);
assign u2_rms_delta_x10 = ({4'd0, u2_rms_delta_abs} << 3)
                       + ({4'd0, u2_rms_delta_abs} << 1);

// 基线建立后，当前 RMS 相对变化超过 10% 时生成对应通道告警编码。
assign u1_alarm_hit = sharp_window_valid && rms_valid_latched
                   && (u1_rms_baseline_abs != 32'd0)
                   && (u1_rms_delta_x10 > {4'd0, u1_rms_baseline_abs});
assign u2_alarm_hit = sharp_window_valid && rms_valid_latched
                   && (u2_rms_baseline_abs != 32'd0)
                   && (u2_rms_delta_x10 > {4'd0, u2_rms_baseline_abs});
assign sharp_alarm_code_next =
    (u1_alarm_hit && (u1_rms_abs > u1_rms_baseline_abs)) ? SHARP_ALARM_U1_RISE :
    (u1_alarm_hit && (u1_rms_abs < u1_rms_baseline_abs)) ? SHARP_ALARM_U1_DROP :
    (u2_alarm_hit && (u2_rms_abs > u2_rms_baseline_abs)) ? SHARP_ALARM_U2_RISE :
    (u2_alarm_hit && (u2_rms_abs < u2_rms_baseline_abs)) ? SHARP_ALARM_U2_DROP :
                                                       SHARP_ALARM_NONE;
assign full_scale_changed = (u1_full_scale_x100_previous != u1_full_scale_x100)
                         || (u2_full_scale_x100_previous != u2_full_scale_x100);
assign alarm_active = sharp_alarm_active;

// 按共享内存 ABI 固定顺序组合标量值、告警和逐字段有效位。
assign ps_snapshot_words = {
    // validity 字（shm 0x1F）：bit11..0 是原有逐字段有效位，ABI 一个都没动；
    // bit15..12 原本恒 0，现把三个"数据还能不能信"的标志放进去（缺陷 3）：
    //   bit12 = 去零点 17→16 位饱和（freq_center_sat_sticky）
    //   bit13 = RFG 引擎内部溢出粘滞（freq_rfg_overflow_sticky）
    //   bit14 = 取样 FIFO 溢出粘滞（freq_fifo_overflow_sticky）
    //   bit15 = 保留 0
    // 选位理由：validity 字本身就是"这些数是否可信"的语义位，且 bit15..12 空闲，
    // 比去占 0x20/0x21 两个空闲字更自然（那两个字留给后续真正的标量字段）。
    {16'd0, 1'b0, freq_fifo_overflow_sticky, freq_rfg_overflow_sticky,
     freq_center_sat_sticky, freq_metrics_valid, freq_dc_u2_valid, freq_dc_u1_valid,
     freq_thd_u2_valid, freq_thd_u1_valid, power_metrics_valid_reg,
     freq_valid_reg, phase_valid_reg, u2_pp_valid_reg, u1_pp_valid_reg,
     rms_valid_reg, rms_valid_reg},
    {28'd0, sharp_alarm_code, sharp_alarm_active},
    freq_dc_u2_x100,
    freq_dc_u1_x100,
    freq_thd_u2_x100,
    freq_thd_u1_x100,
    power_factor_x100_reg,
    apparent_s_x100_reg,
    reactive_q_x100_reg,
    active_p_x100_reg,
    phase_x100_reg,
    freq_x100_reg,
    u2_pp_x100_reg,
    u1_pp_x100_reg,
    u2_rms_x100_reg,
    u1_rms_x100_reg
};

// 频域分析输出直接映射为共享内存桥消费的谐波条目。
assign ps_harmonic_valid = freq_harmonic_valid;
assign ps_harmonic_last = freq_harmonic_last;
assign ps_harmonic_index = freq_harmonic_order;
assign ps_harmonic_u1_ratio = {16'd0, freq_harmonic_u1_pct_x100};
assign ps_harmonic_u2_ratio = {16'd0, freq_harmonic_u2_pct_x100};
assign ps_harmonic_phase = {{16{freq_phase_diff_deg_x100[15]}},
                            freq_phase_diff_deg_x100};
assign ps_harmonic_flags = {30'd0, freq_phase_diff_valid,
                            freq_harmonic_present};

// 复用现有时域 raw 调度器，在同一采样窗口生成 RMS、峰峰值、相位和功率。
time_parameters_initiator #(
    .SAMPLE_WIDTH(16),
    .MAX_FRAME_SAMPLES(8192),
    .N_WIDTH(13),
    .MEASURE_FRAME_SAMPLES(MEASURE_FRAME_SAMPLES)
) u_time_parameters_initiator (
    .clk(clk), .rst_n(rst_n), .start(parameters_start),
    .u1_sample_valid(u1_sample_valid), .u1_sample_code(u1_sample_code),
    .u1_zero_code(u1_zero_code), .u1_zero_valid(u1_zero_valid),
    .u2_sample_valid(u2_sample_valid), .u2_sample_code(u2_sample_code),
    .u2_zero_code(u2_zero_code), .u2_zero_valid(u2_zero_valid),
    .busy(), .done(parameters_done),
    .u1_rms_raw(u1_rms_raw_wire), .u2_rms_raw(u2_rms_raw_wire),
    .rms_valid(rms_valid_wire), .u1_pp_raw(u1_pp_raw_wire),
    .u1_pp_valid(u1_pp_valid_wire), .u2_pp_raw(u2_pp_raw_wire),
    .u2_pp_valid(u2_pp_valid_wire), .phase_offset_raw(phase_offset_raw_wire),
    .phase_period_raw(phase_period_raw_wire), .phase_valid(phase_valid_wire),
    .freq_period_raw(freq_period_raw_wire), .freq_valid(freq_valid_wire),
    .active_p_raw(active_p_raw_wire), .reactive_q_raw(reactive_q_raw_wire),
    .apparent_s_raw(apparent_s_raw_wire),
    .power_factor_raw(power_factor_raw_wire),
    .power_metrics_valid(power_metrics_valid_wire)
);

// 复用现有串行归一化器，把 raw 结果统一换算为 x100 工程量。
time_x100_normalizer #(
    .CODE_WIDTH(16)
) u_time_x100_normalizer (
    .clk(clk), .rst_n(rst_n), .start(x100_start),
    .u1_rms_raw(u1_rms_raw_pending), .u2_rms_raw(u2_rms_raw_pending),
    .rms_valid(rms_valid_latched), .u1_pp_raw(u1_pp_raw_pending),
    .u2_pp_raw(u2_pp_raw_pending), .u1_pp_valid(u1_pp_valid_latched),
    .u2_pp_valid(u2_pp_valid_latched),
    .phase_offset_raw(phase_offset_raw_pending),
    .phase_period_raw(phase_period_raw_pending),
    .phase_valid(phase_valid_latched),
    .freq_period_raw(freq_period_raw_pending), .freq_valid(freq_valid_latched),
    .active_p_raw(active_p_raw_pending),
    .reactive_q_raw(reactive_q_raw_pending),
    .apparent_s_raw(apparent_s_raw_pending),
    .power_factor_raw(power_factor_raw_pending),
    .u1_full_scale_x100(u1_full_scale_x100_pending),
    .u2_full_scale_x100(u2_full_scale_x100_pending),
    .power_metrics_valid(power_metrics_valid_latched), .done(x100_done),
    .u1_rms_x100(u1_rms_x100_wire), .u2_rms_x100(u2_rms_x100_wire),
    .u1_pp_x100(u1_pp_x100_wire), .u2_pp_x100(u2_pp_x100_wire),
    .phase_x100(phase_x100_wire), .freq_x100(freq_x100_wire),
    .active_p_x100(active_p_x100_wire),
    .reactive_q_x100(reactive_q_x100_wire),
    .apparent_s_x100(apparent_s_x100_wire),
    .power_factor_x100(power_factor_x100_wire)
);

// 频域链：RFG 版顶层持续输出 0 到 C_K 次谐波幅值与相位流。
// RFG 版频域链：替掉 freq_analysis_top（无 xfft IP、无流适配器、无 FFT 基波跟踪器）
pqm_freq_analysis_rfg u_freq_analysis (
    .clk(clk), .rst_n(rst_n), .enable(1'b1),
    .i_sample_valid(freq_sample_valid),
    .i_sample_u1(freq_sample_u1), .i_sample_u2(freq_sample_u2),
    // 样本已在此处中心化，所以零码给 0、有效位给 1：frontend 内部做
    // sample - zero_ref = sample - 0 = sample，等价于不再去直流。
    // 这与原厂 RFG 整链用例（tb_pqm_rfg_chain，已 PASS）的激励形式完全一致。
    .i_u1_zero_code(16'd0), .i_u1_zero_valid(1'b1),
    .i_u2_zero_code(16'd0), .i_u2_zero_valid(1'b1),
    .o_sample_ready(freq_sample_ready),
    .i_harmonic_ready(ps_harmonic_ready),
    .m_harmonic_valid(freq_harmonic_valid),
    .m_harmonic_last(freq_harmonic_last),
    .m_harmonic_order(freq_harmonic_order),
    .m_harmonic_present(freq_harmonic_present),
    .m_u1_real(), .m_u1_imag(), .m_u2_real(), .m_u2_imag(),
    .m_u1_mag(freq_harmonic_u1_mag), .m_u2_mag(freq_harmonic_u2_mag),
    .m_u1_pct_x100(freq_harmonic_u1_pct_x100), .m_u2_pct_x100(freq_harmonic_u2_pct_x100),
    .m_phase_vector_valid(), .m_phase_dot(), .m_phase_cross(),
    .m_phase_diff_valid(freq_phase_diff_valid),
    .m_phase_diff_deg_x100(freq_phase_diff_deg_x100),
    .filtered_frame_count(),
    .o_center_sat(freq_fe_center_sat),
    .o_rfg_overflow(freq_rfg_overflow),
    .o_fifo_overflow(freq_fifo_overflow)
);

// 聚合已完成握手的谐波条目，生成 THD、基波相位和直流分量等标量。
freq_metrics_raw_calc u_freq_metrics_raw_calc (
    .clk(clk), .rst_n(rst_n), .enable(1'b1),
    .s_harmonic_fire(freq_harmonic_fire),
    .s_harmonic_last(freq_harmonic_last),
    .s_harmonic_order(freq_harmonic_order),
    .s_harmonic_present(freq_harmonic_present),
    .s_u1_mag(freq_harmonic_u1_mag), .s_u2_mag(freq_harmonic_u2_mag),
    .s_u1_pct_x100(freq_harmonic_u1_pct_x100),
    .s_u2_pct_x100(freq_harmonic_u2_pct_x100),
    .s_phase_diff_valid(freq_phase_diff_valid),
    .s_phase_diff_deg_x100(freq_phase_diff_deg_x100),
    .raw_result_commit_toggle(freq_metrics_commit_toggle),
    .thd_u1_raw_x100(freq_thd_u1_x100), .thd_u2_raw_x100(freq_thd_u2_x100),
    .thd_u1_valid(freq_thd_u1_valid), .thd_u2_valid(freq_thd_u2_valid),
    .u1_mag_raw_x100(), .u2_mag_raw_x100(), .u1_mag_valid(), .u2_mag_valid(),
    .phase1_raw_x100(freq_phase1_x100), .phase1_valid(freq_phase1_valid),
    .dc_u1_raw_x100(freq_dc_u1_x100), .dc_u2_raw_x100(freq_dc_u2_x100),
    .dc_u1_valid(freq_dc_u1_valid), .dc_u2_valid(freq_dc_u2_valid),
    .dh_order_u1_list_raw(), .dh_order_u2_list_raw(), .dh_order_u1_count_raw(),
    .dh_order_u2_count_raw(), .dh_order_u1_valid(), .dh_order_u2_valid(),
    .metrics_valid(freq_metrics_valid)
);

// 周期调度 raw 测量和 x100 换算，并在结果稳定后原子更新标量快照寄存器。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= ST_INTERVAL;
        interval_counter <= 32'd0;
        sharp_window_counter <= 26'd0;
        parameters_start <= 1'b0;
        x100_start <= 1'b0;
        rms_valid_latched <= 1'b0;
        u1_pp_valid_latched <= 1'b0;
        u2_pp_valid_latched <= 1'b0;
        phase_valid_latched <= 1'b0;
        freq_valid_latched <= 1'b0;
        power_metrics_valid_latched <= 1'b0;
        u1_rms_raw_pending <= 32'sd0;
        u2_rms_raw_pending <= 32'sd0;
        u1_pp_raw_pending <= 32'sd0;
        u2_pp_raw_pending <= 32'sd0;
        phase_offset_raw_pending <= 32'sd0;
        phase_period_raw_pending <= 32'sd0;
        freq_period_raw_pending <= 32'sd0;
        active_p_raw_pending <= 32'sd0;
        reactive_q_raw_pending <= 32'sd0;
        apparent_s_raw_pending <= 32'sd0;
        power_factor_raw_pending <= 32'sd0;
        u1_full_scale_x100_pending <= 32'd0;
        u2_full_scale_x100_pending <= 32'd0;
        u1_rms_x100_reg <= 32'sd0;
        u2_rms_x100_reg <= 32'sd0;
        u1_pp_x100_reg <= 32'sd0;
        u2_pp_x100_reg <= 32'sd0;
        phase_x100_reg <= 32'sd0;
        freq_x100_reg <= 32'sd0;
        active_p_x100_reg <= 32'sd0;
        reactive_q_x100_reg <= 32'sd0;
        apparent_s_x100_reg <= 32'sd0;
        power_factor_x100_reg <= 32'sd0;
        rms_valid_reg <= 1'b0;
        u1_pp_valid_reg <= 1'b0;
        u2_pp_valid_reg <= 1'b0;
        phase_valid_reg <= 1'b0;
        freq_valid_reg <= 1'b0;
        power_metrics_valid_reg <= 1'b0;
        sharp_alarm_code <= SHARP_ALARM_NONE;
        sharp_alarm_active <= 1'b0;
        sharp_latest_valid <= 1'b0;
        sharp_window_valid <= 1'b0;
        u1_rms_x100_latest <= 32'sd0;
        u2_rms_x100_latest <= 32'sd0;
        u1_rms_x100_baseline <= 32'sd0;
        u2_rms_x100_baseline <= 32'sd0;
        u1_full_scale_x100_previous <= 32'd0;
        u2_full_scale_x100_previous <= 32'd0;
        freq_metrics_commit_d1 <= 1'b0;
        ps_snapshot_commit_toggle <= 1'b0;
    end else begin
        parameters_start <= 1'b0;
        x100_start <= 1'b0;
        u1_full_scale_x100_previous <= u1_full_scale_x100;
        u2_full_scale_x100_previous <= u2_full_scale_x100;
        freq_metrics_commit_d1 <= freq_metrics_commit_toggle;

        if (sharp_window_counter == (SHARP_MONITOR_WINDOW_CYCLES - 1)) begin
            sharp_window_counter <= 26'd0;
            if (sharp_latest_valid && !sharp_alarm_active) begin
                u1_rms_x100_baseline <= u1_rms_x100_latest;
                u2_rms_x100_baseline <= u2_rms_x100_latest;
                sharp_window_valid <= 1'b1;
            end
        end else begin
            sharp_window_counter <= sharp_window_counter + 26'd1;
        end

        case (state)
            ST_INTERVAL: begin
                if (interval_counter == (MEASUREMENT_INTERVAL_CYCLES - 1)) begin
                    interval_counter <= 32'd0;
                    parameters_start <= 1'b1;
                    state <= ST_WAIT_RAW;
                end else begin
                    interval_counter <= interval_counter + 32'd1;
                end
            end
            ST_WAIT_RAW: begin
                if (parameters_done) begin
                    u1_rms_raw_pending <= u1_rms_raw_wire;
                    u2_rms_raw_pending <= u2_rms_raw_wire;
                    u1_pp_raw_pending <= u1_pp_raw_wire;
                    u2_pp_raw_pending <= u2_pp_raw_wire;
                    phase_offset_raw_pending <= phase_offset_raw_wire;
                    phase_period_raw_pending <= phase_period_raw_wire;
                    freq_period_raw_pending <= freq_period_raw_wire;
                    active_p_raw_pending <= active_p_raw_wire;
                    reactive_q_raw_pending <= reactive_q_raw_phase_signed;
                    apparent_s_raw_pending <= apparent_s_raw_wire;
                    power_factor_raw_pending <= power_factor_raw_wire;
                    u1_full_scale_x100_pending <= u1_full_scale_x100;
                    u2_full_scale_x100_pending <= u2_full_scale_x100;
                    rms_valid_latched <= rms_valid_wire;
                    u1_pp_valid_latched <= u1_pp_valid_wire;
                    u2_pp_valid_latched <= u2_pp_valid_wire;
                    phase_valid_latched <= power_metrics_valid_wire;
                    freq_valid_latched <= freq_valid_wire;
                    power_metrics_valid_latched <= power_metrics_valid_wire;
                    state <= ST_START_X100;
                end
            end
            ST_START_X100: begin
                x100_start <= 1'b1;
                state <= ST_WAIT_X100;
            end
            ST_WAIT_X100: begin
                if (x100_done) begin
                    u1_rms_x100_reg <= u1_rms_x100_wire;
                    u2_rms_x100_reg <= u2_rms_x100_wire;
                    u1_pp_x100_reg <= u1_pp_x100_wire;
                    u2_pp_x100_reg <= u2_pp_x100_wire;
                    phase_x100_reg <= phase_x100_wire;
                    freq_x100_reg <= freq_x100_wire;
                    active_p_x100_reg <= active_p_x100_wire;
                    reactive_q_x100_reg <= reactive_q_x100_wire;
                    apparent_s_x100_reg <= apparent_s_x100_wire;
                    power_factor_x100_reg <= power_factor_x100_wire;
                    rms_valid_reg <= rms_valid_latched;
                    u1_pp_valid_reg <= u1_pp_valid_latched;
                    u2_pp_valid_reg <= u2_pp_valid_latched;
                    phase_valid_reg <= phase_valid_latched;
                    freq_valid_reg <= freq_valid_latched;
                    power_metrics_valid_reg <= power_metrics_valid_latched;
                    sharp_latest_valid <= rms_valid_latched;
                    u1_rms_x100_latest <= u1_rms_x100_wire;
                    u2_rms_x100_latest <= u2_rms_x100_wire;
                    sharp_alarm_code <= sharp_alarm_code_next;
                    sharp_alarm_active <=
                        (sharp_alarm_code_next != SHARP_ALARM_NONE);
                    ps_snapshot_commit_toggle <=
                        ~ps_snapshot_commit_toggle;
                    state <= ST_INTERVAL;
                end
            end
            default: state <= ST_INTERVAL;
        endcase

        if (freq_metrics_commit_edge && !x100_done) begin
            ps_snapshot_commit_toggle <= ~ps_snapshot_commit_toggle;
        end

        if (full_scale_changed) begin
            sharp_latest_valid <= 1'b0;
            sharp_window_counter <= 26'd0;
            sharp_window_valid <= 1'b0;
            u1_rms_x100_baseline <= 32'sd0;
            u2_rms_x100_baseline <= 32'sd0;
            sharp_alarm_code <= SHARP_ALARM_NONE;
            sharp_alarm_active <= 1'b0;
        end
    end
end

endmodule
