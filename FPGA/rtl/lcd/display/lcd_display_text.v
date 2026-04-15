/*
 * 模块: lcd_display_text
 * 功能:
 *   根据测量结果和界面布局生成 LCD 文本层字符信息。
 *
 * 输入:
 *   pixel_xpos: 当前扫描像素的 X 坐标。
 *   pixel_ypos: 当前扫描像素的 Y 坐标。
 *   u_rms_tens: 信号。
 *   u_rms_units: 信号。
 *   u_rms_decile: 信号。
 *   u_rms_percentiles: 信号。
 *   u_rms_digits_valid: 有效标志。
 *   i_rms_tens: 信号。
 *   i_rms_units: 信号。
 *   i_rms_decile: 信号。
 *   i_rms_percentiles: 信号。
 *   i_rms_digits_valid: 有效标志。
 *   phase_neg: 信号。
 *   phase_hundreds: 信号。
 *   phase_tens: 信号。
 *   phase_units: 信号。
 *   phase_decile: 信号。
 *   phase_percentiles: 信号。
 *   phase_valid: 有效标志。
 *   freq_hundreds: 信号。
 *   freq_tens: 信号。
 *   freq_units: 信号。
 *   freq_decile: 信号。
 *   freq_percentiles: 信号。
 *   freq_valid: 有效标志。
 *   u_pp_tens: 信号。
 *   u_pp_units: 信号。
 *   u_pp_decile: 信号。
 *   u_pp_percentiles: 信号。
 *   u_pp_digits_valid: 有效标志。
 *   i_pp_tens: 信号。
 *   i_pp_units: 信号。
 *   i_pp_decile: 信号。
 *   i_pp_percentiles: 信号。
 *   i_pp_digits_valid: 有效标志。
 *   active_p_neg: 信号。
 *   active_p_tens: 信号。
 *   active_p_units: 信号。
 *   active_p_decile: 信号。
 *   active_p_percentiles: 信号。
 *   reactive_q_neg: 信号。
 *   reactive_q_tens: 信号。
 *   reactive_q_units: 信号。
 *   reactive_q_decile: 信号。
 *   reactive_q_percentiles: 信号。
 *   apparent_s_tens: 信号。
 *   apparent_s_units: 信号。
 *   apparent_s_decile: 信号。
 *   apparent_s_percentiles: 信号。
 *   power_factor_neg: 信号。
 *   power_factor_units: 信号。
 *   power_factor_decile: 信号。
 *   power_factor_percentiles: 信号。
 *   power_metrics_valid: 有效标志。
 *   freeze_active: 信号。
 *
 * 输出:
 *   text_en: 使能信号。
 *   text_font_small: 信号。
 *   text_char_idx: 信号。
 *   text_rel_x: 信号。
 *   text_rel_y: 信号。
 *   text_color: 信号。
 */
module lcd_display_text #(
    parameter integer U_FULL_SCALE_X100 = 1000,
    parameter integer I_FULL_SCALE_X100 = 300
)(
    input      [10:0] pixel_xpos,
    input      [10:0] pixel_ypos,
    input      [7:0]  u_rms_tens,
    input      [7:0]  u_rms_units,
    input      [7:0]  u_rms_decile,
    input      [7:0]  u_rms_percentiles,
    input             u_rms_digits_valid,
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
    input      [7:0]  u_pp_tens,
    input      [7:0]  u_pp_units,
    input      [7:0]  u_pp_decile,
    input      [7:0]  u_pp_percentiles,
    input             u_pp_digits_valid,
    input      [7:0]  i_pp_tens,
    input      [7:0]  i_pp_units,
    input      [7:0]  i_pp_decile,
    input      [7:0]  i_pp_percentiles,
    input             i_pp_digits_valid,
    input             active_p_neg,
    input      [7:0]  active_p_tens,
    input      [7:0]  active_p_units,
    input      [7:0]  active_p_decile,
    input      [7:0]  active_p_percentiles,
    input             reactive_q_neg,
    input      [7:0]  reactive_q_tens,
    input      [7:0]  reactive_q_units,
    input      [7:0]  reactive_q_decile,
    input      [7:0]  reactive_q_percentiles,
    input      [7:0]  apparent_s_tens,
    input      [7:0]  apparent_s_units,
    input      [7:0]  apparent_s_decile,
    input      [7:0]  apparent_s_percentiles,
    input             power_factor_neg,
    input      [7:0]  power_factor_units,
    input      [7:0]  power_factor_decile,
    input      [7:0]  power_factor_percentiles,
    input             power_metrics_valid,
    input             freeze_active,
    output reg        text_en,
    output reg        text_font_small,
    output reg [6:0]  text_char_idx,
    output reg [5:0]  text_rel_x,
    output reg [5:0]  text_rel_y,
    output reg [23:0] text_color
);

