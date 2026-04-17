`timescale 1ns / 1ps

/*
 * 模块: freq_text_x100_normalizer
 * 功能:
 *   对频域 raw 指标做 LCD 文本显示前的 x100 定点规整。
 *   当前 raw 指标已经由上游以百分比 x100 或角度 x100 给出，本模块负责统一截幅和有效位传递。
 * 输入:
 *   clk: 文本预处理工作时钟。
 *   rst_n: 低有效复位信号。
 *   start: 启动一次频域文本 x100 规整。
 *   thd_u_raw_x100: 电压 THD raw 值。
 *   thd_i_raw_x100: 电流 THD raw 值。
 *   u1_mag_raw_x100: 电压基波幅值占比 raw 值。
 *   i1_mag_raw_x100: 电流基波幅值占比 raw 值。
 *   phase1_raw_x100: 基波相位差 raw 值。
 *   dc_u_raw_x100: 电压直流分量占比 raw 值。
 *   dc_i_raw_x100: 电流直流分量占比 raw 值。
 *   dh_order_u_raw: 电压主导谐波次数 raw 值。
 *   dh_order_i_raw: 电流主导谐波次数 raw 值。
 *   各 valid 输入: 对应 raw 指标是否有效。
 * 输出:
 *   done: 本次 x100 规整完成脉冲。
 *   各 x100/order 输出: 规整后供数位拆分使用的数值。
 *   各 valid 输出: 对应显示数值是否有效。
 */
module freq_text_x100_normalizer (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               start,
    input  wire [31:0]        thd_u_raw_x100,
    input  wire [31:0]        thd_i_raw_x100,
    input  wire               thd_u_valid_in,
    input  wire               thd_i_valid_in,
    input  wire [31:0]        u1_mag_raw_x100,
    input  wire [31:0]        i1_mag_raw_x100,
    input  wire               u1_mag_valid_in,
    input  wire               i1_mag_valid_in,
    input  wire signed [31:0] phase1_raw_x100,
    input  wire               phase1_valid_in,
    input  wire [31:0]        dc_u_raw_x100,
    input  wire [31:0]        dc_i_raw_x100,
    input  wire               dc_u_valid_in,
    input  wire               dc_i_valid_in,
    input  wire [8:0]         dh_order_u_raw,
    input  wire [8:0]         dh_order_i_raw,
    input  wire               dh_order_u_valid_in,
    input  wire               dh_order_i_valid_in,
    output reg                done,
    output reg  [31:0]        thd_u_x100,
    output reg  [31:0]        thd_i_x100,
    output reg                thd_u_valid,
    output reg                thd_i_valid,
    output reg  [31:0]        u1_mag_x100,
    output reg  [31:0]        i1_mag_x100,
    output reg                u1_mag_valid,
    output reg                i1_mag_valid,
    output reg  signed [31:0] phase1_x100,
    output reg                phase1_valid,
    output reg  [31:0]        dc_u_x100,
    output reg  [31:0]        dc_i_x100,
    output reg                dc_u_valid,
    output reg                dc_i_valid,
    output reg  [8:0]         dh_order_u,
    output reg  [8:0]         dh_order_i,
    output reg                dh_order_u_valid,
    output reg                dh_order_i_valid
);

localparam [31:0]        PERCENT_CLIP_X100 = 32'd99999;
localparam signed [31:0] PHASE_POS_CLIP_X100 = 32'sd18000;
localparam signed [31:0] PHASE_NEG_CLIP_X100 = -32'sd18000;

// 对百分比类和相位类显示数值做统一截幅，避免异常 raw 值破坏文本显示范围。
function [31:0] clip_percent_x100;
    input [31:0] value_x100;
    begin
        clip_percent_x100 = (value_x100 > PERCENT_CLIP_X100) ? PERCENT_CLIP_X100 : value_x100;
    end
endfunction

function signed [31:0] clip_phase_x100;
    input signed [31:0] value_x100;
    begin
        if (value_x100 > PHASE_POS_CLIP_X100)
            clip_phase_x100 = PHASE_POS_CLIP_X100;
        else if (value_x100 < PHASE_NEG_CLIP_X100)
            clip_phase_x100 = PHASE_NEG_CLIP_X100;
        else
            clip_phase_x100 = value_x100;
    end
endfunction

// start 到来时一次性锁存规整后的 x100/order 结果。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        done               <= 1'b0;
        thd_u_x100         <= 32'd0;
        thd_i_x100         <= 32'd0;
        thd_u_valid        <= 1'b0;
        thd_i_valid        <= 1'b0;
        u1_mag_x100        <= 32'd0;
        i1_mag_x100        <= 32'd0;
        u1_mag_valid       <= 1'b0;
        i1_mag_valid       <= 1'b0;
        phase1_x100        <= 32'sd0;
        phase1_valid       <= 1'b0;
        dc_u_x100          <= 32'd0;
        dc_i_x100          <= 32'd0;
        dc_u_valid         <= 1'b0;
        dc_i_valid         <= 1'b0;
        dh_order_u         <= 9'd0;
        dh_order_i         <= 9'd0;
        dh_order_u_valid   <= 1'b0;
        dh_order_i_valid   <= 1'b0;
    end else begin
        done <= 1'b0;

        if (start) begin
            thd_u_x100       <= clip_percent_x100(thd_u_raw_x100);
            thd_i_x100       <= clip_percent_x100(thd_i_raw_x100);
            thd_u_valid      <= thd_u_valid_in;
            thd_i_valid      <= thd_i_valid_in;
            u1_mag_x100      <= clip_percent_x100(u1_mag_raw_x100);
            i1_mag_x100      <= clip_percent_x100(i1_mag_raw_x100);
            u1_mag_valid     <= u1_mag_valid_in;
            i1_mag_valid     <= i1_mag_valid_in;
            phase1_x100      <= clip_phase_x100(phase1_raw_x100);
            phase1_valid     <= phase1_valid_in;
            dc_u_x100        <= clip_percent_x100(dc_u_raw_x100);
            dc_i_x100        <= clip_percent_x100(dc_i_raw_x100);
            dc_u_valid       <= dc_u_valid_in;
            dc_i_valid       <= dc_i_valid_in;
            dh_order_u       <= dh_order_u_raw;
            dh_order_i       <= dh_order_i_raw;
            dh_order_u_valid <= dh_order_u_valid_in;
            dh_order_i_valid <= dh_order_i_valid_in;
            done             <= 1'b1;
        end
    end
end

endmodule
