/*
 * 模块: signed_code_to_digits_x100
 * 功能:
 *   将 16bit 补码输入按给定满量程比例映射为 x100 定点值，并进一步拆分为十位、个位、十分位和百分位。
 *
 * 输入:
 *   code_in: 16bit 补码输入值
 *   full_scale_x100: 正满量程对应的实际值，采用 x100 定点格式
 *   start: 启动一次换算
 *
 * 输出:
 *   busy: 模块忙标志
 *   digits_valid: 本次换算结果有效脉冲
 *   value_x100: 换算后的 x100 定点值
 *   tens/units/decile/percentiles: 供文本显示使用的十进制数字位
 *
 * 说明:
 *   - 输入为负时按 0 处理，因此输出范围为 0.00 到 99.99。
 *   - 乘法复用 multiplier_signed，除法复用 divider_unsigned。
 *   - 最终数值超过 99.99 时饱和到 99.99。
 */
module signed_code_to_digits_x100 (
    input                    clk,
    input                    rst_n,
    input                    start,
    input      signed [15:0] code_in,
    input             [31:0] full_scale_x100,
    output reg               busy,
    output reg               digits_valid,
    output reg        [31:0] value_x100,
    output reg        [7:0]  tens,
    output reg        [7:0]  units,
    output reg        [7:0]  decile,
    output reg        [7:0]  percentiles
);

localparam [47:0] DIVISOR_CODE = 48'd32767;
localparam [47:0] ROUND_BIAS   = 48'd16383;
localparam [31:0] VALUE_CLIP   = 32'd9999;

// 补码输入先裁为非负，再与满量程相乘。
wire signed [15:0] code_nonneg_signed;
wire signed [31:0] full_scale_signed;
wire signed [47:0] product_signed;
wire [47:0]        product_unsigned;
wire               div_busy;
wire               div_done;
wire               div_zero;
wire [47:0]        div_quotient;

reg                div_start;
reg [47:0]         div_dividend;
reg [31:0]         value_clip_reg;
reg [31:0]         digit_work;
reg [7:0]          tens_work;
reg [7:0]          units_work;
reg [7:0]          decile_work;
integer            idx;

// 负输入不参与换算，直接按 0 处理。
assign code_nonneg_signed = code_in[15] ? 16'sd0 : {1'b0, code_in[14:0]};
assign full_scale_signed  = {1'b0, full_scale_x100[30:0]};
assign product_unsigned   = product_signed[47] ? 48'd0 : product_signed[47:0];

// 先做比例乘法，得到待归一化的中间值。
multiplier_signed #(
    .A_WIDTH(16),
    .B_WIDTH(32)
) u_multiplier_signed (
    .multiplicand(code_nonneg_signed),
    .multiplier  (full_scale_signed),
    .product     (product_signed)
);

divider_unsigned #(
    .WIDTH(48)
) u_divider_unsigned (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (div_start),
    .dividend      (div_dividend),
    .divisor       (DIVISOR_CODE),
    .busy          (div_busy),
    .done          (div_done),
    .divide_by_zero(div_zero),
    .quotient      (div_quotient)
);

// 启动比例换算后，等待除法完成并将结果拆分为文本显示数字位。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        busy         <= 1'b0;
        digits_valid <= 1'b0;
        div_start    <= 1'b0;
        div_dividend <= 48'd0;
        value_x100   <= 32'd0;
        tens         <= 8'd0;
        units        <= 8'd0;
        decile       <= 8'd0;
        percentiles  <= 8'd0;
    end else begin
        digits_valid <= 1'b0;
        div_start    <= 1'b0;

        if (start && !busy && !div_busy) begin
            busy         <= 1'b1;
            div_dividend <= product_unsigned + ROUND_BIAS;
            div_start    <= 1'b1;
        end else if (busy && div_done) begin
            busy <= 1'b0;

            // 先完成数值裁剪，再做十进制拆位。
            if (div_zero) begin
                value_clip_reg = 32'd0;
            end else if ((div_quotient[47:32] != 16'd0) || (div_quotient[31:0] > VALUE_CLIP)) begin
                value_clip_reg = VALUE_CLIP;
            end else begin
                value_clip_reg = div_quotient[31:0];
            end

            digit_work  = value_clip_reg;
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

            tens         <= tens_work;
            units        <= units_work;
            decile       <= decile_work;
            percentiles  <= digit_work[7:0];
            value_x100   <= value_clip_reg;
            digits_valid <= 1'b1;
        end
    end
end

endmodule
