`timescale 1ns / 1ps

/*
 * 模块: mean_filter_decim8_runtime
 * 功能:
 *   对输入的 N 个 16bit 补码采样点执行长度为 8 的窗口均值滤波，
 *   每累计 8 个样本输出 1 个补码均值点，最终得到 N/8 个 16bit 输出样本。
 *
 * 使用约定:
 *   - frame_start 用于标记一帧新数据的开始
 *   - frame_start 之后应连续送入恰好 N 个 sample_valid 有效样本
 *   - N 由输入端口 sample_count_n 运行时给定，不使用参数固定
 *   - 为保证输出长度严格等于 N/8，要求 N 为 8 的整数倍
 *   - sample_out_valid 每 8 个输入样本拉高 1 拍
 *   - frame_done 在最后 1 个输出样本产生的同一拍拉高 1 拍
 *
 * 输入:
 *   clk: 模块工作时钟
 *   rst_n: 低有效复位
 *   frame_start: 启动一帧新的 N 点处理
 *   sample_count_n: 本帧输入样本数 N
 *   sample_valid: 输入样本有效标志
 *   sample_in: 输入的 16bit 补码原始采样值
 *
 * 输出:
 *   busy: 当前正在处理一帧 N 点数据
 *   sample_out_valid: 降采样输出有效脉冲
 *   sample_out: 8 点均值滤波后的 16bit 补码输出样本
 *   frame_done: 当前 N 点数据全部处理完成
 */
module mean_filter_decim8_runtime #(
    parameter integer DATA_WIDTH        = 16,
    parameter integer N_WIDTH           = 16,
    parameter integer WINDOW_LEN        = 8,
    parameter integer WINDOW_SHIFT      = 3
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  frame_start,
    input  wire [N_WIDTH-1:0]    sample_count_n,
    input  wire                  sample_valid,
    input  wire signed [DATA_WIDTH-1:0] sample_in,
    output reg                   busy,
    output reg                   sample_out_valid,
    output reg  signed [DATA_WIDTH-1:0] sample_out,
    output reg                   frame_done
);

// 8 点窗口求和至少需要扩展 3bit，避免均值前溢出
localparam integer SUM_WIDTH = DATA_WIDTH + WINDOW_SHIFT;
localparam signed [SUM_WIDTH-1:0] ROUND_POS_BIAS = 4;
localparam signed [SUM_WIDTH-1:0] ROUND_NEG_BIAS = 3;

// 输入样本计数、窗口计数、目标长度与补码累加值
reg [N_WIDTH-1:0]         sample_target;
reg [N_WIDTH-1:0]         sample_count;
reg [2:0]                 window_count;
reg signed [SUM_WIDTH-1:0] window_sum;
reg signed [SUM_WIDTH-1:0] window_sum_next;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        busy             <= 1'b0;
        sample_out_valid <= 1'b0;
        sample_out       <= {DATA_WIDTH{1'b0}};
        frame_done       <= 1'b0;
        sample_target    <= {N_WIDTH{1'b0}};
        sample_count     <= {N_WIDTH{1'b0}};
        window_count     <= 3'd0;
        window_sum       <= {SUM_WIDTH{1'b0}};
    end else begin
        // 有效输出与帧完成均为单拍脉冲，默认先拉低
        sample_out_valid <= 1'b0;
        frame_done       <= 1'b0;

        if (frame_start) begin
            // 启动一帧新的 N 点处理，并清空窗口累加状态
            sample_target<= sample_count_n;
            sample_count <= {N_WIDTH{1'b0}};
            window_count <= 3'd0;
            window_sum   <= {SUM_WIDTH{1'b0}};
            if (sample_count_n == {N_WIDTH{1'b0}}) begin
                busy       <= 1'b0;
                frame_done <= 1'b1;
            end else begin
                busy       <= 1'b1;
            end
        end else if (busy && sample_valid) begin
            // 输入样本按补码有符号数参与累加
            window_sum_next = window_sum + $signed(sample_in);

            if (window_count == (WINDOW_LEN - 1)) begin
                // 收到第 8 个样本后输出补码均值，正负数分别做对称舍入
                if (window_sum_next >= 0)
                    sample_out <= (window_sum_next + ROUND_POS_BIAS) >>> WINDOW_SHIFT;
                else
                    sample_out <= (window_sum_next + ROUND_NEG_BIAS) >>> WINDOW_SHIFT;
                sample_out_valid <= 1'b1;
                window_count     <= 3'd0;
                window_sum       <= {SUM_WIDTH{1'b0}};
            end else begin
                window_count <= window_count + 3'd1;
                window_sum   <= window_sum + $signed(sample_in);
            end

            if (sample_count == (sample_target - 1'b1)) begin
                // 第 N 个样本处理完成后结束本帧
                busy         <= 1'b0;
                frame_done   <= 1'b1;
                sample_count <= {N_WIDTH{1'b0}};
            end else begin
                sample_count <= sample_count + {{(N_WIDTH - 1){1'b0}}, 1'b1};
            end
        end
    end
end

endmodule
