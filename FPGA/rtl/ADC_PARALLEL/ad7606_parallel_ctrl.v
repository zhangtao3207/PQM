`timescale 1ns / 1ps

//==============================================================================
// Module Name: ad7606_parallel_ctrl
// Function:
//   CM2248/AD7606 并行接口底层控制器。
//   主要功能如下：
//   1. 上电后输出一次 RESET 脉冲；
//   2. 在收到 start 上升沿后输出一次 CONVST 触发转换；
//   3. 等待 BUSY 先拉高再拉低，确认 ADC 已完成本次转换；
//   4. 通过 CS# / RD# 依次读取 8 路 16bit 并行数据；
//   5. 使用物理 FRSTDATA 校验第 1 路读数窗口是否对齐；
//   6. 在 8 路数据全部读取完成后输出 data_valid_o 单拍脉冲。
//==============================================================================
/*
 * 详细说明：
 *   AD7606 并行接口底层时序控制器。收到 `start` 后，模块依次完成：
 *   RESET/CONVST/BUSY 等待/8 路并行读数，并利用 FRSTDATA 校验首通道
 *   是否对齐。
 */
module ad7606_parallel_ctrl #(
    parameter integer RESET_HIGH_CYCLES   = 500,
    parameter integer CONVST_LOW_CYCLES   = 20,
    parameter integer RD_LOW_CYCLES       = 16,
    parameter integer RD_HIGH_CYCLES      = 16,
    parameter integer BUSY_TIMEOUT_CYCLES = 100000
)(
    input  wire         clk,              // 控制状态机工作时钟
    input  wire         rst_n,            // 低有效总复位
    input  wire         start,            // 启动一次采样流程的脉冲
    input  wire         soft_reset,       // 软件复位脉冲
    input  wire         busy_i,           // ADC BUSY 输入
    input  wire         frstdata_i,       // ADC FRSTDATA 输入，用于首通道对齐校验
    input  wire [15:0]  data_i,           // ADC 并行数据总线 DB[15:0]

    output reg          reset_o,          // 输出到 ADC 的 RESET，高有效
    output reg          convst_o,         // 输出到 ADC 的 CONVST
    output reg          cs_n_o,           // 输出到 ADC 的 CS#，低有效
    output reg          rd_n_o,           // 输出到 ADC 的 RD#，低有效
    output reg [127:0]  data_frame_o,     // 8 路拼接后的完整数据帧
    output reg          data_valid_o,     // 数据帧有效脉冲，仅拉高 1 拍
    output reg          sample_active_o,  // 采样流程忙标志
    output reg          timeout_o,        // BUSY 或 FRSTDATA 对齐异常标志
    output wire [3:0]   channel_o,        // 当前正在读取的通道号，范围 1~8；空闲时为 0
    output wire [2:0]   state_o           // 当前状态机状态编码
);

// 状态机编码。
localparam [2:0] ST_RESET          = 3'd0;
localparam [2:0] ST_IDLE           = 3'd1;
localparam [2:0] ST_CONV_LOW       = 3'd2;
localparam [2:0] ST_WAIT_BUSY_HIGH = 3'd3;
localparam [2:0] ST_WAIT_BUSY_LOW  = 3'd4;
localparam [2:0] ST_RD_LOW         = 3'd5;
localparam [2:0] ST_RD_HIGH        = 3'd6;

reg [2:0]  state;          // 状态机当前状态
reg [2:0]  channel_index;  // 当前读取到的通道索引，范围 0~7
reg [31:0] counter;        // 通用延时计数器
reg        start_d;        // start 的延迟 1 拍值，用于检测上升沿
reg        soft_reset_d;   // soft_reset 的延迟 1 拍值，用于检测上升沿
reg        busy_meta;      // BUSY 双触发同步第 1 级
reg        busy_sync;      // BUSY 双触发同步第 2 级
reg        frstdata_meta;  // FRSTDATA 双触发同步第 1 级
reg        frstdata_sync;  // FRSTDATA 双触发同步第 2 级

wire start_rise;           // start 上升沿检测结果
wire soft_reset_rise;      // soft_reset 上升沿检测结果

// 将“保持 N 个周期”换算成计数器装载值。
// 把“保持 N 个时钟周期”换算成计数器装载值。
function [31:0] cycles_to_counter;
    input integer cycles;
    begin
        if (cycles > 1)
            cycles_to_counter = cycles - 1;
        else
            cycles_to_counter = 32'd0;
    end
endfunction

// 直接导出当前状态编码，供 ILA 调试。
assign state_o = state;

// 检测 start 和 soft_reset 的上升沿。
assign start_rise      = start & ~start_d;
assign soft_reset_rise = soft_reset & ~soft_reset_d;

// 在并行读数阶段导出当前通道号，空闲时输出 0。
assign channel_o = ((state == ST_RD_LOW) || (state == ST_RD_HIGH)) ?
                   ({1'b0, channel_index} + 4'd1) : 4'd0;

// 主状态机。
// 主状态机：描述一帧 AD7606 并行采样流程。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state           <= ST_RESET;
        channel_index   <= 3'd0;
        counter         <= cycles_to_counter(RESET_HIGH_CYCLES);
        start_d         <= 1'b0;
        soft_reset_d    <= 1'b0;
        busy_meta       <= 1'b0;
        busy_sync       <= 1'b0;
        frstdata_meta   <= 1'b0;
        frstdata_sync   <= 1'b0;
        reset_o         <= 1'b1;
        convst_o        <= 1'b1;
        cs_n_o          <= 1'b1;
        rd_n_o          <= 1'b1;
        data_frame_o    <= 128'd0;
        data_valid_o    <= 1'b0;
        sample_active_o <= 1'b1;
        timeout_o       <= 1'b0;
    end else begin
        // 同步外部异步输入，并产生单拍边沿检测参考值。
        start_d       <= start;
        soft_reset_d  <= soft_reset;
        busy_meta     <= busy_i;
        busy_sync     <= busy_meta;
        frstdata_meta <= frstdata_i;
        frstdata_sync <= frstdata_meta;

        // data_valid_o 只在一整帧读完时拉高 1 拍。
        data_valid_o <= 1'b0;

        // 软件复位优先级高于普通采样流程。
        if (soft_reset_rise) begin
            state           <= ST_RESET;
            channel_index   <= 3'd0;
            counter         <= cycles_to_counter(RESET_HIGH_CYCLES);
            reset_o         <= 1'b1;
            convst_o        <= 1'b1;
            cs_n_o          <= 1'b1;
            rd_n_o          <= 1'b1;
            data_frame_o    <= 128'd0;
            sample_active_o <= 1'b1;
            timeout_o       <= 1'b0;
        end else begin
            case (state)
                // 输出 RESET 脉冲。
                ST_RESET: begin
                    reset_o         <= 1'b1;
                    convst_o        <= 1'b1;
                    cs_n_o          <= 1'b1;
                    rd_n_o          <= 1'b1;
                    sample_active_o <= 1'b1;
                    timeout_o       <= 1'b0;

                    if (counter == 0) begin
                        reset_o         <= 1'b0;
                        sample_active_o <= 1'b0;
                        state           <= ST_IDLE;
                    end else begin
                        counter <= counter - 1'b1;
                    end
                end

                // 空闲等待 start。
                ST_IDLE: begin
                    reset_o         <= 1'b0;
                    convst_o        <= 1'b1;
                    cs_n_o          <= 1'b1;
                    rd_n_o          <= 1'b1;
                    sample_active_o <= 1'b0;

                    if (start_rise) begin
                        timeout_o       <= 1'b0;
                        data_frame_o    <= 128'd0;
                        convst_o        <= 1'b0;
                        counter         <= cycles_to_counter(CONVST_LOW_CYCLES);
                        sample_active_o <= 1'b1;
                        state           <= ST_CONV_LOW;
                    end
                end

                // 拉低 CONVST 触发一次转换。
                ST_CONV_LOW: begin
                    convst_o <= 1'b0;

                    if (counter == 0) begin
                        convst_o <= 1'b1;
                        counter  <= cycles_to_counter(BUSY_TIMEOUT_CYCLES);
                        state    <= ST_WAIT_BUSY_HIGH;
                    end else begin
                        counter <= counter - 1'b1;
                    end
                end

                // 等待 BUSY 拉高，确认 ADC 开始转换。
                ST_WAIT_BUSY_HIGH: begin
                    convst_o <= 1'b1;
                    cs_n_o   <= 1'b1;
                    rd_n_o   <= 1'b1;

                    if (busy_sync) begin
                        counter <= cycles_to_counter(BUSY_TIMEOUT_CYCLES);
                        state   <= ST_WAIT_BUSY_LOW;
                    end else if (counter == 0) begin
                        timeout_o       <= 1'b1;
                        sample_active_o <= 1'b0;
                        state           <= ST_IDLE;
                    end else begin
                        counter <= counter - 1'b1;
                    end
                end

                // 等待 BUSY 拉低，确认 ADC 转换完成。
                ST_WAIT_BUSY_LOW: begin
                    cs_n_o <= 1'b1;
                    rd_n_o <= 1'b1;

                    if (!busy_sync) begin
                        cs_n_o        <= 1'b0;
                        channel_index <= 3'd0;
                        counter       <= cycles_to_counter(RD_LOW_CYCLES);
                        state         <= ST_RD_LOW;
                    end else if (counter == 0) begin
                        timeout_o       <= 1'b1;
                        sample_active_o <= 1'b0;
                        state           <= ST_IDLE;
                    end else begin
                        counter <= counter - 1'b1;
                    end
                end

                // 拉低 RD# 读取当前通道数据，并在读窗口末尾校验 FRSTDATA。
                ST_RD_LOW: begin
                    cs_n_o <= 1'b0;
                    rd_n_o <= 1'b0;

                    if (counter == 0) begin
                        // 第 1 路读窗口末尾必须看到 FRSTDATA=1；
                        // 第 2~8 路读窗口末尾必须看到 FRSTDATA=0。
                        if ((channel_index == 3'd0) && !frstdata_sync) begin
                            cs_n_o          <= 1'b1;
                            rd_n_o          <= 1'b1;
                            sample_active_o <= 1'b0;
                            timeout_o       <= 1'b1;
                            state           <= ST_IDLE;
                        end else if ((channel_index != 3'd0) && frstdata_sync) begin
                            cs_n_o          <= 1'b1;
                            rd_n_o          <= 1'b1;
                            sample_active_o <= 1'b0;
                            timeout_o       <= 1'b1;
                            state           <= ST_IDLE;
                        end else begin
                            data_frame_o[(channel_index * 16) +: 16] <= data_i;
                            rd_n_o  <= 1'b1;
                            counter <= cycles_to_counter(RD_HIGH_CYCLES);
                            state   <= ST_RD_HIGH;
                        end
                    end else begin
                        counter <= counter - 1'b1;
                    end
                end

                // 拉高 RD# 结束本通道读周期，并决定是否切换到下一通道。
                ST_RD_HIGH: begin
                    cs_n_o <= 1'b0;
                    rd_n_o <= 1'b1;

                    if (counter == 0) begin
                        if (channel_index == 3'd7) begin
                            cs_n_o          <= 1'b1;
                            data_valid_o    <= 1'b1;
                            sample_active_o <= 1'b0;
                            state           <= ST_IDLE;
                        end else begin
                            channel_index <= channel_index + 1'b1;
                            counter       <= cycles_to_counter(RD_LOW_CYCLES);
                            state         <= ST_RD_LOW;
                        end
                    end else begin
                        counter <= counter - 1'b1;
                    end
                end

                // 兜底状态，回到空闲安全电平。
                default: begin
                    state           <= ST_IDLE;
                    reset_o         <= 1'b0;
                    convst_o        <= 1'b1;
                    cs_n_o          <= 1'b1;
                    rd_n_o          <= 1'b1;
                    data_valid_o    <= 1'b0;
                    sample_active_o <= 1'b0;
                end
            endcase
        end
    end
end

endmodule
