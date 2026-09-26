`timescale 1ns / 1ps

/*
 * 模块: pqm_rfg_dc_sum
 * 功能:
 *   补出 RFG 没有的 0 次（直流）分量，且**标度与 RFG 的 bin 输出完全一致**，
 *   使下游的「占比 = mag*10000/total」可以把直流和 1~K 次谐波放在一起算。
 *
 * 标度依据（用 RFG 自带向量标定，见 pl/sim/RFG/README.md）：
 *   RFG 的 o_result_* 满足   output_q15 = 2 * (Q2.14 整数序列的原始 DFT 求和)
 *   实测佐证：
 *     冲激 16384（=1.0）           -> 所有 bin 输出 ≈ 32768 = 2*16384
 *     单音 A=3243 在 bin1          -> 2*3243*256 = 1660416，向量实测 1660457
 *   bin0 的 DFT 求和就是 Σx[n]（W^0 = 1），所以只需要
 *     o_dc_q15 = 2 * Σ (sample - zero_code)
 *   即 **一个 32 位加法器 + 一个寄存器 + 左移 1 位**，不需要除法器、ROM 或乘法器。
 *   （N=512 是 2 的幂，日后若要改成「均值」也只是右移 9 位。）
 *
 * 帧对齐：只在 RFG 真正接收样本的拍累加（i_sample_valid && i_sample_ready），
 * 并在 RFG 的 i_start 同拍清零，保证与 RFG 的一帧严格对齐；最后一个样本参与的
 * 结果同样要算进去（用组合的 acc_next 而不是 acc，避免整帧差一个样本）。
 *
 * 溢出：N 个 |x|<=2^15 的样本，和的绝对值 <= N*2^15 = 2^24，左移后 <= 2^25，
 *       32 位有符号足够，不做饱和。
 */

module pqm_rfg_dc_sum #(
    parameter integer C_N = 512                 // 帧长，必须与 RFG 的 C_N 一致
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               i_start,          // 与 RFG 的 i_start 同拍
    input  wire               i_sample_valid,   // 采样有效
    input  wire               i_sample_ready,   // RFG 能收（接 RFG 的 o_sample_ready）
    input  wire [15:0]        i_sample,         // 原始偏移二进制采样码
    input  wire [15:0]        i_zero_code,      // 零点码
    output reg  signed [31:0] o_dc_q15,         // 0 次分量，标度同 RFG 的 bin 输出
    output reg                o_dc_valid,       // 一帧累加完成脉冲
    output reg  [15:0]        o_frame_count
);

    // 与 fft_stream_adapter 的去直流写法保持一致：两路都零扩展到 17 位再相减，
    // 取低 16 位作为有符号 Q2.14 样本（交变成分默认不超过 ±32767）。
    wire signed [16:0] centered_diff = $signed({1'b0, i_sample}) - $signed({1'b0, i_zero_code});
    wire signed [15:0] centered      = centered_diff[15:0];
    wire signed [31:0] centered_ext  = {{16{centered[15]}}, centered};

    reg  signed [31:0] acc;
    reg  [15:0]        sample_cnt;

    wire               sample_fire = i_sample_valid && i_sample_ready;
    wire signed [31:0] acc_next    = acc + centered_ext;
    wire               last_sample = (sample_cnt == C_N[15:0] - 16'd1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc           <= 32'sd0;
            sample_cnt    <= 16'd0;
            o_dc_q15      <= 32'sd0;
            o_dc_valid    <= 1'b0;
            o_frame_count <= 16'd0;
        end else begin
            o_dc_valid <= 1'b0;

            if (i_start) begin
                // 与 RFG 的 i_start 同拍清零，保证同一帧边界
                acc        <= 32'sd0;
                sample_cnt <= 16'd0;
            end else if (sample_fire) begin
                acc <= acc_next;

                if (last_sample) begin
                    // 含最后一个样本：acc_next 左移 1 位即与 RFG 同标度
                    o_dc_q15      <= acc_next <<< 1;
                    o_dc_valid    <= 1'b1;
                    o_frame_count <= o_frame_count + 16'd1;
                    sample_cnt    <= 16'd0;
                end else begin
                    sample_cnt <= sample_cnt + 16'd1;
                end
            end
        end
    end

endmodule
