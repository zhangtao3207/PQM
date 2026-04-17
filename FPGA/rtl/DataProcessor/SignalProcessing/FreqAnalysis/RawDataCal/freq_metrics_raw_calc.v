`timescale 1ns / 1ps

/*
 * 模块: freq_metrics_raw_calc
 * 功能:
 *   从一帧 0~500 次谐波流中提取频域右侧文本区所需的原始指标：
 *   THD_U/THD_I、U1/I1 幅值占比、Phase1、DC_U/DC_I 和 U/I 主导谐波次数。
 *   本模块只输出 raw/x100 定点结果，不负责十进制数位拆分。
 * 输入:
 *   clk: 频域 raw 指标统计时钟。
 *   rst_n: 低有效复位信号。
 *   enable: 指标统计使能。
 *   s_harmonic_fire: 当前谐波结果已被下游接收的单周期脉冲。
 *   s_harmonic_last: 当前谐波是否为本帧最后一项。
 *   s_harmonic_order: 当前谐波次数。
 *   s_harmonic_present: 当前谐波在本帧中是否有效。
 *   s_u_mag: 当前谐波电压幅值原始量。
 *   s_i_mag: 当前谐波电流幅值原始量。
 *   s_u_pct_x100: 当前谐波电压幅值占比，单位为百分比 x100。
 *   s_i_pct_x100: 当前谐波电流幅值占比，单位为百分比 x100。
 *   s_phase_diff_valid: 当前谐波 U-I 相位差是否有效。
 *   s_phase_diff_deg_x100: 当前谐波 U-I 相位差，单位为度 x100。
 * 输出:
 *   raw_result_commit_toggle: 一帧 raw 指标完成后翻转一次。
 *   thd_u_raw_x100: 电压 THD，单位为百分比 x100。
 *   thd_i_raw_x100: 电流 THD，单位为百分比 x100。
 *   u1_mag_raw_x100: 电压基波幅值占比，单位为百分比 x100。
 *   i1_mag_raw_x100: 电流基波幅值占比，单位为百分比 x100。
 *   phase1_raw_x100: 基波 U-I 相位差，单位为度 x100。
 *   dc_u_raw_x100: 电压直流分量占比，单位为百分比 x100。
 *   dc_i_raw_x100: 电流直流分量占比，单位为百分比 x100。
 *   dh_order_u_raw: 电压主导谐波次数，统计范围为 2~500 次。
 *   dh_order_i_raw: 电流主导谐波次数，统计范围为 2~500 次。
 *   各 valid 输出: 对应 raw 指标是否有效。
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
    output reg  [8:0]         dh_order_u_raw,
    output reg  [8:0]         dh_order_i_raw,
    output reg                dh_order_u_valid,
    output reg                dh_order_i_valid,
    output reg                metrics_valid
);

localparam ST_CAPTURE  = 1'b0;
localparam ST_WAIT_THD = 1'b1;

reg        state;
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
reg [8:0]  dh_order_u_pending;
reg [8:0]  dh_order_i_pending;
reg        dh_order_u_valid_pending;
reg        dh_order_i_valid_pending;
reg [16:0] dh_u_mag_work;
reg [16:0] dh_i_mag_work;
reg [8:0]  dh_u_order_work;
reg [8:0]  dh_i_order_work;
reg        dh_u_valid_work;
reg        dh_i_valid_work;
reg        thd_start;
reg [45:0] thd_u_square_sum_req;
reg [45:0] thd_i_square_sum_req;
reg [16:0] thd_u_fund_mag_req;
reg [16:0] thd_i_fund_mag_req;
reg        thd_u_fund_valid_req;
reg        thd_i_fund_valid_req;

wire signed [17:0] u_mag_signed;
wire signed [17:0] i_mag_signed;
wire signed [35:0] u_mag_square_product;
wire signed [35:0] i_mag_square_product;
wire               is_dc_order;
wire               is_fund_order;
wire               is_distortion_order;
wire [45:0]        u_square_sum_next;
wire [45:0]        i_square_sum_next;
wire [16:0]        dh_u_mag_next;
wire [16:0]        dh_i_mag_next;
wire [8:0]         dh_u_order_next;
wire [8:0]         dh_i_order_next;
wire               dh_u_valid_next;
wire               dh_i_valid_next;
wire               thd_busy;
wire               thd_done;
wire [31:0]        thd_u_calc_x100;
wire [31:0]        thd_i_calc_x100;
wire               thd_u_calc_valid;
wire               thd_i_calc_valid;

assign u_mag_signed = {1'b0, s_u_mag};
assign i_mag_signed = {1'b0, s_i_mag};
assign is_dc_order = (s_harmonic_order == 9'd0);
assign is_fund_order = (s_harmonic_order == 9'd1);
assign is_distortion_order = s_harmonic_present && (s_harmonic_order >= 9'd2);
assign u_square_sum_next = is_distortion_order ?
                           (u_square_sum_work + {10'd0, u_mag_square_product[35:0]}) :
                           u_square_sum_work;
assign i_square_sum_next = is_distortion_order ?
                           (i_square_sum_work + {10'd0, i_mag_square_product[35:0]}) :
                           i_square_sum_work;
assign dh_u_mag_next = (is_distortion_order && (s_u_mag > dh_u_mag_work)) ? s_u_mag : dh_u_mag_work;
assign dh_i_mag_next = (is_distortion_order && (s_i_mag > dh_i_mag_work)) ? s_i_mag : dh_i_mag_work;
assign dh_u_order_next = (is_distortion_order && (s_u_mag > dh_u_mag_work)) ? s_harmonic_order : dh_u_order_work;
assign dh_i_order_next = (is_distortion_order && (s_i_mag > dh_i_mag_work)) ? s_harmonic_order : dh_i_order_work;
assign dh_u_valid_next = dh_u_valid_work || (is_distortion_order && (s_u_mag != 17'd0));
assign dh_i_valid_next = dh_i_valid_work || (is_distortion_order && (s_i_mag != 17'd0));

// 对当前谐波幅值平方，供 THD 的 2~500 次谐波平方和累加使用。
multiplier_signed #(
    .A_WIDTH(18),
    .B_WIDTH(18)
) u_u_mag_square_multiplier (
    .multiplicand(u_mag_signed),
    .multiplier  (u_mag_signed),
    .product     (u_mag_square_product)
);

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

// 跟随谐波流逐项统计 raw 指标，在 THD 计算完成后统一提交一帧结果。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state                    <= ST_CAPTURE;
        u_square_sum_work        <= 46'd0;
        i_square_sum_work        <= 46'd0;
        u_fund_mag_work          <= 17'd0;
        i_fund_mag_work          <= 17'd0;
        u_fund_valid_work        <= 1'b0;
        i_fund_valid_work        <= 1'b0;
        u1_mag_pending           <= 32'd0;
        i1_mag_pending           <= 32'd0;
        u1_mag_valid_pending     <= 1'b0;
        i1_mag_valid_pending     <= 1'b0;
        phase1_pending           <= 32'sd0;
        phase1_valid_pending     <= 1'b0;
        dc_u_pending             <= 32'd0;
        dc_i_pending             <= 32'd0;
        dc_u_valid_pending       <= 1'b0;
        dc_i_valid_pending       <= 1'b0;
        dh_order_u_pending       <= 9'd0;
        dh_order_i_pending       <= 9'd0;
        dh_order_u_valid_pending <= 1'b0;
        dh_order_i_valid_pending <= 1'b0;
        dh_u_mag_work            <= 17'd0;
        dh_i_mag_work            <= 17'd0;
        dh_u_order_work          <= 9'd0;
        dh_i_order_work          <= 9'd0;
        dh_u_valid_work          <= 1'b0;
        dh_i_valid_work          <= 1'b0;
        thd_start                <= 1'b0;
        thd_u_square_sum_req     <= 46'd0;
        thd_i_square_sum_req     <= 46'd0;
        thd_u_fund_mag_req       <= 17'd0;
        thd_i_fund_mag_req       <= 17'd0;
        thd_u_fund_valid_req     <= 1'b0;
        thd_i_fund_valid_req     <= 1'b0;
        raw_result_commit_toggle <= 1'b0;
        thd_u_raw_x100           <= 32'd0;
        thd_i_raw_x100           <= 32'd0;
        thd_u_valid              <= 1'b0;
        thd_i_valid              <= 1'b0;
        u1_mag_raw_x100          <= 32'd0;
        i1_mag_raw_x100          <= 32'd0;
        u1_mag_valid             <= 1'b0;
        i1_mag_valid             <= 1'b0;
        phase1_raw_x100          <= 32'sd0;
        phase1_valid             <= 1'b0;
        dc_u_raw_x100            <= 32'd0;
        dc_i_raw_x100            <= 32'd0;
        dc_u_valid               <= 1'b0;
        dc_i_valid               <= 1'b0;
        dh_order_u_raw           <= 9'd0;
        dh_order_i_raw           <= 9'd0;
        dh_order_u_valid         <= 1'b0;
        dh_order_i_valid         <= 1'b0;
        metrics_valid            <= 1'b0;
    end else begin
        thd_start <= 1'b0;

        if (!enable) begin
            state <= ST_CAPTURE;
        end else begin
            case (state)
                ST_CAPTURE: begin
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
                            dh_i_mag_work        <= 17'd0;
                            dh_u_order_work      <= 9'd0;
                            dh_i_order_work      <= 9'd0;
                            dh_u_valid_work      <= 1'b0;
                            dh_i_valid_work      <= 1'b0;
                            metrics_valid        <= 1'b0;
                        end else begin
                            u_square_sum_work <= u_square_sum_next;
                            i_square_sum_work <= i_square_sum_next;
                            dh_u_mag_work     <= dh_u_mag_next;
                            dh_i_mag_work     <= dh_i_mag_next;
                            dh_u_order_work   <= dh_u_order_next;
                            dh_i_order_work   <= dh_i_order_next;
                            dh_u_valid_work   <= dh_u_valid_next;
                            dh_i_valid_work   <= dh_i_valid_next;
                        end

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

                        if (s_harmonic_last) begin
                            thd_u_square_sum_req     <= u_square_sum_next;
                            thd_i_square_sum_req     <= i_square_sum_next;
                            thd_u_fund_mag_req       <= u_fund_mag_work;
                            thd_i_fund_mag_req       <= i_fund_mag_work;
                            thd_u_fund_valid_req     <= u_fund_valid_work;
                            thd_i_fund_valid_req     <= i_fund_valid_work;
                            dh_order_u_pending       <= dh_u_order_next;
                            dh_order_i_pending       <= dh_i_order_next;
                            dh_order_u_valid_pending <= dh_u_valid_next;
                            dh_order_i_valid_pending <= dh_i_valid_next;
                            thd_start                <= 1'b1;
                            state                    <= ST_WAIT_THD;
                        end
                    end
                end

                ST_WAIT_THD: begin
                    if (thd_done) begin
                        thd_u_raw_x100           <= thd_u_calc_x100;
                        thd_i_raw_x100           <= thd_i_calc_x100;
                        thd_u_valid              <= thd_u_calc_valid;
                        thd_i_valid              <= thd_i_calc_valid;
                        u1_mag_raw_x100          <= u1_mag_pending;
                        i1_mag_raw_x100          <= i1_mag_pending;
                        u1_mag_valid             <= u1_mag_valid_pending;
                        i1_mag_valid             <= i1_mag_valid_pending;
                        phase1_raw_x100          <= phase1_pending;
                        phase1_valid             <= phase1_valid_pending;
                        dc_u_raw_x100            <= dc_u_pending;
                        dc_i_raw_x100            <= dc_i_pending;
                        dc_u_valid               <= dc_u_valid_pending;
                        dc_i_valid               <= dc_i_valid_pending;
                        dh_order_u_raw           <= dh_order_u_pending;
                        dh_order_i_raw           <= dh_order_i_pending;
                        dh_order_u_valid         <= dh_order_u_valid_pending;
                        dh_order_i_valid         <= dh_order_i_valid_pending;
                        metrics_valid            <= 1'b1;
                        raw_result_commit_toggle <= ~raw_result_commit_toggle;
                        state                    <= ST_CAPTURE;
                    end
                end

                default: begin
                    state <= ST_CAPTURE;
                end
            endcase
        end
    end
end

endmodule
