`timescale 1ns / 1ps

/*
 * 模块: freq_metrics_raw_calc
 * 功能:
 *   从一帧 0~500 次谐波结果流中提取频域右侧文本区需要的 raw 指标。
 *   本模块输出 THD、基波占比、基波相位、DC 占比，以及 U1/U2 各自按幅值降序排列的前五大谐波次数列表。
 *   DH 列表只统计 2~500 次有效谐波，列表中每项占 9 bit，顺序固定为第 1~第 5 大。
 * 输入:
 *   clk: 频域 raw 指标统计时钟。
 *   rst_n: 低有效复位。
 *   enable: 指标统计使能。
 *   s_harmonic_fire: 当前谐波结果被下游接收的单周期脉冲。
 *   s_harmonic_last: 当前谐波是否为本帧最后一项。
 *   s_harmonic_order: 当前谐波次数。
 *   s_harmonic_present: 当前谐波在本帧中是否有效。
 *   s_u1_mag: 当前谐波U1幅值 raw。
 *   s_u2_mag: 当前谐波U2幅值 raw。
 *   s_u1_pct_x100: 当前谐波U1幅值占比，单位为 % x100。
 *   s_u2_pct_x100: 当前谐波U2幅值占比，单位为 % x100。
 *   s_phase_diff_valid: 当前谐波 U1-U2 相位差是否有效。
 *   s_phase_diff_deg_x100: 当前谐波 U1-U2 相位差，单位为 deg x100。
 * 输出:
 *   raw_result_commit_toggle: 一帧 raw 指标提交后翻转一次。
 *   thd_u1_raw_x100: U1 THD raw，单位为 % x100。
 *   thd_u2_raw_x100: U2 THD raw，单位为 % x100。
 *   u1_mag_raw_x100: U1基波占比 raw，单位为 % x100。
 *   u2_mag_raw_x100: U2基波占比 raw，单位为 % x100。
 *   phase1_raw_x100: 基波 U1-U2 相位差 raw，单位为 deg x100。
 *   dc_u1_raw_x100: U1 DC 占比 raw，单位为 % x100。
 *   dc_u2_raw_x100: U2 DC 占比 raw，单位为 % x100。
 *   dh_order_u1_list_raw: U1前五大谐波次数列表，按幅值降序打包。
 *   dh_order_u2_list_raw: U2前五大谐波次数列表，按幅值降序打包。
 *   dh_order_u1_count_raw: U1列表中的有效项数量。
 *   dh_order_u2_count_raw: U2列表中的有效项数量。
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
    input  wire [16:0]        s_u1_mag,
    input  wire [16:0]        s_u2_mag,
    input  wire [15:0]        s_u1_pct_x100,
    input  wire [15:0]        s_u2_pct_x100,
    input  wire               s_phase_diff_valid,
    input  wire signed [15:0] s_phase_diff_deg_x100,
    output reg                raw_result_commit_toggle,
    output reg  [31:0]        thd_u1_raw_x100,
    output reg  [31:0]        thd_u2_raw_x100,
    output reg                thd_u1_valid,
    output reg                thd_u2_valid,
    output reg  [31:0]        u1_mag_raw_x100,
    output reg  [31:0]        u2_mag_raw_x100,
    output reg                u1_mag_valid,
    output reg                u2_mag_valid,
    output reg  signed [31:0] phase1_raw_x100,
    output reg                phase1_valid,
    output reg  [31:0]        dc_u1_raw_x100,
    output reg  [31:0]        dc_u2_raw_x100,
    output reg                dc_u1_valid,
    output reg                dc_u2_valid,
    output reg                dh_order_u1_valid,
    output reg                dh_order_u2_valid,
    output reg  [44:0]        dh_order_u1_list_raw,
    output reg  [44:0]        dh_order_u2_list_raw,
    output reg  [2:0]         dh_order_u1_count_raw,
    output reg  [2:0]         dh_order_u2_count_raw,
    output reg                metrics_valid
);

reg        frame_end_pending;
// 异步复位累加器使用逻辑加法链，避免综合器把反馈路径折叠进 DSP48 形成时序环。
(* use_dsp = "no" *) reg [45:0] u1_square_sum_work;
(* use_dsp = "no" *) reg [45:0] u2_square_sum_work;
reg [16:0] u1_fund_mag_work;
reg [16:0] u2_fund_mag_work;
reg        u1_fund_valid_work;
reg        u2_fund_valid_work;
reg [31:0] u1_mag_pending;
reg [31:0] u2_mag_pending;
reg        u1_mag_valid_pending;
reg        u2_mag_valid_pending;
reg signed [31:0] phase1_pending;
reg        phase1_valid_pending;
reg [31:0] dc_u1_pending;
reg [31:0] dc_u2_pending;
reg        dc_u1_valid_pending;
reg        dc_u2_valid_pending;
reg        thd_start;
reg [45:0] thd_u1_square_sum_req;
reg [45:0] thd_u2_square_sum_req;
reg [16:0] thd_u1_fund_mag_req;
reg [16:0] thd_u2_fund_mag_req;
reg        thd_u1_fund_valid_req;
reg        thd_u2_fund_valid_req;
reg [31:0] u1_mag_result_req;
reg [31:0] u2_mag_result_req;
reg        u1_mag_valid_result_req;
reg        u2_mag_valid_result_req;
reg signed [31:0] phase1_result_req;
reg        phase1_valid_result_req;
reg [31:0] dc_u1_result_req;
reg [31:0] dc_u2_result_req;
reg        dc_u1_valid_result_req;
reg        dc_u2_valid_result_req;
reg        dh_order_u1_valid_result_req;
reg        dh_order_u2_valid_result_req;
reg [44:0] dh_order_u1_list_result_req;
reg [44:0] dh_order_u2_list_result_req;
reg [2:0]  dh_order_u1_count_result_req;
reg [2:0]  dh_order_u2_count_result_req;

reg [16:0] dh_u1_mag_work;
reg [16:0] dh_u1_mag2_work;
reg [16:0] dh_u1_mag3_work;
reg [16:0] dh_u1_mag4_work;
reg [16:0] dh_u1_mag5_work;
reg [8:0]  dh_u1_order_work;
reg [8:0]  dh_u1_order2_work;
reg [8:0]  dh_u1_order3_work;
reg [8:0]  dh_u1_order4_work;
reg [8:0]  dh_u1_order5_work;
reg        dh_u1_valid_work;
reg        dh_u1_valid2_work;
reg        dh_u1_valid3_work;
reg        dh_u1_valid4_work;
reg        dh_u1_valid5_work;

reg [16:0] dh_u2_mag_work;
reg [16:0] dh_u2_mag2_work;
reg [16:0] dh_u2_mag3_work;
reg [16:0] dh_u2_mag4_work;
reg [16:0] dh_u2_mag5_work;
reg [8:0]  dh_u2_order_work;
reg [8:0]  dh_u2_order2_work;
reg [8:0]  dh_u2_order3_work;
reg [8:0]  dh_u2_order4_work;
reg [8:0]  dh_u2_order5_work;
reg        dh_u2_valid_work;
reg        dh_u2_valid2_work;
reg        dh_u2_valid3_work;
reg        dh_u2_valid4_work;
reg        dh_u2_valid5_work;

wire signed [17:0] u1_mag_signed;
wire signed [17:0] u2_mag_signed;
wire signed [35:0] u1_mag_square_product;
wire signed [35:0] u2_mag_square_product;
wire               is_dc_order;
wire               is_fund_order;
wire               is_distortion_order;
wire               thd_busy;
wire               thd_done;
wire [31:0]        thd_u1_calc_x100;
wire [31:0]        thd_u2_calc_x100;
wire               thd_u1_calc_valid;
wire               thd_u2_calc_valid;

assign u1_mag_signed        = {1'b0, s_u1_mag};
assign u2_mag_signed        = {1'b0, s_u2_mag};
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
) u_u1_mag_square_multiplier (
    .multiplicand(u1_mag_signed),
    .multiplier  (u1_mag_signed),
    .product     (u1_mag_square_product)
);

// 对当前谐波幅值平方，供 THD 的 2~500 次谐波平方和累加使用。
multiplier_signed #(
    .A_WIDTH(18),
    .B_WIDTH(18)
) u_u2_mag_square_multiplier (
    .multiplicand(u2_mag_signed),
    .multiplier  (u2_mag_signed),
    .product     (u2_mag_square_product)
);

// 复用独立 THD raw 计算模块，保持统计和除法/开方流程解耦。
freq_thd_raw_calc u_freq_thd_raw_calc (
    .clk                  (clk),
    .rst_n                (rst_n),
    .start                (thd_start),
    .u1_harmonic_square_sum(thd_u1_square_sum_req),
    .u2_harmonic_square_sum(thd_u2_square_sum_req),
    .u1_fund_mag           (thd_u1_fund_mag_req),
    .u2_fund_mag           (thd_u2_fund_mag_req),
    .u1_fund_valid         (thd_u1_fund_valid_req),
    .u2_fund_valid         (thd_u2_fund_valid_req),
    .busy                 (thd_busy),
    .done                 (thd_done),
    .thd_u1_raw_x100       (thd_u1_calc_x100),
    .thd_u2_raw_x100       (thd_u2_calc_x100),
    .thd_u1_valid          (thd_u1_calc_valid),
    .thd_u2_valid          (thd_u2_calc_valid)
);

// 顺着谐波流累计一帧 raw 指标；帧尾延后一拍发起 THD 请求，确保最后一个谐波先写入统计寄存器。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        frame_end_pending          <= 1'b0;
        u1_square_sum_work          <= 46'd0;
        u2_square_sum_work          <= 46'd0;
        u1_fund_mag_work            <= 17'd0;
        u2_fund_mag_work            <= 17'd0;
        u1_fund_valid_work          <= 1'b0;
        u2_fund_valid_work          <= 1'b0;
        u1_mag_pending             <= 32'd0;
        u2_mag_pending             <= 32'd0;
        u1_mag_valid_pending       <= 1'b0;
        u2_mag_valid_pending       <= 1'b0;
        phase1_pending             <= 32'sd0;
        phase1_valid_pending       <= 1'b0;
        dc_u1_pending               <= 32'd0;
        dc_u2_pending               <= 32'd0;
        dc_u1_valid_pending         <= 1'b0;
        dc_u2_valid_pending         <= 1'b0;
        thd_start                  <= 1'b0;
        thd_u1_square_sum_req       <= 46'd0;
        thd_u2_square_sum_req       <= 46'd0;
        thd_u1_fund_mag_req         <= 17'd0;
        thd_u2_fund_mag_req         <= 17'd0;
        thd_u1_fund_valid_req       <= 1'b0;
        thd_u2_fund_valid_req       <= 1'b0;
        u1_mag_result_req          <= 32'd0;
        u2_mag_result_req          <= 32'd0;
        u1_mag_valid_result_req    <= 1'b0;
        u2_mag_valid_result_req    <= 1'b0;
        phase1_result_req          <= 32'sd0;
        phase1_valid_result_req    <= 1'b0;
        dc_u1_result_req            <= 32'd0;
        dc_u2_result_req            <= 32'd0;
        dc_u1_valid_result_req      <= 1'b0;
        dc_u2_valid_result_req      <= 1'b0;
        dh_order_u1_valid_result_req<= 1'b0;
        dh_order_u2_valid_result_req<= 1'b0;
        dh_order_u1_list_result_req <= 45'd0;
        dh_order_u2_list_result_req <= 45'd0;
        dh_order_u1_count_result_req<= 3'd0;
        dh_order_u2_count_result_req<= 3'd0;
        dh_u1_mag_work              <= 17'd0;
        dh_u1_mag2_work             <= 17'd0;
        dh_u1_mag3_work             <= 17'd0;
        dh_u1_mag4_work             <= 17'd0;
        dh_u1_mag5_work             <= 17'd0;
        dh_u1_order_work            <= 9'd0;
        dh_u1_order2_work           <= 9'd0;
        dh_u1_order3_work           <= 9'd0;
        dh_u1_order4_work           <= 9'd0;
        dh_u1_order5_work           <= 9'd0;
        dh_u1_valid_work            <= 1'b0;
        dh_u1_valid2_work           <= 1'b0;
        dh_u1_valid3_work           <= 1'b0;
        dh_u1_valid4_work           <= 1'b0;
        dh_u1_valid5_work           <= 1'b0;
        dh_u2_mag_work              <= 17'd0;
        dh_u2_mag2_work             <= 17'd0;
        dh_u2_mag3_work             <= 17'd0;
        dh_u2_mag4_work             <= 17'd0;
        dh_u2_mag5_work             <= 17'd0;
        dh_u2_order_work            <= 9'd0;
        dh_u2_order2_work           <= 9'd0;
        dh_u2_order3_work           <= 9'd0;
        dh_u2_order4_work           <= 9'd0;
        dh_u2_order5_work           <= 9'd0;
        dh_u2_valid_work            <= 1'b0;
        dh_u2_valid2_work           <= 1'b0;
        dh_u2_valid3_work           <= 1'b0;
        dh_u2_valid4_work           <= 1'b0;
        dh_u2_valid5_work           <= 1'b0;
        raw_result_commit_toggle   <= 1'b0;
        thd_u1_raw_x100             <= 32'd0;
        thd_u2_raw_x100             <= 32'd0;
        thd_u1_valid                <= 1'b0;
        thd_u2_valid                <= 1'b0;
        u1_mag_raw_x100            <= 32'd0;
        u2_mag_raw_x100            <= 32'd0;
        u1_mag_valid               <= 1'b0;
        u2_mag_valid               <= 1'b0;
        phase1_raw_x100            <= 32'sd0;
        phase1_valid               <= 1'b0;
        dc_u1_raw_x100              <= 32'd0;
        dc_u2_raw_x100              <= 32'd0;
        dc_u1_valid                 <= 1'b0;
        dc_u2_valid                 <= 1'b0;
        dh_order_u1_valid           <= 1'b0;
        dh_order_u2_valid           <= 1'b0;
        dh_order_u1_list_raw        <= 45'd0;
        dh_order_u2_list_raw        <= 45'd0;
        dh_order_u1_count_raw       <= 3'd0;
        dh_order_u2_count_raw       <= 3'd0;
        metrics_valid              <= 1'b0;
    end else begin
        thd_start <= 1'b0;

        if (!enable) begin
            frame_end_pending    <= 1'b0;
            u1_square_sum_work    <= 46'd0;
            u2_square_sum_work    <= 46'd0;
            u1_fund_mag_work      <= 17'd0;
            u2_fund_mag_work      <= 17'd0;
            u1_fund_valid_work    <= 1'b0;
            u2_fund_valid_work    <= 1'b0;
            u1_mag_pending       <= 32'd0;
            u2_mag_pending       <= 32'd0;
            u1_mag_valid_pending <= 1'b0;
            u2_mag_valid_pending <= 1'b0;
            phase1_pending       <= 32'sd0;
            phase1_valid_pending <= 1'b0;
            dc_u1_pending         <= 32'd0;
            dc_u2_pending         <= 32'd0;
            dc_u1_valid_pending   <= 1'b0;
            dc_u2_valid_pending   <= 1'b0;
            dh_u1_mag_work        <= 17'd0;
            dh_u1_mag2_work       <= 17'd0;
            dh_u1_mag3_work       <= 17'd0;
            dh_u1_mag4_work       <= 17'd0;
            dh_u1_mag5_work       <= 17'd0;
            dh_u1_order_work      <= 9'd0;
            dh_u1_order2_work     <= 9'd0;
            dh_u1_order3_work     <= 9'd0;
            dh_u1_order4_work     <= 9'd0;
            dh_u1_order5_work     <= 9'd0;
            dh_u1_valid_work      <= 1'b0;
            dh_u1_valid2_work     <= 1'b0;
            dh_u1_valid3_work     <= 1'b0;
            dh_u1_valid4_work     <= 1'b0;
            dh_u1_valid5_work     <= 1'b0;
            dh_u2_mag_work        <= 17'd0;
            dh_u2_mag2_work       <= 17'd0;
            dh_u2_mag3_work       <= 17'd0;
            dh_u2_mag4_work       <= 17'd0;
            dh_u2_mag5_work       <= 17'd0;
            dh_u2_order_work      <= 9'd0;
            dh_u2_order2_work     <= 9'd0;
            dh_u2_order3_work     <= 9'd0;
            dh_u2_order4_work     <= 9'd0;
            dh_u2_order5_work     <= 9'd0;
            dh_u2_valid_work      <= 1'b0;
            dh_u2_valid2_work     <= 1'b0;
            dh_u2_valid3_work     <= 1'b0;
            dh_u2_valid4_work     <= 1'b0;
            dh_u2_valid5_work     <= 1'b0;
            thd_u1_valid          <= 1'b0;
            thd_u2_valid          <= 1'b0;
            u1_mag_valid         <= 1'b0;
            u2_mag_valid         <= 1'b0;
            phase1_valid         <= 1'b0;
            dc_u1_valid           <= 1'b0;
            dc_u2_valid           <= 1'b0;
            dh_order_u1_valid     <= 1'b0;
            dh_order_u2_valid     <= 1'b0;
            dh_order_u1_count_raw <= 3'd0;
            dh_order_u2_count_raw <= 3'd0;
            metrics_valid        <= 1'b0;
        end else begin
            // 上一帧尾巴已经写入统计寄存器后，再启动 THD 计算，保证不会漏掉最后一个谐波。
            if (frame_end_pending && (thd_done || !thd_busy)) begin
                frame_end_pending           <= 1'b0;
                thd_start                   <= 1'b1;
                thd_u1_square_sum_req        <= u1_square_sum_work;
                thd_u2_square_sum_req        <= u2_square_sum_work;
                thd_u1_fund_mag_req          <= u1_fund_mag_work;
                thd_u2_fund_mag_req          <= u2_fund_mag_work;
                thd_u1_fund_valid_req        <= u1_fund_valid_work;
                thd_u2_fund_valid_req        <= u2_fund_valid_work;
                u1_mag_result_req           <= u1_mag_pending;
                u2_mag_result_req           <= u2_mag_pending;
                u1_mag_valid_result_req     <= u1_mag_valid_pending;
                u2_mag_valid_result_req     <= u2_mag_valid_pending;
                phase1_result_req           <= phase1_pending;
                phase1_valid_result_req     <= phase1_valid_pending;
                dc_u1_result_req             <= dc_u1_pending;
                dc_u2_result_req             <= dc_u2_pending;
                dc_u1_valid_result_req       <= dc_u1_valid_pending;
                dc_u2_valid_result_req       <= dc_u2_valid_pending;
                dh_order_u1_valid_result_req <= dh_u1_valid_work;
                dh_order_u2_valid_result_req <= dh_u2_valid_work;
                dh_order_u1_list_result_req  <= pack_order_list5(
                                               dh_u1_order_work,
                                               dh_u1_order2_work,
                                               dh_u1_order3_work,
                                               dh_u1_order4_work,
                                               dh_u1_order5_work
                                           );
                dh_order_u2_list_result_req  <= pack_order_list5(
                                               dh_u2_order_work,
                                               dh_u2_order2_work,
                                               dh_u2_order3_work,
                                               dh_u2_order4_work,
                                               dh_u2_order5_work
                                           );
                dh_order_u1_count_result_req <= valid_count5(
                                               dh_u1_valid_work,
                                               dh_u1_valid2_work,
                                               dh_u1_valid3_work,
                                               dh_u1_valid4_work,
                                               dh_u1_valid5_work
                                           );
                dh_order_u2_count_result_req <= valid_count5(
                                               dh_u2_valid_work,
                                               dh_u2_valid2_work,
                                               dh_u2_valid3_work,
                                               dh_u2_valid4_work,
                                               dh_u2_valid5_work
                                           );
            end

            // 跟随谐波流更新当前帧统计寄存器，DC 项同时承担新一帧清零和初始化职责。
            if (s_harmonic_fire) begin
                if (is_dc_order) begin
                    u1_square_sum_work    <= 46'd0;
                    u2_square_sum_work    <= 46'd0;
                    u1_fund_mag_work      <= 17'd0;
                    u2_fund_mag_work      <= 17'd0;
                    u1_fund_valid_work    <= 1'b0;
                    u2_fund_valid_work    <= 1'b0;
                    u1_mag_pending       <= 32'd0;
                    u2_mag_pending       <= 32'd0;
                    u1_mag_valid_pending <= 1'b0;
                    u2_mag_valid_pending <= 1'b0;
                    phase1_pending       <= 32'sd0;
                    phase1_valid_pending <= 1'b0;
                    dc_u1_pending         <= s_harmonic_present ? {16'd0, s_u1_pct_x100} : 32'd0;
                    dc_u2_pending         <= s_harmonic_present ? {16'd0, s_u2_pct_x100} : 32'd0;
                    dc_u1_valid_pending   <= s_harmonic_present;
                    dc_u2_valid_pending   <= s_harmonic_present;
                    dh_u1_mag_work        <= 17'd0;
                    dh_u1_mag2_work       <= 17'd0;
                    dh_u1_mag3_work       <= 17'd0;
                    dh_u1_mag4_work       <= 17'd0;
                    dh_u1_mag5_work       <= 17'd0;
                    dh_u1_order_work      <= 9'd0;
                    dh_u1_order2_work     <= 9'd0;
                    dh_u1_order3_work     <= 9'd0;
                    dh_u1_order4_work     <= 9'd0;
                    dh_u1_order5_work     <= 9'd0;
                    dh_u1_valid_work      <= 1'b0;
                    dh_u1_valid2_work     <= 1'b0;
                    dh_u1_valid3_work     <= 1'b0;
                    dh_u1_valid4_work     <= 1'b0;
                    dh_u1_valid5_work     <= 1'b0;
                    dh_u2_mag_work        <= 17'd0;
                    dh_u2_mag2_work       <= 17'd0;
                    dh_u2_mag3_work       <= 17'd0;
                    dh_u2_mag4_work       <= 17'd0;
                    dh_u2_mag5_work       <= 17'd0;
                    dh_u2_order_work      <= 9'd0;
                    dh_u2_order2_work     <= 9'd0;
                    dh_u2_order3_work     <= 9'd0;
                    dh_u2_order4_work     <= 9'd0;
                    dh_u2_order5_work     <= 9'd0;
                    dh_u2_valid_work      <= 1'b0;
                    dh_u2_valid2_work     <= 1'b0;
                    dh_u2_valid3_work     <= 1'b0;
                    dh_u2_valid4_work     <= 1'b0;
                    dh_u2_valid5_work     <= 1'b0;
                    metrics_valid        <= 1'b0;
                end else begin
                    if (is_distortion_order) begin
                        u1_square_sum_work <= u1_square_sum_work + {10'd0, u1_mag_square_product[35:0]};
                        u2_square_sum_work <= u2_square_sum_work + {10'd0, u2_mag_square_product[35:0]};
                    end

                    // U1谐波列表使用插入排序保持前五大幅值始终按降序排列。
                    if (is_distortion_order && (s_u1_mag != 17'd0)) begin
                        if (!dh_u1_valid_work || (s_u1_mag > dh_u1_mag_work)) begin
                            dh_u1_mag5_work   <= dh_u1_mag4_work;
                            dh_u1_order5_work <= dh_u1_order4_work;
                            dh_u1_valid5_work <= dh_u1_valid4_work;
                            dh_u1_mag4_work   <= dh_u1_mag3_work;
                            dh_u1_order4_work <= dh_u1_order3_work;
                            dh_u1_valid4_work <= dh_u1_valid3_work;
                            dh_u1_mag3_work   <= dh_u1_mag2_work;
                            dh_u1_order3_work <= dh_u1_order2_work;
                            dh_u1_valid3_work <= dh_u1_valid2_work;
                            dh_u1_mag2_work   <= dh_u1_mag_work;
                            dh_u1_order2_work <= dh_u1_order_work;
                            dh_u1_valid2_work <= dh_u1_valid_work;
                            dh_u1_mag_work    <= s_u1_mag;
                            dh_u1_order_work  <= s_harmonic_order;
                            dh_u1_valid_work  <= 1'b1;
                        end else if (!dh_u1_valid2_work || (s_u1_mag > dh_u1_mag2_work)) begin
                            dh_u1_mag5_work   <= dh_u1_mag4_work;
                            dh_u1_order5_work <= dh_u1_order4_work;
                            dh_u1_valid5_work <= dh_u1_valid4_work;
                            dh_u1_mag4_work   <= dh_u1_mag3_work;
                            dh_u1_order4_work <= dh_u1_order3_work;
                            dh_u1_valid4_work <= dh_u1_valid3_work;
                            dh_u1_mag3_work   <= dh_u1_mag2_work;
                            dh_u1_order3_work <= dh_u1_order2_work;
                            dh_u1_valid3_work <= dh_u1_valid2_work;
                            dh_u1_mag2_work   <= s_u1_mag;
                            dh_u1_order2_work <= s_harmonic_order;
                            dh_u1_valid2_work <= 1'b1;
                        end else if (!dh_u1_valid3_work || (s_u1_mag > dh_u1_mag3_work)) begin
                            dh_u1_mag5_work   <= dh_u1_mag4_work;
                            dh_u1_order5_work <= dh_u1_order4_work;
                            dh_u1_valid5_work <= dh_u1_valid4_work;
                            dh_u1_mag4_work   <= dh_u1_mag3_work;
                            dh_u1_order4_work <= dh_u1_order3_work;
                            dh_u1_valid4_work <= dh_u1_valid3_work;
                            dh_u1_mag3_work   <= s_u1_mag;
                            dh_u1_order3_work <= s_harmonic_order;
                            dh_u1_valid3_work <= 1'b1;
                        end else if (!dh_u1_valid4_work || (s_u1_mag > dh_u1_mag4_work)) begin
                            dh_u1_mag5_work   <= dh_u1_mag4_work;
                            dh_u1_order5_work <= dh_u1_order4_work;
                            dh_u1_valid5_work <= dh_u1_valid4_work;
                            dh_u1_mag4_work   <= s_u1_mag;
                            dh_u1_order4_work <= s_harmonic_order;
                            dh_u1_valid4_work <= 1'b1;
                        end else if (!dh_u1_valid5_work || (s_u1_mag > dh_u1_mag5_work)) begin
                            dh_u1_mag5_work   <= s_u1_mag;
                            dh_u1_order5_work <= s_harmonic_order;
                            dh_u1_valid5_work <= 1'b1;
                        end
                    end

                    // U2谐波列表独立维护前五大，口径与U1通道保持一致。
                    if (is_distortion_order && (s_u2_mag != 17'd0)) begin
                        if (!dh_u2_valid_work || (s_u2_mag > dh_u2_mag_work)) begin
                            dh_u2_mag5_work   <= dh_u2_mag4_work;
                            dh_u2_order5_work <= dh_u2_order4_work;
                            dh_u2_valid5_work <= dh_u2_valid4_work;
                            dh_u2_mag4_work   <= dh_u2_mag3_work;
                            dh_u2_order4_work <= dh_u2_order3_work;
                            dh_u2_valid4_work <= dh_u2_valid3_work;
                            dh_u2_mag3_work   <= dh_u2_mag2_work;
                            dh_u2_order3_work <= dh_u2_order2_work;
                            dh_u2_valid3_work <= dh_u2_valid2_work;
                            dh_u2_mag2_work   <= dh_u2_mag_work;
                            dh_u2_order2_work <= dh_u2_order_work;
                            dh_u2_valid2_work <= dh_u2_valid_work;
                            dh_u2_mag_work    <= s_u2_mag;
                            dh_u2_order_work  <= s_harmonic_order;
                            dh_u2_valid_work  <= 1'b1;
                        end else if (!dh_u2_valid2_work || (s_u2_mag > dh_u2_mag2_work)) begin
                            dh_u2_mag5_work   <= dh_u2_mag4_work;
                            dh_u2_order5_work <= dh_u2_order4_work;
                            dh_u2_valid5_work <= dh_u2_valid4_work;
                            dh_u2_mag4_work   <= dh_u2_mag3_work;
                            dh_u2_order4_work <= dh_u2_order3_work;
                            dh_u2_valid4_work <= dh_u2_valid3_work;
                            dh_u2_mag3_work   <= dh_u2_mag2_work;
                            dh_u2_order3_work <= dh_u2_order2_work;
                            dh_u2_valid3_work <= dh_u2_valid2_work;
                            dh_u2_mag2_work   <= s_u2_mag;
                            dh_u2_order2_work <= s_harmonic_order;
                            dh_u2_valid2_work <= 1'b1;
                        end else if (!dh_u2_valid3_work || (s_u2_mag > dh_u2_mag3_work)) begin
                            dh_u2_mag5_work   <= dh_u2_mag4_work;
                            dh_u2_order5_work <= dh_u2_order4_work;
                            dh_u2_valid5_work <= dh_u2_valid4_work;
                            dh_u2_mag4_work   <= dh_u2_mag3_work;
                            dh_u2_order4_work <= dh_u2_order3_work;
                            dh_u2_valid4_work <= dh_u2_valid3_work;
                            dh_u2_mag3_work   <= s_u2_mag;
                            dh_u2_order3_work <= s_harmonic_order;
                            dh_u2_valid3_work <= 1'b1;
                        end else if (!dh_u2_valid4_work || (s_u2_mag > dh_u2_mag4_work)) begin
                            dh_u2_mag5_work   <= dh_u2_mag4_work;
                            dh_u2_order5_work <= dh_u2_order4_work;
                            dh_u2_valid5_work <= dh_u2_valid4_work;
                            dh_u2_mag4_work   <= s_u2_mag;
                            dh_u2_order4_work <= s_harmonic_order;
                            dh_u2_valid4_work <= 1'b1;
                        end else if (!dh_u2_valid5_work || (s_u2_mag > dh_u2_mag5_work)) begin
                            dh_u2_mag5_work   <= s_u2_mag;
                            dh_u2_order5_work <= s_harmonic_order;
                            dh_u2_valid5_work <= 1'b1;
                        end
                    end
                end

                // 基波项单独保留，供 THD、幅值占比和相位文本复用。
                if (is_fund_order) begin
                    u1_fund_mag_work      <= s_u1_mag;
                    u2_fund_mag_work      <= s_u2_mag;
                    u1_fund_valid_work    <= s_harmonic_present && (s_u1_mag != 17'd0);
                    u2_fund_valid_work    <= s_harmonic_present && (s_u2_mag != 17'd0);
                    u1_mag_pending       <= s_harmonic_present ? {16'd0, s_u1_pct_x100} : 32'd0;
                    u2_mag_pending       <= s_harmonic_present ? {16'd0, s_u2_pct_x100} : 32'd0;
                    u1_mag_valid_pending <= s_harmonic_present;
                    u2_mag_valid_pending <= s_harmonic_present;
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
                thd_u1_raw_x100         <= thd_u1_calc_x100;
                thd_u2_raw_x100         <= thd_u2_calc_x100;
                thd_u1_valid            <= thd_u1_calc_valid;
                thd_u2_valid            <= thd_u2_calc_valid;
                u1_mag_raw_x100        <= u1_mag_result_req;
                u2_mag_raw_x100        <= u2_mag_result_req;
                u1_mag_valid           <= u1_mag_valid_result_req;
                u2_mag_valid           <= u2_mag_valid_result_req;
                phase1_raw_x100        <= phase1_result_req;
                phase1_valid           <= phase1_valid_result_req;
                dc_u1_raw_x100          <= dc_u1_result_req;
                dc_u2_raw_x100          <= dc_u2_result_req;
                dc_u1_valid             <= dc_u1_valid_result_req;
                dc_u2_valid             <= dc_u2_valid_result_req;
                dh_order_u1_valid       <= dh_order_u1_valid_result_req;
                dh_order_u2_valid       <= dh_order_u2_valid_result_req;
                dh_order_u1_list_raw    <= dh_order_u1_list_result_req;
                dh_order_u2_list_raw    <= dh_order_u2_list_result_req;
                dh_order_u1_count_raw   <= dh_order_u1_count_result_req;
                dh_order_u2_count_raw   <= dh_order_u2_count_result_req;
                metrics_valid          <= 1'b1;
                raw_result_commit_toggle <= ~raw_result_commit_toggle;
            end
        end
    end
end

endmodule
