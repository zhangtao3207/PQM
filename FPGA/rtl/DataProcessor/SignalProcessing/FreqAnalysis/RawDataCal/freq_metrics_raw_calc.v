`timescale 1ns / 1ps

/*
 * 模块: freq_metrics_raw_calc
 * 功能:
 *   从一帧 0~500 次谐波结果流中提取频域右侧文本区需要的 raw 指标。
 *   本模块输出 THD、基波占比、基波相位、DC 占比，以及 U/I 各自按幅值降序排列的前五大谐波次数列表。
 *   DH 列表只统计 2~500 次有效谐波，列表中每项占 9 bit，顺序固定为第 1~第 5 大。
 * 输入:
 *   clk: 频域 raw 指标统计时钟。
 *   rst_n: 低有效复位。
 *   enable: 指标统计使能。
 *   s_harmonic_fire: 当前谐波结果被下游接收的单周期脉冲。
 *   s_harmonic_last: 当前谐波是否为本帧最后一项。
 *   s_harmonic_order: 当前谐波次数。
 *   s_harmonic_present: 当前谐波在本帧中是否有效。
 *   s_u_mag: 当前谐波电压幅值 raw。
 *   s_i_mag: 当前谐波电流幅值 raw。
 *   s_u_pct_x100: 当前谐波电压幅值占比，单位为 % x100。
 *   s_i_pct_x100: 当前谐波电流幅值占比，单位为 % x100。
 *   s_phase_diff_valid: 当前谐波 U-I 相位差是否有效。
 *   s_phase_diff_deg_x100: 当前谐波 U-I 相位差，单位为 deg x100。
 * 输出:
 *   raw_result_commit_toggle: 一帧 raw 指标提交后翻转一次。
 *   thd_u_raw_x100: 电压 THD raw，单位为 % x100。
 *   thd_i_raw_x100: 电流 THD raw，单位为 % x100。
 *   u1_mag_raw_x100: 电压基波占比 raw，单位为 % x100。
 *   i1_mag_raw_x100: 电流基波占比 raw，单位为 % x100。
 *   phase1_raw_x100: 基波 U-I 相位差 raw，单位为 deg x100。
 *   dc_u_raw_x100: 电压 DC 占比 raw，单位为 % x100。
 *   dc_i_raw_x100: 电流 DC 占比 raw，单位为 % x100。
 *   dh_order_u_list_raw: 电压前五大谐波次数列表，按幅值降序打包。
 *   dh_order_i_list_raw: 电流前五大谐波次数列表，按幅值降序打包。
 *   dh_order_u_count_raw: 电压列表中的有效项数量。
 *   dh_order_i_count_raw: 电流列表中的有效项数量。
 *   metrics_valid: 当前一帧 raw 指标是否已经提交。
 */
module freq_metrics_raw_calc (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               enable,
    input  wire               s_harmonic_fire,
    input  wire               s_harmonic_last,
    input  wire [8:0]         s_harmonic_order,
    input  wire               s_harmonic_present,
    input  wire [16:0]        s_u_mag,
    input  wire [16:0]        s_i_mag,
    input  wire [15:0]        s_u_pct_x100,
    input  wire [15:0]        s_i_pct_x100,
    input  wire               s_phase_diff_valid,
    input  wire signed [15:0] s_phase_diff_deg_x100,
    output reg                raw_result_commit_toggle,
    output reg  [31:0]        thd_u_raw_x100,
    output reg  [31:0]        thd_i_raw_x100,
    output reg                thd_u_valid,
    output reg                thd_i_valid,
    output reg  [31:0]        u1_mag_raw_x100,
    output reg  [31:0]        i1_mag_raw_x100,
    output reg                u1_mag_valid,
    output reg                i1_mag_valid,
    output reg  signed [31:0] phase1_raw_x100,
    output reg                phase1_valid,
    output reg  [31:0]        dc_u_raw_x100,
    output reg  [31:0]        dc_i_raw_x100,
    output reg                dc_u_valid,
    output reg                dc_i_valid,
    output reg                dh_order_u_valid,
    output reg                dh_order_i_valid,
    output reg  [44:0]        dh_order_u_list_raw,
    output reg  [44:0]        dh_order_i_list_raw,
    output reg  [2:0]         dh_order_u_count_raw,
    output reg  [2:0]         dh_order_i_count_raw,
    output reg                metrics_valid
);

reg        frame_end_pending;
reg [45:0] u_square_sum_work;
reg [45:0] i_square_sum_work;
reg [16:0] u_fund_mag_work;
reg [16:0] i_fund_mag_work;
reg        u_fund_valid_work;
reg        i_fund_valid_work;
reg [31:0] u1_mag_pending;
reg [31:0] i1_mag_pending;
reg        u1_mag_valid_pending;
reg        i1_mag_valid_pending;
reg signed [31:0] phase1_pending;
reg        phase1_valid_pending;
reg [31:0] dc_u_pending;
reg [31:0] dc_i_pending;
reg        dc_u_valid_pending;
reg        dc_i_valid_pending;
reg        thd_start;
reg [45:0] thd_u_square_sum_req;
reg [45:0] thd_i_square_sum_req;
reg [16:0] thd_u_fund_mag_req;
reg [16:0] thd_i_fund_mag_req;
reg        thd_u_fund_valid_req;
reg        thd_i_fund_valid_req;
reg [31:0] u1_mag_result_req;
reg [31:0] i1_mag_result_req;
reg        u1_mag_valid_result_req;
reg        i1_mag_valid_result_req;
reg signed [31:0] phase1_result_req;
reg        phase1_valid_result_req;
reg [31:0] dc_u_result_req;
reg [31:0] dc_i_result_req;
reg        dc_u_valid_result_req;
reg        dc_i_valid_result_req;
reg        dh_order_u_valid_result_req;
reg        dh_order_i_valid_result_req;
reg [44:0] dh_order_u_list_result_req;
reg [44:0] dh_order_i_list_result_req;
reg [2:0]  dh_order_u_count_result_req;
reg [2:0]  dh_order_i_count_result_req;

reg [16:0] dh_u_mag_work;
reg [16:0] dh_u_mag2_work;
reg [16:0] dh_u_mag3_work;
reg [16:0] dh_u_mag4_work;
reg [16:0] dh_u_mag5_work;
reg [8:0]  dh_u_order_work;
reg [8:0]  dh_u_order2_work;
reg [8:0]  dh_u_order3_work;
reg [8:0]  dh_u_order4_work;
reg [8:0]  dh_u_order5_work;
reg        dh_u_valid_work;
reg        dh_u_valid2_work;
reg        dh_u_valid3_work;
reg        dh_u_valid4_work;
reg        dh_u_valid5_work;

reg [16:0] dh_i_mag_work;
reg [16:0] dh_i_mag2_work;
reg [16:0] dh_i_mag3_work;
reg [16:0] dh_i_mag4_work;
reg [16:0] dh_i_mag5_work;
reg [8:0]  dh_i_order_work;
reg [8:0]  dh_i_order2_work;
reg [8:0]  dh_i_order3_work;
reg [8:0]  dh_i_order4_work;
reg [8:0]  dh_i_order5_work;
reg        dh_i_valid_work;
reg        dh_i_valid2_work;
reg        dh_i_valid3_work;
reg        dh_i_valid4_work;
reg        dh_i_valid5_work;

wire signed [17:0] u_mag_signed;
wire signed [17:0] i_mag_signed;
wire signed [35:0] u_mag_square_product;
wire signed [35:0] i_mag_square_product;
wire               is_dc_order;
wire               is_fund_order;
wire               is_distortion_order;
wire               thd_busy;
wire               thd_done;
wire [31:0]        thd_u_calc_x100;
wire [31:0]        thd_i_calc_x100;
wire               thd_u_calc_valid;
wire               thd_i_calc_valid;

assign u_mag_signed        = {1'b0, s_u_mag};
assign i_mag_signed        = {1'b0, s_i_mag};
assign is_dc_order         = (s_harmonic_order == 9'd0);
assign is_fund_order       = (s_harmonic_order == 9'd1);
assign is_distortion_order = s_harmonic_present && (s_harmonic_order >= 9'd2);

// 统计当前前五大列表中已经填入的有效项数量。
function [2:0] valid_count5;
    input valid1;
    input valid2;
    input valid3;
    input valid4;
    input valid5;
    begin
        if (valid5)
            valid_count5 = 3'd5;
        else if (valid4)
            valid_count5 = 3'd4;
        else if (valid3)
            valid_count5 = 3'd3;
        else if (valid2)
            valid_count5 = 3'd2;
        else if (valid1)
            valid_count5 = 3'd1;
        else
            valid_count5 = 3'd0;
    end
endfunction

// 把前五大谐波次数按固定顺序打包，供后级直接格式化为字符串。
function [44:0] pack_order_list5;
    input [8:0] order1;
    input [8:0] order2;
    input [8:0] order3;
    input [8:0] order4;
    input [8:0] order5;
    begin
        pack_order_list5 = {order1, order2, order3, order4, order5};
    end
endfunction

// 对当前谐波幅值平方，供 THD 的 2~500 次谐波平方和累加使用。
multiplier_signed #(
    .A_WIDTH(18),
    .B_WIDTH(18)
) u_u_mag_square_multiplier (
    .multiplicand(u_mag_signed),
    .multiplier  (u_mag_signed),
    .product     (u_mag_square_product)
);

// 对当前谐波幅值平方，供 THD 的 2~500 次谐波平方和累加使用。
multiplier_signed #(
    .A_WIDTH(18),
    .B_WIDTH(18)
) u_i_mag_square_multiplier (
    .multiplicand(i_mag_signed),
    .multiplier  (i_mag_signed),
    .product     (i_mag_square_product)
);

// 复用独立 THD raw 计算模块，保持统计和除法/开方流程解耦。
freq_thd_raw_calc u_freq_thd_raw_calc (
    .clk                  (clk),
    .rst_n                (rst_n),
    .start                (thd_start),
    .u_harmonic_square_sum(thd_u_square_sum_req),
    .i_harmonic_square_sum(thd_i_square_sum_req),
    .u_fund_mag           (thd_u_fund_mag_req),
    .i_fund_mag           (thd_i_fund_mag_req),
    .u_fund_valid         (thd_u_fund_valid_req),
    .i_fund_valid         (thd_i_fund_valid_req),
    .busy                 (thd_busy),
    .done                 (thd_done),
    .thd_u_raw_x100       (thd_u_calc_x100),
    .thd_i_raw_x100       (thd_i_calc_x100),
    .thd_u_valid          (thd_u_calc_valid),
    .thd_i_valid          (thd_i_calc_valid)
);

// 顺着谐波流累计一帧 raw 指标；帧尾延后一拍发起 THD 请求，确保最后一个谐波先写入统计寄存器。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        frame_end_pending          <= 1'b0;
        u_square_sum_work          <= 46'd0;
        i_square_sum_work          <= 46'd0;
        u_fund_mag_work            <= 17'd0;
        i_fund_mag_work            <= 17'd0;
        u_fund_valid_work          <= 1'b0;
        i_fund_valid_work          <= 1'b0;
        u1_mag_pending             <= 32'd0;
        i1_mag_pending             <= 32'd0;
        u1_mag_valid_pending       <= 1'b0;
        i1_mag_valid_pending       <= 1'b0;
        phase1_pending             <= 32'sd0;
        phase1_valid_pending       <= 1'b0;
        dc_u_pending               <= 32'd0;
        dc_i_pending               <= 32'd0;
        dc_u_valid_pending         <= 1'b0;
        dc_i_valid_pending         <= 1'b0;
        thd_start                  <= 1'b0;
        thd_u_square_sum_req       <= 46'd0;
        thd_i_square_sum_req       <= 46'd0;
        thd_u_fund_mag_req         <= 17'd0;
        thd_i_fund_mag_req         <= 17'd0;
        thd_u_fund_valid_req       <= 1'b0;
        thd_i_fund_valid_req       <= 1'b0;
        u1_mag_result_req          <= 32'd0;
        i1_mag_result_req          <= 32'd0;
        u1_mag_valid_result_req    <= 1'b0;
        i1_mag_valid_result_req    <= 1'b0;
        phase1_result_req          <= 32'sd0;
        phase1_valid_result_req    <= 1'b0;
        dc_u_result_req            <= 32'd0;
        dc_i_result_req            <= 32'd0;
        dc_u_valid_result_req      <= 1'b0;
        dc_i_valid_result_req      <= 1'b0;
        dh_order_u_valid_result_req<= 1'b0;
        dh_order_i_valid_result_req<= 1'b0;
        dh_order_u_list_result_req <= 45'd0;
        dh_order_i_list_result_req <= 45'd0;
        dh_order_u_count_result_req<= 3'd0;
        dh_order_i_count_result_req<= 3'd0;
        dh_u_mag_work              <= 17'd0;
        dh_u_mag2_work             <= 17'd0;
        dh_u_mag3_work             <= 17'd0;
        dh_u_mag4_work             <= 17'd0;
        dh_u_mag5_work             <= 17'd0;
        dh_u_order_work            <= 9'd0;
        dh_u_order2_work           <= 9'd0;
        dh_u_order3_work           <= 9'd0;
        dh_u_order4_work           <= 9'd0;
        dh_u_order5_work           <= 9'd0;
        dh_u_valid_work            <= 1'b0;
        dh_u_valid2_work           <= 1'b0;
        dh_u_valid3_work           <= 1'b0;
        dh_u_valid4_work           <= 1'b0;
        dh_u_valid5_work           <= 1'b0;
        dh_i_mag_work              <= 17'd0;
        dh_i_mag2_work             <= 17'd0;
        dh_i_mag3_work             <= 17'd0;
        dh_i_mag4_work             <= 17'd0;
        dh_i_mag5_work             <= 17'd0;
        dh_i_order_work            <= 9'd0;
        dh_i_order2_work           <= 9'd0;
        dh_i_order3_work           <= 9'd0;
        dh_i_order4_work           <= 9'd0;
        dh_i_order5_work           <= 9'd0;
        dh_i_valid_work            <= 1'b0;
        dh_i_valid2_work           <= 1'b0;
        dh_i_valid3_work           <= 1'b0;
        dh_i_valid4_work           <= 1'b0;
        dh_i_valid5_work           <= 1'b0;
        raw_result_commit_toggle   <= 1'b0;
        thd_u_raw_x100             <= 32'd0;
        thd_i_raw_x100             <= 32'd0;
        thd_u_valid                <= 1'b0;
        thd_i_valid                <= 1'b0;
        u1_mag_raw_x100            <= 32'd0;
        i1_mag_raw_x100            <= 32'd0;
        u1_mag_valid               <= 1'b0;
        i1_mag_valid               <= 1'b0;
        phase1_raw_x100            <= 32'sd0;
        phase1_valid               <= 1'b0;
        dc_u_raw_x100              <= 32'd0;
        dc_i_raw_x100              <= 32'd0;
        dc_u_valid                 <= 1'b0;
        dc_i_valid                 <= 1'b0;
        dh_order_u_valid           <= 1'b0;
        dh_order_i_valid           <= 1'b0;
        dh_order_u_list_raw        <= 45'd0;
        dh_order_i_list_raw        <= 45'd0;
        dh_order_u_count_raw       <= 3'd0;
        dh_order_i_count_raw       <= 3'd0;
        metrics_valid              <= 1'b0;
    end else begin
        thd_start <= 1'b0;

        if (!enable) begin
            frame_end_pending    <= 1'b0;
            u_square_sum_work    <= 46'd0;
            i_square_sum_work    <= 46'd0;
            u_fund_mag_work      <= 17'd0;
            i_fund_mag_work      <= 17'd0;
            u_fund_valid_work    <= 1'b0;
            i_fund_valid_work    <= 1'b0;
            u1_mag_pending       <= 32'd0;
            i1_mag_pending       <= 32'd0;
            u1_mag_valid_pending <= 1'b0;
            i1_mag_valid_pending <= 1'b0;
            phase1_pending       <= 32'sd0;
            phase1_valid_pending <= 1'b0;
            dc_u_pending         <= 32'd0;
            dc_i_pending         <= 32'd0;
            dc_u_valid_pending   <= 1'b0;
            dc_i_valid_pending   <= 1'b0;
            dh_u_mag_work        <= 17'd0;
            dh_u_mag2_work       <= 17'd0;
            dh_u_mag3_work       <= 17'd0;
            dh_u_mag4_work       <= 17'd0;
            dh_u_mag5_work       <= 17'd0;
            dh_u_order_work      <= 9'd0;
            dh_u_order2_work     <= 9'd0;
            dh_u_order3_work     <= 9'd0;
            dh_u_order4_work     <= 9'd0;
            dh_u_order5_work     <= 9'd0;
            dh_u_valid_work      <= 1'b0;
            dh_u_valid2_work     <= 1'b0;
            dh_u_valid3_work     <= 1'b0;
            dh_u_valid4_work     <= 1'b0;
            dh_u_valid5_work     <= 1'b0;
            dh_i_mag_work        <= 17'd0;
            dh_i_mag2_work       <= 17'd0;
            dh_i_mag3_work       <= 17'd0;
            dh_i_mag4_work       <= 17'd0;
            dh_i_mag5_work       <= 17'd0;
            dh_i_order_work      <= 9'd0;
            dh_i_order2_work     <= 9'd0;
            dh_i_order3_work     <= 9'd0;
            dh_i_order4_work     <= 9'd0;
            dh_i_order5_work     <= 9'd0;
            dh_i_valid_work      <= 1'b0;
            dh_i_valid2_work     <= 1'b0;
            dh_i_valid3_work     <= 1'b0;
            dh_i_valid4_work     <= 1'b0;
            dh_i_valid5_work     <= 1'b0;
            thd_u_valid          <= 1'b0;
            thd_i_valid          <= 1'b0;
            u1_mag_valid         <= 1'b0;
            i1_mag_valid         <= 1'b0;
            phase1_valid         <= 1'b0;
            dc_u_valid           <= 1'b0;
            dc_i_valid           <= 1'b0;
            dh_order_u_valid     <= 1'b0;
            dh_order_i_valid     <= 1'b0;
            dh_order_u_count_raw <= 3'd0;
            dh_order_i_count_raw <= 3'd0;
            metrics_valid        <= 1'b0;
        end else begin
            // 上一帧尾巴已经写入统计寄存器后，再启动 THD 计算，保证不会漏掉最后一个谐波。
            if (frame_end_pending && (thd_done || !thd_busy)) begin
                frame_end_pending           <= 1'b0;
                thd_start                   <= 1'b1;
                thd_u_square_sum_req        <= u_square_sum_work;
                thd_i_square_sum_req        <= i_square_sum_work;
                thd_u_fund_mag_req          <= u_fund_mag_work;
                thd_i_fund_mag_req          <= i_fund_mag_work;
                thd_u_fund_valid_req        <= u_fund_valid_work;
                thd_i_fund_valid_req        <= i_fund_valid_work;
                u1_mag_result_req           <= u1_mag_pending;
                i1_mag_result_req           <= i1_mag_pending;
                u1_mag_valid_result_req     <= u1_mag_valid_pending;
                i1_mag_valid_result_req     <= i1_mag_valid_pending;
                phase1_result_req           <= phase1_pending;
                phase1_valid_result_req     <= phase1_valid_pending;
                dc_u_result_req             <= dc_u_pending;
                dc_i_result_req             <= dc_i_pending;
                dc_u_valid_result_req       <= dc_u_valid_pending;
                dc_i_valid_result_req       <= dc_i_valid_pending;
                dh_order_u_valid_result_req <= dh_u_valid_work;
                dh_order_i_valid_result_req <= dh_i_valid_work;
                dh_order_u_list_result_req  <= pack_order_list5(
                                               dh_u_order_work,
                                               dh_u_order2_work,
                                               dh_u_order3_work,
                                               dh_u_order4_work,
                                               dh_u_order5_work
                                           );
                dh_order_i_list_result_req  <= pack_order_list5(
                                               dh_i_order_work,
                                               dh_i_order2_work,
                                               dh_i_order3_work,
                                               dh_i_order4_work,
                                               dh_i_order5_work
                                           );
                dh_order_u_count_result_req <= valid_count5(
                                               dh_u_valid_work,
                                               dh_u_valid2_work,
                                               dh_u_valid3_work,
                                               dh_u_valid4_work,
                                               dh_u_valid5_work
                                           );
                dh_order_i_count_result_req <= valid_count5(
                                               dh_i_valid_work,
                                               dh_i_valid2_work,
                                               dh_i_valid3_work,
                                               dh_i_valid4_work,
                                               dh_i_valid5_work
                                           );
            end

            // 跟随谐波流更新当前帧统计寄存器，DC 项同时承担新一帧清零和初始化职责。
            if (s_harmonic_fire) begin
                if (is_dc_order) begin
                    u_square_sum_work    <= 46'd0;
                    i_square_sum_work    <= 46'd0;
                    u_fund_mag_work      <= 17'd0;
                    i_fund_mag_work      <= 17'd0;
                    u_fund_valid_work    <= 1'b0;
                    i_fund_valid_work    <= 1'b0;
                    u1_mag_pending       <= 32'd0;
                    i1_mag_pending       <= 32'd0;
                    u1_mag_valid_pending <= 1'b0;
                    i1_mag_valid_pending <= 1'b0;
                    phase1_pending       <= 32'sd0;
                    phase1_valid_pending <= 1'b0;
                    dc_u_pending         <= s_harmonic_present ? {16'd0, s_u_pct_x100} : 32'd0;
                    dc_i_pending         <= s_harmonic_present ? {16'd0, s_i_pct_x100} : 32'd0;
                    dc_u_valid_pending   <= s_harmonic_present;
                    dc_i_valid_pending   <= s_harmonic_present;
                    dh_u_mag_work        <= 17'd0;
                    dh_u_mag2_work       <= 17'd0;
                    dh_u_mag3_work       <= 17'd0;
                    dh_u_mag4_work       <= 17'd0;
                    dh_u_mag5_work       <= 17'd0;
                    dh_u_order_work      <= 9'd0;
                    dh_u_order2_work     <= 9'd0;
                    dh_u_order3_work     <= 9'd0;
                    dh_u_order4_work     <= 9'd0;
                    dh_u_order5_work     <= 9'd0;
                    dh_u_valid_work      <= 1'b0;
                    dh_u_valid2_work     <= 1'b0;
                    dh_u_valid3_work     <= 1'b0;
                    dh_u_valid4_work     <= 1'b0;
                    dh_u_valid5_work     <= 1'b0;
                    dh_i_mag_work        <= 17'd0;
                    dh_i_mag2_work       <= 17'd0;
                    dh_i_mag3_work       <= 17'd0;
                    dh_i_mag4_work       <= 17'd0;
                    dh_i_mag5_work       <= 17'd0;
                    dh_i_order_work      <= 9'd0;
                    dh_i_order2_work     <= 9'd0;
                    dh_i_order3_work     <= 9'd0;
                    dh_i_order4_work     <= 9'd0;
                    dh_i_order5_work     <= 9'd0;
                    dh_i_valid_work      <= 1'b0;
                    dh_i_valid2_work     <= 1'b0;
                    dh_i_valid3_work     <= 1'b0;
                    dh_i_valid4_work     <= 1'b0;
                    dh_i_valid5_work     <= 1'b0;
                    metrics_valid        <= 1'b0;
                end else begin
                    if (is_distortion_order) begin
                        u_square_sum_work <= u_square_sum_work + {10'd0, u_mag_square_product[35:0]};
                        i_square_sum_work <= i_square_sum_work + {10'd0, i_mag_square_product[35:0]};
                    end

                    // 电压谐波列表使用插入排序保持前五大幅值始终按降序排列。
                    if (is_distortion_order && (s_u_mag != 17'd0)) begin
                        if (!dh_u_valid_work || (s_u_mag > dh_u_mag_work)) begin
                            dh_u_mag5_work   <= dh_u_mag4_work;
                            dh_u_order5_work <= dh_u_order4_work;
                            dh_u_valid5_work <= dh_u_valid4_work;
                            dh_u_mag4_work   <= dh_u_mag3_work;
                            dh_u_order4_work <= dh_u_order3_work;
                            dh_u_valid4_work <= dh_u_valid3_work;
                            dh_u_mag3_work   <= dh_u_mag2_work;
                            dh_u_order3_work <= dh_u_order2_work;
                            dh_u_valid3_work <= dh_u_valid2_work;
                            dh_u_mag2_work   <= dh_u_mag_work;
                            dh_u_order2_work <= dh_u_order_work;
                            dh_u_valid2_work <= dh_u_valid_work;
                            dh_u_mag_work    <= s_u_mag;
                            dh_u_order_work  <= s_harmonic_order;
                            dh_u_valid_work  <= 1'b1;
                        end else if (!dh_u_valid2_work || (s_u_mag > dh_u_mag2_work)) begin
                            dh_u_mag5_work   <= dh_u_mag4_work;
                            dh_u_order5_work <= dh_u_order4_work;
                            dh_u_valid5_work <= dh_u_valid4_work;
                            dh_u_mag4_work   <= dh_u_mag3_work;
                            dh_u_order4_work <= dh_u_order3_work;
                            dh_u_valid4_work <= dh_u_valid3_work;
                            dh_u_mag3_work   <= dh_u_mag2_work;
                            dh_u_order3_work <= dh_u_order2_work;
                            dh_u_valid3_work <= dh_u_valid2_work;
                            dh_u_mag2_work   <= s_u_mag;
                            dh_u_order2_work <= s_harmonic_order;
                            dh_u_valid2_work <= 1'b1;
                        end else if (!dh_u_valid3_work || (s_u_mag > dh_u_mag3_work)) begin
                            dh_u_mag5_work   <= dh_u_mag4_work;
                            dh_u_order5_work <= dh_u_order4_work;
                            dh_u_valid5_work <= dh_u_valid4_work;
                            dh_u_mag4_work   <= dh_u_mag3_work;
                            dh_u_order4_work <= dh_u_order3_work;
                            dh_u_valid4_work <= dh_u_valid3_work;
                            dh_u_mag3_work   <= s_u_mag;
                            dh_u_order3_work <= s_harmonic_order;
                            dh_u_valid3_work <= 1'b1;
                        end else if (!dh_u_valid4_work || (s_u_mag > dh_u_mag4_work)) begin
                            dh_u_mag5_work   <= dh_u_mag4_work;
                            dh_u_order5_work <= dh_u_order4_work;
                            dh_u_valid5_work <= dh_u_valid4_work;
                            dh_u_mag4_work   <= s_u_mag;
                            dh_u_order4_work <= s_harmonic_order;
                            dh_u_valid4_work <= 1'b1;
                        end else if (!dh_u_valid5_work || (s_u_mag > dh_u_mag5_work)) begin
                            dh_u_mag5_work   <= s_u_mag;
                            dh_u_order5_work <= s_harmonic_order;
                            dh_u_valid5_work <= 1'b1;
                        end
                    end

                    // 电流谐波列表独立维护前五大，口径与电压通道保持一致。
                    if (is_distortion_order && (s_i_mag != 17'd0)) begin
                        if (!dh_i_valid_work || (s_i_mag > dh_i_mag_work)) begin
                            dh_i_mag5_work   <= dh_i_mag4_work;
                            dh_i_order5_work <= dh_i_order4_work;
                            dh_i_valid5_work <= dh_i_valid4_work;
                            dh_i_mag4_work   <= dh_i_mag3_work;
                            dh_i_order4_work <= dh_i_order3_work;
                            dh_i_valid4_work <= dh_i_valid3_work;
                            dh_i_mag3_work   <= dh_i_mag2_work;
                            dh_i_order3_work <= dh_i_order2_work;
                            dh_i_valid3_work <= dh_i_valid2_work;
                            dh_i_mag2_work   <= dh_i_mag_work;
                            dh_i_order2_work <= dh_i_order_work;
                            dh_i_valid2_work <= dh_i_valid_work;
                            dh_i_mag_work    <= s_i_mag;
                            dh_i_order_work  <= s_harmonic_order;
                            dh_i_valid_work  <= 1'b1;
                        end else if (!dh_i_valid2_work || (s_i_mag > dh_i_mag2_work)) begin
                            dh_i_mag5_work   <= dh_i_mag4_work;
                            dh_i_order5_work <= dh_i_order4_work;
                            dh_i_valid5_work <= dh_i_valid4_work;
                            dh_i_mag4_work   <= dh_i_mag3_work;
                            dh_i_order4_work <= dh_i_order3_work;
                            dh_i_valid4_work <= dh_i_valid3_work;
                            dh_i_mag3_work   <= dh_i_mag2_work;
                            dh_i_order3_work <= dh_i_order2_work;
                            dh_i_valid3_work <= dh_i_valid2_work;
                            dh_i_mag2_work   <= s_i_mag;
                            dh_i_order2_work <= s_harmonic_order;
                            dh_i_valid2_work <= 1'b1;
                        end else if (!dh_i_valid3_work || (s_i_mag > dh_i_mag3_work)) begin
                            dh_i_mag5_work   <= dh_i_mag4_work;
                            dh_i_order5_work <= dh_i_order4_work;
                            dh_i_valid5_work <= dh_i_valid4_work;
                            dh_i_mag4_work   <= dh_i_mag3_work;
                            dh_i_order4_work <= dh_i_order3_work;
                            dh_i_valid4_work <= dh_i_valid3_work;
                            dh_i_mag3_work   <= s_i_mag;
                            dh_i_order3_work <= s_harmonic_order;
                            dh_i_valid3_work <= 1'b1;
                        end else if (!dh_i_valid4_work || (s_i_mag > dh_i_mag4_work)) begin
                            dh_i_mag5_work   <= dh_i_mag4_work;
                            dh_i_order5_work <= dh_i_order4_work;
                            dh_i_valid5_work <= dh_i_valid4_work;
                            dh_i_mag4_work   <= s_i_mag;
                            dh_i_order4_work <= s_harmonic_order;
                            dh_i_valid4_work <= 1'b1;
                        end else if (!dh_i_valid5_work || (s_i_mag > dh_i_mag5_work)) begin
                            dh_i_mag5_work   <= s_i_mag;
                            dh_i_order5_work <= s_harmonic_order;
                            dh_i_valid5_work <= 1'b1;
                        end
                    end
                end

                // 基波项单独保留，供 THD、幅值占比和相位文本复用。
                if (is_fund_order) begin
                    u_fund_mag_work      <= s_u_mag;
                    i_fund_mag_work      <= s_i_mag;
                    u_fund_valid_work    <= s_harmonic_present && (s_u_mag != 17'd0);
                    i_fund_valid_work    <= s_harmonic_present && (s_i_mag != 17'd0);
                    u1_mag_pending       <= s_harmonic_present ? {16'd0, s_u_pct_x100} : 32'd0;
                    i1_mag_pending       <= s_harmonic_present ? {16'd0, s_i_pct_x100} : 32'd0;
                    u1_mag_valid_pending <= s_harmonic_present;
                    i1_mag_valid_pending <= s_harmonic_present;
                    phase1_pending       <= (s_harmonic_present && s_phase_diff_valid) ?
                                            {{16{s_phase_diff_deg_x100[15]}}, s_phase_diff_deg_x100} :
                                            32'sd0;
                    phase1_valid_pending <= s_harmonic_present && s_phase_diff_valid;
                end

                if (s_harmonic_last)
                    frame_end_pending <= 1'b1;
            end

            // THD 计算完成后统一提交一帧 raw 指标，并翻转 commit toggle 触发文本链更新。
            if (thd_done) begin
                thd_u_raw_x100         <= thd_u_calc_x100;
                thd_i_raw_x100         <= thd_i_calc_x100;
                thd_u_valid            <= thd_u_calc_valid;
                thd_i_valid            <= thd_i_calc_valid;
                u1_mag_raw_x100        <= u1_mag_result_req;
                i1_mag_raw_x100        <= i1_mag_result_req;
                u1_mag_valid           <= u1_mag_valid_result_req;
                i1_mag_valid           <= i1_mag_valid_result_req;
                phase1_raw_x100        <= phase1_result_req;
                phase1_valid           <= phase1_valid_result_req;
                dc_u_raw_x100          <= dc_u_result_req;
                dc_i_raw_x100          <= dc_i_result_req;
                dc_u_valid             <= dc_u_valid_result_req;
                dc_i_valid             <= dc_i_valid_result_req;
                dh_order_u_valid       <= dh_order_u_valid_result_req;
                dh_order_i_valid       <= dh_order_i_valid_result_req;
                dh_order_u_list_raw    <= dh_order_u_list_result_req;
                dh_order_i_list_raw    <= dh_order_i_list_result_req;
                dh_order_u_count_raw   <= dh_order_u_count_result_req;
                dh_order_i_count_raw   <= dh_order_i_count_result_req;
                metrics_valid          <= 1'b1;
                raw_result_commit_toggle <= ~raw_result_commit_toggle;
            end
        end
    end
end

endmodule
