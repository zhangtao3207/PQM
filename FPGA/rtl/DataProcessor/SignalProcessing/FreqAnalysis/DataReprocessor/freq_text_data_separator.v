`timescale 1ns / 1ps

/*
 * 模块: freq_text_data_separator
 * 功能:
 *   将频域文本指标的 x100/order 数值拆分为 LCD 字符渲染需要的十进制数位和符号位。
 * 输入:
 *   clk: 文本预处理工作时钟。
 *   rst_n: 低有效复位信号。
 *   start: 启动一次频域文本数位拆分。
 *   thd_u_x100: 电压 THD，单位为百分比 x100。
 *   thd_i_x100: 电流 THD，单位为百分比 x100。
 *   u1_mag_x100: 电压基波幅值占比，单位为百分比 x100。
 *   i1_mag_x100: 电流基波幅值占比，单位为百分比 x100。
 *   phase1_x100: 基波 U-I 相位差，单位为度 x100。
 *   dc_u_x100: 电压直流分量占比，单位为百分比 x100。
 *   dc_i_x100: 电流直流分量占比，单位为百分比 x100。
 *   dh_order_u: 电压主导谐波次数。
 *   dh_order_i: 电流主导谐波次数。
 *   各 valid 输入: 对应数值是否有效。
 * 输出:
 *   done: 本次数位拆分完成脉冲。
 *   各 digit/valid 输出: 供 LCD 文本层直接渲染的数字位、符号位和有效位。
 */
module freq_text_data_separator (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               start,
    input  wire [31:0]        thd_u_x100,
    input  wire [31:0]        thd_i_x100,
    input  wire               thd_u_valid_in,
    input  wire               thd_i_valid_in,
    input  wire [31:0]        u1_mag_x100,
    input  wire [31:0]        i1_mag_x100,
    input  wire               u1_mag_valid_in,
    input  wire               i1_mag_valid_in,
    input  wire signed [31:0] phase1_x100,
    input  wire               phase1_valid_in,
    input  wire [31:0]        dc_u_x100,
    input  wire [31:0]        dc_i_x100,
    input  wire               dc_u_valid_in,
    input  wire               dc_i_valid_in,
    input  wire [8:0]         dh_order_u,
    input  wire [8:0]         dh_order_i,
    input  wire               dh_order_u_valid_in,
    input  wire               dh_order_i_valid_in,
    output reg                done,
    output reg  [7:0]         thd_u_hundreds,
    output reg  [7:0]         thd_u_tens,
    output reg  [7:0]         thd_u_units,
    output reg  [7:0]         thd_u_decile,
    output reg  [7:0]         thd_u_percentiles,
    output reg                thd_u_valid,
    output reg  [7:0]         thd_i_hundreds,
    output reg  [7:0]         thd_i_tens,
    output reg  [7:0]         thd_i_units,
    output reg  [7:0]         thd_i_decile,
    output reg  [7:0]         thd_i_percentiles,
    output reg                thd_i_valid,
    output reg  [7:0]         u1_mag_hundreds,
    output reg  [7:0]         u1_mag_tens,
    output reg  [7:0]         u1_mag_units,
    output reg  [7:0]         u1_mag_decile,
    output reg  [7:0]         u1_mag_percentiles,
    output reg                u1_mag_valid,
    output reg  [7:0]         i1_mag_hundreds,
    output reg  [7:0]         i1_mag_tens,
    output reg  [7:0]         i1_mag_units,
    output reg  [7:0]         i1_mag_decile,
    output reg  [7:0]         i1_mag_percentiles,
    output reg                i1_mag_valid,
    output reg                phase1_neg,
    output reg  [7:0]         phase1_hundreds,
    output reg  [7:0]         phase1_tens,
    output reg  [7:0]         phase1_units,
    output reg  [7:0]         phase1_decile,
    output reg  [7:0]         phase1_percentiles,
    output reg                phase1_valid,
    output reg  [7:0]         dc_u_hundreds,
    output reg  [7:0]         dc_u_tens,
    output reg  [7:0]         dc_u_units,
    output reg  [7:0]         dc_u_decile,
    output reg  [7:0]         dc_u_percentiles,
    output reg                dc_u_valid,
    output reg  [7:0]         dc_i_hundreds,
    output reg  [7:0]         dc_i_tens,
    output reg  [7:0]         dc_i_units,
    output reg  [7:0]         dc_i_decile,
    output reg  [7:0]         dc_i_percentiles,
    output reg                dc_i_valid,
    output reg  [7:0]         dh_order_u_hundreds,
    output reg  [7:0]         dh_order_u_tens,
    output reg  [7:0]         dh_order_u_units,
    output reg                dh_order_u_valid,
    output reg  [7:0]         dh_order_i_hundreds,
    output reg  [7:0]         dh_order_i_tens,
    output reg  [7:0]         dh_order_i_units,
    output reg                dh_order_i_valid
);

wire [31:0] phase1_abs_x100;
wire [31:0] dh_order_u_x100;
wire [31:0] dh_order_i_x100;

wire [7:0] thd_u_hundreds_wire, thd_u_tens_wire, thd_u_units_wire, thd_u_decile_wire, thd_u_percentiles_wire;
wire [7:0] thd_i_hundreds_wire, thd_i_tens_wire, thd_i_units_wire, thd_i_decile_wire, thd_i_percentiles_wire;
wire [7:0] u1_mag_hundreds_wire, u1_mag_tens_wire, u1_mag_units_wire, u1_mag_decile_wire, u1_mag_percentiles_wire;
wire [7:0] i1_mag_hundreds_wire, i1_mag_tens_wire, i1_mag_units_wire, i1_mag_decile_wire, i1_mag_percentiles_wire;
wire [7:0] phase1_hundreds_wire, phase1_tens_wire, phase1_units_wire, phase1_decile_wire, phase1_percentiles_wire;
wire [7:0] dc_u_hundreds_wire, dc_u_tens_wire, dc_u_units_wire, dc_u_decile_wire, dc_u_percentiles_wire;
wire [7:0] dc_i_hundreds_wire, dc_i_tens_wire, dc_i_units_wire, dc_i_decile_wire, dc_i_percentiles_wire;
wire [7:0] dh_order_u_hundreds_wire, dh_order_u_tens_wire, dh_order_u_units_wire;
wire [7:0] dh_order_i_hundreds_wire, dh_order_i_tens_wire, dh_order_i_units_wire;

// 将有符号相位转换成绝对值，符号单独传递给 LCD 文本层。
function [31:0] abs_value_of;
    input signed [31:0] signed_value;
    begin
        abs_value_of = signed_value[31] ? (~signed_value + 32'd1) : signed_value[31:0];
    end
endfunction

assign phase1_abs_x100 = abs_value_of(phase1_x100);
assign dh_order_u_x100 = ({23'd0, dh_order_u} << 6) +
                         ({23'd0, dh_order_u} << 5) +
                         ({23'd0, dh_order_u} << 2);
assign dh_order_i_x100 = ({23'd0, dh_order_i} << 6) +
                         ({23'd0, dh_order_i} << 5) +
                         ({23'd0, dh_order_i} << 2);

// 百分比类、相位类和整数谐波次数统一复用 x100 数位拆分模块。
value_x100_to_digits u_thd_u_digits (
    .value_x100 (thd_u_x100),
    .hundreds   (thd_u_hundreds_wire),
    .tens       (thd_u_tens_wire),
    .units      (thd_u_units_wire),
    .decile     (thd_u_decile_wire),
    .percentiles(thd_u_percentiles_wire)
);

value_x100_to_digits u_thd_i_digits (
    .value_x100 (thd_i_x100),
    .hundreds   (thd_i_hundreds_wire),
    .tens       (thd_i_tens_wire),
    .units      (thd_i_units_wire),
    .decile     (thd_i_decile_wire),
    .percentiles(thd_i_percentiles_wire)
);

value_x100_to_digits u_u1_mag_digits (
    .value_x100 (u1_mag_x100),
    .hundreds   (u1_mag_hundreds_wire),
    .tens       (u1_mag_tens_wire),
    .units      (u1_mag_units_wire),
    .decile     (u1_mag_decile_wire),
    .percentiles(u1_mag_percentiles_wire)
);

value_x100_to_digits u_i1_mag_digits (
    .value_x100 (i1_mag_x100),
    .hundreds   (i1_mag_hundreds_wire),
    .tens       (i1_mag_tens_wire),
    .units      (i1_mag_units_wire),
    .decile     (i1_mag_decile_wire),
    .percentiles(i1_mag_percentiles_wire)
);

value_x100_to_digits u_phase1_digits (
    .value_x100 (phase1_abs_x100),
    .hundreds   (phase1_hundreds_wire),
    .tens       (phase1_tens_wire),
    .units      (phase1_units_wire),
    .decile     (phase1_decile_wire),
    .percentiles(phase1_percentiles_wire)
);

value_x100_to_digits u_dc_u_digits (
    .value_x100 (dc_u_x100),
    .hundreds   (dc_u_hundreds_wire),
    .tens       (dc_u_tens_wire),
    .units      (dc_u_units_wire),
    .decile     (dc_u_decile_wire),
    .percentiles(dc_u_percentiles_wire)
);

value_x100_to_digits u_dc_i_digits (
    .value_x100 (dc_i_x100),
    .hundreds   (dc_i_hundreds_wire),
    .tens       (dc_i_tens_wire),
    .units      (dc_i_units_wire),
    .decile     (dc_i_decile_wire),
    .percentiles(dc_i_percentiles_wire)
);

value_x100_to_digits u_dh_order_u_digits (
    .value_x100 (dh_order_u_x100),
    .hundreds   (dh_order_u_hundreds_wire),
    .tens       (dh_order_u_tens_wire),
    .units      (dh_order_u_units_wire),
    .decile     (),
    .percentiles()
);

value_x100_to_digits u_dh_order_i_digits (
    .value_x100 (dh_order_i_x100),
    .hundreds   (dh_order_i_hundreds_wire),
    .tens       (dh_order_i_tens_wire),
    .units      (dh_order_i_units_wire),
    .decile     (),
    .percentiles()
);

// 在 start 到来时一次性提交所有拆分结果，保证 LCD 文本包来自同一批 raw 指标。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        done                  <= 1'b0;
        thd_u_hundreds        <= 8'd0;
        thd_u_tens            <= 8'd0;
        thd_u_units           <= 8'd0;
        thd_u_decile          <= 8'd0;
        thd_u_percentiles     <= 8'd0;
        thd_u_valid           <= 1'b0;
        thd_i_hundreds        <= 8'd0;
        thd_i_tens            <= 8'd0;
        thd_i_units           <= 8'd0;
        thd_i_decile          <= 8'd0;
        thd_i_percentiles     <= 8'd0;
        thd_i_valid           <= 1'b0;
        u1_mag_hundreds       <= 8'd0;
        u1_mag_tens           <= 8'd0;
        u1_mag_units          <= 8'd0;
        u1_mag_decile         <= 8'd0;
        u1_mag_percentiles    <= 8'd0;
        u1_mag_valid          <= 1'b0;
        i1_mag_hundreds       <= 8'd0;
        i1_mag_tens           <= 8'd0;
        i1_mag_units          <= 8'd0;
        i1_mag_decile         <= 8'd0;
        i1_mag_percentiles    <= 8'd0;
        i1_mag_valid          <= 1'b0;
        phase1_neg            <= 1'b0;
        phase1_hundreds       <= 8'd0;
        phase1_tens           <= 8'd0;
        phase1_units          <= 8'd0;
        phase1_decile         <= 8'd0;
        phase1_percentiles    <= 8'd0;
        phase1_valid          <= 1'b0;
        dc_u_hundreds         <= 8'd0;
        dc_u_tens             <= 8'd0;
        dc_u_units            <= 8'd0;
        dc_u_decile           <= 8'd0;
        dc_u_percentiles      <= 8'd0;
        dc_u_valid            <= 1'b0;
        dc_i_hundreds         <= 8'd0;
        dc_i_tens             <= 8'd0;
        dc_i_units            <= 8'd0;
        dc_i_decile           <= 8'd0;
        dc_i_percentiles      <= 8'd0;
        dc_i_valid            <= 1'b0;
        dh_order_u_hundreds   <= 8'd0;
        dh_order_u_tens       <= 8'd0;
        dh_order_u_units      <= 8'd0;
        dh_order_u_valid      <= 1'b0;
        dh_order_i_hundreds   <= 8'd0;
        dh_order_i_tens       <= 8'd0;
        dh_order_i_units      <= 8'd0;
        dh_order_i_valid      <= 1'b0;
    end else begin
        done <= 1'b0;

        if (start) begin
            thd_u_hundreds      <= thd_u_hundreds_wire;
            thd_u_tens          <= thd_u_tens_wire;
            thd_u_units         <= thd_u_units_wire;
            thd_u_decile        <= thd_u_decile_wire;
            thd_u_percentiles   <= thd_u_percentiles_wire;
            thd_u_valid         <= thd_u_valid_in;
            thd_i_hundreds      <= thd_i_hundreds_wire;
            thd_i_tens          <= thd_i_tens_wire;
            thd_i_units         <= thd_i_units_wire;
            thd_i_decile        <= thd_i_decile_wire;
            thd_i_percentiles   <= thd_i_percentiles_wire;
            thd_i_valid         <= thd_i_valid_in;
            u1_mag_hundreds     <= u1_mag_hundreds_wire;
            u1_mag_tens         <= u1_mag_tens_wire;
            u1_mag_units        <= u1_mag_units_wire;
            u1_mag_decile       <= u1_mag_decile_wire;
            u1_mag_percentiles  <= u1_mag_percentiles_wire;
            u1_mag_valid        <= u1_mag_valid_in;
            i1_mag_hundreds     <= i1_mag_hundreds_wire;
            i1_mag_tens         <= i1_mag_tens_wire;
            i1_mag_units        <= i1_mag_units_wire;
            i1_mag_decile       <= i1_mag_decile_wire;
            i1_mag_percentiles  <= i1_mag_percentiles_wire;
            i1_mag_valid        <= i1_mag_valid_in;
            phase1_neg          <= phase1_x100[31] && (phase1_abs_x100 != 32'd0);
            phase1_hundreds     <= phase1_hundreds_wire;
            phase1_tens         <= phase1_tens_wire;
            phase1_units        <= phase1_units_wire;
            phase1_decile       <= phase1_decile_wire;
            phase1_percentiles  <= phase1_percentiles_wire;
            phase1_valid        <= phase1_valid_in;
            dc_u_hundreds       <= dc_u_hundreds_wire;
            dc_u_tens           <= dc_u_tens_wire;
            dc_u_units          <= dc_u_units_wire;
            dc_u_decile         <= dc_u_decile_wire;
            dc_u_percentiles    <= dc_u_percentiles_wire;
            dc_u_valid          <= dc_u_valid_in;
            dc_i_hundreds       <= dc_i_hundreds_wire;
            dc_i_tens           <= dc_i_tens_wire;
            dc_i_units          <= dc_i_units_wire;
            dc_i_decile         <= dc_i_decile_wire;
            dc_i_percentiles    <= dc_i_percentiles_wire;
            dc_i_valid          <= dc_i_valid_in;
            dh_order_u_hundreds <= dh_order_u_hundreds_wire;
            dh_order_u_tens     <= dh_order_u_tens_wire;
            dh_order_u_units    <= dh_order_u_units_wire;
            dh_order_u_valid    <= dh_order_u_valid_in;
            dh_order_i_hundreds <= dh_order_i_hundreds_wire;
            dh_order_i_tens     <= dh_order_i_tens_wire;
            dh_order_i_units    <= dh_order_i_units_wire;
            dh_order_i_valid    <= dh_order_i_valid_in;
            done                <= 1'b1;
        end
    end
end

endmodule
