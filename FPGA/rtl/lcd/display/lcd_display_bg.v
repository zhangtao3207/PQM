/*
 * 模块: lcd_display_bg
 * 功能:
 *   生成 LCD 页面背景层颜色。
 *
 * 输入:
 *   pixel_xpos: 当前扫描像素的 X 坐标。
 *   pixel_ypos: 当前扫描像素的 Y 坐标。
 *   frequency_page_active: 当前是否显示频域页面。
 *   mode_button_pressed: MODE 按钮当前是否被按下。
 *   freeze_button_pressed: Freeze/Auto 按钮当前是否被按下。
 *   harmonic_prev_pressed: 频域页上一组谐波按钮当前是否被按下。
 *   harmonic_next_pressed: 频域页下一组谐波按钮当前是否被按下。
 *
 * 输出:
 *   base_color: 背景层颜色输出。
 */
module lcd_display_bg(
    input      [10:0] pixel_xpos,
    input      [10:0] pixel_ypos,
    input             frequency_page_active,
    input             mode_button_pressed,
    input             freeze_button_pressed,
    input             harmonic_prev_pressed,
    input             harmonic_next_pressed,
    output reg [23:0] base_color
);

// 茅隆碌茅聺垄盲陆驴莽聰篓氓聢掳莽職聞盲赂禄猫娄聛茅聟聧猫聣虏茫聙聜
localparam [23:0] BG_COLOR      = 24'h0B1524;
localparam [23:0] TITLE_BG      = 24'h173B63;
localparam [23:0] PANEL_DARK    = 24'h101A28;
localparam [23:0] PANEL_BORDER  = 24'h4F6D8F;
localparam [23:0] GRAPH_BG      = 24'h020406;
localparam [23:0] GRAPH_GRID    = 24'h243645;
localparam [23:0] GRAPH_AXIS    = 24'h8EA7BF;
localparam [23:0] GRAPH_Y_AXIS  = 24'hEAF3FF;
localparam [23:0] BUTTON_BG     = 24'h49617E;
localparam [23:0] BUTTON_BG_PRESSED = 24'h3D536D;
localparam [23:0] BUTTON_BORDER = 24'hDEE9F5;
localparam [23:0] WAVE_U_COLOR  = 24'h39E46F;
localparam [23:0] WAVE_I_COLOR  = 24'hFFD84E;
localparam [23:0] ACCENT_COLOR  = 24'h58B6FF;
localparam [23:0] SEPARATOR_CLR = 24'h243243;

// 氓聬聞莽聲聦茅聺垄氓聦潞氓聼聼莽職聞氓聺聬忙聽聡盲赂聨氓掳潞氓炉赂氓聫聜忙聲掳茫聙聜
localparam [10:0] TITLE_BAR_H = 11'd44;
localparam [10:0] LEFT_X      = 11'd0;
localparam [10:0] LEFT_Y      = 11'd64;
localparam [10:0] LEFT_W      = 11'd480;
localparam [10:0] LEFT_H      = 11'd392;
localparam [10:0] RIGHT_X     = 11'd500;
localparam [10:0] RIGHT_Y     = 11'd64;
localparam [10:0] RIGHT_W     = 11'd276;
localparam [10:0] RIGHT_H     = 11'd392;
localparam [10:0] DIVIDER_X   = 11'd486;
localparam [10:0] DIVIDER_W   = 11'd4;
localparam [10:0] GRAPH_X     = 11'd66;
localparam [10:0] GRAPH_Y     = 11'd144;
localparam [10:0] GRAPH_W     = 11'd354;
localparam [10:0] GRAPH_H     = 11'd240;
localparam [10:0] GRAPH_CY    = 11'd264;
localparam [10:0] GRID_X_STEP = 11'd96;
localparam [10:0] GRID_Y_STEP = 11'd40;
localparam [10:0] GRID_X_1    = GRAPH_X + GRID_X_STEP;
localparam [10:0] GRID_X_2    = GRID_X_1 + GRID_X_STEP;
localparam [10:0] GRID_X_3    = GRID_X_2 + GRID_X_STEP;
localparam [10:0] GRID_Y_1    = GRAPH_Y + GRID_Y_STEP;
localparam [10:0] GRID_Y_2    = GRID_Y_1 + GRID_Y_STEP;
localparam [10:0] GRID_Y_3    = GRID_Y_2 + GRID_Y_STEP;
localparam [10:0] GRID_Y_4    = GRID_Y_3 + GRID_Y_STEP;
localparam [10:0] GRID_Y_5    = GRID_Y_4 + GRID_Y_STEP;
localparam [10:0] BTN_X       = 11'd572;
localparam [10:0] BTN_Y       = 11'd6;
localparam [10:0] BTN_W       = 11'd87;
localparam [10:0] BTN_H       = 11'd32;
localparam [10:0] AUTO_X      = 11'd672;
localparam [10:0] AUTO_Y      = 11'd6;
localparam [10:0] AUTO_W      = 11'd110;
localparam [10:0] AUTO_H      = 11'd32;
localparam [10:0] LINE_Y0     = 11'd114;
localparam [10:0] LINE_STEP   = 11'd28;
localparam [10:0] LINE_Y1     = LINE_Y0 + LINE_STEP;
localparam [10:0] LINE_Y2     = LINE_Y1 + LINE_STEP;
localparam [10:0] LINE_Y3     = LINE_Y2 + LINE_STEP;
localparam [10:0] LINE_Y4     = LINE_Y3 + LINE_STEP;
localparam [10:0] LINE_Y5     = LINE_Y4 + LINE_STEP;
localparam [10:0] LINE_Y6     = LINE_Y5 + LINE_STEP;

