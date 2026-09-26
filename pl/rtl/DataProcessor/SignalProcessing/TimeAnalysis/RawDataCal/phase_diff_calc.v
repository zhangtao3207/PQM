`timescale 1ns / 1ps

/*
 * 模块: phase_diff_calc
 * 功能:
 *   在一次采样窗口内分别检测电压与电流信号的同向过零事件，
 *   输出相位差换算所需的原始偏移计数和周期计数，供上层统一换算为显示用 x100 数据。
 * 输入:
 *   clk: 工作时钟。
 *   rst_n: 低有效复位。
 *   start: 启动一次相位差测量。
 *   sample_count_n: 本次测量允许处理的采样点数。
 *   sample_valid: 当前 U/I 联合采样是否有效。
 *   u_sample_code: 当前电压采样码值。
 *   u_zero_code: 电压过零参考码值。
 *   u_zero_valid: 电压过零参考是否有效。
 *   i_sample_code: 当前电流采样码值。
 *   i_zero_code: 电流过零参考码值。
 *   i_zero_valid: 电流过零参考是否有效。
 * 输出:
 *   busy: 当前相位差测量流程是否仍在进行。
 *   done: 本次测量结束时给出的完成脉冲。
 *   phase_offset_raw: 电流过零相对电压过零的偏移计数原始值。
 *   phase_period_raw: 电压相邻两次有效过零之间的周期计数原始值。
 *   phase_valid: 本次原始相位差结果是否有效。
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
    output reg  signed [31:0] phase_offset_raw,
    output reg  signed [31:0] phase_period_raw,
    output reg                phase_valid
);

localparam [1:0] ST_IDLE    = 2'd0;
localparam [1:0] ST_CAPTURE = 2'd1;

localparam [WIDTH-1:0] CENTER_DEFAULT = {1'b1, {(WIDTH - 1){1'b0}}};
localparam integer     PHASE_HYST_INT = (WIDTH >= 8) ? (2 << (WIDTH - 8)) : 2;
localparam [WIDTH-1:0] PHASE_HYST     = PHASE_HYST_INT;

reg  [1:0]            state;
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
reg  [31:0]           phase_offset_work;

wire [WIDTH-1:0]      u_ref_code;
wire [WIDTH-1:0]      i_ref_code;
wire [WIDTH-1:0]      u_low;
wire [WIDTH-1:0]      u_high;
wire [WIDTH-1:0]      i_low;
wire [WIDTH-1:0]      i_high;

// 基于电压和电流的零点参考构造带迟滞的过零门限，降低噪声抖动引发的误触发。
assign u_ref_code = u_zero_valid ? u_zero_code : CENTER_DEFAULT;
assign i_ref_code = i_zero_valid ? i_zero_code : CENTER_DEFAULT;
assign u_low      = (u_ref_code > PHASE_HYST) ? (u_ref_code - PHASE_HYST) : {WIDTH{1'b0}};
assign u_high     = (u_ref_code < ({WIDTH{1'b1}} - PHASE_HYST)) ? (u_ref_code + PHASE_HYST) : {WIDTH{1'b1}};
assign i_low      = (i_ref_code > PHASE_HYST) ? (i_ref_code - PHASE_HYST) : {WIDTH{1'b0}};
assign i_high     = (i_ref_code < ({WIDTH{1'b1}} - PHASE_HYST)) ? (i_ref_code + PHASE_HYST) : {WIDTH{1'b1}};

// 在采样窗口内同步追踪 U/I 过零事件，满足条件时锁存相位差换算所需的原始偏移和周期。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state                 <= ST_IDLE;
        sample_target         <= {N_WIDTH{1'b0}};
        sample_count          <= {N_WIDTH{1'b0}};
        u_period_clk_cnt      <= 32'd0;
        i_since_cross_clk_cnt <= 32'd0;
        u_period_valid        <= 1'b0;
        i_cross_valid         <= 1'b0;
        u_trigger_armed       <= 1'b0;
        i_trigger_armed       <= 1'b0;
        u_cross_now           <= 1'b0;
        i_cross_now           <= 1'b0;
        phase_offset_work     <= 32'd0;
        busy                  <= 1'b0;
        done                  <= 1'b0;
        phase_offset_raw      <= 32'sd0;
        phase_period_raw      <= 32'sd0;
        phase_valid           <= 1'b0;
    end else begin
        done       <= 1'b0;
        phase_valid<= 1'b0;

        case (state)
            ST_IDLE: begin
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
                    phase_offset_work     <= 32'd0;

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
                            if (i_cross_now)
                                phase_offset_work = 32'd0;
                            else
                                phase_offset_work = i_since_cross_clk_cnt;

                            phase_offset_raw <= {1'b0, phase_offset_work[30:0]};
                            phase_period_raw <= {1'b0, u_period_clk_cnt[30:0]};
                            phase_valid      <= 1'b1;
                            busy             <= 1'b0;
                            done             <= 1'b1;
                            u_period_clk_cnt <= 32'd0;
                            u_period_valid   <= 1'b1;
                            state            <= ST_IDLE;
                        end else begin
                            u_period_clk_cnt <= 32'd0;
                            u_period_valid   <= 1'b1;
                        end
                    end

                    if ((state == ST_CAPTURE) && (sample_count == (sample_target - 1'b1))) begin
                        if (!(u_cross_now && u_period_valid && i_cross_valid && (u_period_clk_cnt != 32'd0))) begin
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
