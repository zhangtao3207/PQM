`timescale 1ns / 1ps

//==============================================================================
// Module Name: AD7606_Parallel_DRIVER
// Function:
//   CM2248/AD7606 并行模式上层封装。
//   当前版本固定：
//   1. OS = 3'd0；
//   2. RANGE = 1'b1。
//   模块对外提供 ADC 控制口、8 路通道数据、整帧数据以及调试状态信号。
//==============================================================================
/*
 * 详细说明：
 *   AD7606 并行接口上层封装。负责例化底层控制器，并把整帧 128bit 数据
 *   拆分成 8 路 16bit 通道数据，供后级电压/电流处理链使用。
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
