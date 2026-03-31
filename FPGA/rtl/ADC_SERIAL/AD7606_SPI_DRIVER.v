`timescale 1ns / 1ps

module AD7606_SPI_DRIVER #(
    parameter integer RESET_HIGH_CYCLES   = 8,      // ADC RESET 保持高电平的时钟周期数
    parameter integer CONVST_LOW_CYCLES   = 4,      // CONVST 拉低保持的时钟周期数
    parameter integer SCLK_LOW_CYCLES     = 20,     // 串行时钟低电平保持的时钟周期数
    parameter integer SCLK_HIGH_CYCLES    = 20,     // 串行时钟高电平保持的时钟周期数
    parameter integer BUSY_TIMEOUT_CYCLES = 100000  // 等待 BUSY 拉高或拉低的超时周期数
)(
    input  wire        clk,           // 控制器工作时钟
    input  wire        rst_n,         // 低有效复位
    input  wire        start,         // 启动一次完整采样流程的触发脉冲
    input  wire        soft_reset,    // 软件复位触发脉冲
    input  wire [2:0]  os_mode,       // 过采样模式配置
    input  wire        range_sel,     // 量程选择配置
    input  wire        ad_busy,       // ADC BUSY 输入
    input  wire        ad_frstdata,   // ADC FRSTDATA 输入，用于首通道对齐校验
    input  wire        ad_sdata,      // ADC 串行数据输入
    output wire        ad_reset,      // 输出到 ADC 的 RESET 信号
    output wire        ad_convst,     // 输出到 ADC 的 CONVST 信号
    output wire        ad_cs_n,       // 输出到 ADC 的 CS# 信号
    output wire        ad_sclk,       // 输出到 ADC 的串行时钟
    output wire        ad_os0,        // 输出到 ADC 的 OS0 管脚
    output wire        ad_os1,        // 输出到 ADC 的 OS1 管脚
    output wire        ad_os2,        // 输出到 ADC 的 OS2 管脚
    output wire        ad_range,      // 输出到 ADC 的 RANGE 管脚
    output reg  [15:0] ch1_data,      // 第 1 通道采样结果
    output reg  [15:0] ch2_data,      // 第 2 通道采样结果
    output reg  [15:0] ch3_data,      // 第 3 通道采样结果
    output reg  [15:0] ch4_data,      // 第 4 通道采样结果
    output reg  [15:0] ch5_data,      // 第 5 通道采样结果
    output reg  [15:0] ch6_data,      // 第 6 通道采样结果
    output reg  [15:0] ch7_data,      // 第 7 通道采样结果
    output reg  [15:0] ch8_data,      // 第 8 通道采样结果
    output reg  [127:0] data_frame,   // 8 通道拼接后的 128bit 数据帧
    output reg         data_valid,    // 数据帧有效脉冲
    output wire        sample_active, // 采样流程忙标志
    output wire        timeout        // BUSY 等待超时标志
);

wire [2:0]   os_lines;        // 输出到 ADC OS 引脚的过采样模式控制信号
wire         range_line;      // 输出到 ADC RANGE 引脚的量程选择信号
wire [127:0] frame_raw;       // 底层串行控制器输出的原始 8 通道打包数据
wire         frame_valid_raw; // 底层串行控制器输出的数据有效脉冲

// 把底层控制器生成的 OS/RANGE 控制信号直接转接到模块输出端口
assign ad_os0   = os_lines[0]; // 输出 OS0 控制位
assign ad_os1   = os_lines[1]; // 输出 OS1 控制位
assign ad_os2   = os_lines[2]; // 输出 OS2 控制位
assign ad_range = range_line;  // 输出 RANGE 控制位

ad7606_serial_ctrl #(
    .RESET_HIGH_CYCLES(RESET_HIGH_CYCLES),
    .CONVST_LOW_CYCLES(CONVST_LOW_CYCLES),
    .SCLK_LOW_CYCLES(SCLK_LOW_CYCLES),
    .SCLK_HIGH_CYCLES(SCLK_HIGH_CYCLES),
    .BUSY_TIMEOUT_CYCLES(BUSY_TIMEOUT_CYCLES)
) u_ad7606_serial_ctrl (
    .clk(clk),
    .rst_n(rst_n),
    .start(start),
    .soft_reset(soft_reset),
    .os_mode(os_mode),
    .range_sel(range_sel),
    .busy_i(ad_busy),
    .frstdata_i(ad_frstdata),
    .sdata_i(ad_sdata),
    .os_o(os_lines),
    .range_o(range_line),
    .reset_o(ad_reset),
    .convst_o(ad_convst),
    .cs_n_o(ad_cs_n),
    .sclk_o(ad_sclk),
    .data_frame_o(frame_raw),
    .data_valid_o(frame_valid_raw),
    .sample_active_o(sample_active),
    .timeout_o(timeout)
);

// 当底层控制器给出一帧有效数据时，将 128bit 结果拆成 8 路 16bit 通道数据
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ch1_data   <= 16'd0;
        ch2_data   <= 16'd0;
        ch3_data   <= 16'd0;
        ch4_data   <= 16'd0;
        ch5_data   <= 16'd0;
        ch6_data   <= 16'd0;
        ch7_data   <= 16'd0;
        ch8_data   <= 16'd0;
        data_frame <= 128'd0;
        data_valid <= 1'b0;
    end else begin
        data_valid <= frame_valid_raw;

        if (frame_valid_raw) begin
            data_frame <= frame_raw;
            ch1_data   <= frame_raw[15:0];
            ch2_data   <= frame_raw[31:16];
            ch3_data   <= frame_raw[47:32];
            ch4_data   <= frame_raw[63:48];
            ch5_data   <= frame_raw[79:64];
            ch6_data   <= frame_raw[95:80];
            ch7_data   <= frame_raw[111:96];
            ch8_data   <= frame_raw[127:112];
        end
    end
end

endmodule
