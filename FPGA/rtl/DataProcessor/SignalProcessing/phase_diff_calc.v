`timescale 1ns / 1ps

/*
 * 模块: phase_diff_calc
 * 功能:
 *   在同一采样窗口内检测电压和电流的过零时刻，
 *   根据两者的时间差和电压周期估算相位差，并输出带符号的 x100 结果及显示数字。
 *
 * 输入:
 *   clk: 系统时钟。
 *   rst_n: 低有效复位信号。
 *   start: 启动一次新的相位测量。
 *   sample_count_n: 本次测量使用的采样点数量。
 *   sample_valid: 当前拍输入采样有效。
 *   u_sample_code: 电压通道采样码值。
 *   u_zero_code: 电压通道零点参考码值。
 *   u_zero_valid: 电压零点参考是否有效。
 *   i_sample_code: 电流通道采样码值。
 *   i_zero_code: 电流通道零点参考码值。
 *   i_zero_valid: 电流零点参考是否有效。
 *
 * 输出:
 *   busy: 模块正在采样或换算相位时拉高。
 *   done: 本次相位测量完成脉冲。
 *   phase_neg: 相位符号位，1 表示负相位。
 *   phase_hundreds: 相位百位数字。
 *   phase_tens: 相位十位数字。
 *   phase_units: 相位个位数字。
 *   phase_decile: 相位十分位数字。
 *   phase_percentiles: 相位百分位数字。
 *   phase_x100_signed: 相位原始定点结果，缩放为 x100。
 *   phase_valid: 相位结果有效标志。
 */
module phase_diff_calc #(
    parameter integer WIDTH             = 16,
    parameter integer MAX_FRAME_SAMPLES = 4096,
    parameter integer N_WIDTH           = (MAX_FRAME_SAMPLES <= 2) ? 2 : $clog2(MAX_FRAME_SAMPLES)
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               start,
    input  wire [N_WIDTH-1:0] sample_count_n,
    input  wire               sample_valid,
    input  wire [WIDTH-1:0]   u_sample_code,
    input  wire [WIDTH-1:0]   u_zero_code,
    input  wire               u_zero_valid,
    input  wire [WIDTH-1:0]   i_sample_code,
    input  wire [WIDTH-1:0]   i_zero_code,
    input  wire               i_zero_valid,
    output reg                busy,
    output reg                done,
    output reg                phase_neg,
    output reg  [7:0]         phase_hundreds,
    output reg  [7:0]         phase_tens,
    output reg  [7:0]         phase_units,
    output reg  [7:0]         phase_decile,
    output reg  [7:0]         phase_percentiles,
    output reg  signed [16:0] phase_x100_signed,
    output reg                phase_valid
);

// 状态机：等待启动、采样找过零、启动除法、等待除法、提交相位结果。
localparam [2:0] ST_IDLE      = 3'd0;
localparam [2:0] ST_CAPTURE   = 3'd1;
localparam [2:0] ST_DIV_START = 3'd2;
localparam [2:0] ST_DIV_WAIT  = 3'd3;
localparam [2:0] ST_COMMIT    = 3'd4;

// 过零参考、迟滞阈值和相位量程常量。
localparam [WIDTH-1:0] CENTER_DEFAULT = {1'b1, {(WIDTH - 1){1'b0}}};
localparam integer     PHASE_HYST_INT = (WIDTH >= 8) ? (2 << (WIDTH - 8)) : 2;
localparam [WIDTH-1:0] PHASE_HYST     = PHASE_HYST_INT;
localparam [15:0]      DEG_180_X100   = 16'd18000;
localparam [15:0]      DEG_360_X100   = 16'd36000;

// 周期计数、过零检测和结果缓存寄存器。
reg  [2:0]            state;
reg  [N_WIDTH-1:0]    sample_target;
reg  [N_WIDTH-1:0]    sample_count;
reg  [31:0]           u_period_clk_cnt;
reg  [31:0]           i_since_cross_clk_cnt;
reg                   u_period_valid;
reg                   i_cross_valid;
reg                   u_trigger_armed;
reg                   i_trigger_armed;
reg                   u_cross_now;
reg                   i_cross_now;
reg                   phase_div_start;
reg  [47:0]           phase_dividend;
reg  [31:0]           phase_divisor;
reg                   phase_neg_next;
reg  [15:0]           phase_mag_x100_next;
reg  signed [16:0]    phase_x100_signed_next;
reg                   phase_valid_next;
reg  [31:0]           phase_digit_value;
reg  [7:0]            phase_hundreds_calc;
reg  [31:0]           phase_offset_clks;
reg  [15:0]           phase_mod_x100;
reg  [15:0]           phase_mag_x100;
reg                   current_neg_next;
integer               digit_idx;

// 零点门限、除法换算和数字拆分相关连线。
wire [WIDTH-1:0]      u_ref_code;
wire [WIDTH-1:0]      i_ref_code;
wire [WIDTH-1:0]      u_low;
wire [WIDTH-1:0]      u_high;
wire [WIDTH-1:0]      i_low;
wire [WIDTH-1:0]      i_high;
wire                  phase_div_done;
wire                  phase_div_zero;
wire [47:0]           phase_div_q;
wire [7:0]            phase_tens_calc;
wire [7:0]            phase_units_calc;
wire [7:0]            phase_decile_calc;
wire [7:0]            phase_percentiles_calc;

// 为电压和电流通道分别生成带迟滞的过零比较门限。
assign u_ref_code = u_zero_valid ? u_zero_code : CENTER_DEFAULT;
assign i_ref_code = i_zero_valid ? i_zero_code : CENTER_DEFAULT;
assign u_low  = (u_ref_code > PHASE_HYST) ? (u_ref_code - PHASE_HYST) : {WIDTH{1'b0}};
assign u_high = (u_ref_code < ({WIDTH{1'b1}} - PHASE_HYST)) ? (u_ref_code + PHASE_HYST) : {WIDTH{1'b1}};
assign i_low  = (i_ref_code > PHASE_HYST) ? (i_ref_code - PHASE_HYST) : {WIDTH{1'b0}};
assign i_high = (i_ref_code < ({WIDTH{1'b1}} - PHASE_HYST)) ? (i_ref_code + PHASE_HYST) : {WIDTH{1'b1}};

// 把过零时间差按 360 度比例换算成相位 x100。
divider_unsigned #(
    .WIDTH(48)
) u_phase_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (phase_div_start),
    .dividend      (phase_dividend),
    .divisor       ({16'd0, phase_divisor}),
    .busy          (),
    .done          (phase_div_done),
    .divide_by_zero(phase_div_zero),
    .quotient      (phase_div_q)
);

// 组合拆出相位百位，余下部分继续交给十进制拆分模块。
always @(*) begin
    phase_digit_value   = {16'd0, phase_mag_x100_next};
    phase_hundreds_calc = 8'd0;

    for (digit_idx = 0; digit_idx < 10; digit_idx = digit_idx + 1) begin
        if (phase_digit_value >= 32'd10000) begin
            phase_digit_value   = phase_digit_value - 32'd10000;
            phase_hundreds_calc = phase_hundreds_calc + 8'd1;
        end
    end
end

// 把相位幅值 x100 拆成十位、个位、十分位和百分位。
value_x100_to_digits u_phase_digits (
    .value_x100  (phase_digit_value),
    .tens        (phase_tens_calc),
    .units       (phase_units_calc),
    .decile      (phase_decile_calc),
    .percentiles (phase_percentiles_calc)
);

// 主状态机：先测电压周期，再结合电流过零时间差计算相位并提交结果。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state                <= ST_IDLE;
        sample_target        <= {N_WIDTH{1'b0}};
        sample_count         <= {N_WIDTH{1'b0}};
        u_period_clk_cnt     <= 32'd0;
        i_since_cross_clk_cnt<= 32'd0;
        u_period_valid       <= 1'b0;
        i_cross_valid        <= 1'b0;
        u_trigger_armed      <= 1'b0;
        i_trigger_armed      <= 1'b0;
        u_cross_now          <= 1'b0;
        i_cross_now          <= 1'b0;
        phase_div_start      <= 1'b0;
        phase_dividend       <= 48'd0;
        phase_divisor        <= 32'd1;
        phase_neg_next       <= 1'b0;
        phase_mag_x100_next  <= 16'd0;
        phase_x100_signed_next <= 17'sd0;
        phase_valid_next     <= 1'b0;
        busy                 <= 1'b0;
        done                 <= 1'b0;
        phase_neg            <= 1'b0;
        phase_hundreds       <= 8'd0;
        phase_tens           <= 8'd0;
        phase_units          <= 8'd0;
        phase_decile         <= 8'd0;
        phase_percentiles    <= 8'd0;
        phase_x100_signed    <= 17'sd0;
        phase_valid          <= 1'b0;
    end else begin
        done            <= 1'b0;
        phase_div_start <= 1'b0;

        case (state)
            ST_IDLE: begin
                // 等待 start，同时清空上一轮相位测量状态。
                busy <= 1'b0;

                if (start) begin
                    sample_target         <= sample_count_n;
                    sample_count          <= {N_WIDTH{1'b0}};
                    u_period_clk_cnt      <= 32'd0;
                    i_since_cross_clk_cnt <= 32'd0;
                    u_period_valid        <= 1'b0;
                    i_cross_valid         <= 1'b0;
                    u_trigger_armed       <= 1'b0;
                    i_trigger_armed       <= 1'b0;
                    phase_dividend        <= 48'd0;
                    phase_divisor         <= 32'd1;
                    phase_neg_next        <= 1'b0;
                    phase_mag_x100_next   <= 16'd0;
                    phase_x100_signed_next<= 17'sd0;
                    phase_valid_next      <= 1'b0;
                    phase_valid           <= 1'b0;

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
                // 在采样流中分别跟踪电压周期和电流相对电压的过零偏移。
                if (u_period_clk_cnt != 32'hFFFF_FFFF)
                    u_period_clk_cnt <= u_period_clk_cnt + 32'd1;

                if (i_cross_valid && (i_since_cross_clk_cnt != 32'hFFFF_FFFF))
                    i_since_cross_clk_cnt <= i_since_cross_clk_cnt + 32'd1;

                if (sample_valid) begin
                    u_cross_now = 1'b0;
                    i_cross_now = 1'b0;

                    if (u_sample_code <= u_low)
                        u_trigger_armed <= 1'b1;
                    else if (u_trigger_armed && (u_sample_code >= u_high)) begin
                        u_cross_now     = 1'b1;
                        u_trigger_armed <= 1'b0;
                    end

                    if (i_sample_code <= i_low)
                        i_trigger_armed <= 1'b1;
                    else if (i_trigger_armed && (i_sample_code >= i_high)) begin
                        i_cross_now     = 1'b1;
                        i_trigger_armed <= 1'b0;
                    end

                    if (i_cross_now) begin
                        i_since_cross_clk_cnt <= 32'd0;
                        i_cross_valid         <= 1'b1;
                    end

                    if (u_cross_now) begin
                        if (u_period_valid && (u_period_clk_cnt != 32'd0) && i_cross_valid) begin
                            phase_offset_clks = i_cross_now ? 32'd0 : i_since_cross_clk_cnt;
                            phase_dividend    <= ({16'd0, phase_offset_clks} << 15)
                                               + ({16'd0, phase_offset_clks} << 11)
                                               + ({16'd0, phase_offset_clks} << 10)
                                               + ({16'd0, phase_offset_clks} << 7)
                                               + ({16'd0, phase_offset_clks} << 5);
                            phase_divisor     <= u_period_clk_cnt;
                            u_period_clk_cnt  <= 32'd0;
                            u_period_valid    <= 1'b1;
                            state             <= ST_DIV_START;
                        end else begin
                            u_period_clk_cnt <= 32'd0;
                            u_period_valid   <= 1'b1;
                        end
                    end

                    if (sample_count == (sample_target - 1'b1)) begin
                        if (!(u_cross_now && u_period_valid && i_cross_valid && (u_period_clk_cnt != 32'd0))) begin
                            busy       <= 1'b0;
                            done       <= 1'b1;
                            phase_valid<= 1'b0;
                            state      <= ST_IDLE;
                        end
                        sample_count <= {N_WIDTH{1'b0}};
                    end else begin
                        sample_count <= sample_count + {{(N_WIDTH - 1){1'b0}}, 1'b1};
                    end
                end
            end

            ST_DIV_START: begin
                // 发出一次除法启动脉冲，准备把时间差换算成角度。
                phase_div_start <= 1'b1;
                state           <= ST_DIV_WAIT;
            end

            ST_DIV_WAIT: begin
                // 等待除法器完成，并把结果折算到 [-180.00, +180.00] 范围内。
                if (phase_div_done) begin
                    if (phase_div_zero) begin
                        phase_neg_next         <= 1'b0;
                        phase_mag_x100_next    <= 16'd0;
                        phase_x100_signed_next <= 17'sd0;
                        phase_valid_next       <= 1'b0;
                    end else begin
                        phase_mod_x100 = phase_div_q[15:0];

                        if (phase_mod_x100 > DEG_180_X100) begin
                            phase_mag_x100   = DEG_360_X100 - phase_mod_x100;
                            current_neg_next = 1'b1;
                        end else begin
                            phase_mag_x100   = phase_mod_x100;
                            current_neg_next = 1'b0;
                        end

                        if (phase_mag_x100 == 16'd0)
                            phase_neg_next = 1'b0;
                        else
                            phase_neg_next = ~current_neg_next;

                        phase_mag_x100_next <= phase_mag_x100;
                        if (phase_neg_next)
                            phase_x100_signed_next <= ~{1'b0, phase_mag_x100} + 17'd1;
                        else
                            phase_x100_signed_next <= {1'b0, phase_mag_x100};
                        phase_valid_next <= 1'b1;
                    end
                    state <= ST_COMMIT;
                end
            end

            ST_COMMIT: begin
                // 提交相位符号、显示数字和带符号原始定点值。
                phase_neg         <= phase_neg_next;
                phase_hundreds    <= phase_hundreds_calc;
                phase_tens        <= phase_tens_calc;
                phase_units       <= phase_units_calc;
                phase_decile      <= phase_decile_calc;
                phase_percentiles <= phase_percentiles_calc;
                phase_x100_signed <= phase_x100_signed_next;
                phase_valid       <= phase_valid_next;
                busy              <= 1'b0;
                done              <= 1'b1;
                state             <= ST_IDLE;
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
