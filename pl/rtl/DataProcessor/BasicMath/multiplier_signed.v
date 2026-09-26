`timescale 1ns / 1ps

/*
 * 模块: multiplier_signed
 * 功能:
 *   参数化有符号乘法器包装器，用于替换功率指标数据路径中的内联 "*" 表达式。
 */
module multiplier_signed #(
    parameter integer A_WIDTH = 16,
    parameter integer B_WIDTH = 16
)(
    input  wire signed [A_WIDTH-1:0] multiplicand,
    input  wire signed [B_WIDTH-1:0] multiplier,
    output wire signed [A_WIDTH+B_WIDTH-1:0] product
);

assign product = multiplicand * multiplier;

endmodule
