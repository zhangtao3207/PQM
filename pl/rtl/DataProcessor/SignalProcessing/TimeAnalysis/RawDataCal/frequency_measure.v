`timescale 1ns / 1ps

/*
 * 模块: frequency_measure
 * 功能:
 *   在一次采样窗口内用带迟滞的施密特判据检测 U1 信号的正向过零事件，
 *   对每次过零在「最近一个低于零点参考的采样点」与「本次越过上门限的采样点」之间
 *   做线性插值，得到亚采样精度的过零时刻；再用
 *      一个基波周期 = (末次过零时刻 - 首次过零时刻) / 过零周期数
 *   求出基波周期的时钟计数，作为 freq_period_raw 输出，供上层换算为频率 x100。
 *
 * 为什么不再找峰值（本模块的历史缺陷）:
 *   旧实现是「半周内找最大值当峰、测峰-峰间隔」。它有两个互相错开的门限参考系：
 *   武装用零点 ref_code，峰值确认用「峰顶 - FREQ_HYST」。当"从峰顶回落超过迟滞"
 *   恰好落在过零点附近时，确认时刻被推迟到零点，而零点又是武装事件发生的同一拍，
 *   两者互相吞掉，于是有概率整个半周不出峰、读数在真值与 2 倍附近随机跳
 *   （板上实测：信号源稳定 50 Hz 时读数在 52~85 Hz 之间跳）。
 *   正向过零事件在每个基波周期必然发生且只发生一次，没有"跳过"的余地；
 *   而且"首末过零差分"会把 AM / 谐波 / 直流引起的固定相位偏移整体抵消掉。
 *
 * 算法:
 *   1) 施密特判据（迟滞 ±FREQ_HYST，参考 ref_code = zero_valid ? zero_code : 中心码）:
 *        code <= ref - HYST          -> 置 armed（确认信号确实在参考点下方）
 *        armed 且 code >= ref + HYST -> 判为一次正向过零，清 armed
 *      要求先 armed 才开始找过零，所以窗口开头那半周不完整的过零不会被误判。
 *   2) 线性插值: 记 anchor = 最近一个 code < ref 的采样点（时刻 a_clk、码 a_code），
 *      过零落在 anchor 与当前采样点 c 之间，取
 *          frac = (ref - a_code) / (c_code - a_code)
 *          t_cross = a_clk + (c_clk - a_clk) * frac
 *      由于 c_code >= ref + HYST 且 a_code <= ref - 1，必有
 *          分母 >= HYST + 1 > 0、分子 ∈ [1, ref]，且 分子 < 分母，
 *      所以插值不会退化——噪声让相邻两采样值互相靠拢也不会出现除零/溢出。
 *      frac 用 FRAC_BITS 位定点小数表示，由逐位长除法产生。
 *   3) 窗口内只保留「首次」与「末次」两次过零的四元组（anchor码/锚点拍号/过零码/过零拍号）。
 *      窗口结束后用同一个移位-相减除法器依次算:
 *          frac_first -> t_first, frac_last -> t_last, (t_last - t_first) / (N-1) -> 周期
 *   4) 过零次数 < 2 或时间差非正 -> 只给 done，不给 freq_valid。
 *
 * 输入:
 *   clk: 工作时钟。
 *   rst_n: 低有效复位。
 *   start: 启动一次频率测量。
 *   sample_count_n: 本次测量允许处理的采样点数。
 *   sample_valid: 当前采样是否有效。
 *   sample_code: 当前U1采样码值。
 *   zero_code: 过零参考零点码值。
 *   zero_valid: 参考零点码值是否有效。
 * 输出:
 *   busy: 当前频率测量流程是否仍在进行（含窗口结束后的三次除法）。
 *   done: 本次测量结束时给出的完成脉冲。
 *   freq_period_raw: 一个基波周期的时钟计数原始值，统一扩展为 32 位补码。
 *   freq_valid: 本次原始周期结果是否有效。
 */
module frequency_measure #(
    parameter integer WIDTH             = 16,
    parameter integer MAX_FRAME_SAMPLES = 4096,
    parameter integer N_WIDTH           = (MAX_FRAME_SAMPLES <= 2) ? 2 : $clog2(MAX_FRAME_SAMPLES)
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               start,
    input  wire [N_WIDTH-1:0] sample_count_n,
    input  wire               sample_valid,
    input  wire [WIDTH-1:0]   sample_code,
    input  wire [WIDTH-1:0]   zero_code,
    input  wire               zero_valid,

    output reg                busy,
    output reg                done,
    output reg  signed [31:0] freq_period_raw,
    output reg                freq_valid
);

localparam [3:0] ST_IDLE    = 4'd0;
localparam [3:0] ST_CAPTURE = 4'd1;
localparam [3:0] ST_CALC    = 4'd2;

// 插值小数的位宽。12 位把"一个采样间隔"细分到 1/4096：
// 真机 1953.125 拍/采样时约 0.48 拍（≈10 ns），远小于本测量的误差预算。
localparam integer FRAC_BITS = 12;

localparam [WIDTH-1:0] CENTER_DEFAULT = {1'b1, {(WIDTH - 1){1'b0}}};
localparam integer     FREQ_HYST_INT  = (WIDTH >= 8) ? (2 << (WIDTH - 8)) : 2;
localparam [WIDTH-1:0] FREQ_HYST      = FREQ_HYST_INT;

// 运算中间量的位宽：时间差最多取 18 位（真机 262143 拍 ≈ 134 个采样间隔，够用），
// 乘上 13 位小数后仍在 31 位内，不需要更宽的乘法器。
localparam integer DT_WIDTH = 18;

reg  [3:0]            state;
reg  [N_WIDTH-1:0]    sample_target;
reg  [N_WIDTH-1:0]    sample_count;
reg  [31:0]           sample_clk_cnt;

reg  [WIDTH-1:0]      below_code;      // 最近一个 code < ref 的采样码
reg  [31:0]           below_clk;       // 它的采样时刻
reg                   armed;
reg  [15:0]           cross_count;
reg                   first_seen;

// 首次 / 末次过零的四元组
reg  [WIDTH:0]        first_num;       // ref - anchor_code
reg  [WIDTH:0]        first_den;       // cur_code - anchor_code
reg  [31:0]           first_a_clk;
reg  [DT_WIDTH-1:0]   first_dt;        // cur_clk - anchor_clk
reg  [WIDTH:0]        last_num;
reg  [WIDTH:0]        last_den;
reg  [31:0]           last_a_clk;
reg  [DT_WIDTH-1:0]   last_dt;

// 除法器：dividend(WIDTH 32) / divisor(17 位)，逐位移位-相减，32 拍出商。
reg  [31:0]           div_dividend_in;
reg  [16:0]           div_divisor_in;
reg  [31:0]           div_dividend;
reg  [16:0]           div_divisor;
reg  [16:0]           div_rem;
reg  [31:0]           div_quot;
reg  [5:0]            div_cnt;
reg                   div_start;
reg                   div_busy;
reg                   div_done;

// 窗口结束后的计算流程
reg  [2:0]            calc_step;
reg  [12:0]           frac_first;
reg  [12:0]           frac_last;
reg  [31:0]           t_first;

wire [WIDTH-1:0]      ref_code;
wire [WIDTH-1:0]      code_low;
wire [WIDTH-1:0]      code_high;

// 除法器本体
wire [17:0]           div_shifted;
wire [17:0]           div_sub;
wire                  div_ge;

// 插值组合逻辑（本次过零的候选取值）
wire [WIDTH:0]        cross_num_now;
wire [WIDTH:0]        cross_den_now;
wire [31:0]           cross_dt_now;

// 计算用组合逻辑
wire [30:0]           first_prod;
wire [DT_WIDTH-1:0]   first_corr;
wire [31:0]           t_first_next;
wire [30:0]           last_prod;
wire [DT_WIDTH-1:0]   last_corr;
wire [31:0]           t_last_next;
wire [31:0]           delta_next;
wire [16:0]           periods_next;

// 基于零点参考构造带迟滞的过零门限；参考无效时退回码值中心。
assign ref_code  = zero_valid ? zero_code : CENTER_DEFAULT;
assign code_low  = (ref_code > FREQ_HYST) ? (ref_code - FREQ_HYST) : {WIDTH{1'b0}};
assign code_high = (ref_code < ({WIDTH{1'b1}} - FREQ_HYST)) ?
                   (ref_code + FREQ_HYST) : {WIDTH{1'b1}};

// 本次过零的插值参数：anchor 一定在参考点下方，当前采样一定在上门限上方，
// 所以分子恒为正、分母 >= HYST + 1，插值不会退化。
assign cross_num_now = {1'b0, ref_code} - {1'b0, below_code};
assign cross_den_now = {1'b0, sample_code} - {1'b0, below_code};
assign cross_dt_now  = sample_clk_cnt - below_clk;

// 逐位长除法：32 拍得到 div_dividend / div_divisor 的商。
assign div_shifted = {div_rem, div_dividend[31]};
assign div_sub     = div_shifted - {1'b0, div_divisor};
assign div_ge      = (div_shifted >= {1'b0, div_divisor});

// 定点插值：corr = (dt * frac) >> FRAC_BITS
assign first_prod    = first_dt * frac_first;
assign first_corr    = first_prod[FRAC_BITS+DT_WIDTH-1:FRAC_BITS];
assign t_first_next  = first_a_clk + {{(32-DT_WIDTH){1'b0}}, first_corr};
assign last_prod     = last_dt * frac_last;
assign last_corr     = last_prod[FRAC_BITS+DT_WIDTH-1:FRAC_BITS];
assign t_last_next   = last_a_clk + {{(32-DT_WIDTH){1'b0}}, last_corr};
assign delta_next    = t_last_next - t_first;
assign periods_next  = {1'b0, cross_count} - 17'd1;

// 除法器：load 一拍，之后 32 拍移位-相减，最后给出一拍 div_done。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        div_dividend <= 32'd0;
        div_divisor  <= 17'd0;
        div_rem      <= 17'd0;
        div_quot     <= 32'd0;
        div_cnt      <= 6'd0;
        div_busy     <= 1'b0;
        div_done     <= 1'b0;
    end else begin
        div_done <= 1'b0;

        if (div_start) begin
            div_dividend <= div_dividend_in;
            div_divisor  <= div_divisor_in;
            div_rem      <= 17'd0;
            div_quot     <= 32'd0;
            div_cnt      <= 6'd0;
            div_busy     <= 1'b1;
        end else if (div_busy) begin
            div_rem      <= div_ge ? div_sub[16:0] : div_shifted[16:0];
            div_quot     <= {div_quot[30:0], div_ge};
            div_dividend <= {div_dividend[30:0], 1'b0};

            if (div_cnt == 6'd31) begin
                div_busy <= 1'b0;
                div_done <= 1'b1;
            end else begin
                div_cnt <= div_cnt + 6'd1;
            end
        end
    end
end

// 采样窗口内追踪过零事件；窗口结束后集中算插值时刻与周期。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state            <= ST_IDLE;
        sample_target    <= {N_WIDTH{1'b0}};
        sample_count     <= {N_WIDTH{1'b0}};
        sample_clk_cnt   <= 32'd0;
        below_code       <= {WIDTH{1'b0}};
        below_clk        <= 32'd0;
        armed            <= 1'b0;
        cross_count      <= 16'd0;
        first_seen       <= 1'b0;
        first_num        <= {(WIDTH + 1){1'b0}};
        first_den        <= {(WIDTH + 1){1'b0}};
        first_a_clk      <= 32'd0;
        first_dt         <= {DT_WIDTH{1'b0}};
        last_num         <= {(WIDTH + 1){1'b0}};
        last_den         <= {(WIDTH + 1){1'b0}};
        last_a_clk       <= 32'd0;
        last_dt          <= {DT_WIDTH{1'b0}};
        div_dividend_in  <= 32'd0;
        div_divisor_in   <= 17'd0;
        div_start        <= 1'b0;
        calc_step        <= 3'd0;
        frac_first       <= 13'd0;
        frac_last        <= 13'd0;
        t_first          <= 32'd0;
        busy             <= 1'b0;
        done             <= 1'b0;
        freq_period_raw  <= 32'sd0;
        freq_valid       <= 1'b0;
    end else begin
        done       <= 1'b0;
        freq_valid <= 1'b0;

        case (state)
            ST_IDLE: begin
                busy <= 1'b0;

                if (start) begin
                    sample_target  <= sample_count_n;
                    sample_count   <= {N_WIDTH{1'b0}};
                    sample_clk_cnt <= 32'd0;
                    below_code     <= {WIDTH{1'b0}};
                    below_clk      <= 32'd0;
                    armed          <= 1'b0;
                    cross_count    <= 16'd0;
                    first_seen     <= 1'b0;
                    first_num      <= {(WIDTH + 1){1'b0}};
                    first_den      <= {(WIDTH + 1){1'b0}};
                    first_a_clk    <= 32'd0;
                    first_dt       <= {DT_WIDTH{1'b0}};
                    last_num       <= {(WIDTH + 1){1'b0}};
                    last_den       <= {(WIDTH + 1){1'b0}};
                    last_a_clk     <= 32'd0;
                    last_dt        <= {DT_WIDTH{1'b0}};
                    div_start      <= 1'b0;
                    calc_step      <= 3'd0;

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
                if (sample_clk_cnt != 32'hFFFF_FFFF)
                    sample_clk_cnt <= sample_clk_cnt + 32'd1;

                if (sample_valid) begin
                    // 锚点：最近一个严格低于参考点的采样
                    if (sample_code < ref_code) begin
                        below_code <= sample_code;
                        below_clk  <= sample_clk_cnt;
                    end

                    // 施密特判据：先武装，再判正向过零
                    if (armed && (sample_code >= code_high)) begin
                        armed <= 1'b0;
                        cross_count <= cross_count + 16'd1;

                        last_num   <= cross_num_now;
                        last_den   <= cross_den_now;
                        last_a_clk <= below_clk;
                        last_dt    <= (cross_dt_now > {{(32-DT_WIDTH){1'b0}}, {DT_WIDTH{1'b1}}})
                                      ? {DT_WIDTH{1'b1}} : cross_dt_now[DT_WIDTH-1:0];

                        if (!first_seen) begin
                            first_seen <= 1'b1;
                            first_num   <= cross_num_now;
                            first_den   <= cross_den_now;
                            first_a_clk <= below_clk;
                            first_dt    <= (cross_dt_now > {{(32-DT_WIDTH){1'b0}}, {DT_WIDTH{1'b1}}})
                                           ? {DT_WIDTH{1'b1}} : cross_dt_now[DT_WIDTH-1:0];
                        end
                    end else if (sample_code <= code_low) begin
                        armed <= 1'b1;
                    end

                    // 窗口结束：转去算插值与周期
                    if (sample_count == (sample_target - 1'b1)) begin
                        sample_count <= {N_WIDTH{1'b0}};
                        calc_step    <= 3'd0;
                        state        <= ST_CALC;
                    end else begin
                        sample_count <= sample_count + {{(N_WIDTH - 1){1'b0}}, 1'b1};
                    end
                end
            end

            // 窗口结束后集中算：frac_first -> t_first -> frac_last -> t_last -> 周期
            ST_CALC: begin
                div_start <= 1'b0;

                case (calc_step)
                    // 过零不足两个：只给 done，不给 valid
                    3'd0: begin
                        if (cross_count < 16'd2) begin
                            busy       <= 1'b0;
                            done       <= 1'b1;
                            freq_valid <= 1'b0;
                            state      <= ST_IDLE;
                        end else begin
                            div_dividend_in <= {first_num, {FRAC_BITS{1'b0}}};
                            div_divisor_in  <= {1'b0, first_den[WIDTH-1:0]};
                            div_start       <= 1'b1;
                            calc_step       <= 3'd1;
                        end
                    end

                    3'd1: begin
                        if (div_done) begin
                            frac_first <= div_quot[12:0];
                            calc_step  <= 3'd2;
                        end
                    end

                    3'd2: begin
                        t_first         <= t_first_next;
                        div_dividend_in <= {last_num, {FRAC_BITS{1'b0}}};
                        div_divisor_in  <= {1'b0, last_den[WIDTH-1:0]};
                        div_start       <= 1'b1;
                        calc_step       <= 3'd3;
                    end

                    3'd3: begin
                        if (div_done) begin
                            frac_last <= div_quot[12:0];
                            calc_step <= 3'd4;
                        end
                    end

                    3'd4: begin
                        if ((delta_next == 32'd0) || (periods_next == 17'd0) ||
                            (t_last_next < t_first)) begin
                            busy       <= 1'b0;
                            done       <= 1'b1;
                            freq_valid <= 1'b0;
                            state      <= ST_IDLE;
                        end else begin
                            div_dividend_in <= delta_next;
                            div_divisor_in  <= periods_next;
                            div_start       <= 1'b1;
                            calc_step       <= 3'd5;
                        end
                    end

                    3'd5: begin
                        if (div_done) begin
                            freq_period_raw <= {1'b0, div_quot[30:0]};
                            freq_valid      <= 1'b1;
                            busy            <= 1'b0;
                            done            <= 1'b1;
                            state           <= ST_IDLE;
                        end
                    end

                    default: begin
                        busy  <= 1'b0;
                        done  <= 1'b1;
                        state <= ST_IDLE;
                    end
                endcase
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
