/*
 * Module: lcd_display
 * 功能说明:
 *   该模块根据当前像素坐标直接输出 LCD 像素颜色。
 *   模块不负责 LCD 时序，只负责描述“当前这个像素应该显示什么”。
 *
 * 当前界面内容:
 *   1. 顶部标题栏，显示模式标题以及 Freeze / Auto 两个按钮；
 *   2. 左侧时域分析坐标区，仅保留网格、坐标轴、刻度与标题，不绘制波形线；
 *   3. 右侧参数区，仅保留 Parameterss、U/I 图例和 4 行参数文字；
 *   4. 右侧 Voltage 条目由 ADC_TEMP 链路输出的数字实时刷新。
 *
 * 设计约束:
 *   1. 文字字符集限制在 ASCII 范围内，因此界面文本保持英文；
 *   2. 顶部标题、按钮和左侧主标题使用 16x32 字模；
 *   3. 坐标轴文字、刻度和右侧参数区使用 10x20 字模。
 */
`include "font_rom_16x32.v"
`include "font_rom_10x20.v"

module lcd_display(
    input              lcd_pclk,
    input              sys_rst_n,
    input      [31:0]  data,
    input      [15:0]  touch_x,
    input      [15:0]  touch_y,
    input      [4:0]   touch_state_bits,
    input      [15:0]  start_x_bcd,
    input      [15:0]  start_y_bcd,
    input      [15:0]  press_time_bcd,
    input      [127:0] rx_line_ascii,
    input              wave_clk,
    input      [7:0]   wave_avg_code,
    input              wave_avg_valid,
    input      [7:0]   wave_zero_code,
    input              wave_zero_valid,
    input      [7:0]   voltage_tens,
    input      [7:0]   voltage_units,
    input      [7:0]   voltage_decile,
    input      [7:0]   voltage_percentiles,
    input              voltage_symbol,
    input              voltage_digits_valid,
    input      [10:0]  pixel_xpos,
    input      [10:0]  pixel_ypos,
    output reg [23:0]  pixel_data
);

// ============================================================================
// 输入兼容说明
// ============================================================================
// data / touch_x / touch_y / touch_state_bits / start_x_bcd / start_y_bcd /
// press_time_bcd / rx_line_ascii 当前版本未参与显示，仅为保持上层接口兼容。

// ============================================================================
// 字模参数与字符索引
// ============================================================================
localparam BIG_CHAR_W   = 11'd16;
localparam BIG_CHAR_H   = 11'd32;
localparam SMALL_CHAR_W = 11'd10;
localparam SMALL_CHAR_H = 11'd20;

localparam FONT_BLANK      = 7'd127;
localparam FONT_DIGIT_BASE = 7'd0;
localparam FONT_UPPER_BASE = 7'd10;
localparam FONT_LOWER_BASE = 7'd36;
localparam FONT_LPAREN     = 7'd71;
localparam FONT_RPAREN     = 7'd72;
localparam FONT_UNDERSCORE = 7'd73;
localparam FONT_PLUS       = 7'd74;
localparam FONT_MINUS      = 7'd75;
localparam FONT_DOT        = 7'd84;
localparam FONT_SLASH      = 7'd85;
localparam FONT_COLON      = 7'd89;

// ============================================================================
// 颜色定义，与 lcd.html 保持一致
// ============================================================================
localparam BG_COLOR      = 24'h0B1524;
localparam TITLE_BG      = 24'h173B63;
localparam PANEL_BG      = 24'h142235;
localparam PANEL_DARK    = 24'h101A28;
localparam PANEL_BORDER  = 24'h4F6D8F;
localparam GRAPH_BG      = 24'h020406;
localparam GRAPH_GRID    = 24'h243645;
localparam GRAPH_AXIS    = 24'h8EA7BF;
localparam GRAPH_Y_AXIS  = 24'hEAF3FF;
localparam TEXT_WHITE    = 24'hF2F6FA;
localparam TEXT_SOFT     = 24'hC6D3E2;
localparam TEXT_DIM      = 24'h95A9BE;
localparam BUTTON_BG     = 24'h49617E;
localparam BUTTON_BORDER = 24'hDEE9F5;
localparam WAVE_U_COLOR  = 24'h39E46F;
localparam WAVE_I_COLOR  = 24'hFFD84E;
localparam ACCENT_COLOR  = 24'h58B6FF;
localparam SEPARATOR_CLR = 24'h243243;

// ============================================================================
// 布局参数，与 lcd.html 保持一致
// ============================================================================
localparam TITLE_BAR_H = 11'd44;

localparam LEFT_X = 11'd0;
localparam LEFT_Y = 11'd64;
localparam LEFT_W = 11'd480;
localparam LEFT_H = 11'd392;

localparam RIGHT_X = 11'd500;
localparam RIGHT_Y = 11'd64;
localparam RIGHT_W = 11'd276;
localparam RIGHT_H = 11'd392;

localparam DIVIDER_X = 11'd486;
localparam DIVIDER_W = 11'd4;

localparam GRAPH_X      = 11'd36;
localparam GRAPH_Y      = 11'd144;
localparam GRAPH_W      = 11'd384;
localparam GRAPH_H      = 11'd240;
localparam GRAPH_CY     = 11'd264;
localparam GRID_X_STEP  = 11'd96;
localparam GRID_Y_STEP  = 11'd40;

localparam TITLE_TXT_X  = 11'd32;
localparam TITLE_TXT_Y  = 11'd6;
localparam BTN_X        = 11'd572;
localparam BTN_Y        = 11'd6;
localparam BTN_W        = 11'd102;
localparam BTN_H        = 11'd32;
localparam BTN_TXT_X    = 11'd578;
localparam BTN_TXT_Y    = 11'd6;
localparam AUTO_X       = 11'd692;
localparam AUTO_Y       = 11'd6;
localparam AUTO_W       = 11'd80;
localparam AUTO_H       = 11'd32;
localparam AUTO_TXT_X   = 11'd700;
localparam AUTO_TXT_Y   = 11'd6;

