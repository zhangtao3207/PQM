`timescale 1ns / 1ps

//==============================================================================
// 模块说明
// 1. 本模块由原例程 30_digital_voltmeter 的 ADC 数据处理链提取并重构而来。
// 2. 当前实现为“绝对电压模式”：
//    ADC 码值先做均值滤波，再按满量程直接换算为绝对电压，不再使用 0V 校准偏移。
// 3. 在不增加、不减少当前顶层引脚的前提下，下面只列出“必须连接真实硬件”的端口约束，
//    便于你逐项对照并替换成自己板卡的引脚。
//
// 必须连接真实硬件并修改 XDC 的端口：
// 1) sys_clk
//    create_clock -period 20.000 -name sys_clk [get_ports sys_clk]
//    set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN U18} [get_ports sys_clk]
//
// 2) sys_rst_n
//    set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN N16} [get_ports sys_rst_n]
//
// 3) ad_data[7:0]
//    set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN U14} [get_ports {ad_data[7]}]
//    set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN U15} [get_ports {ad_data[6]}]
//    set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN V12} [get_ports {ad_data[5]}]
//    set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN W13} [get_ports {ad_data[4]}]
//    set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN W14} [get_ports {ad_data[3]}]
//    set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN Y14} [get_ports {ad_data[2]}]
//    set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN V15} [get_ports {ad_data[1]}]
//    set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN W15} [get_ports {ad_data[0]}]
//
// 4) ad_clk
//    set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN V13} [get_ports ad_clk]
//
// 5) ad_otr
//    set_property -dict {IOSTANDARD LVCMOS33 PACKAGE_PIN U13} [get_ports ad_otr]
//
// 当前顶层其余端口 avg_code / avg_valid / voltage_mv / voltage_valid / over_range /
// data_symbol / data_tens / data_units / data_decile / data_percentiles / digits_valid
// 都是逻辑处理结果输出。原数字电压表例程没有为这些信号分配板级外部引脚约束。
// 如果你后续要把这些信号直接引到 FPGA 管脚，需要按你的目标板另行补充 XDC。
//==============================================================================

module adc_abs_voltage_top #(
    parameter integer WIDTH         = 8,
    parameter integer AVERAGE_SHIFT = 6,
    parameter integer ZERO_CAL_SHIFT = 10,
    parameter integer FULL_SCALE_MV = 5000,
    parameter integer ZERO_CODE_DEFAULT = (1 << (WIDTH - 1)) - 1,
    parameter integer ZERO_CODE_TOLERANCE = (1 << (WIDTH - 3))
)(
    input  wire             sys_clk,           // 系统时钟输入，必须连接真实硬件时钟
    input  wire             sys_rst_n,         // 系统复位输入，低电平有效，必须连接真实硬件复位
    input  wire [WIDTH-1:0] ad_data,           // ADC 原始采样数据输入，必须连接 ADC 数据总线
    input  wire             ad_otr,            // ADC 超量程标志输入，必须连接 ADC OTR 信号
    output reg              ad_clk,            // 输出给 ADC 的采样时钟，必须连接 ADC 时钟脚
    output wire [WIDTH-1:0] avg_code,          // 均值滤波后的 ADC 码值，逻辑输出
    output wire             avg_valid,         // 均值码值有效脉冲，逻辑输出
    output wire [31:0]      voltage_mv,        // 绝对电压值输出，单位 mV，逻辑输出
    output wire             voltage_valid,     // 电压值有效脉冲，逻辑输出
    output wire             over_range,        // 超量程输出标志，逻辑输出
    output wire             data_symbol,       // 显示符号位，绝对电压模式下恒为 0，逻辑输出
    output wire [7:0]       data_tens,         // 显示电压十位数字，逻辑输出
    output wire [7:0]       data_units,        // 显示电压个位数字，逻辑输出
    output wire [7:0]       data_decile,       // 显示电压小数点后第一位，逻辑输出
    output wire [7:0]       data_percentiles,  // 显示电压小数点后第二位，逻辑输出
    output wire             digits_valid,      // 数码位有效脉冲，逻辑输出
    output wire [WIDTH-1:0] zero_code_out,
    output wire             zero_code_valid_out
);

wire avg_over_range;
wire [WIDTH-1:0] zero_code;
wire             zero_code_valid;
wire             calc_data_symbol;

assign zero_code_out       = zero_code;
assign zero_code_valid_out = zero_code_valid;

always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n)
        ad_clk <= 1'b0;
    else
        ad_clk <= ~ad_clk;
end

adc_zero_calibrator #(
    .WIDTH             (WIDTH),
    .CAL_SHIFT         (ZERO_CAL_SHIFT),
    .ZERO_CODE_DEFAULT (ZERO_CODE_DEFAULT),
    .ACCEPT_TOLERANCE  (ZERO_CODE_TOLERANCE)
) u_adc_zero_calibrator (
    .clk            (ad_clk),
    .rst_n          (sys_rst_n),
    .ad_data        (ad_data),
    .zero_code_valid(zero_code_valid),
    .zero_code      (zero_code)
);

adc_sample_average #(
    .WIDTH        (WIDTH),
    .AVERAGE_SHIFT(AVERAGE_SHIFT)
) u_adc_sample_average (
    .clk       (ad_clk),
    .rst_n     (sys_rst_n),
    .ad_data   (ad_data),
    .ad_otr    (ad_otr),
    .avg_code  (avg_code),
    .avg_valid (avg_valid),
    .over_range(avg_over_range)
);

adc_abs_voltage_calc #(
    .WIDTH            (WIDTH),
    .FULL_SCALE_MV    (FULL_SCALE_MV),
    .ZERO_CODE_DEFAULT(ZERO_CODE_DEFAULT)
) u_adc_abs_voltage_calc (
    .clk           (ad_clk),
    .rst_n         (sys_rst_n),
    .avg_code      (avg_code),
    .avg_valid     (avg_valid),
    .over_range_in (avg_over_range),
    .zero_code     (zero_code),
    .zero_code_valid(zero_code_valid),
    .voltage_mv    (voltage_mv),
    .voltage_valid (voltage_valid),
    .over_range_out(over_range),
    .data_symbol   (calc_data_symbol)
);

adc_voltage_digits u_adc_voltage_digits (
    .clk             (ad_clk),
    .rst_n           (sys_rst_n),
    .voltage_mv      (voltage_mv),
    .voltage_valid   (voltage_valid),
    .over_range      (over_range),
    .data_symbol_in  (calc_data_symbol),
    .data_symbol     (data_symbol),
    .data_tens       (data_tens),
    .data_units      (data_units),
    .data_decile     (data_decile),
    .data_percentiles(data_percentiles),
    .digits_valid    (digits_valid)
);

endmodule