// 盲赂陇氓楼聴氓颅聴氓聫路莽職聞氓聼潞莽隆聙氓掳潞氓炉赂茫聙聜
localparam [5:0] BIG_CHAR_W   = 6'd16;
localparam [5:0] BIG_CHAR_H   = 6'd32;
localparam [5:0] SMALL_CHAR_W = 6'd10;
localparam [5:0] SMALL_CHAR_H = 6'd20;

// 氓颅聴氓潞聯莽麓垄氓录聲氓庐職盲鹿聣茂录聦茅聹聙盲赂聨氓颅聴盲陆聯 ROM 忙聳聡盲禄露盲驴聺忙聦聛盲赂聙猫聡麓茫聙聜
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

// 忙聳聡氓颅聴茅垄聹猫聣虏氓庐職盲鹿聣茫聙聜
localparam [23:0] TEXT_WHITE   = 24'hF2F6FA;
localparam [23:0] TEXT_SOFT    = 24'hC6D3E2;
localparam [23:0] TEXT_DIM     = 24'h95A9BE;
localparam [23:0] WAVE_U_COLOR = 24'h39E46F;
localparam [23:0] WAVE_I_COLOR = 24'hFFD84E;
localparam [23:0] ACCENT_COLOR = 24'h58B6FF;

// 氓聬聞忙聳聡忙聹卢氓聺聴氓聹篓氓卤聫氓鹿聲盲赂聤莽職聞猫碌路氓搂聥盲陆聧莽陆庐茫聙聜
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
localparam [10:0] U_PP_X       = 11'd68;
localparam [10:0] U_PP_Y       = 11'd425;
localparam [10:0] I_PP_X       = 11'd68;
localparam [10:0] I_PP_Y       = 11'd449;

localparam integer MAX_TEXT_LEN = 25;
localparam integer TITLE_LEN    = 19;
localparam integer BTN_LEN      = 4;
localparam integer AUTO_FREEZE_LEN = 6;
localparam integer AUTO_AUTO_LEN   = 4;
localparam integer PLOT_LEN     = 20;
localparam integer AXIS_V_LEN   = 11;
localparam integer AXIS_I_LEN   = 11;
localparam integer AXIS_T_LEN   = 8;
localparam integer V_TICK_LEN   = 5;
localparam integer I_TICK_LEN   = 5;
localparam integer T_TICK_LEN   = 3;
localparam integer RP_HEAD_LEN  = 10;
localparam integer FREQ_LEN     = 22;
localparam integer RMS_LEN      = 16;
localparam integer PHASE_LEN    = 25;
localparam integer ACTIVE_LEN   = 20;
localparam integer REACTIVE_LEN = 24;
localparam integer APPARENT_LEN = 23;
localparam integer PF_LEN       = 20;
localparam integer PP_LEN       = 14;

localparam [8*TITLE_LEN-1:0]   TITLE_STR   = "MODE: Single - Time";
localparam [8*BTN_LEN-1:0]     BTN_STR     = "MODE";
localparam [8*AUTO_FREEZE_LEN-1:0] AUTO_FREEZE_STR = "Freeze";
localparam [8*AUTO_AUTO_LEN-1:0]   AUTO_AUTO_STR   = "Auto";
localparam [8*PLOT_LEN-1:0]    PLOT_STR    = "Time Domain Analysis";
localparam [8*AXIS_V_LEN-1:0]  AXIS_V_STR  = "Voltage (V)";
localparam [8*AXIS_I_LEN-1:0]  AXIS_I_STR  = "Current (A)";
localparam [8*AXIS_T_LEN-1:0]  AXIS_T_STR  = "Time(ms)";
localparam [8*RP_HEAD_LEN-1:0] RP_HEAD_STR = "Parameters";

