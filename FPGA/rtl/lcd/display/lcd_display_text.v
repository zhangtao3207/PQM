/*
 * 模块: lcd_display_text
 * 功能:
 *   根据时域/频域测量结果、当前页面状态和像素坐标，生成 LCD 文本层的字符索引、字形相对坐标与颜色。
 *
 * 输入:
 *   pixel_xpos: 当前扫描像素的 X 坐标。
 *   pixel_ypos: 当前扫描像素的 Y 坐标。
 *   u_rms_hundreds: 电压 RMS 的百位数字。
 *   u_rms_tens: 电压 RMS 的十位数字。
 *   u_rms_units: 电压 RMS 的个位数字。
 *   u_rms_decile: 电压 RMS 的十分位数字。
 *   u_rms_percentiles: 电压 RMS 的百分位数字。
 *   u_rms_digits_valid: 电压 RMS 数字是否有效。
 *   i_rms_hundreds: 电流 RMS 的百位数字。
 *   i_rms_tens: 电流 RMS 的十位数字。
 *   i_rms_units: 电流 RMS 的个位数字。
 *   i_rms_decile: 电流 RMS 的十分位数字。
 *   i_rms_percentiles: 电流 RMS 的百分位数字。
 *   i_rms_digits_valid: 电流 RMS 数字是否有效。
 *   phase_neg: 功率角符号位，1 表示负值。
 *   phase_hundreds: 功率角的百位数字。
 *   phase_tens: 功率角的十位数字。
 *   phase_units: 功率角的个位数字。
 *   phase_decile: 功率角的十分位数字。
 *   phase_percentiles: 功率角的百分位数字。
 *   phase_valid: 功率角数字是否有效。
 *   freq_hundreds: 频率的百位数字。
 *   freq_tens: 频率的十位数字。
 *   freq_units: 频率的个位数字。
 *   freq_decile: 频率的十分位数字。
 *   freq_percentiles: 频率的百分位数字。
 *   freq_valid: 频率数字是否有效。
 *   u_pp_hundreds: 电压峰峰值的百位数字。
 *   u_pp_tens: 电压峰峰值的十位数字。
 *   u_pp_units: 电压峰峰值的个位数字。
 *   u_pp_decile: 电压峰峰值的十分位数字。
 *   u_pp_percentiles: 电压峰峰值的百分位数字。
 *   u_pp_digits_valid: 电压峰峰值数字是否有效。
 *   i_pp_hundreds: 电流峰峰值的百位数字。
 *   i_pp_tens: 电流峰峰值的十位数字。
 *   i_pp_units: 电流峰峰值的个位数字。
 *   i_pp_decile: 电流峰峰值的十分位数字。
 *   i_pp_percentiles: 电流峰峰值的百分位数字。
 *   i_pp_digits_valid: 电流峰峰值数字是否有效。
 *   active_p_neg: 有功功率符号位，1 表示负值。
 *   active_p_hundreds: 有功功率的百位数字。
 *   active_p_tens: 有功功率的十位数字。
 *   active_p_units: 有功功率的个位数字。
 *   active_p_decile: 有功功率的十分位数字。
 *   active_p_percentiles: 有功功率的百分位数字。
 *   reactive_q_neg: 无功功率符号位，1 表示负值。
 *   reactive_q_hundreds: 无功功率的百位数字。
 *   reactive_q_tens: 无功功率的十位数字。
 *   reactive_q_units: 无功功率的个位数字。
 *   reactive_q_decile: 无功功率的十分位数字。
 *   reactive_q_percentiles: 无功功率的百分位数字。
 *   apparent_s_hundreds: 视在功率的百位数字。
 *   apparent_s_tens: 视在功率的十位数字。
 *   apparent_s_units: 视在功率的个位数字。
 *   apparent_s_decile: 视在功率的十分位数字。
 *   apparent_s_percentiles: 视在功率的百分位数字。
 *   power_factor_neg: 功率因数符号位，1 表示负值。
 *   power_factor_units: 功率因数的个位数字。
 *   power_factor_decile: 功率因数的十分位数字。
 *   power_factor_percentiles: 功率因数的百分位数字。
 *   power_metrics_valid: 功率相关数字是否有效。
 *   sharp_alarm_code: 时域骤升/骤降告警编码。
 *   freq_thd_u_hundreds: 电压 THD 的百位数字。
 *   freq_thd_u_tens: 电压 THD 的十位数字。
 *   freq_thd_u_units: 电压 THD 的个位数字。
 *   freq_thd_u_decile: 电压 THD 的十分位数字。
 *   freq_thd_u_percentiles: 电压 THD 的百分位数字。
 *   freq_thd_u_valid: 电压 THD 数字是否有效。
 *   freq_thd_i_hundreds: 电流 THD 的百位数字。
 *   freq_thd_i_tens: 电流 THD 的十位数字。
 *   freq_thd_i_units: 电流 THD 的个位数字。
 *   freq_thd_i_decile: 电流 THD 的十分位数字。
 *   freq_thd_i_percentiles: 电流 THD 的百分位数字。
 *   freq_thd_i_valid: 电流 THD 数字是否有效。
 *   freq_u1_mag_hundreds: 基波电压幅值占比的百位数字。
 *   freq_u1_mag_tens: 基波电压幅值占比的十位数字。
 *   freq_u1_mag_units: 基波电压幅值占比的个位数字。
 *   freq_u1_mag_decile: 基波电压幅值占比的十分位数字。
 *   freq_u1_mag_percentiles: 基波电压幅值占比的百分位数字。
 *   freq_u1_mag_valid: 基波电压幅值占比数字是否有效。
 *   freq_i1_mag_hundreds: 基波电流幅值占比的百位数字。
 *   freq_i1_mag_tens: 基波电流幅值占比的十位数字。
 *   freq_i1_mag_units: 基波电流幅值占比的个位数字。
 *   freq_i1_mag_decile: 基波电流幅值占比的十分位数字。
 *   freq_i1_mag_percentiles: 基波电流幅值占比的百分位数字。
 *   freq_i1_mag_valid: 基波电流幅值占比数字是否有效。
 *   freq_phase1_neg: 基波相位差符号位，1 表示负值。
 *   freq_phase1_hundreds: 基波相位差的百位数字。
 *   freq_phase1_tens: 基波相位差的十位数字。
 *   freq_phase1_units: 基波相位差的个位数字。
 *   freq_phase1_decile: 基波相位差的十分位数字。
 *   freq_phase1_percentiles: 基波相位差的百分位数字。
 *   freq_phase1_valid: 基波相位差数字是否有效。
 *   freq_dc_u_hundreds: 电压直流分量的百位数字。
 *   freq_dc_u_tens: 电压直流分量的十位数字。
 *   freq_dc_u_units: 电压直流分量的个位数字。
 *   freq_dc_u_decile: 电压直流分量的十分位数字。
 *   freq_dc_u_percentiles: 电压直流分量的百分位数字。
 *   freq_dc_u_valid: 电压直流分量数字是否有效。
 *   freq_dc_i_hundreds: 电流直流分量的百位数字。
 *   freq_dc_i_tens: 电流直流分量的十位数字。
 *   freq_dc_i_units: 电流直流分量的个位数字。
 *   freq_dc_i_decile: 电流直流分量的十分位数字。
 *   freq_dc_i_percentiles: 电流直流分量的百分位数字。
 *   freq_dc_i_valid: 电流直流分量数字是否有效。
 *   freq_dh_order_u_text: 电压主导谐波次序文本打包总线。
 *   freq_dh_order_i_text: 电流主导谐波次序文本打包总线。
 *   full_scale_low_range_active: 时域量程切换标志，1 表示 10V/3A 档。
 *   freeze_active: Freeze/Auto 按钮当前显示状态。
 *   frequency_page_active: 页面选择标志，1 表示频域页。
 *   harmonic_window_index: 频域谐波窗口序号。
 *
 * 输出:
 *   text_en: 当前像素是否命中文本区域。
 *   text_font_small: 当前像素使用小字体还是大字体。
 *   text_char_idx: 当前像素对应的字体索引。
 *   text_rel_x: 当前像素在字符字模内的 X 偏移。
 *   text_rel_y: 当前像素在字符字模内的 Y 偏移。
 *   text_color: 当前像素文本颜色。
 */
module lcd_display_text(
    input      [10:0] pixel_xpos,
    input      [10:0] pixel_ypos,
    input      [7:0]  u_rms_hundreds,
    input      [7:0]  u_rms_tens,
    input      [7:0]  u_rms_units,
    input      [7:0]  u_rms_decile,
    input      [7:0]  u_rms_percentiles,
    input             u_rms_digits_valid,
    input      [7:0]  i_rms_hundreds,
    input      [7:0]  i_rms_tens,
    input      [7:0]  i_rms_units,
    input      [7:0]  i_rms_decile,
    input      [7:0]  i_rms_percentiles,
    input             i_rms_digits_valid,
    input             phase_neg,
    input      [7:0]  phase_hundreds,
    input      [7:0]  phase_tens,
    input      [7:0]  phase_units,
    input      [7:0]  phase_decile,
    input      [7:0]  phase_percentiles,
    input             phase_valid,
    input      [7:0]  freq_hundreds,
    input      [7:0]  freq_tens,
    input      [7:0]  freq_units,
    input      [7:0]  freq_decile,
    input      [7:0]  freq_percentiles,
    input             freq_valid,
    input      [7:0]  u_pp_hundreds,
    input      [7:0]  u_pp_tens,
    input      [7:0]  u_pp_units,
    input      [7:0]  u_pp_decile,
    input      [7:0]  u_pp_percentiles,
    input             u_pp_digits_valid,
    input      [7:0]  i_pp_hundreds,
    input      [7:0]  i_pp_tens,
    input      [7:0]  i_pp_units,
    input      [7:0]  i_pp_decile,
    input      [7:0]  i_pp_percentiles,
    input             i_pp_digits_valid,
    input             active_p_neg,
    input      [7:0]  active_p_hundreds,
    input      [7:0]  active_p_tens,
    input      [7:0]  active_p_units,
    input      [7:0]  active_p_decile,
    input      [7:0]  active_p_percentiles,
    input             reactive_q_neg,
    input      [7:0]  reactive_q_hundreds,
    input      [7:0]  reactive_q_tens,
    input      [7:0]  reactive_q_units,
    input      [7:0]  reactive_q_decile,
    input      [7:0]  reactive_q_percentiles,
    input      [7:0]  apparent_s_hundreds,
    input      [7:0]  apparent_s_tens,
    input      [7:0]  apparent_s_units,
    input      [7:0]  apparent_s_decile,
    input      [7:0]  apparent_s_percentiles,
    input             power_factor_neg,
    input      [7:0]  power_factor_units,
    input      [7:0]  power_factor_decile,
    input      [7:0]  power_factor_percentiles,
    input             power_metrics_valid,
    input      [2:0]  sharp_alarm_code,
    input      [7:0]  freq_thd_u_hundreds,
    input      [7:0]  freq_thd_u_tens,
    input      [7:0]  freq_thd_u_units,
    input      [7:0]  freq_thd_u_decile,
    input      [7:0]  freq_thd_u_percentiles,
    input             freq_thd_u_valid,
    input      [7:0]  freq_thd_i_hundreds,
    input      [7:0]  freq_thd_i_tens,
    input      [7:0]  freq_thd_i_units,
    input      [7:0]  freq_thd_i_decile,
    input      [7:0]  freq_thd_i_percentiles,
    input             freq_thd_i_valid,
    input      [7:0]  freq_u1_mag_hundreds,
    input      [7:0]  freq_u1_mag_tens,
    input      [7:0]  freq_u1_mag_units,
    input      [7:0]  freq_u1_mag_decile,
    input      [7:0]  freq_u1_mag_percentiles,
    input             freq_u1_mag_valid,
    input      [7:0]  freq_i1_mag_hundreds,
    input      [7:0]  freq_i1_mag_tens,
    input      [7:0]  freq_i1_mag_units,
    input      [7:0]  freq_i1_mag_decile,
    input      [7:0]  freq_i1_mag_percentiles,
    input             freq_i1_mag_valid,
    input             freq_phase1_neg,
    input      [7:0]  freq_phase1_hundreds,
    input      [7:0]  freq_phase1_tens,
    input      [7:0]  freq_phase1_units,
    input      [7:0]  freq_phase1_decile,
    input      [7:0]  freq_phase1_percentiles,
    input             freq_phase1_valid,
    input      [7:0]  freq_dc_u_hundreds,
    input      [7:0]  freq_dc_u_tens,
    input      [7:0]  freq_dc_u_units,
    input      [7:0]  freq_dc_u_decile,
    input      [7:0]  freq_dc_u_percentiles,
    input             freq_dc_u_valid,
    input      [7:0]  freq_dc_i_hundreds,
    input      [7:0]  freq_dc_i_tens,
    input      [7:0]  freq_dc_i_units,
    input      [7:0]  freq_dc_i_decile,
    input      [7:0]  freq_dc_i_percentiles,
    input             freq_dc_i_valid,
    input      [199:0] freq_dh_order_u_text,
    input      [199:0] freq_dh_order_i_text,
    input             full_scale_low_range_active,
    input             freeze_active,
    input             frequency_page_active,
    input      [4:0]  harmonic_window_index,
    output reg        text_en,
    output reg        text_font_small,
    output reg [6:0]  text_char_idx,
    output reg [5:0]  text_rel_x,
    output reg [5:0]  text_rel_y,
    output reg [23:0] text_color
);

