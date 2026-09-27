`timescale 1ns / 1ps

/*
 * 模块: pqm_rfg_frontend
 * 功能:
 *   PQM2 频域前端的 RFG 版：U1/U2 各一个 RFG 实例 + 各一个直流累加器，
 *   合成为**一路按次数递增的顺序流**：先出 0 次（直流），再出 1..C_K 次。
 *
 *   为什么合成一路：
 *     - 原 FFT 链下游的 harmonic_stats 以「0 次」作为一帧的起点与累加器清零点
 *       （is_dc_order），把直流放在流首，这段已验证过的逻辑可以原样复用；
 *     - 下游需要的是每帧每个次数的 (u1_re,u1_im,u2_re,u2_im)，RFG 本身就给复数，
 *       所以这一路流直接就是后级要的形状。
 *
 *   为什么用两个实例而不是一个跑两遍：
 *     两个实例各自吃自己通道的样本流，**不需要任何输入帧缓存**，
 *     于是 data_fifo / blk_mem_gen_fft_fifo_ram 那个 IP 也可以一并去掉。
 *
 *   与 RFG 的握手：
 *     - i_start / i_sample_valid / i_sample_u1 / i_sample_u2 直接给两个实例；
 *     - 直流项未取走前，把两个实例的 i_result_ready 压住（o_item_ready=0），
 *       保证 0 次一定排在 1..K 之前；
 *     - 两个实例帧长与配置相同、result_ready 同源，所以输出严格同步；
 *       万一 bin 号不一致，o_channel_error 置起（自检用，正常恒 0）。
 */

module pqm_rfg_frontend #(
    parameter integer C_N = 512,        // 帧长（必须与 RFG 一致，且为 2 的幂）
    parameter integer C_K = 64,         // 谐波次数上限
    parameter integer C_L = 4,          // RFG 折叠长度
    parameter integer C_D = 1           // RFG 并行度
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               i_start,          // 与 RFG 的 i_start 同拍
    input  wire               i_sample_valid,
    input  wire [15:0]        i_sample_u1,       // U1通道原始偏移二进制码
    input  wire [15:0]        i_sample_u2,       // U2通道原始偏移二进制码
    input  wire [15:0]        i_zero_code,      // U1/U2 共用的零点码（PQM 两路同源）

    output wire               o_sample_ready,   // 两个 RFG 都能收才拉高

    output wire               o_item_valid,     // 顺序流：0 次 + 1..C_K 次
    input  wire               i_item_ready,     // 下游接收
    output wire [8:0]         o_order,          // 0..C_K
    output wire signed [31:0] o_u1_real,
    output wire signed [31:0] o_u1_imag,
    output wire signed [31:0] o_u2_real,
    output wire signed [31:0] o_u2_imag,
    output wire               o_item_last,      // 本帧最后一项（= C_K 次）
    output wire               o_frame_done,     // 本帧最后一项握手完成
    output wire               o_overflow,       // 任一通道 RFG 溢出粘滞
    output wire               o_channel_error   // 两通道 bin 号不一致（自检）
);

    // ---------------- 两个 RFG 实例 ----------------
    wire        u1_sample_ready, u2_sample_ready;
    wire        u1_result_valid, u2_result_valid;
    wire [8:0]  u1_bin_index,    u2_bin_index;
    wire signed [31:0] u1_result_real, u1_result_imag;
    wire signed [31:0] u2_result_real, u2_result_imag;
    wire        u1_result_last,  u2_result_last;
    wire        u1_frame_done,   u2_frame_done;
    wire        u1_overflow,     u2_overflow;
    wire        rfg_result_ready;

    e01_rfg_nkld_top #(
        .C_N(C_N), .C_K(C_K), .C_L(C_L), .C_D(C_D), .C_BACKEND(0)
    ) u_rfg_u1 (
        .sys_clk(clk), .rst_n(rst_n),
        .i_start(i_start), .i_sample_valid(i_sample_valid), .i_sample(i_sample_u1),
        .i_result_ready(rfg_result_ready),
        .o_sample_ready(u1_sample_ready), .o_busy(),
        .o_result_valid(u1_result_valid), .o_bin_index(u1_bin_index),
        .o_result_real(u1_result_real), .o_result_imag(u1_result_imag),
        .o_result_last(u1_result_last), .o_frame_done(u1_frame_done), .o_overflow(u1_overflow)
    );

    e01_rfg_nkld_top #(
        .C_N(C_N), .C_K(C_K), .C_L(C_L), .C_D(C_D), .C_BACKEND(0)
    ) u_rfg_u2 (
        .sys_clk(clk), .rst_n(rst_n),
        .i_start(i_start), .i_sample_valid(i_sample_valid), .i_sample(i_sample_u2),
        .i_result_ready(rfg_result_ready),
        .o_sample_ready(u2_sample_ready), .o_busy(),
        .o_result_valid(u2_result_valid), .o_bin_index(u2_bin_index),
        .o_result_real(u2_result_real), .o_result_imag(u2_result_imag),
        .o_result_last(u2_result_last), .o_frame_done(u2_frame_done), .o_overflow(u2_overflow)
    );

    // ---------------- 两个直流累加器 ----------------
    wire signed [31:0] u1_dc_q15, u2_dc_q15;
    wire               u1_dc_valid, u2_dc_valid;

    pqm_rfg_dc_sum #(.C_N(C_N)) u_dc_u1 (
        .clk(clk), .rst_n(rst_n), .i_start(i_start),
        .i_sample_valid(i_sample_valid), .i_sample_ready(u1_sample_ready),
        .i_sample(i_sample_u1), .i_zero_code(i_zero_code),
        .o_dc_q15(u1_dc_q15), .o_dc_valid(u1_dc_valid), .o_frame_count()
    );

    pqm_rfg_dc_sum #(.C_N(C_N)) u_dc_u2 (
        .clk(clk), .rst_n(rst_n), .i_start(i_start),
        .i_sample_valid(i_sample_valid), .i_sample_ready(u2_sample_ready),
        .i_sample(i_sample_u2), .i_zero_code(i_zero_code),
        .o_dc_q15(u2_dc_q15), .o_dc_valid(u2_dc_valid), .o_frame_count()
    );

    // ---------------- 0 次（直流）优先的合流 ----------------
    reg  dc_pending;      // 本帧的直流项已就绪、尚未被下游取走
    reg  dc_ready_seen;   // 本帧已经见过 dcv valid（避免重复入队）

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dc_pending    <= 1'b0;
            dc_ready_seen <= 1'b0;
        end else if (i_start) begin
            dc_pending    <= 1'b0;
            dc_ready_seen <= 1'b0;
        end else begin
            if (u1_dc_valid && u2_dc_valid && !dc_ready_seen) begin
                dc_pending    <= 1'b1;
                dc_ready_seen <= 1'b1;
            end
            if (dc_pending && o_item_valid && i_item_ready)   // 直流被取走
                dc_pending    <= 1'b0;
        end
    end

    // 直流未取走前压住 RFG 的结果通道，保证 0 次排在最前
    assign rfg_result_ready = i_item_ready && !dc_pending;

    // 输出：直流项 或 RFG 的结果项
    assign o_item_valid = dc_pending ? 1'b1 : (u1_result_valid && u2_result_valid);
    assign o_order      = dc_pending ? 9'd0 : u1_bin_index;
    assign o_u1_real     = dc_pending ? u1_dc_q15            : u1_result_real;
    assign o_u1_imag     = dc_pending ? 32'sd0              : u1_result_imag;
    assign o_u2_real     = dc_pending ? u2_dc_q15            : u2_result_real;
    assign o_u2_imag     = dc_pending ? 32'sd0              : u2_result_imag;
    assign o_item_last  = dc_pending ? 1'b0                : u1_result_last;

    assign o_sample_ready = u1_sample_ready && u2_sample_ready;
    assign o_overflow     = u1_overflow | u2_overflow;
    assign o_channel_error = (u1_result_valid && u2_result_valid && (u1_bin_index != u2_bin_index));

    // 末项握手完成即一帧结束
    reg frame_done_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)                      frame_done_reg <= 1'b0;
        else if (i_start)                frame_done_reg <= 1'b0;
        else if (o_item_valid && i_item_ready && o_item_last)
                                         frame_done_reg <= 1'b1;
    end
    assign o_frame_done = frame_done_reg;

endmodule