// 频域页布局坐标，与 rtl/lcd/lcd.html 中的预览稿保持一致。
localparam [10:0] FREQ_GRAPH_X       = 11'd50;
localparam [10:0] FREQ_GRAPH_W       = 11'd440;
localparam [10:0] FREQ_MAG_Y         = 11'd144;
localparam [10:0] FREQ_MAG_H         = 11'd182;
localparam [10:0] FREQ_PHASE_Y       = 11'd344;
localparam [10:0] FREQ_PHASE_H       = 11'd80;
localparam [10:0] FREQ_GRID_X_STEP   = 11'd55;
localparam [10:0] FREQ_MAG_Y_STEP    = 11'd26;
localparam [10:0] FREQ_PHASE_Y_STEP  = 11'd20;
localparam [10:0] FREQ_GRID_X1       = FREQ_GRAPH_X + FREQ_GRID_X_STEP;
localparam [10:0] FREQ_GRID_X2       = FREQ_GRID_X1 + FREQ_GRID_X_STEP;
localparam [10:0] FREQ_GRID_X3       = FREQ_GRID_X2 + FREQ_GRID_X_STEP;
localparam [10:0] FREQ_GRID_X4       = FREQ_GRID_X3 + FREQ_GRID_X_STEP;
localparam [10:0] FREQ_GRID_X5       = FREQ_GRID_X4 + FREQ_GRID_X_STEP;
localparam [10:0] FREQ_GRID_X6       = FREQ_GRID_X5 + FREQ_GRID_X_STEP;
localparam [10:0] FREQ_GRID_X7       = FREQ_GRID_X6 + FREQ_GRID_X_STEP;
localparam [10:0] FREQ_MAG_Y1        = FREQ_MAG_Y + FREQ_MAG_Y_STEP;
localparam [10:0] FREQ_MAG_Y2        = FREQ_MAG_Y1 + FREQ_MAG_Y_STEP;
localparam [10:0] FREQ_MAG_Y3        = FREQ_MAG_Y2 + FREQ_MAG_Y_STEP;
localparam [10:0] FREQ_MAG_Y4        = FREQ_MAG_Y3 + FREQ_MAG_Y_STEP;
localparam [10:0] FREQ_MAG_Y5        = FREQ_MAG_Y4 + FREQ_MAG_Y_STEP;
localparam [10:0] FREQ_MAG_Y6        = FREQ_MAG_Y5 + FREQ_MAG_Y_STEP;
localparam [10:0] FREQ_PHASE_Y1      = FREQ_PHASE_Y + FREQ_PHASE_Y_STEP;
localparam [10:0] FREQ_PHASE_Y2      = FREQ_PHASE_Y1 + FREQ_PHASE_Y_STEP;
localparam [10:0] FREQ_PHASE_Y3      = FREQ_PHASE_Y2 + FREQ_PHASE_Y_STEP;
localparam [10:0] HARM_PREV_X        = 11'd325;
localparam [10:0] HARM_NEXT_X        = 11'd375;
localparam [10:0] HARM_BTN_Y         = 11'd180;
localparam [10:0] HARM_BTN_W         = 11'd38;
localparam [10:0] HARM_BTN_H         = 11'd28;

