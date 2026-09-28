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
 *     magnitude_calc -> harmonic_stats(FUND_BIN=1) -> phase_vector_calc
 *     -> phase_deg_lut_calc（内部用 rom_atan_lut_1024）-> freq_harmonic_iir_filter
 *
 *   去直流在这里做（与原 fft_stream_adapter 同一写法：两路零扩展到 17 位再相减），
 *   送进 frontend 时零点码固定给 0，于是 frontend 里的直流累加器拿到的就是中心化样本。
 *
 *   帧节奏：由内部 FSM 在上一帧收完后立刻给下一帧 i_start，帧与帧之间只隔一拍。
 *   计算期间 frontend 的 o_sample_ready 为低，采样自然被跳过 —— 这不影响结果：
 *   每一帧仍是 **连续的 512 个采样点**（= 一个 50 Hz 周期），谐波幅值/直流/帧内
 *   U1-U2 相位都只依赖帧内数据，帧间的时间间隔不参与计算。
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
    input  wire [15:0] i_sample_u1,
    input  wire [15:0] i_sample_u2,
    input  wire [15:0] i_u1_zero_code,
    input  wire        i_u1_zero_valid,
    input  wire [15:0] i_u2_zero_code,
    input  wire        i_u2_zero_valid,

    // 采样握手：前端能收时才为高（计算期间为低，采样自然被跳过）
    output wire        o_sample_ready,

    // 谐波流（消费者面向，与 fft_harmonic_iir_filter 的输出同形）
    input  wire        i_harmonic_ready,
    output wire        m_harmonic_valid,
    output wire        m_harmonic_last,
    output wire [8:0]  m_harmonic_order,
    output wire        m_harmonic_present,
    output wire signed [15:0] m_u1_real,
    output wire signed [15:0] m_u1_imag,
    output wire signed [15:0] m_u2_real,
    output wire signed [15:0] m_u2_imag,
    output wire [16:0] m_u1_mag,
    output wire [16:0] m_u2_mag,
    output wire [15:0] m_u1_pct_x100,
    output wire [15:0] m_u2_pct_x100,
    output wire        m_phase_vector_valid,
    output wire signed [32:0] m_phase_dot,
    output wire signed [32:0] m_phase_cross,
    output wire        m_phase_diff_valid,
    output wire signed [15:0] m_phase_diff_deg_x100,
    output wire [15:0] filtered_frame_count,
    // 缺陷 3：饱和/溢出可见性。这三个信号本模块内部早就有（fe_overflow、
    // fifo_u*_ovf），但全工程没有任何消费者，溢出发生时界面只会显示错数据。
    output wire        o_center_sat,     // 去零点 17→16 位发生饱和（任一通道，组合）
    output wire        o_rfg_overflow,   // RFG 引擎内部溢出粘滞（U1|U2）
    output wire        o_fifo_overflow   // 取样 FIFO 溢出粘滞（U1|U2）
);

    localparam [15:0] CENTER_DEFAULT = 16'h8000;

    // ---------------- 去直流（照抄 fft_stream_adapter 的写法） ----------------
    wire [15:0] u1_zero_ref = i_u1_zero_valid ? i_u1_zero_code : CENTER_DEFAULT;
    wire [15:0] u2_zero_ref = i_u2_zero_valid ? i_u2_zero_code : CENTER_DEFAULT;

