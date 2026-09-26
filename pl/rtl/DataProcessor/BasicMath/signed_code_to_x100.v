/*
 * 模块: signed_code_to_x100
 * 功能:
 *   将补码输入按满量程比例换算为无符号 x100 数值。
 *
 * 输入:
 *   clk: 时钟
 *   rst_n: 低有效复位
 *   start: 启动一次换算
 *   code_in: 原始补码输入
 *   full_scale_x100: 正满量程对应的 x100 实际值
 *
 * 输出:
 *   busy: 换算进行中
 *   value_valid: 本次 x100 结果有效脉冲
 *   value_x100: 换算后的无符号 x100 数值
 */
module signed_code_to_x100 #(
    parameter integer WIDTH = 16
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    start,
    input  wire signed [WIDTH-1:0] code_in,
    input  wire [31:0]             full_scale_x100,

    output reg                     busy,
    output reg                     value_valid,
    output reg [31:0]              value_x100
);

localparam [47:0] DIVISOR_CODE = (48'd1 << (WIDTH - 1)) - 48'd1;
localparam [47:0] ROUND_BIAS   = 48'd1 << (WIDTH - 2);
localparam [31:0] VALUE_CLIP   = 32'd99999;

wire signed [WIDTH-1:0] code_nonneg_signed;
wire signed [31:0]      full_scale_signed;
wire signed [WIDTH+31:0] product_signed;
wire [47:0]            product_unsigned;
wire                   div_done;
wire                   div_zero;
wire [47:0]            div_quotient;

reg                    div_start;
reg [47:0]             div_dividend;

assign code_nonneg_signed = code_in[WIDTH-1] ? {WIDTH{1'b0}} : code_in;
assign full_scale_signed  = {1'b0, full_scale_x100[30:0]};
assign product_unsigned   = product_signed[WIDTH+31] ? 48'd0 : product_signed[47:0];

// 先完成比例乘法，得到待归一化的中间值。
multiplier_signed #(
    .A_WIDTH(WIDTH),
    .B_WIDTH(32)
) u_scale_multiplier (
    .multiplicand(code_nonneg_signed),
    .multiplier  (full_scale_signed),
    .product     (product_signed)
);

// 再用无符号除法器完成满量程归一化，并通过加半除数实现四舍五入。
divider_unsigned #(
    .WIDTH(48)
) u_scale_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (div_start),
    .dividend      (div_dividend),
    .divisor       (DIVISOR_CODE),
    .busy          (),
    .done          (div_done),
    .divide_by_zero(div_zero),
    .quotient      (div_quotient)
);

// 在本地只输出统一的 x100 原始值，不再负责拆位。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        busy       <= 1'b0;
        value_valid<= 1'b0;
        value_x100 <= 32'd0;
        div_start  <= 1'b0;
        div_dividend <= 48'd0;
    end else begin
        value_valid <= 1'b0;
        div_start   <= 1'b0;

        if (start && !busy) begin
            busy        <= 1'b1;
            div_dividend<= product_unsigned + ROUND_BIAS;
            div_start   <= 1'b1;
        end else if (busy && div_done) begin
            busy <= 1'b0;

            if (div_zero) begin
                value_x100 <= 32'd0;
            end else if ((div_quotient[47:32] != 16'd0) || (div_quotient[31:0] > VALUE_CLIP)) begin
                value_x100 <= VALUE_CLIP;
            end else begin
                value_x100 <= div_quotient[31:0];
            end

            value_valid <= 1'b1;
        end
    end
end

endmodule
