
/*
 * 模块: data_separator
 * 功能:
 *   在所有 x100 数据已经稳定后，统一提取符号位并拆分出显示所需的十进制各位。
 * 输入:
 *   clk: 工作时钟。
 *   rst_n: 低有效复位。
 *   start: 启动一次统一拆位。
 *   u_rms_x100: 电压 RMS 的 x100 补码数据。
 *   i_rms_x100: 电流 RMS 的 x100 补码数据。
 *   rms_valid: RMS 数据是否有效。
 *   u_pp_x100: 电压峰峰值的 x100 补码数据。
 *   i_pp_x100: 电流峰峰值的 x100 补码数据。
 *   u_pp_valid: 电压峰峰值数据是否有效。
 *   i_pp_valid: 电流峰峰值数据是否有效。
 *   phase_x100_signed: 相位差的 x100 补码数据。
 *   phase_valid: 相位差数据是否有效。
 *   freq_x100: 频率的 x100 补码数据。
 *   freq_valid: 频率数据是否有效。
 *   active_p_x100: 有功功率的 x100 补码数据。
 *   reactive_q_x100: 无功功率的 x100 补码数据。
 *   apparent_s_x100: 视在功率的 x100 补码数据。
 *   power_factor_x100: 功率因数的 x100 补码数据。
 *   power_metrics_valid: 功率相关数据是否有效。
 * 输出:
 *   done: 本次统一拆位完成脉冲。
 *   各量的 sign/hundreds/tens/units/decile/percentiles/valid:
 *     提供给显示链路的标准化数字位与符号位。
 */
module data_separator (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    start,

    input  wire signed [31:0]      u_rms_x100,
    input  wire signed [31:0]      i_rms_x100,
    input  wire                    rms_valid,

    input  wire signed [31:0]      u_pp_x100,
    input  wire signed [31:0]      i_pp_x100,
    input  wire                    u_pp_valid,
    input  wire                    i_pp_valid,

    input  wire signed [31:0]      phase_x100_signed,
    input  wire                    phase_valid,

    input  wire signed [31:0]      freq_x100,
    input  wire                    freq_valid,

    input  wire signed [31:0]      active_p_x100,
    input  wire signed [31:0]      reactive_q_x100,
    input  wire signed [31:0]      apparent_s_x100,
    input  wire signed [31:0]      power_factor_x100,
    input  wire                    power_metrics_valid,

    output reg                     done,

    output reg [7:0]               u_rms_hundreds,
    output reg [7:0]               u_rms_tens,
    output reg [7:0]               u_rms_units,
    output reg [7:0]               u_rms_decile,
    output reg [7:0]               u_rms_percentiles,
    output reg                     u_rms_digits_valid,
    output reg [7:0]               i_rms_hundreds,
    output reg [7:0]               i_rms_tens,
    output reg [7:0]               i_rms_units,
    output reg [7:0]               i_rms_decile,
    output reg [7:0]               i_rms_percentiles,
    output reg                     i_rms_digits_valid,

    output reg                     phase_neg,
    output reg [7:0]               phase_hundreds,
    output reg [7:0]               phase_tens,
    output reg [7:0]               phase_units,
    output reg [7:0]               phase_decile,
    output reg [7:0]               phase_percentiles,
    output reg                     phase_digits_valid,

    output reg [7:0]               freq_hundreds,
    output reg [7:0]               freq_tens,
    output reg [7:0]               freq_units,
    output reg [7:0]               freq_decile,
    output reg [7:0]               freq_percentiles,
    output reg                     freq_digits_valid,

    output reg [7:0]               u_pp_hundreds,
    output reg [7:0]               u_pp_tens,
    output reg [7:0]               u_pp_units,
    output reg [7:0]               u_pp_decile,
    output reg [7:0]               u_pp_percentiles,
    output reg                     u_pp_digits_valid,
    output reg [7:0]               i_pp_hundreds,
    output reg [7:0]               i_pp_tens,
    output reg [7:0]               i_pp_units,
    output reg [7:0]               i_pp_decile,
    output reg [7:0]               i_pp_percentiles,
    output reg                     i_pp_digits_valid,

    output reg                     active_p_neg,
    output reg [7:0]               active_p_hundreds,
    output reg [7:0]               active_p_tens,
    output reg [7:0]               active_p_units,
    output reg [7:0]               active_p_decile,
    output reg [7:0]               active_p_percentiles,
    output reg                     reactive_q_neg,
    output reg [7:0]               reactive_q_hundreds,
    output reg [7:0]               reactive_q_tens,
    output reg [7:0]               reactive_q_units,
    output reg [7:0]               reactive_q_decile,
    output reg [7:0]               reactive_q_percentiles,
    output reg [7:0]               apparent_s_hundreds,
    output reg [7:0]               apparent_s_tens,
    output reg [7:0]               apparent_s_units,
    output reg [7:0]               apparent_s_decile,
    output reg [7:0]               apparent_s_percentiles,
    output reg                     power_factor_neg,
    output reg [7:0]               power_factor_hundreds,
    output reg [7:0]               power_factor_tens,
    output reg [7:0]               power_factor_units,
    output reg [7:0]               power_factor_decile,
    output reg [7:0]               power_factor_percentiles,
    output reg                     power_metrics_digits_valid
);