// 去直流的位宽契约（踩过，写清楚）：
//   两个输入都是 16 位，但**只能按有符号（两补码）相减**，不能零扩展成 17 位无符号再相减。
//   原因：本模块被 pqm_measurement_core 以"已中心化样本 + zero_code = 0"调用，
//   那里送进来的样本本身就是**两补码**；零扩展相减得到的 0..65535 再取低 16 位，
//   实际上是"把位型重新解释成两补码"，靠取低位才碰巧成立，
//   而一旦改成饱和（本轮修复）就会把负样本钳到 +32767，整条频域链当场变成巨直流。
//   （实测：tb_pqm_rfg_chain 立刻从 H1≈71% 变成 DC 95.95%，正好暴露这一点。）
//   写成 $signed 相减后：zero_code=0 时是精确直通；
//   文档契约"原始偏移码 - 零点码"也同样正确（两个偏移码同域的差等于真差）。
//   饱和限取满 16 位有符号范围 ±32768/+32767：对 16 位操作数永不触发（精确直通），
//   而万一被当成偏移码调用（真差可达 ±65535）也是钳位而不是回绕。
localparam signed [16:0] CENTER_MAX =  17'sd32767;
localparam signed [16:0] CENTER_MIN = -17'sd32768;
wire signed [16:0] u1_centered_ext = $signed(i_sample_u1) - $signed(u1_zero_ref);
wire signed [16:0] u2_centered_ext = $signed(i_sample_u2) - $signed(u2_zero_ref);
wire u1_center_sat = (u1_centered_ext > CENTER_MAX) || (u1_centered_ext < CENTER_MIN);
wire u2_center_sat = (u2_centered_ext > CENTER_MAX) || (u2_centered_ext < CENTER_MIN);
wire signed [15:0] u1_centered = u1_center_sat ? (u1_centered_ext[16] ? 16'sh8000 : 16'sh7FFF)
                                             : u1_centered_ext[15:0];
