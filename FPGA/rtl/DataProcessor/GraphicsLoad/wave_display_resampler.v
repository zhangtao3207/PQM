`timescale 1ns / 1ps

/*
 * 模块: wave_display_resampler
 * 功能:
 *   按显示帧节拍从原始采样流中提取用于绘制波形的显示点，并将采样码值换算为屏幕 Y 坐标。
 *   模块内部维护重采样节拍、幅值缩放乘除法与点提交时序，对外输出触发采样脉冲与显示点结果。
 *
 * 输入:
 *   clk: 模块工作时钟
 *   rst_n: 低有效复位
 *   sample_code: 当前原始采样码值
 *   zero_code: 外部提供的零点参考码值
 *   zero_valid: 零点参考是否有效
 *
 * 输出:
 *   trigger_sample_valid: 本拍启动一次触发采样更新
 *   point_valid: 本拍有一个显示点提交完成
 *   point_sample_code: 本次提交显示点对应的原始采样码值
 *   point_y: 本次提交显示点的屏幕 Y 坐标
 *   resample_pending: 已启动一次点生成、正在等待除法结果返回
 */
module wave_display_resampler #(
    parameter integer WIDTH              = 16,
    parameter integer POINT_COUNT        = 384,
    parameter integer FRAME_TICKS        = 3_000_000,
    parameter integer GRAPH_H            = 240,
    parameter integer GRAPH_HALF_H       = 120,
    parameter integer DIV_WIDTH          = 32,
    parameter integer FULL_SCALE_CODE    = (1 << (WIDTH - 1)) - 1,
    parameter [WIDTH-1:0] CENTER_DEFAULT = {1'b1, {(WIDTH - 1){1'b0}}}
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire [WIDTH-1:0] sample_code,
    input  wire [WIDTH-1:0] zero_code,
    input  wire             zero_valid,
    output wire             trigger_sample_valid,
    output wire             point_valid,
    output reg  [WIDTH-1:0] point_sample_code,
    output reg  [7:0]       point_y,
    output reg              resample_pending
);

// 串行除法器内部数据位宽与波形满量程码值配置。
localparam [DIV_WIDTH-1:0] FULL_SCALE_DIVISOR   = FULL_SCALE_CODE;
localparam [DIV_WIDTH-1:0] FULL_SCALE_ROUND_BIAS= FULL_SCALE_DIVISOR >> 1;
localparam integer GRAPH_FULL_SCALE_PX = GRAPH_HALF_H - 2;
localparam integer AMP_DELTA_WIDTH = WIDTH + 1;
localparam integer AMP_SCALE_WIDTH = 15;
localparam integer AMP_PRODUCT_WIDTH = AMP_DELTA_WIDTH + AMP_SCALE_WIDTH;

// 显示重采样状态与幅值换算中间量
reg  [21:0]          resample_acc;
reg                  div_start;
reg  [DIV_WIDTH-1:0] dividend;
reg  [DIV_WIDTH-1:0] divisor;
reg                  sample_positive;

// 组合线网：零点选择、节拍累计、点提交判定
wire [WIDTH-1:0]             display_zero_code;
wire [WIDTH:0]               sample_delta_abs;
wire signed [WIDTH:0]        sample_delta_abs_signed;
wire signed [AMP_SCALE_WIDTH-1:0] graph_full_scale_px_signed;
wire signed [AMP_PRODUCT_WIDTH-1:0] amp_product_signed;
wire [DIV_WIDTH-1:0]         amp_product_unsigned;
wire [21:0]                  resample_sum;
wire                         div_busy;
wire                         div_done;
wire                         div_zero;
wire [DIV_WIDTH-1:0]         div_quotient;

integer amp_px;
integer y_next;
reg [7:0] y_clamped;

assign display_zero_code    = zero_valid ? zero_code : CENTER_DEFAULT;
assign sample_delta_abs     = (sample_code >= display_zero_code) ?
                              {1'b0, (sample_code - display_zero_code)} :
                              {1'b0, (display_zero_code - sample_code)};
assign sample_delta_abs_signed = $signed(sample_delta_abs);
assign graph_full_scale_px_signed = GRAPH_FULL_SCALE_PX;
assign amp_product_unsigned = amp_product_signed[AMP_PRODUCT_WIDTH-1] ?
                              {DIV_WIDTH{1'b0}} :
                              amp_product_signed[DIV_WIDTH-1:0];
assign resample_sum         = resample_acc + POINT_COUNT;
assign trigger_sample_valid = !resample_pending && !div_busy && (resample_sum >= FRAME_TICKS);
assign point_valid          = div_done && resample_pending;

// 幅值缩放乘法器：先将采样偏移量乘以图框半高，后续再按满量程码值归一化。
multiplier_signed #(
    .A_WIDTH(AMP_DELTA_WIDTH),
    .B_WIDTH(AMP_SCALE_WIDTH)
) u_wave_amp_multiplier (
    .multiplicand(sample_delta_abs_signed),
    .multiplier  (graph_full_scale_px_signed),
    .product     (amp_product_signed)
);

// 幅值缩放除法器：将满量程码值偏移映射到图框半高。
divider_unsigned #(
    .WIDTH(DIV_WIDTH)
) u_wave_amp_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (div_start),
    .dividend      (dividend),
    .divisor       (divisor),
    .busy          (div_busy),
    .done          (div_done),
    .divide_by_zero(div_zero),
    .quotient      (div_quotient)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        resample_acc      <= 22'd0;
        div_start         <= 1'b0;
        dividend          <= {DIV_WIDTH{1'b0}};
        divisor           <= {{(DIV_WIDTH - 1){1'b0}}, 1'b1};
        sample_positive   <= 1'b1;
        point_sample_code <= {WIDTH{1'b0}};
        point_y           <= GRAPH_HALF_H[7:0];
        resample_pending  <= 1'b0;
    end else begin
        // 除法启动仅持续一拍，默认先拉低
        div_start <= 1'b0;

        if (!resample_pending && !div_busy) begin
            if (trigger_sample_valid) begin
                // 达到一帧显示节拍后，锁存当前样本并启动幅值换算
                resample_acc      <= resample_sum - FRAME_TICKS;
                point_sample_code <= sample_code;
                resample_pending  <= 1'b1;
                div_start         <= 1'b1;
                sample_positive   <= (sample_code >= display_zero_code);
                divisor           <= FULL_SCALE_DIVISOR;
                dividend          <= amp_product_unsigned + FULL_SCALE_ROUND_BIAS;
            end else begin
                // 未到输出显示点的时刻时，持续累计显示帧节拍
                resample_acc <= resample_sum;
            end
        end

        if (point_valid) begin
            // 除法完成后，将极性与幅值还原为屏幕 Y 坐标，并做边界钳位
            amp_px = div_zero ? 0 : div_quotient;

            if (sample_positive)
                y_next = GRAPH_HALF_H - amp_px;
            else
                y_next = GRAPH_HALF_H + amp_px;

            if (y_next < 1)
                y_clamped = 8'd1;
            else if (y_next > (GRAPH_H - 2))
                y_clamped = (GRAPH_H - 2);
            else
                y_clamped = y_next[7:0];

            point_y          <= y_clamped;
            resample_pending <= 1'b0;
        end
    end
end

endmodule