// 字体尺寸参数，分别给 16x32 大字和 10x20 小字使用。
localparam [5:0] BIG_CHAR_W   = 6'd16;
localparam [5:0] BIG_CHAR_H   = 6'd32;
localparam [5:0] SMALL_CHAR_W = 6'd10;
localparam [5:0] SMALL_CHAR_H = 6'd20;

// 字体 ROM 中各类字符的索引常量。
localparam [6:0] FONT_BLANK      = 7'd127;
localparam [6:0] FONT_DIGIT_BASE = 7'd0;
localparam [6:0] FONT_UPPER_BASE = 7'd10;
localparam [6:0] FONT_LOWER_BASE = 7'd36;
localparam [6:0] FONT_LPAREN     = 7'd71;
localparam [6:0] FONT_RPAREN     = 7'd72;
localparam [6:0] FONT_UNDERSCORE = 7'd73;
localparam [6:0] FONT_PLUS       = 7'd74;
localparam [6:0] FONT_MINUS      = 7'd75;
localparam [6:0] FONT_DOT        = 7'd84;
localparam [6:0] FONT_COLON      = 7'd89;
localparam [6:0] FONT_PERCENT    = 7'd90;
localparam [6:0] FONT_LESS       = 7'd91;
localparam [6:0] FONT_GREATER    = 7'd92;

// 文本渲染使用的颜色常量。
localparam [23:0] TEXT_WHITE   = 24'hF2F6FA;
localparam [23:0] TEXT_SOFT    = 24'hC6D3E2;
localparam [23:0] TEXT_DIM     = 24'h95A9BE;
localparam [23:0] WAVE_U_COLOR = 24'h39E46F;
localparam [23:0] WAVE_I_COLOR = 24'hFFD84E;
localparam [23:0] ACCENT_COLOR = 24'h58B6FF;
localparam [23:0] ALARM_COLOR  = 24'hFF5A5F;

// 时域页和频域页各文本区域的起始坐标。
localparam [10:0] TITLE_TXT_X  = 11'd32;
localparam [10:0] TITLE_TXT_Y  = 11'd6;
localparam [10:0] BTN_TXT_X    = 11'd583;
localparam [10:0] BTN_TXT_Y    = 11'd6;
localparam [10:0] AUTO_FREEZE_TXT_X = 11'd680;
localparam [10:0] AUTO_AUTO_TXT_X   = 11'd696;
localparam [10:0] AUTO_TXT_Y   = 11'd6;
localparam [10:0] PLOT_TXT_X   = 11'd68;
localparam [10:0] PLOT_TXT_Y   = 11'd72;
localparam [10:0] AXIS_V_X     = 11'd60;
localparam [10:0] AXIS_V_Y     = 11'd118;
localparam [10:0] AXIS_I_X     = 11'd306;
localparam [10:0] AXIS_I_Y     = 11'd118;
localparam [10:0] AXIS_TICK0_X = 11'd66;
localparam [10:0] AXIS_TICK1_X = 11'd140;
localparam [10:0] AXIS_TICK2_X = 11'd229;
localparam [10:0] AXIS_TICK3_X = 11'd317;
localparam [10:0] AXIS_TICK4_X = 11'd389;
localparam [10:0] AXIS_TICK_Y  = 11'd392;
localparam [10:0] AXIS_T_X     = 11'd336;
localparam [10:0] AXIS_T_Y     = 11'd416;
localparam [10:0] V_TICK_X     = 11'd2;
localparam [10:0] V_TICK_Y0    = 11'd134;
localparam [10:0] V_TICK_STEP  = 11'd40;
localparam [10:0] I_TICK_X     = 11'd424;
localparam [10:0] I_TICK_Y0    = 11'd134;
localparam [10:0] I_TICK_STEP  = 11'd40;
localparam [10:0] RP_TITLE_X   = 11'd520;
localparam [10:0] RP_TITLE_Y   = 11'd76;
localparam [10:0] LINE_X       = 11'd516;
localparam [10:0] LINE_Y0      = 11'd114;
localparam [10:0] LINE_STEP    = 11'd28;
localparam [10:0] ALARM_LINE_Y = LINE_Y0 + LINE_STEP + LINE_STEP + LINE_STEP + LINE_STEP +
                                  LINE_STEP + LINE_STEP + LINE_STEP + LINE_STEP;
localparam [10:0] U_PP_X       = 11'd68;
localparam [10:0] U_PP_Y       = 11'd425;
localparam [10:0] I_PP_X       = 11'd68;
localparam [10:0] I_PP_Y       = 11'd449;
localparam [10:0] FREQ_LABEL_X = 11'd30;
localparam [10:0] FREQ_MAG_LABEL_Y = 11'd118;
localparam [10:0] FREQ_PHASE_LABEL_Y = 11'd456;
localparam [10:0] FREQ_HARM_LABEL_X = 11'd266;
localparam [10:0] FREQ_HARM_LABEL_Y = 11'd456;
localparam [10:0] FREQ_PREV_TXT_X = 11'd339;
localparam [10:0] FREQ_NEXT_TXT_X = 11'd389;
localparam [10:0] FREQ_BTN_TXT_Y  = 11'd184;
localparam [10:0] FREQ_AXIS_TICK0_X  = 11'd45;
localparam [10:0] FREQ_AXIS_TICK1_X  = 11'd63;
localparam [10:0] FREQ_AXIS_TICK5_X  = 11'd133;
localparam [10:0] FREQ_AXIS_TICK10_X = 11'd216;
localparam [10:0] FREQ_AXIS_TICK15_X = 11'd304;
localparam [10:0] FREQ_AXIS_TICK20_X = 11'd392;
localparam [10:0] FREQ_AXIS_TICK25_X = 11'd470;
localparam [10:0] FREQ_AXIS_TICK_Y   = 11'd426;
localparam [10:0] FREQ_AXIS_TICK_W   = 11'd30;

localparam integer MAX_TEXT_LEN = 25;
localparam integer TITLE_LEN    = 19;
localparam integer BTN_LEN      = 4;
localparam integer AUTO_FREEZE_LEN = 6;
localparam integer AUTO_AUTO_LEN   = 4;
localparam integer PLOT_LEN     = 20;
localparam integer AXIS_V_LEN   = 11;
localparam integer AXIS_I_LEN   = 11;
localparam integer AXIS_T_LEN   = 8;
localparam integer V_TICK_LEN   = 4;
localparam integer I_TICK_LEN   = 4;
localparam integer T_TICK_LEN   = 3;
localparam integer RP_HEAD_LEN  = 10;
localparam integer FREQ_LEN     = 22;
localparam integer RMS_LEN      = 17;
localparam integer PHASE_LEN    = 25;
localparam integer ACTIVE_LEN   = 21;
localparam integer REACTIVE_LEN = 25;
localparam integer APPARENT_LEN = 24;
localparam integer PF_LEN       = 20;
localparam integer ALARM_LEN    = 17;
localparam integer PP_LEN       = 15;
localparam [10:0] ALARM_LINE_W  = 11'd170;
localparam integer FREQ_TITLE_LEN = 24;
localparam integer FREQ_PLOT_LEN = 20;
localparam integer FREQ_MAG_LABEL_LEN = 13;
localparam integer FREQ_PHASE_LABEL_LEN = 16;
localparam integer FREQ_HARM_LABEL_LEN = 14;
localparam integer FREQ_AXIS_TICK_LEN = 3;
localparam integer FREQ_FUND_LEN = 24;
localparam integer FREQ_U1_LEN = 18;
localparam integer FREQ_I1_LEN = 18;
localparam integer FREQ_THD_LEN = 17;
localparam integer FREQ_PHASE1_LEN = 21;
localparam integer FREQ_DC_LEN = 16;
localparam integer FREQ_DH_LEN = 25;

localparam [8*TITLE_LEN-1:0]   TITLE_STR   = "MODE: Single - Time";
localparam [8*BTN_LEN-1:0]     BTN_STR     = "MODE";
localparam [8*AUTO_FREEZE_LEN-1:0] AUTO_FREEZE_STR = "Freeze";
localparam [8*AUTO_AUTO_LEN-1:0]   AUTO_AUTO_STR   = "Auto";
localparam [8*PLOT_LEN-1:0]    PLOT_STR    = "Time Domain Analysis";
localparam [8*AXIS_V_LEN-1:0]  AXIS_V_STR  = "Voltage (V)";
localparam [8*AXIS_I_LEN-1:0]  AXIS_I_STR  = "Current (A)";
localparam [8*AXIS_T_LEN-1:0]  AXIS_T_STR  = "Time(ms)";
localparam [8*RP_HEAD_LEN-1:0] RP_HEAD_STR = "Parameters";

localparam integer U_TICK_FULL_HIGH_X100       = 35000;
localparam integer U_TICK_TWO_THIRDS_HIGH_X100 = 23333;
localparam integer U_TICK_ONE_THIRD_HIGH_X100  = 11667;
localparam integer I_TICK_FULL_HIGH_X100       = 3000;
localparam integer I_TICK_TWO_THIRDS_HIGH_X100 = 2000;
localparam integer I_TICK_ONE_THIRD_HIGH_X100  = 1000;
localparam integer U_TICK_FULL_LOW_X100        = 1000;
localparam integer U_TICK_TWO_THIRDS_LOW_X100  = 667;
localparam integer U_TICK_ONE_THIRD_LOW_X100   = 333;
localparam integer I_TICK_FULL_LOW_X100        = 300;
localparam integer I_TICK_TWO_THIRDS_LOW_X100  = 200;
localparam integer I_TICK_ONE_THIRD_LOW_X100   = 100;

wire [7:0] u_tick_full_hundreds;
wire [7:0] u_tick_full_tens;
wire [7:0] u_tick_full_units;
wire [7:0] u_tick_two_thirds_hundreds;
wire [7:0] u_tick_two_thirds_tens;
wire [7:0] u_tick_two_thirds_units;
wire [7:0] u_tick_one_third_hundreds;
wire [7:0] u_tick_one_third_tens;
wire [7:0] u_tick_one_third_units;
wire [7:0] i_tick_full_hundreds;
wire [7:0] i_tick_full_tens;
wire [7:0] i_tick_full_units;
wire [7:0] i_tick_two_thirds_hundreds;
wire [7:0] i_tick_two_thirds_tens;
wire [7:0] i_tick_two_thirds_units;
wire [7:0] i_tick_one_third_hundreds;
wire [7:0] i_tick_one_third_tens;
wire [7:0] i_tick_one_third_units;
wire [31:0] u_tick_full_x100;
wire [31:0] u_tick_two_thirds_x100;
wire [31:0] u_tick_one_third_x100;
wire [31:0] i_tick_full_x100;
wire [31:0] i_tick_two_thirds_x100;
wire [31:0] i_tick_one_third_x100;
wire       sharp_alarm_active;
wire       sharp_alarm_is_current;
wire       sharp_alarm_is_drop;

integer line_slot;
integer tick_slot;

// 根据当前量程选择电压/电流纵轴刻度的满量程、2/3FS 和 1/3FS 数值。
assign u_tick_full_x100 =
    full_scale_low_range_active ? U_TICK_FULL_LOW_X100 : U_TICK_FULL_HIGH_X100;
assign u_tick_two_thirds_x100 =
    full_scale_low_range_active ? U_TICK_TWO_THIRDS_LOW_X100 : U_TICK_TWO_THIRDS_HIGH_X100;
assign u_tick_one_third_x100 =
    full_scale_low_range_active ? U_TICK_ONE_THIRD_LOW_X100 : U_TICK_ONE_THIRD_HIGH_X100;
assign i_tick_full_x100 =
    full_scale_low_range_active ? I_TICK_FULL_LOW_X100 : I_TICK_FULL_HIGH_X100;
assign i_tick_two_thirds_x100 =
    full_scale_low_range_active ? I_TICK_TWO_THIRDS_LOW_X100 : I_TICK_TWO_THIRDS_HIGH_X100;
assign i_tick_one_third_x100 =
    full_scale_low_range_active ? I_TICK_ONE_THIRD_LOW_X100 : I_TICK_ONE_THIRD_HIGH_X100;

