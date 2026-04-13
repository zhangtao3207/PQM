`timescale 1ns / 1ps

/*
 * 模块: p2p_measure
 * 功能:
 *   在指定采样窗口内统计输入波形的最大码值和最小码值，
 *   将两者之差换算为峰峰值，并输出供显示使用的十进制数字。
 *
 * 输入:
 *   clk: 系统时钟。
 *   rst_n: 低有效复位信号。
 *   start: 启动一次新的峰峰值测量。
 *   sample_count_n: 本次测量使用的采样点数量。
 *   sample_valid: 当前拍 sample_code 有效。
 *   sample_code: 待测波形采样码值。
 *
 * 输出:
 *   busy: 模块正在采样或换算结果时拉高。
 *   done: 本次峰峰值测量完成脉冲。
 *   p2p_tens: 峰峰值十位数字。
 *   p2p_units: 峰峰值个位数字。
 *   p2p_decile: 峰峰值十分位数字。
 *   p2p_percentiles: 峰峰值百分位数字。
 *   p2p_digits_valid: 峰峰值显示数字有效标志。
 * 结果格式:
 *   四个数字共同表示 xx.xx。
 */
module p2p_measure #(
    parameter integer WIDTH             = 16,
    parameter integer MAX_FRAME_SAMPLES = 4096,
    parameter integer N_WIDTH           = (MAX_FRAME_SAMPLES <= 2) ? 2 : $clog2(MAX_FRAME_SAMPLES),
    parameter integer FULL_SCALE_X100   = 1000
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               start,
    input  wire [N_WIDTH-1:0] sample_count_n,
    input  wire               sample_valid,
    input  wire [WIDTH-1:0]   sample_code,
    output reg                busy,
    output reg                done,
    output reg  [7:0]         p2p_tens,
    output reg  [7:0]         p2p_units,
    output reg  [7:0]         p2p_decile,
    output reg  [7:0]         p2p_percentiles,
    output reg                p2p_digits_valid
);

// 状态机：等待启动、采样找极值、启动除法、等待除法、提交数字结果。
localparam [2:0] ST_IDLE      = 3'd0;
localparam [2:0] ST_CAPTURE   = 3'd1;
localparam [2:0] ST_DIV_START = 3'd2;
localparam [2:0] ST_DIV_WAIT  = 3'd3;
localparam [2:0] ST_COMMIT    = 3'd4;

// 把峰峰码值差换算成实际量程时使用的缩放常量和显示上限。
localparam [31:0] HALF_SCALE_CODE = 32'd1 << (WIDTH - 1);
localparam [31:0] ROUND_BIAS      = HALF_SCALE_CODE >> 1;
localparam [31:0] VALUE_CLIP_X100 = 32'd9999;

// 采样窗口、极值跟踪和结果缓存寄存器。
reg  [2:0]          state;
reg  [N_WIDTH-1:0]  sample_target;
reg  [N_WIDTH-1:0]  sample_count;
reg  [WIDTH-1:0]    min_code;
reg  [WIDTH-1:0]    max_code;
reg                 seen_sample;
reg                 p2p_div_start;
reg                 p2p_valid_next;
reg  [31:0]         p2p_x100_reg;

// 峰峰值缩放、除法换算和数字拆分相关连线。
wire [WIDTH:0]      p2p_diff_unsigned;
wire signed [63:0]  p2p_scale_product_signed;
wire [63:0]         p2p_scale_product_unsigned;
wire                p2p_div_done;
wire                p2p_div_zero;
wire [63:0]         p2p_div_quotient;
wire [7:0]          p2p_tens_wire;
wire [7:0]          p2p_units_wire;
wire [7:0]          p2p_decile_wire;
wire [7:0]          p2p_percentiles_wire;

// 组合得到峰峰码值差，并屏蔽乘法器可能产生的负值。
assign p2p_diff_unsigned = {1'b0, max_code} - {1'b0, min_code};
assign p2p_scale_product_unsigned = p2p_scale_product_signed[63] ? 64'd0 : p2p_scale_product_signed[63:0];

// 将峰峰码值差乘以满量程系数，得到后续除法所需的被除数。
multiplier_signed #(
    .A_WIDTH(32),
    .B_WIDTH(32)
) u_p2p_scale_multiplier (
    .multiplicand({{(32 - (WIDTH + 1)){1'b0}}, p2p_diff_unsigned}),
    .multiplier  (FULL_SCALE_X100),
    .product     (p2p_scale_product_signed)
);

// 用无符号除法器完成量程归一化，并通过加半个除数实现四舍五入。
divider_unsigned #(
    .WIDTH(64)
) u_p2p_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (p2p_div_start),
    .dividend      (p2p_scale_product_unsigned + {32'd0, ROUND_BIAS}),
    .divisor       ({32'd0, HALF_SCALE_CODE}),
    .busy          (),
    .done          (p2p_div_done),
    .divide_by_zero(p2p_div_zero),
    .quotient      (p2p_div_quotient)
);

// 把峰峰值 x100 结果拆成显示使用的十进制数字。
value_x100_to_digits u_p2p_digits (
    .value_x100  (p2p_x100_reg),
    .tens        (p2p_tens_wire),
    .units       (p2p_units_wire),
    .decile      (p2p_decile_wire),
    .percentiles (p2p_percentiles_wire)
);

// 主状态机：采样窗口内更新极值，结束后完成峰峰值换算并提交显示数字。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state            <= ST_IDLE;
        sample_target    <= {N_WIDTH{1'b0}};
        sample_count     <= {N_WIDTH{1'b0}};
        min_code         <= {WIDTH{1'b1}};
        max_code         <= {WIDTH{1'b0}};
        seen_sample      <= 1'b0;
        p2p_div_start    <= 1'b0;
        p2p_valid_next   <= 1'b0;
        p2p_x100_reg     <= 32'd0;
        busy             <= 1'b0;
        done             <= 1'b0;
        p2p_tens         <= 8'd0;
        p2p_units        <= 8'd0;
        p2p_decile       <= 8'd0;
        p2p_percentiles  <= 8'd0;
        p2p_digits_valid <= 1'b0;
    end else begin
        done          <= 1'b0;
        p2p_div_start <= 1'b0;

        case (state)
            ST_IDLE: begin
                // 等待 start，同时清空上一轮测量残留状态。
                busy <= 1'b0;

                if (start) begin
                    sample_target    <= sample_count_n;
                    sample_count     <= {N_WIDTH{1'b0}};
                    min_code         <= {WIDTH{1'b1}};
                    max_code         <= {WIDTH{1'b0}};
                    seen_sample      <= 1'b0;
                    p2p_valid_next   <= 1'b0;
                    p2p_x100_reg     <= 32'd0;
                    p2p_digits_valid <= 1'b0;

                    if (sample_count_n == {N_WIDTH{1'b0}}) begin
                        done  <= 1'b1;
                        state <= ST_IDLE;
                    end else begin
                        busy  <= 1'b1;
                        state <= ST_CAPTURE;
                    end
                end
            end

            ST_CAPTURE: begin
                // 在 sample_valid 有效的窗口内持续更新最大值和最小值。
                if (sample_valid) begin
                    if (!seen_sample) begin
                        min_code    <= sample_code;
                        max_code    <= sample_code;
                        seen_sample <= 1'b1;
                    end else begin
                        if (sample_code < min_code)
                            min_code <= sample_code;
                        if (sample_code > max_code)
                            max_code <= sample_code;
                    end

                    if (sample_count == (sample_target - 1'b1)) begin
                        if (seen_sample || (sample_count_n != {N_WIDTH{1'b0}}))
                            state <= ST_DIV_START;
                        else begin
                            busy             <= 1'b0;
                            done             <= 1'b1;
                            p2p_digits_valid <= 1'b0;
                            state            <= ST_IDLE;
                        end
                        sample_count <= {N_WIDTH{1'b0}};
                    end else begin
                        sample_count <= sample_count + {{(N_WIDTH - 1){1'b0}}, 1'b1};
                    end
                end
            end

            ST_DIV_START: begin
                // 发出一次除法启动脉冲，准备把码值差换算为峰峰值。
                p2p_div_start <= 1'b1;
                state         <= ST_DIV_WAIT;
            end

            ST_DIV_WAIT: begin
                // 等待除法器完成，并把结果限制到 99.99 的显示范围内。
                if (p2p_div_done) begin
                    if (p2p_div_zero) begin
                        p2p_x100_reg   <= 32'd0;
                        p2p_valid_next <= 1'b0;
                    end else if ((p2p_div_quotient[63:32] != 32'd0) ||
                                 (p2p_div_quotient[31:0] > VALUE_CLIP_X100)) begin
                        p2p_x100_reg   <= VALUE_CLIP_X100;
                        p2p_valid_next <= 1'b1;
                    end else begin
                        p2p_x100_reg   <= p2p_div_quotient[31:0];
                        p2p_valid_next <= 1'b1;
                    end
                    state <= ST_COMMIT;
                end
            end

            ST_COMMIT: begin
                // 提交拆好的十进制数字，并对外声明本轮结果有效。
                p2p_tens         <= p2p_tens_wire;
                p2p_units        <= p2p_units_wire;
                p2p_decile       <= p2p_decile_wire;
                p2p_percentiles  <= p2p_percentiles_wire;
                p2p_digits_valid <= p2p_valid_next;
                busy             <= 1'b0;
                done             <= 1'b1;
                state            <= ST_IDLE;
            end

            default: begin
                busy  <= 1'b0;
                done  <= 1'b0;
                state <= ST_IDLE;
            end
        endcase
    end
end

endmodule
