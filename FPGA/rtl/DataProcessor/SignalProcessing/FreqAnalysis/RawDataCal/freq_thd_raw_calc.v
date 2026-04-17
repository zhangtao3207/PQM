`timescale 1ns / 1ps

/*
 * 模块: freq_thd_raw_calc
 * 功能:
 *   根据一帧谐波幅值平方和与基波幅值计算 U/I 总谐波畸变率 THD。
 *   本模块只输出 x100 百分比形式的原始数值，不进行十进制数位拆分。
 * 输入:
 *   clk: 频域 raw 计算时钟。
 *   rst_n: 低有效复位信号。
 *   start: 启动一次 THD 计算。
 *   u_harmonic_square_sum: 电压 2 次及以上谐波幅值平方和。
 *   i_harmonic_square_sum: 电流 2 次及以上谐波幅值平方和。
 *   u_fund_mag: 电压基波幅值。
 *   i_fund_mag: 电流基波幅值。
 *   u_fund_valid: 电压基波幅值是否有效。
 *   i_fund_valid: 电流基波幅值是否有效。
 * 输出:
 *   busy: THD 计算正在进行。
 *   done: 本次 THD 计算完成脉冲。
 *   thd_u_raw_x100: 电压 THD 原始输出，单位为百分比 x100。
 *   thd_i_raw_x100: 电流 THD 原始输出，单位为百分比 x100。
 *   thd_u_valid: 电压 THD 结果是否有效。
 *   thd_i_valid: 电流 THD 结果是否有效。
 */
module freq_thd_raw_calc (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [45:0] u_harmonic_square_sum,
    input  wire [45:0] i_harmonic_square_sum,
    input  wire [16:0] u_fund_mag,
    input  wire [16:0] i_fund_mag,
    input  wire        u_fund_valid,
    input  wire        i_fund_valid,
    output wire        busy,
    output reg         done,
    output reg  [31:0] thd_u_raw_x100,
    output reg  [31:0] thd_i_raw_x100,
    output reg         thd_u_valid,
    output reg         thd_i_valid
);

localparam [2:0] ST_IDLE       = 3'd0;
localparam [2:0] ST_SQRT_START = 3'd1;
localparam [2:0] ST_SQRT_WAIT  = 3'd2;
localparam [2:0] ST_DIV_START  = 3'd3;
localparam [2:0] ST_DIV_WAIT   = 3'd4;
localparam [2:0] ST_COMMIT     = 3'd5;
localparam signed [15:0] THD_SCALE_X100 = 16'sd10000;
localparam [31:0] THD_CLIP_X100 = 32'd99999;

reg [2:0]  state;
reg [45:0] work_u_square_sum;
reg [45:0] work_i_square_sum;
reg [16:0] work_u_fund_mag;
reg [16:0] work_i_fund_mag;
reg        work_u_fund_valid;
reg        work_i_fund_valid;
reg        u_sqrt_start;
reg        i_sqrt_start;
reg        u_div_start;
reg        i_div_start;
reg        u_div_bypass;
reg        i_div_bypass;
reg [22:0] u_thd_root_reg;
reg [22:0] i_thd_root_reg;

wire        u_sqrt_busy;
wire        i_sqrt_busy;
wire        u_sqrt_done;
wire        i_sqrt_done;
wire [22:0] u_sqrt_root;
wire [22:0] i_sqrt_root;
wire signed [23:0] u_root_signed;
wire signed [23:0] i_root_signed;
wire signed [39:0] u_scaled_product_signed;
wire signed [39:0] i_scaled_product_signed;
wire [39:0] u_scaled_product_unsigned;
wire [39:0] i_scaled_product_unsigned;
wire        u_div_done;
wire        i_div_done;
wire        u_div_zero;
wire        i_div_zero;
wire [39:0] u_div_quotient;
wire [39:0] i_div_quotient;
wire        div_done_all;

assign busy = (state != ST_IDLE);
assign u_root_signed = {1'b0, u_thd_root_reg};
assign i_root_signed = {1'b0, i_thd_root_reg};
assign u_scaled_product_unsigned = u_scaled_product_signed[39] ? 40'd0 : u_scaled_product_signed[39:0];
assign i_scaled_product_unsigned = i_scaled_product_signed[39] ? 40'd0 : i_scaled_product_signed[39:0];
assign div_done_all = (u_div_bypass || u_div_done) && (i_div_bypass || i_div_done);

// 对谐波平方和开方，得到 THD 分子中的谐波 RMS 幅值。
sqrt_unsigned #(
    .RADICAND_WIDTH(46),
    .ROOT_WIDTH    (23)
) u_u_thd_sqrt (
    .clk     (clk),
    .rst_n   (rst_n),
    .start   (u_sqrt_start),
    .radicand(work_u_square_sum),
    .busy    (u_sqrt_busy),
    .done    (u_sqrt_done),
    .root    (u_sqrt_root)
);

sqrt_unsigned #(
    .RADICAND_WIDTH(46),
    .ROOT_WIDTH    (23)
) u_i_thd_sqrt (
    .clk     (clk),
    .rst_n   (rst_n),
    .start   (i_sqrt_start),
    .radicand(work_i_square_sum),
    .busy    (i_sqrt_busy),
    .done    (i_sqrt_done),
    .root    (i_sqrt_root)
);

// 将开方后的谐波幅值乘以 10000，形成百分比 x100 除法的被除数。
multiplier_signed #(
    .A_WIDTH(24),
    .B_WIDTH(16)
) u_u_thd_scale_multiplier (
    .multiplicand(u_root_signed),
    .multiplier  (THD_SCALE_X100),
    .product     (u_scaled_product_signed)
);

multiplier_signed #(
    .A_WIDTH(24),
    .B_WIDTH(16)
) u_i_thd_scale_multiplier (
    .multiplicand(i_root_signed),
    .multiplier  (THD_SCALE_X100),
    .product     (i_scaled_product_signed)
);

// 除以基波幅值，得到 THD 百分比 x100 原始值。
divider_unsigned #(
    .WIDTH(40)
) u_u_thd_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (u_div_start),
    .dividend      (u_scaled_product_unsigned),
    .divisor       ({23'd0, work_u_fund_mag}),
    .busy          (),
    .done          (u_div_done),
    .divide_by_zero(u_div_zero),
    .quotient      (u_div_quotient)
);

divider_unsigned #(
    .WIDTH(40)
) u_i_thd_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (i_div_start),
    .dividend      (i_scaled_product_unsigned),
    .divisor       ({23'd0, work_i_fund_mag}),
    .busy          (),
    .done          (i_div_done),
    .divide_by_zero(i_div_zero),
    .quotient      (i_div_quotient)
);

// 顺序完成开方、比例放大和除法，并在最后统一提交 U/I THD。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state                  <= ST_IDLE;
        work_u_square_sum      <= 46'd0;
        work_i_square_sum      <= 46'd0;
        work_u_fund_mag        <= 17'd0;
        work_i_fund_mag        <= 17'd0;
        work_u_fund_valid      <= 1'b0;
        work_i_fund_valid      <= 1'b0;
        u_sqrt_start           <= 1'b0;
        i_sqrt_start           <= 1'b0;
        u_div_start            <= 1'b0;
        i_div_start            <= 1'b0;
        u_div_bypass           <= 1'b1;
        i_div_bypass           <= 1'b1;
        u_thd_root_reg         <= 23'd0;
        i_thd_root_reg         <= 23'd0;
        done                   <= 1'b0;
        thd_u_raw_x100         <= 32'd0;
        thd_i_raw_x100         <= 32'd0;
        thd_u_valid            <= 1'b0;
        thd_i_valid            <= 1'b0;
    end else begin
        done         <= 1'b0;
        u_sqrt_start <= 1'b0;
        i_sqrt_start <= 1'b0;
        u_div_start  <= 1'b0;
        i_div_start  <= 1'b0;

        case (state)
            ST_IDLE: begin
                if (start) begin
                    work_u_square_sum <= u_harmonic_square_sum;
                    work_i_square_sum <= i_harmonic_square_sum;
                    work_u_fund_mag   <= u_fund_mag;
                    work_i_fund_mag   <= i_fund_mag;
                    work_u_fund_valid <= u_fund_valid;
                    work_i_fund_valid <= i_fund_valid;
                    thd_u_raw_x100    <= 32'd0;
                    thd_i_raw_x100    <= 32'd0;
                    thd_u_valid       <= 1'b0;
                    thd_i_valid       <= 1'b0;
                    state             <= ST_SQRT_START;
                end
            end

            ST_SQRT_START: begin
                u_sqrt_start <= 1'b1;
                i_sqrt_start <= 1'b1;
                state        <= ST_SQRT_WAIT;
            end

            ST_SQRT_WAIT: begin
                if (u_sqrt_done && i_sqrt_done) begin
                    u_thd_root_reg <= u_sqrt_root;
                    i_thd_root_reg <= i_sqrt_root;
                    state          <= ST_DIV_START;
                end
            end

            ST_DIV_START: begin
                u_div_bypass <= !work_u_fund_valid || (work_u_fund_mag == 17'd0) || (u_thd_root_reg == 23'd0);
                i_div_bypass <= !work_i_fund_valid || (work_i_fund_mag == 17'd0) || (i_thd_root_reg == 23'd0);
                u_div_start  <= work_u_fund_valid && (work_u_fund_mag != 17'd0) && (u_thd_root_reg != 23'd0);
                i_div_start  <= work_i_fund_valid && (work_i_fund_mag != 17'd0) && (i_thd_root_reg != 23'd0);
                state        <= ST_DIV_WAIT;
            end

            ST_DIV_WAIT: begin
                if (div_done_all)
                    state <= ST_COMMIT;
            end

            ST_COMMIT: begin
                if (u_div_bypass || u_div_zero) begin
                    thd_u_raw_x100 <= 32'd0;
                    thd_u_valid    <= work_u_fund_valid;
                end else if ((u_div_quotient[39:32] != 8'd0) || (u_div_quotient[31:0] > THD_CLIP_X100)) begin
                    thd_u_raw_x100 <= THD_CLIP_X100;
                    thd_u_valid    <= 1'b1;
                end else begin
                    thd_u_raw_x100 <= u_div_quotient[31:0];
                    thd_u_valid    <= 1'b1;
                end

                if (i_div_bypass || i_div_zero) begin
                    thd_i_raw_x100 <= 32'd0;
                    thd_i_valid    <= work_i_fund_valid;
                end else if ((i_div_quotient[39:32] != 8'd0) || (i_div_quotient[31:0] > THD_CLIP_X100)) begin
                    thd_i_raw_x100 <= THD_CLIP_X100;
                    thd_i_valid    <= 1'b1;
                end else begin
                    thd_i_raw_x100 <= i_div_quotient[31:0];
                    thd_i_valid    <= 1'b1;
                end

                done  <= 1'b1;
                state <= ST_IDLE;
            end

            default: begin
                state <= ST_IDLE;
            end
        endcase
    end
end

endmodule