wire graph_inner;
wire freq_mag_inner;
wire freq_phase_inner;

// 氓聢陇忙聳颅氓陆聯氓聣聧氓聝聫莽麓聽忙聵炉氓聬娄盲陆聧盲潞聨忙聼聬盲赂陋莽聼漏氓陆垄氓聠聟茅聝篓茫聙聜
function in_rect;
    input [10:0] x0;
    input [10:0] y0;
    input [10:0] w;
    input [10:0] h;
    begin
        in_rect = (pixel_xpos >= x0) && (pixel_xpos < x0 + w) &&
                  (pixel_ypos >= y0) && (pixel_ypos < y0 + h);
    end
endfunction

// 氓聢陇忙聳颅氓陆聯氓聣聧氓聝聫莽麓聽忙聵炉氓聬娄盲陆聧盲潞聨莽聼漏氓陆垄猫戮鹿忙隆聠盲赂聤茫聙聜
function on_rect_border;
    input [10:0] x0;
    input [10:0] y0;
    input [10:0] w;
    input [10:0] h;
    begin
        on_rect_border = in_rect(x0, y0, w, h) &&
                         ((pixel_xpos == x0) || (pixel_xpos == x0 + w - 1) ||
                          (pixel_ypos == y0) || (pixel_ypos == y0 + h - 1));
    end
endfunction

assign graph_inner = (pixel_xpos > GRAPH_X) && (pixel_xpos < GRAPH_X + GRAPH_W - 1) &&
                     (pixel_ypos > GRAPH_Y) && (pixel_ypos < GRAPH_Y + GRAPH_H - 1);
assign freq_mag_inner = (pixel_xpos > FREQ_GRAPH_X) && (pixel_xpos < FREQ_GRAPH_X + FREQ_GRAPH_W - 1) &&
                        (pixel_ypos > FREQ_MAG_Y) && (pixel_ypos < FREQ_MAG_Y + FREQ_MAG_H - 1);
assign freq_phase_inner = (pixel_xpos > FREQ_GRAPH_X) && (pixel_xpos < FREQ_GRAPH_X + FREQ_GRAPH_W - 1) &&
                          (pixel_ypos > FREQ_PHASE_Y) && (pixel_ypos < FREQ_PHASE_Y + FREQ_PHASE_H - 1);

