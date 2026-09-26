`timescale 1ns / 1ps

/*
 * 模块: freq_analysis_top
 * 功能:
 *   频域分析链路顶层。该模块串接采样到 FFT 的数据流适配、FFT 结果筛选、幅值计算和
 *   0~500 次谐波幅值占比统计，输出后续相位差计算和显示所需的数据流。
 *
 * 输入:
 *   sample_clk: 采样写入时钟，通常接 ADC 采样所在时钟域。
 *   fft_clk: FFT IP 和频域计算工作时钟。
 *   rst_n: 低有效复位信号。
 *   analysis_enable: 频域分析链路使能，拉低时不启动新的 FFT 帧并清空下游计算输出。
 *   sample_valid: U/I 采样对当前周期有效。
 *   sample_frame_marker: 可选采样帧标记，传递给 FIFO 调试计数。
 *   u_sample_code: 电压通道原始偏置码。
 *   u_zero_code: 电压通道直流零点估计值。
 *   u_zero_valid: 电压通道零点估计有效标志。
 *   i_sample_code: 电流通道原始偏置码。
 *   i_zero_code: 电流通道直流零点估计值。
 *   i_zero_valid: 电流通道零点估计有效标志。
 *   m_mag_ready: 外部幅值调试旁路接收就绪标志；不用该旁路时可接 1'b1。
 *   m_harmonic_ready: 下游谐波统计结果接收就绪标志。
 *
 * 输出:
 *   sample_accepted: 当前采样对已写入 FFT 输入 FIFO。
 *   sample_dropped: FIFO 满导致当前采样对被丢弃。
 *   fifo_full: FFT 输入 FIFO 满标志。
 *   fifo_prog_full: FFT 输入 FIFO 接近满标志。
 *   fifo_empty: FFT 输入 FIFO 空标志。
 *   fifo_prog_empty: FFT 输入 FIFO 接近空标志。
 *   fifo_overflow_warn: FFT 输入 FIFO 接近溢出告警。
 *   fifo_overflow: FFT 输入 FIFO 溢出标志。
 *   fifo_underflow_warn: FFT 输入 FIFO 接近欠载告警。
 *   fifo_underflow: FFT 输入 FIFO 欠载标志。
 *   fifo_fft_frame_ready: FIFO 中至少有一整帧 FFT 样本可读。
 *   fifo_wr_data_count: 写端视角 FIFO 数据量。
 *   fifo_rd_data_count: 读端视角 FIFO 数据量。
 *   fifo_wr_marker_count: FIFO 写端采样帧标记计数。
 *   fifo_rd_marker_count: FIFO 兼容调试计数。
 *   fifo_wr_fft_frame_count: FIFO 写端已写满的 FFT 帧计数。
 *   fifo_rd_fft_frame_count: FIFO 读端已读出的 FFT 帧计数。
 *   fft_config_done: xfft_0 配置通道已完成一次握手。
 *   fft_input_busy: FFT 输入侧正在读取或发送一帧。
 *   fft_input_tvalid: 送入 xfft_0 的数据有效标志。
 *   fft_input_tready: xfft_0 输入数据接收就绪标志。
 *   fft_input_tlast: 送入 xfft_0 的帧尾标志。
 *   fft_output_valid: xfft_0 原始输出有效标志。
 *   fft_output_last: xfft_0 原始输出帧尾标志。
 *   fft_bin_index: xfft_0 原始输出频点索引。
 *   fft_status_tdata: xfft_0 状态通道数据。
 *   fft_status_valid: xfft_0 状态通道有效标志。
 *   event_frame_started: xfft_0 帧启动事件。
 *   event_tlast_unexpected: xfft_0 输入 TLAST 过早事件。
 *   event_tlast_missing: xfft_0 输入 TLAST 缺失事件。
 *   event_fft_overflow: xfft_0 固定点运算溢出事件。
 *   event_status_channel_halt: xfft_0 状态通道阻塞事件。
 *   event_data_in_channel_halt: xfft_0 输入通道阻塞事件。
 *   event_data_out_channel_halt: xfft_0 输出通道阻塞事件。
 *   selected_raw_frame_active: 结果筛选模块正在接收一帧原始 FFT 输出。
 *   selected_raw_frame_done: 结果筛选模块已接收完整一帧原始 FFT 输出的单周期脉冲。
 *   selected_frame_done: 正半谱频点流已被幅值模块取完的单周期脉冲。
 *   selected_raw_bin_count: 当前原始 FFT 帧内已接收的频点数量。
 *   selected_bin_count: 当前原始 FFT 帧内已筛选出的频点数量。
 *   selected_last_raw_bin_count: 上一完整原始帧接收到的频点数量。
 *   selected_last_bin_count: 上一完整原始帧筛选出的频点数量。
 *   selected_frame_count: 结果筛选模块已完整接收的原始 FFT 帧计数。
 *   m_mag_valid: 幅值结果有效标志。
 *   m_mag_last: 正半谱幅值结果帧尾标志。
 *   m_bin_index: 幅值结果对应的频点索引。
 *   m_u_real: 与幅值结果对齐的电压通道频点实部。
 *   m_u_imag: 与幅值结果对齐的电压通道频点虚部。
 *   m_i_real: 与幅值结果对齐的电流通道频点实部。
 *   m_i_imag: 与幅值结果对齐的电流通道频点虚部。
 *   m_u_mag_sq: 电压通道幅值平方和。
 *   m_u_mag: 电压通道幅值。
 *   m_i_mag_sq: 电流通道幅值平方和。
 *   m_i_mag: 电流通道幅值。
 *   mag_calc_busy: 幅值计算模块正在计算或等待下游接收。
 *   mag_frame_done: 一帧正半谱幅值结果已被下游取完的单周期脉冲。
 *   mag_frame_count: 已完整输出的正半谱幅值帧计数。
 *   m_harmonic_valid: 滤波后谐波结果有效标志。
 *   m_harmonic_last: 滤波后 0~500 次谐波结果的最后一项标志。
 *   m_harmonic_order: 滤波后当前输出的谐波次数。
 *   m_harmonic_present: 滤波后当前谐波是否有效。
 *   m_harmonic_u_real: 滤波后当前谐波电压通道实部。
 *   m_harmonic_u_imag: 滤波后当前谐波电压通道虚部。
 *   m_harmonic_i_real: 滤波后当前谐波电流通道实部。
 *   m_harmonic_i_imag: 滤波后当前谐波电流通道虚部。
 *   m_harmonic_u_mag: 滤波后当前谐波电压通道幅值。
 *   m_harmonic_i_mag: 滤波后当前谐波电流通道幅值。
 *   m_harmonic_u_pct_x100: 滤波后当前谐波电压幅值占本帧电压总幅值的百分比。
 *   m_harmonic_i_pct_x100: 滤波后当前谐波电流幅值占本帧电流总幅值的百分比。
 *   m_phase_vector_valid: 滤波后当前谐波的 phase_dot/phase_cross 是否有效。
 *   m_phase_dot: 滤波后的 U-I 相位差 atan2 同相投影。
 *   m_phase_cross: 滤波后的 U-I 相位差 atan2 正交投影。
 *   m_phase_diff_valid: 滤波后当前谐波的 U-I 相位差角度是否有效。
 *   m_phase_diff_deg_x100: 滤波后当前谐波的 U-I 相位差角度，单位为 deg_x100。
 *   harmonic_stats_busy: 谐波统计模块正在接收、归一化或输出一帧结果。
 *   harmonic_capture_frame_done: 谐波统计模块已捕获一帧幅值结果的单周期脉冲。
 *   harmonic_frame_done: 0~500 次谐波统计结果已输出完毕的单周期脉冲。
 *   harmonic_frame_count: 已输出完成的谐波统计帧计数。
 *   harmonic_u_total_mag: 本帧 0~500 次谐波的电压幅值总和。
 *   harmonic_i_total_mag: 本帧 0~500 次谐波的电流幅值总和。
 *   phase_deg_busy: 相位角查表模块正在计算或等待下游接收。
 *   phase_deg_frame_done: 0~500 次谐波相位角结果已输出完毕的单周期脉冲。
 *   phase_deg_frame_count: 已完整输出的相位角结果帧计数。
 */
module freq_analysis_top #(
    parameter integer FIFO_ADDR_WIDTH = 13,
    parameter [10:0] FIRST_ANALYSIS_BIN = 11'd0,
    parameter [10:0] LAST_ANALYSIS_BIN  = 11'd1024,
    parameter [10:0] HARMONIC_FUND_BIN  = 11'd1
)(
    input  wire               sample_clk,
    input  wire               fft_clk,
    input  wire               rst_n,
    input  wire               analysis_enable,
    input  wire               sample_valid,
    input  wire               sample_frame_marker,
    input  wire [15:0]        u_sample_code,
    input  wire [15:0]        u_zero_code,
    input  wire               u_zero_valid,
    input  wire [15:0]        i_sample_code,
    input  wire [15:0]        i_zero_code,
    input  wire               i_zero_valid,
    input  wire               m_mag_ready,
    input  wire               m_harmonic_ready,
    output wire               sample_accepted,
    output wire               sample_dropped,
    output wire               fifo_full,
    output wire               fifo_prog_full,
    output wire               fifo_empty,
    output wire               fifo_prog_empty,
    output wire               fifo_overflow_warn,
    output wire               fifo_overflow,
    output wire               fifo_underflow_warn,
    output wire               fifo_underflow,
    output wire               fifo_fft_frame_ready,
    output wire [FIFO_ADDR_WIDTH:0] fifo_wr_data_count,
    output wire [FIFO_ADDR_WIDTH:0] fifo_rd_data_count,
    output wire [7:0]         fifo_wr_marker_count,
    output wire [7:0]         fifo_rd_marker_count,
    output wire [15:0]        fifo_wr_fft_frame_count,
    output wire [15:0]        fifo_rd_fft_frame_count,
    output wire               fft_config_done,
    output wire               fft_input_busy,
    output wire               fft_input_tvalid,
    output wire               fft_input_tready,
    output wire               fft_input_tlast,
    output wire               fft_output_valid,
    output wire               fft_output_last,
    output wire [10:0]        fft_bin_index,
    output wire [7:0]         fft_status_tdata,
    output wire               fft_status_valid,
    output wire               event_frame_started,
    output wire               event_tlast_unexpected,
    output wire               event_tlast_missing,
    output wire               event_fft_overflow,
    output wire               event_status_channel_halt,
    output wire               event_data_in_channel_halt,
    output wire               event_data_out_channel_halt,
    output wire               selected_raw_frame_active,
    output wire               selected_raw_frame_done,
    output wire               selected_frame_done,
    output wire [11:0]        selected_raw_bin_count,
    output wire [11:0]        selected_bin_count,
    output wire [11:0]        selected_last_raw_bin_count,
    output wire [11:0]        selected_last_bin_count,
    output wire [15:0]        selected_frame_count,
    output wire               m_mag_valid,
    output wire               m_mag_last,
    output wire [10:0]        m_bin_index,
    output wire signed [15:0] m_u_real,
    output wire signed [15:0] m_u_imag,
    output wire signed [15:0] m_i_real,
    output wire signed [15:0] m_i_imag,
    output wire [32:0]        m_u_mag_sq,
    output wire [16:0]        m_u_mag,
    output wire [32:0]        m_i_mag_sq,
    output wire [16:0]        m_i_mag,
    output wire               mag_calc_busy,
    output wire               mag_frame_done,
    output wire [15:0]        mag_frame_count,
    output wire signed [31:0] fund_freq_period_raw,
    output wire               fund_freq_valid,
    output wire               m_harmonic_valid,
    output wire               m_harmonic_last,
    output wire [8:0]         m_harmonic_order,
    output wire               m_harmonic_present,
    output wire signed [15:0] m_harmonic_u_real,
    output wire signed [15:0] m_harmonic_u_imag,
    output wire signed [15:0] m_harmonic_i_real,
    output wire signed [15:0] m_harmonic_i_imag,
    output wire [16:0]        m_harmonic_u_mag,
    output wire [16:0]        m_harmonic_i_mag,
    output wire [15:0]        m_harmonic_u_pct_x100,
    output wire [15:0]        m_harmonic_i_pct_x100,
    output wire               m_phase_vector_valid,
    output wire signed [32:0] m_phase_dot,
    output wire signed [32:0] m_phase_cross,
    output wire               m_phase_diff_valid,
    output wire signed [15:0] m_phase_diff_deg_x100,
    output wire               harmonic_stats_busy,
    output wire               harmonic_capture_frame_done,
    output wire               harmonic_frame_done,
    output wire [15:0]        harmonic_frame_count,
    output wire [31:0]        harmonic_u_total_mag,
    output wire [31:0]        harmonic_i_total_mag,
    output wire               phase_deg_busy,
    output wire               phase_deg_frame_done,
    output wire [15:0]        phase_deg_frame_count
);

wire               fft_result_ready;
wire signed [15:0] fft_u_real;
wire signed [15:0] fft_u_imag;
wire signed [15:0] fft_i_real;
wire signed [15:0] fft_i_imag;
wire [63:0]        fft_output_tdata;
wire [23:0]        fft_output_tuser;
wire               selected_bin_ready;
wire               selected_bin_valid;
wire               selected_bin_last;
wire [10:0]        selected_bin_index;
wire signed [15:0] selected_u_real;
wire signed [15:0] selected_u_imag;
wire signed [15:0] selected_i_real;
wire signed [15:0] selected_i_imag;
wire               harmonic_mag_ready;
wire               mag_output_ready;
wire               phase_vector_ready;
wire               stats_harmonic_valid;
wire               stats_harmonic_last;
wire [8:0]         stats_harmonic_order;
wire               stats_harmonic_present;
wire signed [15:0] stats_harmonic_u_real;
wire signed [15:0] stats_harmonic_u_imag;
wire signed [15:0] stats_harmonic_i_real;
wire signed [15:0] stats_harmonic_i_imag;
wire [16:0]        stats_harmonic_u_mag;
wire [16:0]        stats_harmonic_i_mag;
wire [15:0]        stats_harmonic_u_pct_x100;
wire [15:0]        stats_harmonic_i_pct_x100;
wire               phase_deg_ready;
wire               phase_vec_harmonic_valid;
wire               phase_vec_harmonic_last;
wire [8:0]         phase_vec_harmonic_order;
wire               phase_vec_harmonic_present;
wire signed [15:0] phase_vec_harmonic_u_real;
wire signed [15:0] phase_vec_harmonic_u_imag;
wire signed [15:0] phase_vec_harmonic_i_real;
wire signed [15:0] phase_vec_harmonic_i_imag;
wire [16:0]        phase_vec_harmonic_u_mag;
wire [16:0]        phase_vec_harmonic_i_mag;
wire [15:0]        phase_vec_harmonic_u_pct_x100;
wire [15:0]        phase_vec_harmonic_i_pct_x100;
wire               phase_vec_vector_valid;
wire signed [32:0] phase_vec_dot;
wire signed [32:0] phase_vec_cross;
wire               phase_filter_ready;
wire               phase_deg_harmonic_valid;
wire               phase_deg_harmonic_last;
wire [8:0]         phase_deg_harmonic_order;
wire               phase_deg_harmonic_present;
wire signed [15:0] phase_deg_u_real;
wire signed [15:0] phase_deg_u_imag;
wire signed [15:0] phase_deg_i_real;
wire signed [15:0] phase_deg_i_imag;
wire [16:0]        phase_deg_u_mag;
wire [16:0]        phase_deg_i_mag;
wire [15:0]        phase_deg_u_pct_x100;
wire [15:0]        phase_deg_i_pct_x100;
wire               phase_deg_vector_valid;
wire signed [32:0] phase_deg_dot;
wire signed [32:0] phase_deg_cross;
wire               phase_deg_diff_valid;
wire signed [15:0] phase_deg_diff_x100;

// 组合合并外部幅值调试旁路和内部谐波统计模块的反压。
assign mag_output_ready = m_mag_ready && harmonic_mag_ready;

// 实例化 FFT 数据流适配器，负责采样去直流、FIFO 缓冲、驱动 xfft_0 并拆出原始频点复数值。
fft_stream_adapter #(
    .FIFO_ADDR_WIDTH(FIFO_ADDR_WIDTH)
) u_fft_stream_adapter (
    .sample_clk               (sample_clk),
    .fft_clk                  (fft_clk),
    .rst_n                    (rst_n),
    .fft_enable               (analysis_enable),
    .sample_valid             (sample_valid),
    .sample_frame_marker      (sample_frame_marker),
    .u_sample_code            (u_sample_code),
    .u_zero_code              (u_zero_code),
    .u_zero_valid             (u_zero_valid),
    .i_sample_code            (i_sample_code),
    .i_zero_code              (i_zero_code),
    .i_zero_valid             (i_zero_valid),
    .fft_output_ready         (fft_result_ready),
    .sample_accepted          (sample_accepted),
    .sample_dropped           (sample_dropped),
    .fifo_full                (fifo_full),
    .fifo_prog_full           (fifo_prog_full),
    .fifo_empty               (fifo_empty),
    .fifo_prog_empty          (fifo_prog_empty),
    .fifo_overflow_warn       (fifo_overflow_warn),
    .fifo_overflow            (fifo_overflow),
    .fifo_underflow_warn      (fifo_underflow_warn),
    .fifo_underflow           (fifo_underflow),
    .fifo_fft_frame_ready     (fifo_fft_frame_ready),
    .fifo_wr_data_count       (fifo_wr_data_count),
    .fifo_rd_data_count       (fifo_rd_data_count),
    .fifo_wr_marker_count     (fifo_wr_marker_count),
    .fifo_rd_marker_count     (fifo_rd_marker_count),
    .fifo_wr_fft_frame_count  (fifo_wr_fft_frame_count),
    .fifo_rd_fft_frame_count  (fifo_rd_fft_frame_count),
    .fft_config_done          (fft_config_done),
    .fft_input_busy           (fft_input_busy),
    .fft_input_tvalid         (fft_input_tvalid),
    .fft_input_tready         (fft_input_tready),
    .fft_input_tlast          (fft_input_tlast),
    .fft_output_valid         (fft_output_valid),
    .fft_output_last          (fft_output_last),
    .fft_bin_index            (fft_bin_index),
    .u_fft_real               (fft_u_real),
    .u_fft_imag               (fft_u_imag),
    .i_fft_real               (fft_i_real),
    .i_fft_imag               (fft_i_imag),
    .fft_output_tdata         (fft_output_tdata),
    .fft_output_tuser         (fft_output_tuser),
    .fft_status_tdata         (fft_status_tdata),
    .fft_status_valid         (fft_status_valid),
    .event_frame_started      (event_frame_started),
    .event_tlast_unexpected   (event_tlast_unexpected),
    .event_tlast_missing      (event_tlast_missing),
    .event_fft_overflow       (event_fft_overflow),
    .event_status_channel_halt(event_status_channel_halt),
    .event_data_in_channel_halt(event_data_in_channel_halt),
    .event_data_out_channel_halt(event_data_out_channel_halt)
);

// 实例化 FFT 结果接收器，按参数筛选正半谱频点；默认从 bin 0 开始，便于后续统计 0 次谐波。
fft_result_receiver #(
    .FIRST_BIN(FIRST_ANALYSIS_BIN),
    .LAST_BIN (LAST_ANALYSIS_BIN)
) u_fft_result_receiver (
    .clk                          (fft_clk),
    .rst_n                        (rst_n),
    .enable                       (analysis_enable),
    .s_fft_valid                  (fft_output_valid),
    .s_fft_ready                  (fft_result_ready),
    .s_fft_last                   (fft_output_last),
    .s_bin_index                  (fft_bin_index),
    .s_u_real                     (fft_u_real),
    .s_u_imag                     (fft_u_imag),
    .s_i_real                     (fft_i_real),
    .s_i_imag                     (fft_i_imag),
    .m_bin_ready                  (selected_bin_ready),
    .m_bin_valid                  (selected_bin_valid),
    .m_bin_last                   (selected_bin_last),
    .m_bin_index                  (selected_bin_index),
    .m_u_real                     (selected_u_real),
    .m_u_imag                     (selected_u_imag),
    .m_i_real                     (selected_i_real),
    .m_i_imag                     (selected_i_imag),
    .raw_frame_active             (selected_raw_frame_active),
    .raw_frame_done               (selected_raw_frame_done),
    .selected_frame_done          (selected_frame_done),
    .raw_bin_count                (selected_raw_bin_count),
    .selected_bin_count           (selected_bin_count),
    .last_frame_raw_bin_count     (selected_last_raw_bin_count),
    .last_frame_selected_bin_count(selected_last_bin_count),
    .frame_count                  (selected_frame_count)
);

// 实例化幅值计算器，输出与幅值对齐的 real/imag，供后续相位差和谐波统计模块使用。
fft_magnitude_calc u_fft_magnitude_calc (
    .clk           (fft_clk),
    .rst_n         (rst_n),
    .enable        (analysis_enable),
    .s_bin_valid   (selected_bin_valid),
    .s_bin_ready   (selected_bin_ready),
    .s_bin_last    (selected_bin_last),
    .s_bin_index   (selected_bin_index),
    .s_u_real      (selected_u_real),
    .s_u_imag      (selected_u_imag),
    .s_i_real      (selected_i_real),
    .s_i_imag      (selected_i_imag),
    .m_mag_ready   (mag_output_ready),
    .m_mag_valid   (m_mag_valid),
    .m_mag_last    (m_mag_last),
    .m_bin_index   (m_bin_index),
    .m_u_real      (m_u_real),
    .m_u_imag      (m_u_imag),
    .m_i_real      (m_i_real),
    .m_i_imag      (m_i_imag),
    .m_u_mag_sq    (m_u_mag_sq),
    .m_u_mag       (m_u_mag),
    .m_i_mag_sq    (m_i_mag_sq),
    .m_i_mag       (m_i_mag),
    .calc_busy     (mag_calc_busy),
    .mag_frame_done(mag_frame_done),
    .mag_frame_count(mag_frame_count)
);

// 实例化谐波统计模块，按基波所在 bin 统计 0~500 次谐波 U/I 幅值占比。
// 基于相邻 FFT 帧基波 bin 的相位增量估计频率，给时域文字区提供抗谐波的周期 raw。
fft_fundamental_freq_tracker u_fft_fundamental_freq_tracker (
    .clk            (fft_clk),
    .rst_n          (rst_n),
    .enable         (analysis_enable),
    .s_mag_valid    (m_mag_valid),
    .s_mag_ready    (mag_output_ready),
    .s_bin_index    (m_bin_index),
    .s_u_real       (m_u_real),
    .s_u_imag       (m_u_imag),
    .s_u_mag        (m_u_mag),
    .freq_period_raw(fund_freq_period_raw),
    .freq_valid     (fund_freq_valid)
);

fft_harmonic_stats #(
    .FUND_BIN(HARMONIC_FUND_BIN)
) u_fft_harmonic_stats (
    .clk                 (fft_clk),
    .rst_n               (rst_n),
    .enable              (analysis_enable),
    .s_mag_valid         (m_mag_valid),
    .s_mag_ready         (harmonic_mag_ready),
    .s_mag_last          (m_mag_last),
    .s_bin_index         (m_bin_index),
    .s_u_real            (m_u_real),
    .s_u_imag            (m_u_imag),
    .s_i_real            (m_i_real),
    .s_i_imag            (m_i_imag),
    .s_u_mag             (m_u_mag),
    .s_i_mag             (m_i_mag),
    .m_harmonic_ready    (phase_vector_ready),
    .m_harmonic_valid    (stats_harmonic_valid),
    .m_harmonic_last     (stats_harmonic_last),
    .m_harmonic_order    (stats_harmonic_order),
    .m_harmonic_present  (stats_harmonic_present),
    .m_u_real            (stats_harmonic_u_real),
    .m_u_imag            (stats_harmonic_u_imag),
    .m_i_real            (stats_harmonic_i_real),
    .m_i_imag            (stats_harmonic_i_imag),
    .m_u_mag             (stats_harmonic_u_mag),
    .m_i_mag             (stats_harmonic_i_mag),
    .m_u_pct_x100        (stats_harmonic_u_pct_x100),
    .m_i_pct_x100        (stats_harmonic_i_pct_x100),
    .stats_busy          (harmonic_stats_busy),
    .capture_frame_done  (harmonic_capture_frame_done),
    .harmonic_frame_done (harmonic_frame_done),
    .harmonic_frame_count(harmonic_frame_count),
    .u_total_mag         (harmonic_u_total_mag),
    .i_total_mag         (harmonic_i_total_mag)
);

// 实例化相位向量计算模块，生成 U-I 相位差 atan2 所需的 dot/cross。
fft_phase_vector_calc u_fft_phase_vector_calc (
    .clk                 (fft_clk),
    .rst_n               (rst_n),
    .enable              (analysis_enable),
    .s_harmonic_valid    (stats_harmonic_valid),
    .s_harmonic_ready    (phase_vector_ready),
    .s_harmonic_last     (stats_harmonic_last),
    .s_harmonic_order    (stats_harmonic_order),
    .s_harmonic_present  (stats_harmonic_present),
    .s_u_real            (stats_harmonic_u_real),
    .s_u_imag            (stats_harmonic_u_imag),
    .s_i_real            (stats_harmonic_i_real),
    .s_i_imag            (stats_harmonic_i_imag),
    .s_u_mag             (stats_harmonic_u_mag),
    .s_i_mag             (stats_harmonic_i_mag),
    .s_u_pct_x100        (stats_harmonic_u_pct_x100),
    .s_i_pct_x100        (stats_harmonic_i_pct_x100),
    .m_harmonic_ready    (phase_deg_ready),
    .m_harmonic_valid    (phase_vec_harmonic_valid),
    .m_harmonic_last     (phase_vec_harmonic_last),
    .m_harmonic_order    (phase_vec_harmonic_order),
    .m_harmonic_present  (phase_vec_harmonic_present),
    .m_u_real            (phase_vec_harmonic_u_real),
    .m_u_imag            (phase_vec_harmonic_u_imag),
    .m_i_real            (phase_vec_harmonic_i_real),
    .m_i_imag            (phase_vec_harmonic_i_imag),
    .m_u_mag             (phase_vec_harmonic_u_mag),
    .m_i_mag             (phase_vec_harmonic_i_mag),
    .m_u_pct_x100        (phase_vec_harmonic_u_pct_x100),
    .m_i_pct_x100        (phase_vec_harmonic_i_pct_x100),
    .m_phase_vector_valid(phase_vec_vector_valid),
    .m_phase_dot         (phase_vec_dot),
    .m_phase_cross       (phase_vec_cross)
);

// 实例化 ROM 查表相位角模块，将 dot/cross 转换为最终 U-I 相位差 deg_x100。
phase_deg_lut_calc u_phase_deg_lut_calc (
    .clk                 (fft_clk),
    .rst_n               (rst_n),
    .enable              (analysis_enable),
    .s_harmonic_valid    (phase_vec_harmonic_valid),
    .s_harmonic_ready    (phase_deg_ready),
    .s_harmonic_last     (phase_vec_harmonic_last),
    .s_harmonic_order    (phase_vec_harmonic_order),
    .s_harmonic_present  (phase_vec_harmonic_present),
    .s_u_real            (phase_vec_harmonic_u_real),
    .s_u_imag            (phase_vec_harmonic_u_imag),
    .s_i_real            (phase_vec_harmonic_i_real),
    .s_i_imag            (phase_vec_harmonic_i_imag),
    .s_u_mag             (phase_vec_harmonic_u_mag),
    .s_i_mag             (phase_vec_harmonic_i_mag),
    .s_u_pct_x100        (phase_vec_harmonic_u_pct_x100),
    .s_i_pct_x100        (phase_vec_harmonic_i_pct_x100),
    .s_phase_vector_valid(phase_vec_vector_valid),
    .s_phase_dot         (phase_vec_dot),
    .s_phase_cross       (phase_vec_cross),
    .m_harmonic_ready    (phase_filter_ready),
    .m_harmonic_valid    (phase_deg_harmonic_valid),
    .m_harmonic_last     (phase_deg_harmonic_last),
    .m_harmonic_order    (phase_deg_harmonic_order),
    .m_harmonic_present  (phase_deg_harmonic_present),
    .m_u_real            (phase_deg_u_real),
    .m_u_imag            (phase_deg_u_imag),
    .m_i_real            (phase_deg_i_real),
    .m_i_imag            (phase_deg_i_imag),
    .m_u_mag             (phase_deg_u_mag),
    .m_i_mag             (phase_deg_i_mag),
    .m_u_pct_x100        (phase_deg_u_pct_x100),
    .m_i_pct_x100        (phase_deg_i_pct_x100),
    .m_phase_vector_valid(phase_deg_vector_valid),
    .m_phase_dot         (phase_deg_dot),
    .m_phase_cross       (phase_deg_cross),
    .m_phase_diff_valid  (phase_deg_diff_valid),
    .m_phase_diff_deg_x100(phase_deg_diff_x100),
    .phase_deg_busy      (phase_deg_busy),
    .phase_deg_frame_done(phase_deg_frame_done),
    .phase_deg_frame_count(phase_deg_frame_count)
);

// 对相位角查表后的完整谐波流做统一 IIR 滤波，保证 freq_analysis_top 的公开谐波接口均为滤波后数据。
freq_harmonic_iir_filter u_freq_harmonic_iir_filter (
    .clk                    (fft_clk),
    .rst_n                  (rst_n),
    .enable                 (analysis_enable),
    .s_harmonic_valid       (phase_deg_harmonic_valid),
    .s_harmonic_ready       (phase_filter_ready),
    .s_harmonic_last        (phase_deg_harmonic_last),
    .s_harmonic_order       (phase_deg_harmonic_order),
    .s_harmonic_present     (phase_deg_harmonic_present),
    .s_u_real               (phase_deg_u_real),
    .s_u_imag               (phase_deg_u_imag),
    .s_i_real               (phase_deg_i_real),
    .s_i_imag               (phase_deg_i_imag),
    .s_u_mag                (phase_deg_u_mag),
    .s_i_mag                (phase_deg_i_mag),
    .s_u_pct_x100           (phase_deg_u_pct_x100),
    .s_i_pct_x100           (phase_deg_i_pct_x100),
    .s_phase_vector_valid   (phase_deg_vector_valid),
    .s_phase_dot            (phase_deg_dot),
    .s_phase_cross          (phase_deg_cross),
    .s_phase_diff_valid     (phase_deg_diff_valid),
    .s_phase_diff_deg_x100  (phase_deg_diff_x100),
    .m_harmonic_ready       (m_harmonic_ready),
    .m_harmonic_valid       (m_harmonic_valid),
    .m_harmonic_last        (m_harmonic_last),
    .m_harmonic_order       (m_harmonic_order),
    .m_harmonic_present     (m_harmonic_present),
    .m_u_real               (m_harmonic_u_real),
    .m_u_imag               (m_harmonic_u_imag),
    .m_i_real               (m_harmonic_i_real),
    .m_i_imag               (m_harmonic_i_imag),
    .m_u_mag                (m_harmonic_u_mag),
    .m_i_mag                (m_harmonic_i_mag),
    .m_u_pct_x100           (m_harmonic_u_pct_x100),
    .m_i_pct_x100           (m_harmonic_i_pct_x100),
    .m_phase_vector_valid   (m_phase_vector_valid),
    .m_phase_dot            (m_phase_dot),
    .m_phase_cross          (m_phase_cross),
    .m_phase_diff_valid     (m_phase_diff_valid),
    .m_phase_diff_deg_x100  (m_phase_diff_deg_x100),
    .filtered_frame_count   ()
);

endmodule
