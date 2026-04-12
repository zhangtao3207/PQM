/*
 * 模块: value_x100_to_digits
 * 功能:
 *   将 x100 定点格式的无符号数拆分为十位、个位、十分位和百分位。
 *
 * 输入:
 *   value_x100: 按 x100 缩放后的无符号数值，例如 32'd1234 表示 12.34
 *
 * 输出:
 *   tens: 十位数字
 *   units: 个位数字
 *   decile: 十分位数字
 *   percentiles: 百分位数字
 *
 * 说明:
 *   本模块不使用直接除法和取模，而是通过逐级减法拆分各十进制位。
 */
module value_x100_to_digits (
    input      [31:0] value_x100,
    output reg [7:0]  tens,
    output reg [7:0]  units,
    output reg [7:0]  decile,
    output reg [7:0]  percentiles
);

// 拆位过程中的工作寄存器。
reg [31:0] digit_work;
reg [7:0]  tens_work;
reg [7:0]  units_work;
reg [7:0]  decile_work;
integer    idx;

// 依次剥离十位、个位和十分位，剩余值即为百分位。
always @(*) begin
    digit_work  = value_x100;
    tens_work   = 8'd0;
    units_work  = 8'd0;
    decile_work = 8'd0;

    for (idx = 0; idx < 10; idx = idx + 1) begin
        if (digit_work >= 32'd1000) begin
            digit_work = digit_work - 32'd1000;
            tens_work  = tens_work + 8'd1;
        end
    end

    for (idx = 0; idx < 10; idx = idx + 1) begin
        if (digit_work >= 32'd100) begin
            digit_work = digit_work - 32'd100;
            units_work = units_work + 8'd1;
        end
    end

    for (idx = 0; idx < 10; idx = idx + 1) begin
        if (digit_work >= 32'd10) begin
            digit_work  = digit_work - 32'd10;
            decile_work = decile_work + 8'd1;
        end
    end

    tens        = tens_work;
    units       = units_work;
    decile      = decile_work;
    percentiles = digit_work[7:0];
end

endmodule
