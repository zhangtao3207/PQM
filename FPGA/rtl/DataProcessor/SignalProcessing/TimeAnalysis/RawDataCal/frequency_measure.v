`timescale 1ns / 1ps

/*
 * 模块: frequency_measure
 * 功能:
 *   在一次采样窗口内检测电压信号的正向峰值事件，
 *   输出相邻两次有效峰值之间的周期计数原始值，供上层统一换算为频率 x100。
 * 输入:
 *   clk: 工作时钟。
 *   rst_n: 低有效复位。
 *   start: 启动一次频率测量。
 *   sample_count_n: 本次测量允许处理的采样点数。
 *   sample_valid: 当前采样是否有效。
 *   sample_code: 当前电压采样码值。
 *   zero_code: 峰值搜索使用的参考零点码值，用于构造正半周进入门限。
 *   zero_valid: 参考零点码值是否有效。
 * 输出:
 *   busy: 当前频率测量流程是否仍在进行。
 *   done: 本次测量结束时给出的完成脉冲。
 *   freq_period_raw: 相邻两次有效峰值之间的周期计数原始值，统一扩展为 32 位补码。
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
reg  [31:0]           sample_clk_cnt;
reg  [31:0]           last_peak_clk_cnt;
reg  [31:0]           candidate_peak_clk_cnt;
reg  [WIDTH-1:0]      candidate_peak_code;
reg                   peak_search_armed;
reg                   peak_tracking;
reg                   first_peak_seen;
reg                   peak_now;

wire [WIDTH-1:0]      ref_code;
wire [WIDTH-1:0]      code_high;
wire [WIDTH-1:0]      peak_drop_code;
wire [31:0]           peak_period_delta;

// 根据零点参考构造峰值进入门限和峰值回落确认门限，降低抖动导致的误触发概率。
assign ref_code  = zero_valid ? zero_code : CENTER_DEFAULT;
assign code_high = (ref_code < ({WIDTH{1'b1}} - FREQ_HYST)) ? (ref_code + FREQ_HYST) : {WIDTH{1'b1}};
assign peak_drop_code = (candidate_peak_code > FREQ_HYST) ?
                        (candidate_peak_code - FREQ_HYST) : {WIDTH{1'b0}};
assign peak_period_delta = candidate_peak_clk_cnt - last_peak_clk_cnt;

// 在采样窗口内累计时钟计数并检测正向峰值，窗口结束或测量成功时统一锁存 raw 结果。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state                  <= ST_IDLE;
        sample_target          <= {N_WIDTH{1'b0}};
        sample_count           <= {N_WIDTH{1'b0}};
        sample_clk_cnt         <= 32'd0;
        last_peak_clk_cnt      <= 32'd0;
        candidate_peak_clk_cnt <= 32'd0;
        candidate_peak_code    <= {WIDTH{1'b0}};
        peak_search_armed      <= 1'b0;
        peak_tracking          <= 1'b0;
        first_peak_seen        <= 1'b0;
        peak_now               <= 1'b0;
        busy                   <= 1'b0;
        done                   <= 1'b0;
        freq_period_raw        <= 32'sd0;
        freq_valid             <= 1'b0;
    end else begin
        done       <= 1'b0;
        freq_valid <= 1'b0;
        peak_now   = 1'b0;

        case (state)
            ST_IDLE: begin
                busy <= 1'b0;

                if (start) begin
                    sample_target          <= sample_count_n;
                    sample_count           <= {N_WIDTH{1'b0}};
                    sample_clk_cnt         <= 32'd0;
                    last_peak_clk_cnt      <= 32'd0;
                    candidate_peak_clk_cnt <= 32'd0;
                    candidate_peak_code    <= {WIDTH{1'b0}};
                    peak_search_armed      <= 1'b1;
                    peak_tracking          <= 1'b0;
                    first_peak_seen        <= 1'b0;
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
                    if (!peak_tracking) begin
                        if (!peak_search_armed && (sample_code <= ref_code))
                            peak_search_armed <= 1'b1;

                        if (peak_search_armed && (sample_code >= code_high)) begin
                            peak_tracking          <= 1'b1;
                            candidate_peak_code    <= sample_code;
                            candidate_peak_clk_cnt <= sample_clk_cnt;
                        end
                    end else begin
                        if (sample_code >= candidate_peak_code) begin
                            candidate_peak_code    <= sample_code;
                            candidate_peak_clk_cnt <= sample_clk_cnt;
                        end else if (sample_code <= peak_drop_code) begin
                            peak_now          = 1'b1;
                            peak_tracking     <= 1'b0;
                            peak_search_armed <= 1'b0;
                        end
                    end

                    if (peak_now) begin
                        if (!first_peak_seen) begin
                            first_peak_seen   <= 1'b1;
                            last_peak_clk_cnt <= candidate_peak_clk_cnt;
                        end else begin
                            if (candidate_peak_clk_cnt > last_peak_clk_cnt && (peak_period_delta != 32'd0)) begin
                                freq_period_raw <= {1'b0, peak_period_delta[30:0]};
                                freq_valid      <= 1'b1;
                                busy            <= 1'b0;
                                done            <= 1'b1;
                                state           <= ST_IDLE;
                            end else begin
                                last_peak_clk_cnt <= candidate_peak_clk_cnt;
                            end
                        end
                    end

                    if ((state == ST_CAPTURE) && (sample_count == (sample_target - 1'b1))) begin
                        if (!(peak_now && first_peak_seen)) begin
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