// 将当前档位下的刻度值转换成三位整数数字，供纵轴刻度文本直接复用。
value_x100_to_digits u_u_tick_full_digits (
    .value_x100 (u_tick_full_x100 + 50),
    .hundreds   (u_tick_full_hundreds),
    .tens       (u_tick_full_tens),
    .units      (u_tick_full_units),
    .decile     (),
    .percentiles()
);

value_x100_to_digits u_u_tick_two_thirds_digits (
    .value_x100 (u_tick_two_thirds_x100 + 50),
    .hundreds   (u_tick_two_thirds_hundreds),
    .tens       (u_tick_two_thirds_tens),
    .units      (u_tick_two_thirds_units),
    .decile     (),
    .percentiles()
);

value_x100_to_digits u_u_tick_one_third_digits (
    .value_x100 (u_tick_one_third_x100 + 50),
    .hundreds   (u_tick_one_third_hundreds),
    .tens       (u_tick_one_third_tens),
    .units      (u_tick_one_third_units),
    .decile     (),
    .percentiles()
);

value_x100_to_digits u_i_tick_full_digits (
    .value_x100 (i_tick_full_x100 + 50),
    .hundreds   (i_tick_full_hundreds),
    .tens       (i_tick_full_tens),
    .units      (i_tick_full_units),
    .decile     (),
    .percentiles()
);

value_x100_to_digits u_i_tick_two_thirds_digits (
    .value_x100 (i_tick_two_thirds_x100 + 50),
    .hundreds   (i_tick_two_thirds_hundreds),
    .tens       (i_tick_two_thirds_tens),
    .units      (i_tick_two_thirds_units),
    .decile     (),
    .percentiles()
);

value_x100_to_digits u_i_tick_one_third_digits (
    .value_x100 (i_tick_one_third_x100 + 50),
    .hundreds   (i_tick_one_third_hundreds),
    .tens       (i_tick_one_third_tens),
    .units      (i_tick_one_third_units),
    .decile     (),
    .percentiles()
);
// 从 sharp_alarm_code 中译码是否告警、告警通道以及 rise/drop 类型。
assign sharp_alarm_active     = (sharp_alarm_code != 3'd0);
assign sharp_alarm_is_current = (sharp_alarm_code == 3'd3) || (sharp_alarm_code == 3'd4);
assign sharp_alarm_is_drop    = (sharp_alarm_code == 3'd2) || (sharp_alarm_code == 3'd4);

// 将 ASCII 字符映射到字体 ROM 索引。
function [6:0] ascii_to_idx;
    input [7:0] ch;
    begin
        if (ch >= "0" && ch <= "9")
            ascii_to_idx = FONT_DIGIT_BASE + (ch - "0");
        else if (ch >= "A" && ch <= "Z")
            ascii_to_idx = FONT_UPPER_BASE + (ch - "A");
        else if (ch >= "a" && ch <= "z")
            ascii_to_idx = FONT_LOWER_BASE + (ch - "a");
        else begin
            case (ch)
                " ": ascii_to_idx = FONT_BLANK;
                "(": ascii_to_idx = FONT_LPAREN;
                ")": ascii_to_idx = FONT_RPAREN;
                "_": ascii_to_idx = FONT_UNDERSCORE;
                "+": ascii_to_idx = FONT_PLUS;
                "-": ascii_to_idx = FONT_MINUS;
                ".": ascii_to_idx = FONT_DOT;
                ":": ascii_to_idx = FONT_COLON;
                "%": ascii_to_idx = FONT_PERCENT;
                "<": ascii_to_idx = FONT_LESS;
                ">": ascii_to_idx = FONT_GREATER;
                default: ascii_to_idx = FONT_BLANK;
            endcase
        end
    end
endfunction

// 根据有效位和百位数值决定是否显示百位字符。
function [7:0] hundreds_ascii_or_blank;
    input       digits_valid;
    input [7:0] hundreds_digit;
    begin
        hundreds_ascii_or_blank =
            digits_valid ? ((hundreds_digit == 8'd0) ? " " : ("0" + hundreds_digit[7:0])) : " ";
    end
endfunction

// 根据有效位和更高位数值决定十位字符是否留空。
function [7:0] tens_ascii_or_blank;
    input       digits_valid;
    input [7:0] hundreds_digit;
    input [7:0] tens_digit;
    begin
        tens_ascii_or_blank =
            digits_valid ? (((hundreds_digit == 8'd0) && (tens_digit == 8'd0)) ? " " : ("0" + tens_digit[7:0])) : " ";
    end
endfunction

// 生成 Active P 文本行中指定字符位置的 ASCII 字符。
function [7:0] active_p_line_ascii;
    input integer char_slot;
    begin
        case (char_slot)
            0:  active_p_line_ascii = "A";
            1:  active_p_line_ascii = "c";
            2:  active_p_line_ascii = "t";
            3:  active_p_line_ascii = "i";
            4:  active_p_line_ascii = "v";
            5:  active_p_line_ascii = "e";
            6:  active_p_line_ascii = " ";
            7:  active_p_line_ascii = "P";
            8:  active_p_line_ascii = ":";
            9:  active_p_line_ascii = " ";
            10: active_p_line_ascii = power_metrics_valid ? (active_p_neg ? "-" : " ") : " ";
            11: active_p_line_ascii = hundreds_ascii_or_blank(power_metrics_valid, active_p_hundreds);
            12: active_p_line_ascii = tens_ascii_or_blank(power_metrics_valid, active_p_hundreds, active_p_tens);
            13: active_p_line_ascii = power_metrics_valid ? digit_to_ascii(active_p_units) : " ";
            14: active_p_line_ascii = ".";
            15: active_p_line_ascii = power_metrics_valid ? digit_to_ascii(active_p_decile) : " ";
            16: active_p_line_ascii = power_metrics_valid ? digit_to_ascii(active_p_percentiles) : " ";
            17: active_p_line_ascii = " ";
            18: active_p_line_ascii = "(";
            19: active_p_line_ascii = "W";
            20: active_p_line_ascii = ")";
            default: active_p_line_ascii = " ";
        endcase
    end
endfunction

// 生成 Reactive Q 文本行中指定字符位置的 ASCII 字符。
function [7:0] reactive_q_line_ascii;
    input integer char_slot;
    begin
        case (char_slot)
            0:  reactive_q_line_ascii = "R";
            1:  reactive_q_line_ascii = "e";
            2:  reactive_q_line_ascii = "a";
            3:  reactive_q_line_ascii = "c";
            4:  reactive_q_line_ascii = "t";
            5:  reactive_q_line_ascii = "i";
            6:  reactive_q_line_ascii = "v";
            7:  reactive_q_line_ascii = "e";
            8:  reactive_q_line_ascii = " ";
            9:  reactive_q_line_ascii = "Q";
            10: reactive_q_line_ascii = ":";
            11: reactive_q_line_ascii = " ";
            12: reactive_q_line_ascii = power_metrics_valid ? (reactive_q_neg ? "-" : "+") : " ";
            13: reactive_q_line_ascii = hundreds_ascii_or_blank(power_metrics_valid, reactive_q_hundreds);
            14: reactive_q_line_ascii = tens_ascii_or_blank(power_metrics_valid, reactive_q_hundreds, reactive_q_tens);
            15: reactive_q_line_ascii = power_metrics_valid ? digit_to_ascii(reactive_q_units) : " ";
            16: reactive_q_line_ascii = ".";
            17: reactive_q_line_ascii = power_metrics_valid ? digit_to_ascii(reactive_q_decile) : " ";
            18: reactive_q_line_ascii = power_metrics_valid ? digit_to_ascii(reactive_q_percentiles) : " ";
            19: reactive_q_line_ascii = " ";
            20: reactive_q_line_ascii = "(";
            21: reactive_q_line_ascii = "v";
            22: reactive_q_line_ascii = "a";
            23: reactive_q_line_ascii = "r";
            24: reactive_q_line_ascii = ")";
            default: reactive_q_line_ascii = " ";
        endcase
    end
endfunction

// 生成 Apparent S 文本行中指定字符位置的 ASCII 字符。
function [7:0] apparent_s_line_ascii;
    input integer char_slot;
    begin
        case (char_slot)
            0:  apparent_s_line_ascii = "A";
            1:  apparent_s_line_ascii = "p";
            2:  apparent_s_line_ascii = "p";
            3:  apparent_s_line_ascii = "a";
            4:  apparent_s_line_ascii = "r";
            5:  apparent_s_line_ascii = "e";
            6:  apparent_s_line_ascii = "n";
            7:  apparent_s_line_ascii = "t";
            8:  apparent_s_line_ascii = " ";
            9:  apparent_s_line_ascii = "S";
            10: apparent_s_line_ascii = ":";
            11: apparent_s_line_ascii = " ";
            12: apparent_s_line_ascii = " ";
            13: apparent_s_line_ascii = hundreds_ascii_or_blank(power_metrics_valid, apparent_s_hundreds);
            14: apparent_s_line_ascii = tens_ascii_or_blank(power_metrics_valid, apparent_s_hundreds, apparent_s_tens);
            15: apparent_s_line_ascii = power_metrics_valid ? digit_to_ascii(apparent_s_units) : " ";
            16: apparent_s_line_ascii = ".";
            17: apparent_s_line_ascii = power_metrics_valid ? digit_to_ascii(apparent_s_decile) : " ";
            18: apparent_s_line_ascii = power_metrics_valid ? digit_to_ascii(apparent_s_percentiles) : " ";
            19: apparent_s_line_ascii = " ";
            20: apparent_s_line_ascii = "(";
            21: apparent_s_line_ascii = "V";
            22: apparent_s_line_ascii = "A";
            23: apparent_s_line_ascii = ")";
            default: apparent_s_line_ascii = " ";
        endcase
    end
endfunction

// 生成功率因数文本行中指定字符位置的 ASCII 字符。
function [7:0] power_factor_line_ascii;
    input integer char_slot;
    begin
        case (char_slot)
            0:  power_factor_line_ascii = "P";
            1:  power_factor_line_ascii = "o";
            2:  power_factor_line_ascii = "w";
            3:  power_factor_line_ascii = "e";
            4:  power_factor_line_ascii = "r";
            5:  power_factor_line_ascii = " ";
            6:  power_factor_line_ascii = "F";
            7:  power_factor_line_ascii = "a";
            8:  power_factor_line_ascii = "c";
            9:  power_factor_line_ascii = "t";
            10: power_factor_line_ascii = "o";
            11: power_factor_line_ascii = "r";
            12: power_factor_line_ascii = ":";
            13: power_factor_line_ascii = " ";
            14: power_factor_line_ascii = power_metrics_valid ? (power_factor_neg ? "-" : " ") : " ";
            15: power_factor_line_ascii = power_metrics_valid ? digit_to_ascii(power_factor_units) : " ";
            16: power_factor_line_ascii = ".";
            17: power_factor_line_ascii = power_metrics_valid ? digit_to_ascii(power_factor_decile) : " ";
            18: power_factor_line_ascii = power_metrics_valid ? digit_to_ascii(power_factor_percentiles) : " ";
            default: power_factor_line_ascii = " ";
        endcase
    end
endfunction

// 生成时域 sharp alarm 文本行中指定字符位置的 ASCII 字符。
function [7:0] sharp_alarm_line_ascii;
    input integer char_slot;
    begin
        case (char_slot)
            0:  sharp_alarm_line_ascii = "E";
            1:  sharp_alarm_line_ascii = "R";
            2:  sharp_alarm_line_ascii = "R";
            3:  sharp_alarm_line_ascii = ":";
            4:  sharp_alarm_line_ascii = " ";
            5:  sharp_alarm_line_ascii = sharp_alarm_is_current ? "I" : "U";
            6:  sharp_alarm_line_ascii = " ";
            7:  sharp_alarm_line_ascii = "S";
            8:  sharp_alarm_line_ascii = "H";
            9:  sharp_alarm_line_ascii = "A";
            10: sharp_alarm_line_ascii = "R";
            11: sharp_alarm_line_ascii = "P";
            12: sharp_alarm_line_ascii = " ";
            13: sharp_alarm_line_ascii = sharp_alarm_is_drop ? "D" : "R";
            14: sharp_alarm_line_ascii = sharp_alarm_is_drop ? "R" : "I";
            15: sharp_alarm_line_ascii = sharp_alarm_is_drop ? "O" : "S";
            16: sharp_alarm_line_ascii = sharp_alarm_is_drop ? "P" : "E";
            default: sharp_alarm_line_ascii = " ";
        endcase
    end
endfunction

// 将 0~9 数字转换成对应的 ASCII 字符。
function [7:0] digit_to_ascii;
    input [7:0] digit;
    begin
        if (digit <= 8'd9)
            digit_to_ascii = "0" + digit[7:0];
        else
            digit_to_ascii = " ";
    end
endfunction

// 计算频域横轴当前窗口下各刻度点对应的谐波次序值。
function [8:0] freq_axis_tick_value;
    input [4:0] page_index;
    input [2:0] tick_index;
    reg   [8:0] page_base;
    begin
        page_base = {page_index, 4'b0000} +
                    {1'b0, page_index, 3'b000} +
                    {4'b0000, page_index};

        case (tick_index)
            3'd0: freq_axis_tick_value = page_base;
            3'd1: freq_axis_tick_value = (page_index == 5'd0) ? 9'd1 : (page_base + 9'd5);
            3'd2: freq_axis_tick_value = (page_index == 5'd0) ? 9'd5 : (page_base + 9'd10);
            3'd3: freq_axis_tick_value = (page_index == 5'd0) ? 9'd10 : (page_base + 9'd15);
            3'd4: freq_axis_tick_value = (page_index == 5'd0) ? 9'd15 : (page_base + 9'd20);
            3'd5: freq_axis_tick_value = (page_index == 5'd0) ? 9'd20 : (page_base + 9'd25);
            3'd6: freq_axis_tick_value = page_base + 9'd25;
            default: freq_axis_tick_value = page_base;
        endcase
    end
