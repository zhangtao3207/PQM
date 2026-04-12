`timescale 1ns / 1ps

/*
 * 模块: zero_code_tracker
 * 功能:
 *   对输入的偏移二进制采样做慢速零点跟踪，输出可供过零检测与 RMS 去直流使用的 zero_code。
 *
 * 说明:
 *   - 复位后默认从 16'h8000 开始跟踪。
 *   - 每次 sample_valid 到来时，用移位平均方式向当前样本靠拢。
 *   - 为避免误差较小时完全停滞，最小修正步长保持为 1 个码值。
 *   - 零点跟踪预热完成后输出 zero_valid=1。
 */
module zero_code_tracker #(
    parameter integer WIDTH          = 16,
    parameter integer EST_SHIFT      = 8,
    parameter integer WARMUP_SAMPLES = 256
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             sample_valid,
    input  wire [WIDTH-1:0] sample_code,
    output reg  [WIDTH-1:0] zero_code,
    output reg              zero_valid
);

localparam [WIDTH-1:0] CENTER_DEFAULT = {1'b1, {(WIDTH - 1){1'b0}}};
localparam integer     COUNT_WIDTH    = (WARMUP_SAMPLES <= 2) ? 2 : $clog2(WARMUP_SAMPLES);

reg [COUNT_WIDTH-1:0]        warmup_count;
reg signed [WIDTH:0]         sample_delta_signed;
reg signed [WIDTH:0]         zero_step_signed;
reg signed [WIDTH:0]         zero_code_next_signed;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        zero_code             <= CENTER_DEFAULT;
        zero_valid            <= 1'b0;
        warmup_count          <= {COUNT_WIDTH{1'b0}};
        sample_delta_signed   <= {(WIDTH + 1){1'b0}};
        zero_step_signed      <= {(WIDTH + 1){1'b0}};
        zero_code_next_signed <= {(WIDTH + 1){1'b0}};
    end else if (sample_valid) begin
        sample_delta_signed = $signed({1'b0, sample_code}) - $signed({1'b0, zero_code});
        zero_step_signed    = sample_delta_signed >>> EST_SHIFT;

        if ((sample_delta_signed > 0) && (zero_step_signed == 0))
            zero_step_signed = {{WIDTH{1'b0}}, 1'b1};
        else if ((sample_delta_signed < 0) && (zero_step_signed == 0))
            zero_step_signed = {(WIDTH + 1){1'b1}};

        zero_code_next_signed = $signed({1'b0, zero_code}) + zero_step_signed;

        if (zero_code_next_signed < 0)
            zero_code <= {WIDTH{1'b0}};
        else if (zero_code_next_signed > $signed({1'b0, {WIDTH{1'b1}}}))
            zero_code <= {WIDTH{1'b1}};
        else
            zero_code <= zero_code_next_signed[WIDTH-1:0];

        if (!zero_valid) begin
            if (warmup_count == (WARMUP_SAMPLES - 1)) begin
                warmup_count <= warmup_count;
                zero_valid   <= 1'b1;
            end else begin
                warmup_count <= warmup_count + {{(COUNT_WIDTH - 1){1'b0}}, 1'b1};
            end
        end
    end
end

endmodule
