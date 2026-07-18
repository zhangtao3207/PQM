`timescale 1ns / 1ps

/*
 * 模块: freq_text_x100_normalizer
 * 功能:
 *   对频域 raw 文本指标做 LCD 显示前的 x100 截幅和有效位传递。
 *   本模块串行处理各个字段，复用比较/截幅逻辑，避免并行展开造成 LUT 占用过高。
 * 输入:
 *   clk: 文本预处理工作时钟。
 *   rst_n: 低有效复位信号。
 *   start: 启动一次频域文本 x100 规整。
 *   thd_u_raw_x100: 电压 THD raw 值。
 *   thd_i_raw_x100: 电流 THD raw 值。
 *   thd_u_valid_in: 电压 THD raw 值有效标志。
 *   thd_i_valid_in: 电流 THD raw 值有效标志。
 *   u1_mag_raw_x100: 电压基波幅值占比 raw 值。
 *   i1_mag_raw_x100: 电流基波幅值占比 raw 值。
 *   u1_mag_valid_in: 电压基波幅值占比有效标志。
 *   i1_mag_valid_in: 电流基波幅值占比有效标志。
 *   phase1_raw_x100: 基波 U-I 相位差 raw 值。
 *   phase1_valid_in: 基波相位差有效标志。
 *   dc_u_raw_x100: 电压直流分量占比 raw 值。
 *   dc_i_raw_x100: 电流直流分量占比 raw 值。
 *   dc_u_valid_in: 电压直流分量有效标志。
 *   dc_i_valid_in: 电流直流分量有效标志。
 *   dh_order_u_raw: 电压主导谐波次数 raw 值。
 *   dh_order_i_raw: 电流主导谐波次数 raw 值。
 *   dh_order_u_valid_in: 电压主导谐波次数有效标志。
 *   dh_order_i_valid_in: 电流主导谐波次数有效标志。
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

localparam [3:0] IDX_THD_U      = 4'd0;
localparam [3:0] IDX_THD_I      = 4'd1;
localparam [3:0] IDX_U1_MAG     = 4'd2;
localparam [3:0] IDX_I1_MAG     = 4'd3;
localparam [3:0] IDX_PHASE1     = 4'd4;
localparam [3:0] IDX_DC_U       = 4'd5;
localparam [3:0] IDX_DC_I       = 4'd6;
localparam [3:0] IDX_DH_ORDER_U = 4'd7;
localparam [3:0] IDX_DH_ORDER_I = 4'd8;

reg       busy;
reg [3:0] item_index;

// 对百分比类显示值做统一截幅，避免异常 raw 值破坏文本显示范围。
function [31:0] clip_percent_x100;
    input [31:0] value_x100;
    begin
        clip_percent_x100 = (value_x100 > PERCENT_CLIP_X100) ? PERCENT_CLIP_X100 : value_x100;
    end
endfunction

// 对相位类显示值做统一截幅，限制在 LCD 文本可显示的角度范围内。
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

// 串行规整频域文本字段，复用同一组比较/截幅逻辑以降低 LUT 占用。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        busy               <= 1'b0;
        item_index         <= IDX_THD_U;
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

        if (start && !busy) begin
            busy       <= 1'b1;
            item_index <= IDX_THD_U;
        end else if (busy) begin
            case (item_index)
                IDX_THD_U: begin
                    thd_u_x100  <= clip_percent_x100(thd_u_raw_x100);
                    thd_u_valid <= thd_u_valid_in;
                    item_index  <= IDX_THD_I;
                end

                IDX_THD_I: begin
                    thd_i_x100  <= clip_percent_x100(thd_i_raw_x100);
                    thd_i_valid <= thd_i_valid_in;
                    item_index  <= IDX_U1_MAG;
                end

                IDX_U1_MAG: begin
                    u1_mag_x100  <= clip_percent_x100(u1_mag_raw_x100);
                    u1_mag_valid <= u1_mag_valid_in;
                    item_index   <= IDX_I1_MAG;
                end

                IDX_I1_MAG: begin
                    i1_mag_x100  <= clip_percent_x100(i1_mag_raw_x100);
                    i1_mag_valid <= i1_mag_valid_in;
                    item_index   <= IDX_PHASE1;
                end

                IDX_PHASE1: begin
                    phase1_x100  <= clip_phase_x100(phase1_raw_x100);
                    phase1_valid <= phase1_valid_in;
                    item_index   <= IDX_DC_U;
                end

                IDX_DC_U: begin
                    dc_u_x100  <= clip_percent_x100(dc_u_raw_x100);
                    dc_u_valid <= dc_u_valid_in;
                    item_index <= IDX_DC_I;
                end

                IDX_DC_I: begin
                    dc_i_x100  <= clip_percent_x100(dc_i_raw_x100);
                    dc_i_valid <= dc_i_valid_in;
                    item_index <= IDX_DH_ORDER_U;
                end

                IDX_DH_ORDER_U: begin
                    dh_order_u       <= dh_order_u_raw;
                    dh_order_u_valid <= dh_order_u_valid_in;
                    item_index       <= IDX_DH_ORDER_I;
                end

                IDX_DH_ORDER_I: begin
                    dh_order_i       <= dh_order_i_raw;
                    dh_order_i_valid <= dh_order_i_valid_in;
                    busy             <= 1'b0;
                    done             <= 1'b1;
                end

                default: begin
                    busy       <= 1'b0;
                    item_index <= IDX_THD_U;
                end
            endcase
        end
    end
end

endmodule
