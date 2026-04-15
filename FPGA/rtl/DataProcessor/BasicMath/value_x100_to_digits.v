/*
 * 模块: value_x100_to_digits
 * 功能:
 *   将无符号 x100 定点数拆分为百位、十位、个位、十分位和百分位。
 *
 * 输入:
 *   value_x100: 待拆分的无符号 x100 数值，例如 32'd1234 表示 12.34
 *
 * 输出:
 *   hundreds: 百位数字
 *   tens: 十位数字
 *   units: 个位数字
 *   decile: 十分位数字
 *   percentiles: 百分位数字
 */
module value_x100_to_digits (
    input      [31:0] value_x100,
    output reg [7:0]  hundreds,
    output reg [7:0]  tens,
    output reg [7:0]  units,
    output reg [7:0]  decile,
    output reg [7:0]  percentiles
);

reg [31:0] digit_work;
reg [7:0]  hundreds_work;
reg [7:0]  tens_work;
reg [7:0]  units_work;
reg [7:0]  decile_work;
integer    idx;

// 逐级减去 10000/1000/100/10，得到每一位十进制数字。
always @(*) begin
    digit_work    = value_x100;
    hundreds_work = 8'd0;
    tens_work     = 8'd0;
    units_work    = 8'd0;
    decile_work   = 8'd0;

    for (idx = 0; idx < 10; idx = idx + 1) begin
        if (digit_work >= 32'd10000) begin
            digit_work    = digit_work - 32'd10000;
            hundreds_work = hundreds_work + 8'd1;
        end
    end

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
            digit_work   = digit_work - 32'd10;
            decile_work  = decile_work + 8'd1;
        end
    end

    hundreds    = hundreds_work;
    tens        = tens_work;
    units       = units_work;
    decile      = decile_work;
    percentiles = digit_work[7:0];
end

endmodule
