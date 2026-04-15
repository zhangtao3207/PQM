`timescale 1ns / 1ps

/*
 * 模块: text_display_preprocess
 * 功能:
 *   在 LCD 帧完成事件后调度 RMS、峰峰值、相位、频率、标幺换算和数字拆分流程，
 *   将电压、电流、相位、频率和功率相关结果统一提交给文本显示链路。
 * 输入:
 *   clk: 本模块工作时钟。
 *   rst_n: 低有效异步复位信号。
 *   lcd_frame_done_toggle: LCD 帧绘制完成的 toggle 事件信号。
 *   lcd_swap_ack_toggle: LCD 结果切换应答 toggle，同步保留给显示握手链路使用。
 *   u_sample_valid: 电压通道采样码在当前周期有效。
 *   u_sample_code: 电压通道 ADC 采样码。
 *   u_zero_code: 电压通道零点/中心码。
 *   u_zero_valid: 电压通道零点码有效标志。
 *   i_sample_valid: 电流通道采样码在当前周期有效。
 *   i_sample_code: 电流通道 ADC 采样码。
 *   i_zero_code: 电流通道零点/中心码。
 *   i_zero_valid: 电流通道零点码有效标志。
 * 输出:
 *   text_result_commit_toggle: 一批文本结果完成提交时翻转一次。
 *   u_rms_tens: 电压 RMS 十位数字。
 *   u_rms_units: 电压 RMS 个位数字。
 *   u_rms_decile: 电压 RMS 十分位数字。
 *   u_rms_percentiles: 电压 RMS 百分位数字。
 *   u_rms_digits_valid: 电压 RMS 显示数字有效标志。
 *   i_rms_tens: 电流 RMS 十位数字。
 *   i_rms_units: 电流 RMS 个位数字。
 *   i_rms_decile: 电流 RMS 十分位数字。
 *   i_rms_percentiles: 电流 RMS 百分位数字。
 *   i_rms_digits_valid: 电流 RMS 显示数字有效标志。
 *   phase_hundreds: 相位百位数字。
 *   phase_tens: 相位十位数字。
 *   phase_units: 相位个位数字。
 *   phase_decile: 相位十分位数字。
 *   phase_percentiles: 相位百分位数字。
 *   phase_x100_signed: 相位 x100 定点有符号值。
 *   phase_neg: 相位显示符号，1 表示负值。
 *   phase_valid: 相位显示结果有效标志。
 *   freq_hundreds: 频率百位数字。
 *   freq_tens: 频率十位数字。
 *   freq_units: 频率个位数字。
 *   freq_decile: 频率十分位数字。
 *   freq_percentiles: 频率百分位数字。
 *   freq_valid: 频率显示结果有效标志。
 *   u_pp_tens: 电压峰峰值十位数字。
 *   u_pp_units: 电压峰峰值个位数字。
 *   u_pp_decile: 电压峰峰值十分位数字。
 *   u_pp_percentiles: 电压峰峰值百分位数字。
 *   u_pp_digits_valid: 电压峰峰值显示数字有效标志。
 *   i_pp_tens: 电流峰峰值十位数字。
 *   i_pp_units: 电流峰峰值个位数字。
 *   i_pp_decile: 电流峰峰值十分位数字。
 *   i_pp_percentiles: 电流峰峰值百分位数字。
 *   i_pp_digits_valid: 电流峰峰值显示数字有效标志。
 *   active_p_neg: 有功功率显示符号，1 表示负值。
 *   active_p_tens: 有功功率十位数字。
 *   active_p_units: 有功功率个位数字。
 *   active_p_decile: 有功功率十分位数字。
 *   active_p_percentiles: 有功功率百分位数字。
 *   reactive_q_neg: 无功功率显示符号，1 表示负值。
 *   reactive_q_tens: 无功功率十位数字。
 *   reactive_q_units: 无功功率个位数字。
 *   reactive_q_decile: 无功功率十分位数字。
 *   reactive_q_percentiles: 无功功率百分位数字。
 *   apparent_s_tens: 视在功率十位数字。
 *   apparent_s_units: 视在功率个位数字。
 *   apparent_s_decile: 视在功率十分位数字。
 *   apparent_s_percentiles: 视在功率百分位数字。
 *   power_factor_neg: 功率因数显示符号，1 表示负值。
 *   power_factor_units: 功率因数个位数字。
 *   power_factor_decile: 功率因数十分位数字。
 *   power_factor_percentiles: 功率因数百分位数字。
 *   power_metrics_valid: 功率相关显示结果有效标志。
 */
module text_display_preprocess #(
    parameter integer SAMPLE_WIDTH          = 16,
    parameter integer RMS_MAX_FRAME_SAMPLES = 8192,
    parameter integer RMS_N_WIDTH           = (RMS_MAX_FRAME_SAMPLES <= 2) ? 2 : $clog2(RMS_MAX_FRAME_SAMPLES),
    parameter integer RMS_FRAME_SAMPLES     = 6144,
    parameter integer U_FULL_SCALE_X100     = 1000,
    parameter integer I_FULL_SCALE_X100     = 300,
    parameter integer START_DELAY_CYCLES    = 1_000_000
)(
    input                          clk,
    input                          rst_n,
    input                          lcd_frame_done_toggle,
    input                          lcd_swap_ack_toggle,
    input                          u_sample_valid,
    input      [SAMPLE_WIDTH-1:0]  u_sample_code,
    input      [SAMPLE_WIDTH-1:0]  u_zero_code,
    input                          u_zero_valid,
    input                          i_sample_valid,
    input      [SAMPLE_WIDTH-1:0]  i_sample_code,
    input      [SAMPLE_WIDTH-1:0]  i_zero_code,
    input                          i_zero_valid,
    output reg                     text_result_commit_toggle,
    output reg [7:0]               u_rms_tens,
    output reg [7:0]               u_rms_units,
    output reg [7:0]               u_rms_decile,
    output reg [7:0]               u_rms_percentiles,
    output reg                     u_rms_digits_valid,
    output reg [7:0]               i_rms_tens,
    output reg [7:0]               i_rms_units,
    output reg [7:0]               i_rms_decile,
    output reg [7:0]               i_rms_percentiles,
    output reg                     i_rms_digits_valid,
    output reg [7:0]               phase_hundreds,
    output reg [7:0]               phase_tens,
    output reg [7:0]               phase_units,
    output reg [7:0]               phase_decile,
    output reg [7:0]               phase_percentiles,
    output reg signed [16:0]       phase_x100_signed,
    output reg                     phase_neg,
    output reg                     phase_valid,
    output reg [7:0]               freq_hundreds,
    output reg [7:0]               freq_tens,
    output reg [7:0]               freq_units,
    output reg [7:0]               freq_decile,
    output reg [7:0]               freq_percentiles,
    output reg                     freq_valid,
    output reg [7:0]               u_pp_tens,
    output reg [7:0]               u_pp_units,
    output reg [7:0]               u_pp_decile,
    output reg [7:0]               u_pp_percentiles,
    output reg                     u_pp_digits_valid,
    output reg [7:0]               i_pp_tens,
    output reg [7:0]               i_pp_units,
    output reg [7:0]               i_pp_decile,
    output reg [7:0]               i_pp_percentiles,
    output reg                     i_pp_digits_valid,
    output reg                     active_p_neg,
    output reg [7:0]               active_p_tens,
    output reg [7:0]               active_p_units,
    output reg [7:0]               active_p_decile,
    output reg [7:0]               active_p_percentiles,
    output reg                     reactive_q_neg,
    output reg [7:0]               reactive_q_tens,
    output reg [7:0]               reactive_q_units,
    output reg [7:0]               reactive_q_decile,
    output reg [7:0]               reactive_q_percentiles,
    output reg [7:0]               apparent_s_tens,
    output reg [7:0]               apparent_s_units,
    output reg [7:0]               apparent_s_decile,
    output reg [7:0]               apparent_s_percentiles,
    output reg                     power_factor_neg,
    output reg [7:0]               power_factor_units,
    output reg [7:0]               power_factor_decile,
    output reg [7:0]               power_factor_percentiles,
    output reg                     power_metrics_valid
);

// 调度状态机：等待帧事件、延时、启动基础测量、归一化换算、数字拆分并统一提交。
localparam [3:0] ST_WAIT_FRAME   = 4'd0;
localparam [3:0] ST_WAIT_DELAY   = 4'd1;
localparam [3:0] ST_START_BASIC  = 4'd2;
localparam [3:0] ST_WAIT_BASIC   = 4'd3;
localparam [3:0] ST_START_X100   = 4'd4;
localparam [3:0] ST_WAIT_X100    = 4'd5;
localparam [3:0] ST_START_FORMAT = 4'd6;
localparam [3:0] ST_WAIT_FORMAT  = 4'd7;
localparam [3:0] ST_COMMIT       = 4'd8;

// 主状态、帧同步寄存器、各计算模块启动脉冲和结果完成锁存标志。
reg  [3:0]                    state;
reg  [31:0]                   start_delay_cnt;
reg                           frame_toggle_sync1;
reg                           frame_toggle_sync2;
reg                           frame_toggle_sync3;
reg                           swap_ack_sync1;
reg                           swap_ack_sync2;
reg                           swap_ack_sync3;
reg                           parameters_start;
reg                           x100_start;
reg                           separator_start;
reg                           rms_valid_latched;
reg                           u_pp_valid_latched;
reg                           i_pp_valid_latched;
reg                           phase_valid_latched;
reg                           freq_valid_latched;
reg                           power_metrics_valid_latched;
reg signed [31:0]             u_rms_raw_pending;
reg signed [31:0]             i_rms_raw_pending;
reg signed [31:0]             u_pp_raw_pending;
reg signed [31:0]             i_pp_raw_pending;
reg signed [31:0]             phase_offset_raw_pending;
reg signed [31:0]             phase_period_raw_pending;
reg signed [31:0]             freq_period_raw_pending;
reg signed [31:0]             active_p_raw_pending;
reg signed [31:0]             reactive_q_raw_pending;
reg signed [31:0]             apparent_s_raw_pending;
reg signed [31:0]             power_factor_raw_pending;

// 输入预处理、各计算模块原始输出、x100 换算结果和数字拆分结果连线。
wire                          frame_edge_wave;
wire                          parameters_done;
wire signed [31:0]            u_rms_raw_wire;
wire signed [31:0]            i_rms_raw_wire;
wire                          rms_valid_wire;
wire signed [31:0]            u_pp_raw_wire;
wire                          u_pp_valid_wire;
wire signed [31:0]            i_pp_raw_wire;
wire                          i_pp_valid_wire;
wire signed [31:0]            phase_offset_raw_wire;
wire signed [31:0]            phase_period_raw_wire;
wire                          phase_valid_wire;
wire signed [31:0]            freq_period_raw_wire;
wire                          freq_valid_wire;
wire signed [31:0]            active_p_raw_wire;
wire signed [31:0]            reactive_q_raw_wire;
wire signed [31:0]            apparent_s_raw_wire;
wire signed [31:0]            power_factor_raw_wire;
wire                          power_metrics_valid_wire;
wire                          x100_done;
wire signed [31:0]            u_rms_x100_wire;
wire signed [31:0]            i_rms_x100_wire;
wire signed [31:0]            u_pp_x100_wire;
wire signed [31:0]            i_pp_x100_wire;
wire signed [31:0]            phase_x100_wire;
wire signed [31:0]            freq_x100_wire;
wire signed [31:0]            active_p_x100_wire;
wire signed [31:0]            reactive_q_x100_wire;
wire signed [31:0]            apparent_s_x100_wire;
wire signed [31:0]            power_factor_x100_wire;
wire                          separator_done;
wire [7:0]                    u_rms_hundreds_sep, u_rms_tens_sep, u_rms_units_sep, u_rms_decile_sep, u_rms_percentiles_sep;
wire                          u_rms_digits_valid_sep;
wire [7:0]                    i_rms_hundreds_sep, i_rms_tens_sep, i_rms_units_sep, i_rms_decile_sep, i_rms_percentiles_sep;
wire                          i_rms_digits_valid_sep;
wire                          phase_neg_sep, phase_digits_valid_sep;
wire [7:0]                    phase_hundreds_sep, phase_tens_sep, phase_units_sep, phase_decile_sep, phase_percentiles_sep;
wire [7:0]                    freq_hundreds_sep, freq_tens_sep, freq_units_sep, freq_decile_sep, freq_percentiles_sep;
wire                          freq_digits_valid_sep;
wire [7:0]                    u_pp_hundreds_sep, u_pp_tens_sep, u_pp_units_sep, u_pp_decile_sep, u_pp_percentiles_sep;
wire                          u_pp_digits_valid_sep;
wire [7:0]                    i_pp_hundreds_sep, i_pp_tens_sep, i_pp_units_sep, i_pp_decile_sep, i_pp_percentiles_sep;
wire                          i_pp_digits_valid_sep;
wire                          active_p_neg_sep, reactive_q_neg_sep, power_factor_neg_sep, power_metrics_digits_valid_sep;
wire [7:0]                    active_p_hundreds_sep, active_p_tens_sep, active_p_units_sep, active_p_decile_sep, active_p_percentiles_sep;
wire [7:0]                    reactive_q_hundreds_sep, reactive_q_tens_sep, reactive_q_units_sep, reactive_q_decile_sep, reactive_q_percentiles_sep;
wire [7:0]                    apparent_s_hundreds_sep, apparent_s_tens_sep, apparent_s_units_sep, apparent_s_decile_sep, apparent_s_percentiles_sep;
wire [7:0]                    power_factor_hundreds_sep, power_factor_tens_sep, power_factor_units_sep, power_factor_decile_sep, power_factor_percentiles_sep;
wire                          base_packet_valid;
wire                          power_packet_valid;

// 对 LCD 帧完成 toggle 做边沿检测，作为下一轮文字刷新调度的触发事件。
assign frame_edge_wave         = frame_toggle_sync2 ^ frame_toggle_sync3;
// 判定基础结果包和功率结果包是否具备提交或格式化条件。
assign base_packet_valid       = rms_valid_latched && u_pp_valid_latched && i_pp_valid_latched;
assign power_packet_valid      = power_metrics_valid_latched;

// 原始测量调度器统一启动 RawDataCal 模块，并返回同一批次的 raw/valid 结果。
parameters_initiator #(
    .SAMPLE_WIDTH(SAMPLE_WIDTH),
    .MAX_FRAME_SAMPLES(RMS_MAX_FRAME_SAMPLES),
    .N_WIDTH(RMS_N_WIDTH),
    .MEASURE_FRAME_SAMPLES(RMS_FRAME_SAMPLES)
) u_parameters_initiator (
    .clk             (clk),
    .rst_n           (rst_n),
    .start           (parameters_start),
    .u_sample_valid  (u_sample_valid),
    .u_sample_code   (u_sample_code),
    .u_zero_code     (u_zero_code),
    .u_zero_valid    (u_zero_valid),
    .i_sample_valid  (i_sample_valid),
    .i_sample_code   (i_sample_code),
    .i_zero_code     (i_zero_code),
    .i_zero_valid    (i_zero_valid),
    .busy            (),
    .done            (parameters_done),
    .u_rms_raw       (u_rms_raw_wire),
    .i_rms_raw       (i_rms_raw_wire),
    .rms_valid       (rms_valid_wire),
    .u_pp_raw        (u_pp_raw_wire),
    .u_pp_valid      (u_pp_valid_wire),
    .i_pp_raw        (i_pp_raw_wire),
    .i_pp_valid      (i_pp_valid_wire),
    .phase_offset_raw(phase_offset_raw_wire),
    .phase_period_raw(phase_period_raw_wire),
    .phase_valid     (phase_valid_wire),
    .freq_period_raw (freq_period_raw_wire),
    .freq_valid      (freq_valid_wire),
    .active_p_raw    (active_p_raw_wire),
    .reactive_q_raw  (reactive_q_raw_wire),
    .apparent_s_raw  (apparent_s_raw_wire),
    .power_factor_raw(power_factor_raw_wire),
    .power_metrics_valid(power_metrics_valid_wire)
);

// 将 RMS、峰峰值、相位、频率和功率相关原始量换算为 x100 定点显示值。
x100_normalizer #(
    .CODE_WIDTH(SAMPLE_WIDTH), .U_FULL_SCALE_X100(U_FULL_SCALE_X100), .I_FULL_SCALE_X100(I_FULL_SCALE_X100)
) u_x100_normalizer (
    .clk(clk), .rst_n(rst_n), .start(x100_start),
    .u_rms_raw(u_rms_raw_pending), .i_rms_raw(i_rms_raw_pending), .rms_valid(rms_valid_latched),
    .u_pp_raw(u_pp_raw_pending), .i_pp_raw(i_pp_raw_pending), .u_pp_valid(u_pp_valid_latched), .i_pp_valid(i_pp_valid_latched),
    .phase_offset_raw(phase_offset_raw_pending), .phase_period_raw(phase_period_raw_pending), .phase_valid(phase_valid_latched),
    .freq_period_raw(freq_period_raw_pending), .freq_valid(freq_valid_latched),
    .active_p_raw(active_p_raw_pending), .reactive_q_raw(reactive_q_raw_pending),
    .apparent_s_raw(apparent_s_raw_pending), .power_factor_raw(power_factor_raw_pending),
    .power_metrics_valid(power_metrics_valid_latched), .done(x100_done),
    .u_rms_x100(u_rms_x100_wire), .i_rms_x100(i_rms_x100_wire), .u_pp_x100(u_pp_x100_wire), .i_pp_x100(i_pp_x100_wire),
    .phase_x100(phase_x100_wire), .freq_x100(freq_x100_wire), .active_p_x100(active_p_x100_wire),
    .reactive_q_x100(reactive_q_x100_wire), .apparent_s_x100(apparent_s_x100_wire), .power_factor_x100(power_factor_x100_wire)
);

// 将 x100 定点值拆分成文本显示需要的符号位和十进制数字位。
data_separator u_data_separator (
    .clk(clk), .rst_n(rst_n), .start(separator_start),
    .u_rms_x100(u_rms_x100_wire), .i_rms_x100(i_rms_x100_wire), .rms_valid(rms_valid_latched),
    .u_pp_x100(u_pp_x100_wire), .i_pp_x100(i_pp_x100_wire), .u_pp_valid(u_pp_valid_latched), .i_pp_valid(i_pp_valid_latched),
    .phase_x100_signed(phase_x100_wire), .phase_valid(phase_valid_latched),
    .freq_x100(freq_x100_wire), .freq_valid(freq_valid_latched),
    .active_p_x100(active_p_x100_wire), .reactive_q_x100(reactive_q_x100_wire),
    .apparent_s_x100(apparent_s_x100_wire), .power_factor_x100(power_factor_x100_wire),
    .power_metrics_valid(power_packet_valid), .done(separator_done),
    .u_rms_hundreds(u_rms_hundreds_sep), .u_rms_tens(u_rms_tens_sep), .u_rms_units(u_rms_units_sep),
    .u_rms_decile(u_rms_decile_sep), .u_rms_percentiles(u_rms_percentiles_sep), .u_rms_digits_valid(u_rms_digits_valid_sep),
    .i_rms_hundreds(i_rms_hundreds_sep), .i_rms_tens(i_rms_tens_sep), .i_rms_units(i_rms_units_sep),
    .i_rms_decile(i_rms_decile_sep), .i_rms_percentiles(i_rms_percentiles_sep), .i_rms_digits_valid(i_rms_digits_valid_sep),
    .phase_neg(phase_neg_sep), .phase_hundreds(phase_hundreds_sep), .phase_tens(phase_tens_sep), .phase_units(phase_units_sep),
    .phase_decile(phase_decile_sep), .phase_percentiles(phase_percentiles_sep), .phase_digits_valid(phase_digits_valid_sep),
    .freq_hundreds(freq_hundreds_sep), .freq_tens(freq_tens_sep), .freq_units(freq_units_sep),
    .freq_decile(freq_decile_sep), .freq_percentiles(freq_percentiles_sep), .freq_digits_valid(freq_digits_valid_sep),
    .u_pp_hundreds(u_pp_hundreds_sep), .u_pp_tens(u_pp_tens_sep), .u_pp_units(u_pp_units_sep),
    .u_pp_decile(u_pp_decile_sep), .u_pp_percentiles(u_pp_percentiles_sep), .u_pp_digits_valid(u_pp_digits_valid_sep),
    .i_pp_hundreds(i_pp_hundreds_sep), .i_pp_tens(i_pp_tens_sep), .i_pp_units(i_pp_units_sep),
    .i_pp_decile(i_pp_decile_sep), .i_pp_percentiles(i_pp_percentiles_sep), .i_pp_digits_valid(i_pp_digits_valid_sep),
    .active_p_neg(active_p_neg_sep), .active_p_hundreds(active_p_hundreds_sep), .active_p_tens(active_p_tens_sep),
    .active_p_units(active_p_units_sep), .active_p_decile(active_p_decile_sep), .active_p_percentiles(active_p_percentiles_sep),
    .reactive_q_neg(reactive_q_neg_sep), .reactive_q_hundreds(reactive_q_hundreds_sep), .reactive_q_tens(reactive_q_tens_sep),
    .reactive_q_units(reactive_q_units_sep), .reactive_q_decile(reactive_q_decile_sep), .reactive_q_percentiles(reactive_q_percentiles_sep),
    .apparent_s_hundreds(apparent_s_hundreds_sep), .apparent_s_tens(apparent_s_tens_sep), .apparent_s_units(apparent_s_units_sep),
    .apparent_s_decile(apparent_s_decile_sep), .apparent_s_percentiles(apparent_s_percentiles_sep),
    .power_factor_neg(power_factor_neg_sep), .power_factor_hundreds(power_factor_hundreds_sep), .power_factor_tens(power_factor_tens_sep),
    .power_factor_units(power_factor_units_sep), .power_factor_decile(power_factor_decile_sep), .power_factor_percentiles(power_factor_percentiles_sep),
    .power_metrics_digits_valid(power_metrics_digits_valid_sep)
);

// 在 clk 域调度整条文本预处理流水线，并在结果齐备后一次性刷新输出寄存器。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 复位调度状态、跨域同步链、启动脉冲、结果锁存和显示输出。
        state                     <= ST_WAIT_FRAME;
        start_delay_cnt           <= 32'd0;
        frame_toggle_sync1        <= 1'b0;
        frame_toggle_sync2        <= 1'b0;
        frame_toggle_sync3        <= 1'b0;
        swap_ack_sync1            <= 1'b0;
        swap_ack_sync2            <= 1'b0;
        swap_ack_sync3            <= 1'b0;
        parameters_start          <= 1'b0;
        x100_start                <= 1'b0;
        separator_start           <= 1'b0;
        rms_valid_latched         <= 1'b0;
        u_pp_valid_latched        <= 1'b0;
        i_pp_valid_latched        <= 1'b0;
        phase_valid_latched       <= 1'b0;
        freq_valid_latched        <= 1'b0;
        power_metrics_valid_latched <= 1'b0;
        u_rms_raw_pending         <= 32'sd0;
        i_rms_raw_pending         <= 32'sd0;
        u_pp_raw_pending          <= 32'sd0;
        i_pp_raw_pending          <= 32'sd0;
        phase_offset_raw_pending  <= 32'sd0;
        phase_period_raw_pending  <= 32'sd0;
        freq_period_raw_pending   <= 32'sd0;
        active_p_raw_pending      <= 32'sd0;
        reactive_q_raw_pending    <= 32'sd0;
        apparent_s_raw_pending    <= 32'sd0;
        power_factor_raw_pending  <= 32'sd0;
        text_result_commit_toggle <= 1'b0;
        u_rms_tens                <= 8'd0;
        u_rms_units               <= 8'd0;
        u_rms_decile              <= 8'd0;
        u_rms_percentiles         <= 8'd0;
        u_rms_digits_valid        <= 1'b0;
        i_rms_tens                <= 8'd0;
        i_rms_units               <= 8'd0;
        i_rms_decile              <= 8'd0;
        i_rms_percentiles         <= 8'd0;
        i_rms_digits_valid        <= 1'b0;
        phase_hundreds            <= 8'd0;
        phase_tens                <= 8'd0;
        phase_units               <= 8'd0;
        phase_decile              <= 8'd0;
        phase_percentiles         <= 8'd0;
        phase_x100_signed         <= 17'sd0;
        phase_neg                 <= 1'b0;
        phase_valid               <= 1'b0;
        freq_hundreds             <= 8'd0;
        freq_tens                 <= 8'd0;
        freq_units                <= 8'd0;
        freq_decile               <= 8'd0;
        freq_percentiles          <= 8'd0;
        freq_valid                <= 1'b0;
        u_pp_tens                 <= 8'd0;
        u_pp_units                <= 8'd0;
        u_pp_decile               <= 8'd0;
        u_pp_percentiles          <= 8'd0;
        u_pp_digits_valid         <= 1'b0;
        i_pp_tens                 <= 8'd0;
        i_pp_units                <= 8'd0;
        i_pp_decile               <= 8'd0;
        i_pp_percentiles          <= 8'd0;
        i_pp_digits_valid         <= 1'b0;
        active_p_neg              <= 1'b0;
        active_p_tens             <= 8'd0;
        active_p_units            <= 8'd0;
        active_p_decile           <= 8'd0;
        active_p_percentiles      <= 8'd0;
        reactive_q_neg            <= 1'b0;
        reactive_q_tens           <= 8'd0;
        reactive_q_units          <= 8'd0;
        reactive_q_decile         <= 8'd0;
        reactive_q_percentiles    <= 8'd0;
        apparent_s_tens           <= 8'd0;
        apparent_s_units          <= 8'd0;
        apparent_s_decile         <= 8'd0;
        apparent_s_percentiles    <= 8'd0;
        power_factor_neg          <= 1'b0;
        power_factor_units        <= 8'd0;
        power_factor_decile       <= 8'd0;
        power_factor_percentiles  <= 8'd0;
        power_metrics_valid       <= 1'b0;
    end else begin
        // 将 LCD toggle 握手信号同步到当前时钟域，供后续边沿检测和握手扩展使用。
        frame_toggle_sync1 <= lcd_frame_done_toggle;
        frame_toggle_sync2 <= frame_toggle_sync1;
        frame_toggle_sync3 <= frame_toggle_sync2;
        swap_ack_sync1     <= lcd_swap_ack_toggle;
        swap_ack_sync2     <= swap_ack_sync1;
        swap_ack_sync3     <= swap_ack_sync2;

        // 启动信号均为单周期脉冲，默认拉低，仅在对应状态中拉高一拍。
        parameters_start   <= 1'b0;
        x100_start         <= 1'b0;
        separator_start    <= 1'b0;

        // 主状态机按帧节拍依次启动测量、换算、拆分和提交，保证显示端拿到同一批结果。
        case (state)
            ST_WAIT_FRAME: begin
                // 等待 LCD 帧完成事件，作为下一批文本结果计算的触发点。
                start_delay_cnt <= 32'd0;
                if (frame_edge_wave) state <= ST_WAIT_DELAY;
            end
            ST_WAIT_DELAY: begin
                // 帧事件后延迟固定周期，避开显示切换瞬间并等待采样窗口稳定。
                if (start_delay_cnt == (START_DELAY_CYCLES - 1)) begin
                    start_delay_cnt <= 32'd0;
                    state           <= ST_START_BASIC;
                end else begin
                    start_delay_cnt <= start_delay_cnt + 32'd1;
                end
            end
            ST_START_BASIC: begin
                // 启动 parameters_initiator 原始测量调度阶段，并清空本轮 raw 结果锁存。
                parameters_start         <= 1'b1;
                rms_valid_latched        <= 1'b0;
                u_pp_valid_latched       <= 1'b0;
                i_pp_valid_latched       <= 1'b0;
                phase_valid_latched      <= 1'b0;
                freq_valid_latched       <= 1'b0;
                power_metrics_valid_latched <= 1'b0;
                u_rms_raw_pending        <= 32'sd0;
                i_rms_raw_pending        <= 32'sd0;
                u_pp_raw_pending         <= 32'sd0;
                i_pp_raw_pending         <= 32'sd0;
                phase_offset_raw_pending <= 32'sd0;
                phase_period_raw_pending <= 32'sd0;
                freq_period_raw_pending  <= 32'sd0;
                active_p_raw_pending     <= 32'sd0;
                reactive_q_raw_pending   <= 32'sd0;
                apparent_s_raw_pending   <= 32'sd0;
                power_factor_raw_pending <= 32'sd0;
                state                    <= ST_WAIT_BASIC;
            end
            ST_WAIT_BASIC: begin
                // parameters_initiator 返回批次完成后，锁存同一批 raw/valid 结果再进入 x100 换算阶段。
                if (parameters_done) begin
                    u_rms_raw_pending        <= u_rms_raw_wire;
                    i_rms_raw_pending        <= i_rms_raw_wire;
                    u_pp_raw_pending         <= u_pp_raw_wire;
                    i_pp_raw_pending         <= i_pp_raw_wire;
                    phase_offset_raw_pending <= phase_offset_raw_wire;
                    phase_period_raw_pending <= phase_period_raw_wire;
                    freq_period_raw_pending  <= freq_period_raw_wire;
                    active_p_raw_pending     <= active_p_raw_wire;
                    reactive_q_raw_pending   <= reactive_q_raw_wire;
                    apparent_s_raw_pending   <= apparent_s_raw_wire;
                    power_factor_raw_pending <= power_factor_raw_wire;
                    rms_valid_latched        <= rms_valid_wire;
                    u_pp_valid_latched       <= u_pp_valid_wire;
                    i_pp_valid_latched       <= i_pp_valid_wire;
                    phase_valid_latched      <= phase_valid_wire;
                    freq_valid_latched       <= freq_valid_wire;
                    power_metrics_valid_latched <= power_metrics_valid_wire;
                    state                    <= ST_START_X100;
                end
            end
            ST_START_X100: begin
                // 启动原始测量值到 x100 定点显示值的统一换算。
                x100_start <= 1'b1;
                state      <= ST_WAIT_X100;
            end
            ST_WAIT_X100: begin
                // 等待换算模块输出完整的 x100 定点结果。
                if (x100_done) state <= ST_START_FORMAT;
            end
            ST_START_FORMAT: begin
                // 启动十进制数字拆分，生成文本渲染直接使用的数字位。
                separator_start <= 1'b1;
                state           <= ST_WAIT_FORMAT;
            end
            ST_WAIT_FORMAT: begin
                // 等待数字拆分完成后进入统一提交阶段。
                if (separator_done) state <= ST_COMMIT;
            end
            ST_COMMIT: begin
                // 基础包齐备时刷新显示寄存器，并按各类有效位选择性更新相位、频率和功率结果。
                if (base_packet_valid) begin
                    u_rms_tens         <= u_rms_tens_sep;
                    u_rms_units        <= u_rms_units_sep;
                    u_rms_decile       <= u_rms_decile_sep;
                    u_rms_percentiles  <= u_rms_percentiles_sep;
                    u_rms_digits_valid <= u_rms_digits_valid_sep;
                    i_rms_tens         <= i_rms_tens_sep;
                    i_rms_units        <= i_rms_units_sep;
                    i_rms_decile       <= i_rms_decile_sep;
                    i_rms_percentiles  <= i_rms_percentiles_sep;
                    i_rms_digits_valid <= i_rms_digits_valid_sep;
                    u_pp_tens          <= u_pp_tens_sep;
                    u_pp_units         <= u_pp_units_sep;
                    u_pp_decile        <= u_pp_decile_sep;
                    u_pp_percentiles   <= u_pp_percentiles_sep;
                    u_pp_digits_valid  <= u_pp_digits_valid_sep;
                    i_pp_tens          <= i_pp_tens_sep;
                    i_pp_units         <= i_pp_units_sep;
                    i_pp_decile        <= i_pp_decile_sep;
                    i_pp_percentiles   <= i_pp_percentiles_sep;
                    i_pp_digits_valid  <= i_pp_digits_valid_sep;
                    if (phase_digits_valid_sep) begin
                        phase_hundreds    <= phase_hundreds_sep;
                        phase_tens        <= phase_tens_sep;
                        phase_units       <= phase_units_sep;
                        phase_decile      <= phase_decile_sep;
                        phase_percentiles <= phase_percentiles_sep;
                        phase_x100_signed <= phase_x100_wire[16:0];
                        phase_neg         <= phase_neg_sep;
                    end
                    phase_valid <= phase_digits_valid_sep;
                    if (freq_digits_valid_sep) begin
                        freq_hundreds    <= freq_hundreds_sep;
                        freq_tens        <= freq_tens_sep;
                        freq_units       <= freq_units_sep;
                        freq_decile      <= freq_decile_sep;
                        freq_percentiles <= freq_percentiles_sep;
                    end
                    freq_valid <= freq_digits_valid_sep;
                    if (power_metrics_digits_valid_sep) begin
                        active_p_neg             <= active_p_neg_sep;
                        active_p_tens            <= active_p_tens_sep;
                        active_p_units           <= active_p_units_sep;
                        active_p_decile          <= active_p_decile_sep;
                        active_p_percentiles     <= active_p_percentiles_sep;
                        reactive_q_neg           <= reactive_q_neg_sep;
                        reactive_q_tens          <= reactive_q_tens_sep;
                        reactive_q_units         <= reactive_q_units_sep;
                        reactive_q_decile        <= reactive_q_decile_sep;
                        reactive_q_percentiles   <= reactive_q_percentiles_sep;
                        apparent_s_tens          <= apparent_s_tens_sep;
                        apparent_s_units         <= apparent_s_units_sep;
                        apparent_s_decile        <= apparent_s_decile_sep;
                        apparent_s_percentiles   <= apparent_s_percentiles_sep;
                        power_factor_neg         <= power_factor_neg_sep;
                        power_factor_units       <= power_factor_units_sep;
                        power_factor_decile      <= power_factor_decile_sep;
                        power_factor_percentiles <= power_factor_percentiles_sep;
                    end
                    power_metrics_valid <= power_metrics_digits_valid_sep;
                    text_result_commit_toggle <= ~text_result_commit_toggle;
                end
                state <= ST_WAIT_FRAME;
            end
            default: state <= ST_WAIT_FRAME;
        endcase
    end
end

endmodule
