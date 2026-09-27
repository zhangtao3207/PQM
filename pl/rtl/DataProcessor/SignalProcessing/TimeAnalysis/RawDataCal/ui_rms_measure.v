`timescale 1ns / 1ps

/*
 * 模块: ui_rms_measure
 * 功能:
 *   在同一批时域采样窗口内直接累计 U1/U2 去零点后的平方和与乘积和，
 *   输出真实时域 RMS 原始值，并同时给出同窗口平均有功功率 raw。
 * 输入:
 *   clk: 工作时钟。
 *   rst_n: 低有效复位。
 *   start: 启动一次同窗口 RMS/平均有功功率测量。
 *   sample_count_n: 本次测量需要处理的联合采样点数。
 *   sample_valid: 当前 U1/U2 联合采样点是否有效。
 *   u1_sample_code: U1通道 ADC 采样码。
 *   u1_zero_code: U1通道零点参考码。
 *   u1_zero_valid: U1零点参考是否有效。
 *   u2_sample_code: U2通道 ADC 采样码。
 *   u2_zero_code: U2通道零点参考码。
 *   u2_zero_valid: U2零点参考是否有效。
 * 输出:
 *   busy: 当前 RMS/平均有功功率测量是否仍在进行。
 *   done: 本次测量完成脉冲。
 *   rms_valid: U1/U2 RMS raw 是否有效。
 *   active_p_valid: 同窗口平均有功功率 raw 是否有效。
 *   config_error: 当前实现不额外上报配置错误，固定为 0。
 *   frame_overflow: 当前实现不额外上报窗口溢出错误，固定为 0。
 *   u1_rms_raw: U1 RMS 原始补码值。
 *   u2_rms_raw: U2 RMS 原始补码值。
 *   active_p_raw: 同窗口平均有功功率原始补码值。
 */
module ui_rms_measure #(
    parameter integer DATA_WIDTH        = 16,
    parameter integer MAX_FRAME_SAMPLES = 8192,
    parameter integer N_WIDTH           = (MAX_FRAME_SAMPLES <= 2) ? 2 : $clog2(MAX_FRAME_SAMPLES)
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         start,
    input  wire [N_WIDTH-1:0]           sample_count_n,
    input  wire                         sample_valid,
    input  wire [DATA_WIDTH-1:0]        u1_sample_code,
    input  wire [DATA_WIDTH-1:0]        u1_zero_code,
    input  wire                         u1_zero_valid,
    input  wire [DATA_WIDTH-1:0]        u2_sample_code,
    input  wire [DATA_WIDTH-1:0]        u2_zero_code,
    input  wire                         u2_zero_valid,

    output wire                         busy,
    output reg                          done,
    output reg                          rms_valid,
    output reg                          active_p_valid,
    output wire                         config_error,
    output wire                         frame_overflow,
    output reg  signed [31:0]           u1_rms_raw,
    output reg  signed [31:0]           u2_rms_raw,
    output reg  signed [31:0]           active_p_raw
);

localparam integer SAMPLE_DIFF_WIDTH = DATA_WIDTH + 1;
localparam integer PRODUCT_WIDTH     = SAMPLE_DIFF_WIDTH + SAMPLE_DIFF_WIDTH;
localparam integer ACC_WIDTH         = PRODUCT_WIDTH + N_WIDTH + 2;

localparam [2:0] ST_IDLE       = 3'd0;
localparam [2:0] ST_CAPTURE    = 3'd1;
localparam [2:0] ST_DIV_START  = 3'd2;
localparam [2:0] ST_DIV_WAIT   = 3'd3;
localparam [2:0] ST_SQRT_START = 3'd4;
localparam [2:0] ST_SQRT_WAIT  = 3'd5;
localparam [2:0] ST_COMMIT     = 3'd6;

localparam [DATA_WIDTH-1:0] CENTER_DEFAULT    = {1'b1, {(DATA_WIDTH - 1){1'b0}}};
localparam [31:0]           RMS_RAW_CLIP_VALUE = (32'd1 << (DATA_WIDTH - 1)) - 32'd1;

reg  [2:0]                          state;
reg  [N_WIDTH-1:0]                  sample_target_reg;
reg  [N_WIDTH-1:0]                  sample_count_reg;
reg  [ACC_WIDTH-1:0]                sum_u1_sq_reg;
reg  [ACC_WIDTH-1:0]                sum_u2_sq_reg;
reg  signed [ACC_WIDTH-1:0]         sum_ui_reg;
reg                                 u1_mean_div_start;
reg                                 u2_mean_div_start;
reg                                 active_p_div_start;
reg                                 u1_sqrt_start;
reg                                 u2_sqrt_start;
reg                                 u1_mean_div_done_seen;
reg                                 u2_mean_div_done_seen;
reg                                 active_p_div_done_seen;

wire signed [SAMPLE_DIFF_WIDTH-1:0] u1_centered_code;
wire signed [SAMPLE_DIFF_WIDTH-1:0] u2_centered_code;
wire signed [PRODUCT_WIDTH-1:0]     u1_square_signed;
wire signed [PRODUCT_WIDTH-1:0]     u2_square_signed;
wire signed [PRODUCT_WIDTH-1:0]     ui_product_signed;
wire [PRODUCT_WIDTH-1:0]            u1_square_unsigned;
wire [PRODUCT_WIDTH-1:0]            u2_square_unsigned;
wire [ACC_WIDTH-1:0]                div_round_bias;
wire [ACC_WIDTH-1:0]                sample_divisor_unsigned;

wire                                u1_mean_div_done;
wire                                u1_mean_div_zero;
wire [ACC_WIDTH-1:0]                u1_mean_div_quotient;
wire                                u2_mean_div_done;
wire                                u2_mean_div_zero;
wire [ACC_WIDTH-1:0]                u2_mean_div_quotient;
wire                                active_p_div_done;
wire                                active_p_div_zero;
wire signed [ACC_WIDTH-1:0]         active_p_div_quotient;
wire                                u1_sqrt_done;
wire [31:0]                         u1_sqrt_root;
wire                                u2_sqrt_done;
wire [31:0]                         u2_sqrt_root;
wire                                active_p_positive_overflow;
wire                                active_p_negative_overflow;
wire [DATA_WIDTH-1:0]               u1_zero_ref_code;
wire [DATA_WIDTH-1:0]               u2_zero_ref_code;

assign busy           = (state != ST_IDLE);
assign config_error   = 1'b0;
assign frame_overflow = 1'b0;

// 选择当前窗口使用的零点参考；若零点参考暂不可用，则退回到偏移二进制中心码。
assign u1_zero_ref_code = u1_zero_valid ? u1_zero_code : CENTER_DEFAULT;
assign u2_zero_ref_code = u2_zero_valid ? u2_zero_code : CENTER_DEFAULT;

// 将采样码统一转换成相对动态零点的有符号偏移量，只保留交流分量参与总体 RMS 和总体功率统计。
assign u1_centered_code = $signed({1'b0, u1_sample_code}) - $signed({1'b0, u1_zero_ref_code});
assign u2_centered_code = $signed({1'b0, u2_sample_code}) - $signed({1'b0, u2_zero_ref_code});

// 计算U1平方项，供同窗口真实 RMS 统计使用。
multiplier_signed #(
    .A_WIDTH(SAMPLE_DIFF_WIDTH),
    .B_WIDTH(SAMPLE_DIFF_WIDTH)
) u_u1_square_multiplier (
    .multiplicand(u1_centered_code),
    .multiplier  (u1_centered_code),
    .product     (u1_square_signed)
);

// 计算U2平方项，供同窗口真实 RMS 统计使用。
multiplier_signed #(
    .A_WIDTH(SAMPLE_DIFF_WIDTH),
    .B_WIDTH(SAMPLE_DIFF_WIDTH)
) u_u2_square_multiplier (
    .multiplicand(u2_centered_code),
    .multiplier  (u2_centered_code),
    .product     (u2_square_signed)
);

// 计算瞬时功率项，供同窗口平均有功功率统计使用。
multiplier_signed #(
    .A_WIDTH(SAMPLE_DIFF_WIDTH),
    .B_WIDTH(SAMPLE_DIFF_WIDTH)
) u_ui_product_multiplier (
    .multiplicand(u1_centered_code),
    .multiplier  (u2_centered_code),
    .product     (ui_product_signed)
);

assign u1_square_unsigned = u1_square_signed[PRODUCT_WIDTH-1] ? {PRODUCT_WIDTH{1'b0}} : u1_square_signed[PRODUCT_WIDTH-1:0];
assign u2_square_unsigned = u2_square_signed[PRODUCT_WIDTH-1] ? {PRODUCT_WIDTH{1'b0}} : u2_square_signed[PRODUCT_WIDTH-1:0];
assign sample_divisor_unsigned = {{(ACC_WIDTH - N_WIDTH){1'b0}}, sample_target_reg};
assign div_round_bias          = {{(ACC_WIDTH - N_WIDTH){1'b0}}, {1'b0, sample_target_reg[N_WIDTH-1:1]}};

// 对U1平方和做均值换算，得到开方前的均方值。
divider_unsigned #(
    .WIDTH(ACC_WIDTH)
) u_u1_mean_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (u1_mean_div_start),
    .dividend      (sum_u1_sq_reg + div_round_bias),
    .divisor       (sample_divisor_unsigned),
    .busy          (),
    .done          (u1_mean_div_done),
    .divide_by_zero(u1_mean_div_zero),
    .quotient      (u1_mean_div_quotient)
);

// 对U2平方和做均值换算，得到开方前的均方值。
divider_unsigned #(
    .WIDTH(ACC_WIDTH)
) u_u2_mean_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (u2_mean_div_start),
    .dividend      (sum_u2_sq_reg + div_round_bias),
    .divisor       (sample_divisor_unsigned),
    .busy          (),
    .done          (u2_mean_div_done),
    .divide_by_zero(u2_mean_div_zero),
    .quotient      (u2_mean_div_quotient)
);

// 对瞬时功率和做均值换算，得到同窗口平均有功功率 raw。
divider_signed #(
    .WIDTH(ACC_WIDTH)
) u_active_p_mean_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (active_p_div_start),
    .dividend      (sum_ui_reg),
    .divisor       ($signed(sample_divisor_unsigned)),
    .busy          (),
    .done          (active_p_div_done),
    .divide_by_zero(active_p_div_zero),
    .quotient      (active_p_div_quotient)
);

// 对U1均方值开方，得到U1 RMS raw。
sqrt_unsigned #(
    .RADICAND_WIDTH(ACC_WIDTH),
    .ROOT_WIDTH    (32)
) u_u1_rms_sqrt (
    .clk     (clk),
    .rst_n   (rst_n),
    .start   (u1_sqrt_start),
    .radicand(u1_mean_div_quotient),
    .busy    (),
    .done    (u1_sqrt_done),
    .root    (u1_sqrt_root)
);

// 对U2均方值开方，得到U2 RMS raw。
sqrt_unsigned #(
    .RADICAND_WIDTH(ACC_WIDTH),
    .ROOT_WIDTH    (32)
) u_u2_rms_sqrt (
    .clk     (clk),
    .rst_n   (rst_n),
    .start   (u2_sqrt_start),
    .radicand(u2_mean_div_quotient),
    .busy    (),
    .done    (u2_sqrt_done),
    .root    (u2_sqrt_root)
);

assign active_p_positive_overflow = !active_p_div_quotient[ACC_WIDTH-1] &&
                                    (|active_p_div_quotient[ACC_WIDTH-2:31]);
assign active_p_negative_overflow = active_p_div_quotient[ACC_WIDTH-1] &&
                                    (~&active_p_div_quotient[ACC_WIDTH-2:31]);

// 顺序完成同窗口采样累计、均值换算、开方和最终结果提交。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state              <= ST_IDLE;
        sample_target_reg  <= {N_WIDTH{1'b0}};
        sample_count_reg   <= {N_WIDTH{1'b0}};
        sum_u1_sq_reg         <= {ACC_WIDTH{1'b0}};
        sum_u2_sq_reg         <= {ACC_WIDTH{1'b0}};
        sum_ui_reg         <= {ACC_WIDTH{1'b0}};
        u1_mean_div_start   <= 1'b0;
        u2_mean_div_start   <= 1'b0;
        active_p_div_start <= 1'b0;
        u1_sqrt_start       <= 1'b0;
        u2_sqrt_start       <= 1'b0;
        u1_mean_div_done_seen <= 1'b0;
        u2_mean_div_done_seen <= 1'b0;
        active_p_div_done_seen <= 1'b0;
        done               <= 1'b0;
        rms_valid          <= 1'b0;
        active_p_valid     <= 1'b0;
        u1_rms_raw          <= 32'sd0;
        u2_rms_raw          <= 32'sd0;
        active_p_raw       <= 32'sd0;
    end else begin
        done               <= 1'b0;
        rms_valid          <= 1'b0;
        active_p_valid     <= 1'b0;
        u1_mean_div_start   <= 1'b0;
        u2_mean_div_start   <= 1'b0;
        active_p_div_start <= 1'b0;
        u1_sqrt_start       <= 1'b0;
        u2_sqrt_start       <= 1'b0;

        if (u1_mean_div_done)
            u1_mean_div_done_seen <= 1'b1;
        if (u2_mean_div_done)
            u2_mean_div_done_seen <= 1'b1;
        if (active_p_div_done)
            active_p_div_done_seen <= 1'b1;

        case (state)
            ST_IDLE: begin
                if (start) begin
                    sample_target_reg <= sample_count_n;
                    sample_count_reg  <= {N_WIDTH{1'b0}};
                    sum_u1_sq_reg        <= {ACC_WIDTH{1'b0}};
                    sum_u2_sq_reg        <= {ACC_WIDTH{1'b0}};
                    sum_ui_reg        <= {ACC_WIDTH{1'b0}};
                    u1_rms_raw         <= 32'sd0;
                    u2_rms_raw         <= 32'sd0;
                    active_p_raw      <= 32'sd0;
                    u1_mean_div_done_seen <= 1'b0;
                    u2_mean_div_done_seen <= 1'b0;
                    active_p_div_done_seen <= 1'b0;

                    if (sample_count_n == {N_WIDTH{1'b0}}) begin
                        done  <= 1'b1;
                        state <= ST_IDLE;
                    end else begin
                        state <= ST_CAPTURE;
                    end
                end
            end

            ST_CAPTURE: begin
                if (sample_valid) begin
                    sum_u1_sq_reg <= sum_u1_sq_reg + {{(ACC_WIDTH - PRODUCT_WIDTH){1'b0}}, u1_square_unsigned};
                    sum_u2_sq_reg <= sum_u2_sq_reg + {{(ACC_WIDTH - PRODUCT_WIDTH){1'b0}}, u2_square_unsigned};
                    sum_ui_reg <= sum_ui_reg + {{(ACC_WIDTH - PRODUCT_WIDTH){ui_product_signed[PRODUCT_WIDTH-1]}}, ui_product_signed};

                    if (sample_count_reg == (sample_target_reg - {{(N_WIDTH - 1){1'b0}}, 1'b1})) begin
                        sample_count_reg <= {N_WIDTH{1'b0}};
                        state            <= ST_DIV_START;
                    end else begin
                        sample_count_reg <= sample_count_reg + {{(N_WIDTH - 1){1'b0}}, 1'b1};
                    end
                end
            end

            ST_DIV_START: begin
                u1_mean_div_start   <= 1'b1;
                u2_mean_div_start   <= 1'b1;
                active_p_div_start <= 1'b1;
                state              <= ST_DIV_WAIT;
            end

            ST_DIV_WAIT: begin
                if ((u1_mean_div_done_seen || u1_mean_div_done) &&
                    (u2_mean_div_done_seen || u2_mean_div_done) &&
                    (active_p_div_done_seen || active_p_div_done))
                    state <= ST_SQRT_START;
            end

            ST_SQRT_START: begin
                u1_sqrt_start <= 1'b1;
                u2_sqrt_start <= 1'b1;
                state        <= ST_SQRT_WAIT;
            end

            ST_SQRT_WAIT: begin
                if (u1_sqrt_done && u2_sqrt_done)
                    state <= ST_COMMIT;
            end

            ST_COMMIT: begin
                if (u1_mean_div_zero)
                    u1_rms_raw <= 32'sd0;
                else if (u1_sqrt_root > RMS_RAW_CLIP_VALUE)
                    u1_rms_raw <= {1'b0, RMS_RAW_CLIP_VALUE[30:0]};
                else
                    u1_rms_raw <= {1'b0, u1_sqrt_root[30:0]};

                if (u2_mean_div_zero)
                    u2_rms_raw <= 32'sd0;
                else if (u2_sqrt_root > RMS_RAW_CLIP_VALUE)
                    u2_rms_raw <= {1'b0, RMS_RAW_CLIP_VALUE[30:0]};
                else
                    u2_rms_raw <= {1'b0, u2_sqrt_root[30:0]};

                if (active_p_div_zero)
                    active_p_raw <= 32'sd0;
                else if (active_p_positive_overflow)
                    active_p_raw <= 32'sh7FFF_FFFF;
                else if (active_p_negative_overflow)
                    active_p_raw <= -32'sh7FFF_FFFF;
                else
                    active_p_raw <= active_p_div_quotient[31:0];

                rms_valid      <= 1'b1;
                active_p_valid <= 1'b1;
                done           <= 1'b1;
                state          <= ST_IDLE;
            end

            default: begin
                state <= ST_IDLE;
            end
        endcase
    end
end

endmodule
