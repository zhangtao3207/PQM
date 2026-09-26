`timescale 1ns / 1ps

/*
 * 模块: divider_signed
 * 功能:
 *   基于 divider_unsigned 的参数化有符号除法器。
 *   该模块在 WIDTH 个时钟周期后返回有符号商。
 *
 * 输入:
 *   dividend: 被除数 (有符号)
 *   divisor: 除数 (有符号)
 *   clk: 系统时钟
 *   rst_n: 系统复位信号
 *   start: 除法启动信号
 *
 * 输出:
 *   busy: 忙状态标志
 *   done: 除法完成标志 (单周期脉冲)
 *   divide_by_zero: 除零错误标志
 *   quotient: 商值 (有符号)
 */
module divider_signed #(
    parameter integer WIDTH = 16
)(
    input  wire signed [WIDTH-1:0] dividend,
    input  wire signed [WIDTH-1:0] divisor,
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    start,
    output reg                     busy,
    output reg                     done,
    output reg                     divide_by_zero,
    output reg  signed [WIDTH-1:0] quotient
);

reg                  launch_pending;
reg                  quotient_neg;
reg  [WIDTH-1:0]     dividend_abs_reg;
reg  [WIDTH-1:0]     divisor_abs_reg;
reg                  unsigned_start;

wire                 unsigned_busy;
wire                 unsigned_done;
wire                 unsigned_divide_by_zero;
wire [WIDTH-1:0]     unsigned_quotient;
wire [WIDTH-1:0]     dividend_abs_next;
wire [WIDTH-1:0]     divisor_abs_next;
wire [WIDTH-1:0]     quotient_signed_mag;

assign dividend_abs_next = dividend[WIDTH-1] ? (~dividend + {{(WIDTH-1){1'b0}}, 1'b1}) : dividend;
assign divisor_abs_next  = divisor[WIDTH-1]  ? (~divisor  + {{(WIDTH-1){1'b0}}, 1'b1}) : divisor;
assign quotient_signed_mag = quotient_neg ? (~unsigned_quotient + {{(WIDTH-1){1'b0}}, 1'b1}) :
                                           unsigned_quotient;

divider_unsigned #(
    .WIDTH(WIDTH)
) u_divider_unsigned (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (unsigned_start),
    .dividend      (dividend_abs_reg),
    .divisor       (divisor_abs_reg),
    .busy          (unsigned_busy),
    .done          (unsigned_done),
    .divide_by_zero(unsigned_divide_by_zero),
    .quotient      (unsigned_quotient)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        busy             <= 1'b0;
        done             <= 1'b0;
        divide_by_zero   <= 1'b0;
        quotient         <= {WIDTH{1'b0}};
        launch_pending   <= 1'b0;
        quotient_neg     <= 1'b0;
        dividend_abs_reg <= {WIDTH{1'b0}};
        divisor_abs_reg  <= {WIDTH{1'b0}};
        unsigned_start   <= 1'b0;
    end else begin
        done           <= 1'b0;
        unsigned_start <= 1'b0;

        if (start && !busy) begin
            if (divisor == {WIDTH{1'b0}}) begin
                busy           <= 1'b0;
                done           <= 1'b1;
                divide_by_zero <= 1'b1;
                quotient       <= {WIDTH{1'b0}};
            end else begin
                busy             <= 1'b1;
                divide_by_zero   <= 1'b0;
                launch_pending   <= 1'b1;
                quotient_neg     <= dividend[WIDTH-1] ^ divisor[WIDTH-1];
                dividend_abs_reg <= dividend_abs_next;
                divisor_abs_reg  <= divisor_abs_next;
            end
        end else if (launch_pending) begin
            launch_pending <= 1'b0;
            unsigned_start <= 1'b1;
        end else if (busy && unsigned_done) begin
            busy           <= 1'b0;
            done           <= 1'b1;
            divide_by_zero <= unsigned_divide_by_zero;
            quotient       <= quotient_signed_mag;
        end
    end
end

endmodule