localparam PLOT_TXT_X   = 11'd68;
localparam PLOT_TXT_Y   = 11'd72;
localparam AXIS_V_X     = 11'd40;
localparam AXIS_V_Y     = 11'd118;
localparam AXIS_I_X     = 11'd306;
localparam AXIS_I_Y     = 11'd118;
localparam AXIS_TICK0_X = 11'd36;
localparam AXIS_TICK1_X = 11'd117;
localparam AXIS_TICK2_X = 11'd213;
localparam AXIS_TICK3_X = 11'd309;
localparam AXIS_TICK4_X = 11'd389;
localparam AXIS_TICK_Y  = 11'd392;
localparam AXIS_T_X     = 11'd336;
localparam AXIS_T_Y     = 11'd416;
localparam V_TICK_X     = 11'd12;
localparam V_TICK_Y0    = 11'd134;
localparam V_TICK_STEP  = 11'd24;
localparam I_TICK_X     = 11'd424;
localparam I_TICK_Y0    = 11'd134;
localparam I_TICK_STEP  = 11'd40;

localparam RP_TITLE_X   = 11'd520;
localparam RP_TITLE_Y   = 11'd76;
localparam LEGEND1_X    = 11'd560;
localparam LEGEND1_Y    = 11'd112;
localparam LEGEND2_X    = 11'd676;
localparam LEGEND2_Y    = 11'd112;
localparam LINE_X       = 11'd516;
localparam LINE_Y0      = 11'd144;
localparam LINE_STEP    = 11'd30;

// ============================================================================
// 示波器式波形显示参数
// 40ms 窗口下使用 384 个重采样点，右边界是触发时刻 t=0。
// adc_avg_valid 当前来自 64 点均值输出，等效 390625SPS；
// 40ms 内共有 15625 个均值样本，因此用分数抽取得到恰好 384 列。
// ============================================================================
localparam integer WAVE_POINT_COUNT  = 384;
localparam integer WAVE_FRAME_TICKS  = 15625;
localparam [7:0] WAVE_TRIGGER_HYST   = 8'd2;
localparam integer GRAPH_HALF_H      = 120;

// ============================================================================
// 字符串长度
// ============================================================================
localparam TITLE_LEN    = 19;
localparam BTN_LEN      = 6;
localparam AUTO_LEN     = 4;
localparam PLOT_LEN     = 20;
localparam AXIS_V_LEN   = 12;
localparam AXIS_I_LEN   = 11;
localparam AXIS_T_LEN   = 8;
localparam V_TICK_LEN   = 2;
localparam I_TICK_LEN   = 4;
localparam T_TICK_LEN   = 3;
localparam RP_HEAD_LEN  = 10;
localparam LEGEND_U_LEN = 1;
localparam LEGEND_I_LEN = 1;
localparam LINE1_LEN    = 17;
localparam LINE2_LEN    = 19;
localparam LINE3_LEN    = 17;
localparam LINE4_LEN    = 22;

// ============================================================================
// 固定字符串
// ============================================================================
localparam [8*TITLE_LEN-1:0]    TITLE_STR    = "MODE: Single - Time";
localparam [8*BTN_LEN-1:0]      BTN_STR      = "Freeze";
localparam [8*AUTO_LEN-1:0]     AUTO_STR     = "Auto";
localparam [8*PLOT_LEN-1:0]     PLOT_STR     = "Time Domain Analysis";
localparam [8*AXIS_V_LEN-1:0]   AXIS_V_STR   = "Voltage ( V)";
localparam [8*AXIS_I_LEN-1:0]   AXIS_I_STR   = "Current (A)";
localparam [8*AXIS_T_LEN-1:0]   AXIS_T_STR   = "Time(ms)";

localparam [8*V_TICK_LEN-1:0]   V_TICK0_STR  = "+5";
localparam [8*V_TICK_LEN-1:0]   V_TICK1_STR  = "+4";
localparam [8*V_TICK_LEN-1:0]   V_TICK2_STR  = "+3";
localparam [8*V_TICK_LEN-1:0]   V_TICK3_STR  = "+2";
localparam [8*V_TICK_LEN-1:0]   V_TICK4_STR  = "+1";
localparam [8*V_TICK_LEN-1:0]   V_TICK5_STR  = " 0";
localparam [8*V_TICK_LEN-1:0]   V_TICK6_STR  = "-1";
localparam [8*V_TICK_LEN-1:0]   V_TICK7_STR  = "-2";
localparam [8*V_TICK_LEN-1:0]   V_TICK8_STR  = "-3";
localparam [8*V_TICK_LEN-1:0]   V_TICK9_STR  = "-4";
localparam [8*V_TICK_LEN-1:0]   V_TICK10_STR = "-5";

localparam [8*I_TICK_LEN-1:0]   I_TICK0_STR  = "+0.3";
localparam [8*I_TICK_LEN-1:0]   I_TICK1_STR  = "+0.2";
localparam [8*I_TICK_LEN-1:0]   I_TICK2_STR  = "+0.1";
localparam [8*I_TICK_LEN-1:0]   I_TICK3_STR  = " 0.0";
localparam [8*I_TICK_LEN-1:0]   I_TICK4_STR  = "-0.1";
localparam [8*I_TICK_LEN-1:0]   I_TICK5_STR  = "-0.2";
localparam [8*I_TICK_LEN-1:0]   I_TICK6_STR  = "-0.3";

localparam [8*T_TICK_LEN-1:0]   T_TICK0_STR  = "-40";
localparam [8*T_TICK_LEN-1:0]   T_TICK1_STR  = "-30";
localparam [8*T_TICK_LEN-1:0]   T_TICK2_STR  = "-20";
localparam [8*T_TICK_LEN-1:0]   T_TICK3_STR  = "-10";
localparam [8*T_TICK_LEN-1:0]   T_TICK4_STR  = "  0";

localparam [8*RP_HEAD_LEN-1:0]  RP_HEAD_STR  = "Parameters";
localparam [8*LEGEND_U_LEN-1:0] LEGEND_U_STR = "U";
localparam [8*LEGEND_I_LEN-1:0] LEGEND_I_STR = "I";
localparam [8*LINE1_LEN-1:0]    LINE1_STR    = "Sampling: 5 (KPS)";
localparam [8*LINE3_LEN-1:0]    LINE3_STR    = "Current: 0.03 (A)";
localparam [8*LINE4_LEN-1:0]    LINE4_STR    = "Phase Diff: 0.49 (rad)";

