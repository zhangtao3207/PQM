`timescale 1ns / 1ps

/*
 * 模块: frequency_measure
 * 功能:
 *   在一次采样窗口内检测同向过零点，测出相邻两次有效过零之间的 clk 周期数，
 *   再换算为带两位小数的频率结果，供后级显示链路直接使用。
 *
 * 输入:
 *   clk: 系统时钟，同时作为周期计数基准。
 *   rst_n: 低有效复位信号。
 *   start: 启动一次新的频率测量。
 *   sample_count_n: 本次测量允许处理的采样点数量。
 *   sample_valid: 当前拍 sample_code 有效。
 *   sample_code: 待测波形的采样码值。
 *   zero_code: 外部提供的零点/中心码值。
 *   zero_valid: 为 1 时使用 zero_code 作为过零参考，否则退回默认中心码。
 *
 * 输出:
 *   busy: 模块正在采样或换算频率时拉高。
 *   done: 本次测量结束脉冲。
 *   freq_hundreds: 频率百位数字。
 *   freq_tens: 频率十位数字。
 *   freq_units: 频率个位数字。
 *   freq_decile: 频率十分位数字。
 *   freq_percentiles: 频率百分位数字。
 *   freq_valid: 频率结果有效标志；为 0 表示窗口内未成功测到完整周期。
 *
 * 结果格式:
 *   五个数字共同表示 xxx.xx Hz，例如 50.00 Hz 对应 0, 5, 0, 0, 0。
 */
module frequency_measure #(
    parameter integer WIDTH             = 16,
    parameter integer MAX_FRAME_SAMPLES = 4096,
    parameter integer N_WIDTH           = (MAX_FRAME_SAMPLES <= 2) ? 2 : $clog2(MAX_FRAME_SAMPLES),
    parameter [39:0]  CLK_FREQ_X100     = 40'd5000000000
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             start,
    input  wire [N_WIDTH-1:0] sample_count_n,
    input  wire             sample_valid,
    input  wire [WIDTH-1:0] sample_code,
    input  wire [WIDTH-1:0] zero_code,
    input  wire             zero_valid,

    output reg              busy,
    output reg              done,
    output reg  [7:0]       freq_hundreds,
    output reg  [7:0]       freq_tens,
    output reg  [7:0]       freq_units,
    output reg  [7:0]       freq_decile,
    output reg  [7:0]       freq_percentiles,
    output reg              freq_valid
);

// 状态机：等待启动、采样找周期、启动除法、等待除法、提交结果。
localparam [2:0] ST_IDLE      = 3'd0;
localparam [2:0] ST_CAPTURE   = 3'd1;
localparam [2:0] ST_DIV_START = 3'd2;
localparam [2:0] ST_DIV_WAIT  = 3'd3;
localparam [2:0] ST_COMMIT    = 3'd4;

// 过零检测与结果裁剪相关常量：默认中心码、迟滞宽度和最大显示值 999.99 Hz。
localparam [WIDTH-1:0] CENTER_DEFAULT = {1'b1, {(WIDTH - 1){1'b0}}};
localparam integer     FREQ_HYST_INT  = (WIDTH >= 8) ? (2 << (WIDTH - 8)) : 2;
localparam [WIDTH-1:0] FREQ_HYST      = FREQ_HYST_INT;
localparam [31:0]      VALUE_CLIP_X100 = 32'd99999;

// 采样窗口、周期计数和结果缓存寄存器。
reg  [2:0]            state;
reg  [N_WIDTH-1:0]    sample_target;
reg  [N_WIDTH-1:0]    sample_count;
reg  [31:0]           period_clk_cnt;
reg  [31:0]           period_clk_latched;
reg                   trigger_armed;
reg                   first_cross_seen;
reg                   freq_div_start;
reg                   freq_valid_next;
reg  [31:0]           freq_x100_reg;
reg  [31:0]           freq_digit_value;
reg  [7:0]            freq_hundreds_calc;
reg                   cross_now;
integer               digit_idx;

// 过零参考、带迟滞门限以及频率换算/拆位相关连线。
wire [WIDTH-1:0]      ref_code;
wire [WIDTH-1:0]      code_low;
wire [WIDTH-1:0]      code_high;
wire                  freq_div_done;
wire                  freq_div_zero;
wire [63:0]           freq_div_quotient;
wire [7:0]            freq_tens_calc;
wire [7:0]            freq_units_calc;
wire [7:0]            freq_decile_calc;
wire [7:0]            freq_percentiles_calc;

// 生成带迟滞的过零比较门限，避免采样值在零点附近抖动时重复触发。
assign ref_code = zero_valid ? zero_code : CENTER_DEFAULT;
assign code_low  = (ref_code > FREQ_HYST) ? (ref_code - FREQ_HYST) : {WIDTH{1'b0}};
assign code_high = (ref_code < ({WIDTH{1'b1}} - FREQ_HYST)) ? (ref_code + FREQ_HYST) : {WIDTH{1'b1}};

// 调用无符号除法器，把一个周期对应的 clk 计数换算为频率 x100，并通过加半个除数实现四舍五入。
divider_unsigned #(
    .WIDTH(64)
) u_frequency_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (freq_div_start),
    .dividend      ({24'd0, CLK_FREQ_X100} + {32'd0, period_clk_latched[31:1]}),
    .divisor       ({32'd0, period_clk_latched}),
    .busy          (),
    .done          (freq_div_done),
    .divide_by_zero(freq_div_zero),
    .quotient      (freq_div_quotient)
);

// 组合拆出频率百位，剩余部分保持 x100 形式，交给后级模块继续拆位。
always @(*) begin
    freq_digit_value   = freq_x100_reg;
    freq_hundreds_calc = 8'd0;

    for (digit_idx = 0; digit_idx < 10; digit_idx = digit_idx + 1) begin
        if (freq_digit_value >= 32'd10000) begin
            freq_digit_value   = freq_digit_value - 32'd10000;
            freq_hundreds_calc = freq_hundreds_calc + 8'd1;
        end
    end
end

// 把去掉百位后的频率 x100 结果拆成十位、个位、十分位和百分位。
value_x100_to_digits u_frequency_digits (
    .value_x100  (freq_digit_value),
    .tens        (freq_tens_calc),
    .units       (freq_units_calc),
    .decile      (freq_decile_calc),
    .percentiles (freq_percentiles_calc)
);

// 主状态机：在采样窗口内寻找两次同向过零，锁存周期计数，完成频率换算并提交显示数字。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state            <= ST_IDLE;
        sample_target    <= {N_WIDTH{1'b0}};
        sample_count     <= {N_WIDTH{1'b0}};
        period_clk_cnt   <= 32'd0;
        period_clk_latched<= 32'd0;
        trigger_armed    <= 1'b0;
        first_cross_seen <= 1'b0;
        freq_div_start   <= 1'b0;
        freq_valid_next  <= 1'b0;
        freq_x100_reg    <= 32'd0;
        busy             <= 1'b0;
        done             <= 1'b0;
        freq_hundreds    <= 8'd0;
        freq_tens        <= 8'd0;
        freq_units       <= 8'd0;
        freq_decile      <= 8'd0;
        freq_percentiles <= 8'd0;
        freq_valid       <= 1'b0;
    end else begin
        done           <= 1'b0;
        freq_div_start <= 1'b0;

        case (state)
            ST_IDLE: begin
                // 等待 start，同时清空上一次测量残留状态。
                busy <= 1'b0;

                if (start) begin
                    sample_target     <= sample_count_n;
                    sample_count      <= {N_WIDTH{1'b0}};
                    period_clk_cnt    <= 32'd0;
                    period_clk_latched<= 32'd0;
                    trigger_armed     <= 1'b0;
                    first_cross_seen  <= 1'b0;
                    freq_valid_next   <= 1'b0;
                    freq_x100_reg     <= 32'd0;
                    freq_valid        <= 1'b0;

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
                // 在 sample_valid 有效的采样流中查找两次由低门限到高门限的过零事件。
                if (period_clk_cnt != 32'hFFFF_FFFF)
                    period_clk_cnt <= period_clk_cnt + 32'd1;

                if (sample_valid) begin
                    cross_now = 1'b0;

                    if (sample_code <= code_low)
                        trigger_armed <= 1'b1;
                    else if (trigger_armed && (sample_code >= code_high)) begin
                        cross_now     = 1'b1;
                        trigger_armed <= 1'b0;
                    end

                    if (cross_now) begin
                        if (!first_cross_seen) begin
                            first_cross_seen <= 1'b1;
                            period_clk_cnt   <= 32'd0;
                        end else begin
                            period_clk_latched <= period_clk_cnt;
                            state             <= ST_DIV_START;
                        end
                    end

                    if (sample_count == (sample_target - 1'b1)) begin
                        if (!cross_now || !first_cross_seen) begin
                            busy       <= 1'b0;
                            done       <= 1'b1;
                            freq_valid <= 1'b0;
                            state      <= ST_IDLE;
                        end
                        sample_count <= {N_WIDTH{1'b0}};
                    end else begin
                        sample_count <= sample_count + {{(N_WIDTH - 1){1'b0}}, 1'b1};
                    end
                end
            end

            ST_DIV_START: begin
                // 发出一次除法启动脉冲，准备把周期计数转换为频率值。
                freq_div_start <= 1'b1;
                state          <= ST_DIV_WAIT;
            end

            ST_DIV_WAIT: begin
                // 等待除法器完成，并把结果限制在显示上限 999.99 Hz 以内。
                if (freq_div_done) begin
                    if (freq_div_zero) begin
                        freq_x100_reg   <= 32'd0;
                        freq_valid_next <= 1'b0;
                    end else if ((freq_div_quotient[63:32] != 32'd0) ||
                                 (freq_div_quotient[31:0] > VALUE_CLIP_X100)) begin
                        freq_x100_reg   <= VALUE_CLIP_X100;
                        freq_valid_next <= 1'b1;
                    end else begin
                        freq_x100_reg   <= freq_div_quotient[31:0];
                        freq_valid_next <= 1'b1;
                    end
                    state <= ST_COMMIT;
                end
            end

            ST_COMMIT: begin
                // 提交拆好的十进制数字，并用 done/freq_valid 对外宣布本次测量结果。
                freq_hundreds    <= freq_hundreds_calc;
                freq_tens        <= freq_tens_calc;
                freq_units       <= freq_units_calc;
                freq_decile      <= freq_decile_calc;
                freq_percentiles <= freq_percentiles_calc;
                freq_valid       <= freq_valid_next;
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
