/*
 * Module: lcd_display_text
 * Function:
 *   Decode the current pixel into a text cell, font size, glyph index and
 *   color. The module keeps the page wording in one place and uses helper
 *   tasks/functions to avoid repeating the same region decode pattern.
 */
module lcd_display_text(
    input      [10:0] pixel_xpos,
    input      [10:0] pixel_ypos,
    input      [7:0]  u_rms_tens,
    input      [7:0]  u_rms_units,
    input      [7:0]  u_rms_decile,
    input      [7:0]  u_rms_percentiles,
    input             u_rms_digits_valid,
    output reg        text_en,
    output reg        text_font_small,
    output reg [6:0]  text_char_idx,
    output reg [5:0]  text_rel_x,
    output reg [5:0]  text_rel_y,
    output reg [23:0] text_color
);

localparam [5:0] BIG_CHAR_W   = 6'd16;
localparam [5:0] BIG_CHAR_H   = 6'd32;
localparam [5:0] SMALL_CHAR_W = 6'd10;
localparam [5:0] SMALL_CHAR_H = 6'd20;

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
localparam [6:0] FONT_SLASH      = 7'd85;
localparam [6:0] FONT_COLON      = 7'd89;

localparam [23:0] TEXT_WHITE   = 24'hF2F6FA;
localparam [23:0] TEXT_SOFT    = 24'hC6D3E2;
localparam [23:0] TEXT_DIM     = 24'h95A9BE;
localparam [23:0] WAVE_U_COLOR = 24'h39E46F;
localparam [23:0] WAVE_I_COLOR = 24'hFFD84E;
localparam [23:0] ACCENT_COLOR = 24'h58B6FF;

localparam [10:0] TITLE_TXT_X  = 11'd32;
localparam [10:0] TITLE_TXT_Y  = 11'd6;
localparam [10:0] BTN_TXT_X    = 11'd578;
localparam [10:0] BTN_TXT_Y    = 11'd6;
localparam [10:0] AUTO_TXT_X   = 11'd700;
localparam [10:0] AUTO_TXT_Y   = 11'd6;
localparam [10:0] PLOT_TXT_X   = 11'd68;
localparam [10:0] PLOT_TXT_Y   = 11'd72;
localparam [10:0] AXIS_V_X     = 11'd40;
localparam [10:0] AXIS_V_Y     = 11'd118;
localparam [10:0] AXIS_I_X     = 11'd306;
localparam [10:0] AXIS_I_Y     = 11'd118;
localparam [10:0] AXIS_TICK0_X = 11'd36;
localparam [10:0] AXIS_TICK1_X = 11'd117;
localparam [10:0] AXIS_TICK2_X = 11'd213;
localparam [10:0] AXIS_TICK3_X = 11'd309;
localparam [10:0] AXIS_TICK4_X = 11'd389;
localparam [10:0] AXIS_TICK_Y  = 11'd392;
localparam [10:0] AXIS_T_X     = 11'd336;
localparam [10:0] AXIS_T_Y     = 11'd416;
localparam [10:0] V_TICK_X     = 11'd12;
localparam [10:0] V_TICK_Y0    = 11'd134;
localparam [10:0] V_TICK_STEP  = 11'd24;
localparam [10:0] I_TICK_X     = 11'd424;
localparam [10:0] I_TICK_Y0    = 11'd134;
localparam [10:0] I_TICK_STEP  = 11'd40;
localparam [10:0] RP_TITLE_X   = 11'd520;
localparam [10:0] RP_TITLE_Y   = 11'd76;
localparam [10:0] LEGEND1_X    = 11'd560;
localparam [10:0] LEGEND1_Y    = 11'd112;
localparam [10:0] LEGEND2_X    = 11'd676;
localparam [10:0] LEGEND2_Y    = 11'd112;
localparam [10:0] LINE_X       = 11'd516;
localparam [10:0] LINE_Y0      = 11'd144;
localparam [10:0] LINE_STEP    = 11'd30;

localparam integer MAX_TEXT_LEN = 22;
localparam integer TITLE_LEN    = 19;
localparam integer BTN_LEN      = 6;
localparam integer AUTO_LEN     = 4;
localparam integer PLOT_LEN     = 20;
localparam integer AXIS_V_LEN   = 12;
localparam integer AXIS_I_LEN   = 11;
localparam integer AXIS_T_LEN   = 8;
localparam integer V_TICK_LEN   = 2;
localparam integer I_TICK_LEN   = 4;
localparam integer T_TICK_LEN   = 3;
localparam integer RP_HEAD_LEN  = 10;
localparam integer LEGEND_U_LEN = 1;
localparam integer LEGEND_I_LEN = 1;
localparam integer LINE1_LEN    = 17;
localparam integer LINE2_LEN    = 16;
localparam integer LINE3_LEN    = 16;
localparam integer LINE4_LEN    = 22;

