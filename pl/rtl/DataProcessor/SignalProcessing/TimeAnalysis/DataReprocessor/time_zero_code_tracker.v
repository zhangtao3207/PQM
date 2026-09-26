`timescale 1ns / 1ps

/*
 * 模块: time_zero_code_tracker
 * 功能:
 *   对输入的偏移二进制采样做动态零点跟踪，输出供时域测量和波形显示复用的 zero_code。
 *
 * 输入:
 *   clk: 模块工作时钟。
 *   rst_n: 低有效复位。
 *   sample_valid: 当前 sample_code 是否有效。
 *   sample_code: 输入采样码值。
 *
 * 输出:
 *   zero_code: 跟踪得到的动态零点码值。
 *   zero_valid: 预热完成后拉高，表示 zero_code 可供测量链路直接使用。
 *
 * 说明:
 *   - 复位后默认从 16'h8000 开始跟踪。
 *   - 预热阶段使用较快的 WARMUP_SHIFT 收敛真实中心，减小上电后波形偏移。
 *   - 预热完成后切回较慢的 EST_SHIFT，避免 zero_code 过快吞掉交流幅值。
 *   - 为避免误差较小时完全停滞，最小修正步长保持为 1 个码值。
 */
module time_zero_code_tracker #(
    parameter integer WIDTH          = 16,
    parameter integer EST_SHIFT      = 8,
    parameter integer WARMUP_SHIFT   = (EST_SHIFT > 4) ? (EST_SHIFT - 4) : EST_SHIFT,
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

reg [COUNT_WIDTH-1:0] warmup_count;
reg signed [WIDTH:0]  sample_delta_signed;
reg signed [WIDTH:0]  zero_step_signed;
reg signed [WIDTH:0]  zero_code_next_signed;

// 每个有效样本到来时更新 zero_code：预热期快收敛，稳态期慢跟踪。
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

        if (!zero_valid)
            zero_step_signed = sample_delta_signed >>> WARMUP_SHIFT;
        else
            zero_step_signed = sample_delta_signed >>> EST_SHIFT;

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