wire signed [15:0] u2_centered = u2_center_sat ? (u2_centered_ext[16] ? 16'sh8000 : 16'sh7FFF)
                                             : u2_centered_ext[15:0];

    // ---------------- 帧控制：上一帧收完立刻开下一帧 ----------------
    wire fe_frame_done;      // 提前声明：FSM 要先用它
    // 前端采样握手，提前声明：下面 FIFO 的 fifo_sample_pop 要先用它。
    // （旧版这行被粘在 "RFG 前端 + 缩放" 那行注释末尾，实际被注释掉，
    //   靠隐式 wire 兜住，综合报 Synth 8-11241 undeclared symbol。）
    wire fe_sample_ready;
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
            // 注意：不能只判 fe_frame_done。它是 frontend 里的电平，只被 i_start 清零；
            // 而发脉冲的那一拍 running 刚置 1、该电平仍是上一帧的 1，若在此清 running
            // 会立刻再发一个脉冲（实测两拍内两个 i_start），把只以 i_start 为帧边界的
            // pqm_rfg_dc_sum 提前清零，导致该帧少累加样本、直流项永不产出。
            end else if (fe_frame_done && !start_pulse) begin
                running <= 1'b0;
            end
        end
    end

    // ---------------- 每通道一级小缓冲 ----------------
    // 让 RFG 每次都能取到**连续的** N 个采样点：ADC 一直在产数据，
    // RFG 计算期的采样先存进 FIFO，下一帧再取，不会出现"跨周期的 512 点"。
    wire [15:0] fifo_u1_dout, fifo_u2_dout;
    wire        fifo_u1_empty, fifo_u2_empty, fifo_u1_full, fifo_u2_full;
    wire        fifo_u1_ovf, fifo_u2_ovf;
    wire [6:0]  fifo_u1_cnt, fifo_u2_cnt;

    wire        fifo_sample_valid = !fifo_u1_empty && !fifo_u2_empty;
    wire        fifo_sample_pop   = fe_sample_ready && fifo_sample_valid;

    pqm_sample_fifo #(.DEPTH(64), .AW(6)) u_fifo_u1 (
        .clk(clk), .rst_n(rst_n),
        .i_wr_en(i_sample_valid && enable), .i_din(u1_centered),
        .i_rd_en(fifo_sample_pop), .o_dout(fifo_u1_dout),
        .o_empty(fifo_u1_empty), .o_full(fifo_u1_full),
        .o_overflow(fifo_u1_ovf), .o_count(fifo_u1_cnt)
    );

    pqm_sample_fifo #(.DEPTH(64), .AW(6)) u_fifo_u2 (
        .clk(clk), .rst_n(rst_n),
        .i_wr_en(i_sample_valid && enable), .i_din(u2_centered),
        .i_rd_en(fifo_sample_pop), .o_dout(fifo_u2_dout),
        .o_empty(fifo_u2_empty), .o_full(fifo_u2_full),
        .o_overflow(fifo_u2_ovf), .o_count(fifo_u2_cnt)
    );

    // ---------------- RFG 前端 + 缩放 ----------------
    wire        fe_item_valid, fe_item_ready;
    wire [8:0]  fe_order;
    wire signed [31:0] fe_u1_real, fe_u1_imag, fe_u2_real, fe_u2_imag;
    wire        fe_item_last, fe_overflow, fe_channel_error;

    pqm_rfg_frontend #(
        .C_N(C_N), .C_K(C_K), .C_L(C_L), .C_D(C_D)
    ) u_frontend (
        .clk(clk), .rst_n(rst_n),
        .i_start(start_pulse), .i_sample_valid(fifo_sample_valid),
        .i_sample_u1(fifo_u1_dout), .i_sample_u2(fifo_u2_dout),
        .i_zero_code(16'd0),
        .o_sample_ready(fe_sample_ready),
        .o_item_valid(fe_item_valid), .i_item_ready(fe_item_ready),
        .o_order(fe_order),
        .o_u1_real(fe_u1_real), .o_u1_imag(fe_u1_imag),
        .o_u2_real(fe_u2_real), .o_u2_imag(fe_u2_imag),
        .o_item_last(fe_item_last), .o_frame_done(fe_frame_done),
        .o_overflow(fe_overflow), .o_channel_error(fe_channel_error)
    );

    // 把内部三个"没人看"的异常标志接到端口上，供测量核心写进快照 validity 字。
    assign o_center_sat    = u1_center_sat | u2_center_sat;
    assign o_rfg_overflow  = fe_overflow;
    assign o_fifo_overflow = fifo_u1_ovf | fifo_u2_ovf;

    wire        sc_bin_valid, sc_bin_ready, sc_bin_last;
    wire [10:0] sc_bin_index;
    wire signed [15:0] sc_u1_real, sc_u1_imag, sc_u2_real, sc_u2_imag;

    pqm_rfg_scale #(
        .C_K(C_K), .SHIFT(SHIFT)
    ) u_scale (
        .clk(clk), .rst_n(rst_n), .i_start(start_pulse),
        .i_item_valid(fe_item_valid), .o_item_ready(fe_item_ready),
        .i_order(fe_order),
        .i_u1_real(fe_u1_real), .i_u1_imag(fe_u1_imag),
        .i_u2_real(fe_u2_real), .i_u2_imag(fe_u2_imag),
        .i_item_last(fe_item_last),
        .m_bin_valid(sc_bin_valid), .m_bin_ready(sc_bin_ready),
        .m_bin_last(sc_bin_last), .m_bin_index(sc_bin_index),
        .m_u1_real(sc_u1_real), .m_u1_imag(sc_u1_imag),
        .m_u2_real(sc_u2_real), .m_u2_imag(sc_u2_imag),
        .o_frame_done()
    );

    // ---------------- 后级：与原顶层逐条一致 ----------------
    wire        mag_valid, mag_last, harm_stats_s_mag_ready;
    wire [10:0] mag_bin_index;
    wire signed [15:0] mag_u1_real, mag_u1_imag, mag_u2_real, mag_u2_imag;
    wire [32:0] mag_u1_mag_sq, mag_u2_mag_sq;
    wire [16:0] mag_u1_mag, mag_u2_mag;
    wire        mag_busy, mag_frame_done;
    wire [15:0] mag_frame_count;

    magnitude_calc u_magnitude_calc (
        .clk(clk), .rst_n(rst_n), .enable(enable),
        .s_bin_valid(sc_bin_valid), .s_bin_ready(sc_bin_ready),
        .s_bin_last(sc_bin_last), .s_bin_index(sc_bin_index),
        .s_u1_real(sc_u1_real), .s_u1_imag(sc_u1_imag),
        .s_u2_real(sc_u2_real), .s_u2_imag(sc_u2_imag),
        .m_mag_ready(harm_stats_s_mag_ready),
        .m_mag_valid(mag_valid), .m_mag_last(mag_last), .m_bin_index(mag_bin_index),
        .m_u1_real(mag_u1_real), .m_u1_imag(mag_u1_imag),
        .m_u2_real(mag_u2_real), .m_u2_imag(mag_u2_imag),
        .m_u1_mag_sq(mag_u1_mag_sq), .m_u1_mag(mag_u1_mag),
        .m_u2_mag_sq(mag_u2_mag_sq), .m_u2_mag(mag_u2_mag),
        .calc_busy(mag_busy), .mag_frame_done(mag_frame_done),
        .mag_frame_count(mag_frame_count)
    );

    wire        hs_valid, hs_ready, hs_last;
    wire [8:0]  hs_order;
    wire        hs_present;
    wire signed [15:0] hs_u1_real, hs_u1_imag, hs_u2_real, hs_u2_imag;
    wire [16:0] hs_u1_mag, hs_u2_mag;
    wire [15:0] hs_u1_pct, hs_u2_pct;
    wire        hs_stats_busy, hs_capture_done, hs_frame_done;
    wire [15:0] hs_frame_count;
    wire [31:0] hs_u1_total, hs_u2_total;

    harmonic_stats #(
        .FUND_BIN(HARMONIC_FUND_BIN)
    ) u_harmonic_stats (
        .clk(clk), .rst_n(rst_n), .enable(enable),
        .s_mag_valid(mag_valid), .s_mag_ready(harm_stats_s_mag_ready),
        .s_mag_last(mag_last), .s_bin_index(mag_bin_index),
        .s_u1_real(mag_u1_real), .s_u1_imag(mag_u1_imag),
        .s_u2_real(mag_u2_real), .s_u2_imag(mag_u2_imag),
        .s_u1_mag(mag_u1_mag), .s_u2_mag(mag_u2_mag),
        .m_harmonic_ready(hs_ready),
        .m_harmonic_valid(hs_valid), .m_harmonic_last(hs_last),
        .m_harmonic_order(hs_order), .m_harmonic_present(hs_present),
        .m_u1_real(hs_u1_real), .m_u1_imag(hs_u1_imag),
        .m_u2_real(hs_u2_real), .m_u2_imag(hs_u2_imag),
        .m_u1_mag(hs_u1_mag), .m_u2_mag(hs_u2_mag),
        .m_u1_pct_x100(hs_u1_pct), .m_u2_pct_x100(hs_u2_pct),
        .stats_busy(hs_stats_busy), .capture_frame_done(hs_capture_done),
        .harmonic_frame_done(hs_frame_done), .harmonic_frame_count(hs_frame_count),
        .u1_total_mag(hs_u1_total), .u2_total_mag(hs_u2_total)
    );

    wire        pv_valid, pv_ready, pv_last;
    wire [8:0]  pv_order;
    wire        pv_present;
    wire signed [15:0] pv_u1_real, pv_u1_imag, pv_u2_real, pv_u2_imag;
    wire [16:0] pv_u1_mag, pv_u2_mag;
    wire [15:0] pv_u1_pct, pv_u2_pct;
    wire        pv_vector_valid;
    wire signed [32:0] pv_dot, pv_cross;
    wire        pv_busy, pv_frame_done;
    wire [15:0] pv_frame_count;

    phase_vector_calc u_phase_vector_calc (
        .clk(clk), .rst_n(rst_n), .enable(enable),
        .s_harmonic_valid(hs_valid), .s_harmonic_ready(hs_ready),
        .s_harmonic_last(hs_last), .s_harmonic_order(hs_order),
        .s_harmonic_present(hs_present),
        .s_u1_real(hs_u1_real), .s_u1_imag(hs_u1_imag),
        .s_u2_real(hs_u2_real), .s_u2_imag(hs_u2_imag),
        .s_u1_mag(hs_u1_mag), .s_u2_mag(hs_u2_mag),
        .s_u1_pct_x100(hs_u1_pct), .s_u2_pct_x100(hs_u2_pct),
        .m_harmonic_ready(pv_ready),
        .m_harmonic_valid(pv_valid), .m_harmonic_last(pv_last),
        .m_harmonic_order(pv_order), .m_harmonic_present(pv_present),
        .m_u1_real(pv_u1_real), .m_u1_imag(pv_u1_imag),
        .m_u2_real(pv_u2_real), .m_u2_imag(pv_u2_imag),
        .m_u1_mag(pv_u1_mag), .m_u2_mag(pv_u2_mag),
        .m_u1_pct_x100(pv_u1_pct), .m_u2_pct_x100(pv_u2_pct),
        .m_phase_vector_valid(pv_vector_valid),
        .m_phase_dot(pv_dot), .m_phase_cross(pv_cross)
    );

    wire        lut_valid, lut_ready, lut_last;
    wire [8:0]  lut_order;
    wire        lut_present;
    wire signed [15:0] lut_u1_real, lut_u1_imag, lut_u2_real, lut_u2_imag;
    wire [16:0] lut_u1_mag, lut_u2_mag;
    wire [15:0] lut_u1_pct, lut_u2_pct;
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
        .s_u1_real(pv_u1_real), .s_u1_imag(pv_u1_imag),
        .s_u2_real(pv_u2_real), .s_u2_imag(pv_u2_imag),
        .s_u1_mag(pv_u1_mag), .s_u2_mag(pv_u2_mag),
        .s_u1_pct_x100(pv_u1_pct), .s_u2_pct_x100(pv_u2_pct),
        .s_phase_vector_valid(pv_vector_valid),
        .s_phase_dot(pv_dot), .s_phase_cross(pv_cross),
        .m_harmonic_ready(lut_ready),
        .m_harmonic_valid(lut_valid), .m_harmonic_last(lut_last),
        .m_harmonic_order(lut_order), .m_harmonic_present(lut_present),
        .m_u1_real(lut_u1_real), .m_u1_imag(lut_u1_imag),
        .m_u2_real(lut_u2_real), .m_u2_imag(lut_u2_imag),
        .m_u1_mag(lut_u1_mag), .m_u2_mag(lut_u2_mag),
        .m_u1_pct_x100(lut_u1_pct), .m_u2_pct_x100(lut_u2_pct),
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
        .s_u1_real(lut_u1_real), .s_u1_imag(lut_u1_imag),
        .s_u2_real(lut_u2_real), .s_u2_imag(lut_u2_imag),
        .s_u1_mag(lut_u1_mag), .s_u2_mag(lut_u2_mag),
        .s_u1_pct_x100(lut_u1_pct), .s_u2_pct_x100(lut_u2_pct),
        .s_phase_vector_valid(lut_vector_valid),
        .s_phase_dot(lut_dot), .s_phase_cross(lut_cross),
        .s_phase_diff_valid(lut_diff_valid),
        .s_phase_diff_deg_x100(lut_diff_deg),
        .m_harmonic_ready(i_harmonic_ready),
        .m_harmonic_valid(m_harmonic_valid), .m_harmonic_last(m_harmonic_last),
        .m_harmonic_order(m_harmonic_order), .m_harmonic_present(m_harmonic_present),
        .m_u1_real(m_u1_real), .m_u1_imag(m_u1_imag),
        .m_u2_real(m_u2_real), .m_u2_imag(m_u2_imag),
        .m_u1_mag(m_u1_mag), .m_u2_mag(m_u2_mag),
        .m_u1_pct_x100(m_u1_pct_x100), .m_u2_pct_x100(m_u2_pct_x100),
        .m_phase_vector_valid(m_phase_vector_valid),
        .m_phase_dot(m_phase_dot), .m_phase_cross(m_phase_cross),
        .m_phase_diff_valid(m_phase_diff_valid),
        .m_phase_diff_deg_x100(m_phase_diff_deg_x100),
        .filtered_frame_count(filtered_frame_count)
    );

    assign o_sample_ready = !fifo_u1_full && !fifo_u2_full;

endmodule
