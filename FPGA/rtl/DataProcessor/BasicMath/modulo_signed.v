`timescale 1ns / 1ps

/*
 * 模块: modulo_signed
 * 功能:
 *   基于 modulo_unsigned 的参数化有符号余数单元。
 *   输出余数遵循被除数的符号，与 Verilog "%" 语义匹配。
 */
module modulo_signed #(
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
    output reg  signed [WIDTH-1:0] remainder
);

reg                  launch_pending;
reg                  remainder_neg;
reg  [WIDTH-1:0]     dividend_abs_reg;
reg  [WIDTH-1:0]     divisor_abs_reg;
reg                  unsigned_start;

wire                 unsigned_busy;
wire                 unsigned_done;
wire                 unsigned_divide_by_zero;
wire [WIDTH-1:0]     unsigned_remainder;
wire [WIDTH-1:0]     dividend_abs_next;
wire [WIDTH-1:0]     divisor_abs_next;
wire [WIDTH-1:0]     remainder_signed_mag;

assign dividend_abs_next = dividend[WIDTH-1] ? (~dividend + {{(WIDTH-1){1'b0}}, 1'b1}) : dividend;
assign divisor_abs_next  = divisor[WIDTH-1]  ? (~divisor  + {{(WIDTH-1){1'b0}}, 1'b1}) : divisor;
assign remainder_signed_mag = remainder_neg ? (~unsigned_remainder + {{(WIDTH-1){1'b0}}, 1'b1}) :
                                              unsigned_remainder;

modulo_unsigned #(
    .WIDTH(WIDTH)
) u_modulo_unsigned (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (unsigned_start),
    .dividend      (dividend_abs_reg),
    .divisor       (divisor_abs_reg),
    .busy          (unsigned_busy),
    .done          (unsigned_done),
    .divide_by_zero(unsigned_divide_by_zero),
    .remainder     (unsigned_remainder)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        busy             <= 1'b0;
        done             <= 1'b0;
        divide_by_zero   <= 1'b0;
        remainder        <= {WIDTH{1'b0}};
        launch_pending   <= 1'b0;
        remainder_neg    <= 1'b0;
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
                remainder      <= {WIDTH{1'b0}};
            end else begin
                busy             <= 1'b1;
                divide_by_zero   <= 1'b0;
                launch_pending   <= 1'b1;
                remainder_neg    <= dividend[WIDTH-1];
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
            remainder      <= remainder_signed_mag;
        end
    end
end

endmodule
