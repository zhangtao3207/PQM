/*
 * 模块: lcd_display_bg
 * 功能:
 *   生成 LCD 页面背景层颜色。
 *
 * 输入:
 *   pixel_xpos: 当前扫描像素的 X 坐标。
 *   pixel_ypos: 当前扫描像素的 Y 坐标。
 *   freeze_button_pressed: 信号。
 *
 * 输出:
 *   base_color: 背景层颜色输出。
 */
module lcd_display_bg(
    input      [10:0] pixel_xpos,
    input      [10:0] pixel_ypos,
    input             freeze_button_pressed,
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
localparam [10:0] GRAPH_X     = 11'd36;
localparam [10:0] GRAPH_Y     = 11'd144;
localparam [10:0] GRAPH_W     = 11'd384;
localparam [10:0] GRAPH_H     = 11'd240;
localparam [10:0] GRAPH_CY    = 11'd264;
localparam [10:0] GRID_X_STEP = 11'd96;
localparam [10:0] GRID_Y_STEP = 11'd40;
localparam [10:0] GRID_X_1    = GRAPH_X + GRID_X_STEP;
localparam [10:0] GRID_X_2    = GRAPH_X + (GRID_X_STEP * 2);
localparam [10:0] GRID_X_3    = GRAPH_X + (GRID_X_STEP * 3);
localparam [10:0] GRID_Y_1    = GRAPH_Y + GRID_Y_STEP;
localparam [10:0] GRID_Y_2    = GRAPH_Y + (GRID_Y_STEP * 2);
localparam [10:0] GRID_Y_3    = GRAPH_Y + (GRID_Y_STEP * 3);
localparam [10:0] GRID_Y_4    = GRAPH_Y + (GRID_Y_STEP * 4);
localparam [10:0] GRID_Y_5    = GRAPH_Y + (GRID_Y_STEP * 5);
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

wire graph_inner;

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
        base_color = BUTTON_BG;

    if (on_rect_border(BTN_X, BTN_Y, BTN_W, BTN_H))
        base_color = BUTTON_BORDER;

    if (in_rect(AUTO_X, AUTO_Y, AUTO_W, AUTO_H))
        base_color = freeze_button_pressed ? BUTTON_BG_PRESSED : BUTTON_BG;

    if (on_rect_border(AUTO_X, AUTO_Y, AUTO_W, AUTO_H))
        base_color = BUTTON_BORDER;

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

    if ((pixel_xpos >= RIGHT_X + 11'd12) && (pixel_xpos < RIGHT_X + RIGHT_W - 11'd12) &&
        ((pixel_ypos == LINE_Y0 + 11'd24) ||
         (pixel_ypos == LINE_Y0 + LINE_STEP + 11'd24) ||
         (pixel_ypos == LINE_Y0 + (LINE_STEP * 2) + 11'd24) ||
         (pixel_ypos == LINE_Y0 + (LINE_STEP * 3) + 11'd24) ||
         (pixel_ypos == LINE_Y0 + (LINE_STEP * 4) + 11'd24) ||
         (pixel_ypos == LINE_Y0 + (LINE_STEP * 5) + 11'd24) ||
         (pixel_ypos == LINE_Y0 + (LINE_STEP * 6) + 11'd24)))
        base_color = SEPARATOR_CLR;
end

endmodule