endfunction

// 将频域横轴刻度数值转换成左对齐的 ASCII 数字字符。
function [7:0] freq_axis_value_ascii;
    input [8:0] value;
    input integer char_slot;
    reg [8:0] value_work;
    reg [7:0] hundreds_digit;
    reg [7:0] tens_digit;
    reg [7:0] units_digit;
    integer idx;
    begin
        value_work     = value;
        hundreds_digit = 8'd0;
        tens_digit     = 8'd0;
        units_digit    = 8'd0;

        for (idx = 0; idx < 5; idx = idx + 1) begin
            if (value_work >= 9'd100) begin
                value_work     = value_work - 9'd100;
                hundreds_digit = hundreds_digit + 8'd1;
            end
        end

        for (idx = 0; idx < 9; idx = idx + 1) begin
            if (value_work >= 9'd10) begin
                value_work = value_work - 9'd10;
                tens_digit = tens_digit + 8'd1;
            end
        end

        units_digit = {4'd0, value_work[3:0]};

        if (hundreds_digit != 8'd0) begin
            case (char_slot)
                0: freq_axis_value_ascii = digit_to_ascii(hundreds_digit);
                1: freq_axis_value_ascii = digit_to_ascii(tens_digit);
                2: freq_axis_value_ascii = digit_to_ascii(units_digit);
                default: freq_axis_value_ascii = " ";
            endcase
        end else if (tens_digit != 8'd0) begin
            case (char_slot)
                0: freq_axis_value_ascii = digit_to_ascii(tens_digit);
                1: freq_axis_value_ascii = digit_to_ascii(units_digit);
                default: freq_axis_value_ascii = " ";
            endcase
        end else begin
            case (char_slot)
                0: freq_axis_value_ascii = digit_to_ascii(units_digit);
                default: freq_axis_value_ascii = " ";
            endcase
        end
    end
endfunction

// 取出频域横轴某个刻度标签在指定字符槽位上的 ASCII 字符。
function [7:0] freq_axis_tick_ascii;
    input [4:0] page_index;
    input [2:0] tick_index;
    input integer char_slot;
    begin
        freq_axis_tick_ascii =
            freq_axis_value_ascii(freq_axis_tick_value(page_index, tick_index), char_slot);
    end
endfunction

// 根据刻度值大小返回频域横轴标签的字符宽度。
function integer freq_axis_tick_len;
    input [4:0] page_index;
    input [2:0] tick_index;
    reg   [8:0] tick_value;
    begin
        tick_value = freq_axis_tick_value(page_index, tick_index);
        if (tick_value >= 9'd100)
            freq_axis_tick_len = 3;
        else if (tick_value >= 9'd10)
            freq_axis_tick_len = 2;
        else
            freq_axis_tick_len = 1;
    end
endfunction

// 从定长字符串参数中取出指定槽位的字符。
function [7:0] text_char_from_str;
    input [8*MAX_TEXT_LEN-1:0] str_value;
    input integer text_len;
    input integer char_slot;
    begin
        if ((char_slot < 0) || (char_slot >= text_len))
            text_char_from_str = " ";
        else
            text_char_from_str = str_value[((text_len - 1 - char_slot) * 8) +: 8];
    end
endfunction

// 将带符号的三位整数量程刻度拆成逐字符 ASCII 输出。
function [7:0] tick_value_ascii;
    input [7:0] sign_char;
    input [7:0] hundreds_digit;
    input [7:0] tens_digit;
    input [7:0] units_digit;
    input integer char_slot;
    begin
        case (char_slot)
            0: tick_value_ascii = sign_char;
            1: tick_value_ascii = hundreds_ascii_or_blank(1'b1, hundreds_digit);
            2: tick_value_ascii = tens_ascii_or_blank(1'b1, hundreds_digit, tens_digit);
            3: tick_value_ascii = digit_to_ascii(units_digit);
            default: tick_value_ascii = " ";
        endcase
    end
endfunction

// 生成电压纵轴刻度文本在指定字符槽位上的 ASCII 字符。
function [7:0] voltage_tick_ascii;
    input integer tick_index;
    input integer char_slot;
    begin
        case (tick_index)
            0:  voltage_tick_ascii = tick_value_ascii("+", u_tick_full_hundreds, u_tick_full_tens, u_tick_full_units, char_slot);
            1:  voltage_tick_ascii = tick_value_ascii("+", u_tick_two_thirds_hundreds, u_tick_two_thirds_tens, u_tick_two_thirds_units, char_slot);
            2:  voltage_tick_ascii = tick_value_ascii("+", u_tick_one_third_hundreds, u_tick_one_third_tens, u_tick_one_third_units, char_slot);
            3:  voltage_tick_ascii = tick_value_ascii(" ", 8'd0, 8'd0, 8'd0, char_slot);
            4:  voltage_tick_ascii = tick_value_ascii("-", u_tick_one_third_hundreds, u_tick_one_third_tens, u_tick_one_third_units, char_slot);
            5:  voltage_tick_ascii = tick_value_ascii("-", u_tick_two_thirds_hundreds, u_tick_two_thirds_tens, u_tick_two_thirds_units, char_slot);
            6:  voltage_tick_ascii = tick_value_ascii("-", u_tick_full_hundreds, u_tick_full_tens, u_tick_full_units, char_slot);
            default: voltage_tick_ascii = " ";
        endcase
    end
endfunction

// 生成电流纵轴刻度文本在指定字符槽位上的 ASCII 字符。
function [7:0] current_tick_ascii;
    input integer tick_index;
    input integer char_slot;
    begin
        case (tick_index)
            0: current_tick_ascii = tick_value_ascii("+", i_tick_full_hundreds, i_tick_full_tens, i_tick_full_units, char_slot);
            1: current_tick_ascii = tick_value_ascii("+", i_tick_two_thirds_hundreds, i_tick_two_thirds_tens, i_tick_two_thirds_units, char_slot);
            2: current_tick_ascii = tick_value_ascii("+", i_tick_one_third_hundreds, i_tick_one_third_tens, i_tick_one_third_units, char_slot);
            3: current_tick_ascii = tick_value_ascii(" ", 8'd0, 8'd0, 8'd0, char_slot);
            4: current_tick_ascii = tick_value_ascii("-", i_tick_one_third_hundreds, i_tick_one_third_tens, i_tick_one_third_units, char_slot);
            5: current_tick_ascii = tick_value_ascii("-", i_tick_two_thirds_hundreds, i_tick_two_thirds_tens, i_tick_two_thirds_units, char_slot);
            6: current_tick_ascii = tick_value_ascii("-", i_tick_full_hundreds, i_tick_full_tens, i_tick_full_units, char_slot);
            default: current_tick_ascii = " ";
        endcase
    end
endfunction

// 生成时域页频率文本行中指定字符位置的 ASCII 字符。
function [7:0] freq_line_ascii;
    input integer char_slot;
    begin
        case (char_slot)
            0:  freq_line_ascii = "F";
            1:  freq_line_ascii = "r";
            2:  freq_line_ascii = "e";
            3:  freq_line_ascii = "q";
            4:  freq_line_ascii = "u";
            5:  freq_line_ascii = "e";
            6:  freq_line_ascii = "n";
            7:  freq_line_ascii = "c";
            8:  freq_line_ascii = "y";
            9:  freq_line_ascii = ":";
            10: freq_line_ascii = " ";
            11: freq_line_ascii = freq_valid ? ((freq_hundreds == 8'd0) ? " " : digit_to_ascii(freq_hundreds)) : " ";
            12: freq_line_ascii = freq_valid ? digit_to_ascii(freq_tens) : " ";
            13: freq_line_ascii = freq_valid ? digit_to_ascii(freq_units) : " ";
            14: freq_line_ascii = ".";
            15: freq_line_ascii = freq_valid ? digit_to_ascii(freq_decile) : " ";
            16: freq_line_ascii = freq_valid ? digit_to_ascii(freq_percentiles) : " ";
            17: freq_line_ascii = " ";
            18: freq_line_ascii = "(";
            19: freq_line_ascii = "H";
            20: freq_line_ascii = "z";
            21: freq_line_ascii = ")";
            default: freq_line_ascii = " ";
        endcase
    end
endfunction

// 生成频域页 Fundamental 文本行中指定字符位置的 ASCII 字符。
function [7:0] freq_fund_line_ascii;
    input integer char_slot;
    begin
        case (char_slot)
            0:  freq_fund_line_ascii = "F";
            1:  freq_fund_line_ascii = "u";
            2:  freq_fund_line_ascii = "n";
            3:  freq_fund_line_ascii = "d";
            4:  freq_fund_line_ascii = "a";
            5:  freq_fund_line_ascii = "m";
            6:  freq_fund_line_ascii = "e";
            7:  freq_fund_line_ascii = "n";
            8:  freq_fund_line_ascii = "t";
            9:  freq_fund_line_ascii = "a";
            10: freq_fund_line_ascii = "l";
            11: freq_fund_line_ascii = ":";
            12: freq_fund_line_ascii = " ";
            13: freq_fund_line_ascii = freq_valid ? ((freq_hundreds == 8'd0) ? " " : digit_to_ascii(freq_hundreds)) : " ";
            14: freq_fund_line_ascii = freq_valid ? digit_to_ascii(freq_tens) : " ";
            15: freq_fund_line_ascii = freq_valid ? digit_to_ascii(freq_units) : " ";
            16: freq_fund_line_ascii = ".";
            17: freq_fund_line_ascii = freq_valid ? digit_to_ascii(freq_decile) : " ";
            18: freq_fund_line_ascii = freq_valid ? digit_to_ascii(freq_percentiles) : " ";
            19: freq_fund_line_ascii = " ";
            20: freq_fund_line_ascii = "(";
            21: freq_fund_line_ascii = "H";
            22: freq_fund_line_ascii = "z";
            23: freq_fund_line_ascii = ")";
            default: freq_fund_line_ascii = " ";
        endcase
    end
endfunction

// 生成频域页 U1 Magnitude 文本行中指定字符位置的 ASCII 字符。
function [7:0] freq_u1_line_ascii;
    input integer char_slot;
    begin
        case (char_slot)
            0:  freq_u1_line_ascii = "U";
            1:  freq_u1_line_ascii = "1";
            2:  freq_u1_line_ascii = " ";
            3:  freq_u1_line_ascii = "M";
            4:  freq_u1_line_ascii = "a";
            5:  freq_u1_line_ascii = "g";
            6:  freq_u1_line_ascii = ":";
            7:  freq_u1_line_ascii = " ";
            8:  freq_u1_line_ascii = freq_u1_mag_valid ? ((freq_u1_mag_hundreds == 8'd0) ? " " : digit_to_ascii(freq_u1_mag_hundreds)) : " ";
            9:  freq_u1_line_ascii = freq_u1_mag_valid ? (((freq_u1_mag_hundreds == 8'd0) && (freq_u1_mag_tens == 8'd0)) ? " " : digit_to_ascii(freq_u1_mag_tens)) : " ";
            10: freq_u1_line_ascii = freq_u1_mag_valid ? digit_to_ascii(freq_u1_mag_units) : " ";
            11: freq_u1_line_ascii = ".";
            12: freq_u1_line_ascii = freq_u1_mag_valid ? digit_to_ascii(freq_u1_mag_decile) : " ";
            13: freq_u1_line_ascii = freq_u1_mag_valid ? digit_to_ascii(freq_u1_mag_percentiles) : " ";
            14: freq_u1_line_ascii = " ";
            15: freq_u1_line_ascii = "(";
            16: freq_u1_line_ascii = "%";
            17: freq_u1_line_ascii = ")";
            default: freq_u1_line_ascii = " ";
        endcase
    end
endfunction

// 生成频域页 I1 Magnitude 文本行中指定字符位置的 ASCII 字符。
function [7:0] freq_i1_line_ascii;
    input integer char_slot;
    begin
        case (char_slot)
            0:  freq_i1_line_ascii = "I";
            1:  freq_i1_line_ascii = "1";
            2:  freq_i1_line_ascii = " ";
            3:  freq_i1_line_ascii = "M";
            4:  freq_i1_line_ascii = "a";
            5:  freq_i1_line_ascii = "g";
            6:  freq_i1_line_ascii = ":";
            7:  freq_i1_line_ascii = " ";
            8:  freq_i1_line_ascii = freq_i1_mag_valid ? ((freq_i1_mag_hundreds == 8'd0) ? " " : digit_to_ascii(freq_i1_mag_hundreds)) : " ";
            9:  freq_i1_line_ascii = freq_i1_mag_valid ? (((freq_i1_mag_hundreds == 8'd0) && (freq_i1_mag_tens == 8'd0)) ? " " : digit_to_ascii(freq_i1_mag_tens)) : " ";
            10: freq_i1_line_ascii = freq_i1_mag_valid ? digit_to_ascii(freq_i1_mag_units) : " ";
            11: freq_i1_line_ascii = ".";
            12: freq_i1_line_ascii = freq_i1_mag_valid ? digit_to_ascii(freq_i1_mag_decile) : " ";
            13: freq_i1_line_ascii = freq_i1_mag_valid ? digit_to_ascii(freq_i1_mag_percentiles) : " ";
            14: freq_i1_line_ascii = " ";
            15: freq_i1_line_ascii = "(";
            16: freq_i1_line_ascii = "%";
            17: freq_i1_line_ascii = ")";
            default: freq_i1_line_ascii = " ";
        endcase
    end
endfunction

// 生成频域页电压 THD 文本行中指定字符位置的 ASCII 字符。
function [7:0] freq_thd_u_line_ascii;
    input integer char_slot;
    begin
        case (char_slot)
            0:  freq_thd_u_line_ascii = "T";
            1:  freq_thd_u_line_ascii = "H";
            2:  freq_thd_u_line_ascii = "D";
            3:  freq_thd_u_line_ascii = "-";
            4:  freq_thd_u_line_ascii = "U";
            5:  freq_thd_u_line_ascii = ":";
            6:  freq_thd_u_line_ascii = " ";
            7:  freq_thd_u_line_ascii = freq_thd_u_valid ? ((freq_thd_u_hundreds == 8'd0) ? " " : digit_to_ascii(freq_thd_u_hundreds)) : " ";
            8:  freq_thd_u_line_ascii = freq_thd_u_valid ? (((freq_thd_u_hundreds == 8'd0) && (freq_thd_u_tens == 8'd0)) ? " " : digit_to_ascii(freq_thd_u_tens)) : " ";
            9:  freq_thd_u_line_ascii = freq_thd_u_valid ? digit_to_ascii(freq_thd_u_units) : " ";
            10: freq_thd_u_line_ascii = ".";
            11: freq_thd_u_line_ascii = freq_thd_u_valid ? digit_to_ascii(freq_thd_u_decile) : " ";
            12: freq_thd_u_line_ascii = freq_thd_u_valid ? digit_to_ascii(freq_thd_u_percentiles) : " ";
            13: freq_thd_u_line_ascii = " ";
            14: freq_thd_u_line_ascii = "(";
            15: freq_thd_u_line_ascii = "%";
            16: freq_thd_u_line_ascii = ")";
            default: freq_thd_u_line_ascii = " ";
        endcase
    end
endfunction

// 生成频域页电流 THD 文本行中指定字符位置的 ASCII 字符。
function [7:0] freq_thd_i_line_ascii;
    input integer char_slot;
    begin
        case (char_slot)
            0:  freq_thd_i_line_ascii = "T";
            1:  freq_thd_i_line_ascii = "H";
            2:  freq_thd_i_line_ascii = "D";
            3:  freq_thd_i_line_ascii = "-";
            4:  freq_thd_i_line_ascii = "I";
            5:  freq_thd_i_line_ascii = ":";
            6:  freq_thd_i_line_ascii = " ";
            7:  freq_thd_i_line_ascii = freq_thd_i_valid ? ((freq_thd_i_hundreds == 8'd0) ? " " : digit_to_ascii(freq_thd_i_hundreds)) : " ";
            8:  freq_thd_i_line_ascii = freq_thd_i_valid ? (((freq_thd_i_hundreds == 8'd0) && (freq_thd_i_tens == 8'd0)) ? " " : digit_to_ascii(freq_thd_i_tens)) : " ";
            9:  freq_thd_i_line_ascii = freq_thd_i_valid ? digit_to_ascii(freq_thd_i_units) : " ";
            10: freq_thd_i_line_ascii = ".";
            11: freq_thd_i_line_ascii = freq_thd_i_valid ? digit_to_ascii(freq_thd_i_decile) : " ";
            12: freq_thd_i_line_ascii = freq_thd_i_valid ? digit_to_ascii(freq_thd_i_percentiles) : " ";
            13: freq_thd_i_line_ascii = " ";
            14: freq_thd_i_line_ascii = "(";
            15: freq_thd_i_line_ascii = "%";
            16: freq_thd_i_line_ascii = ")";
            default: freq_thd_i_line_ascii = " ";
        endcase
    end
endfunction

// 生成频域页基波相位差文本行中指定字符位置的 ASCII 字符。
function [7:0] freq_phase1_line_ascii;
    input integer char_slot;
    begin
        case (char_slot)
            0:  freq_phase1_line_ascii = "P";
            1:  freq_phase1_line_ascii = "h";
            2:  freq_phase1_line_ascii = "a";
            3:  freq_phase1_line_ascii = "s";
            4:  freq_phase1_line_ascii = "e";
            5:  freq_phase1_line_ascii = "1";
            6:  freq_phase1_line_ascii = ":";
            7:  freq_phase1_line_ascii = " ";
            8:  freq_phase1_line_ascii = freq_phase1_valid ? (freq_phase1_neg ? "-" : "+") : " ";
            9:  freq_phase1_line_ascii = freq_phase1_valid ? ((freq_phase1_hundreds == 8'd0) ? " " : digit_to_ascii(freq_phase1_hundreds)) : " ";
            10: freq_phase1_line_ascii = freq_phase1_valid ? (((freq_phase1_hundreds == 8'd0) && (freq_phase1_tens == 8'd0)) ? " " : digit_to_ascii(freq_phase1_tens)) : " ";
            11: freq_phase1_line_ascii = freq_phase1_valid ? digit_to_ascii(freq_phase1_units) : " ";
            12: freq_phase1_line_ascii = ".";
            13: freq_phase1_line_ascii = freq_phase1_valid ? digit_to_ascii(freq_phase1_decile) : " ";
            14: freq_phase1_line_ascii = freq_phase1_valid ? digit_to_ascii(freq_phase1_percentiles) : " ";
            15: freq_phase1_line_ascii = " ";
            16: freq_phase1_line_ascii = "(";
            17: freq_phase1_line_ascii = "d";
            18: freq_phase1_line_ascii = "e";
            19: freq_phase1_line_ascii = "g";
            20: freq_phase1_line_ascii = ")";
            default: freq_phase1_line_ascii = " ";
        endcase
    end
endfunction

// 生成频域页电压直流分量文本行中指定字符位置的 ASCII 字符。
function [7:0] freq_dc_u_line_ascii;
    input integer char_slot;
    begin
        case (char_slot)
            0:  freq_dc_u_line_ascii = "D";
            1:  freq_dc_u_line_ascii = "C";
            2:  freq_dc_u_line_ascii = "-";
            3:  freq_dc_u_line_ascii = "U";
            4:  freq_dc_u_line_ascii = ":";
            5:  freq_dc_u_line_ascii = " ";
            6:  freq_dc_u_line_ascii = freq_dc_u_valid ? ((freq_dc_u_hundreds == 8'd0) ? " " : digit_to_ascii(freq_dc_u_hundreds)) : " ";
            7:  freq_dc_u_line_ascii = freq_dc_u_valid ? (((freq_dc_u_hundreds == 8'd0) && (freq_dc_u_tens == 8'd0)) ? " " : digit_to_ascii(freq_dc_u_tens)) : " ";
            8:  freq_dc_u_line_ascii = freq_dc_u_valid ? digit_to_ascii(freq_dc_u_units) : " ";
            9:  freq_dc_u_line_ascii = ".";
            10: freq_dc_u_line_ascii = freq_dc_u_valid ? digit_to_ascii(freq_dc_u_decile) : " ";
            11: freq_dc_u_line_ascii = freq_dc_u_valid ? digit_to_ascii(freq_dc_u_percentiles) : " ";
            12: freq_dc_u_line_ascii = " ";
            13: freq_dc_u_line_ascii = "(";
            14: freq_dc_u_line_ascii = "%";
            15: freq_dc_u_line_ascii = ")";
            default: freq_dc_u_line_ascii = " ";
        endcase
    end
endfunction

// 生成频域页电流直流分量文本行中指定字符位置的 ASCII 字符。
function [7:0] freq_dc_i_line_ascii;
    input integer char_slot;
    begin
        case (char_slot)
            0:  freq_dc_i_line_ascii = "D";
            1:  freq_dc_i_line_ascii = "C";
            2:  freq_dc_i_line_ascii = "-";
            3:  freq_dc_i_line_ascii = "I";
            4:  freq_dc_i_line_ascii = ":";
            5:  freq_dc_i_line_ascii = " ";
            6:  freq_dc_i_line_ascii = freq_dc_i_valid ? ((freq_dc_i_hundreds == 8'd0) ? " " : digit_to_ascii(freq_dc_i_hundreds)) : " ";
            7:  freq_dc_i_line_ascii = freq_dc_i_valid ? (((freq_dc_i_hundreds == 8'd0) && (freq_dc_i_tens == 8'd0)) ? " " : digit_to_ascii(freq_dc_i_tens)) : " ";
            8:  freq_dc_i_line_ascii = freq_dc_i_valid ? digit_to_ascii(freq_dc_i_units) : " ";
            9:  freq_dc_i_line_ascii = ".";
            10: freq_dc_i_line_ascii = freq_dc_i_valid ? digit_to_ascii(freq_dc_i_decile) : " ";
            11: freq_dc_i_line_ascii = freq_dc_i_valid ? digit_to_ascii(freq_dc_i_percentiles) : " ";
            12: freq_dc_i_line_ascii = " ";
            13: freq_dc_i_line_ascii = "(";
            14: freq_dc_i_line_ascii = "%";
            15: freq_dc_i_line_ascii = ")";
            default: freq_dc_i_line_ascii = " ";
        endcase
    end
endfunction

// 从 25 字符打包文本总线中按槽位取出单个 ASCII 字符。
function [7:0] packed_text_char;
    input [199:0] packed_text;
    input integer char_slot;
    begin
        if ((char_slot < 0) || (char_slot >= MAX_TEXT_LEN))
            packed_text_char = " ";
        else
            packed_text_char = packed_text[(MAX_TEXT_LEN - char_slot) * 8 - 1 -: 8];
    end
endfunction

// 生成频域页电压主导谐波次序文本行中指定字符位置的 ASCII 字符。
function [7:0] freq_dh_u_line_ascii;
    input integer char_slot;
    begin
        freq_dh_u_line_ascii = packed_text_char(freq_dh_order_u_text, char_slot);
    end
endfunction

// 生成频域页电流主导谐波次序文本行中指定字符位置的 ASCII 字符。
function [7:0] freq_dh_i_line_ascii;
    input integer char_slot;
    begin
        freq_dh_i_line_ascii = packed_text_char(freq_dh_order_i_text, char_slot);
    end
endfunction

// 生成时域页电压 RMS 文本行中指定字符位置的 ASCII 字符。
function [7:0] u_rms_line_ascii;
    input integer char_slot;
    begin
        case (char_slot)
            0:  u_rms_line_ascii = "U";
            1:  u_rms_line_ascii = "_";
            2:  u_rms_line_ascii = "r";
            3:  u_rms_line_ascii = "m";
            4:  u_rms_line_ascii = "s";
            5:  u_rms_line_ascii = ":";
            6:  u_rms_line_ascii = " ";
            7:  u_rms_line_ascii = hundreds_ascii_or_blank(u_rms_digits_valid, u_rms_hundreds);
            8:  u_rms_line_ascii = tens_ascii_or_blank(u_rms_digits_valid, u_rms_hundreds, u_rms_tens);
            9:  u_rms_line_ascii = u_rms_digits_valid ? digit_to_ascii(u_rms_units) : " ";
            10: u_rms_line_ascii = ".";
            11: u_rms_line_ascii = u_rms_digits_valid ? digit_to_ascii(u_rms_decile) : " ";
            12: u_rms_line_ascii = u_rms_digits_valid ? digit_to_ascii(u_rms_percentiles) : " ";
            13: u_rms_line_ascii = " ";
            14: u_rms_line_ascii = "(";
            15: u_rms_line_ascii = "V";
            16: u_rms_line_ascii = ")";
            default: u_rms_line_ascii = " ";
        endcase
    end
endfunction

// 生成时域页电流 RMS 文本行中指定字符位置的 ASCII 字符。
function [7:0] i_rms_line_ascii;
    input integer char_slot;
    begin
        case (char_slot)
            0:  i_rms_line_ascii = "I";
            1:  i_rms_line_ascii = "_";
            2:  i_rms_line_ascii = "r";
            3:  i_rms_line_ascii = "m";
            4:  i_rms_line_ascii = "s";
            5:  i_rms_line_ascii = ":";
            6:  i_rms_line_ascii = " ";
            7:  i_rms_line_ascii = hundreds_ascii_or_blank(i_rms_digits_valid, i_rms_hundreds);
            8:  i_rms_line_ascii = tens_ascii_or_blank(i_rms_digits_valid, i_rms_hundreds, i_rms_tens);
            9:  i_rms_line_ascii = i_rms_digits_valid ? digit_to_ascii(i_rms_units) : " ";
            10: i_rms_line_ascii = ".";
            11: i_rms_line_ascii = i_rms_digits_valid ? digit_to_ascii(i_rms_decile) : " ";
            12: i_rms_line_ascii = i_rms_digits_valid ? digit_to_ascii(i_rms_percentiles) : " ";
            13: i_rms_line_ascii = " ";
            14: i_rms_line_ascii = "(";
            15: i_rms_line_ascii = "A";
            16: i_rms_line_ascii = ")";
            default: i_rms_line_ascii = " ";
        endcase
    end
endfunction

// 生成时域页功率角文本行中指定字符位置的 ASCII 字符。
function [7:0] phase_line_ascii;
    input integer char_slot;
    begin
        case (char_slot)
            0:  phase_line_ascii = "P";
            1:  phase_line_ascii = "o";
            2:  phase_line_ascii = "w";
            3:  phase_line_ascii = "e";
            4:  phase_line_ascii = "r";
            5:  phase_line_ascii = " ";
            6:  phase_line_ascii = "A";
            7:  phase_line_ascii = "n";
            8:  phase_line_ascii = "g";
            9:  phase_line_ascii = ":";
            10: phase_line_ascii = " ";
            11: phase_line_ascii = phase_valid ? (phase_neg ? "-" : "+") : " ";
            12: phase_line_ascii = phase_valid ? ((phase_hundreds == 8'd0) ? " " : digit_to_ascii(phase_hundreds)) : " ";
            13: phase_line_ascii = phase_valid ? (((phase_hundreds == 8'd0) && (phase_tens == 8'd0)) ? " " : digit_to_ascii(phase_tens)) : " ";
            14: phase_line_ascii = phase_valid ? digit_to_ascii(phase_units) : " ";
            15: phase_line_ascii = ".";
            16: phase_line_ascii = phase_valid ? digit_to_ascii(phase_decile) : " ";
            17: phase_line_ascii = phase_valid ? digit_to_ascii(phase_percentiles) : " ";
            18: phase_line_ascii = " ";
            19: phase_line_ascii = "(";
            20: phase_line_ascii = "d";
            21: phase_line_ascii = "e";
            22: phase_line_ascii = "g";
            23: phase_line_ascii = ")";
            default: phase_line_ascii = " ";
        endcase
    end
endfunction

// 生成时域页电压峰峰值文本行中指定字符位置的 ASCII 字符。
function [7:0] u_pp_line_ascii;
    input integer char_slot;
    begin
        case (char_slot)
            0:  u_pp_line_ascii = "U";
            1:  u_pp_line_ascii = "p";
            2:  u_pp_line_ascii = "p";
            3:  u_pp_line_ascii = ":";
            4:  u_pp_line_ascii = " ";
            5:  u_pp_line_ascii = hundreds_ascii_or_blank(u_pp_digits_valid, u_pp_hundreds);
            6:  u_pp_line_ascii = tens_ascii_or_blank(u_pp_digits_valid, u_pp_hundreds, u_pp_tens);
            7:  u_pp_line_ascii = u_pp_digits_valid ? digit_to_ascii(u_pp_units) : " ";
            8:  u_pp_line_ascii = ".";
            9:  u_pp_line_ascii = u_pp_digits_valid ? digit_to_ascii(u_pp_decile) : " ";
            10: u_pp_line_ascii = u_pp_digits_valid ? digit_to_ascii(u_pp_percentiles) : " ";
            11: u_pp_line_ascii = " ";
            12: u_pp_line_ascii = "(";
            13: u_pp_line_ascii = "V";
            14: u_pp_line_ascii = ")";
            default: u_pp_line_ascii = " ";
        endcase
    end
endfunction

// 生成时域页电流峰峰值文本行中指定字符位置的 ASCII 字符。
function [7:0] i_pp_line_ascii;
    input integer char_slot;
    begin
        case (char_slot)
            0:  i_pp_line_ascii = "I";
            1:  i_pp_line_ascii = "p";
            2:  i_pp_line_ascii = "p";
            3:  i_pp_line_ascii = ":";
            4:  i_pp_line_ascii = " ";
            5:  i_pp_line_ascii = hundreds_ascii_or_blank(i_pp_digits_valid, i_pp_hundreds);
            6:  i_pp_line_ascii = tens_ascii_or_blank(i_pp_digits_valid, i_pp_hundreds, i_pp_tens);
            7:  i_pp_line_ascii = i_pp_digits_valid ? digit_to_ascii(i_pp_units) : " ";
            8:  i_pp_line_ascii = ".";
            9:  i_pp_line_ascii = i_pp_digits_valid ? digit_to_ascii(i_pp_decile) : " ";
            10: i_pp_line_ascii = i_pp_digits_valid ? digit_to_ascii(i_pp_percentiles) : " ";
            11: i_pp_line_ascii = " ";
            12: i_pp_line_ascii = "(";
            13: i_pp_line_ascii = "A";
            14: i_pp_line_ascii = ")";
            default: i_pp_line_ascii = " ";
        endcase
    end
endfunction

// 根据小字体区域内的 X 偏移返回当前命中的字符槽位。
function integer small_text_slot;
    input [10:0] delta_x;
    input integer text_len;
    integer idx;
    begin
        small_text_slot = 0;
        for (idx = 0; idx < MAX_TEXT_LEN; idx = idx + 1) begin
            if ((idx < text_len) &&
                (delta_x >= (idx * SMALL_CHAR_W)) &&
                (delta_x < ((idx + 1) * SMALL_CHAR_W)))
                small_text_slot = idx;
        end
    end
endfunction

// 根据小字体区域内的 X 偏移返回字模内部的列坐标。
function [5:0] small_text_rel_x;
    input [10:0] delta_x;
    integer idx;
    begin
        small_text_rel_x = 6'd0;
        for (idx = 0; idx < MAX_TEXT_LEN; idx = idx + 1) begin
            if ((delta_x >= (idx * SMALL_CHAR_W)) &&
                (delta_x < ((idx + 1) * SMALL_CHAR_W)))
                small_text_rel_x = delta_x - (idx * SMALL_CHAR_W);
        end
    end
endfunction

// 判断当前像素是否落在任一电压纵轴刻度标签的高度范围内。
function voltage_tick_hit;
    input [10:0] delta_y;
    integer idx;
    begin
        voltage_tick_hit = 1'b0;
        for (idx = 0; idx < 7; idx = idx + 1) begin
            if ((delta_y >= (idx * V_TICK_STEP)) &&
                (delta_y < ((idx * V_TICK_STEP) + SMALL_CHAR_H)))
                voltage_tick_hit = 1'b1;
        end
    end
endfunction

// 根据 Y 偏移确定当前命中的电压纵轴刻度序号。
function integer voltage_tick_slot_from_y;
    input [10:0] delta_y;
    integer idx;
    begin
        voltage_tick_slot_from_y = 0;
        for (idx = 0; idx < 7; idx = idx + 1) begin
            if ((delta_y >= (idx * V_TICK_STEP)) &&
                (delta_y < ((idx * V_TICK_STEP) + SMALL_CHAR_H)))
                voltage_tick_slot_from_y = idx;
        end
    end
endfunction

// 计算当前像素在电压纵轴刻度字符内的 Y 偏移。
function [5:0] voltage_tick_rel_y;
    input [10:0] delta_y;
    integer idx;
    begin
        voltage_tick_rel_y = 6'd0;
        for (idx = 0; idx < 7; idx = idx + 1) begin
            if ((delta_y >= (idx * V_TICK_STEP)) &&
                (delta_y < ((idx * V_TICK_STEP) + SMALL_CHAR_H)))
                voltage_tick_rel_y = delta_y - (idx * V_TICK_STEP);
        end
    end
endfunction

// 判断当前像素是否落在任一电流纵轴刻度标签的高度范围内。
function current_tick_hit;
    input [10:0] delta_y;
    integer idx;
    begin
        current_tick_hit = 1'b0;
        for (idx = 0; idx < 7; idx = idx + 1) begin
            if ((delta_y >= (idx * I_TICK_STEP)) &&
                (delta_y < ((idx * I_TICK_STEP) + SMALL_CHAR_H)))
                current_tick_hit = 1'b1;
        end
    end
endfunction

// 根据 Y 偏移确定当前命中的电流纵轴刻度序号。
function integer current_tick_slot_from_y;
    input [10:0] delta_y;
    integer idx;
    begin
        current_tick_slot_from_y = 0;
        for (idx = 0; idx < 7; idx = idx + 1) begin
            if ((delta_y >= (idx * I_TICK_STEP)) &&
                (delta_y < ((idx * I_TICK_STEP) + SMALL_CHAR_H)))
                current_tick_slot_from_y = idx;
        end
    end
endfunction

// 计算当前像素在电流纵轴刻度字符内的 Y 偏移。
function [5:0] current_tick_rel_y;
    input [10:0] delta_y;
    integer idx;
    begin
        current_tick_rel_y = 6'd0;
        for (idx = 0; idx < 7; idx = idx + 1) begin
            if ((delta_y >= (idx * I_TICK_STEP)) &&
                (delta_y < ((idx * I_TICK_STEP) + SMALL_CHAR_H)))
                current_tick_rel_y = delta_y - (idx * I_TICK_STEP);
        end
    end
endfunction

// 在指定矩形区域内渲染一行 16x32 大字体静态文本。
task try_big_text_region;
    input [10:0] base_x;
    input [10:0] base_y;
    input integer text_len;
    input [23:0] color_value;
    input [8*MAX_TEXT_LEN-1:0] text_value;
    reg   [10:0] delta_x;
    begin
        if (!text_en &&
            (pixel_xpos >= base_x) && (pixel_xpos < base_x + (text_len * BIG_CHAR_W)) &&
            (pixel_ypos >= base_y) && (pixel_ypos < base_y + BIG_CHAR_H)) begin
            delta_x         = pixel_xpos - base_x;
            line_slot       = delta_x[10:4];
            text_en         = 1'b1;
            text_font_small = 1'b0;
            text_char_idx   = ascii_to_idx(text_char_from_str(text_value, text_len, line_slot));
            text_color      = color_value;
            text_rel_x      = {2'b00, delta_x[3:0]};
            text_rel_y      = pixel_ypos - base_y;
        end
    end
endtask

// 在指定矩形区域内渲染一行 10x20 小字体静态文本。
task try_small_text_region;
    input [10:0] base_x;
    input [10:0] base_y;
    input integer text_len;
    input [23:0] color_value;
    input [8*MAX_TEXT_LEN-1:0] text_value;
    reg   [10:0] delta_x;
    begin
        if (!text_en &&
            (pixel_xpos >= base_x) && (pixel_xpos < base_x + (text_len * SMALL_CHAR_W)) &&
            (pixel_ypos >= base_y) && (pixel_ypos < base_y + SMALL_CHAR_H)) begin
            delta_x         = pixel_xpos - base_x;
            line_slot       = small_text_slot(delta_x, text_len);
            text_en         = 1'b1;
            text_font_small = 1'b1;
            text_char_idx   = ascii_to_idx(text_char_from_str(text_value, text_len, line_slot));
            text_color      = color_value;
            text_rel_x      = small_text_rel_x(delta_x);
            text_rel_y      = pixel_ypos - base_y;
        end
    end
endtask

// 在电压纵轴刻度区域内按像素位置渲染对应的刻度文本。
task try_voltage_tick_region;
    input [10:0] base_x;
    input [10:0] base_y;
    reg   [10:0] delta_x;
    reg   [10:0] delta_y;
    begin
        if (!text_en &&
            (pixel_xpos >= base_x) && (pixel_xpos < base_x + (V_TICK_LEN * SMALL_CHAR_W)) &&
            (pixel_ypos >= base_y) &&
            (pixel_ypos < base_y + (6 * V_TICK_STEP) + SMALL_CHAR_H)) begin
            delta_x = pixel_xpos - base_x;
            delta_y = pixel_ypos - base_y;

            if (voltage_tick_hit(delta_y)) begin
                tick_slot       = voltage_tick_slot_from_y(delta_y);
                line_slot       = small_text_slot(delta_x, V_TICK_LEN);
                text_en         = 1'b1;
                text_font_small = 1'b1;
                text_char_idx   = ascii_to_idx(voltage_tick_ascii(tick_slot, line_slot));
                text_color      = WAVE_U_COLOR;
                text_rel_x      = small_text_rel_x(delta_x);
                text_rel_y      = voltage_tick_rel_y(delta_y);
            end
        end
    end
endtask

// 在电流纵轴刻度区域内按像素位置渲染对应的刻度文本。
task try_current_tick_region;
    input [10:0] base_x;
    input [10:0] base_y;
    reg   [10:0] delta_x;
    reg   [10:0] delta_y;
    begin
        if (!text_en &&
            (pixel_xpos >= base_x) && (pixel_xpos < base_x + (I_TICK_LEN * SMALL_CHAR_W)) &&
            (pixel_ypos >= base_y) &&
            (pixel_ypos < base_y + (6 * I_TICK_STEP) + SMALL_CHAR_H)) begin
            delta_x = pixel_xpos - base_x;
            delta_y = pixel_ypos - base_y;

            if (current_tick_hit(delta_y)) begin
                tick_slot       = current_tick_slot_from_y(delta_y);
                line_slot       = small_text_slot(delta_x, I_TICK_LEN);
                text_en         = 1'b1;
                text_font_small = 1'b1;
                text_char_idx   = ascii_to_idx(current_tick_ascii(tick_slot, line_slot));
                text_color      = WAVE_I_COLOR;
                text_rel_x      = small_text_rel_x(delta_x);
                text_rel_y      = current_tick_rel_y(delta_y);
            end
        end
    end
endtask

// 在时域页参数区渲染频率文本行。
task try_freq_line_region;
    input [10:0] base_x;
    input [10:0] base_y;
    reg   [10:0] delta_x;
    begin
        if (!text_en &&
            (pixel_xpos >= base_x) && (pixel_xpos < base_x + (FREQ_LEN * SMALL_CHAR_W)) &&
            (pixel_ypos >= base_y) && (pixel_ypos < base_y + SMALL_CHAR_H)) begin
            delta_x         = pixel_xpos - base_x;
            line_slot       = small_text_slot(delta_x, FREQ_LEN);
            text_en         = 1'b1;
            text_font_small = 1'b1;
            text_char_idx   = ascii_to_idx(freq_line_ascii(line_slot));
            text_color      = TEXT_SOFT;
            text_rel_x      = small_text_rel_x(delta_x);
            text_rel_y      = pixel_ypos - base_y;
        end
    end
endtask

// 在时域页参数区渲染电压 RMS 文本行。
task try_u_rms_line_region;
    input [10:0] base_x;
    input [10:0] base_y;
    reg   [10:0] delta_x;
    begin
        if (!text_en &&
            (pixel_xpos >= base_x) && (pixel_xpos < base_x + (RMS_LEN * SMALL_CHAR_W)) &&
            (pixel_ypos >= base_y) && (pixel_ypos < base_y + SMALL_CHAR_H)) begin
            delta_x         = pixel_xpos - base_x;
            line_slot       = small_text_slot(delta_x, RMS_LEN);
            text_en         = 1'b1;
            text_font_small = 1'b1;
            text_char_idx   = ascii_to_idx(u_rms_line_ascii(line_slot));
            text_color      = WAVE_U_COLOR;
            text_rel_x      = small_text_rel_x(delta_x);
            text_rel_y      = pixel_ypos - base_y;
        end
    end
endtask

// 在时域页参数区渲染电流 RMS 文本行。
task try_i_rms_line_region;
    input [10:0] base_x;
    input [10:0] base_y;
    reg   [10:0] delta_x;
    begin
        if (!text_en &&
            (pixel_xpos >= base_x) && (pixel_xpos < base_x + (RMS_LEN * SMALL_CHAR_W)) &&
            (pixel_ypos >= base_y) && (pixel_ypos < base_y + SMALL_CHAR_H)) begin
            delta_x         = pixel_xpos - base_x;
            line_slot       = small_text_slot(delta_x, RMS_LEN);
            text_en         = 1'b1;
            text_font_small = 1'b1;
            text_char_idx   = ascii_to_idx(i_rms_line_ascii(line_slot));
            text_color      = WAVE_I_COLOR;
            text_rel_x      = small_text_rel_x(delta_x);
            text_rel_y      = pixel_ypos - base_y;
        end
    end
endtask

// 在时域页参数区渲染功率角文本行。
task try_phase_line_region;
    input [10:0] base_x;
    input [10:0] base_y;
    reg   [10:0] delta_x;
    begin
        if (!text_en &&
            (pixel_xpos >= base_x) && (pixel_xpos < base_x + (PHASE_LEN * SMALL_CHAR_W)) &&
            (pixel_ypos >= base_y) && (pixel_ypos < base_y + SMALL_CHAR_H)) begin
            delta_x         = pixel_xpos - base_x;
            line_slot       = small_text_slot(delta_x, PHASE_LEN);
            text_en         = 1'b1;
            text_font_small = 1'b1;
            text_char_idx   = ascii_to_idx(phase_line_ascii(line_slot));
            text_color      = TEXT_WHITE;
            text_rel_x      = small_text_rel_x(delta_x);
            text_rel_y      = pixel_ypos - base_y;
        end
    end
endtask

// 在时域页底部渲染电压峰峰值文本行。
task try_u_pp_line_region;
    input [10:0] base_x;
    input [10:0] base_y;
    reg   [10:0] delta_x;
    begin
        if (!text_en &&
            (pixel_xpos >= base_x) && (pixel_xpos < base_x + (PP_LEN * SMALL_CHAR_W)) &&
            (pixel_ypos >= base_y) && (pixel_ypos < base_y + SMALL_CHAR_H)) begin
            delta_x         = pixel_xpos - base_x;
            line_slot       = small_text_slot(delta_x, PP_LEN);
            text_en         = 1'b1;
            text_font_small = 1'b1;
            text_char_idx   = ascii_to_idx(u_pp_line_ascii(line_slot));
            text_color      = WAVE_U_COLOR;
            text_rel_x      = small_text_rel_x(delta_x);
            text_rel_y      = pixel_ypos - base_y;
        end
    end
endtask

// 在时域页底部渲染电流峰峰值文本行。
task try_i_pp_line_region;
    input [10:0] base_x;
    input [10:0] base_y;
    reg   [10:0] delta_x;
    begin
        if (!text_en &&
            (pixel_xpos >= base_x) && (pixel_xpos < base_x + (PP_LEN * SMALL_CHAR_W)) &&
            (pixel_ypos >= base_y) && (pixel_ypos < base_y + SMALL_CHAR_H)) begin
            delta_x         = pixel_xpos - base_x;
            line_slot       = small_text_slot(delta_x, PP_LEN);
            text_en         = 1'b1;
            text_font_small = 1'b1;
            text_char_idx   = ascii_to_idx(i_pp_line_ascii(line_slot));
            text_color      = WAVE_I_COLOR;
            text_rel_x      = small_text_rel_x(delta_x);
            text_rel_y      = pixel_ypos - base_y;
        end
    end
endtask

// 在时域页参数区渲染有功功率文本行。
task try_active_p_line_region;
    input [10:0] base_x;
    input [10:0] base_y;
    reg   [10:0] delta_x;
    begin
        if (!text_en &&
            (pixel_xpos >= base_x) && (pixel_xpos < base_x + (ACTIVE_LEN * SMALL_CHAR_W)) &&
            (pixel_ypos >= base_y) && (pixel_ypos < base_y + SMALL_CHAR_H)) begin
            delta_x         = pixel_xpos - base_x;
            line_slot       = small_text_slot(delta_x, ACTIVE_LEN);
            text_en         = 1'b1;
            text_font_small = 1'b1;
            text_char_idx   = ascii_to_idx(active_p_line_ascii(line_slot));
            text_color      = ACCENT_COLOR;
            text_rel_x      = small_text_rel_x(delta_x);
            text_rel_y      = pixel_ypos - base_y;
        end
    end
endtask

// 在时域页参数区渲染无功功率文本行。
task try_reactive_q_line_region;
    input [10:0] base_x;
    input [10:0] base_y;
    reg   [10:0] delta_x;
    begin
        if (!text_en &&
            (pixel_xpos >= base_x) && (pixel_xpos < base_x + (REACTIVE_LEN * SMALL_CHAR_W)) &&
            (pixel_ypos >= base_y) && (pixel_ypos < base_y + SMALL_CHAR_H)) begin
            delta_x         = pixel_xpos - base_x;
            line_slot       = small_text_slot(delta_x, REACTIVE_LEN);
            text_en         = 1'b1;
            text_font_small = 1'b1;
            text_char_idx   = ascii_to_idx(reactive_q_line_ascii(line_slot));
            text_color      = TEXT_SOFT;
            text_rel_x      = small_text_rel_x(delta_x);
            text_rel_y      = pixel_ypos - base_y;
        end
    end
endtask

// 在时域页参数区渲染视在功率文本行。
task try_apparent_s_line_region;
    input [10:0] base_x;
    input [10:0] base_y;
    reg   [10:0] delta_x;
    begin
        if (!text_en &&
            (pixel_xpos >= base_x) && (pixel_xpos < base_x + (APPARENT_LEN * SMALL_CHAR_W)) &&
            (pixel_ypos >= base_y) && (pixel_ypos < base_y + SMALL_CHAR_H)) begin
            delta_x         = pixel_xpos - base_x;
            line_slot       = small_text_slot(delta_x, APPARENT_LEN);
            text_en         = 1'b1;
            text_font_small = 1'b1;
            text_char_idx   = ascii_to_idx(apparent_s_line_ascii(line_slot));
            text_color      = TEXT_WHITE;
            text_rel_x      = small_text_rel_x(delta_x);
            text_rel_y      = pixel_ypos - base_y;
        end
    end
endtask

// 在时域页参数区渲染功率因数文本行。
task try_power_factor_line_region;
    input [10:0] base_x;
    input [10:0] base_y;
    reg   [10:0] delta_x;
    begin
        if (!text_en &&
            (pixel_xpos >= base_x) && (pixel_xpos < base_x + (PF_LEN * SMALL_CHAR_W)) &&
            (pixel_ypos >= base_y) && (pixel_ypos < base_y + SMALL_CHAR_H)) begin
            delta_x         = pixel_xpos - base_x;
            line_slot       = small_text_slot(delta_x, PF_LEN);
            text_en         = 1'b1;
            text_font_small = 1'b1;
            text_char_idx   = ascii_to_idx(power_factor_line_ascii(line_slot));
            text_color      = WAVE_U_COLOR;
            text_rel_x      = small_text_rel_x(delta_x);
            text_rel_y      = pixel_ypos - base_y;
        end
    end
endtask

// 在时域页参数区渲染 sharp alarm 告警文本行。
task try_sharp_alarm_line_region;
    input [10:0] base_x;
    input [10:0] base_y;
    reg   [10:0] delta_x;
    begin
        if (!text_en && sharp_alarm_active &&
            (pixel_xpos >= base_x) && (pixel_xpos < base_x + ALARM_LINE_W) &&
            (pixel_ypos >= base_y) && (pixel_ypos < base_y + SMALL_CHAR_H)) begin
            delta_x         = pixel_xpos - base_x;
            line_slot       = small_text_slot(delta_x, ALARM_LEN);
            text_en         = 1'b1;
            text_font_small = 1'b1;
            text_char_idx   = ascii_to_idx(sharp_alarm_line_ascii(line_slot));
            text_color      = ALARM_COLOR;
            text_rel_x      = small_text_rel_x(delta_x);
            text_rel_y      = pixel_ypos - base_y;
        end
    end
endtask

// 在频域页右侧参数区按行号选择并渲染对应的文本行。
task try_freq_panel_line_region;
    input [10:0] base_y;
    input [10:0] right_x;
    input integer text_len;
    input [3:0]  line_id;
    input [23:0] color_value;
    reg   [10:0] delta_x;
    reg   [7:0]  line_char;
    begin
        if (!text_en &&
            (pixel_xpos >= LINE_X) && (pixel_xpos < LINE_X + (text_len * SMALL_CHAR_W)) &&
            (pixel_ypos >= base_y) && (pixel_ypos < base_y + SMALL_CHAR_H)) begin
            delta_x   = pixel_xpos - LINE_X;
            line_slot = small_text_slot(delta_x, text_len);

            case (line_id)
                4'd0: line_char = freq_fund_line_ascii(line_slot);
                4'd1: line_char = freq_thd_u_line_ascii(line_slot);
                4'd2: line_char = freq_thd_i_line_ascii(line_slot);
                4'd3: line_char = freq_u1_line_ascii(line_slot);
                4'd4: line_char = freq_i1_line_ascii(line_slot);
                4'd5: line_char = freq_phase1_line_ascii(line_slot);
                4'd6: line_char = freq_dc_u_line_ascii(line_slot);
                4'd7: line_char = freq_dc_i_line_ascii(line_slot);
                4'd8: line_char = freq_dh_u_line_ascii(line_slot);
                4'd9: line_char = freq_dh_i_line_ascii(line_slot);
                default: line_char = " ";
            endcase

            text_en         = 1'b1;
            text_font_small = 1'b1;
            text_char_idx   = ascii_to_idx(line_char);
            text_color      = color_value;
            text_rel_x      = small_text_rel_x(delta_x);
            text_rel_y      = pixel_ypos - base_y;
        end
    end
endtask

// 在频域页横轴刻度区域内按像素位置渲染当前窗口的谐波刻度标签。
task try_freq_axis_tick_region;
    input [10:0] base_x;
    input [2:0]  tick_index;
    reg   [10:0] delta_x;
    begin
        if (!text_en &&
            (pixel_xpos >= base_x) &&
            (pixel_xpos < base_x + (freq_axis_tick_len(harmonic_window_index, tick_index) * SMALL_CHAR_W)) &&
            (pixel_ypos >= FREQ_AXIS_TICK_Y) && (pixel_ypos < FREQ_AXIS_TICK_Y + SMALL_CHAR_H)) begin
            delta_x         = pixel_xpos - base_x;
            line_slot       = small_text_slot(delta_x, freq_axis_tick_len(harmonic_window_index, tick_index));
            text_en         = 1'b1;
            text_font_small = 1'b1;
            text_char_idx   = ascii_to_idx(freq_axis_tick_ascii(harmonic_window_index, tick_index, line_slot));
            text_color      = TEXT_DIM;
            text_rel_x      = small_text_rel_x(delta_x);
            text_rel_y      = pixel_ypos - FREQ_AXIS_TICK_Y;
        end
    end
endtask

// 组合选择当前像素命中的文本元素，并输出对应的字体、颜色与字模内坐标。
always @(*) begin
    text_en         = 1'b0;
    text_font_small = 1'b0;
    text_char_idx   = FONT_BLANK;
    text_color      = TEXT_WHITE;
    text_rel_x      = 6'd0;
    text_rel_y      = 6'd0;
    line_slot       = 0;
    tick_slot       = 0;

    if (frequency_page_active)
        try_big_text_region(TITLE_TXT_X, TITLE_TXT_Y, FREQ_TITLE_LEN, TEXT_WHITE, "MODE: Single - Frequency");
    else
        try_big_text_region(TITLE_TXT_X, TITLE_TXT_Y, TITLE_LEN, TEXT_WHITE, TITLE_STR);
    try_big_text_region(BTN_TXT_X,   BTN_TXT_Y,   BTN_LEN,   TEXT_WHITE, BTN_STR);
    if (freeze_active)
        try_big_text_region(AUTO_AUTO_TXT_X, AUTO_TXT_Y, AUTO_AUTO_LEN, TEXT_WHITE, AUTO_AUTO_STR);
    else
        try_big_text_region(AUTO_FREEZE_TXT_X, AUTO_TXT_Y, AUTO_FREEZE_LEN, TEXT_WHITE, AUTO_FREEZE_STR);

    if (frequency_page_active) begin
        try_big_text_region(PLOT_TXT_X, PLOT_TXT_Y, FREQ_PLOT_LEN, TEXT_SOFT, "Freq Domain Analysis");
        try_small_text_region(FREQ_LABEL_X, FREQ_MAG_LABEL_Y, FREQ_MAG_LABEL_LEN, WAVE_U_COLOR, "Magnitude (%)");
        try_small_text_region(FREQ_LABEL_X, FREQ_PHASE_LABEL_Y, FREQ_PHASE_LABEL_LEN, ACCENT_COLOR, "Phase Diff (deg)");
        try_small_text_region(FREQ_HARM_LABEL_X, FREQ_HARM_LABEL_Y, FREQ_HARM_LABEL_LEN, TEXT_DIM, "Harmonic Order");
        try_small_text_region(FREQ_PREV_TXT_X, FREQ_BTN_TXT_Y, 1, TEXT_WHITE, "<");
        try_small_text_region(FREQ_NEXT_TXT_X, FREQ_BTN_TXT_Y, 1, TEXT_WHITE, ">");

        try_small_text_region(FREQ_LABEL_X - 11'd22, FREQ_MAG_LABEL_Y + 11'd18, 3, TEXT_DIM, "100");
        try_small_text_region(FREQ_LABEL_X - 11'd18, FREQ_MAG_LABEL_Y + 11'd54, 2, TEXT_DIM, "80");
        try_small_text_region(FREQ_LABEL_X - 11'd18, FREQ_MAG_LABEL_Y + 11'd90, 2, TEXT_DIM, "60");
        try_small_text_region(FREQ_LABEL_X - 11'd18, FREQ_MAG_LABEL_Y + 11'd126, 2, TEXT_DIM, "40");
        try_small_text_region(FREQ_LABEL_X - 11'd18, FREQ_MAG_LABEL_Y + 11'd162, 2, TEXT_DIM, "20");
        try_small_text_region(FREQ_LABEL_X - 11'd10, FREQ_MAG_LABEL_Y + 11'd198, 1, TEXT_DIM, "0");
        try_small_text_region(FREQ_LABEL_X - 11'd26, FREQ_PHASE_LABEL_Y - 11'd119, 3, TEXT_DIM, "180");
        try_small_text_region(FREQ_LABEL_X - 11'd20, FREQ_PHASE_LABEL_Y - 11'd79, 2, TEXT_DIM, "90");
        try_small_text_region(FREQ_LABEL_X - 11'd10, FREQ_PHASE_LABEL_Y - 11'd39, 1, TEXT_DIM, "0");

        try_freq_axis_tick_region(FREQ_AXIS_TICK0_X, 3'd0);
        if (harmonic_window_index == 5'd0) begin
            try_freq_axis_tick_region(FREQ_AXIS_TICK1_X, 3'd1);
            try_freq_axis_tick_region(FREQ_AXIS_TICK5_X, 3'd2);
            try_freq_axis_tick_region(FREQ_AXIS_TICK10_X, 3'd3);
            try_freq_axis_tick_region(FREQ_AXIS_TICK15_X, 3'd4);
            try_freq_axis_tick_region(FREQ_AXIS_TICK20_X, 3'd5);
            try_freq_axis_tick_region(FREQ_AXIS_TICK25_X, 3'd6);
        end else begin
            try_freq_axis_tick_region(FREQ_AXIS_TICK5_X, 3'd1);
            try_freq_axis_tick_region(FREQ_AXIS_TICK10_X, 3'd2);
            try_freq_axis_tick_region(FREQ_AXIS_TICK15_X, 3'd3);
            try_freq_axis_tick_region(FREQ_AXIS_TICK20_X, 3'd4);
            try_freq_axis_tick_region(FREQ_AXIS_TICK25_X, 3'd5);
        end

        try_small_text_region(RP_TITLE_X, RP_TITLE_Y, RP_HEAD_LEN, ACCENT_COLOR, RP_HEAD_STR);
        try_freq_panel_line_region(LINE_Y0, 11'd756, FREQ_FUND_LEN, 4'd0, TEXT_SOFT);
        try_freq_panel_line_region(LINE_Y0 + LINE_STEP, 11'd756, FREQ_THD_LEN, 4'd1, WAVE_U_COLOR);
        try_freq_panel_line_region(LINE_Y0 + LINE_STEP + LINE_STEP, 11'd756, FREQ_THD_LEN, 4'd2, WAVE_I_COLOR);
        try_freq_panel_line_region(LINE_Y0 + LINE_STEP + LINE_STEP + LINE_STEP, 11'd756, FREQ_U1_LEN, 4'd3, WAVE_U_COLOR);
        try_freq_panel_line_region(LINE_Y0 + LINE_STEP + LINE_STEP + LINE_STEP + LINE_STEP, 11'd756, FREQ_I1_LEN, 4'd4, WAVE_I_COLOR);
        try_freq_panel_line_region(LINE_Y0 + LINE_STEP + LINE_STEP + LINE_STEP + LINE_STEP + LINE_STEP, 11'd756, FREQ_PHASE1_LEN, 4'd5, TEXT_WHITE);
        try_freq_panel_line_region(LINE_Y0 + LINE_STEP + LINE_STEP + LINE_STEP + LINE_STEP + LINE_STEP + LINE_STEP, 11'd756, FREQ_DC_LEN, 4'd6, WAVE_U_COLOR);
        try_freq_panel_line_region(LINE_Y0 + LINE_STEP + LINE_STEP + LINE_STEP + LINE_STEP + LINE_STEP + LINE_STEP + LINE_STEP, 11'd756, FREQ_DC_LEN, 4'd7, WAVE_I_COLOR);
        try_freq_panel_line_region(LINE_Y0 + LINE_STEP + LINE_STEP + LINE_STEP + LINE_STEP + LINE_STEP + LINE_STEP + LINE_STEP + LINE_STEP, 11'd756, FREQ_DH_LEN, 4'd8, WAVE_U_COLOR);
        try_freq_panel_line_region(LINE_Y0 + LINE_STEP + LINE_STEP + LINE_STEP + LINE_STEP + LINE_STEP + LINE_STEP + LINE_STEP + LINE_STEP + LINE_STEP, 11'd756, FREQ_DH_LEN, 4'd9, WAVE_I_COLOR);
    end
    else begin
        try_big_text_region(PLOT_TXT_X,  PLOT_TXT_Y,  PLOT_LEN,  TEXT_SOFT,  PLOT_STR);

        try_small_text_region(AXIS_V_X, AXIS_V_Y, AXIS_V_LEN, WAVE_U_COLOR, AXIS_V_STR);
        try_small_text_region(AXIS_I_X, AXIS_I_Y, AXIS_I_LEN, WAVE_I_COLOR, AXIS_I_STR);
        try_voltage_tick_region(V_TICK_X, V_TICK_Y0);
        try_current_tick_region(I_TICK_X, I_TICK_Y0);

        try_small_text_region(AXIS_TICK0_X, AXIS_TICK_Y, T_TICK_LEN, TEXT_DIM, "-60");
        try_small_text_region(AXIS_TICK1_X, AXIS_TICK_Y, T_TICK_LEN, TEXT_DIM, "-45");
        try_small_text_region(AXIS_TICK2_X, AXIS_TICK_Y, T_TICK_LEN, TEXT_DIM, "-30");
        try_small_text_region(AXIS_TICK3_X, AXIS_TICK_Y, T_TICK_LEN, TEXT_DIM, "-15");
        try_small_text_region(AXIS_TICK4_X, AXIS_TICK_Y, T_TICK_LEN, TEXT_DIM, "  0");
        try_small_text_region(AXIS_T_X, AXIS_T_Y, AXIS_T_LEN, TEXT_DIM, AXIS_T_STR);

        try_small_text_region(RP_TITLE_X, RP_TITLE_Y, RP_HEAD_LEN, ACCENT_COLOR, RP_HEAD_STR);
        try_freq_line_region(LINE_X, LINE_Y0);
        try_u_rms_line_region(LINE_X, LINE_Y0 + LINE_STEP);
        try_i_rms_line_region(LINE_X, LINE_Y0 + LINE_STEP + LINE_STEP);
        try_phase_line_region(LINE_X, LINE_Y0 + LINE_STEP + LINE_STEP + LINE_STEP);
        try_active_p_line_region(LINE_X, LINE_Y0 + LINE_STEP + LINE_STEP + LINE_STEP + LINE_STEP);
        try_reactive_q_line_region(LINE_X, LINE_Y0 + LINE_STEP + LINE_STEP + LINE_STEP + LINE_STEP + LINE_STEP);
        try_apparent_s_line_region(LINE_X, LINE_Y0 + LINE_STEP + LINE_STEP + LINE_STEP + LINE_STEP + LINE_STEP + LINE_STEP);
        try_power_factor_line_region(LINE_X, LINE_Y0 + LINE_STEP + LINE_STEP + LINE_STEP + LINE_STEP + LINE_STEP + LINE_STEP + LINE_STEP);
        try_sharp_alarm_line_region(LINE_X, ALARM_LINE_Y);
        try_u_pp_line_region(U_PP_X, U_PP_Y);
        try_i_pp_line_region(I_PP_X, I_PP_Y);
    end
end

endmodule
