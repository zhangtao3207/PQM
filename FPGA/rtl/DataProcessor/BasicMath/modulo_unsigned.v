`timescale 1ns / 1ps

/*
 * 模块: modulo_unsigned
 * 功能:
 *   基于 restoring-division 算法的参数化无符号余数单元。
 *   该模块避免使用 "%" 运算符，在 WIDTH 个时钟周期后返回余数。
 *   "done" 是一个单周期脉冲。
 *
 * 详细说明：
 *   参数化无符号求余器，与除法器共用 restoring division 思路，只是最终
 *   输出余数而不是商，用于替代 `%` 运算。
 */
module modulo_unsigned #(
    parameter integer WIDTH = 16
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 start,
    input  wire [WIDTH-1:0]     dividend,
    input  wire [WIDTH-1:0]     divisor,
    output reg                  busy,
    output reg                  done,
    output reg                  divide_by_zero,
    output reg  [WIDTH-1:0]     remainder
);

localparam integer COUNT_W = (WIDTH <= 2) ? 2 : $clog2(WIDTH + 1);

reg [WIDTH-1:0] divisor_reg;
reg [WIDTH-1:0] quotient_reg;
reg [WIDTH:0]   remainder_reg;
reg [COUNT_W-1:0] bit_count;

reg [WIDTH:0]   remainder_shift;
reg [WIDTH:0]   remainder_next;
reg [WIDTH-1:0] quotient_next;

// 单轮迭代组合逻辑：更新余数与商移位寄存器。
always @(*) begin
    remainder_shift = {remainder_reg[WIDTH-1:0], quotient_reg[WIDTH-1]};

    if (remainder_shift >= {1'b0, divisor_reg}) begin
        remainder_next = remainder_shift - {1'b0, divisor_reg};
        quotient_next  = {quotient_reg[WIDTH-2:0], 1'b1};
    end else begin
        remainder_next = remainder_shift;
        quotient_next  = {quotient_reg[WIDTH-2:0], 1'b0};
    end
end

// 时序控制：完成 WIDTH 轮后输出余数，`done` 为单拍脉冲。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        busy           <= 1'b0;
        done           <= 1'b0;
        divide_by_zero <= 1'b0;
        remainder      <= {WIDTH{1'b0}};
        divisor_reg    <= {WIDTH{1'b0}};
        quotient_reg   <= {WIDTH{1'b0}};
        remainder_reg  <= {(WIDTH + 1){1'b0}};
        bit_count      <= {COUNT_W{1'b0}};
    end else begin
        done <= 1'b0;

        if (start && !busy) begin
            if (divisor == {WIDTH{1'b0}}) begin
                busy           <= 1'b0;
                done           <= 1'b1;
                divide_by_zero <= 1'b1;
                remainder      <= {WIDTH{1'b0}};
            end else begin
                busy           <= 1'b1;
                divide_by_zero <= 1'b0;
                divisor_reg    <= divisor;
                quotient_reg   <= dividend;
                remainder_reg  <= {(WIDTH + 1){1'b0}};
                bit_count      <= WIDTH;
            end
        end else if (busy) begin
            quotient_reg  <= quotient_next;
            remainder_reg <= remainder_next;

            if (bit_count == {{(COUNT_W-1){1'b0}}, 1'b1}) begin
                busy      <= 1'b0;
                done      <= 1'b1;
                remainder <= remainder_next[WIDTH-1:0];
                bit_count <= {COUNT_W{1'b0}};
            end else begin
                bit_count <= bit_count - {{(COUNT_W-1){1'b0}}, 1'b1};
            end
        end
    end
end

endmodule