// 莽禄聞氓聬聢莽禄聵氓聢露茅隆潞氓潞聫茂录職氓潞聲猫聣虏 -> 茅聺垄忙聺驴/忙聦聣茅聮庐 -> 氓聺聬忙聽聡氓聦潞 -> 莽陆聭忙聽录盲赂聨氓聺聬忙聽聡猫陆麓茫聙聜
always @(*) begin
    base_color = BG_COLOR;

    if (pixel_ypos < TITLE_BAR_H)
        base_color = TITLE_BG;

    if ((pixel_ypos == TITLE_BAR_H - 1) && (pixel_xpos < 11'd800))
        base_color = ACCENT_COLOR;

    if (in_rect(RIGHT_X, RIGHT_Y, RIGHT_W, RIGHT_H))
        base_color = PANEL_DARK;

    if (in_rect(DIVIDER_X, LEFT_Y, DIVIDER_W, LEFT_H))
        base_color = PANEL_BORDER;

    if (on_rect_border(RIGHT_X, RIGHT_Y, RIGHT_W, RIGHT_H))
        base_color = PANEL_BORDER;

    if (in_rect(BTN_X, BTN_Y, BTN_W, BTN_H))
        base_color = mode_button_pressed ? BUTTON_BG_PRESSED : BUTTON_BG;

    if (on_rect_border(BTN_X, BTN_Y, BTN_W, BTN_H))
        base_color = BUTTON_BORDER;

    if (in_rect(AUTO_X, AUTO_Y, AUTO_W, AUTO_H))
        base_color = freeze_button_pressed ? BUTTON_BG_PRESSED : BUTTON_BG;

    if (on_rect_border(AUTO_X, AUTO_Y, AUTO_W, AUTO_H))
        base_color = BUTTON_BORDER;

    if (frequency_page_active) begin
        if (in_rect(FREQ_GRAPH_X, FREQ_MAG_Y, FREQ_GRAPH_W, FREQ_MAG_H))
            base_color = GRAPH_BG;

        if (in_rect(FREQ_GRAPH_X, FREQ_PHASE_Y, FREQ_GRAPH_W, FREQ_PHASE_H))
            base_color = GRAPH_BG;

        if ((freq_mag_inner || freq_phase_inner) &&
            ((pixel_xpos == FREQ_GRID_X1) || (pixel_xpos == FREQ_GRID_X2) ||
             (pixel_xpos == FREQ_GRID_X3) || (pixel_xpos == FREQ_GRID_X4) ||
             (pixel_xpos == FREQ_GRID_X5) || (pixel_xpos == FREQ_GRID_X6) ||
             (pixel_xpos == FREQ_GRID_X7)))
            base_color = GRAPH_GRID;

        if (freq_mag_inner &&
            ((pixel_ypos == FREQ_MAG_Y1) || (pixel_ypos == FREQ_MAG_Y2) ||
             (pixel_ypos == FREQ_MAG_Y3) || (pixel_ypos == FREQ_MAG_Y4) ||
             (pixel_ypos == FREQ_MAG_Y5) || (pixel_ypos == FREQ_MAG_Y6)))
            base_color = GRAPH_GRID;

        if (freq_phase_inner &&
            ((pixel_ypos == FREQ_PHASE_Y1) || (pixel_ypos == FREQ_PHASE_Y2) ||
             (pixel_ypos == FREQ_PHASE_Y3)))
            base_color = GRAPH_GRID;

        if (on_rect_border(FREQ_GRAPH_X, FREQ_MAG_Y, FREQ_GRAPH_W, FREQ_MAG_H))
            base_color = PANEL_BORDER;

        if (on_rect_border(FREQ_GRAPH_X, FREQ_PHASE_Y, FREQ_GRAPH_W, FREQ_PHASE_H))
            base_color = PANEL_BORDER;

        if (in_rect(HARM_PREV_X, HARM_BTN_Y, HARM_BTN_W, HARM_BTN_H))
            base_color = harmonic_prev_pressed ? BUTTON_BG_PRESSED : BUTTON_BG;

        if (on_rect_border(HARM_PREV_X, HARM_BTN_Y, HARM_BTN_W, HARM_BTN_H))
            base_color = BUTTON_BORDER;

        if (in_rect(HARM_NEXT_X, HARM_BTN_Y, HARM_BTN_W, HARM_BTN_H))
            base_color = harmonic_next_pressed ? BUTTON_BG_PRESSED : BUTTON_BG;

        if (on_rect_border(HARM_NEXT_X, HARM_BTN_Y, HARM_BTN_W, HARM_BTN_H))
            base_color = BUTTON_BORDER;
    end
    else begin
        if (in_rect(GRAPH_X, GRAPH_Y, GRAPH_W, GRAPH_H))
            base_color = GRAPH_BG;

        if (on_rect_border(GRAPH_X, GRAPH_Y, GRAPH_W, GRAPH_H))
            base_color = PANEL_BORDER;

        if (graph_inner &&
            ((pixel_xpos == GRID_X_1) || (pixel_xpos == GRID_X_2) || (pixel_xpos == GRID_X_3) ||
             (pixel_ypos == GRID_Y_1) || (pixel_ypos == GRID_Y_2) ||
             (pixel_ypos == GRID_Y_4) || (pixel_ypos == GRID_Y_5)))
            base_color = GRAPH_GRID;

        if (((pixel_xpos > GRAPH_X) && (pixel_xpos < GRAPH_X + GRAPH_W - 1)) &&
            (pixel_ypos == GRAPH_CY))
            base_color = GRAPH_AXIS;

        if (((pixel_ypos > GRAPH_Y) && (pixel_ypos < GRAPH_Y + GRAPH_H - 1)) &&
            ((pixel_xpos == GRAPH_X) || (pixel_xpos == GRAPH_X + GRAPH_W - 1)))
            base_color = GRAPH_Y_AXIS;
    end

    if ((pixel_xpos >= RIGHT_X + 11'd12) && (pixel_xpos < RIGHT_X + RIGHT_W - 11'd12) &&
        ((pixel_ypos == LINE_Y0 + 11'd24) ||
         (pixel_ypos == LINE_Y0 + LINE_STEP + 11'd24) ||
         (pixel_ypos == LINE_Y2 + 11'd24) ||
         (pixel_ypos == LINE_Y3 + 11'd24) ||
         (pixel_ypos == LINE_Y4 + 11'd24) ||
         (pixel_ypos == LINE_Y5 + 11'd24) ||
         (pixel_ypos == LINE_Y6 + 11'd24)))
        base_color = SEPARATOR_CLR;
end

endmodule
