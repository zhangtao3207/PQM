`timescale 1ns / 1ps

/*
 * 模块: power_metrics_calc
 * 功能:
 *   基于原始 RMS 补码值和原始相位补码值，统一计算有功功率 P、无功功率 Q、
 *   视在功率 S 以及功率因数 Factor，并直接输出 LCD 显示需要的数字位。
 *
 * 输入:
 *   clk: 系统时钟
 *   rst_n: 低有效复位
 *   rms_valid: U/I 两路 RMS 原始码值有效脉冲
 *   u_rms_code: 电压 RMS 原始补码值
 *   i_rms_code: 电流 RMS 原始补码值
 *   phase_x100_signed: 相位差原始补码值，单位为 0.01°
 *   phase_valid: 相位差原始补码值有效脉冲
 *
 * 输出:
 *   active_p_neg 及 active_p_*: 有功功率显示符号和数字位
 *   reactive_q_neg 及 reactive_q_*: 无功功率显示符号和数字位
 *   apparent_s_*: 视在功率显示数字位
 *   power_factor_neg 及 power_factor_*: 功率因数显示符号和数字位
 *   power_metrics_valid: 本次功率参数全部更新完成脉冲
 *
 * 说明:
 *   - 本模块不再使用瞬时功率平均法，而是按 S = U_rms * I_rms、P = S * cos(phi)、
 *     Q = sqrt(S^2 - P^2)、Factor = cos(phi) 的链路统一计算。
 *   - RMS 先使用原始补码值参与计算，避免先换算到 x100 后再次截断。
 *   - 乘法、除法和开方均复用已有基础数学模块，不直接使用 "/", "*" 或 "%"。
 */
module power_metrics_calc #(
    parameter integer WIDTH             = 16,
    parameter integer WINDOW_SAMPLES    = 4096,
    parameter integer U_FULL_SCALE_X100 = 1000,
    parameter integer I_FULL_SCALE_X100 = 30
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    start,
    input  wire                    rms_valid,
    input  wire signed [WIDTH-1:0] u_rms_code,
    input  wire signed [WIDTH-1:0] i_rms_code,
    input  wire signed [16:0]      phase_x100_signed,
    input  wire                    phase_valid,
    output wire                    busy,
    output reg                     done,
    output reg                     active_p_neg,
    output reg  [7:0]              active_p_tens,
    output reg  [7:0]              active_p_units,
    output reg  [7:0]              active_p_decile,
    output reg  [7:0]              active_p_percentiles,
    output reg                     reactive_q_neg,
    output reg  [7:0]              reactive_q_tens,
    output reg  [7:0]              reactive_q_units,
    output reg  [7:0]              reactive_q_decile,
    output reg  [7:0]              reactive_q_percentiles,
    output reg  [7:0]              apparent_s_tens,
    output reg  [7:0]              apparent_s_units,
    output reg  [7:0]              apparent_s_decile,
    output reg  [7:0]              apparent_s_percentiles,
    output reg                     power_factor_neg,
    output reg  [7:0]              power_factor_units,
    output reg  [7:0]              power_factor_decile,
    output reg  [7:0]              power_factor_percentiles,
    output reg                     power_metrics_valid
);

localparam [95:0] RMS_SCALE_DEN      = 96'd107367628900;
localparam [95:0] RMS_SCALE_DEN_HALF = 96'd53683814450;
localparam [47:0] COS_SCALE_DEN      = 48'd10000;
localparam [47:0] COS_SCALE_DEN_HALF = 48'd5000;
localparam [15:0] PF_SCALE_DEN       = 16'd100;
localparam [15:0] PF_SCALE_DEN_HALF  = 16'd50;
localparam [31:0] VALUE_CLIP_X100    = 32'd9999;
localparam [31:0] PF_CLIP_X100       = 32'd100;

localparam [3:0] ST_IDLE      = 4'd0;
localparam [3:0] ST_COS_START = 4'd1;
localparam [3:0] ST_COS_WAIT  = 4'd2;
localparam [3:0] ST_SPF_START = 4'd3;
localparam [3:0] ST_SPF_WAIT  = 4'd4;
localparam [3:0] ST_P_START   = 4'd5;
localparam [3:0] ST_P_WAIT    = 4'd6;
localparam [3:0] ST_Q_START   = 4'd7;
localparam [3:0] ST_Q_WAIT    = 4'd8;
localparam [3:0] ST_COMMIT    = 4'd9;

reg  [3:0]               state;

reg  signed [WIDTH-1:0]  latest_u_rms_code;
reg  signed [WIDTH-1:0]  latest_i_rms_code;
reg  signed [16:0]       latest_phase_x100_signed;
reg                      latest_rms_valid;
reg                      latest_phase_valid;
reg                      calc_request_pending;

reg  signed [WIDTH-1:0]  work_u_rms_code;
reg  signed [WIDTH-1:0]  work_i_rms_code;
reg  signed [16:0]       work_phase_x100_signed;

reg                      cos_start;
wire                     cos_busy;
wire                     cos_valid;
wire signed [15:0]       cos_x10000_signed;
wire [15:0]              cos_x10000_abs;
wire                     cos_neg_calc;

wire [WIDTH-1:0]         u_rms_mag_work;
wire [WIDTH-1:0]         i_rms_mag_work;
wire signed [63:0]       full_scale_prod_signed;
wire signed [(2*WIDTH)-1:0] rms_code_prod_signed;
wire signed [95:0]       apparent_scale_prod_signed;
wire [95:0]              apparent_scale_prod_unsigned;
wire [95:0]              apparent_div_quotient;
wire                     apparent_div_done;
wire                     apparent_div_zero;
reg                      apparent_div_start;
reg                      apparent_done_latched;

wire [47:0]              active_p_scale_prod_unsigned;
wire [47:0]              active_p_div_quotient;
wire                     active_p_div_done;
wire                     active_p_div_zero;
reg                      active_p_div_start;

wire [15:0]              power_factor_div_quotient;
wire                     power_factor_div_done;
wire                     power_factor_div_zero;
reg                      power_factor_div_start;
reg                      power_factor_done_latched;

reg  [31:0]              apparent_s_x100_reg;
reg  [31:0]              active_p_x100_reg;
reg  [31:0]              reactive_q_x100_reg;
reg  [31:0]              power_factor_x100_reg;
reg                      active_p_neg_reg;
reg                      reactive_q_neg_reg;
reg                      power_factor_neg_reg;

wire signed [31:0]       u_full_scale_x100_signed;
wire signed [31:0]       i_full_scale_x100_signed;

wire signed [63:0]       apparent_sq_signed;
wire signed [63:0]       active_sq_signed;
wire [63:0]              apparent_sq_unsigned;
wire [63:0]              active_sq_unsigned;
wire [63:0]              reactive_sq_unsigned;
reg                      reactive_sqrt_start;
wire                     reactive_sqrt_done;
wire [31:0]              reactive_sqrt_root;

wire [7:0] active_p_tens_wire;
wire [7:0] active_p_units_wire;
wire [7:0] active_p_decile_wire;
wire [7:0] active_p_percentiles_wire;
wire [7:0] reactive_q_tens_wire;
wire [7:0] reactive_q_units_wire;
wire [7:0] reactive_q_decile_wire;
wire [7:0] reactive_q_percentiles_wire;
wire [7:0] apparent_s_tens_wire;
wire [7:0] apparent_s_units_wire;
wire [7:0] apparent_s_decile_wire;
wire [7:0] apparent_s_percentiles_wire;
wire [7:0] power_factor_tens_wire;
wire [7:0] power_factor_units_wire;
wire [7:0] power_factor_decile_wire;
wire [7:0] power_factor_percentiles_wire;

assign busy = (state != ST_IDLE) || calc_request_pending;

assign u_rms_mag_work = work_u_rms_code[WIDTH-1] ? {WIDTH{1'b0}} : work_u_rms_code[WIDTH-1:0];
assign i_rms_mag_work = work_i_rms_code[WIDTH-1] ? {WIDTH{1'b0}} : work_i_rms_code[WIDTH-1:0];
assign cos_neg_calc   = cos_x10000_signed[15];
assign cos_x10000_abs = cos_neg_calc ? (~cos_x10000_signed + 16'd1) : cos_x10000_signed;
assign u_full_scale_x100_signed = U_FULL_SCALE_X100;
assign i_full_scale_x100_signed = I_FULL_SCALE_X100;

// 满量程换算系数先相乘，再与 RMS 码值乘积组合成视在功率换算分子。
multiplier_signed #(
    .A_WIDTH(32),
    .B_WIDTH(32)
) u_full_scale_multiplier (
    .multiplicand(u_full_scale_x100_signed),
    .multiplier  (i_full_scale_x100_signed),
    .product     (full_scale_prod_signed)
);

multiplier_signed #(
    .A_WIDTH(WIDTH),
    .B_WIDTH(WIDTH)
) u_rms_code_multiplier (
    .multiplicand({1'b0, u_rms_mag_work[WIDTH-2:0]}),
    .multiplier  ({1'b0, i_rms_mag_work[WIDTH-2:0]}),
    .product     (rms_code_prod_signed)
);

multiplier_signed #(
    .A_WIDTH(64),
    .B_WIDTH(32)
) u_apparent_scale_multiplier (
    .multiplicand(full_scale_prod_signed),
    .multiplier  ({1'b0, rms_code_prod_signed[(2*WIDTH)-2:0]}),
    .product     (apparent_scale_prod_signed)
);

assign apparent_scale_prod_unsigned =
    apparent_scale_prod_signed[95] ? 96'd0 : apparent_scale_prod_signed[95:0];

divider_unsigned #(
    .WIDTH(96)
) u_apparent_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (apparent_div_start),
    .dividend      (apparent_scale_prod_unsigned + RMS_SCALE_DEN_HALF),
    .divisor       (RMS_SCALE_DEN),
    .busy          (),
    .done          (apparent_div_done),
    .divide_by_zero(apparent_div_zero),
    .quotient      (apparent_div_quotient)
);

// 有功功率 = 视在功率 * |cos(phi)| / 10000。
multiplier_signed #(
    .A_WIDTH(32),
    .B_WIDTH(16)
) u_active_p_multiplier (
    .multiplicand({1'b0, apparent_s_x100_reg[30:0]}),
    .multiplier  ({1'b0, cos_x10000_abs[14:0]}),
    .product     (active_p_scale_prod_unsigned)
);

divider_unsigned #(
    .WIDTH(48)
) u_active_p_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (active_p_div_start),
    .dividend      (active_p_scale_prod_unsigned + COS_SCALE_DEN_HALF),
    .divisor       ({32'd0, COS_SCALE_DEN}),
    .busy          (),
    .done          (active_p_div_done),
    .divide_by_zero(active_p_div_zero),
    .quotient      (active_p_div_quotient)
);

// 功率因数直接由 cos(phi) 幅值缩放得到，结果采用 x100。
divider_unsigned #(
    .WIDTH(16)
) u_power_factor_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (power_factor_div_start),
    .dividend      (cos_x10000_abs + PF_SCALE_DEN_HALF),
    .divisor       (PF_SCALE_DEN),
    .busy          (),
    .done          (power_factor_div_done),
    .divide_by_zero(power_factor_div_zero),
    .quotient      (power_factor_div_quotient)
);

multiplier_signed #(
    .A_WIDTH(32),
    .B_WIDTH(32)
) u_apparent_square_multiplier (
    .multiplicand({1'b0, apparent_s_x100_reg[30:0]}),
    .multiplier  ({1'b0, apparent_s_x100_reg[30:0]}),
    .product     (apparent_sq_signed)
);

multiplier_signed #(
    .A_WIDTH(32),
    .B_WIDTH(32)
) u_active_square_multiplier (
    .multiplicand({1'b0, active_p_x100_reg[30:0]}),
    .multiplier  ({1'b0, active_p_x100_reg[30:0]}),
    .product     (active_sq_signed)
);

assign apparent_sq_unsigned = apparent_sq_signed[63] ? 64'd0 : apparent_sq_signed[63:0];
assign active_sq_unsigned   = active_sq_signed[63] ? 64'd0 : active_sq_signed[63:0];
assign reactive_sq_unsigned = (apparent_sq_unsigned > active_sq_unsigned) ?
                              (apparent_sq_unsigned - active_sq_unsigned) : 64'd0;

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

cos_lookup_x10000 u_cos_lookup_x10000 (
    .clk              (clk),
    .rst_n            (rst_n),
    .start            (cos_start),
    .phase_x100_signed(work_phase_x100_signed),
    .busy             (cos_busy),
    .valid            (cos_valid),
    .cos_x10000_signed(cos_x10000_signed)
);

value_x100_to_digits u_active_p_digits (
    .value_x100  (active_p_x100_reg),
    .tens        (active_p_tens_wire),
    .units       (active_p_units_wire),
    .decile      (active_p_decile_wire),
    .percentiles (active_p_percentiles_wire)
);

value_x100_to_digits u_reactive_q_digits (
    .value_x100  (reactive_q_x100_reg),
    .tens        (reactive_q_tens_wire),
    .units       (reactive_q_units_wire),
    .decile      (reactive_q_decile_wire),
    .percentiles (reactive_q_percentiles_wire)
);

value_x100_to_digits u_apparent_s_digits (
    .value_x100  (apparent_s_x100_reg),
    .tens        (apparent_s_tens_wire),
    .units       (apparent_s_units_wire),
    .decile      (apparent_s_decile_wire),
    .percentiles (apparent_s_percentiles_wire)
);

value_x100_to_digits u_power_factor_digits (
    .value_x100  (power_factor_x100_reg),
    .tens        (power_factor_tens_wire),
    .units       (power_factor_units_wire),
    .decile      (power_factor_decile_wire),
    .percentiles (power_factor_percentiles_wire)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state                   <= ST_IDLE;
        latest_u_rms_code       <= {WIDTH{1'b0}};
        latest_i_rms_code       <= {WIDTH{1'b0}};
        latest_phase_x100_signed<= 17'sd0;
        latest_rms_valid        <= 1'b0;
        latest_phase_valid      <= 1'b0;
        calc_request_pending    <= 1'b0;
        work_u_rms_code         <= {WIDTH{1'b0}};
        work_i_rms_code         <= {WIDTH{1'b0}};
        work_phase_x100_signed  <= 17'sd0;
        cos_start               <= 1'b0;
        apparent_div_start      <= 1'b0;
        active_p_div_start      <= 1'b0;
        power_factor_div_start  <= 1'b0;
        reactive_sqrt_start     <= 1'b0;
        apparent_done_latched   <= 1'b0;
        power_factor_done_latched <= 1'b0;
        apparent_s_x100_reg     <= 32'd0;
        active_p_x100_reg       <= 32'd0;
        reactive_q_x100_reg     <= 32'd0;
        power_factor_x100_reg   <= 32'd0;
        active_p_neg_reg        <= 1'b0;
        reactive_q_neg_reg      <= 1'b0;
        power_factor_neg_reg    <= 1'b0;
        active_p_neg            <= 1'b0;
        active_p_tens           <= 8'd0;
        active_p_units          <= 8'd0;
        active_p_decile         <= 8'd0;
        active_p_percentiles    <= 8'd0;
        reactive_q_neg          <= 1'b0;
        reactive_q_tens         <= 8'd0;
        reactive_q_units        <= 8'd0;
        reactive_q_decile       <= 8'd0;
        reactive_q_percentiles  <= 8'd0;
        apparent_s_tens         <= 8'd0;
        apparent_s_units        <= 8'd0;
        apparent_s_decile       <= 8'd0;
        apparent_s_percentiles  <= 8'd0;
        power_factor_neg        <= 1'b0;
        power_factor_units      <= 8'd0;
        power_factor_decile     <= 8'd0;
        power_factor_percentiles<= 8'd0;
        done                    <= 1'b0;
        power_metrics_valid     <= 1'b0;
    end else begin
        done                   <= 1'b0;
        power_metrics_valid    <= 1'b0;
        cos_start              <= 1'b0;
        apparent_div_start     <= 1'b0;
        active_p_div_start     <= 1'b0;
        power_factor_div_start <= 1'b0;
        reactive_sqrt_start    <= 1'b0;

        if (start && (state == ST_IDLE) && !calc_request_pending) begin
            latest_u_rms_code        <= u_rms_code;
            latest_i_rms_code        <= i_rms_code;
            latest_phase_x100_signed <= phase_x100_signed;
            latest_rms_valid         <= rms_valid;
            latest_phase_valid       <= phase_valid;
            calc_request_pending     <= rms_valid && phase_valid;

            if (!(rms_valid && phase_valid)) begin
                done <= 1'b1;
            end
        end

        case (state)
            ST_IDLE: begin
                if (calc_request_pending && latest_rms_valid && latest_phase_valid) begin
                    work_u_rms_code        <= latest_u_rms_code;
                    work_i_rms_code        <= latest_i_rms_code;
                    work_phase_x100_signed <= latest_phase_x100_signed;
                    calc_request_pending   <= 1'b0;
                    state                  <= ST_COS_START;
                end
            end

            ST_COS_START: begin
                cos_start <= 1'b1;
                state     <= ST_COS_WAIT;
            end

            ST_COS_WAIT: begin
                if (cos_valid) begin
                    apparent_done_latched     <= 1'b0;
                    power_factor_done_latched <= 1'b0;
                    state                     <= ST_SPF_START;
                end
            end

            ST_SPF_START: begin
                apparent_div_start     <= 1'b1;
                power_factor_div_start <= 1'b1;
                state                  <= ST_SPF_WAIT;
            end

            ST_SPF_WAIT: begin
                if (apparent_div_done) begin
                    if (apparent_div_zero) begin
                        apparent_s_x100_reg <= 32'd0;
                    end else if ((apparent_div_quotient[95:32] != 64'd0) ||
                                 (apparent_div_quotient[31:0] > VALUE_CLIP_X100)) begin
                        apparent_s_x100_reg <= VALUE_CLIP_X100;
                    end else begin
                        apparent_s_x100_reg <= apparent_div_quotient[31:0];
                    end
                    apparent_done_latched <= 1'b1;
                end

                if (power_factor_div_done) begin
                    if (power_factor_div_zero) begin
                        power_factor_x100_reg <= 32'd0;
                        power_factor_neg_reg  <= 1'b0;
                    end else if (power_factor_div_quotient > PF_CLIP_X100[15:0]) begin
                        power_factor_x100_reg <= PF_CLIP_X100;
                        power_factor_neg_reg  <= cos_neg_calc;
                    end else begin
                        power_factor_x100_reg <= {16'd0, power_factor_div_quotient};
                        power_factor_neg_reg  <= cos_neg_calc && (power_factor_div_quotient != 16'd0);
                    end
                    power_factor_done_latched <= 1'b1;
                end

                if ((apparent_done_latched || apparent_div_done) &&
                    (power_factor_done_latched || power_factor_div_done)) begin
                    state <= ST_P_START;
                end
            end

            ST_P_START: begin
                active_p_div_start <= 1'b1;
                state              <= ST_P_WAIT;
            end

            ST_P_WAIT: begin
                if (active_p_div_done) begin
                    if (active_p_div_zero) begin
                        active_p_x100_reg <= 32'd0;
                        active_p_neg_reg  <= 1'b0;
                    end else if ((active_p_div_quotient[47:32] != 16'd0) ||
                                 (active_p_div_quotient[31:0] > VALUE_CLIP_X100)) begin
                        active_p_x100_reg <= VALUE_CLIP_X100;
                        active_p_neg_reg  <= cos_neg_calc;
                    end else begin
                        active_p_x100_reg <= active_p_div_quotient[31:0];
                        active_p_neg_reg  <= cos_neg_calc && (active_p_div_quotient[31:0] != 32'd0);
                    end
                    state            <= ST_Q_START;
                end
            end

            ST_Q_START: begin
                reactive_sqrt_start <= 1'b1;
                state               <= ST_Q_WAIT;
            end

            ST_Q_WAIT: begin
                if (reactive_sqrt_done) begin
                    if (reactive_sqrt_root > VALUE_CLIP_X100)
                        reactive_q_x100_reg <= VALUE_CLIP_X100;
                    else
                        reactive_q_x100_reg <= reactive_sqrt_root;

                    reactive_q_neg_reg <= work_phase_x100_signed[16] && (reactive_sqrt_root != 32'd0);
                    state              <= ST_COMMIT;
                end
            end

            ST_COMMIT: begin
                active_p_neg             <= active_p_neg_reg;
                active_p_tens            <= active_p_tens_wire;
                active_p_units           <= active_p_units_wire;
                active_p_decile          <= active_p_decile_wire;
                active_p_percentiles     <= active_p_percentiles_wire;
                reactive_q_neg           <= reactive_q_neg_reg;
                reactive_q_tens          <= reactive_q_tens_wire;
                reactive_q_units         <= reactive_q_units_wire;
                reactive_q_decile        <= reactive_q_decile_wire;
                reactive_q_percentiles   <= reactive_q_percentiles_wire;
                apparent_s_tens          <= apparent_s_tens_wire;
                apparent_s_units         <= apparent_s_units_wire;
                apparent_s_decile        <= apparent_s_decile_wire;
                apparent_s_percentiles   <= apparent_s_percentiles_wire;
                power_factor_neg         <= power_factor_neg_reg;
                power_factor_units       <= power_factor_units_wire;
                power_factor_decile      <= power_factor_decile_wire;
                power_factor_percentiles <= power_factor_percentiles_wire;
                power_metrics_valid      <= 1'b1;
                done                     <= 1'b1;
                state                    <= ST_IDLE;
            end

            default: begin
                state <= ST_IDLE;
            end
        endcase
    end
end

endmodule
