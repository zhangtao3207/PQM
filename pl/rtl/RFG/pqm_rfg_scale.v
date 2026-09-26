`timescale 1ns / 1ps

/*
 * 模块: pqm_rfg_scale
 * 功能:
 *   把 pqm_rfg_frontend 的 32 位顺序流（0 次 + 1..C_K 次）缩放成
 *   **与 fft_result_receiver 输出形状完全一致**的 16 位频点流，从而让后续
 *   fft_magnitude_calc / fft_harmonic_stats / fft_phase_vector_calc /
 *   freq_harmonic_iir_filter / freq_metrics_raw_calc **原样复用**（都已验证过）。
 *
 * 为什么一次统一的右移就够了（这是等价性的依据）：
 *   两条链的输出都是"某个整体标度 × 真实频谱"，而下游要的全是比值与角度：
 *     占比 = mag*10000/total、THD = sqrt(Σ|X_h|²)/|X_1|、相位 = atan2(...)
 *   全部尺度无关。逐项核对：
 *     FFT ：直流 = A（=Σx/N，N=2048），基波 = A/2       -> 直/基 = 2
 *     RFG ：直流 = 2Σx（N=512），  基波 = 2·A·N/2 = A·N -> 直/基 = 2
 *   即 RFG 的直流与各次相对 FFT **同比例**，所以统一缩放不改变任何比值。
 *
 * 位宽与溢出（SHIFT=10）：
 *   RFG 的最大幅值出现在"满量程直流"：|DC| = 2·N·2^15 = 2^25（N=512）
 *     -> >>10 = 32768，恰好在 16 位有符号边界（±32767），最坏情况差 1 LSB；
 *   满量程单音：|X(1)| = 2^15·512 = 2^24 -> >>10 = 16384，余量充足。
 *   实机上零点跟踪会把直流压到很小，所以这个边界只在异常工况下才碰到。
 *   代价：小谐波的分辨率随之下降（1% 的谐波约剩 7~8 位有效），
 *   而对"百分比"这类比值量的影响约 0.01% 量级，可接受。
 *
 * 本模块是纯组合的（只有握手直通与一个帧尾锁存），不引入额外流水延迟。
 */

module pqm_rfg_scale #(
    parameter integer C_K   = 64,     // 谐波次数上限
    parameter integer SHIFT = 10      // 统一右移位数，见文件头
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               i_start,          // 与 RFG 的 i_start 同拍，用于清帧尾

    // 上游：pqm_rfg_frontend 的 32 位顺序流
    input  wire               i_item_valid,
    output wire               o_item_ready,
    input  wire [8:0]         i_order,
    input  wire signed [31:0] i_u_real,
    input  wire signed [31:0] i_u_imag,
    input  wire signed [31:0] i_i_real,
    input  wire signed [31:0] i_i_imag,
    input  wire               i_item_last,

    // 下游：与 fft_result_receiver 的输出同名同形
    output wire               m_bin_valid,
    input  wire               m_bin_ready,
    output wire               m_bin_last,
    output wire [10:0]        m_bin_index,
    output wire signed [15:0] m_u_real,
    output wire signed [15:0] m_u_imag,
    output wire signed [15:0] m_i_real,
    output wire signed [15:0] m_i_imag,
    output wire               o_frame_done
);

    assign m_bin_valid = i_item_valid;
    assign o_item_ready = m_bin_ready;
    assign m_bin_last   = i_item_last;
    assign m_bin_index  = {2'b00, i_order};

    // 算术右移保持符号；取低 16 位（溢出边界见文件头）
    assign m_u_real = (i_u_real >>> SHIFT);
    assign m_u_imag = (i_u_imag >>> SHIFT);
    assign m_i_real = (i_i_real >>> SHIFT);
    assign m_i_imag = (i_i_imag >>> SHIFT);

    // 末项握手完成即一帧结束
    reg frame_done_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)          frame_done_reg <= 1'b0;
        else if (i_start)    frame_done_reg <= 1'b0;
        else if (i_item_valid && m_bin_ready && i_item_last)
                             frame_done_reg <= 1'b1;
    end
    assign o_frame_done = frame_done_reg;

endmodule
