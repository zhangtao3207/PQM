`timescale 1ns / 1ps

/*
 * 模块: ui_rms_measure
 * 功能:
 *   使用 U/I 两路峰峰值原始码差，按正弦波近似公式 `RMS = Vpp / (2*sqrt(2))`
 *   直接估算 U/I 两路 RMS 原始值。
 *   本模块只接收 p2p 原始数据，不再处理样本窗口、滤波或逐点 RMS 计算。
 * 输入:
 *   clk: 工作时钟。
 *   rst_n: 低有效复位。
 *   start: 启动一次 U/I 两路 RMS 原始值估算。
 *   u_pp_raw: 电压峰峰值原始补码值。
 *   i_pp_raw: 电流峰峰值原始补码值。
 *   u_pp_valid: 电压峰峰值原始值有效脉冲。
 *   i_pp_valid: 电流峰峰值原始值有效脉冲。
 * 输出:
 *   busy: 当前 RMS 原始值估算流程是否仍在进行。
 *   done: 本次估算完成时给出的完成脉冲。
 *   rms_valid: U/I 两路 RMS 原始值同时更新有效的单周期脉冲。
 *   config_error: 当前实现不使用配置校验，固定输出 0。
 *   frame_overflow: 当前实现不使用帧溢出检测，固定输出 0。
 *   u_rms_raw: 电压 RMS 原始补码值。
 *   i_rms_raw: 电流 RMS 原始补码值。
 */
module ui_rms_measure #(
    parameter integer DATA_WIDTH = 16
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    start,
    input  wire signed [31:0]      u_pp_raw,
    input  wire signed [31:0]      i_pp_raw,
    input  wire                    u_pp_valid,
    input  wire                    i_pp_valid,

    output wire                    busy,
    output reg                     done,
    output reg                     rms_valid,
    output wire                    config_error,
    output wire                    frame_overflow,
    output reg  signed [31:0]      u_rms_raw,
    output reg  signed [31:0]      i_rms_raw
);

localparam [15:0] RMS_NUMERATOR      = 16'd3536;
localparam [47:0] RMS_DENOMINATOR    = 48'd10000;
localparam [47:0] RMS_DENOM_HALF     = 48'd5000;
localparam [31:0] RMS_RAW_CLIP_VALUE = (32'd1 << (DATA_WIDTH - 1)) - 32'd1;

reg                     measure_active;
reg                     u_div_start;
reg                     i_div_start;
reg                     u_div_started;
reg                     i_div_started;
reg                     u_div_done_seen;
reg                     i_div_done_seen;

wire [31:0]             u_pp_abs_raw;
wire [31:0]             i_pp_abs_raw;
wire signed [47:0]      u_rms_scale_product_signed;
wire signed [47:0]      i_rms_scale_product_signed;
wire [47:0]             u_rms_scale_product_unsigned;
wire [47:0]             i_rms_scale_product_unsigned;
wire                    u_div_done;
wire                    u_div_zero;
wire [47:0]             u_div_quotient;
wire                    i_div_done;
wire                    i_div_zero;
wire [47:0]             i_div_quotient;

// 当前仅做 p2p 到 RMS 的固定比例换算，不再输出旧 RMS 链路里的错误标志。
assign busy           = measure_active;
assign config_error   = 1'b0;
assign frame_overflow = 1'b0;

// 将峰峰值原始补码量统一转成正幅值，异常负值按绝对值处理。
function [31:0] abs_value_of;
    input signed [31:0] signed_value;
    reg   [31:0]        abs_value;
begin
    if (signed_value[31])
        abs_value = ~signed_value + 32'd1;
    else
        abs_value = signed_value[31:0];

    abs_value_of = abs_value;
end
endfunction

// 提取 U/I 两路 p2p 原始值的幅值，供后续固定比例换算使用。
assign u_pp_abs_raw = abs_value_of(u_pp_raw);
assign i_pp_abs_raw = abs_value_of(i_pp_raw);

// 将电压峰峰值原始量乘以固定比例分子，构造 RMS 原始值换算分子。
multiplier_signed #(
    .A_WIDTH(32),
    .B_WIDTH(16)
) u_u_pp_to_rms_multiplier (
    .multiplicand({1'b0, u_pp_abs_raw[30:0]}),
    .multiplier  (RMS_NUMERATOR),
    .product     (u_rms_scale_product_signed)
);

// 将电流峰峰值原始量乘以固定比例分子，构造 RMS 原始值换算分子。
multiplier_signed #(
    .A_WIDTH(32),
    .B_WIDTH(16)
) u_i_pp_to_rms_multiplier (
    .multiplicand({1'b0, i_pp_abs_raw[30:0]}),
    .multiplier  (RMS_NUMERATOR),
    .product     (i_rms_scale_product_signed)
);

// 将乘积统一转成无符号除法输入，负值保护为 0。
assign u_rms_scale_product_unsigned = u_rms_scale_product_signed[47] ? 48'd0 : u_rms_scale_product_signed[47:0];
assign i_rms_scale_product_unsigned = i_rms_scale_product_signed[47] ? 48'd0 : i_rms_scale_product_signed[47:0];

// 对电压峰峰值原始量执行固定比例换算，得到电压 RMS 原始值。
divider_unsigned #(
    .WIDTH(48)
) u_u_rms_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (u_div_start),
    .dividend      (u_rms_scale_product_unsigned + RMS_DENOM_HALF),
    .divisor       (RMS_DENOMINATOR),
    .busy          (),
    .done          (u_div_done),
    .divide_by_zero(u_div_zero),
    .quotient      (u_div_quotient)
);

// 对电流峰峰值原始量执行固定比例换算，得到电流 RMS 原始值。
divider_unsigned #(
    .WIDTH(48)
) u_i_rms_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (i_div_start),
    .dividend      (i_rms_scale_product_unsigned + RMS_DENOM_HALF),
    .divisor       (RMS_DENOMINATOR),
    .busy          (),
    .done          (i_div_done),
    .divide_by_zero(i_div_zero),
    .quotient      (i_div_quotient)
);

// 在当前时钟域等待两路 p2p 原始值到齐，并统一完成 U/I 两路 RMS 原始值换算。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        measure_active  <= 1'b0;
        u_div_start     <= 1'b0;
        i_div_start     <= 1'b0;
        u_div_started   <= 1'b0;
        i_div_started   <= 1'b0;
        u_div_done_seen <= 1'b0;
        i_div_done_seen <= 1'b0;
        done            <= 1'b0;
        rms_valid       <= 1'b0;
        u_rms_raw       <= 32'sd0;
        i_rms_raw       <= 32'sd0;
    end else begin
        done      <= 1'b0;
        rms_valid <= 1'b0;
        u_div_start <= 1'b0;
        i_div_start <= 1'b0;

        if (u_div_done)
            u_div_done_seen <= 1'b1;
        if (i_div_done)
            i_div_done_seen <= 1'b1;

        if (start && !measure_active) begin
            measure_active  <= 1'b1;
            u_div_started   <= 1'b0;
            i_div_started   <= 1'b0;
            u_div_done_seen <= 1'b0;
            i_div_done_seen <= 1'b0;
            u_rms_raw       <= 32'sd0;
            i_rms_raw       <= 32'sd0;
        end

        if (measure_active) begin
            if (u_pp_valid && !u_div_started) begin
                u_div_start   <= 1'b1;
                u_div_started <= 1'b1;
            end

            if (i_pp_valid && !i_div_started) begin
                i_div_start   <= 1'b1;
                i_div_started <= 1'b1;
            end

            if (u_div_done) begin
                if (u_div_zero)
                    u_rms_raw <= 32'sd0;
                else if ((u_div_quotient[47:32] != 16'd0) || (u_div_quotient[31:0] > RMS_RAW_CLIP_VALUE))
                    u_rms_raw <= {1'b0, RMS_RAW_CLIP_VALUE[30:0]};
                else
                    u_rms_raw <= {1'b0, u_div_quotient[30:0]};
            end

            if (i_div_done) begin
                if (i_div_zero)
                    i_rms_raw <= 32'sd0;
                else if ((i_div_quotient[47:32] != 16'd0) || (i_div_quotient[31:0] > RMS_RAW_CLIP_VALUE))
                    i_rms_raw <= {1'b0, RMS_RAW_CLIP_VALUE[30:0]};
                else
                    i_rms_raw <= {1'b0, i_div_quotient[30:0]};
            end

            if ((u_div_done_seen || u_div_done) && (i_div_done_seen || i_div_done)) begin
                measure_active <= 1'b0;
                rms_valid      <= 1'b1;
                done           <= 1'b1;
            end
        end
    end
end

endmodule
