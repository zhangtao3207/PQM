`timescale 1ns / 1ps

/*
 * 模块: time_x100_normalizer
 * 功能:
 *   将时域测量链路输出的各类 raw 数据统一换算成 x100 工程量，按固定顺序完成 RMS、峰峰值、频率、相位和功率相关结果的归一化。
 *
 * 输入:
 *   clk: 模块工作时钟。
 *   rst_n: 低有效复位信号。
 *   start: 启动一次 raw->x100 归一化流程。
 *   u_rms_raw: 电压 RMS 原始码值。
 *   i_rms_raw: 电流 RMS 原始码值。
 *   rms_valid: RMS 原始数据有效标志。
 *   u_pp_raw: 电压峰峰值原始码值。
 *   i_pp_raw: 电流峰峰值原始码值。
 *   u_pp_valid: 电压峰峰值原始数据有效标志。
 *   i_pp_valid: 电流峰峰值原始数据有效标志。
 *   phase_offset_raw: 相位偏移原始计数。
 *   phase_period_raw: 相位周期原始计数。
 *   phase_valid: 相位原始数据有效标志。
 *   freq_period_raw: 频率周期原始计数。
 *   freq_valid: 频率原始数据有效标志。
 *   active_p_raw: 有功功率原始码值。
 *   reactive_q_raw: 无功功率原始码值。
 *   apparent_s_raw: 视在功率原始码值。
 *   power_factor_raw: 功率因数原始码值。
 *   u_full_scale_x100: 电压满量程 x100 参数。
 *   i_full_scale_x100: 电流满量程 x100 参数。
 *   power_metrics_valid: 功率相关原始数据有效标志。
 *
 * 输出:
 *   done: 本次 x100 归一化完成脉冲。
 *   u_rms_x100: 电压 RMS 的 x100 结果。
 *   i_rms_x100: 电流 RMS 的 x100 结果。
 *   u_pp_x100: 电压峰峰值的 x100 结果。
 *   i_pp_x100: 电流峰峰值的 x100 结果。
 *   phase_x100: 功率角的 x100 结果。
 *   freq_x100: 频率的 x100 结果。
 *   active_p_x100: 有功功率的 x100 结果。
 *   reactive_q_x100: 无功功率的 x100 结果。
 *   apparent_s_x100: 视在功率的 x100 结果。
 *   power_factor_x100: 功率因数的 x100 结果。
 */
module time_x100_normalizer #(
    parameter integer CODE_WIDTH        = 16,
    parameter [39:0]  CLK_FREQ_X100     = 40'd5000000000
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    start,
    input  wire signed [31:0]      u_rms_raw,
    input  wire signed [31:0]      i_rms_raw,
    input  wire                    rms_valid,
    input  wire signed [31:0]      u_pp_raw,
    input  wire signed [31:0]      i_pp_raw,
    input  wire                    u_pp_valid,
    input  wire                    i_pp_valid,
    input  wire signed [31:0]      phase_offset_raw,
    input  wire signed [31:0]      phase_period_raw,
    input  wire                    phase_valid,
    input  wire signed [31:0]      freq_period_raw,
    input  wire                    freq_valid,
    input  wire signed [31:0]      active_p_raw,
    input  wire signed [31:0]      reactive_q_raw,
    input  wire signed [31:0]      apparent_s_raw,
    input  wire signed [31:0]      power_factor_raw,
    input  wire [31:0]             u_full_scale_x100,
    input  wire [31:0]             i_full_scale_x100,
    input  wire                    power_metrics_valid,

    output reg                     done,
    output reg signed [31:0]       u_rms_x100,
    output reg signed [31:0]       i_rms_x100,
    output reg signed [31:0]       u_pp_x100,
    output reg signed [31:0]       i_pp_x100,
    output reg signed [31:0]       phase_x100,
    output reg signed [31:0]       freq_x100,
    output reg signed [31:0]       active_p_x100,
    output reg signed [31:0]       reactive_q_x100,
    output reg signed [31:0]       apparent_s_x100,
    output reg signed [31:0]       power_factor_x100
);

localparam [3:0] ST_IDLE             = 4'd0;
localparam [3:0] ST_RMS_X100_START   = 4'd1;
localparam [3:0] ST_RMS_X100_WAIT    = 4'd2;
localparam [3:0] ST_P2P_START        = 4'd3;
localparam [3:0] ST_P2P_WAIT         = 4'd4;
localparam [3:0] ST_FREQ_START       = 4'd5;
localparam [3:0] ST_FREQ_WAIT        = 4'd6;
localparam [3:0] ST_PHASE_START      = 4'd7;
localparam [3:0] ST_PHASE_DIV_WAIT   = 4'd8;
localparam [3:0] ST_PHASE_ROM_REQ    = 4'd9;
localparam [3:0] ST_PHASE_ROM_WAIT   = 4'd10;
localparam [3:0] ST_POWER_X100_START = 4'd11;
localparam [3:0] ST_POWER_X100_WAIT  = 4'd12;
localparam [3:0] ST_COMMIT           = 4'd13;
localparam [3:0] ST_POWER_PRODUCT_LATCH = 4'd14;
localparam [3:0] ST_POWER_DIV_START     = 4'd15;

localparam [31:0] HALF_SCALE_CODE    = 32'd1 << (CODE_WIDTH - 1);
localparam [31:0] ROUND_BIAS         = HALF_SCALE_CODE >> 1;
localparam [31:0] VALUE_CLIP_999     = 32'd99999;
localparam [31:0] VALUE_CLIP_180     = 32'd18000;
localparam [31:0] VALUE_CLIP_PF      = 32'd100;
localparam [15:0] DEG_180_X100       = 16'd18000;
localparam [15:0] DEG_360_X100       = 16'd36000;
localparam [95:0] RMS_SCALE_DEN      = 96'd107367628900;
localparam [95:0] RMS_SCALE_DEN_HALF = 96'd53683814450;
localparam [15:0] PF_SCALE_DEN       = 16'd100;
localparam [15:0] PF_SCALE_DEN_HALF  = 16'd50;

reg  [3:0]               state;

reg  signed [31:0]       work_u_rms_raw;
reg  signed [31:0]       work_i_rms_raw;
reg                      work_rms_valid;
reg  signed [31:0]       work_u_pp_raw;
reg  signed [31:0]       work_i_pp_raw;
reg                      work_u_pp_valid;
reg                      work_i_pp_valid;
reg  signed [31:0]       work_phase_offset_raw;
reg  signed [31:0]       work_phase_period_raw;
reg                      work_phase_valid;
reg  signed [31:0]       work_freq_period_raw;
reg                      work_freq_valid;

reg                      rms_start_pulse;
wire                     u_rms_conv_valid;
wire                     i_rms_conv_valid;
wire [31:0]              u_rms_conv_value;
wire [31:0]              i_rms_conv_value;

reg                      p2p_start_pulse;
wire signed [31:0]       u_full_scale_x100_signed;
wire signed [31:0]       i_full_scale_x100_signed;
wire [31:0]              u_pp_raw_abs;
wire [31:0]              i_pp_raw_abs;
wire signed [63:0]       u_pp_scale_product_signed;
wire signed [63:0]       i_pp_scale_product_signed;
wire [63:0]              u_pp_scale_product_unsigned;
wire [63:0]              i_pp_scale_product_unsigned;
wire                     u_pp_div_done;
wire                     u_pp_div_zero;
wire [63:0]              u_pp_div_quotient;
wire                     i_pp_div_done;
wire                     i_pp_div_zero;
wire [63:0]              i_pp_div_quotient;

reg                      freq_start_pulse;
wire                     freq_div_done;
wire                     freq_div_zero;
wire [63:0]              freq_div_quotient;

reg                      phase_start_pulse;
reg  [43:0]              phase_dividend;
reg  [43:0]              phase_divisor;
reg  [10:0]              phase_rom_addr;
reg                      phase_dot_negative;
reg                      phase_cross_negative;
reg                      phase_result_valid;
wire                     phase_div_done;
wire                     phase_div_zero;
wire [43:0]              phase_div_q;
wire [32:0]              phase_denominator;
wire [43:0]              phase_dividend_next;
wire [43:0]              phase_divisor_next;
wire [10:0]              phase_div_addr;
wire [13:0]              phase_rom_angle_deg_x100;
wire                     phase_input_valid;
wire signed [15:0]       phase_angle_0_90;
wire signed [15:0]       phase_angle_next;

reg  signed [31:0]       active_p_raw_work;
reg  signed [31:0]       reactive_q_raw_work;
reg  signed [31:0]       apparent_s_raw_work;
reg  signed [31:0]       power_factor_raw_work;
reg                      work_power_metrics_valid;
reg                      power_scale_start_pulse;
reg                      active_p_x100_done_seen;
reg                      reactive_q_x100_done_seen;
reg                      apparent_s_x100_done_seen;
reg                      power_factor_x100_done_seen;

wire [31:0]              active_p_raw_abs;
wire [31:0]              reactive_q_raw_abs;
wire [31:0]              apparent_s_raw_abs;
wire [31:0]              power_factor_raw_abs;
wire                     active_p_raw_neg;
wire                     reactive_q_raw_neg;
wire                     power_factor_raw_neg;

wire signed [63:0]       full_scale_prod_signed;
reg  signed [63:0]       full_scale_prod_work;
wire signed [95:0]       active_p_scale_product_signed;
wire signed [95:0]       reactive_q_scale_product_signed;
wire signed [95:0]       apparent_s_scale_product_signed;
reg  [95:0]              active_p_scale_product_work;
reg  [95:0]              reactive_q_scale_product_work;
reg  [95:0]              apparent_s_scale_product_work;
wire [95:0]              active_p_scale_product_unsigned;
wire [95:0]              reactive_q_scale_product_unsigned;
wire [95:0]              apparent_s_scale_product_unsigned;
wire                     active_p_x100_div_done;
wire                     active_p_x100_div_zero;
wire [95:0]              active_p_x100_div_quotient;
wire                     reactive_q_x100_div_done;
wire                     reactive_q_x100_div_zero;
wire [95:0]              reactive_q_x100_div_quotient;
wire                     apparent_s_x100_div_done;
wire                     apparent_s_x100_div_zero;
wire [95:0]              apparent_s_x100_div_quotient;
wire                     power_factor_x100_div_done;
wire                     power_factor_x100_div_zero;
wire [31:0]              power_factor_x100_div_quotient;

// 使用 signed_code_to_x100 将锁存的电压 RMS 原始码换算成 x100 工程值。
signed_code_to_x100 #(
    .WIDTH(CODE_WIDTH)
) u_u_rms_raw_to_x100 (
    .clk            (clk),
    .rst_n          (rst_n),
    .start          (rms_start_pulse),
    .code_in        (work_u_rms_raw[CODE_WIDTH-1:0]),
    .full_scale_x100(u_full_scale_x100),
    .busy           (),
    .value_valid    (u_rms_conv_valid),
    .value_x100     (u_rms_conv_value)
);

// 使用 signed_code_to_x100 将锁存的电流 RMS 原始码换算成 x100 工程值。
signed_code_to_x100 #(
    .WIDTH(CODE_WIDTH)
) u_i_rms_raw_to_x100 (
    .clk            (clk),
    .rst_n          (rst_n),
    .start          (rms_start_pulse),
    .code_in        (work_i_rms_raw[CODE_WIDTH-1:0]),
    .full_scale_x100(i_full_scale_x100),
    .busy           (),
    .value_valid    (i_rms_conv_valid),
    .value_x100     (i_rms_conv_value)
);

// 提取峰峰值 raw 的幅值，并准备后续满量程换算所需的组合量。
assign u_pp_raw_abs            = work_u_pp_raw[31] ? 32'd0 : work_u_pp_raw[31:0];
assign i_pp_raw_abs            = work_i_pp_raw[31] ? 32'd0 : work_i_pp_raw[31:0];
assign u_full_scale_x100_signed= u_full_scale_x100;
assign i_full_scale_x100_signed= i_full_scale_x100;

// 将电压峰峰值 raw 与电压满量程相乘，构造 x100 换算分子。
multiplier_signed #(
    .A_WIDTH(32),
    .B_WIDTH(32)
) u_u_pp_scale_multiplier (
    .multiplicand({1'b0, u_pp_raw_abs[30:0]}),
    .multiplier  (u_full_scale_x100_signed),
    .product     (u_pp_scale_product_signed)
);

// 将电流峰峰值 raw 与电流满量程相乘，构造 x100 换算分子。
multiplier_signed #(
    .A_WIDTH(32),
    .B_WIDTH(32)
) u_i_pp_scale_multiplier (
    .multiplicand({1'b0, i_pp_raw_abs[30:0]}),
    .multiplier  (i_full_scale_x100_signed),
    .product     (i_pp_scale_product_signed)
);

// 将峰峰值乘积整理成无符号除法器输入。
assign u_pp_scale_product_unsigned = u_pp_scale_product_signed[63] ? 64'd0 : u_pp_scale_product_signed[63:0];
assign i_pp_scale_product_unsigned = i_pp_scale_product_signed[63] ? 64'd0 : i_pp_scale_product_signed[63:0];

// 对电压峰峰值 raw 执行比例换算，得到电压峰峰值 x100。
divider_unsigned #(
    .WIDTH(64)
) u_u_pp_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (p2p_start_pulse),
    .dividend      (u_pp_scale_product_unsigned + {32'd0, ROUND_BIAS}),
    .divisor       ({32'd0, HALF_SCALE_CODE}),
    .busy          (),
    .done          (u_pp_div_done),
    .divide_by_zero(u_pp_div_zero),
    .quotient      (u_pp_div_quotient)
);

// 对电流峰峰值 raw 执行比例换算，得到电流峰峰值 x100。
divider_unsigned #(
    .WIDTH(64)
) u_i_pp_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (p2p_start_pulse),
    .dividend      (i_pp_scale_product_unsigned + {32'd0, ROUND_BIAS}),
    .divisor       ({32'd0, HALF_SCALE_CODE}),
    .busy          (),
    .done          (i_pp_div_done),
    .divide_by_zero(i_pp_div_zero),
    .quotient      (i_pp_div_quotient)
);

// 根据周期 raw 完成频率 x100 换算。
divider_unsigned #(
    .WIDTH(64)
) u_frequency_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (freq_start_pulse),
    .dividend      ({24'd0, CLK_FREQ_X100} + {32'd0, work_freq_period_raw[31:1]}),
    .divisor       ({32'd0, work_freq_period_raw[31:0]}),
    .busy          (),
    .done          (freq_div_done),
    .divide_by_zero(freq_div_zero),
    .quotient      (freq_div_quotient)
);

// 基于同窗 P/Q 结果构造 atan2 所需的比值和象限修正量。
assign phase_denominator  = {1'b0, active_p_raw_abs} + {1'b0, reactive_q_raw_abs};
assign phase_dividend_next = {2'b00, reactive_q_raw_abs, 10'd0};
assign phase_divisor_next  = {11'd0, phase_denominator};
assign phase_div_addr      = (phase_div_q[43:11] != 33'd0) ? 11'd1024 : phase_div_q[10:0];
assign phase_input_valid   = work_phase_valid && (phase_denominator != 33'd0);
assign phase_angle_0_90    = {2'b00, phase_rom_angle_deg_x100};
assign phase_angle_next =
    !phase_result_valid ? 16'sd0 :
    (!phase_dot_negative && !phase_cross_negative) ? phase_angle_0_90 :
    (!phase_dot_negative &&  phase_cross_negative) ? -phase_angle_0_90 :
    ( phase_dot_negative && !phase_cross_negative) ? (16'sd18000 - phase_angle_0_90) :
                                                     (-16'sd18000 + phase_angle_0_90);

// 先完成 atan 地址除法，再交给 ROM 查第一象限角度。
divider_unsigned #(
    .WIDTH(44)
) u_phase_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (phase_start_pulse),
    .dividend      (phase_dividend),
    .divisor       (phase_divisor),
    .busy          (),
    .done          (phase_div_done),
    .divide_by_zero(phase_div_zero),
    .quotient      (phase_div_q)
);

// 根据 atan 地址查表得到第一象限角度，再配合象限修正生成最终相位。
rom_atan_lut_1024 u_phase_power_angle_rom (
    .clka (clk),
    .ena  (state == ST_PHASE_ROM_REQ),
    .addra(phase_rom_addr),
    .douta(phase_rom_angle_deg_x100)
);

// 提取功率 raw 的幅值和符号位，供后续统一换算为 x100。
assign active_p_raw_abs     = active_p_raw_work[31] ? (~active_p_raw_work + 32'd1) : active_p_raw_work[31:0];
assign reactive_q_raw_abs   = reactive_q_raw_work[31] ? (~reactive_q_raw_work + 32'd1) : reactive_q_raw_work[31:0];
assign apparent_s_raw_abs   = apparent_s_raw_work[31] ? (~apparent_s_raw_work + 32'd1) : apparent_s_raw_work[31:0];
assign power_factor_raw_abs = power_factor_raw_work[31] ? (~power_factor_raw_work + 32'd1) : power_factor_raw_work[31:0];
assign active_p_raw_neg     = active_p_raw_work[31] && (active_p_raw_abs != 32'd0);
assign reactive_q_raw_neg   = reactive_q_raw_work[31] && (reactive_q_raw_abs != 32'd0);
assign power_factor_raw_neg = power_factor_raw_work[31] && (power_factor_raw_abs != 32'd0);

// 计算电压/电流满量程乘积，作为功率类 raw 统一缩放的公共系数。
multiplier_signed #(
    .A_WIDTH(32),
    .B_WIDTH(32)
) u_full_scale_multiplier (
    .multiplicand(u_full_scale_x100_signed),
    .multiplier  (i_full_scale_x100_signed),
    .product     (full_scale_prod_signed)
);

// 将有功功率 raw 与满量程乘积相乘，构造 x100 换算分子。
multiplier_signed #(
    .A_WIDTH(64),
    .B_WIDTH(32)
) u_active_p_scale_multiplier (
    .multiplicand(full_scale_prod_work),
    .multiplier  ({1'b0, active_p_raw_abs[30:0]}),
    .product     (active_p_scale_product_signed)
);

// 将无功功率 raw 与满量程乘积相乘，构造 x100 换算分子。
multiplier_signed #(
    .A_WIDTH(64),
    .B_WIDTH(32)
) u_reactive_q_scale_multiplier (
    .multiplicand(full_scale_prod_work),
    .multiplier  ({1'b0, reactive_q_raw_abs[30:0]}),
    .product     (reactive_q_scale_product_signed)
);

// 将视在功率 raw 与满量程乘积相乘，构造 x100 换算分子。
multiplier_signed #(
    .A_WIDTH(64),
    .B_WIDTH(32)
) u_apparent_s_scale_multiplier (
    .multiplicand(full_scale_prod_work),
    .multiplier  ({1'b0, apparent_s_raw_abs[30:0]}),
    .product     (apparent_s_scale_product_signed)
);

// 将功率缩放乘积整理成无符号除法器输入。
assign active_p_scale_product_unsigned   = active_p_scale_product_work;
assign reactive_q_scale_product_unsigned = reactive_q_scale_product_work;
assign apparent_s_scale_product_unsigned = apparent_s_scale_product_work;

// 对有功功率 raw 执行满量程比例换算，得到有功功率 x100。
divider_unsigned #(
    .WIDTH(96)
) u_active_p_x100_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (power_scale_start_pulse),
    .dividend      (active_p_scale_product_unsigned + RMS_SCALE_DEN_HALF),
    .divisor       (RMS_SCALE_DEN),
    .busy          (),
    .done          (active_p_x100_div_done),
    .divide_by_zero(active_p_x100_div_zero),
    .quotient      (active_p_x100_div_quotient)
);

// 对无功功率 raw 执行满量程比例换算，得到无功功率 x100。
divider_unsigned #(
    .WIDTH(96)
) u_reactive_q_x100_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (power_scale_start_pulse),
    .dividend      (reactive_q_scale_product_unsigned + RMS_SCALE_DEN_HALF),
    .divisor       (RMS_SCALE_DEN),
    .busy          (),
    .done          (reactive_q_x100_div_done),
    .divide_by_zero(reactive_q_x100_div_zero),
    .quotient      (reactive_q_x100_div_quotient)
);

// 对视在功率 raw 执行满量程比例换算，得到视在功率 x100。
divider_unsigned #(
    .WIDTH(96)
) u_apparent_s_x100_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (power_scale_start_pulse),
    .dividend      (apparent_s_scale_product_unsigned + RMS_SCALE_DEN_HALF),
    .divisor       (RMS_SCALE_DEN),
    .busy          (),
    .done          (apparent_s_x100_div_done),
    .divide_by_zero(apparent_s_x100_div_zero),
    .quotient      (apparent_s_x100_div_quotient)
);

// 对功率因数 raw 的 x10000 数据统一除以 100，得到功率因数 x100。
divider_unsigned #(
    .WIDTH(32)
) u_power_factor_x100_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (power_scale_start_pulse),
    .dividend      (power_factor_raw_abs + {16'd0, PF_SCALE_DEN_HALF}),
    .divisor       ({16'd0, PF_SCALE_DEN}),
    .busy          (),
    .done          (power_factor_x100_div_done),
    .divide_by_zero(power_factor_x100_div_zero),
    .quotient      (power_factor_x100_div_quotient)
);

// 按固定状态顺序完成 RMS、P2P、频率、相位和功率相关量的 raw->x100 换算。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state                  <= ST_IDLE;
        work_u_rms_raw         <= 32'sd0;
        work_i_rms_raw         <= 32'sd0;
        work_rms_valid         <= 1'b0;
        work_u_pp_raw          <= 32'sd0;
        work_i_pp_raw          <= 32'sd0;
        work_u_pp_valid        <= 1'b0;
        work_i_pp_valid        <= 1'b0;
        work_phase_offset_raw  <= 32'sd0;
        work_phase_period_raw  <= 32'sd0;
        work_phase_valid       <= 1'b0;
        work_freq_period_raw   <= 32'sd0;
        work_freq_valid        <= 1'b0;
        rms_start_pulse        <= 1'b0;
        p2p_start_pulse        <= 1'b0;
        freq_start_pulse       <= 1'b0;
        phase_start_pulse      <= 1'b0;
        power_scale_start_pulse<= 1'b0;
        active_p_x100_done_seen   <= 1'b0;
        reactive_q_x100_done_seen <= 1'b0;
        apparent_s_x100_done_seen <= 1'b0;
        power_factor_x100_done_seen <= 1'b0;
        phase_dividend         <= 44'd0;
        phase_divisor          <= 44'd1;
        phase_rom_addr         <= 11'd0;
        phase_dot_negative     <= 1'b0;
        phase_cross_negative   <= 1'b0;
        phase_result_valid     <= 1'b0;
        active_p_raw_work      <= 32'sd0;
        reactive_q_raw_work    <= 32'sd0;
        apparent_s_raw_work    <= 32'sd0;
        power_factor_raw_work  <= 32'sd0;
        work_power_metrics_valid <= 1'b0;
        full_scale_prod_work      <= 64'sd0;
        active_p_scale_product_work   <= 96'd0;
        reactive_q_scale_product_work <= 96'd0;
        apparent_s_scale_product_work <= 96'd0;
        done                   <= 1'b0;
        u_rms_x100             <= 32'sd0;
        i_rms_x100             <= 32'sd0;
        u_pp_x100              <= 32'sd0;
        i_pp_x100              <= 32'sd0;
        phase_x100             <= 32'sd0;
        freq_x100              <= 32'sd0;
        active_p_x100          <= 32'sd0;
        reactive_q_x100        <= 32'sd0;
        apparent_s_x100        <= 32'sd0;
        power_factor_x100      <= 32'sd0;
    end else begin
        done                    <= 1'b0;
        rms_start_pulse         <= 1'b0;
        p2p_start_pulse         <= 1'b0;
        freq_start_pulse        <= 1'b0;
        phase_start_pulse       <= 1'b0;
        power_scale_start_pulse <= 1'b0;

        if (active_p_x100_div_done)
            active_p_x100_done_seen <= 1'b1;
        if (reactive_q_x100_div_done)
            reactive_q_x100_done_seen <= 1'b1;
        if (apparent_s_x100_div_done)
            apparent_s_x100_done_seen <= 1'b1;
        if (power_factor_x100_div_done)
            power_factor_x100_done_seen <= 1'b1;

        case (state)
            ST_IDLE: begin
                if (start) begin
                    work_u_rms_raw        <= u_rms_raw;
                    work_i_rms_raw        <= i_rms_raw;
                    work_rms_valid        <= rms_valid;
                    work_u_pp_raw         <= u_pp_raw;
                    work_i_pp_raw         <= i_pp_raw;
                    work_u_pp_valid       <= u_pp_valid;
                    work_i_pp_valid       <= i_pp_valid;
                    work_phase_offset_raw <= phase_offset_raw;
                    work_phase_period_raw <= phase_period_raw;
                    work_phase_valid      <= phase_valid;
                    work_freq_period_raw  <= freq_period_raw;
                    work_freq_valid       <= freq_valid;
                    active_p_raw_work     <= active_p_raw;
                    reactive_q_raw_work   <= reactive_q_raw;
                    apparent_s_raw_work   <= apparent_s_raw;
                    power_factor_raw_work <= power_factor_raw;
                    work_power_metrics_valid <= power_metrics_valid;
                    active_p_x100         <= 32'sd0;
                    reactive_q_x100       <= 32'sd0;
                    apparent_s_x100       <= 32'sd0;
                    power_factor_x100     <= 32'sd0;
                    state                 <= ST_RMS_X100_START;
                end
            end

            ST_RMS_X100_START: begin
                if (work_rms_valid) begin
                    rms_start_pulse <= 1'b1;
                    state           <= ST_RMS_X100_WAIT;
                end else begin
                    u_rms_x100 <= 32'sd0;
                    i_rms_x100 <= 32'sd0;
                    state      <= ST_P2P_START;
                end
            end

            ST_RMS_X100_WAIT: begin
                if (u_rms_conv_valid && i_rms_conv_valid) begin
                    if (u_rms_conv_value > VALUE_CLIP_999)
                        u_rms_x100 <= {1'b0, VALUE_CLIP_999[30:0]};
                    else
                        u_rms_x100 <= {1'b0, u_rms_conv_value[30:0]};

                    if (i_rms_conv_value > VALUE_CLIP_999)
                        i_rms_x100 <= {1'b0, VALUE_CLIP_999[30:0]};
                    else
                        i_rms_x100 <= {1'b0, i_rms_conv_value[30:0]};

                    state <= ST_P2P_START;
                end
            end

            ST_P2P_START: begin
                p2p_start_pulse <= 1'b1;
                state           <= ST_P2P_WAIT;
            end

            ST_P2P_WAIT: begin
                if (u_pp_div_done && i_pp_div_done) begin
                    if (!work_u_pp_valid || u_pp_div_zero)
                        u_pp_x100 <= 32'sd0;
                    else if ((u_pp_div_quotient[63:32] != 32'd0) || (u_pp_div_quotient[31:0] > VALUE_CLIP_999))
                        u_pp_x100 <= {1'b0, VALUE_CLIP_999[30:0]};
                    else
                        u_pp_x100 <= {1'b0, u_pp_div_quotient[30:0]};

                    if (!work_i_pp_valid || i_pp_div_zero)
                        i_pp_x100 <= 32'sd0;
                    else if ((i_pp_div_quotient[63:32] != 32'd0) || (i_pp_div_quotient[31:0] > VALUE_CLIP_999))
                        i_pp_x100 <= {1'b0, VALUE_CLIP_999[30:0]};
                    else
                        i_pp_x100 <= {1'b0, i_pp_div_quotient[30:0]};

                    state <= ST_FREQ_START;
                end
            end

            ST_FREQ_START: begin
                if (work_freq_valid && !work_freq_period_raw[31] && (work_freq_period_raw != 32'sd0)) begin
                    freq_start_pulse <= 1'b1;
                    state            <= ST_FREQ_WAIT;
                end else begin
                    freq_x100 <= 32'sd0;
                    state     <= ST_PHASE_START;
                end
            end

            ST_FREQ_WAIT: begin
                if (freq_div_done) begin
                    if (freq_div_zero)
                        freq_x100 <= 32'sd0;
                    else if ((freq_div_quotient[63:32] != 32'd0) || (freq_div_quotient[31:0] > VALUE_CLIP_999))
                        freq_x100 <= {1'b0, VALUE_CLIP_999[30:0]};
                    else
                        freq_x100 <= {1'b0, freq_div_quotient[30:0]};

                    state <= ST_PHASE_START;
                end
            end

            ST_PHASE_START: begin
                if (phase_input_valid) begin
                    phase_dividend       <= phase_dividend_next;
                    phase_divisor        <= phase_divisor_next;
                    phase_rom_addr       <= 11'd0;
                    phase_dot_negative   <= active_p_raw_neg;
                    phase_cross_negative <= reactive_q_raw_neg;
                    phase_result_valid   <= 1'b1;
                    phase_start_pulse    <= 1'b1;
                    state                <= ST_PHASE_DIV_WAIT;
                end else begin
                    phase_result_valid <= 1'b0;
                    phase_x100        <= 32'sd0;
                    if (work_power_metrics_valid)
                        state <= ST_POWER_X100_START;
                    else
                        state <= ST_COMMIT;
                end
            end

            ST_PHASE_DIV_WAIT: begin
                if (phase_div_done) begin
                    if (phase_div_zero) begin
                        phase_result_valid <= 1'b0;
                        phase_x100         <= 32'sd0;
                        if (work_power_metrics_valid)
                            state <= ST_POWER_X100_START;
                        else
                            state <= ST_COMMIT;
                    end else begin
                        phase_rom_addr <= phase_div_addr;
                        state          <= ST_PHASE_ROM_REQ;
                    end
                end
            end

            ST_PHASE_ROM_REQ: begin
                state <= ST_PHASE_ROM_WAIT;
            end

            ST_PHASE_ROM_WAIT: begin
                if (phase_result_valid)
                    phase_x100 <= {{16{phase_angle_next[15]}}, phase_angle_next};
                else
                    phase_x100 <= 32'sd0;

                if (work_power_metrics_valid)
                    state <= ST_POWER_X100_START;
                else
                    state <= ST_COMMIT;
            end

            ST_POWER_X100_START: begin
                if (work_power_metrics_valid) begin
                    active_p_x100_done_seen   <= 1'b0;
                    reactive_q_x100_done_seen <= 1'b0;
                    apparent_s_x100_done_seen <= 1'b0;
                    power_factor_x100_done_seen <= 1'b0;
                    full_scale_prod_work <= full_scale_prod_signed;
                    state <= ST_POWER_PRODUCT_LATCH;
                end else begin
                    active_p_x100     <= 32'sd0;
                    reactive_q_x100   <= 32'sd0;
                    apparent_s_x100   <= 32'sd0;
                    power_factor_x100 <= 32'sd0;
                    state             <= ST_COMMIT;
                end
            end

            // 第二级只计算 raw 与满量程乘积，并将结果锁存后再送入除法器。
            ST_POWER_PRODUCT_LATCH: begin
                active_p_scale_product_work <=
                    active_p_scale_product_signed[95]
                        ? 96'd0 : active_p_scale_product_signed;
                reactive_q_scale_product_work <=
                    reactive_q_scale_product_signed[95]
                        ? 96'd0 : reactive_q_scale_product_signed;
                apparent_s_scale_product_work <=
                    apparent_s_scale_product_signed[95]
                        ? 96'd0 : apparent_s_scale_product_signed;
                state <= ST_POWER_DIV_START;
            end

            // 第三级启动现有串行除法器，避免乘法级联与 96 位加法落在同一周期。
            ST_POWER_DIV_START: begin
                power_scale_start_pulse <= 1'b1;
                state <= ST_POWER_X100_WAIT;
            end

            ST_POWER_X100_WAIT: begin
                if ((active_p_x100_done_seen || active_p_x100_div_done) &&
                    (reactive_q_x100_done_seen || reactive_q_x100_div_done) &&
                    (apparent_s_x100_done_seen || apparent_s_x100_div_done) &&
                    (power_factor_x100_done_seen || power_factor_x100_div_done)) begin

                    if (apparent_s_x100_div_zero)
                        apparent_s_x100 <= 32'sd0;
                    else if ((apparent_s_x100_div_quotient[95:32] != 64'd0) ||
                             (apparent_s_x100_div_quotient[31:0] > VALUE_CLIP_999))
                        apparent_s_x100 <= {1'b0, VALUE_CLIP_999[30:0]};
                    else
                        apparent_s_x100 <= {1'b0, apparent_s_x100_div_quotient[30:0]};

                    if (active_p_x100_div_zero)
                        active_p_x100 <= 32'sd0;
                    else if ((active_p_x100_div_quotient[95:32] != 64'd0) ||
                             (active_p_x100_div_quotient[31:0] > VALUE_CLIP_999))
                        active_p_x100 <= active_p_raw_neg ? (~VALUE_CLIP_999 + 32'd1) : {1'b0, VALUE_CLIP_999[30:0]};
                    else if (active_p_raw_neg && (active_p_x100_div_quotient[31:0] != 32'd0))
                        active_p_x100 <= ~active_p_x100_div_quotient[31:0] + 32'd1;
                    else
                        active_p_x100 <= {1'b0, active_p_x100_div_quotient[30:0]};

                    if (reactive_q_x100_div_zero)
                        reactive_q_x100 <= 32'sd0;
                    else if ((reactive_q_x100_div_quotient[95:32] != 64'd0) ||
                             (reactive_q_x100_div_quotient[31:0] > VALUE_CLIP_999))
                        reactive_q_x100 <= reactive_q_raw_neg ? (~VALUE_CLIP_999 + 32'd1) : {1'b0, VALUE_CLIP_999[30:0]};
                    else if (reactive_q_raw_neg && (reactive_q_x100_div_quotient[31:0] != 32'd0))
                        reactive_q_x100 <= ~reactive_q_x100_div_quotient[31:0] + 32'd1;
                    else
                        reactive_q_x100 <= {1'b0, reactive_q_x100_div_quotient[30:0]};

                    if (power_factor_x100_div_zero)
                        power_factor_x100 <= 32'sd0;
                    else if (power_factor_x100_div_quotient > VALUE_CLIP_PF)
                        power_factor_x100 <= power_factor_raw_neg ? (~VALUE_CLIP_PF + 32'd1) : {1'b0, VALUE_CLIP_PF[30:0]};
                    else if (power_factor_raw_neg && (power_factor_x100_div_quotient != 32'd0))
                        power_factor_x100 <= ~power_factor_x100_div_quotient + 32'd1;
                    else
                        power_factor_x100 <= {1'b0, power_factor_x100_div_quotient[30:0]};

                    state <= ST_COMMIT;
                end
            end

            ST_COMMIT: begin
                done  <= 1'b1;
                state <= ST_IDLE;
            end

            default: begin
                state <= ST_IDLE;
            end
        endcase
    end
end

endmodule
