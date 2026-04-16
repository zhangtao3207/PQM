`timescale 1ns / 1ps

/*
 * 模块: fft_result_receiver
 * 功能:
 *   接收 xfft_0 回送的原始 FFT 结果流，并筛选出后续频域分析需要的正半谱频点。
 *   本模块只做握手、寄存、计数和频点范围筛选，不计算幅值、谐波或 THD。
 *
 * 输入:
 *   clk: FFT 结果流所在时钟，通常接 fft_clk。
 *   rst_n: 低有效复位信号。
 *   enable: 结果筛选使能，拉低时继续接收并丢弃输入流。
 *   s_fft_valid: 上游 FFT 结果有效标志。
 *   s_fft_last: 上游 FFT 原始帧尾标志。
 *   s_bin_index: 上游 FFT 当前频点索引。
 *   s_u_real: 电压通道当前频点实部。
 *   s_u_imag: 电压通道当前频点虚部。
 *   s_i_real: 电流通道当前频点实部。
 *   s_i_imag: 电流通道当前频点虚部。
 *   m_bin_ready: 下游频点结果接收就绪标志。
 *
 * 输出:
 *   s_fft_ready: 本模块对上游 FFT 结果流的接收就绪标志。
 *   m_bin_valid: 筛选后的频点结果有效标志。
 *   m_bin_last: 筛选后正半谱结果的最后一个频点标志。
 *   m_bin_index: 筛选后的频点索引。
 *   m_u_real: 筛选后的电压通道频点实部。
 *   m_u_imag: 筛选后的电压通道频点虚部。
 *   m_i_real: 筛选后的电流通道频点实部。
 *   m_i_imag: 筛选后的电流通道频点虚部。
 *   raw_frame_active: 当前正在接收一帧原始 FFT 结果。
 *   raw_frame_done: 已接收完整一帧原始 FFT 结果的单周期脉冲。
 *   selected_frame_done: 筛选后的正半谱结果已被下游取完的单周期脉冲。
 *   raw_bin_count: 当前原始帧内已接收的频点数量。
 *   selected_bin_count: 当前原始帧内已筛选的频点数量。
 *   last_frame_raw_bin_count: 上一完整原始帧接收到的频点数量。
 *   last_frame_selected_bin_count: 上一完整原始帧筛选出的频点数量。
 *   frame_count: 已完整接收的原始 FFT 帧计数。
 */
module fft_result_receiver #(
    parameter [10:0] FIRST_BIN = 11'd1,
    parameter [10:0] LAST_BIN  = 11'd1024
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               enable,
    input  wire               s_fft_valid,
    output wire               s_fft_ready,
    input  wire               s_fft_last,
    input  wire [10:0]        s_bin_index,
    input  wire signed [15:0] s_u_real,
    input  wire signed [15:0] s_u_imag,
    input  wire signed [15:0] s_i_real,
    input  wire signed [15:0] s_i_imag,
    input  wire               m_bin_ready,
    output wire               m_bin_valid,
    output wire               m_bin_last,
    output wire [10:0]        m_bin_index,
    output wire signed [15:0] m_u_real,
    output wire signed [15:0] m_u_imag,
    output wire signed [15:0] m_i_real,
    output wire signed [15:0] m_i_imag,
    output wire               raw_frame_active,
    output wire               raw_frame_done,
    output wire               selected_frame_done,
    output reg  [11:0]        raw_bin_count,
    output reg  [11:0]        selected_bin_count,
    output reg  [11:0]        last_frame_raw_bin_count,
    output reg  [11:0]        last_frame_selected_bin_count,
    output reg  [15:0]        frame_count
);

reg                m_bin_valid_reg;
reg                m_bin_last_reg;
reg [10:0]         m_bin_index_reg;
reg signed [15:0]  m_u_real_reg;
reg signed [15:0]  m_u_imag_reg;
reg signed [15:0]  m_i_real_reg;
reg signed [15:0]  m_i_imag_reg;
reg                raw_frame_active_reg;
reg                raw_frame_done_reg;
reg                selected_frame_done_reg;

wire               selected_input;
wire               output_can_accept;
wire               input_fire;
wire               selected_fire;
wire               output_fire;
wire               selected_last_input;
wire [11:0]        raw_bin_count_next;
wire [11:0]        selected_bin_count_next;

// 组合判断当前输入频点是否属于后续分析使用的正半谱范围。
assign selected_input =
    enable && (s_bin_index >= FIRST_BIN) && (s_bin_index <= LAST_BIN);
assign output_can_accept = !m_bin_valid_reg || m_bin_ready;
assign s_fft_ready       = !selected_input || output_can_accept;
assign input_fire        = s_fft_valid && s_fft_ready;
assign selected_fire     = input_fire && selected_input;
assign output_fire       = m_bin_valid_reg && m_bin_ready;
assign selected_last_input = selected_input && (s_bin_index == LAST_BIN);

// 组合生成当前帧计数的下一个状态，供帧尾统计锁存使用。
assign raw_bin_count_next =
    input_fire ? (raw_bin_count + 12'd1) : raw_bin_count;
assign selected_bin_count_next =
    selected_fire ? (selected_bin_count + 12'd1) : selected_bin_count;

// 对外导出筛选后的频点寄存流和帧状态。
assign m_bin_valid         = m_bin_valid_reg;
assign m_bin_last          = m_bin_last_reg;
assign m_bin_index         = m_bin_index_reg;
assign m_u_real            = m_u_real_reg;
assign m_u_imag            = m_u_imag_reg;
assign m_i_real            = m_i_real_reg;
assign m_i_imag            = m_i_imag_reg;
assign raw_frame_active    = raw_frame_active_reg;
assign raw_frame_done      = raw_frame_done_reg;
assign selected_frame_done = selected_frame_done_reg;

// 在 FFT 结果时钟域接收原始结果流，筛选出的频点用单级寄存器支持下游反压。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        m_bin_valid_reg              <= 1'b0;
        m_bin_last_reg               <= 1'b0;
        m_bin_index_reg              <= 11'd0;
        m_u_real_reg                 <= 16'sd0;
        m_u_imag_reg                 <= 16'sd0;
        m_i_real_reg                 <= 16'sd0;
        m_i_imag_reg                 <= 16'sd0;
        raw_frame_active_reg         <= 1'b0;
        raw_frame_done_reg           <= 1'b0;
        selected_frame_done_reg      <= 1'b0;
        raw_bin_count                <= 12'd0;
        selected_bin_count           <= 12'd0;
        last_frame_raw_bin_count     <= 12'd0;
        last_frame_selected_bin_count <= 12'd0;
        frame_count                  <= 16'd0;
    end else begin
        raw_frame_done_reg      <= 1'b0;
        selected_frame_done_reg <= 1'b0;

        if (output_fire)
            selected_frame_done_reg <= m_bin_last_reg;

        if (selected_fire) begin
            m_bin_valid_reg <= 1'b1;
            m_bin_last_reg  <= selected_last_input;
            m_bin_index_reg <= s_bin_index;
            m_u_real_reg    <= s_u_real;
            m_u_imag_reg    <= s_u_imag;
            m_i_real_reg    <= s_i_real;
            m_i_imag_reg    <= s_i_imag;
        end else if (output_fire) begin
            m_bin_valid_reg <= 1'b0;
            m_bin_last_reg  <= 1'b0;
        end

        if (input_fire) begin
            raw_frame_active_reg <= 1'b1;

            if (s_fft_last) begin
                raw_frame_active_reg          <= 1'b0;
                raw_frame_done_reg            <= 1'b1;
                last_frame_raw_bin_count      <= raw_bin_count_next;
                last_frame_selected_bin_count <= selected_bin_count_next;
                raw_bin_count                 <= 12'd0;
                selected_bin_count            <= 12'd0;
                frame_count                   <= frame_count + 16'd1;
            end else begin
                raw_bin_count      <= raw_bin_count_next;
                selected_bin_count <= selected_bin_count_next;
            end
        end
    end
end

endmodule