// 将 x100 满量程按 7 档刻度需要的 1/3 比例做常量化舍入，避免在显示逻辑中新增除法。
function integer div3_round_const;
    input integer value;
    integer work;
    begin
        work = value + 1;
        div3_round_const = 0;
        while (work >= 3) begin
            work = work - 3;
            div3_round_const = div3_round_const + 1;
        end
    end
endfunction

localparam integer U_TICK_FULL_X100       = U_FULL_SCALE_X100;
localparam integer U_TICK_TWO_THIRDS_X100 = div3_round_const(U_FULL_SCALE_X100 + U_FULL_SCALE_X100);
localparam integer U_TICK_ONE_THIRD_X100  = div3_round_const(U_FULL_SCALE_X100);
localparam integer I_TICK_FULL_X100       = I_FULL_SCALE_X100;
localparam integer I_TICK_TWO_THIRDS_X100 = div3_round_const(I_FULL_SCALE_X100 + I_FULL_SCALE_X100);
localparam integer I_TICK_ONE_THIRD_X100  = div3_round_const(I_FULL_SCALE_X100);

wire [7:0] u_tick_full_tens;
wire [7:0] u_tick_full_units;
wire [7:0] u_tick_full_decile;
wire [7:0] u_tick_two_thirds_tens;
wire [7:0] u_tick_two_thirds_units;
wire [7:0] u_tick_two_thirds_decile;
wire [7:0] u_tick_one_third_tens;
wire [7:0] u_tick_one_third_units;
wire [7:0] u_tick_one_third_decile;
wire [7:0] i_tick_full_tens;
wire [7:0] i_tick_full_units;
wire [7:0] i_tick_full_decile;
wire [7:0] i_tick_two_thirds_tens;
wire [7:0] i_tick_two_thirds_units;
wire [7:0] i_tick_two_thirds_decile;
wire [7:0] i_tick_one_third_tens;
wire [7:0] i_tick_one_third_units;
wire [7:0] i_tick_one_third_decile;

integer line_slot;
integer tick_slot;

// 将满量程及 1/3、2/3 刻度值拆成显示用十进制位，刻度文本不再单独硬编码物理量。
value_x100_to_digits u_u_tick_full_digits (
    .value_x100 (U_TICK_FULL_X100 + 5),
    .hundreds   (),
    .tens       (u_tick_full_tens),
    .units      (u_tick_full_units),
    .decile     (u_tick_full_decile),
    .percentiles()
);

value_x100_to_digits u_u_tick_two_thirds_digits (
    .value_x100 (U_TICK_TWO_THIRDS_X100 + 5),
    .hundreds   (),
    .tens       (u_tick_two_thirds_tens),
    .units      (u_tick_two_thirds_units),
    .decile     (u_tick_two_thirds_decile),
    .percentiles()
);

value_x100_to_digits u_u_tick_one_third_digits (
    .value_x100 (U_TICK_ONE_THIRD_X100 + 5),
    .hundreds   (),
    .tens       (u_tick_one_third_tens),
    .units      (u_tick_one_third_units),
    .decile     (u_tick_one_third_decile),
    .percentiles()
);

value_x100_to_digits u_i_tick_full_digits (
    .value_x100 (I_TICK_FULL_X100 + 5),
    .hundreds   (),
    .tens       (i_tick_full_tens),
    .units      (i_tick_full_units),
    .decile     (i_tick_full_decile),
    .percentiles()
);

value_x100_to_digits u_i_tick_two_thirds_digits (
    .value_x100 (I_TICK_TWO_THIRDS_X100 + 5),
    .hundreds   (),
    .tens       (i_tick_two_thirds_tens),
    .units      (i_tick_two_thirds_units),
    .decile     (i_tick_two_thirds_decile),
    .percentiles()
);

value_x100_to_digits u_i_tick_one_third_digits (
    .value_x100 (I_TICK_ONE_THIRD_X100 + 5),
    .hundreds   (),
    .tens       (i_tick_one_third_tens),
    .units      (i_tick_one_third_units),
    .decile     (i_tick_one_third_decile),
    .percentiles()
);

// ASCII 氓聢掳氓颅聴盲陆聯莽麓垄氓录聲莽職聞莽禄聼盲赂聙忙聵聽氓掳聞茫聙聜
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
                default: ascii_to_idx = FONT_BLANK;
            endcase
        end
    end