wire [31:0] u_rms_abs_value;
wire [31:0] i_rms_abs_value;
wire [31:0] u_pp_abs_value;
wire [31:0] i_pp_abs_value;
wire [31:0] phase_abs_value;
wire [31:0] freq_abs_value;
wire [31:0] active_p_abs_value;
wire [31:0] reactive_q_abs_value;
wire [31:0] apparent_s_abs_value;
wire [31:0] power_factor_abs_value;

wire [7:0] u_rms_hundreds_wire;
wire [7:0] u_rms_tens_wire;
wire [7:0] u_rms_units_wire;
wire [7:0] u_rms_decile_wire;
wire [7:0] u_rms_percentiles_wire;
wire [7:0] i_rms_hundreds_wire;
wire [7:0] i_rms_tens_wire;
wire [7:0] i_rms_units_wire;
wire [7:0] i_rms_decile_wire;
wire [7:0] i_rms_percentiles_wire;
wire [7:0] u_pp_hundreds_wire;
wire [7:0] u_pp_tens_wire;
wire [7:0] u_pp_units_wire;
wire [7:0] u_pp_decile_wire;
wire [7:0] u_pp_percentiles_wire;
wire [7:0] i_pp_hundreds_wire;
wire [7:0] i_pp_tens_wire;
wire [7:0] i_pp_units_wire;
wire [7:0] i_pp_decile_wire;
wire [7:0] i_pp_percentiles_wire;
wire [7:0] phase_hundreds_wire;
wire [7:0] phase_tens_wire;
wire [7:0] phase_units_wire;
wire [7:0] phase_decile_wire;
wire [7:0] phase_percentiles_wire;
wire [7:0] freq_hundreds_wire;
wire [7:0] freq_tens_wire;
wire [7:0] freq_units_wire;
wire [7:0] freq_decile_wire;
wire [7:0] freq_percentiles_wire;
wire [7:0] active_p_hundreds_wire;
wire [7:0] active_p_tens_wire;
wire [7:0] active_p_units_wire;
wire [7:0] active_p_decile_wire;
wire [7:0] active_p_percentiles_wire;
wire [7:0] reactive_q_hundreds_wire;
wire [7:0] reactive_q_tens_wire;
wire [7:0] reactive_q_units_wire;
wire [7:0] reactive_q_decile_wire;
wire [7:0] reactive_q_percentiles_wire;
wire [7:0] apparent_s_hundreds_wire;
wire [7:0] apparent_s_tens_wire;
wire [7:0] apparent_s_units_wire;
wire [7:0] apparent_s_decile_wire;
wire [7:0] apparent_s_percentiles_wire;
wire [7:0] power_factor_hundreds_wire;
wire [7:0] power_factor_tens_wire;
wire [7:0] power_factor_units_wire;
wire [7:0] power_factor_decile_wire;
wire [7:0] power_factor_percentiles_wire;

