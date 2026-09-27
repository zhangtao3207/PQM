`timescale 1ns / 1ps

/*
 * 模块: pqm_measurement_core
 * 功能:
 *   在 PS 显示模式下保留确定性的时域测量、频域谐波统计和骤变告警，
 *   直接生成共享内存标量快照与谐波流，不实例化任何 PL 显示或文本格式化逻辑。
 * 输入:
 *   clk: 采样、时域测量与频域分析共用的 50 MHz 工作时钟。
 *   rst_n: 低有效异步复位。
 *   full_scale_low_range_active: 当前是否使用低量程换算参数。
 *   u_sample_valid: 电压样本有效脉冲。
 *   u_sample_code: 电压 ADC 原始采样码。
 *   u_zero_code: 电压零点跟踪码。
 *   u_zero_valid: 电压零点跟踪结果有效标志。
 *   i_sample_valid: 电流样本有效脉冲。
 *   i_sample_code: 电流 ADC 原始采样码。
 *   i_zero_code: 电流零点跟踪码。
 *   i_zero_valid: 电流零点跟踪结果有效标志。
 *   ps_harmonic_ready: 共享内存桥允许接收当前谐波条目。
 * 输出:
 *   alarm_active: 电压或电流 RMS 骤升、骤降告警有效标志。
 *   ps_snapshot_words: 按共享内存 ABI word15 到 word0 排列的标量快照。
 *   ps_snapshot_commit_toggle: 标量或频域指标更新后的提交 toggle。
 *   ps_harmonic_valid: 当前谐波条目有效标志。
 *   ps_harmonic_last: 当前条目为谐波帧最后一项。
 *   ps_harmonic_index: 当前谐波阶次。
 *   ps_harmonic_u_ratio: 当前谐波电压幅值占比 x100。
 *   ps_harmonic_i_ratio: 当前谐波电流幅值占比 x100。
 *   ps_harmonic_phase: 当前谐波 U-I 相位差 x100。
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
    input  wire         u_sample_valid,
    input  wire [15:0]  u_sample_code,
    input  wire [15:0]  u_zero_code,
    input  wire         u_zero_valid,
    input  wire         i_sample_valid,
    input  wire [15:0]  i_sample_code,
    input  wire [15:0]  i_zero_code,
    input  wire         i_zero_valid,
    input  wire         ps_harmonic_ready,
    output wire         alarm_active,
    output wire [511:0] ps_snapshot_words,
    output reg          ps_snapshot_commit_toggle,
    output wire         ps_harmonic_valid,
    output wire         ps_harmonic_last,
    output wire [8:0]   ps_harmonic_index,
    output wire [31:0]  ps_harmonic_u_ratio,
    output wire [31:0]  ps_harmonic_i_ratio,
    output wire [31:0]  ps_harmonic_phase,
    output wire [31:0]  ps_harmonic_flags,
    output wire         freq_sample_ready   // RFG 取样口：供前置缓冲使用
);

localparam [2:0] ST_INTERVAL   = 3'd0;
localparam [2:0] ST_WAIT_RAW   = 3'd1;
localparam [2:0] ST_START_X100 = 3'd2;
localparam [2:0] ST_WAIT_X100  = 3'd3;
localparam integer U_FULL_SCALE_HIGH_X100 = 35000;
localparam integer I_FULL_SCALE_HIGH_X100 = 3000;
localparam integer U_FULL_SCALE_LOW_X100  = 1000;
localparam integer I_FULL_SCALE_LOW_X100  = 300;
localparam integer SHARP_MONITOR_WINDOW_CYCLES = 50_000_000;
localparam [2:0] SHARP_ALARM_NONE   = 3'd0;
localparam [2:0] SHARP_ALARM_U_RISE = 3'd1;
localparam [2:0] SHARP_ALARM_U_DROP = 3'd2;
localparam [2:0] SHARP_ALARM_I_RISE = 3'd3;
localparam [2:0] SHARP_ALARM_I_DROP = 3'd4;

reg [2:0] state;
reg [31:0] interval_counter;
reg [25:0] sharp_window_counter;
reg parameters_start;
reg x100_start;
reg rms_valid_latched;
reg u_pp_valid_latched;
reg i_pp_valid_latched;
reg phase_valid_latched;
reg freq_valid_latched;
reg power_metrics_valid_latched;
reg signed [31:0] u_rms_raw_pending;
reg signed [31:0] i_rms_raw_pending;
reg signed [31:0] u_pp_raw_pending;
reg signed [31:0] i_pp_raw_pending;
reg signed [31:0] phase_offset_raw_pending;
reg signed [31:0] phase_period_raw_pending;
reg signed [31:0] freq_period_raw_pending;
reg signed [31:0] active_p_raw_pending;
reg signed [31:0] reactive_q_raw_pending;
reg signed [31:0] apparent_s_raw_pending;
reg signed [31:0] power_factor_raw_pending;
reg [31:0] u_full_scale_x100_pending;
reg [31:0] i_full_scale_x100_pending;
reg signed [31:0] u_rms_x100_reg;
reg signed [31:0] i_rms_x100_reg;
reg signed [31:0] u_pp_x100_reg;
reg signed [31:0] i_pp_x100_reg;
reg signed [31:0] phase_x100_reg;
reg signed [31:0] freq_x100_reg;
reg signed [31:0] active_p_x100_reg;
reg signed [31:0] reactive_q_x100_reg;
reg signed [31:0] apparent_s_x100_reg;
reg signed [31:0] power_factor_x100_reg;
reg rms_valid_reg;
reg u_pp_valid_reg;
reg i_pp_valid_reg;
reg phase_valid_reg;
reg freq_valid_reg;
reg power_metrics_valid_reg;
reg [2:0] sharp_alarm_code;
reg sharp_alarm_active;
reg sharp_latest_valid;
reg sharp_window_valid;
reg signed [31:0] u_rms_x100_latest;
reg signed [31:0] i_rms_x100_latest;
reg signed [31:0] u_rms_x100_baseline;
reg signed [31:0] i_rms_x100_baseline;
reg [31:0] u_full_scale_x100_previous;
reg [31:0] i_full_scale_x100_previous;
reg freq_metrics_commit_d1;

wire [31:0] u_full_scale_x100;
wire [31:0] i_full_scale_x100;
wire parameters_done;
wire signed [31:0] u_rms_raw_wire;
wire signed [31:0] i_rms_raw_wire;
wire rms_valid_wire;
wire signed [31:0] u_pp_raw_wire;
wire u_pp_valid_wire;
wire signed [31:0] i_pp_raw_wire;
wire i_pp_valid_wire;
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
wire signed [31:0] u_rms_x100_wire;
wire signed [31:0] i_rms_x100_wire;
wire signed [31:0] u_pp_x100_wire;
wire signed [31:0] i_pp_x100_wire;
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
wire [16:0] freq_harmonic_u_mag;
wire [16:0] freq_harmonic_i_mag;
wire [15:0] freq_harmonic_u_pct_x100;
wire [15:0] freq_harmonic_i_pct_x100;
wire freq_phase_diff_valid;
wire signed [15:0] freq_phase_diff_deg_x100;
wire freq_harmonic_fire;
wire freq_metrics_commit_toggle;
wire freq_metrics_commit_edge;
wire [31:0] freq_thd_u_x100;
wire [31:0] freq_thd_i_x100;
wire freq_thd_u_valid;
wire freq_thd_i_valid;
wire signed [31:0] freq_phase1_x100;
wire freq_phase1_valid;
wire [31:0] freq_dc_u_x100;
wire [31:0] freq_dc_i_x100;
wire freq_dc_u_valid;
wire freq_dc_i_valid;
wire freq_metrics_valid;
wire [31:0] u_rms_abs;
wire [31:0] i_rms_abs;
wire [31:0] u_rms_baseline_abs;
wire [31:0] i_rms_baseline_abs;
wire [31:0] u_rms_delta_abs;
wire [31:0] i_rms_delta_abs;
wire [35:0] u_rms_delta_x10;
wire [35:0] i_rms_delta_x10;
wire u_alarm_hit;
wire i_alarm_hit;
wire [2:0] sharp_alarm_code_next;
wire full_scale_changed;

// 根据量程状态选择时域工程量换算所需的电压、电流满量程值。
assign u_full_scale_x100 = full_scale_low_range_active
                            ? U_FULL_SCALE_LOW_X100 : U_FULL_SCALE_HIGH_X100;
assign i_full_scale_x100 = full_scale_low_range_active
                            ? I_FULL_SCALE_LOW_X100 : I_FULL_SCALE_HIGH_X100;

// 频域链的样本契约：pqm_freq_analysis_rfg 只接受**已去直流的中心化样本**
// （它内部把 frontend 的 i_zero_code 硬编码为 16'd0，说明它的样本必须已经是
//  centered 形式）。所以这里必须先减零点码，不能直接把原始偏移码送进去。
// 踩过的坑：直接送原始码会让整条频域链骑在一个 ~32768 的直流台阶上，
// 表现为 bin0 巨大（实测 20362）以及奇次频点严格按 1/n 泄漏（直流台阶的频谱）。
wire signed [16:0] freq_u_centered_ext = $signed({1'b0, u_sample_code}) - $signed({1'b0, u_zero_code});
wire signed [16:0] freq_i_centered_ext = $signed({1'b0, i_sample_code}) - $signed({1'b0, i_zero_code});
wire signed [15:0] freq_u_centered = freq_u_centered_ext[15:0];
wire signed [15:0] freq_i_centered = freq_i_centered_ext[15:0];

// 仅在 U/I 同拍有效时把样本送入频域分析，保持通道帧严格对齐。
wire freq_sample_valid_raw = u_sample_valid && i_sample_valid;
reg  freq_sample_valid;
reg  signed [15:0] freq_sample_u;
reg  signed [15:0] freq_sample_i;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        freq_sample_valid <= 1'b0;
        freq_sample_u     <= 16'sd0;
        freq_sample_i     <= 16'sd0;
    end else begin
        freq_sample_valid <= freq_sample_valid_raw;
        freq_sample_u     <= freq_u_centered;
        freq_sample_i     <= freq_i_centered;
    end
end

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
assign u_rms_abs = u_rms_x100_wire[31]
                 ? (~u_rms_x100_wire + 32'd1) : u_rms_x100_wire[31:0];
assign i_rms_abs = i_rms_x100_wire[31]
                 ? (~i_rms_x100_wire + 32'd1) : i_rms_x100_wire[31:0];
assign u_rms_baseline_abs = u_rms_x100_baseline[31]
                          ? (~u_rms_x100_baseline + 32'd1)
                          : u_rms_x100_baseline[31:0];
assign i_rms_baseline_abs = i_rms_x100_baseline[31]
                          ? (~i_rms_x100_baseline + 32'd1)
                          : i_rms_x100_baseline[31:0];
assign u_rms_delta_abs = (u_rms_abs >= u_rms_baseline_abs)
                       ? (u_rms_abs - u_rms_baseline_abs)
                       : (u_rms_baseline_abs - u_rms_abs);
assign i_rms_delta_abs = (i_rms_abs >= i_rms_baseline_abs)
                       ? (i_rms_abs - i_rms_baseline_abs)
                       : (i_rms_baseline_abs - i_rms_abs);
assign u_rms_delta_x10 = ({4'd0, u_rms_delta_abs} << 3)
                       + ({4'd0, u_rms_delta_abs} << 1);
assign i_rms_delta_x10 = ({4'd0, i_rms_delta_abs} << 3)
                       + ({4'd0, i_rms_delta_abs} << 1);

// 基线建立后，当前 RMS 相对变化超过 10% 时生成对应通道告警编码。
assign u_alarm_hit = sharp_window_valid && rms_valid_latched
                   && (u_rms_baseline_abs != 32'd0)
                   && (u_rms_delta_x10 > {4'd0, u_rms_baseline_abs});
assign i_alarm_hit = sharp_window_valid && rms_valid_latched
                   && (i_rms_baseline_abs != 32'd0)
                   && (i_rms_delta_x10 > {4'd0, i_rms_baseline_abs});
assign sharp_alarm_code_next =
    (u_alarm_hit && (u_rms_abs > u_rms_baseline_abs)) ? SHARP_ALARM_U_RISE :
    (u_alarm_hit && (u_rms_abs < u_rms_baseline_abs)) ? SHARP_ALARM_U_DROP :
    (i_alarm_hit && (i_rms_abs > i_rms_baseline_abs)) ? SHARP_ALARM_I_RISE :
    (i_alarm_hit && (i_rms_abs < i_rms_baseline_abs)) ? SHARP_ALARM_I_DROP :
                                                       SHARP_ALARM_NONE;
assign full_scale_changed = (u_full_scale_x100_previous != u_full_scale_x100)
                         || (i_full_scale_x100_previous != i_full_scale_x100);
assign alarm_active = sharp_alarm_active;

// 按共享内存 ABI 固定顺序组合标量值、告警和逐字段有效位。
assign ps_snapshot_words = {
    {16'd0, 4'd0, freq_metrics_valid, freq_dc_i_valid, freq_dc_u_valid,
     freq_thd_i_valid, freq_thd_u_valid, power_metrics_valid_reg,
     freq_valid_reg, phase_valid_reg, i_pp_valid_reg, u_pp_valid_reg,
     rms_valid_reg, rms_valid_reg},
    {28'd0, sharp_alarm_code, sharp_alarm_active},
    freq_dc_i_x100,
    freq_dc_u_x100,
    freq_thd_i_x100,
    freq_thd_u_x100,
    power_factor_x100_reg,
    apparent_s_x100_reg,
    reactive_q_x100_reg,
    active_p_x100_reg,
    phase_x100_reg,
    freq_x100_reg,
    i_pp_x100_reg,
    u_pp_x100_reg,
    i_rms_x100_reg,
    u_rms_x100_reg
};

// 频域分析输出直接映射为共享内存桥消费的谐波条目。
assign ps_harmonic_valid = freq_harmonic_valid;
assign ps_harmonic_last = freq_harmonic_last;
assign ps_harmonic_index = freq_harmonic_order;
assign ps_harmonic_u_ratio = {16'd0, freq_harmonic_u_pct_x100};
assign ps_harmonic_i_ratio = {16'd0, freq_harmonic_i_pct_x100};
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
    .u_sample_valid(u_sample_valid), .u_sample_code(u_sample_code),
    .u_zero_code(u_zero_code), .u_zero_valid(u_zero_valid),
    .i_sample_valid(i_sample_valid), .i_sample_code(i_sample_code),
    .i_zero_code(i_zero_code), .i_zero_valid(i_zero_valid),
    .busy(), .done(parameters_done),
    .u_rms_raw(u_rms_raw_wire), .i_rms_raw(i_rms_raw_wire),
    .rms_valid(rms_valid_wire), .u_pp_raw(u_pp_raw_wire),
    .u_pp_valid(u_pp_valid_wire), .i_pp_raw(i_pp_raw_wire),
    .i_pp_valid(i_pp_valid_wire), .phase_offset_raw(phase_offset_raw_wire),
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
    .u_rms_raw(u_rms_raw_pending), .i_rms_raw(i_rms_raw_pending),
    .rms_valid(rms_valid_latched), .u_pp_raw(u_pp_raw_pending),
    .i_pp_raw(i_pp_raw_pending), .u_pp_valid(u_pp_valid_latched),
    .i_pp_valid(i_pp_valid_latched),
    .phase_offset_raw(phase_offset_raw_pending),
    .phase_period_raw(phase_period_raw_pending),
    .phase_valid(phase_valid_latched),
    .freq_period_raw(freq_period_raw_pending), .freq_valid(freq_valid_latched),
    .active_p_raw(active_p_raw_pending),
    .reactive_q_raw(reactive_q_raw_pending),
    .apparent_s_raw(apparent_s_raw_pending),
    .power_factor_raw(power_factor_raw_pending),
    .u_full_scale_x100(u_full_scale_x100_pending),
    .i_full_scale_x100(i_full_scale_x100_pending),
    .power_metrics_valid(power_metrics_valid_latched), .done(x100_done),
    .u_rms_x100(u_rms_x100_wire), .i_rms_x100(i_rms_x100_wire),
    .u_pp_x100(u_pp_x100_wire), .i_pp_x100(i_pp_x100_wire),
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
    .i_sample_u(freq_sample_u), .i_sample_i(freq_sample_i),
    // 样本已在此处中心化，所以零码给 0、有效位给 1：frontend 内部做
    // sample - zero_ref = sample - 0 = sample，等价于不再去直流。
    // 这与原厂 RFG 整链用例（tb_pqm_rfg_chain，已 PASS）的激励形式完全一致。
    .i_u_zero_code(16'd0), .i_u_zero_valid(1'b1),
    .i_i_zero_code(16'd0), .i_i_zero_valid(1'b1),
    .o_sample_ready(freq_sample_ready),
    .i_harmonic_ready(ps_harmonic_ready),
    .m_harmonic_valid(freq_harmonic_valid),
    .m_harmonic_last(freq_harmonic_last),
    .m_harmonic_order(freq_harmonic_order),
    .m_harmonic_present(freq_harmonic_present),
    .m_u_real(), .m_u_imag(), .m_i_real(), .m_i_imag(),
    .m_u_mag(freq_harmonic_u_mag), .m_i_mag(freq_harmonic_i_mag),
    .m_u_pct_x100(freq_harmonic_u_pct_x100), .m_i_pct_x100(freq_harmonic_i_pct_x100),
    .m_phase_vector_valid(), .m_phase_dot(), .m_phase_cross(),
    .m_phase_diff_valid(freq_phase_diff_valid),
    .m_phase_diff_deg_x100(freq_phase_diff_deg_x100),
    .filtered_frame_count()
);

// 聚合已完成握手的谐波条目，生成 THD、基波相位和直流分量等标量。
freq_metrics_raw_calc u_freq_metrics_raw_calc (
    .clk(clk), .rst_n(rst_n), .enable(1'b1),
    .s_harmonic_fire(freq_harmonic_fire),
    .s_harmonic_last(freq_harmonic_last),
    .s_harmonic_order(freq_harmonic_order),
    .s_harmonic_present(freq_harmonic_present),
    .s_u_mag(freq_harmonic_u_mag), .s_i_mag(freq_harmonic_i_mag),
    .s_u_pct_x100(freq_harmonic_u_pct_x100),
    .s_i_pct_x100(freq_harmonic_i_pct_x100),
    .s_phase_diff_valid(freq_phase_diff_valid),
    .s_phase_diff_deg_x100(freq_phase_diff_deg_x100),
    .raw_result_commit_toggle(freq_metrics_commit_toggle),
    .thd_u_raw_x100(freq_thd_u_x100), .thd_i_raw_x100(freq_thd_i_x100),
    .thd_u_valid(freq_thd_u_valid), .thd_i_valid(freq_thd_i_valid),
    .u1_mag_raw_x100(), .i1_mag_raw_x100(), .u1_mag_valid(), .i1_mag_valid(),
    .phase1_raw_x100(freq_phase1_x100), .phase1_valid(freq_phase1_valid),
    .dc_u_raw_x100(freq_dc_u_x100), .dc_i_raw_x100(freq_dc_i_x100),
    .dc_u_valid(freq_dc_u_valid), .dc_i_valid(freq_dc_i_valid),
    .dh_order_u_list_raw(), .dh_order_i_list_raw(), .dh_order_u_count_raw(),
    .dh_order_i_count_raw(), .dh_order_u_valid(), .dh_order_i_valid(),
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
        u_pp_valid_latched <= 1'b0;
        i_pp_valid_latched <= 1'b0;
        phase_valid_latched <= 1'b0;
        freq_valid_latched <= 1'b0;
        power_metrics_valid_latched <= 1'b0;
        u_rms_raw_pending <= 32'sd0;
        i_rms_raw_pending <= 32'sd0;
        u_pp_raw_pending <= 32'sd0;
        i_pp_raw_pending <= 32'sd0;
        phase_offset_raw_pending <= 32'sd0;
        phase_period_raw_pending <= 32'sd0;
        freq_period_raw_pending <= 32'sd0;
        active_p_raw_pending <= 32'sd0;
        reactive_q_raw_pending <= 32'sd0;
        apparent_s_raw_pending <= 32'sd0;
        power_factor_raw_pending <= 32'sd0;
        u_full_scale_x100_pending <= 32'd0;
        i_full_scale_x100_pending <= 32'd0;
        u_rms_x100_reg <= 32'sd0;
        i_rms_x100_reg <= 32'sd0;
        u_pp_x100_reg <= 32'sd0;
        i_pp_x100_reg <= 32'sd0;
        phase_x100_reg <= 32'sd0;
        freq_x100_reg <= 32'sd0;
        active_p_x100_reg <= 32'sd0;
        reactive_q_x100_reg <= 32'sd0;
        apparent_s_x100_reg <= 32'sd0;
        power_factor_x100_reg <= 32'sd0;
        rms_valid_reg <= 1'b0;
        u_pp_valid_reg <= 1'b0;
        i_pp_valid_reg <= 1'b0;
        phase_valid_reg <= 1'b0;
        freq_valid_reg <= 1'b0;
        power_metrics_valid_reg <= 1'b0;
        sharp_alarm_code <= SHARP_ALARM_NONE;
        sharp_alarm_active <= 1'b0;
        sharp_latest_valid <= 1'b0;
        sharp_window_valid <= 1'b0;
        u_rms_x100_latest <= 32'sd0;
        i_rms_x100_latest <= 32'sd0;
        u_rms_x100_baseline <= 32'sd0;
        i_rms_x100_baseline <= 32'sd0;
        u_full_scale_x100_previous <= 32'd0;
        i_full_scale_x100_previous <= 32'd0;
        freq_metrics_commit_d1 <= 1'b0;
        ps_snapshot_commit_toggle <= 1'b0;
    end else begin
        parameters_start <= 1'b0;
        x100_start <= 1'b0;
        u_full_scale_x100_previous <= u_full_scale_x100;
        i_full_scale_x100_previous <= i_full_scale_x100;
        freq_metrics_commit_d1 <= freq_metrics_commit_toggle;

        if (sharp_window_counter == (SHARP_MONITOR_WINDOW_CYCLES - 1)) begin
            sharp_window_counter <= 26'd0;
            if (sharp_latest_valid && !sharp_alarm_active) begin
                u_rms_x100_baseline <= u_rms_x100_latest;
                i_rms_x100_baseline <= i_rms_x100_latest;
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
                    u_rms_raw_pending <= u_rms_raw_wire;
                    i_rms_raw_pending <= i_rms_raw_wire;
                    u_pp_raw_pending <= u_pp_raw_wire;
                    i_pp_raw_pending <= i_pp_raw_wire;
                    phase_offset_raw_pending <= phase_offset_raw_wire;
                    phase_period_raw_pending <= phase_period_raw_wire;
                    freq_period_raw_pending <= freq_period_raw_wire;
                    active_p_raw_pending <= active_p_raw_wire;
                    reactive_q_raw_pending <= reactive_q_raw_phase_signed;
                    apparent_s_raw_pending <= apparent_s_raw_wire;
                    power_factor_raw_pending <= power_factor_raw_wire;
                    u_full_scale_x100_pending <= u_full_scale_x100;
                    i_full_scale_x100_pending <= i_full_scale_x100;
                    rms_valid_latched <= rms_valid_wire;
                    u_pp_valid_latched <= u_pp_valid_wire;
                    i_pp_valid_latched <= i_pp_valid_wire;
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
                    u_rms_x100_reg <= u_rms_x100_wire;
                    i_rms_x100_reg <= i_rms_x100_wire;
                    u_pp_x100_reg <= u_pp_x100_wire;
                    i_pp_x100_reg <= i_pp_x100_wire;
                    phase_x100_reg <= phase_x100_wire;
                    freq_x100_reg <= freq_x100_wire;
                    active_p_x100_reg <= active_p_x100_wire;
                    reactive_q_x100_reg <= reactive_q_x100_wire;
                    apparent_s_x100_reg <= apparent_s_x100_wire;
                    power_factor_x100_reg <= power_factor_x100_wire;
                    rms_valid_reg <= rms_valid_latched;
                    u_pp_valid_reg <= u_pp_valid_latched;
                    i_pp_valid_reg <= i_pp_valid_latched;
                    phase_valid_reg <= phase_valid_latched;
                    freq_valid_reg <= freq_valid_latched;
                    power_metrics_valid_reg <= power_metrics_valid_latched;
                    sharp_latest_valid <= rms_valid_latched;
                    u_rms_x100_latest <= u_rms_x100_wire;
                    i_rms_x100_latest <= i_rms_x100_wire;
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
            u_rms_x100_baseline <= 32'sd0;
            i_rms_x100_baseline <= 32'sd0;
            sharp_alarm_code <= SHARP_ALARM_NONE;
            sharp_alarm_active <= 1'b0;
        end
    end
end

endmodule
