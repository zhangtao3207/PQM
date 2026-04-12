`timescale 1ns / 1ps

/*
 * 模块: ui_rms_measure
 * 功能:
 *   U/I 双通道滤波后 RMS 顶层。
 *   该模块统一完成:
 *   1. 按 N 点采集 U/I 原始样本
 *   2. 对 U/I 两路执行 8 点均值滤波后 RMS 计算
 *   3. 将 U/I 两路 RMS 补码值转换为 LCD 需要的 XX.XX 数字位
 *
 * 说明:
 *   - N 由输入 frame_samples_n 在运行时给定
 *   - 该模块要求 N 为 8 的整数倍
 *   - rms_valid 表示本次 U/I 两路最终输出同时有效
 */
module ui_rms_measure #(
    parameter integer DATA_WIDTH        = 16,
    parameter integer MAX_FRAME_SAMPLES = 4096,
    parameter integer N_WIDTH           = (MAX_FRAME_SAMPLES <= 2) ? 2 : $clog2(MAX_FRAME_SAMPLES),
    parameter integer U_FULL_SCALE_X100 = 1000,
    parameter integer I_FULL_SCALE_X100 = 30
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         start,
    input  wire [N_WIDTH-1:0]           frame_samples_n,
    input  wire                         sample_valid,
    input  wire signed [DATA_WIDTH-1:0] u_sample_in,
    input  wire signed [DATA_WIDTH-1:0] i_sample_in,

    output wire                         busy,
    output reg                          done,
    output reg                          rms_valid,
    output wire                         config_error,
    output wire                         frame_overflow,

    output reg  signed [DATA_WIDTH-1:0] u_rms_out,
    output reg  signed [DATA_WIDTH-1:0] i_rms_out,
    output reg  [31:0]                   u_rms_x100,
    output reg  [31:0]                   i_rms_x100,

    output reg  [7:0]                   u_rms_tens,
    output reg  [7:0]                   u_rms_units,
    output reg  [7:0]                   u_rms_decile,
    output reg  [7:0]                   u_rms_percentiles,
    output reg                          u_rms_digits_valid,

    output reg  [7:0]                   i_rms_tens,
    output reg  [7:0]                   i_rms_units,
    output reg  [7:0]                   i_rms_decile,
    output reg  [7:0]                   i_rms_percentiles,
    output reg                          i_rms_digits_valid
);

wire                         core_busy;
wire                         core_rms_valid;
wire signed [DATA_WIDTH-1:0] core_u_rms_out;
wire signed [DATA_WIDTH-1:0] core_i_rms_out;

wire                         u_digit_busy;
wire                         u_digit_valid;
wire [31:0]                   u_digit_value_x100;
wire [7:0]                   u_digit_tens;
wire [7:0]                   u_digit_units;
wire [7:0]                   u_digit_decile;
wire [7:0]                   u_digit_percentiles;

wire                         i_digit_busy;
wire                         i_digit_valid;
wire [31:0]                   i_digit_value_x100;
wire [7:0]                   i_digit_tens;
wire [7:0]                   i_digit_units;
wire [7:0]                   i_digit_decile;
wire [7:0]                   i_digit_percentiles;

reg                          u_digit_done_latched;
reg                          i_digit_done_latched;
reg                          capture_active;
reg  [N_WIDTH-1:0]           capture_remaining;
wire                         core_sample_valid;

assign core_sample_valid = capture_active && sample_valid;

ui_rms_filtered_runtime #(
    .DATA_WIDTH        (DATA_WIDTH),
    .MAX_FRAME_SAMPLES (MAX_FRAME_SAMPLES),
    .N_WIDTH           (N_WIDTH)
) u_ui_rms_filtered_runtime (
    .clk           (clk),
    .rst_n         (rst_n),
    .frame_samples_n(frame_samples_n),
    .sample_valid  (core_sample_valid),
    .u_sample_in   (u_sample_in),
    .i_sample_in   (i_sample_in),
    .busy          (core_busy),
    .rms_valid     (core_rms_valid),
    .config_error  (config_error),
    .frame_overflow(frame_overflow),
    .u_rms_out     (core_u_rms_out),
    .i_rms_out     (core_i_rms_out)
);

signed_code_to_digits_x100 u_u_rms_digits (
    .clk          (clk),
    .rst_n        (rst_n),
    .start        (core_rms_valid),
    .code_in      (core_u_rms_out),
    .full_scale_x100(U_FULL_SCALE_X100),
    .busy         (u_digit_busy),
    .digits_valid (u_digit_valid),
    .value_x100   (u_digit_value_x100),
    .tens         (u_digit_tens),
    .units        (u_digit_units),
    .decile       (u_digit_decile),
    .percentiles  (u_digit_percentiles)
);

signed_code_to_digits_x100 u_i_rms_digits (
    .clk          (clk),
    .rst_n        (rst_n),
    .start        (core_rms_valid),
    .code_in      (core_i_rms_out),
    .full_scale_x100(I_FULL_SCALE_X100),
    .busy         (i_digit_busy),
    .digits_valid (i_digit_valid),
    .value_x100   (i_digit_value_x100),
    .tens         (i_digit_tens),
    .units        (i_digit_units),
    .decile       (i_digit_decile),
    .percentiles  (i_digit_percentiles)
);

assign busy = capture_active || core_busy || u_digit_busy || i_digit_busy ||
              u_digit_done_latched || i_digit_done_latched;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        done                  <= 1'b0;
        rms_valid             <= 1'b0;
        u_rms_out             <= {DATA_WIDTH{1'b0}};
        i_rms_out             <= {DATA_WIDTH{1'b0}};
        u_rms_x100            <= 32'd0;
        i_rms_x100            <= 32'd0;
        u_rms_tens            <= 8'd0;
        u_rms_units           <= 8'd0;
        u_rms_decile          <= 8'd0;
        u_rms_percentiles     <= 8'd0;
        u_rms_digits_valid    <= 1'b0;
        i_rms_tens            <= 8'd0;
        i_rms_units           <= 8'd0;
        i_rms_decile          <= 8'd0;
        i_rms_percentiles     <= 8'd0;
        i_rms_digits_valid    <= 1'b0;
        u_digit_done_latched  <= 1'b0;
        i_digit_done_latched  <= 1'b0;
        capture_active        <= 1'b0;
        capture_remaining     <= {N_WIDTH{1'b0}};
    end else begin
        done               <= 1'b0;
        rms_valid          <= 1'b0;
        u_rms_digits_valid <= 1'b0;
        i_rms_digits_valid <= 1'b0;

        if (start && !busy) begin
            capture_remaining <= frame_samples_n;
            if (frame_samples_n == {N_WIDTH{1'b0}})
                capture_active <= 1'b0;
            else
                capture_active <= 1'b1;
        end else if (capture_active && sample_valid) begin
            if (capture_remaining == {{(N_WIDTH - 1){1'b0}}, 1'b1}) begin
                capture_active    <= 1'b0;
                capture_remaining <= {N_WIDTH{1'b0}};
            end else begin
                capture_remaining <= capture_remaining - {{(N_WIDTH - 1){1'b0}}, 1'b1};
            end
        end

        if (core_rms_valid) begin
            u_rms_out            <= core_u_rms_out;
            i_rms_out            <= core_i_rms_out;
            u_digit_done_latched <= 1'b0;
            i_digit_done_latched <= 1'b0;
        end

        if (u_digit_valid) begin
            u_rms_x100           <= u_digit_value_x100;
            u_rms_tens           <= u_digit_tens;
            u_rms_units          <= u_digit_units;
            u_rms_decile         <= u_digit_decile;
            u_rms_percentiles    <= u_digit_percentiles;
            u_rms_digits_valid   <= 1'b1;
            u_digit_done_latched <= 1'b1;
        end

        if (i_digit_valid) begin
            i_rms_x100           <= i_digit_value_x100;
            i_rms_tens           <= i_digit_tens;
            i_rms_units          <= i_digit_units;
            i_rms_decile         <= i_digit_decile;
            i_rms_percentiles    <= i_digit_percentiles;
            i_rms_digits_valid   <= 1'b1;
            i_digit_done_latched <= 1'b1;
        end

        if ((u_digit_done_latched || u_digit_valid) &&
            (i_digit_done_latched || i_digit_valid)) begin
            if (u_digit_valid || i_digit_valid) begin
                rms_valid <= 1'b1;
                done      <= 1'b1;
            end
        end

        if (rms_valid) begin
            u_digit_done_latched <= 1'b0;
            i_digit_done_latched <= 1'b0;
        end
    end
end

endmodule