endfunction

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
            11: active_p_line_ascii = power_metrics_valid ? ((active_p_tens == 8'd0) ? " " : digit_to_ascii(active_p_tens)) : " ";
            12: active_p_line_ascii = power_metrics_valid ? digit_to_ascii(active_p_units) : " ";
            13: active_p_line_ascii = ".";
            14: active_p_line_ascii = power_metrics_valid ? digit_to_ascii(active_p_decile) : " ";
            15: active_p_line_ascii = power_metrics_valid ? digit_to_ascii(active_p_percentiles) : " ";
            16: active_p_line_ascii = " ";
            17: active_p_line_ascii = "(";
            18: active_p_line_ascii = "W";
            19: active_p_line_ascii = ")";
            default: active_p_line_ascii = " ";
        endcase
    end
endfunction

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
            13: reactive_q_line_ascii = power_metrics_valid ? ((reactive_q_tens == 8'd0) ? " " : digit_to_ascii(reactive_q_tens)) : " ";
            14: reactive_q_line_ascii = power_metrics_valid ? digit_to_ascii(reactive_q_units) : " ";
            15: reactive_q_line_ascii = ".";
            16: reactive_q_line_ascii = power_metrics_valid ? digit_to_ascii(reactive_q_decile) : " ";
            17: reactive_q_line_ascii = power_metrics_valid ? digit_to_ascii(reactive_q_percentiles) : " ";
            18: reactive_q_line_ascii = " ";
            19: reactive_q_line_ascii = "(";
            20: reactive_q_line_ascii = "v";
            21: reactive_q_line_ascii = "a";
            22: reactive_q_line_ascii = "r";
            23: reactive_q_line_ascii = ")";
            default: reactive_q_line_ascii = " ";
        endcase
    end
endfunction

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
            13: apparent_s_line_ascii = power_metrics_valid ? ((apparent_s_tens == 8'd0) ? " " : digit_to_ascii(apparent_s_tens)) : " ";
            14: apparent_s_line_ascii = power_metrics_valid ? digit_to_ascii(apparent_s_units) : " ";
            15: apparent_s_line_ascii = ".";
            16: apparent_s_line_ascii = power_metrics_valid ? digit_to_ascii(apparent_s_decile) : " ";
            17: apparent_s_line_ascii = power_metrics_valid ? digit_to_ascii(apparent_s_percentiles) : " ";
            18: apparent_s_line_ascii = " ";
            19: apparent_s_line_ascii = "(";
            20: apparent_s_line_ascii = "V";
            21: apparent_s_line_ascii = "A";
            22: apparent_s_line_ascii = ")";
            default: apparent_s_line_ascii = " ";
        endcase
    end
endfunction

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

// 氓聧聛猫驴聸氓聢露忙聲掳氓颅聴猫陆卢 ASCII茂录聸氓录聜氓赂赂猫戮聯氓聟楼氓聸聻茅聙聙盲赂潞 '-'.
function [7:0] digit_to_ascii;
    input [7:0] digit;
    begin
        if (digit <= 8'd9)
            digit_to_ascii = "0" + digit[7:0];
        else
            digit_to_ascii = " ";
    end
endfunction

// 盲禄聨氓庐職茅聲驴氓颅聴莽卢娄盲赂虏盲赂颅氓聫聳氓聡潞忙聦聡氓庐職忙搂陆盲陆聧氓颅聴莽卢娄茫聙聜
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

// 7 档纵向刻度统一显示为“符号 + 两位整数 + 一位小数”。
function [7:0] tick_tens_ascii;
    input [7:0] tens_digit;
    begin
        tick_tens_ascii = (tens_digit == 8'd0) ? " " : digit_to_ascii(tens_digit);
    end
endfunction

function [7:0] tick_value_ascii;
    input [7:0] sign_char;
    input [7:0] tens_digit;
    input [7:0] units_digit;
    input [7:0] decile_digit;
    input integer char_slot;
    begin
        case (char_slot)
            0: tick_value_ascii = sign_char;
            1: tick_value_ascii = tick_tens_ascii(tens_digit);
            2: tick_value_ascii = digit_to_ascii(units_digit);
            3: tick_value_ascii = ".";
            4: tick_value_ascii = digit_to_ascii(decile_digit);
            default: tick_value_ascii = " ";
        endcase
    end
endfunction

// 电压纵向刻度：按 U_FULL_SCALE_X100 拆成 +FS、+2/3FS、+1/3FS、0、-1/3FS、-2/3FS、-FS。
function [7:0] voltage_tick_ascii;
    input integer tick_index;
    input integer char_slot;
    begin
        case (tick_index)
            0:  voltage_tick_ascii = tick_value_ascii("+", u_tick_full_tens, u_tick_full_units, u_tick_full_decile, char_slot);
            1:  voltage_tick_ascii = tick_value_ascii("+", u_tick_two_thirds_tens, u_tick_two_thirds_units, u_tick_two_thirds_decile, char_slot);
            2:  voltage_tick_ascii = tick_value_ascii("+", u_tick_one_third_tens, u_tick_one_third_units, u_tick_one_third_decile, char_slot);
            3:  voltage_tick_ascii = tick_value_ascii(" ", 8'd0, 8'd0, 8'd0, char_slot);
            4:  voltage_tick_ascii = tick_value_ascii("-", u_tick_one_third_tens, u_tick_one_third_units, u_tick_one_third_decile, char_slot);
            5:  voltage_tick_ascii = tick_value_ascii("-", u_tick_two_thirds_tens, u_tick_two_thirds_units, u_tick_two_thirds_decile, char_slot);
            6:  voltage_tick_ascii = tick_value_ascii("-", u_tick_full_tens, u_tick_full_units, u_tick_full_decile, char_slot);
            default: voltage_tick_ascii = " ";
        endcase
    end
endfunction

// 电流纵向刻度：按 I_FULL_SCALE_X100 拆成 +FS、+2/3FS、+1/3FS、0、-1/3FS、-2/3FS、-FS。
function [7:0] current_tick_ascii;
    input integer tick_index;
    input integer char_slot;
    begin
        case (tick_index)
            0: current_tick_ascii = tick_value_ascii("+", i_tick_full_tens, i_tick_full_units, i_tick_full_decile, char_slot);
            1: current_tick_ascii = tick_value_ascii("+", i_tick_two_thirds_tens, i_tick_two_thirds_units, i_tick_two_thirds_decile, char_slot);
            2: current_tick_ascii = tick_value_ascii("+", i_tick_one_third_tens, i_tick_one_third_units, i_tick_one_third_decile, char_slot);
            3: current_tick_ascii = tick_value_ascii(" ", 8'd0, 8'd0, 8'd0, char_slot);
            4: current_tick_ascii = tick_value_ascii("-", i_tick_one_third_tens, i_tick_one_third_units, i_tick_one_third_decile, char_slot);
            5: current_tick_ascii = tick_value_ascii("-", i_tick_two_thirds_tens, i_tick_two_thirds_units, i_tick_two_thirds_decile, char_slot);
            6: current_tick_ascii = tick_value_ascii("-", i_tick_full_tens, i_tick_full_units, i_tick_full_decile, char_slot);
            default: current_tick_ascii = " ";
        endcase
    end
endfunction

// Frequency 猫隆聦氓聤篓忙聙聛氓颅聴莽卢娄莽聰聼忙聢聬茫聙聜
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

// U_rms line formatter.
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
            7:  u_rms_line_ascii = u_rms_digits_valid ? ((u_rms_tens == 8'd0) ? " " : digit_to_ascii(u_rms_tens)) : " ";
            8:  u_rms_line_ascii = u_rms_digits_valid ? digit_to_ascii(u_rms_units) : " ";
            9:  u_rms_line_ascii = ".";
            10: u_rms_line_ascii = u_rms_digits_valid ? digit_to_ascii(u_rms_decile) : " ";
            11: u_rms_line_ascii = u_rms_digits_valid ? digit_to_ascii(u_rms_percentiles) : " ";
            12: u_rms_line_ascii = " ";
            13: u_rms_line_ascii = "(";
            14: u_rms_line_ascii = "V";
            15: u_rms_line_ascii = ")";
            default: u_rms_line_ascii = " ";
        endcase
    end
endfunction

// I_rms 猫隆聦氓聤篓忙聙聛氓颅聴莽卢娄莽聰聼忙聢聬茫聙聜
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
            7:  i_rms_line_ascii = i_rms_digits_valid ? ((i_rms_tens == 8'd0) ? " " : digit_to_ascii(i_rms_tens)) : " ";
            8:  i_rms_line_ascii = i_rms_digits_valid ? digit_to_ascii(i_rms_units) : " ";
            9:  i_rms_line_ascii = ".";
            10: i_rms_line_ascii = i_rms_digits_valid ? digit_to_ascii(i_rms_decile) : " ";
            11: i_rms_line_ascii = i_rms_digits_valid ? digit_to_ascii(i_rms_percentiles) : " ";
            12: i_rms_line_ascii = " ";
            13: i_rms_line_ascii = "(";
            14: i_rms_line_ascii = "A";
            15: i_rms_line_ascii = ")";
            default: i_rms_line_ascii = " ";
        endcase
    end
endfunction

// Phase Diff 猫隆聦氓聤篓忙聙聛氓颅聴莽卢娄莽聰聼忙聢聬茂录聦氓陆聯氓聣聧氓聧聲盲陆聧盲赂潞 deg茫聙聜
function [7:0] phase_line_ascii;
    input integer char_slot;
    begin
        case (char_slot)
            0:  phase_line_ascii = "P";
            1:  phase_line_ascii = "h";
            2:  phase_line_ascii = "a";
            3:  phase_line_ascii = "s";
            4:  phase_line_ascii = "e";
            5:  phase_line_ascii = " ";
            6:  phase_line_ascii = "D";
            7:  phase_line_ascii = "i";
            8:  phase_line_ascii = "f";
            9:  phase_line_ascii = "f";
            10: phase_line_ascii = ":";
            11: phase_line_ascii = " ";
            12: phase_line_ascii = phase_valid ? (phase_neg ? "-" : "+") : " ";
            13: phase_line_ascii = phase_valid ? ((phase_hundreds == 8'd0) ? " " : digit_to_ascii(phase_hundreds)) : " ";
            14: phase_line_ascii = phase_valid ? (((phase_hundreds == 8'd0) && (phase_tens == 8'd0)) ? " " : digit_to_ascii(phase_tens)) : " ";
            15: phase_line_ascii = phase_valid ? digit_to_ascii(phase_units) : " ";
            16: phase_line_ascii = ".";
            17: phase_line_ascii = phase_valid ? digit_to_ascii(phase_decile) : " ";
            18: phase_line_ascii = phase_valid ? digit_to_ascii(phase_percentiles) : " ";
            19: phase_line_ascii = " ";
            20: phase_line_ascii = "(";
            21: phase_line_ascii = "d";
            22: phase_line_ascii = "e";
            23: phase_line_ascii = "g";
            24: phase_line_ascii = ")";
            default: phase_line_ascii = " ";
        endcase
    end
endfunction

// Upp 猫隆聦氓聤篓忙聙聛氓颅聴莽卢娄莽聰聼忙聢聬茫聙聜
function [7:0] u_pp_line_ascii;
    input integer char_slot;
    begin
        case (char_slot)
            0:  u_pp_line_ascii = "U";
            1:  u_pp_line_ascii = "p";
            2:  u_pp_line_ascii = "p";
            3:  u_pp_line_ascii = ":";
            4:  u_pp_line_ascii = " ";
            5:  u_pp_line_ascii = u_pp_digits_valid ? ((u_pp_tens == 8'd0) ? " " : digit_to_ascii(u_pp_tens)) : " ";
            6:  u_pp_line_ascii = u_pp_digits_valid ? digit_to_ascii(u_pp_units) : " ";
            7:  u_pp_line_ascii = ".";
            8:  u_pp_line_ascii = u_pp_digits_valid ? digit_to_ascii(u_pp_decile) : " ";
            9:  u_pp_line_ascii = u_pp_digits_valid ? digit_to_ascii(u_pp_percentiles) : " ";
            10: u_pp_line_ascii = " ";
            11: u_pp_line_ascii = "(";
            12: u_pp_line_ascii = "V";
            13: u_pp_line_ascii = ")";
            default: u_pp_line_ascii = " ";
        endcase
    end
endfunction

// Ipp 猫隆聦氓聤篓忙聙聛氓颅聴莽卢娄莽聰聼忙聢聬茫聙聜
function [7:0] i_pp_line_ascii;
    input integer char_slot;
    begin
        case (char_slot)
            0:  i_pp_line_ascii = "I";
            1:  i_pp_line_ascii = "p";
            2:  i_pp_line_ascii = "p";
            3:  i_pp_line_ascii = ":";
            4:  i_pp_line_ascii = " ";
            5:  i_pp_line_ascii = i_pp_digits_valid ? ((i_pp_tens == 8'd0) ? " " : digit_to_ascii(i_pp_tens)) : " ";
            6:  i_pp_line_ascii = i_pp_digits_valid ? digit_to_ascii(i_pp_units) : " ";
            7:  i_pp_line_ascii = ".";
            8:  i_pp_line_ascii = i_pp_digits_valid ? digit_to_ascii(i_pp_decile) : " ";
            9:  i_pp_line_ascii = i_pp_digits_valid ? digit_to_ascii(i_pp_percentiles) : " ";
            10: i_pp_line_ascii = " ";
            11: i_pp_line_ascii = "(";
            12: i_pp_line_ascii = "A";
            13: i_pp_line_ascii = ")";
            default: i_pp_line_ascii = " ";
        endcase
    end
endfunction

// 氓掳聫氓颅聴氓聫路忙聳聡忙聹卢茂录職忙聽鹿忙聧庐忙篓陋氓聬聭氓聛聫莽搂禄莽隆庐氓庐職氓颅聴莽卢娄忙搂陆盲陆聧茫聙聜
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

// 氓掳聺猫炉聲氓聭陆盲赂颅盲赂聙氓聺聴 16x32 忙聳聡忙聹卢氓聦潞氓聼聼茫聙聜
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

// 氓掳聺猫炉聲氓聭陆盲赂颅盲赂聙氓聺聴 10x20 忙聳聡忙聹卢氓聦潞氓聼聼茫聙聜
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

// 氓掳聺猫炉聲氓聭陆盲赂颅氓路娄盲戮搂莽聰碌氓聨聥氓聢禄氓潞娄氓聦潞茫聙聜
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

// 氓掳聺猫炉聲氓聭陆盲赂颅氓聫鲁盲戮搂莽聰碌忙碌聛氓聢禄氓潞娄氓聦潞茫聙聜
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

// 莽禄聞氓聬聢忙聣芦忙聫聫忙聣聙忙聹聣忙聳聡氓颅聴氓聦潞氓聼聼茂录聦氓聭陆盲赂颅盲录聵氓聟聢莽潞搂盲赂聨猫掳聝莽聰篓茅隆潞氓潞聫盲赂聙猫聡麓茫聙聜
always @(*) begin
    text_en         = 1'b0;
    text_font_small = 1'b0;
    text_char_idx   = FONT_BLANK;
    text_color      = TEXT_WHITE;
    text_rel_x      = 6'd0;
    text_rel_y      = 6'd0;
    line_slot       = 0;
    tick_slot       = 0;

    try_big_text_region(TITLE_TXT_X, TITLE_TXT_Y, TITLE_LEN, TEXT_WHITE, TITLE_STR);
    try_big_text_region(BTN_TXT_X,   BTN_TXT_Y,   BTN_LEN,   TEXT_WHITE, BTN_STR);
    if (freeze_active)
        try_big_text_region(AUTO_AUTO_TXT_X, AUTO_TXT_Y, AUTO_AUTO_LEN, TEXT_WHITE, AUTO_AUTO_STR);
    else
        try_big_text_region(AUTO_FREEZE_TXT_X, AUTO_TXT_Y, AUTO_FREEZE_LEN, TEXT_WHITE, AUTO_FREEZE_STR);
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
    try_i_rms_line_region(LINE_X, LINE_Y0 + (LINE_STEP * 2));
    try_phase_line_region(LINE_X, LINE_Y0 + (LINE_STEP * 3));
    try_active_p_line_region(LINE_X, LINE_Y0 + (LINE_STEP * 4));
    try_reactive_q_line_region(LINE_X, LINE_Y0 + (LINE_STEP * 5));
    try_apparent_s_line_region(LINE_X, LINE_Y0 + (LINE_STEP * 6));
    try_power_factor_line_region(LINE_X, LINE_Y0 + (LINE_STEP * 7));
    try_u_pp_line_region(U_PP_X, U_PP_Y);
    try_i_pp_line_region(I_PP_X, I_PP_Y);
end

endmodule