localparam [8*TITLE_LEN-1:0]    TITLE_STR    = "MODE: Single - Time";
localparam [8*BTN_LEN-1:0]      BTN_STR      = "Freeze";
localparam [8*AUTO_LEN-1:0]     AUTO_STR     = "Auto";
localparam [8*PLOT_LEN-1:0]     PLOT_STR     = "Time Domain Analysis";
localparam [8*AXIS_V_LEN-1:0]   AXIS_V_STR   = "Voltage ( V)";
localparam [8*AXIS_I_LEN-1:0]   AXIS_I_STR   = "Current (A)";
localparam [8*AXIS_T_LEN-1:0]   AXIS_T_STR   = "Time(ms)";
localparam [8*RP_HEAD_LEN-1:0]  RP_HEAD_STR  = "Parameters";
localparam [8*LEGEND_U_LEN-1:0] LEGEND_U_STR = "U";
localparam [8*LEGEND_I_LEN-1:0] LEGEND_I_STR = "I";
localparam [8*LINE1_LEN-1:0]    LINE1_STR    = "Sampling: 5 (KPS)";
localparam [8*LINE3_LEN-1:0]    LINE3_STR    = "I_rms: --.-- (A)";
localparam [8*LINE4_LEN-1:0]    LINE4_STR    = "Phase Diff: 0.49 (rad)";

integer line_slot;
integer tick_slot;

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
                "/": ascii_to_idx = FONT_SLASH;
                ":": ascii_to_idx = FONT_COLON;
                default: ascii_to_idx = FONT_BLANK;
            endcase
        end
    end
endfunction

