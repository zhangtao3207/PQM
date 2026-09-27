`timescale 1ns / 1ps

/*
 * 模块: phase_diff_calc
 * 功能:
 *   在一次采样窗口内分别检测U1 与 U2信号的同向过零事件，
 *   输出相位差换算所需的原始偏移计数和周期计数，供上层统一换算为显示用 x100 数据。
 * 输入:
 *   clk: 工作时钟。
 *   rst_n: 低有效复位。
 *   start: 启动一次相位差测量。
 *   sample_count_n: 本次测量允许处理的采样点数。
 *   sample_valid: 当前 U1/U2 联合采样是否有效。
 *   u1_sample_code: 当前U1采样码值。
 *   u1_zero_code: U1过零参考码值。
 *   u1_zero_valid: U1过零参考是否有效。
 *   u2_sample_code: 当前U2采样码值。
 *   u2_zero_code: U2过零参考码值。
 *   u2_zero_valid: U2过零参考是否有效。
 * 输出:
 *   busy: 当前相位差测量流程是否仍在进行。
 *   done: 本次测量结束时给出的完成脉冲。
 *   phase_offset_raw: U2过零相对U1过零的偏移计数原始值。
 *   phase_period_raw: U1相邻两次有效过零之间的周期计数原始值。
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
    input  wire [WIDTH-1:0]   u1_sample_code,
    input  wire [WIDTH-1:0]   u1_zero_code,
    input  wire               u1_zero_valid,
    input  wire [WIDTH-1:0]   u2_sample_code,
    input  wire [WIDTH-1:0]   u2_zero_code,
    input  wire               u2_zero_valid,
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
reg  [31:0]           u1_period_clk_cnt;
reg  [31:0]           u2_since_cross_clk_cnt;
reg                   u1_period_valid;
reg                   u2_cross_valid;
reg                   u1_trigger_armed;
reg                   u2_trigger_armed;
reg                   u1_cross_now;
reg                   u2_cross_now;
reg  [31:0]           phase_offset_work;

wire [WIDTH-1:0]      u1_ref_code;
wire [WIDTH-1:0]      u2_ref_code;
wire [WIDTH-1:0]      u1_low;
wire [WIDTH-1:0]      u1_high;
wire [WIDTH-1:0]      u2_low;
wire [WIDTH-1:0]      u2_high;

// 基于U1 和 U2的零点参考构造带迟滞的过零门限，降低噪声抖动引发的误触发。
assign u1_ref_code = u1_zero_valid ? u1_zero_code : CENTER_DEFAULT;
assign u2_ref_code = u2_zero_valid ? u2_zero_code : CENTER_DEFAULT;
assign u1_low      = (u1_ref_code > PHASE_HYST) ? (u1_ref_code - PHASE_HYST) : {WIDTH{1'b0}};
assign u1_high     = (u1_ref_code < ({WIDTH{1'b1}} - PHASE_HYST)) ? (u1_ref_code + PHASE_HYST) : {WIDTH{1'b1}};
assign u2_low      = (u2_ref_code > PHASE_HYST) ? (u2_ref_code - PHASE_HYST) : {WIDTH{1'b0}};
assign u2_high     = (u2_ref_code < ({WIDTH{1'b1}} - PHASE_HYST)) ? (u2_ref_code + PHASE_HYST) : {WIDTH{1'b1}};

// 在采样窗口内同步追踪 U1/U2 过零事件，满足条件时锁存相位差换算所需的原始偏移和周期。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state                 <= ST_IDLE;
        sample_target         <= {N_WIDTH{1'b0}};
        sample_count          <= {N_WIDTH{1'b0}};
        u1_period_clk_cnt      <= 32'd0;
        u2_since_cross_clk_cnt <= 32'd0;
        u1_period_valid        <= 1'b0;
        u2_cross_valid         <= 1'b0;
        u1_trigger_armed       <= 1'b0;
        u2_trigger_armed       <= 1'b0;
        u1_cross_now           <= 1'b0;
        u2_cross_now           <= 1'b0;
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
                    u1_period_clk_cnt      <= 32'd0;
                    u2_since_cross_clk_cnt <= 32'd0;
                    u1_period_valid        <= 1'b0;
                    u2_cross_valid         <= 1'b0;
                    u1_trigger_armed       <= 1'b0;
                    u2_trigger_armed       <= 1'b0;
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
                if (u1_period_clk_cnt != 32'hFFFF_FFFF)
                    u1_period_clk_cnt <= u1_period_clk_cnt + 32'd1;

                if (u2_cross_valid && (u2_since_cross_clk_cnt != 32'hFFFF_FFFF))
                    u2_since_cross_clk_cnt <= u2_since_cross_clk_cnt + 32'd1;

                if (sample_valid) begin
                    u1_cross_now = 1'b0;
                    u2_cross_now = 1'b0;

                    if (u1_sample_code <= u1_low)
                        u1_trigger_armed <= 1'b1;
                    else if (u1_trigger_armed && (u1_sample_code >= u1_high)) begin
                        u1_cross_now     = 1'b1;
                        u1_trigger_armed <= 1'b0;
                    end

                    if (u2_sample_code <= u2_low)
                        u2_trigger_armed <= 1'b1;
                    else if (u2_trigger_armed && (u2_sample_code >= u2_high)) begin
                        u2_cross_now     = 1'b1;
                        u2_trigger_armed <= 1'b0;
                    end

                    if (u2_cross_now) begin
                        u2_since_cross_clk_cnt <= 32'd0;
                        u2_cross_valid         <= 1'b1;
                    end

                    if (u1_cross_now) begin
                        if (u1_period_valid && (u1_period_clk_cnt != 32'd0) && u2_cross_valid) begin
                            if (u2_cross_now)
                                phase_offset_work = 32'd0;
                            else
                                phase_offset_work = u2_since_cross_clk_cnt;

                            phase_offset_raw <= {1'b0, phase_offset_work[30:0]};
                            phase_period_raw <= {1'b0, u1_period_clk_cnt[30:0]};
                            phase_valid      <= 1'b1;
                            busy             <= 1'b0;
                            done             <= 1'b1;
                            u1_period_clk_cnt <= 32'd0;
                            u1_period_valid   <= 1'b1;
                            state            <= ST_IDLE;
                        end else begin
                            u1_period_clk_cnt <= 32'd0;
                            u1_period_valid   <= 1'b1;
                        end
                    end

                    if ((state == ST_CAPTURE) && (sample_count == (sample_target - 1'b1))) begin
                        if (!(u1_cross_now && u1_period_valid && u2_cross_valid && (u1_period_clk_cnt != 32'd0))) begin
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