// ============================================================================
// 中间信号
// ============================================================================
reg  [23:0] base_color;
reg  [23:0] text_color;
reg         text_en;
reg         text_font_small;
reg  [6:0]  text_char_idx;
reg  [5:0]  text_rel_x;
reg  [5:0]  text_rel_y;
reg         wave_pixel_on;

reg  [7:0]  wave_y_hist [0:WAVE_POINT_COUNT-1];
reg  [7:0]  wave_y_frame[0:WAVE_POINT_COUNT-1];
reg  [8:0]  wave_wr_ptr;
reg  [15:0] wave_resample_acc;
reg  [7:0]  wave_prev_code;
reg         wave_prev_valid;
reg         wave_hist_full;
reg         wave_frame_valid;

wire [511:0] text_glyph_big;
wire [199:0] text_glyph_small;
wire         text_pixel_on_big;
wire         text_pixel_on_small;
wire         text_pixel_on;
wire [7:0]   wave_zero_eff;
wire [7:0]   wave_trigger_low;
wire [7:0]   wave_trigger_high;
wire [16:0]  wave_resample_sum;

integer line_slot;
integer tick_slot;
integer wave_col;
integer wave_idx_a;
integer wave_idx_b;
integer wave_y_a;
integer wave_y_b;
integer wave_y_lo;
integer wave_y_hi;
integer wave_init_idx;
integer wave_copy_idx;

// ============================================================================
// 字模 ROM
// ============================================================================
font_rom_16x32 u_font_16x32(
    .char_idx(text_char_idx),
    .glyph   (text_glyph_big)
);

font_rom_10x20 u_font_10x20(
    .char_idx(text_char_idx),
    .glyph   (text_glyph_small)
);

