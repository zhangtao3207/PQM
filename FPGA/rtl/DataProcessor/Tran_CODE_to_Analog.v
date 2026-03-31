`timescale 1ns / 1ps

module Tran_CODE_to_Analog (
    input  wire signed [15:0] code_in,     // ADC 原始输出码值，16bit 二进制补码
    input  wire        [15:0] ref_mv,      // ADC 参考电压，单位 mV，典型值 2500
    input  wire               range_sel,   // 量程选择：1'b0 表示 ±5V，1'b1 表示 ±10V
    output reg  signed [31:0] analog_uv,   // 反算后的原始模拟值，单位 uV
    output reg  signed [31:0] analog_mv    // 反算后的原始模拟值，单位 mV，四舍五入
);

// 这里实现的是 ADC 传递函数的逆变换，也就是：
// CODE -> ADC 输入端原始模拟值
//
// 已知正向传递函数：
// ±10V ：CODE = (VIN / 10V) * 32768 * (2.5V / REF)
// ±5V  ：CODE = (VIN /  5V) * 32768 * (2.5V / REF)
//
// 逆变换为：
// ±10V ：VIN = CODE * 10V * REF / (32768 * 2.5V)
// ±5V  ：VIN = CODE *  5V * REF / (32768 * 2.5V)
//
// 为了降低量化损失，模块内部统一输出 uV：
// ±10V ：analog_uv = code_in * 10000000 * ref_mv / (32768 * 2500)
// ±5V  ：analog_uv = code_in *  5000000 * ref_mv / (32768 * 2500)

localparam integer CODE_SCALE         = 32768;    // 双极性 16bit ADC 的码值缩放系数
localparam integer REF_NOMINAL_MV     = 2500;     // 公式中的标称参考电压 2.5V
localparam integer RANGE_5V_FULL_UV   = 5000000;  // ±5V 量程对应的正满量程电压，单位 uV
localparam integer RANGE_10V_FULL_UV  = 10000000; // ±10V 量程对应的正满量程电压，单位 uV
localparam integer UV_PER_MV          = 1000;     // 单位换算：1mV = 1000uV

reg signed [63:0] numerator;      // 分子：CODE * 满量程电压 * REF
reg signed [63:0] denominator;    // 分母：32768 * 2500
reg signed [63:0] analog_uv_calc; // 中间反算结果，单位 uV
reg signed [63:0] analog_mv_calc; // 中间反算结果，单位 mV
reg signed [63:0] round_bias_uv;  // uV -> mV 时的四舍五入补偿值

// 按量程与参考电压把 ADC 原始码值反算为输入端原始模拟值
always @(*) begin
    numerator   = 64'sd0;
    denominator = 64'sd1;
    analog_uv_calc = 64'sd0;
    analog_mv_calc = 64'sd0;
    round_bias_uv  = 64'sd0;
    analog_uv      = 32'sd0;
    analog_mv      = 32'sd0;

    if (ref_mv != 16'd0) begin
        if (range_sel) begin
            numerator = $signed(code_in) * RANGE_10V_FULL_UV * $signed({1'b0, ref_mv});
        end else begin
            numerator = $signed(code_in) * RANGE_5V_FULL_UV * $signed({1'b0, ref_mv});
        end

        denominator = CODE_SCALE * REF_NOMINAL_MV;
        analog_uv_calc = numerator / denominator;

        if (analog_uv_calc >= 0) begin
            round_bias_uv = UV_PER_MV / 2;
        end else begin
            round_bias_uv = -(UV_PER_MV / 2);
        end
        analog_mv_calc = (analog_uv_calc + round_bias_uv) / UV_PER_MV;

        analog_uv = analog_uv_calc[31:0];
        analog_mv = analog_mv_calc[31:0];
    end
end

endmodule