function [7:0] digit_to_ascii;
    input [7:0] digit;
    begin
        if (digit <= 8'd9)
            digit_to_ascii = "0" + digit[7:0];
        else
            digit_to_ascii = "-";
    end
endfunction

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

function [7:0] voltage_tick_ascii;
    input integer tick_index;
    input integer char_slot;
    begin
        case (tick_index)
            0:  voltage_tick_ascii = text_char_from_str("+5", V_TICK_LEN, char_slot);
            1:  voltage_tick_ascii = text_char_from_str("+4", V_TICK_LEN, char_slot);
            2:  voltage_tick_ascii = text_char_from_str("+3", V_TICK_LEN, char_slot);
            3:  voltage_tick_ascii = text_char_from_str("+2", V_TICK_LEN, char_slot);
            4:  voltage_tick_ascii = text_char_from_str("+1", V_TICK_LEN, char_slot);
            5:  voltage_tick_ascii = text_char_from_str(" 0", V_TICK_LEN, char_slot);
            6:  voltage_tick_ascii = text_char_from_str("-1", V_TICK_LEN, char_slot);
            7:  voltage_tick_ascii = text_char_from_str("-2", V_TICK_LEN, char_slot);
            8:  voltage_tick_ascii = text_char_from_str("-3", V_TICK_LEN, char_slot);
            9:  voltage_tick_ascii = text_char_from_str("-4", V_TICK_LEN, char_slot);
            10: voltage_tick_ascii = text_char_from_str("-5", V_TICK_LEN, char_slot);
            default: voltage_tick_ascii = " ";
        endcase
    end
endfunction

function [7:0] current_tick_ascii;
    input integer tick_index;
    input integer char_slot;
    begin
        case (tick_index)
            0: current_tick_ascii = text_char_from_str("+0.3", I_TICK_LEN, char_slot);
            1: current_tick_ascii = text_char_from_str("+0.2", I_TICK_LEN, char_slot);
            2: current_tick_ascii = text_char_from_str("+0.1", I_TICK_LEN, char_slot);
            3: current_tick_ascii = text_char_from_str(" 0.0", I_TICK_LEN, char_slot);
            4: current_tick_ascii = text_char_from_str("-0.1", I_TICK_LEN, char_slot);
            5: current_tick_ascii = text_char_from_str("-0.2", I_TICK_LEN, char_slot);
            6: current_tick_ascii = text_char_from_str("-0.3", I_TICK_LEN, char_slot);
            default: current_tick_ascii = " ";
        endcase
    end
endfunction

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
            7:  u_rms_line_ascii = u_rms_digits_valid ? ((u_rms_tens == 8'd0) ? " " : digit_to_ascii(u_rms_tens)) : "-";
            8:  u_rms_line_ascii = u_rms_digits_valid ? digit_to_ascii(u_rms_units) : "-";
            9:  u_rms_line_ascii = ".";
            10: u_rms_line_ascii = u_rms_digits_valid ? digit_to_ascii(u_rms_decile) : "-";
            11: u_rms_line_ascii = u_rms_digits_valid ? digit_to_ascii(u_rms_percentiles) : "-";
            12: u_rms_line_ascii = " ";
            13: u_rms_line_ascii = "(";
            14: u_rms_line_ascii = "V";
            15: u_rms_line_ascii = ")";
            default: u_rms_line_ascii = " ";
        endcase
    end
endfunction

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
        for (idx = 0; idx < 11; idx = idx + 1) begin
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
        for (idx = 0; idx < 11; idx = idx + 1) begin
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
        for (idx = 0; idx < 11; idx = idx + 1) begin
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

task try_voltage_tick_region;
    input [10:0] base_x;
    input [10:0] base_y;
    reg   [10:0] delta_x;
    reg   [10:0] delta_y;
    begin
        if (!text_en &&
            (pixel_xpos >= base_x) && (pixel_xpos < base_x + (V_TICK_LEN * SMALL_CHAR_W)) &&
            (pixel_ypos >= base_y) &&
            (pixel_ypos < base_y + (10 * V_TICK_STEP) + SMALL_CHAR_H)) begin
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

task try_u_rms_line_region;
    input [10:0] base_x;
    input [10:0] base_y;
    reg   [10:0] delta_x;
    begin
        if (!text_en &&
            (pixel_xpos >= base_x) && (pixel_xpos < base_x + (LINE2_LEN * SMALL_CHAR_W)) &&
            (pixel_ypos >= base_y) && (pixel_ypos < base_y + SMALL_CHAR_H)) begin
            delta_x         = pixel_xpos - base_x;
            line_slot       = small_text_slot(delta_x, LINE2_LEN);
            text_en         = 1'b1;
            text_font_small = 1'b1;
            text_char_idx   = ascii_to_idx(u_rms_line_ascii(line_slot));
            text_color      = WAVE_U_COLOR;
            text_rel_x      = small_text_rel_x(delta_x);
            text_rel_y      = pixel_ypos - base_y;
        end
    end
endtask

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
    try_big_text_region(AUTO_TXT_X,  AUTO_TXT_Y,  AUTO_LEN,  TEXT_WHITE, AUTO_STR);
    try_big_text_region(PLOT_TXT_X,  PLOT_TXT_Y,  PLOT_LEN,  TEXT_SOFT,  PLOT_STR);

    try_small_text_region(AXIS_V_X, AXIS_V_Y, AXIS_V_LEN, WAVE_U_COLOR, AXIS_V_STR);
    try_small_text_region(AXIS_I_X, AXIS_I_Y, AXIS_I_LEN, WAVE_I_COLOR, AXIS_I_STR);
    try_voltage_tick_region(V_TICK_X, V_TICK_Y0);
    try_current_tick_region(I_TICK_X, I_TICK_Y0);

    try_small_text_region(AXIS_TICK0_X, AXIS_TICK_Y, T_TICK_LEN, TEXT_DIM, "-40");
    try_small_text_region(AXIS_TICK1_X, AXIS_TICK_Y, T_TICK_LEN, TEXT_DIM, "-30");
    try_small_text_region(AXIS_TICK2_X, AXIS_TICK_Y, T_TICK_LEN, TEXT_DIM, "-20");
    try_small_text_region(AXIS_TICK3_X, AXIS_TICK_Y, T_TICK_LEN, TEXT_DIM, "-10");
    try_small_text_region(AXIS_TICK4_X, AXIS_TICK_Y, T_TICK_LEN, TEXT_DIM, "  0");
    try_small_text_region(AXIS_T_X, AXIS_T_Y, AXIS_T_LEN, TEXT_DIM, AXIS_T_STR);

    try_small_text_region(RP_TITLE_X, RP_TITLE_Y, RP_HEAD_LEN, ACCENT_COLOR, RP_HEAD_STR);
    try_small_text_region(LEGEND1_X, LEGEND1_Y, LEGEND_U_LEN, WAVE_U_COLOR, LEGEND_U_STR);
    try_small_text_region(LEGEND2_X, LEGEND2_Y, LEGEND_I_LEN, WAVE_I_COLOR, LEGEND_I_STR);
    try_small_text_region(LINE_X, LINE_Y0, LINE1_LEN, TEXT_SOFT, LINE1_STR);
    try_u_rms_line_region(LINE_X, LINE_Y0 + LINE_STEP);
    try_small_text_region(LINE_X, LINE_Y0 + (LINE_STEP * 2), LINE3_LEN, WAVE_I_COLOR, LINE3_STR);
    try_small_text_region(LINE_X, LINE_Y0 + (LINE_STEP * 3), LINE4_LEN, TEXT_WHITE, LINE4_STR);
end

endmodule