// 将补码输入统一转换为绝对值，供后续十进制拆位模块使用。
function [31:0] abs_value_of;
    input signed [31:0] signed_value;
    reg [31:0]          abs_value;
begin
    if (signed_value[31]) begin
        abs_value = ~signed_value + 32'd1;
    end else begin
        abs_value = signed_value[31:0];
    end
    abs_value_of = abs_value;
end
endfunction

// 对所有 x100 补码量统一提取绝对值，符号位在主输出寄存时单独保存。
assign u_rms_abs_value        = abs_value_of(u_rms_x100);
assign i_rms_abs_value        = abs_value_of(i_rms_x100);
assign u_pp_abs_value         = abs_value_of(u_pp_x100);
assign i_pp_abs_value         = abs_value_of(i_pp_x100);
assign phase_abs_value        = abs_value_of(phase_x100_signed);
assign freq_abs_value         = abs_value_of(freq_x100);
assign active_p_abs_value     = abs_value_of(active_p_x100);
assign reactive_q_abs_value   = abs_value_of(reactive_q_x100);
assign apparent_s_abs_value   = abs_value_of(apparent_s_x100);
assign power_factor_abs_value = abs_value_of(power_factor_x100);

// U RMS 数值拆位实例。
value_x100_to_digits u_u_rms_digits (
    .value_x100  (u_rms_abs_value),
    .hundreds    (u_rms_hundreds_wire),
    .tens        (u_rms_tens_wire),
    .units       (u_rms_units_wire),
    .decile      (u_rms_decile_wire),
    .percentiles (u_rms_percentiles_wire)
);

// I RMS 数值拆位实例。
value_x100_to_digits u_i_rms_digits (
    .value_x100  (i_rms_abs_value),
    .hundreds    (i_rms_hundreds_wire),
    .tens        (i_rms_tens_wire),
    .units       (i_rms_units_wire),
    .decile      (i_rms_decile_wire),
    .percentiles (i_rms_percentiles_wire)
);

// U 峰峰值数值拆位实例。
value_x100_to_digits u_u_pp_digits (
    .value_x100  (u_pp_abs_value),
    .hundreds    (u_pp_hundreds_wire),
    .tens        (u_pp_tens_wire),
    .units       (u_pp_units_wire),
    .decile      (u_pp_decile_wire),
    .percentiles (u_pp_percentiles_wire)
);

// I 峰峰值数值拆位实例。
value_x100_to_digits u_i_pp_digits (
    .value_x100  (i_pp_abs_value),
    .hundreds    (i_pp_hundreds_wire),
    .tens        (i_pp_tens_wire),
    .units       (i_pp_units_wire),
    .decile      (i_pp_decile_wire),
    .percentiles (i_pp_percentiles_wire)
);

// 相位差数值拆位实例。
value_x100_to_digits u_phase_digits (
    .value_x100  (phase_abs_value),
    .hundreds    (phase_hundreds_wire),
    .tens        (phase_tens_wire),
    .units       (phase_units_wire),
    .decile      (phase_decile_wire),
    .percentiles (phase_percentiles_wire)
);

// 频率数值拆位实例。
value_x100_to_digits u_freq_digits (
    .value_x100  (freq_abs_value),
    .hundreds    (freq_hundreds_wire),
    .tens        (freq_tens_wire),
    .units       (freq_units_wire),
    .decile      (freq_decile_wire),
    .percentiles (freq_percentiles_wire)
);

// 有功功率数值拆位实例。
value_x100_to_digits u_active_p_digits (
    .value_x100  (active_p_abs_value),
    .hundreds    (active_p_hundreds_wire),
    .tens        (active_p_tens_wire),
    .units       (active_p_units_wire),
    .decile      (active_p_decile_wire),
    .percentiles (active_p_percentiles_wire)
);

