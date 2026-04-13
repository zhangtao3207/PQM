`timescale 1ns / 1ps

/*
 * 模块: AD7606_Parallel_DRIVER
 * 功能:
 *   AD7606 并行接口上层封装，输出各通道采样值和整帧数据。
 *
 * 输入:
 *   clk: 系统时钟。
 *   rst_n: 低有效复位信号。
 *   start: 启动一次采样或处理流程。
 *   soft_reset: 软复位脉冲。
 *   ad_busy: AD7606 BUSY 输入。
 *   ad_frstdata: AD7606 FRSTDATA 输入。
 *   ad_data: AD7606 并行数据总线。
 *
 * 输出:
 *   ad_reset: AD7606 RESET 输出。
 *   ad_convst: AD7606 CONVST 输出。
 *   ad_cs_n: AD7606 CS# 输出。
 *   ad_rd_n: AD7606 RD# 输出。
 *   ch1_data: 数据信号。
 *   ch2_data: 数据信号。
 *   ch3_data: 数据信号。
 *   ch4_data: 数据信号。
 *   ch5_data: 数据信号。
 *   ch6_data: 数据信号。
 *   ch7_data: 数据信号。
 *   ch8_data: 数据信号。
 *   data_frame: 8 通道采样拼接后的整帧数据。
 *   data_valid: 整帧数据有效脉冲。
 *   sample_active: 采样过程忙标志。
 *   timeout: 采样异常超时标志。
 *   ad_channal: 当前读出的 AD7606 通道号。
 *   ad_state: AD7606 控制状态机状态。
 */
module AD7606_Parallel_DRIVER (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire         soft_reset,
    input  wire         ad_busy,
    input  wire         ad_frstdata,
    input  wire [15:0]  ad_data,
    output wire         ad_reset,
    output wire         ad_convst,
    output wire         ad_cs_n,
    output wire         ad_rd_n,
    output reg  [15:0]  ch1_data,
    output reg  [15:0]  ch2_data,
    output reg  [15:0]  ch3_data,
    output reg  [15:0]  ch4_data,
    output reg  [15:0]  ch5_data,
    output reg  [15:0]  ch6_data,
    output reg  [15:0]  ch7_data,
    output reg  [15:0]  ch8_data,
    output reg  [127:0] data_frame,
    output reg          data_valid,
    output wire         sample_active,
    output wire         timeout,
    output wire [3:0]   ad_channal,
    output wire [2:0]   ad_state
);

wire [127:0] frame_raw;        // 底层控制器输出的整帧原始数据
wire         frame_valid_raw;  // 底层控制器输出的整帧有效脉冲



localparam integer RESET_HIGH_CYCLES   = 500;
localparam integer CONVST_LOW_CYCLES   = 20;
localparam integer RD_LOW_CYCLES       = 16;
localparam integer RD_HIGH_CYCLES      = 16;
localparam integer BUSY_TIMEOUT_CYCLES = 100000;

ad7606_parallel_ctrl #(
    .RESET_HIGH_CYCLES(RESET_HIGH_CYCLES),
    .CONVST_LOW_CYCLES(CONVST_LOW_CYCLES),
    .RD_LOW_CYCLES(RD_LOW_CYCLES),
    .RD_HIGH_CYCLES(RD_HIGH_CYCLES),
    .BUSY_TIMEOUT_CYCLES(BUSY_TIMEOUT_CYCLES)
) u_ad7606_parallel_ctrl (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .soft_reset(soft_reset),
    .busy_i(ad_busy),
    .frstdata_i(ad_frstdata),
    .data_i(ad_data),

    .reset_o(ad_reset),
    .convst_o(ad_convst),
    .cs_n_o(ad_cs_n),
    .rd_n_o(ad_rd_n),
    .data_frame_o(frame_raw),
    .data_valid_o(frame_valid_raw),
    .sample_active_o(sample_active),
    .timeout_o(timeout),
    .channel_o(ad_channal),
    .state_o(ad_state)
);

// 在 frame_valid_raw 拉高时锁存一整帧数据，供上层长期使用。
// 在每次整帧采样完成时锁存 8 路通道数据与整帧数据。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        {ch8_data, ch7_data, ch6_data, ch5_data,
         ch4_data, ch3_data, ch2_data, ch1_data} <= 128'd0;
        data_frame <= 128'd0;
        data_valid <= 1'b0;
    end else begin
        data_valid <= frame_valid_raw;

        if (frame_valid_raw) begin
            data_frame <= frame_raw;
            {ch8_data, ch7_data, ch6_data, ch5_data,
             ch4_data, ch3_data, ch2_data, ch1_data} <= frame_raw;
        end
    end
end

endmodule