assign text_pixel_on_big =
    text_en && !text_font_small &&
    (text_rel_x < BIG_CHAR_W) &&
    (text_rel_y < BIG_CHAR_H) &&
    text_glyph_big[(((BIG_CHAR_H - 11'd1) - text_rel_y) * BIG_CHAR_W) +
                   ((BIG_CHAR_W - 11'd1) - text_rel_x)];

assign text_pixel_on_small =
    text_en && text_font_small &&
    (text_rel_x < SMALL_CHAR_W) &&
    (text_rel_y < SMALL_CHAR_H) &&
    text_glyph_small[(((SMALL_CHAR_H - 11'd1) - text_rel_y) * SMALL_CHAR_W) +
                     ((SMALL_CHAR_W - 11'd1) - text_rel_x)];

assign text_pixel_on = text_pixel_on_big || text_pixel_on_small;
assign wave_zero_eff  = wave_zero_valid ? wave_zero_code : 8'd127;
assign wave_trigger_low  = (wave_zero_eff > WAVE_TRIGGER_HYST) ? (wave_zero_eff - WAVE_TRIGGER_HYST) : 8'd0;
assign wave_trigger_high = (wave_zero_eff < (8'd255 - WAVE_TRIGGER_HYST)) ? (wave_zero_eff + WAVE_TRIGGER_HYST) : 8'd255;
assign wave_resample_sum = wave_resample_acc + WAVE_POINT_COUNT;

// ============================================================================
// ASCII -> 字库索引
// ============================================================================
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

function [7:0] code_to_wave_y;
    input [7:0] sample_code;
    input [7:0] zero_code;
    integer amp_px;
    integer span_code;
    integer y_rel;
    begin
        if (sample_code >= zero_code) begin
            span_code = 256 - zero_code;
            if (span_code <= 0)
                amp_px = 0;
            else
                amp_px = ((sample_code - zero_code) * (GRAPH_HALF_H - 2) + (span_code / 2)) / span_code;
            y_rel = GRAPH_HALF_H - amp_px;
        end else begin
            span_code = zero_code + 1;
            if (span_code <= 0)
                amp_px = 0;
            else
                amp_px = ((zero_code - sample_code) * (GRAPH_HALF_H - 2) + (span_code / 2)) / span_code;
            y_rel = GRAPH_HALF_H + amp_px;
        end

        if (y_rel < 1)
            code_to_wave_y = 8'd1;
        else if (y_rel > GRAPH_H - 2)
            code_to_wave_y = GRAPH_H - 2;
        else
            code_to_wave_y = y_rel[7:0];
    end
endfunction

always @(posedge wave_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        wave_wr_ptr       <= 9'd0;
        wave_resample_acc <= 16'd0;
        wave_prev_code    <= 8'd0;
        wave_prev_valid   <= 1'b0;
        wave_hist_full    <= 1'b0;
        wave_frame_valid  <= 1'b0;
        for (wave_init_idx = 0; wave_init_idx < WAVE_POINT_COUNT; wave_init_idx = wave_init_idx + 1) begin
            wave_y_hist[wave_init_idx]  <= 8'd120;
            wave_y_frame[wave_init_idx] <= 8'd120;
        end
    end else if (wave_avg_valid) begin
        if (wave_resample_sum >= WAVE_FRAME_TICKS) begin
            wave_resample_acc        <= wave_resample_sum - WAVE_FRAME_TICKS;
            wave_y_hist[wave_wr_ptr] <= code_to_wave_y(wave_avg_code, wave_zero_eff);

            if (wave_prev_valid &&
                (wave_prev_code <= wave_trigger_low) &&
                (wave_avg_code  >= wave_trigger_high) &&
                wave_hist_full) begin
                wave_frame_valid <= 1'b1;
                for (wave_copy_idx = 0; wave_copy_idx < WAVE_POINT_COUNT; wave_copy_idx = wave_copy_idx + 1) begin
                    if (wave_copy_idx == (WAVE_POINT_COUNT - 1))
                        wave_y_frame[wave_copy_idx] <= code_to_wave_y(wave_avg_code, wave_zero_eff);
                    else if ((wave_wr_ptr + wave_copy_idx + 1) >= WAVE_POINT_COUNT)
                        wave_y_frame[wave_copy_idx] <= wave_y_hist[wave_wr_ptr + wave_copy_idx + 1 - WAVE_POINT_COUNT];
                    else
                        wave_y_frame[wave_copy_idx] <= wave_y_hist[wave_wr_ptr + wave_copy_idx + 1];
                end
            end

            wave_prev_code  <= wave_avg_code;
            wave_prev_valid <= 1'b1;

            if (wave_wr_ptr == (WAVE_POINT_COUNT - 1)) begin
                wave_wr_ptr    <= 9'd0;
                wave_hist_full <= 1'b1;
            end else begin
                wave_wr_ptr    <= wave_wr_ptr + 9'd1;
            end
        end else begin
            wave_resample_acc <= wave_resample_sum[15:0];
        end
    end
end

always @(*) begin
    wave_pixel_on = 1'b0;
    wave_col      = 0;
    wave_idx_a    = 0;
    wave_idx_b    = 0;
    wave_y_a      = 0;
    wave_y_b      = 0;
    wave_y_lo     = 0;
    wave_y_hi     = 0;

    if (wave_frame_valid &&
        (pixel_xpos >= GRAPH_X) && (pixel_xpos < GRAPH_X + GRAPH_W) &&
        (pixel_ypos > GRAPH_Y) && (pixel_ypos < GRAPH_Y + GRAPH_H - 1)) begin
        wave_col   = pixel_xpos - GRAPH_X;
        wave_idx_a = wave_col;
        wave_y_a   = GRAPH_Y + wave_y_frame[wave_idx_a];

        if (wave_col == 0) begin
            if ((pixel_ypos >= wave_y_a - 1) && (pixel_ypos <= wave_y_a + 1))
                wave_pixel_on = 1'b1;
        end else begin
            wave_idx_b = wave_col - 1;
            wave_y_b   = GRAPH_Y + wave_y_frame[wave_idx_b];
            if (wave_y_a < wave_y_b) begin
                wave_y_lo = wave_y_a;
                wave_y_hi = wave_y_b;
            end else begin
                wave_y_lo = wave_y_b;
                wave_y_hi = wave_y_a;
            end

            if ((pixel_ypos >= wave_y_lo - 1) && (pixel_ypos <= wave_y_hi + 1))
                wave_pixel_on = 1'b1;
        end
    end
end

// ============================================================================
// 背景层
// ============================================================================
always @(*) begin
    base_color = BG_COLOR;

    if (pixel_ypos < TITLE_BAR_H)
        base_color = TITLE_BG;

    if ((pixel_ypos == TITLE_BAR_H - 1) && (pixel_xpos < 11'd800))
        base_color = ACCENT_COLOR;

    if ((pixel_xpos >= LEFT_X) && (pixel_xpos < LEFT_X + LEFT_W) &&
        (pixel_ypos >= LEFT_Y) && (pixel_ypos < LEFT_Y + LEFT_H))
        base_color = PANEL_BG;

    if ((pixel_xpos >= RIGHT_X) && (pixel_xpos < RIGHT_X + RIGHT_W) &&
        (pixel_ypos >= RIGHT_Y) && (pixel_ypos < RIGHT_Y + RIGHT_H))
        base_color = PANEL_DARK;

    if ((pixel_xpos >= DIVIDER_X) && (pixel_xpos < DIVIDER_X + DIVIDER_W) &&
        (pixel_ypos >= LEFT_Y) && (pixel_ypos < LEFT_Y + LEFT_H))
        base_color = PANEL_BORDER;

    if ((pixel_xpos >= RIGHT_X) && (pixel_xpos < RIGHT_X + RIGHT_W) &&
        (pixel_ypos >= RIGHT_Y) && (pixel_ypos < RIGHT_Y + RIGHT_H) &&
        ((pixel_xpos == RIGHT_X) || (pixel_xpos == RIGHT_X + RIGHT_W - 1) ||
         (pixel_ypos == RIGHT_Y) || (pixel_ypos == RIGHT_Y + RIGHT_H - 1)))
        base_color = PANEL_BORDER;

    if ((pixel_xpos >= BTN_X) && (pixel_xpos < BTN_X + BTN_W) &&
        (pixel_ypos >= BTN_Y) && (pixel_ypos < BTN_Y + BTN_H))
        base_color = BUTTON_BG;

    if ((pixel_xpos >= BTN_X) && (pixel_xpos < BTN_X + BTN_W) &&
        (pixel_ypos >= BTN_Y) && (pixel_ypos < BTN_Y + BTN_H) &&
        ((pixel_xpos == BTN_X) || (pixel_xpos == BTN_X + BTN_W - 1) ||
         (pixel_ypos == BTN_Y) || (pixel_ypos == BTN_Y + BTN_H - 1)))
        base_color = BUTTON_BORDER;

    if ((pixel_xpos >= AUTO_X) && (pixel_xpos < AUTO_X + AUTO_W) &&
        (pixel_ypos >= AUTO_Y) && (pixel_ypos < AUTO_Y + AUTO_H))
        base_color = BUTTON_BG;

    if ((pixel_xpos >= AUTO_X) && (pixel_xpos < AUTO_X + AUTO_W) &&
        (pixel_ypos >= AUTO_Y) && (pixel_ypos < AUTO_Y + AUTO_H) &&
        ((pixel_xpos == AUTO_X) || (pixel_xpos == AUTO_X + AUTO_W - 1) ||
         (pixel_ypos == AUTO_Y) || (pixel_ypos == AUTO_Y + AUTO_H - 1)))
        base_color = BUTTON_BORDER;

    if ((pixel_xpos >= GRAPH_X) && (pixel_xpos < GRAPH_X + GRAPH_W) &&
        (pixel_ypos >= GRAPH_Y) && (pixel_ypos < GRAPH_Y + GRAPH_H))
        base_color = GRAPH_BG;

    if ((pixel_xpos >= GRAPH_X) && (pixel_xpos < GRAPH_X + GRAPH_W) &&
        (pixel_ypos >= GRAPH_Y) && (pixel_ypos < GRAPH_Y + GRAPH_H) &&
        ((pixel_xpos == GRAPH_X) || (pixel_xpos == GRAPH_X + GRAPH_W - 1) ||
         (pixel_ypos == GRAPH_Y) || (pixel_ypos == GRAPH_Y + GRAPH_H - 1)))
        base_color = PANEL_BORDER;

    if ((pixel_xpos > GRAPH_X) && (pixel_xpos < GRAPH_X + GRAPH_W - 1) &&
        (pixel_ypos > GRAPH_Y) && (pixel_ypos < GRAPH_Y + GRAPH_H - 1) &&
        ((((pixel_xpos - GRAPH_X) % GRID_X_STEP) == 0) ||
         (((pixel_ypos - GRAPH_Y) % GRID_Y_STEP) == 0)))
        base_color = GRAPH_GRID;

    if ((pixel_xpos > GRAPH_X) && (pixel_xpos < GRAPH_X + GRAPH_W - 1) &&
        (pixel_ypos == GRAPH_CY))
        base_color = GRAPH_AXIS;

    if ((pixel_ypos > GRAPH_Y) && (pixel_ypos < GRAPH_Y + GRAPH_H - 1) &&
        (pixel_xpos == GRAPH_X))
        base_color = GRAPH_Y_AXIS;

    if ((pixel_ypos > GRAPH_Y) && (pixel_ypos < GRAPH_Y + GRAPH_H - 1) &&
        (pixel_xpos == GRAPH_X + GRAPH_W - 1))
        base_color = GRAPH_Y_AXIS;

    if (wave_pixel_on)
        base_color = WAVE_U_COLOR;

    if ((pixel_xpos >= 11'd522) && (pixel_xpos < 11'd550) &&
        (pixel_ypos >= 11'd125) && (pixel_ypos < 11'd129))
        base_color = WAVE_U_COLOR;

    if ((pixel_xpos >= 11'd638) && (pixel_xpos < 11'd666) &&
        (pixel_ypos >= 11'd125) && (pixel_ypos < 11'd129))
        base_color = WAVE_I_COLOR;

    if ((pixel_xpos >= RIGHT_X + 11'd12) && (pixel_xpos < RIGHT_X + RIGHT_W - 11'd12) &&
        ((pixel_ypos == LINE_Y0 + 11'd24) ||
         (pixel_ypos == LINE_Y0 + LINE_STEP + 11'd24) ||
         (pixel_ypos == LINE_Y0 + (LINE_STEP * 2) + 11'd24)))
        base_color = SEPARATOR_CLR;
end

// ============================================================================
// 文字层
// ============================================================================
always @(*) begin
    text_en         = 1'b0;
    text_font_small = 1'b0;
    text_char_idx   = FONT_BLANK;
    text_color      = TEXT_WHITE;
    text_rel_x      = 6'd0;
    text_rel_y      = 6'd0;
    line_slot       = 0;
    tick_slot       = 0;

    if ((pixel_xpos >= TITLE_TXT_X) && (pixel_xpos < TITLE_TXT_X + (TITLE_LEN * BIG_CHAR_W)) &&
        (pixel_ypos >= TITLE_TXT_Y) && (pixel_ypos < TITLE_TXT_Y + BIG_CHAR_H)) begin
        line_slot     = (pixel_xpos - TITLE_TXT_X) >> 4;
        text_en       = 1'b1;
        text_char_idx = ascii_to_idx(TITLE_STR[((TITLE_LEN - 1 - line_slot) * 8) +: 8]);
        text_color    = TEXT_WHITE;
        text_rel_x    = (pixel_xpos - TITLE_TXT_X) & 11'h00F;
        text_rel_y    = pixel_ypos - TITLE_TXT_Y;
    end
    else if ((pixel_xpos >= BTN_TXT_X) && (pixel_xpos < BTN_TXT_X + (BTN_LEN * BIG_CHAR_W)) &&
             (pixel_ypos >= BTN_TXT_Y) && (pixel_ypos < BTN_TXT_Y + BIG_CHAR_H)) begin
        line_slot     = (pixel_xpos - BTN_TXT_X) >> 4;
        text_en       = 1'b1;
        text_char_idx = ascii_to_idx(BTN_STR[((BTN_LEN - 1 - line_slot) * 8) +: 8]);
        text_color    = TEXT_WHITE;
        text_rel_x    = (pixel_xpos - BTN_TXT_X) & 11'h00F;
        text_rel_y    = pixel_ypos - BTN_TXT_Y;
    end
    else if ((pixel_xpos >= AUTO_TXT_X) && (pixel_xpos < AUTO_TXT_X + (AUTO_LEN * BIG_CHAR_W)) &&
             (pixel_ypos >= AUTO_TXT_Y) && (pixel_ypos < AUTO_TXT_Y + BIG_CHAR_H)) begin
        line_slot     = (pixel_xpos - AUTO_TXT_X) >> 4;
        text_en       = 1'b1;
        text_char_idx = ascii_to_idx(AUTO_STR[((AUTO_LEN - 1 - line_slot) * 8) +: 8]);
        text_color    = TEXT_WHITE;
        text_rel_x    = (pixel_xpos - AUTO_TXT_X) & 11'h00F;
        text_rel_y    = pixel_ypos - AUTO_TXT_Y;
    end
    else if ((pixel_xpos >= PLOT_TXT_X) && (pixel_xpos < PLOT_TXT_X + (PLOT_LEN * BIG_CHAR_W)) &&
             (pixel_ypos >= PLOT_TXT_Y) && (pixel_ypos < PLOT_TXT_Y + BIG_CHAR_H)) begin
        line_slot     = (pixel_xpos - PLOT_TXT_X) >> 4;
        text_en       = 1'b1;
        text_char_idx = ascii_to_idx(PLOT_STR[((PLOT_LEN - 1 - line_slot) * 8) +: 8]);
        text_color    = TEXT_SOFT;
        text_rel_x    = (pixel_xpos - PLOT_TXT_X) & 11'h00F;
        text_rel_y    = pixel_ypos - PLOT_TXT_Y;
    end
    else if ((pixel_xpos >= AXIS_V_X) && (pixel_xpos < AXIS_V_X + (AXIS_V_LEN * SMALL_CHAR_W)) &&
             (pixel_ypos >= AXIS_V_Y) && (pixel_ypos < AXIS_V_Y + SMALL_CHAR_H)) begin
        line_slot       = (pixel_xpos - AXIS_V_X) / SMALL_CHAR_W;
        text_en         = 1'b1;
        text_font_small = 1'b1;
        text_char_idx   = ascii_to_idx(AXIS_V_STR[((AXIS_V_LEN - 1 - line_slot) * 8) +: 8]);
        text_color      = WAVE_U_COLOR;
        text_rel_x      = (pixel_xpos - AXIS_V_X) % SMALL_CHAR_W;
        text_rel_y      = pixel_ypos - AXIS_V_Y;
    end
    else if ((pixel_xpos >= AXIS_I_X) && (pixel_xpos < AXIS_I_X + (AXIS_I_LEN * SMALL_CHAR_W)) &&
             (pixel_ypos >= AXIS_I_Y) && (pixel_ypos < AXIS_I_Y + SMALL_CHAR_H)) begin
        line_slot       = (pixel_xpos - AXIS_I_X) / SMALL_CHAR_W;
        text_en         = 1'b1;
        text_font_small = 1'b1;
        text_char_idx   = ascii_to_idx(AXIS_I_STR[((AXIS_I_LEN - 1 - line_slot) * 8) +: 8]);
        text_color      = WAVE_I_COLOR;
        text_rel_x      = (pixel_xpos - AXIS_I_X) % SMALL_CHAR_W;
        text_rel_y      = pixel_ypos - AXIS_I_Y;
    end
    else if ((pixel_xpos >= V_TICK_X) && (pixel_xpos < V_TICK_X + (V_TICK_LEN * SMALL_CHAR_W)) &&
             (pixel_ypos >= V_TICK_Y0) && (pixel_ypos < V_TICK_Y0 + (10 * V_TICK_STEP) + SMALL_CHAR_H) &&
             (((pixel_ypos - V_TICK_Y0) % V_TICK_STEP) < SMALL_CHAR_H)) begin
        tick_slot       = (pixel_ypos - V_TICK_Y0) / V_TICK_STEP;
        line_slot       = (pixel_xpos - V_TICK_X) / SMALL_CHAR_W;
        text_en         = 1'b1;
        text_font_small = 1'b1;
        text_color      = WAVE_U_COLOR;
        text_rel_x      = (pixel_xpos - V_TICK_X) % SMALL_CHAR_W;
        text_rel_y      = (pixel_ypos - V_TICK_Y0) % V_TICK_STEP;
        case (tick_slot)
            0:  text_char_idx = ascii_to_idx(V_TICK0_STR[((V_TICK_LEN - 1 - line_slot) * 8) +: 8]);
            1:  text_char_idx = ascii_to_idx(V_TICK1_STR[((V_TICK_LEN - 1 - line_slot) * 8) +: 8]);
            2:  text_char_idx = ascii_to_idx(V_TICK2_STR[((V_TICK_LEN - 1 - line_slot) * 8) +: 8]);
            3:  text_char_idx = ascii_to_idx(V_TICK3_STR[((V_TICK_LEN - 1 - line_slot) * 8) +: 8]);
            4:  text_char_idx = ascii_to_idx(V_TICK4_STR[((V_TICK_LEN - 1 - line_slot) * 8) +: 8]);
            5:  text_char_idx = ascii_to_idx(V_TICK5_STR[((V_TICK_LEN - 1 - line_slot) * 8) +: 8]);
            6:  text_char_idx = ascii_to_idx(V_TICK6_STR[((V_TICK_LEN - 1 - line_slot) * 8) +: 8]);
            7:  text_char_idx = ascii_to_idx(V_TICK7_STR[((V_TICK_LEN - 1 - line_slot) * 8) +: 8]);
            8:  text_char_idx = ascii_to_idx(V_TICK8_STR[((V_TICK_LEN - 1 - line_slot) * 8) +: 8]);
            9:  text_char_idx = ascii_to_idx(V_TICK9_STR[((V_TICK_LEN - 1 - line_slot) * 8) +: 8]);
            10: text_char_idx = ascii_to_idx(V_TICK10_STR[((V_TICK_LEN - 1 - line_slot) * 8) +: 8]);
            default: text_char_idx = FONT_BLANK;
        endcase
    end
    else if ((pixel_xpos >= I_TICK_X) && (pixel_xpos < I_TICK_X + (I_TICK_LEN * SMALL_CHAR_W)) &&
             (pixel_ypos >= I_TICK_Y0) && (pixel_ypos < I_TICK_Y0 + (6 * I_TICK_STEP) + SMALL_CHAR_H) &&
             (((pixel_ypos - I_TICK_Y0) % I_TICK_STEP) < SMALL_CHAR_H)) begin
        tick_slot       = (pixel_ypos - I_TICK_Y0) / I_TICK_STEP;
        line_slot       = (pixel_xpos - I_TICK_X) / SMALL_CHAR_W;
        text_en         = 1'b1;
        text_font_small = 1'b1;
        text_color      = WAVE_I_COLOR;
        text_rel_x      = (pixel_xpos - I_TICK_X) % SMALL_CHAR_W;
        text_rel_y      = (pixel_ypos - I_TICK_Y0) % I_TICK_STEP;
        case (tick_slot)
            0: text_char_idx = ascii_to_idx(I_TICK0_STR[((I_TICK_LEN - 1 - line_slot) * 8) +: 8]);
            1: text_char_idx = ascii_to_idx(I_TICK1_STR[((I_TICK_LEN - 1 - line_slot) * 8) +: 8]);
            2: text_char_idx = ascii_to_idx(I_TICK2_STR[((I_TICK_LEN - 1 - line_slot) * 8) +: 8]);
            3: text_char_idx = ascii_to_idx(I_TICK3_STR[((I_TICK_LEN - 1 - line_slot) * 8) +: 8]);
            4: text_char_idx = ascii_to_idx(I_TICK4_STR[((I_TICK_LEN - 1 - line_slot) * 8) +: 8]);
            5: text_char_idx = ascii_to_idx(I_TICK5_STR[((I_TICK_LEN - 1 - line_slot) * 8) +: 8]);
            6: text_char_idx = ascii_to_idx(I_TICK6_STR[((I_TICK_LEN - 1 - line_slot) * 8) +: 8]);
            default: text_char_idx = FONT_BLANK;
        endcase
    end
    else if ((pixel_xpos >= AXIS_TICK0_X) && (pixel_xpos < AXIS_TICK0_X + (T_TICK_LEN * SMALL_CHAR_W)) &&
             (pixel_ypos >= AXIS_TICK_Y) && (pixel_ypos < AXIS_TICK_Y + SMALL_CHAR_H)) begin
        line_slot       = (pixel_xpos - AXIS_TICK0_X) / SMALL_CHAR_W;
        text_en         = 1'b1;
        text_font_small = 1'b1;
        text_char_idx   = ascii_to_idx(T_TICK0_STR[((T_TICK_LEN - 1 - line_slot) * 8) +: 8]);
        text_color      = TEXT_DIM;
        text_rel_x      = (pixel_xpos - AXIS_TICK0_X) % SMALL_CHAR_W;
        text_rel_y      = pixel_ypos - AXIS_TICK_Y;
    end
    else if ((pixel_xpos >= AXIS_TICK1_X) && (pixel_xpos < AXIS_TICK1_X + (T_TICK_LEN * SMALL_CHAR_W)) &&
             (pixel_ypos >= AXIS_TICK_Y) && (pixel_ypos < AXIS_TICK_Y + SMALL_CHAR_H)) begin
        line_slot       = (pixel_xpos - AXIS_TICK1_X) / SMALL_CHAR_W;
        text_en         = 1'b1;
        text_font_small = 1'b1;
        text_char_idx   = ascii_to_idx(T_TICK1_STR[((T_TICK_LEN - 1 - line_slot) * 8) +: 8]);
        text_color      = TEXT_DIM;
        text_rel_x      = (pixel_xpos - AXIS_TICK1_X) % SMALL_CHAR_W;
        text_rel_y      = pixel_ypos - AXIS_TICK_Y;
    end
    else if ((pixel_xpos >= AXIS_TICK2_X) && (pixel_xpos < AXIS_TICK2_X + (T_TICK_LEN * SMALL_CHAR_W)) &&
             (pixel_ypos >= AXIS_TICK_Y) && (pixel_ypos < AXIS_TICK_Y + SMALL_CHAR_H)) begin
        line_slot       = (pixel_xpos - AXIS_TICK2_X) / SMALL_CHAR_W;
        text_en         = 1'b1;
        text_font_small = 1'b1;
        text_char_idx   = ascii_to_idx(T_TICK2_STR[((T_TICK_LEN - 1 - line_slot) * 8) +: 8]);
        text_color      = TEXT_DIM;
        text_rel_x      = (pixel_xpos - AXIS_TICK2_X) % SMALL_CHAR_W;
        text_rel_y      = pixel_ypos - AXIS_TICK_Y;
    end
    else if ((pixel_xpos >= AXIS_TICK3_X) && (pixel_xpos < AXIS_TICK3_X + (T_TICK_LEN * SMALL_CHAR_W)) &&
             (pixel_ypos >= AXIS_TICK_Y) && (pixel_ypos < AXIS_TICK_Y + SMALL_CHAR_H)) begin
        line_slot       = (pixel_xpos - AXIS_TICK3_X) / SMALL_CHAR_W;
        text_en         = 1'b1;
        text_font_small = 1'b1;
        text_char_idx   = ascii_to_idx(T_TICK3_STR[((T_TICK_LEN - 1 - line_slot) * 8) +: 8]);
        text_color      = TEXT_DIM;
        text_rel_x      = (pixel_xpos - AXIS_TICK3_X) % SMALL_CHAR_W;
        text_rel_y      = pixel_ypos - AXIS_TICK_Y;
    end
    else if ((pixel_xpos >= AXIS_TICK4_X) && (pixel_xpos < AXIS_TICK4_X + (T_TICK_LEN * SMALL_CHAR_W)) &&
             (pixel_ypos >= AXIS_TICK_Y) && (pixel_ypos < AXIS_TICK_Y + SMALL_CHAR_H)) begin
        line_slot       = (pixel_xpos - AXIS_TICK4_X) / SMALL_CHAR_W;
        text_en         = 1'b1;
        text_font_small = 1'b1;
        text_char_idx   = ascii_to_idx(T_TICK4_STR[((T_TICK_LEN - 1 - line_slot) * 8) +: 8]);
        text_color      = TEXT_DIM;
        text_rel_x      = (pixel_xpos - AXIS_TICK4_X) % SMALL_CHAR_W;
        text_rel_y      = pixel_ypos - AXIS_TICK_Y;
    end
    else if ((pixel_xpos >= AXIS_T_X) && (pixel_xpos < AXIS_T_X + (AXIS_T_LEN * SMALL_CHAR_W)) &&
             (pixel_ypos >= AXIS_T_Y) && (pixel_ypos < AXIS_T_Y + SMALL_CHAR_H)) begin
        line_slot       = (pixel_xpos - AXIS_T_X) / SMALL_CHAR_W;
        text_en         = 1'b1;
        text_font_small = 1'b1;
        text_char_idx   = ascii_to_idx(AXIS_T_STR[((AXIS_T_LEN - 1 - line_slot) * 8) +: 8]);
        text_color      = TEXT_DIM;
        text_rel_x      = (pixel_xpos - AXIS_T_X) % SMALL_CHAR_W;
        text_rel_y      = pixel_ypos - AXIS_T_Y;
    end
    else if ((pixel_xpos >= RP_TITLE_X) && (pixel_xpos < RP_TITLE_X + (RP_HEAD_LEN * SMALL_CHAR_W)) &&
             (pixel_ypos >= RP_TITLE_Y) && (pixel_ypos < RP_TITLE_Y + SMALL_CHAR_H)) begin
        line_slot       = (pixel_xpos - RP_TITLE_X) / SMALL_CHAR_W;
        text_en         = 1'b1;
        text_font_small = 1'b1;
        text_char_idx   = ascii_to_idx(RP_HEAD_STR[((RP_HEAD_LEN - 1 - line_slot) * 8) +: 8]);
        text_color      = ACCENT_COLOR;
        text_rel_x      = (pixel_xpos - RP_TITLE_X) % SMALL_CHAR_W;
        text_rel_y      = pixel_ypos - RP_TITLE_Y;
    end
    else if ((pixel_xpos >= LEGEND1_X) && (pixel_xpos < LEGEND1_X + (LEGEND_U_LEN * SMALL_CHAR_W)) &&
             (pixel_ypos >= LEGEND1_Y) && (pixel_ypos < LEGEND1_Y + SMALL_CHAR_H)) begin
        line_slot       = (pixel_xpos - LEGEND1_X) / SMALL_CHAR_W;
        text_en         = 1'b1;
        text_font_small = 1'b1;
        text_char_idx   = ascii_to_idx(LEGEND_U_STR[((LEGEND_U_LEN - 1 - line_slot) * 8) +: 8]);
        text_color      = WAVE_U_COLOR;
        text_rel_x      = (pixel_xpos - LEGEND1_X) % SMALL_CHAR_W;
        text_rel_y      = pixel_ypos - LEGEND1_Y;
    end
    else if ((pixel_xpos >= LEGEND2_X) && (pixel_xpos < LEGEND2_X + (LEGEND_I_LEN * SMALL_CHAR_W)) &&
             (pixel_ypos >= LEGEND2_Y) && (pixel_ypos < LEGEND2_Y + SMALL_CHAR_H)) begin
        line_slot       = (pixel_xpos - LEGEND2_X) / SMALL_CHAR_W;
        text_en         = 1'b1;
        text_font_small = 1'b1;
        text_char_idx   = ascii_to_idx(LEGEND_I_STR[((LEGEND_I_LEN - 1 - line_slot) * 8) +: 8]);
        text_color      = WAVE_I_COLOR;
        text_rel_x      = (pixel_xpos - LEGEND2_X) % SMALL_CHAR_W;
        text_rel_y      = pixel_ypos - LEGEND2_Y;
    end
    else if ((pixel_xpos >= LINE_X) && (pixel_xpos < LINE_X + (LINE1_LEN * SMALL_CHAR_W)) &&
             (pixel_ypos >= LINE_Y0) && (pixel_ypos < LINE_Y0 + SMALL_CHAR_H)) begin
        line_slot       = (pixel_xpos - LINE_X) / SMALL_CHAR_W;
        text_en         = 1'b1;
        text_font_small = 1'b1;
        text_char_idx   = ascii_to_idx(LINE1_STR[((LINE1_LEN - 1 - line_slot) * 8) +: 8]);
        text_color      = TEXT_SOFT;
        text_rel_x      = (pixel_xpos - LINE_X) % SMALL_CHAR_W;
        text_rel_y      = pixel_ypos - LINE_Y0;
    end
    else if ((pixel_xpos >= LINE_X) && (pixel_xpos < LINE_X + (LINE2_LEN * SMALL_CHAR_W)) &&
             (pixel_ypos >= LINE_Y0 + LINE_STEP) &&
             (pixel_ypos < LINE_Y0 + LINE_STEP + SMALL_CHAR_H)) begin
        line_slot       = (pixel_xpos - LINE_X) / SMALL_CHAR_W;
        text_en         = 1'b1;
        text_font_small = 1'b1;
        text_color      = WAVE_U_COLOR;
        text_rel_x      = (pixel_xpos - LINE_X) % SMALL_CHAR_W;
        text_rel_y      = pixel_ypos - (LINE_Y0 + LINE_STEP);
        case (line_slot)
            0:  text_char_idx = ascii_to_idx("V");
            1:  text_char_idx = ascii_to_idx("o");
            2:  text_char_idx = ascii_to_idx("l");
            3:  text_char_idx = ascii_to_idx("t");
            4:  text_char_idx = ascii_to_idx("a");
            5:  text_char_idx = ascii_to_idx("g");
            6:  text_char_idx = ascii_to_idx("e");
            7:  text_char_idx = ascii_to_idx(":");
            8:  text_char_idx = ascii_to_idx(" ");
            9:  text_char_idx = ascii_to_idx(
                        voltage_digits_valid ?
                        (voltage_symbol ? "-" : " ") :
                        "-"
                    );
            10: text_char_idx = ascii_to_idx(
                        voltage_digits_valid ?
                        ((voltage_tens == 8'd0) ? " " : digit_to_ascii(voltage_tens)) :
                        "-"
                    );
            11: text_char_idx = ascii_to_idx(voltage_digits_valid ? digit_to_ascii(voltage_units) : "-");
            12: text_char_idx = ascii_to_idx(".");
            13: text_char_idx = ascii_to_idx(voltage_digits_valid ? digit_to_ascii(voltage_decile) : "-");
            14: text_char_idx = ascii_to_idx(voltage_digits_valid ? digit_to_ascii(voltage_percentiles) : "-");
            15: text_char_idx = ascii_to_idx(" ");
            16: text_char_idx = ascii_to_idx("(");
            17: text_char_idx = ascii_to_idx("V");
            18: text_char_idx = ascii_to_idx(")");
            default: text_char_idx = FONT_BLANK;
        endcase
    end
    else if ((pixel_xpos >= LINE_X) && (pixel_xpos < LINE_X + (LINE3_LEN * SMALL_CHAR_W)) &&
             (pixel_ypos >= LINE_Y0 + (LINE_STEP * 2)) &&
             (pixel_ypos < LINE_Y0 + (LINE_STEP * 2) + SMALL_CHAR_H)) begin
        line_slot       = (pixel_xpos - LINE_X) / SMALL_CHAR_W;
        text_en         = 1'b1;
        text_font_small = 1'b1;
        text_char_idx   = ascii_to_idx(LINE3_STR[((LINE3_LEN - 1 - line_slot) * 8) +: 8]);
        text_color      = WAVE_I_COLOR;
        text_rel_x      = (pixel_xpos - LINE_X) % SMALL_CHAR_W;
        text_rel_y      = pixel_ypos - (LINE_Y0 + (LINE_STEP * 2));
    end
    else if ((pixel_xpos >= LINE_X) && (pixel_xpos < LINE_X + (LINE4_LEN * SMALL_CHAR_W)) &&
             (pixel_ypos >= LINE_Y0 + (LINE_STEP * 3)) &&
             (pixel_ypos < LINE_Y0 + (LINE_STEP * 3) + SMALL_CHAR_H)) begin
        line_slot       = (pixel_xpos - LINE_X) / SMALL_CHAR_W;
        text_en         = 1'b1;
        text_font_small = 1'b1;
        text_char_idx   = ascii_to_idx(LINE4_STR[((LINE4_LEN - 1 - line_slot) * 8) +: 8]);
        text_color      = TEXT_WHITE;
        text_rel_x      = (pixel_xpos - LINE_X) % SMALL_CHAR_W;
        text_rel_y      = pixel_ypos - (LINE_Y0 + (LINE_STEP * 3));
    end
end

// ============================================================================
// 最终像素输出
// ============================================================================
always @(posedge lcd_pclk or negedge sys_rst_n) begin
    if (!sys_rst_n)
        pixel_data <= BG_COLOR;
    else if (text_pixel_on)
        pixel_data <= text_color;
    else
        pixel_data <= base_color;
end

endmodule