// 无功功率数值拆位实例。
value_x100_to_digits u_reactive_q_digits (
    .value_x100  (reactive_q_abs_value),
    .hundreds    (reactive_q_hundreds_wire),
    .tens        (reactive_q_tens_wire),
    .units       (reactive_q_units_wire),
    .decile      (reactive_q_decile_wire),
    .percentiles (reactive_q_percentiles_wire)
);

// 视在功率数值拆位实例。
value_x100_to_digits u_apparent_s_digits (
    .value_x100  (apparent_s_abs_value),
    .hundreds    (apparent_s_hundreds_wire),
    .tens        (apparent_s_tens_wire),
    .units       (apparent_s_units_wire),
    .decile      (apparent_s_decile_wire),
    .percentiles (apparent_s_percentiles_wire)
);

// 功率因数数值拆位实例。
value_x100_to_digits u_power_factor_digits (
    .value_x100  (power_factor_abs_value),
    .hundreds    (power_factor_hundreds_wire),
    .tens        (power_factor_tens_wire),
    .units       (power_factor_units_wire),
    .decile      (power_factor_decile_wire),
    .percentiles (power_factor_percentiles_wire)
);

// 仅在上游确认所有 x100 数据稳定后，统一锁存本次拆位结果和符号位。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        done                       <= 1'b0;
        u_rms_hundreds             <= 8'd0;
        u_rms_tens                 <= 8'd0;
        u_rms_units                <= 8'd0;
        u_rms_decile               <= 8'd0;
        u_rms_percentiles          <= 8'd0;
        u_rms_digits_valid         <= 1'b0;
        i_rms_hundreds             <= 8'd0;
        i_rms_tens                 <= 8'd0;
        i_rms_units                <= 8'd0;
        i_rms_decile               <= 8'd0;
        i_rms_percentiles          <= 8'd0;
        i_rms_digits_valid         <= 1'b0;
        phase_neg                  <= 1'b0;
        phase_hundreds             <= 8'd0;
        phase_tens                 <= 8'd0;
        phase_units                <= 8'd0;
        phase_decile               <= 8'd0;
        phase_percentiles          <= 8'd0;
        phase_digits_valid         <= 1'b0;
        freq_hundreds              <= 8'd0;
        freq_tens                  <= 8'd0;
        freq_units                 <= 8'd0;
        freq_decile                <= 8'd0;
        freq_percentiles           <= 8'd0;
        freq_digits_valid          <= 1'b0;
        u_pp_hundreds              <= 8'd0;
        u_pp_tens                  <= 8'd0;
        u_pp_units                 <= 8'd0;
        u_pp_decile                <= 8'd0;
        u_pp_percentiles           <= 8'd0;
        u_pp_digits_valid          <= 1'b0;
        i_pp_hundreds              <= 8'd0;
        i_pp_tens                  <= 8'd0;
        i_pp_units                 <= 8'd0;
        i_pp_decile                <= 8'd0;
        i_pp_percentiles           <= 8'd0;
        i_pp_digits_valid          <= 1'b0;
        active_p_neg               <= 1'b0;
        active_p_hundreds          <= 8'd0;
        active_p_tens              <= 8'd0;
        active_p_units             <= 8'd0;
        active_p_decile            <= 8'd0;
        active_p_percentiles       <= 8'd0;
        reactive_q_neg             <= 1'b0;
        reactive_q_hundreds        <= 8'd0;
        reactive_q_tens            <= 8'd0;
        reactive_q_units           <= 8'd0;
        reactive_q_decile          <= 8'd0;
        reactive_q_percentiles     <= 8'd0;
        apparent_s_hundreds        <= 8'd0;
        apparent_s_tens            <= 8'd0;
        apparent_s_units           <= 8'd0;
        apparent_s_decile          <= 8'd0;
        apparent_s_percentiles     <= 8'd0;
        power_factor_neg           <= 1'b0;
        power_factor_hundreds      <= 8'd0;
        power_factor_tens          <= 8'd0;
        power_factor_units         <= 8'd0;
        power_factor_decile        <= 8'd0;
        power_factor_percentiles   <= 8'd0;
        power_metrics_digits_valid <= 1'b0;
    end else begin
        done <= 1'b0;

        if (start) begin
            u_rms_hundreds             <= u_rms_hundreds_wire;
            u_rms_tens                 <= u_rms_tens_wire;
            u_rms_units                <= u_rms_units_wire;
            u_rms_decile               <= u_rms_decile_wire;
            u_rms_percentiles          <= u_rms_percentiles_wire;
            u_rms_digits_valid         <= rms_valid;
            i_rms_hundreds             <= i_rms_hundreds_wire;
            i_rms_tens                 <= i_rms_tens_wire;
            i_rms_units                <= i_rms_units_wire;
            i_rms_decile               <= i_rms_decile_wire;
            i_rms_percentiles          <= i_rms_percentiles_wire;
            i_rms_digits_valid         <= rms_valid;

            phase_neg                  <= phase_x100_signed[31] && (phase_abs_value != 32'd0);
            phase_hundreds             <= phase_hundreds_wire;
            phase_tens                 <= phase_tens_wire;
            phase_units                <= phase_units_wire;
            phase_decile               <= phase_decile_wire;
            phase_percentiles          <= phase_percentiles_wire;
            phase_digits_valid         <= phase_valid;

            freq_hundreds              <= freq_hundreds_wire;
            freq_tens                  <= freq_tens_wire;
            freq_units                 <= freq_units_wire;
            freq_decile                <= freq_decile_wire;
            freq_percentiles           <= freq_percentiles_wire;
            freq_digits_valid          <= freq_valid;

            u_pp_hundreds              <= u_pp_hundreds_wire;
            u_pp_tens                  <= u_pp_tens_wire;
            u_pp_units                 <= u_pp_units_wire;
            u_pp_decile                <= u_pp_decile_wire;
            u_pp_percentiles           <= u_pp_percentiles_wire;
            u_pp_digits_valid          <= u_pp_valid;
            i_pp_hundreds              <= i_pp_hundreds_wire;
            i_pp_tens                  <= i_pp_tens_wire;
            i_pp_units                 <= i_pp_units_wire;
            i_pp_decile                <= i_pp_decile_wire;
            i_pp_percentiles           <= i_pp_percentiles_wire;
            i_pp_digits_valid          <= i_pp_valid;

            active_p_neg               <= active_p_x100[31] && (active_p_abs_value != 32'd0);
            active_p_hundreds          <= active_p_hundreds_wire;
            active_p_tens              <= active_p_tens_wire;
            active_p_units             <= active_p_units_wire;
            active_p_decile            <= active_p_decile_wire;
            active_p_percentiles       <= active_p_percentiles_wire;

            reactive_q_neg             <= reactive_q_x100[31] && (reactive_q_abs_value != 32'd0);
            reactive_q_hundreds        <= reactive_q_hundreds_wire;
            reactive_q_tens            <= reactive_q_tens_wire;
            reactive_q_units           <= reactive_q_units_wire;
            reactive_q_decile          <= reactive_q_decile_wire;
            reactive_q_percentiles     <= reactive_q_percentiles_wire;

            apparent_s_hundreds        <= apparent_s_hundreds_wire;
            apparent_s_tens            <= apparent_s_tens_wire;
            apparent_s_units           <= apparent_s_units_wire;
            apparent_s_decile          <= apparent_s_decile_wire;
            apparent_s_percentiles     <= apparent_s_percentiles_wire;

            power_factor_neg           <= power_factor_x100[31] && (power_factor_abs_value != 32'd0);
            power_factor_hundreds      <= power_factor_hundreds_wire;
            power_factor_tens          <= power_factor_tens_wire;
            power_factor_units         <= power_factor_units_wire;
            power_factor_decile        <= power_factor_decile_wire;
            power_factor_percentiles   <= power_factor_percentiles_wire;
            power_metrics_digits_valid <= power_metrics_valid;

            done                       <= 1'b1;
        end
    end
end

endmodule
