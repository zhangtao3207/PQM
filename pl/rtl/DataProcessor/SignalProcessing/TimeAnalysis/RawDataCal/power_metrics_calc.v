`timescale 1ns / 1ps

/*
 * 模块: power_metrics_calc
 * 功能:
 *   基于同窗口 RMS raw、同窗口平均有功功率 raw 和时域相位 raw，
 *   计算总体视在功率、无功功率和功率因数 raw。
 *   其中有功功率直接使用同窗口平均瞬时功率，不再由 RMS 与 cos(phi) 反推。
 * 输入:
 *   clk: 工作时钟。
 *   rst_n: 低有效复位。
 *   start: 启动一次功率 raw 计算。
 *   rms_valid: U1/U2 RMS raw 是否有效。
 *   active_p_valid: 同窗口平均有功功率 raw 是否有效。
 *   u1_rms_code: U1 RMS 原始补码值。
 *   u2_rms_code: U2 RMS 原始补码值。
 *   active_p_input_raw: 同窗口平均有功功率原始补码值。
 *   phase_offset_raw: 相位偏移 raw 计数，仅用于无功符号判定。
 *   phase_period_raw: 相位周期 raw 计数，仅用于无功符号判定。
 *   phase_valid: 相位 raw 是否有效。
 * 输出:
 *   busy: 当前功率 raw 计算是否仍在进行。
 *   done: 本次功率 raw 计算完成脉冲。
 *   active_p_raw: 有功功率原始补码值。
 *   reactive_q_raw: 无功功率原始补码值。
 *   apparent_s_raw: 视在功率原始补码值。
 *   power_factor_raw: 功率因数原始补码值，量纲为 x10000。
 *   power_metrics_valid: 本次功率 raw 结果是否有效。
 */
module power_metrics_calc #(
    parameter integer WIDTH = 16
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    start,
    input  wire                    rms_valid,
    input  wire                    active_p_valid,
    input  wire signed [WIDTH-1:0] u1_rms_code,
    input  wire signed [WIDTH-1:0] u2_rms_code,
    input  wire signed [31:0]      active_p_input_raw,
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

localparam integer APPARENT_RAW_BITS = WIDTH + WIDTH;

localparam [2:0] ST_IDLE           = 3'd0;
localparam [2:0] ST_PF_START       = 3'd1;
localparam [2:0] ST_PF_WAIT        = 3'd2;
localparam [2:0] ST_REACTIVE_START = 3'd3;
localparam [2:0] ST_REACTIVE_WAIT  = 3'd4;
localparam [2:0] ST_COMMIT         = 3'd5;

localparam [15:0] PF_SCALE_NUM      = 16'd10000;
localparam [15:0] PF_SCALE_NUM_CLIP = 16'd10000;

reg  [2:0]               state;
reg  signed [WIDTH-1:0]  work_u1_rms_code;
reg  signed [WIDTH-1:0]  work_u2_rms_code;
reg  signed [31:0]       work_active_p_raw;
reg  signed [31:0]       work_phase_offset_raw;
reg  signed [31:0]       work_phase_period_raw;
reg                      pf_div_start;
reg                      reactive_sqrt_start;
reg  [31:0]              apparent_s_raw_reg;
reg  signed [31:0]       active_p_raw_reg;
reg                      reactive_q_neg_reg;

wire [WIDTH-1:0]         u1_rms_mag_work;
wire [WIDTH-1:0]         u2_rms_mag_work;
wire signed [APPARENT_RAW_BITS-1:0] rms_code_prod_signed;
wire [31:0]              apparent_raw_unsigned;

wire [31:0]              active_p_abs_work;
wire                     active_p_neg_work;
wire [31:0]              phase_offset_abs;
wire                     phase_negative_calc;

wire signed [47:0]       pf_scale_product_signed;
wire [47:0]              pf_scale_product_unsigned;
wire [47:0]              pf_divisor_unsigned;
wire                     pf_div_done;
wire                     pf_div_zero;
wire [47:0]              pf_div_quotient;

wire signed [63:0]       apparent_sq_signed;
wire signed [63:0]       active_sq_signed;
wire [63:0]              apparent_sq_unsigned;
wire [63:0]              active_sq_unsigned;
wire [63:0]              reactive_sq_unsigned;
wire                     reactive_sqrt_done;
wire [31:0]              reactive_sqrt_root;

assign busy = (state != ST_IDLE);

// 将 RMS raw 统一按正幅值处理，负值输入视为无效并按 0 处理。
assign u1_rms_mag_work = work_u1_rms_code[WIDTH-1] ? {WIDTH{1'b0}} : work_u1_rms_code[WIDTH-1:0];
assign u2_rms_mag_work = work_u2_rms_code[WIDTH-1] ? {WIDTH{1'b0}} : work_u2_rms_code[WIDTH-1:0];

// 直接计算视在功率 raw = Urms_raw * Irms_raw。
multiplier_signed #(
    .A_WIDTH(WIDTH),
    .B_WIDTH(WIDTH)
) u_rms_code_multiplier (
    .multiplicand({1'b0, u1_rms_mag_work[WIDTH-2:0]}),
    .multiplier  ({1'b0, u2_rms_mag_work[WIDTH-2:0]}),
    .product     (rms_code_prod_signed)
);

assign apparent_raw_unsigned = rms_code_prod_signed[APPARENT_RAW_BITS-1] ?
                               32'd0 : {{(32 - APPARENT_RAW_BITS){1'b0}}, rms_code_prod_signed[APPARENT_RAW_BITS-1:0]};

// 提取同窗口平均有功功率的绝对值与符号，供 PF 和 Q 计算复用。
assign active_p_abs_work = work_active_p_raw[31] ? (~work_active_p_raw + 32'd1) : work_active_p_raw[31:0];
assign active_p_neg_work = work_active_p_raw[31] && (active_p_abs_work != 32'd0);

// 提取相位偏移绝对值，并根据是否跨过半周期判定 Q 的正负号。
assign phase_offset_abs   = work_phase_offset_raw[31] ? (~work_phase_offset_raw + 32'd1) : work_phase_offset_raw[31:0];
assign phase_negative_calc = !work_phase_period_raw[31] &&
                             (work_phase_period_raw != 32'sd0) &&
                             (phase_offset_abs > {1'b0, work_phase_period_raw[31:1]}) &&
                             (phase_offset_abs < work_phase_period_raw[31:0]);

// 计算 |P| * 10000，供功率因数 raw 计算使用。
multiplier_signed #(
    .A_WIDTH(32),
    .B_WIDTH(16)
) u_pf_scale_multiplier (
    .multiplicand({1'b0, active_p_abs_work[30:0]}),
    .multiplier  (PF_SCALE_NUM),
    .product     (pf_scale_product_signed)
);

assign pf_scale_product_unsigned = pf_scale_product_signed[47] ? 48'd0 : pf_scale_product_signed[47:0];
assign pf_divisor_unsigned       = {16'd0, apparent_raw_unsigned};

// 对 |P| / S 做归一化，得到 x10000 量纲的功率因数原始值。
divider_unsigned #(
    .WIDTH(48)
) u_power_factor_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (pf_div_start),
    .dividend      (pf_scale_product_unsigned + {16'd0, apparent_raw_unsigned[31:1]}),
    .divisor       (pf_divisor_unsigned),
    .busy          (),
    .done          (pf_div_done),
    .divide_by_zero(pf_div_zero),
    .quotient      (pf_div_quotient)
);

// 计算 S^2，供 Q = sqrt(S^2 - P^2) 使用。
multiplier_signed #(
    .A_WIDTH(32),
    .B_WIDTH(32)
) u_apparent_square_multiplier (
    .multiplicand({1'b0, apparent_s_raw_reg[30:0]}),
    .multiplier  ({1'b0, apparent_s_raw_reg[30:0]}),
    .product     (apparent_sq_signed)
);

// 计算 P^2，供 Q = sqrt(S^2 - P^2) 使用。
multiplier_signed #(
    .A_WIDTH(32),
    .B_WIDTH(32)
) u_active_square_multiplier (
    .multiplicand({1'b0, active_p_abs_work[30:0]}),
    .multiplier  ({1'b0, active_p_abs_work[30:0]}),
    .product     (active_sq_signed)
);

assign apparent_sq_unsigned = apparent_sq_signed[63] ? 64'd0 : apparent_sq_signed[63:0];
assign active_sq_unsigned   = active_sq_signed[63] ? 64'd0 : active_sq_signed[63:0];
assign reactive_sq_unsigned = (apparent_sq_unsigned > active_sq_unsigned) ?
                              (apparent_sq_unsigned - active_sq_unsigned) : 64'd0;

// 对无功功率平方值开方，得到 |Q| raw。
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

// 顺序完成 PF raw、Q raw 与最终功率结果提交。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state               <= ST_IDLE;
        work_u1_rms_code     <= {WIDTH{1'b0}};
        work_u2_rms_code     <= {WIDTH{1'b0}};
        work_active_p_raw   <= 32'sd0;
        work_phase_offset_raw <= 32'sd0;
        work_phase_period_raw <= 32'sd0;
        pf_div_start        <= 1'b0;
        reactive_sqrt_start <= 1'b0;
        apparent_s_raw_reg  <= 32'd0;
        active_p_raw_reg    <= 32'sd0;
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
        pf_div_start        <= 1'b0;
        reactive_sqrt_start <= 1'b0;

        case (state)
            ST_IDLE: begin
                if (start) begin
                    if (rms_valid && active_p_valid && phase_valid) begin
                        work_u1_rms_code       <= u1_rms_code;
                        work_u2_rms_code       <= u2_rms_code;
                        work_active_p_raw     <= active_p_input_raw;
                        work_phase_offset_raw <= phase_offset_raw;
                        work_phase_period_raw <= phase_period_raw;
                        state                 <= ST_PF_START;
                    end else begin
                        done  <= 1'b1;
                        state <= ST_IDLE;
                    end
                end
            end

            ST_PF_START: begin
                apparent_s_raw_reg <= apparent_raw_unsigned;
                active_p_raw_reg   <= work_active_p_raw;
                pf_div_start       <= 1'b1;
                state              <= ST_PF_WAIT;
            end

            ST_PF_WAIT: begin
                if (pf_div_done)
                    state <= ST_REACTIVE_START;
            end

            ST_REACTIVE_START: begin
                reactive_sqrt_start <= 1'b1;
                reactive_q_neg_reg  <= phase_negative_calc;
                state               <= ST_REACTIVE_WAIT;
            end

            ST_REACTIVE_WAIT: begin
                if (reactive_sqrt_done)
                    state <= ST_COMMIT;
            end

            ST_COMMIT: begin
                apparent_s_raw <= {1'b0, apparent_s_raw_reg[30:0]};
                active_p_raw   <= active_p_raw_reg;

                if (reactive_q_neg_reg && (reactive_sqrt_root != 32'd0))
                    reactive_q_raw <= ~reactive_sqrt_root + 32'd1;
                else
                    reactive_q_raw <= {1'b0, reactive_sqrt_root[30:0]};

                if (pf_div_zero)
                    power_factor_raw <= 32'sd0;
                else if ((pf_div_quotient[47:16] != 32'd0) || (pf_div_quotient[15:0] > PF_SCALE_NUM_CLIP))
                    power_factor_raw <= active_p_neg_work ? (~{16'd0, PF_SCALE_NUM_CLIP} + 32'd1) : {16'd0, PF_SCALE_NUM_CLIP};
                else if (active_p_neg_work && (pf_div_quotient[15:0] != 16'd0))
                    power_factor_raw <= ~{16'd0, pf_div_quotient[15:0]} + 32'd1;
                else
                    power_factor_raw <= {16'd0, pf_div_quotient[15:0]};

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
