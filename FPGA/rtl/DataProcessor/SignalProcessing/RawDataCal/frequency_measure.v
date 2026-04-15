`timescale 1ns / 1ps

/*
 * 模块: frequency_measure
 * 功能:
 *   在一次采样窗口内检测电压信号的同向过零事件，
 *   输出相邻两次有效过零之间的周期计数原始值，供上层统一换算为频率 x100。
 * 输入:
 *   clk: 工作时钟。
 *   rst_n: 低有效复位。
 *   start: 启动一次频率测量。
 *   sample_count_n: 本次测量允许处理的采样点数。
 *   sample_valid: 当前采样是否有效。
 *   sample_code: 当前电压采样码值。
 *   zero_code: 过零判定使用的参考零点码值。
 *   zero_valid: 参考零点码值是否有效。
 * 输出:
 *   busy: 当前频率测量流程是否仍在进行。
 *   done: 本次测量结束时给出的完成脉冲。
 *   freq_period_raw: 相邻两次有效过零之间的周期计数原始值，统一扩展为 32 位补码。
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

localparam [1:0] ST_IDLE    = 2'd0;
localparam [1:0] ST_CAPTURE = 2'd1;

localparam [WIDTH-1:0] CENTER_DEFAULT = {1'b1, {(WIDTH - 1){1'b0}}};
localparam integer     FREQ_HYST_INT  = (WIDTH >= 8) ? (2 << (WIDTH - 8)) : 2;
localparam [WIDTH-1:0] FREQ_HYST      = FREQ_HYST_INT;

reg  [1:0]            state;
reg  [N_WIDTH-1:0]    sample_target;
reg  [N_WIDTH-1:0]    sample_count;
reg  [31:0]           period_clk_cnt;
reg                   trigger_armed;
reg                   first_cross_seen;
reg                   cross_now;

wire [WIDTH-1:0]      ref_code;
wire [WIDTH-1:0]      code_low;
wire [WIDTH-1:0]      code_high;

// 根据零点参考构造带迟滞的过零判定门限，降低抖动导致的误触发概率。
assign ref_code  = zero_valid ? zero_code : CENTER_DEFAULT;
assign code_low  = (ref_code > FREQ_HYST) ? (ref_code - FREQ_HYST) : {WIDTH{1'b0}};
assign code_high = (ref_code < ({WIDTH{1'b1}} - FREQ_HYST)) ? (ref_code + FREQ_HYST) : {WIDTH{1'b1}};

// 在采样窗口内累计周期计数并检测过零，窗口结束或测量成功时统一锁存 raw 结果。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state           <= ST_IDLE;
        sample_target   <= {N_WIDTH{1'b0}};
        sample_count    <= {N_WIDTH{1'b0}};
        period_clk_cnt  <= 32'd0;
        trigger_armed   <= 1'b0;
        first_cross_seen<= 1'b0;
        busy            <= 1'b0;
        done            <= 1'b0;
        freq_period_raw <= 32'sd0;
        freq_valid      <= 1'b0;
    end else begin
        done       <= 1'b0;
        freq_valid <= 1'b0;

        case (state)
            ST_IDLE: begin
                busy <= 1'b0;

                if (start) begin
                    sample_target    <= sample_count_n;
                    sample_count     <= {N_WIDTH{1'b0}};
                    period_clk_cnt   <= 32'd0;
                    trigger_armed    <= 1'b0;
                    first_cross_seen <= 1'b0;
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
                if (period_clk_cnt != 32'hFFFF_FFFF)
                    period_clk_cnt <= period_clk_cnt + 32'd1;

                if (sample_valid) begin
                    cross_now = 1'b0;

                    if (sample_code <= code_low)
                        trigger_armed <= 1'b1;
                    else if (trigger_armed && (sample_code >= code_high)) begin
                        cross_now     = 1'b1;
                        trigger_armed <= 1'b0;
                    end else begin
                        cross_now     = 1'b0;
                    end

                    if (cross_now) begin
                        if (!first_cross_seen) begin
                            first_cross_seen <= 1'b1;
                            period_clk_cnt   <= 32'd0;
                        end else begin
                            freq_period_raw <= {1'b0, period_clk_cnt[30:0]};
                            freq_valid      <= 1'b1;
                            busy            <= 1'b0;
                            done            <= 1'b1;
                            state           <= ST_IDLE;
                        end
                    end

                    if ((state == ST_CAPTURE) && (sample_count == (sample_target - 1'b1))) begin
                        if (!(cross_now && first_cross_seen)) begin
                            busy  <= 1'b0;
                            done  <= 1'b1;
                            state <= ST_IDLE;
                        end
                        sample_count <= {N_WIDTH{1'b0}};
                    end else if (state == ST_CAPTURE) begin
                        sample_count <= sample_count + {{(N_WIDTH - 1){1'b0}}, 1'b1};
                    end
                end
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
