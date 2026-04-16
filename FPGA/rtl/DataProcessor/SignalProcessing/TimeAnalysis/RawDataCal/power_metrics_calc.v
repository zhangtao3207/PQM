`timescale 1ns / 1ps

/*
 * 模块: power_metrics_calc
 * 功能:
 *   基于 RMS 原始码值和相位偏移/周期 raw，计算功率相关原始量。
 *   本模块只输出 raw 数据，不在模块内部执行 P/Q/S/Factor 的 x100 换算。
 * 输入:
 *   clk: 工作时钟。
 *   rst_n: 低有效复位。
 *   start: 启动一次功率原始量计算。
 *   rms_valid: RMS 原始结果是否有效。
 *   u_rms_code: 电压 RMS 原始补码值。
 *   i_rms_code: 电流 RMS 原始补码值。
 *   phase_offset_raw: 相位差原始偏移计数，用于功率原始量推导。
 *   phase_period_raw: 相位差原始周期计数，用于功率原始量推导。
 *   phase_valid: 相位输入是否有效。
 * 输出:
 *   busy: 当前功率原始量计算流程是否仍在进行。
 *   done: 本次计算完成时给出的完成脉冲。
 *   active_p_raw: 有功功率原始值，单位为 RMS 码值乘积投影后的补码量。
 *   reactive_q_raw: 无功功率原始值，单位为 RMS 码值乘积投影后的补码量。
 *   apparent_s_raw: 视在功率原始值，单位为 RMS 码值乘积的补码量。
 *   power_factor_raw: 功率因数原始值，使用 cos(phi) 的 x10000 补码量。
 *   power_metrics_valid: 本次功率原始量结果是否有效。
 */
module power_metrics_calc #(
    parameter integer WIDTH = 16
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    start,
    input  wire                    rms_valid,
    input  wire signed [WIDTH-1:0] u_rms_code,
    input  wire signed [WIDTH-1:0] i_rms_code,
    input  wire signed [31:0]      phase_offset_raw,
    input  wire signed [31:0]      phase_period_raw,
    input  wire                    phase_valid,
    output wire                    busy,
    output reg                     done,
    output reg  signed [31:0]      active_p_raw,
    output reg  signed [31:0]      reactive_q_raw,
    output reg  signed [31:0]      apparent_s_raw,
    output reg  signed [31:0]      power_factor_raw,
    output reg                     power_metrics_valid
);

localparam integer APPARENT_RAW_BITS = (WIDTH + WIDTH) - 1;
localparam [47:0]  COS_SCALE_DEN      = 48'd10000;
localparam [47:0]  COS_SCALE_DEN_HALF = 48'd5000;
localparam [3:0]   ST_IDLE            = 4'd0;
localparam [3:0]   ST_COS_START       = 4'd1;
localparam [3:0]   ST_COS_WAIT        = 4'd2;
localparam [3:0]   ST_ACTIVE_START    = 4'd3;
localparam [3:0]   ST_ACTIVE_WAIT     = 4'd4;
localparam [3:0]   ST_REACTIVE_START  = 4'd5;
localparam [3:0]   ST_REACTIVE_WAIT   = 4'd6;
localparam [3:0]   ST_COMMIT          = 4'd7;

reg  [3:0]               state;
reg  signed [WIDTH-1:0]  work_u_rms_code;
reg  signed [WIDTH-1:0]  work_i_rms_code;
reg  signed [31:0]       work_phase_offset_raw;
reg  signed [31:0]       work_phase_period_raw;

reg                      cos_start;
wire                     cos_valid;
wire                     phase_neg_calc;
wire signed [15:0]       cos_x10000_signed;
wire                     cos_neg_calc;
wire [15:0]              cos_x10000_abs;

wire [WIDTH-1:0]         u_rms_mag_work;
wire [WIDTH-1:0]         i_rms_mag_work;
wire signed [(WIDTH+WIDTH)-1:0] rms_code_prod_signed;
wire [31:0]              apparent_raw_unsigned;

wire [47:0]              active_p_scale_prod_unsigned;
reg                      active_p_div_start;
wire                     active_p_div_done;
wire                     active_p_div_zero;
wire [47:0]              active_p_div_quotient;

wire signed [63:0]       apparent_sq_signed;
wire signed [63:0]       active_sq_signed;
wire [63:0]              apparent_sq_unsigned;
wire [63:0]              active_sq_unsigned;
wire [63:0]              reactive_sq_unsigned;
reg                      reactive_sqrt_start;
wire                     reactive_sqrt_done;
wire [31:0]              reactive_sqrt_root;

reg  [31:0]              apparent_s_raw_reg;
reg  [31:0]              active_p_raw_reg;
reg  [31:0]              reactive_q_raw_reg;
reg                      active_p_neg_reg;
reg                      reactive_q_neg_reg;

// 只要状态机离开空闲态，就表示功率原始量计算仍在进行。
assign busy = (state != ST_IDLE);

// 将 RMS 原始补码量取幅值，负数统一按 0 处理，避免后续原始乘积无意义。
assign u_rms_mag_work   = work_u_rms_code[WIDTH-1] ? {WIDTH{1'b0}} : work_u_rms_code[WIDTH-1:0];
assign i_rms_mag_work   = work_i_rms_code[WIDTH-1] ? {WIDTH{1'b0}} : work_i_rms_code[WIDTH-1:0];
assign cos_neg_calc     = cos_x10000_signed[15];
assign cos_x10000_abs   = cos_neg_calc ? (~cos_x10000_signed + 16'd1) : cos_x10000_signed;
assign apparent_raw_unsigned = {{(32-APPARENT_RAW_BITS){1'b0}}, rms_code_prod_signed[(WIDTH+WIDTH)-2:0]};

// 计算 RMS 原始码值乘积，作为视在功率 raw 的基础量。
multiplier_signed #(
    .A_WIDTH(WIDTH),
    .B_WIDTH(WIDTH)
) u_rms_code_multiplier (
    .multiplicand({1'b0, u_rms_mag_work[WIDTH-2:0]}),
    .multiplier  ({1'b0, i_rms_mag_work[WIDTH-2:0]}),
    .product     (rms_code_prod_signed)
);

// 根据相位 x100 查表得到 cos(phi) 原始量，供有功和功率因数 raw 计算使用。
// 直接根据相位偏移/周期 raw 计算 cos(phi) 和相位正负，避免在功率模块内再生成 phase_x100。
cos_lookup_raw_x10000 u_cos_lookup_raw_x10000 (
    .clk              (clk),
    .rst_n            (rst_n),
    .start            (cos_start),
    .phase_offset_raw (work_phase_offset_raw),
    .phase_period_raw (work_phase_period_raw),
    .busy             (),
    .valid            (cos_valid),
    .phase_neg        (phase_neg_calc),
    .cos_x10000_signed(cos_x10000_signed)
);

// 将视在功率 raw 与 |cos(phi)| 相乘，构造有功功率 raw 的分子。
multiplier_signed #(
    .A_WIDTH(32),
    .B_WIDTH(16)
) u_active_p_multiplier (
    .multiplicand({1'b0, apparent_s_raw_reg[30:0]}),
    .multiplier  ({1'b0, cos_x10000_abs[14:0]}),
    .product     (active_p_scale_prod_unsigned)
);

// 对乘积除以 10000，得到与视在功率 raw 同量纲的有功功率 raw。
divider_unsigned #(
    .WIDTH(48)
) u_active_p_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (active_p_div_start),
    .dividend      (active_p_scale_prod_unsigned + COS_SCALE_DEN_HALF),
    .divisor       (COS_SCALE_DEN),
    .busy          (),
    .done          (active_p_div_done),
    .divide_by_zero(active_p_div_zero),
    .quotient      (active_p_div_quotient)
);

// 计算视在功率 raw 的平方，供后续无功功率 raw 开方前使用。
multiplier_signed #(
    .A_WIDTH(32),
    .B_WIDTH(32)
) u_apparent_square_multiplier (
    .multiplicand({1'b0, apparent_s_raw_reg[30:0]}),
    .multiplier  ({1'b0, apparent_s_raw_reg[30:0]}),
    .product     (apparent_sq_signed)
);

// 计算有功功率 raw 的平方，与视在功率平方共同构造无功功率平方。
multiplier_signed #(
    .A_WIDTH(32),
    .B_WIDTH(32)
) u_active_square_multiplier (
    .multiplicand({1'b0, active_p_raw_reg[30:0]}),
    .multiplier  ({1'b0, active_p_raw_reg[30:0]}),
    .product     (active_sq_signed)
);

// 组合得到无功功率 raw 开方所需的被开方数，负差值时钳位为 0。
assign apparent_sq_unsigned = apparent_sq_signed[63] ? 64'd0 : apparent_sq_signed[63:0];
assign active_sq_unsigned   = active_sq_signed[63] ? 64'd0 : active_sq_signed[63:0];
assign reactive_sq_unsigned = (apparent_sq_unsigned > active_sq_unsigned) ?
                              (apparent_sq_unsigned - active_sq_unsigned) : 64'd0;

// 对无功功率平方开方，得到无功功率 raw 的幅值。
sqrt_unsigned #(
    .RADICAND_WIDTH(64),
    .ROOT_WIDTH    (32)
) u_reactive_q_sqrt (
    .clk     (clk),
    .rst_n   (rst_n),
    .start   (reactive_sqrt_start),
    .radicand(reactive_sq_unsigned),
    .busy    (),
    .done    (reactive_sqrt_done),
    .root    (reactive_sqrt_root)
);

// 顺序完成 cos 查表、有功 raw、无功 raw 和最终原始量提交。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state               <= ST_IDLE;
        work_u_rms_code        <= {WIDTH{1'b0}};
        work_i_rms_code        <= {WIDTH{1'b0}};
        work_phase_offset_raw  <= 32'sd0;
        work_phase_period_raw  <= 32'sd0;
        cos_start           <= 1'b0;
        active_p_div_start  <= 1'b0;
        reactive_sqrt_start <= 1'b0;
        apparent_s_raw_reg  <= 32'd0;
        active_p_raw_reg    <= 32'd0;
        reactive_q_raw_reg  <= 32'd0;
        active_p_neg_reg    <= 1'b0;
        reactive_q_neg_reg  <= 1'b0;
        done                <= 1'b0;
        active_p_raw        <= 32'sd0;
        reactive_q_raw      <= 32'sd0;
        apparent_s_raw      <= 32'sd0;
        power_factor_raw    <= 32'sd0;
        power_metrics_valid <= 1'b0;
    end else begin
        done                <= 1'b0;
        power_metrics_valid <= 1'b0;
        cos_start           <= 1'b0;
        active_p_div_start  <= 1'b0;
        reactive_sqrt_start <= 1'b0;

        case (state)
            ST_IDLE: begin
                if (start) begin
                    if (rms_valid && phase_valid) begin
                        work_u_rms_code       <= u_rms_code;
                        work_i_rms_code       <= i_rms_code;
                        work_phase_offset_raw <= phase_offset_raw;
                        work_phase_period_raw <= phase_period_raw;
                        state                 <= ST_COS_START;
                    end else begin
                        done  <= 1'b1;
                        state <= ST_IDLE;
                    end
                end
            end

            ST_COS_START: begin
                cos_start <= 1'b1;
                state     <= ST_COS_WAIT;
            end

            ST_COS_WAIT: begin
                if (cos_valid) begin
                    apparent_s_raw_reg <= apparent_raw_unsigned;
                    active_p_neg_reg   <= cos_neg_calc;
                    state              <= ST_ACTIVE_START;
                end
            end

            ST_ACTIVE_START: begin
                active_p_div_start <= 1'b1;
                state              <= ST_ACTIVE_WAIT;
            end

            ST_ACTIVE_WAIT: begin
                if (active_p_div_done) begin
                    if (active_p_div_zero || (active_p_div_quotient[47:32] != 16'd0))
                        active_p_raw_reg <= 32'd0;
                    else
                        active_p_raw_reg <= active_p_div_quotient[31:0];

                    state              <= ST_REACTIVE_START;
                end
            end

            ST_REACTIVE_START: begin
                reactive_sqrt_start <= 1'b1;
                state               <= ST_REACTIVE_WAIT;
            end

            ST_REACTIVE_WAIT: begin
                if (reactive_sqrt_done) begin
                    reactive_q_raw_reg <= reactive_sqrt_root;
                    reactive_q_neg_reg <= phase_neg_calc && (reactive_sqrt_root != 32'd0);
                    state              <= ST_COMMIT;
                end
            end

            ST_COMMIT: begin
                apparent_s_raw <= {1'b0, apparent_s_raw_reg[30:0]};

                if (active_p_neg_reg && (active_p_raw_reg != 32'd0))
                    active_p_raw <= ~active_p_raw_reg + 32'd1;
                else
                    active_p_raw <= {1'b0, active_p_raw_reg[30:0]};

                if (reactive_q_neg_reg && (reactive_q_raw_reg != 32'd0))
                    reactive_q_raw <= ~reactive_q_raw_reg + 32'd1;
                else
                    reactive_q_raw <= {1'b0, reactive_q_raw_reg[30:0]};

                power_factor_raw    <= {{16{cos_x10000_signed[15]}}, cos_x10000_signed};
                power_metrics_valid <= 1'b1;
                done                <= 1'b1;
                state               <= ST_IDLE;
            end

            default: begin
                state <= ST_IDLE;
            end
        endcase
    end
end

endmodule
