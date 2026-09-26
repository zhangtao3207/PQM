`timescale 1ns / 1ps

/*
 * 模块: pqm_freq_analysis_rfg
 * 功能:
 *   freq_analysis_top 的 RFG 版，是"移出 FFT"的顶层替身。
 *
 *   替换掉的两件（FFT 前端）：
 *     fft_stream_adapter（含 xfft_0 与 data_fifo/blk_mem_gen_fft_fifo_ram IP）
 *     fft_result_receiver（正半谱筛选 + 位反转帧尾判定）
 *   丢掉的 FFT 专用件：
 *     fft_fundamental_freq_tracker（基波周期估计来自 FFT 输出；本版改用时域测频）
 *
 *   **其余后级逐条照抄原顶层**，一个都不改：
 *     fft_magnitude_calc -> fft_harmonic_stats(FUND_BIN=1) -> fft_phase_vector_calc
 *     -> phase_deg_lut_calc（内部用 rom_atan_lut_1024）-> freq_harmonic_iir_filter
 *
 *   去直流在这里做（与原 fft_stream_adapter 同一写法：两路零扩展到 17 位再相减），
 *   送进 frontend 时零点码固定给 0，于是 frontend 里的直流累加器拿到的就是中心化样本。
 *
 *   帧节奏：由内部 FSM 在上一帧收完后立刻给下一帧 i_start，帧与帧之间只隔一拍。
 *   计算期间 frontend 的 o_sample_ready 为低，采样自然被跳过 —— 这不影响结果：
 *   每一帧仍是 **连续的 512 个采样点**（= 一个 50 Hz 周期），谐波幅值/直流/帧内
 *   U-I 相位都只依赖帧内数据，帧间的时间间隔不参与计算。
 */

module pqm_freq_analysis_rfg #(
    parameter integer C_N       = 512,
    parameter integer C_K       = 64,
    parameter integer C_L       = 4,
    parameter integer C_D       = 1,
    parameter integer SHIFT     = 10,
    parameter [8:0]   HARMONIC_FUND_BIN = 9'd1
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,

    // 采样输入（与原 fft_stream_adapter 的采样侧同形）
    input  wire        i_sample_valid,
    input  wire [15:0] i_sample_u,
    input  wire [15:0] i_sample_i,
    input  wire [15:0] i_u_zero_code,
    input  wire        i_u_zero_valid,
    input  wire [15:0] i_i_zero_code,
    input  wire        i_i_zero_valid,

    // 采样握手：前端能收时才为高（计算期间为低，采样自然被跳过）
    output wire        o_sample_ready,

    // 谐波流（消费者面向，与 fft_harmonic_iir_filter 的输出同形）
    input  wire        i_harmonic_ready,
    output wire        m_harmonic_valid,
    output wire        m_harmonic_last,
    output wire [8:0]  m_harmonic_order,
    output wire        m_harmonic_present,
    output wire signed [15:0] m_u_real,
    output wire signed [15:0] m_u_imag,
    output wire signed [15:0] m_i_real,
    output wire signed [15:0] m_i_imag,
    output wire [16:0] m_u_mag,
    output wire [16:0] m_i_mag,
    output wire [15:0] m_u_pct_x100,
    output wire [15:0] m_i_pct_x100,
    output wire        m_phase_vector_valid,
    output wire signed [32:0] m_phase_dot,
    output wire signed [32:0] m_phase_cross,
    output wire        m_phase_diff_valid,
    output wire signed [15:0] m_phase_diff_deg_x100,
    output wire [15:0] filtered_frame_count
);

    localparam [15:0] CENTER_DEFAULT = 16'h8000;

    // ---------------- 去直流（照抄 fft_stream_adapter 的写法） ----------------
    wire [15:0] u_zero_ref = i_u_zero_valid ? i_u_zero_code : CENTER_DEFAULT;
    wire [15:0] i_zero_ref = i_i_zero_valid ? i_i_zero_code : CENTER_DEFAULT;

    wire signed [16:0] u_centered_ext = $signed({1'b0, i_sample_u}) - $signed({1'b0, u_zero_ref});
    wire signed [16:0] i_centered_ext = $signed({1'b0, i_sample_i}) - $signed({1'b0, i_zero_ref});
    wire signed [15:0] u_centered     = u_centered_ext[15:0];
    wire signed [15:0] i_centered     = i_centered_ext[15:0];

    // ---------------- 帧控制：上一帧收完立刻开下一帧 ----------------
    wire fe_frame_done;      // 提前声明：FSM 要先用它
    reg start_pulse;
    reg running;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            start_pulse <= 1'b0;
            running     <= 1'b0;
        end else begin
            start_pulse <= 1'b0;
            if (!enable) begin
                running <= 1'b0;
            end else if (!running) begin
                start_pulse <= 1'b1;
                running     <= 1'b1;
            end else if (fe_frame_done) begin
                running <= 1'b0;
            end
        end
    end

    // ---------------- RFG 前端 + 缩放 ----------------
    wire        fe_sample_ready;
    wire        fe_item_valid, fe_item_ready;
    wire [8:0]  fe_order;
    wire signed [31:0] fe_u_real, fe_u_imag, fe_i_real, fe_i_imag;
    wire        fe_item_last, fe_overflow, fe_channel_error;

    pqm_rfg_frontend #(
        .C_N(C_N), .C_K(C_K), .C_L(C_L), .C_D(C_D)
    ) u_frontend (
        .clk(clk), .rst_n(rst_n),
        .i_start(start_pulse), .i_sample_valid(i_sample_valid && enable),
        .i_sample_u(u_centered), .i_sample_i(i_centered),
        .i_zero_code(16'd0),
        .o_sample_ready(fe_sample_ready),
        .o_item_valid(fe_item_valid), .i_item_ready(fe_item_ready),
        .o_order(fe_order),
        .o_u_real(fe_u_real), .o_u_imag(fe_u_imag),
        .o_i_real(fe_i_real), .o_i_imag(fe_i_imag),
        .o_item_last(fe_item_last), .o_frame_done(fe_frame_done),
        .o_overflow(fe_overflow), .o_channel_error(fe_channel_error)
    );

    wire        sc_bin_valid, sc_bin_ready, sc_bin_last;
    wire [10:0] sc_bin_index;
    wire signed [15:0] sc_u_real, sc_u_imag, sc_i_real, sc_i_imag;

    pqm_rfg_scale #(
        .C_K(C_K), .SHIFT(SHIFT)
    ) u_scale (
        .clk(clk), .rst_n(rst_n), .i_start(start_pulse),
        .i_item_valid(fe_item_valid), .o_item_ready(fe_item_ready),
        .i_order(fe_order),
        .i_u_real(fe_u_real), .i_u_imag(fe_u_imag),
        .i_i_real(fe_i_real), .i_i_imag(fe_i_imag),
        .i_item_last(fe_item_last),
        .m_bin_valid(sc_bin_valid), .m_bin_ready(sc_bin_ready),
        .m_bin_last(sc_bin_last), .m_bin_index(sc_bin_index),
        .m_u_real(sc_u_real), .m_u_imag(sc_u_imag),
        .m_i_real(sc_i_real), .m_i_imag(sc_i_imag),
        .o_frame_done()
    );

    // ---------------- 后级：与原顶层逐条一致 ----------------
    wire        mag_valid, mag_last, harm_stats_s_mag_ready;
    wire [10:0] mag_bin_index;
    wire signed [15:0] mag_u_real, mag_u_imag, mag_i_real, mag_i_imag;
    wire [32:0] mag_u_mag_sq, mag_i_mag_sq;
    wire [16:0] mag_u_mag, mag_i_mag;
    wire        mag_busy, mag_frame_done;
    wire [15:0] mag_frame_count;

    fft_magnitude_calc u_fft_magnitude_calc (
        .clk(clk), .rst_n(rst_n), .enable(enable),
        .s_bin_valid(sc_bin_valid), .s_bin_ready(sc_bin_ready),
        .s_bin_last(sc_bin_last), .s_bin_index(sc_bin_index),
        .s_u_real(sc_u_real), .s_u_imag(sc_u_imag),
        .s_i_real(sc_i_real), .s_i_imag(sc_i_imag),
        .m_mag_ready(harm_stats_s_mag_ready),
        .m_mag_valid(mag_valid), .m_mag_last(mag_last), .m_bin_index(mag_bin_index),
        .m_u_real(mag_u_real), .m_u_imag(mag_u_imag),
        .m_i_real(mag_i_real), .m_i_imag(mag_i_imag),
        .m_u_mag_sq(mag_u_mag_sq), .m_u_mag(mag_u_mag),
        .m_i_mag_sq(mag_i_mag_sq), .m_i_mag(mag_i_mag),
        .calc_busy(mag_busy), .mag_frame_done(mag_frame_done),
        .mag_frame_count(mag_frame_count)
    );

    wire        hs_valid, hs_ready, hs_last;
    wire [8:0]  hs_order;
    wire        hs_present;
    wire signed [15:0] hs_u_real, hs_u_imag, hs_i_real, hs_i_imag;
    wire [16:0] hs_u_mag, hs_i_mag;
    wire [15:0] hs_u_pct, hs_i_pct;
    wire        hs_stats_busy, hs_capture_done, hs_frame_done;
    wire [15:0] hs_frame_count;
    wire [31:0] hs_u_total, hs_i_total;

    fft_harmonic_stats #(
        .FUND_BIN(HARMONIC_FUND_BIN)
    ) u_fft_harmonic_stats (
        .clk(clk), .rst_n(rst_n), .enable(enable),
        .s_mag_valid(mag_valid), .s_mag_ready(harm_stats_s_mag_ready),
        .s_mag_last(mag_last), .s_bin_index(mag_bin_index),
        .s_u_real(mag_u_real), .s_u_imag(mag_u_imag),
        .s_i_real(mag_i_real), .s_i_imag(mag_i_imag),
        .s_u_mag(mag_u_mag), .s_i_mag(mag_i_mag),
        .m_harmonic_ready(hs_ready),
        .m_harmonic_valid(hs_valid), .m_harmonic_last(hs_last),
        .m_harmonic_order(hs_order), .m_harmonic_present(hs_present),
        .m_u_real(hs_u_real), .m_u_imag(hs_u_imag),
        .m_i_real(hs_i_real), .m_i_imag(hs_i_imag),
        .m_u_mag(hs_u_mag), .m_i_mag(hs_i_mag),
        .m_u_pct_x100(hs_u_pct), .m_i_pct_x100(hs_i_pct),
        .stats_busy(hs_stats_busy), .capture_frame_done(hs_capture_done),
        .harmonic_frame_done(hs_frame_done), .harmonic_frame_count(hs_frame_count),
        .u_total_mag(hs_u_total), .i_total_mag(hs_i_total)
    );

    wire        pv_valid, pv_ready, pv_last;
    wire [8:0]  pv_order;
    wire        pv_present;
    wire signed [15:0] pv_u_real, pv_u_imag, pv_i_real, pv_i_imag;
    wire [16:0] pv_u_mag, pv_i_mag;
    wire [15:0] pv_u_pct, pv_i_pct;
    wire        pv_vector_valid;
    wire signed [32:0] pv_dot, pv_cross;
    wire        pv_busy, pv_frame_done;
    wire [15:0] pv_frame_count;

    fft_phase_vector_calc u_fft_phase_vector_calc (
        .clk(clk), .rst_n(rst_n), .enable(enable),
        .s_harmonic_valid(hs_valid), .s_harmonic_ready(hs_ready),
        .s_harmonic_last(hs_last), .s_harmonic_order(hs_order),
        .s_harmonic_present(hs_present),
        .s_u_real(hs_u_real), .s_u_imag(hs_u_imag),
        .s_i_real(hs_i_real), .s_i_imag(hs_i_imag),
        .s_u_mag(hs_u_mag), .s_i_mag(hs_i_mag),
        .s_u_pct_x100(hs_u_pct), .s_i_pct_x100(hs_i_pct),
        .m_harmonic_ready(pv_ready),
        .m_harmonic_valid(pv_valid), .m_harmonic_last(pv_last),
        .m_harmonic_order(pv_order), .m_harmonic_present(pv_present),
        .m_u_real(pv_u_real), .m_u_imag(pv_u_imag),
        .m_i_real(pv_i_real), .m_i_imag(pv_i_imag),
        .m_u_mag(pv_u_mag), .m_i_mag(pv_i_mag),
        .m_u_pct_x100(pv_u_pct), .m_i_pct_x100(pv_i_pct),
        .m_phase_vector_valid(pv_vector_valid),
        .m_phase_dot(pv_dot), .m_phase_cross(pv_cross)
    );

    wire        lut_valid, lut_ready, lut_last;
    wire [8:0]  lut_order;
    wire        lut_present;
    wire signed [15:0] lut_u_real, lut_u_imag, lut_i_real, lut_i_imag;
    wire [16:0] lut_u_mag, lut_i_mag;
    wire [15:0] lut_u_pct, lut_i_pct;
    wire        lut_vector_valid;
    wire signed [32:0] lut_dot, lut_cross;
    wire        lut_diff_valid;
    wire signed [15:0] lut_diff_deg;
    wire        lut_busy, lut_frame_done;
    wire [15:0] lut_frame_count;

    phase_deg_lut_calc u_phase_deg_lut_calc (
        .clk(clk), .rst_n(rst_n), .enable(enable),
        .s_harmonic_valid(pv_valid), .s_harmonic_ready(pv_ready),
        .s_harmonic_last(pv_last), .s_harmonic_order(pv_order),
        .s_harmonic_present(pv_present),
        .s_u_real(pv_u_real), .s_u_imag(pv_u_imag),
        .s_i_real(pv_i_real), .s_i_imag(pv_i_imag),
        .s_u_mag(pv_u_mag), .s_i_mag(pv_i_mag),
        .s_u_pct_x100(pv_u_pct), .s_i_pct_x100(pv_i_pct),
        .s_phase_vector_valid(pv_vector_valid),
        .s_phase_dot(pv_dot), .s_phase_cross(pv_cross),
        .m_harmonic_ready(lut_ready),
        .m_harmonic_valid(lut_valid), .m_harmonic_last(lut_last),
        .m_harmonic_order(lut_order), .m_harmonic_present(lut_present),
        .m_u_real(lut_u_real), .m_u_imag(lut_u_imag),
        .m_i_real(lut_i_real), .m_i_imag(lut_i_imag),
        .m_u_mag(lut_u_mag), .m_i_mag(lut_i_mag),
        .m_u_pct_x100(lut_u_pct), .m_i_pct_x100(lut_i_pct),
        .m_phase_vector_valid(lut_vector_valid),
        .m_phase_dot(lut_dot), .m_phase_cross(lut_cross),
        .m_phase_diff_valid(lut_diff_valid),
        .m_phase_diff_deg_x100(lut_diff_deg),
        .phase_deg_busy(lut_busy), .phase_deg_frame_done(lut_frame_done),
        .phase_deg_frame_count(lut_frame_count)
    );

    freq_harmonic_iir_filter u_freq_harmonic_iir_filter (
        .clk(clk), .rst_n(rst_n), .enable(enable),
        .s_harmonic_valid(lut_valid), .s_harmonic_ready(lut_ready),
        .s_harmonic_last(lut_last), .s_harmonic_order(lut_order),
        .s_harmonic_present(lut_present),
        .s_u_real(lut_u_real), .s_u_imag(lut_u_imag),
        .s_i_real(lut_i_real), .s_i_imag(lut_i_imag),
        .s_u_mag(lut_u_mag), .s_i_mag(lut_i_mag),
        .s_u_pct_x100(lut_u_pct), .s_i_pct_x100(lut_i_pct),
        .s_phase_vector_valid(lut_vector_valid),
        .s_phase_dot(lut_dot), .s_phase_cross(lut_cross),
        .s_phase_diff_valid(lut_diff_valid),
        .s_phase_diff_deg_x100(lut_diff_deg),
        .m_harmonic_ready(i_harmonic_ready),
        .m_harmonic_valid(m_harmonic_valid), .m_harmonic_last(m_harmonic_last),
        .m_harmonic_order(m_harmonic_order), .m_harmonic_present(m_harmonic_present),
        .m_u_real(m_u_real), .m_u_imag(m_u_imag),
        .m_i_real(m_i_real), .m_i_imag(m_i_imag),
        .m_u_mag(m_u_mag), .m_i_mag(m_i_mag),
        .m_u_pct_x100(m_u_pct_x100), .m_i_pct_x100(m_i_pct_x100),
        .m_phase_vector_valid(m_phase_vector_valid),
        .m_phase_dot(m_phase_dot), .m_phase_cross(m_phase_cross),
        .m_phase_diff_valid(m_phase_diff_valid),
        .m_phase_diff_deg_x100(m_phase_diff_deg_x100),
        .filtered_frame_count(filtered_frame_count)
    );

    assign o_sample_ready = fe_sample_ready;

endmodule
