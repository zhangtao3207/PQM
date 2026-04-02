/*
 * Module: lcd_display_bg
 * Function:
 *   Draw the static page background and overlay the captured voltage trace.
 *   Repeated rectangle tests are wrapped by helper functions to keep the
 *   combinational layer readable.
 */
module lcd_display_bg(
    input      [10:0] pixel_xpos,
    input      [10:0] pixel_ypos,
    output reg [23:0] base_color
);

localparam [23:0] BG_COLOR      = 24'h0B1524;
localparam [23:0] TITLE_BG      = 24'h173B63;
localparam [23:0] PANEL_BG      = 24'h142235;
localparam [23:0] PANEL_DARK    = 24'h101A28;
localparam [23:0] PANEL_BORDER  = 24'h4F6D8F;
localparam [23:0] GRAPH_BG      = 24'h020406;
localparam [23:0] GRAPH_GRID    = 24'h243645;
localparam [23:0] GRAPH_AXIS    = 24'h8EA7BF;
localparam [23:0] GRAPH_Y_AXIS  = 24'hEAF3FF;
localparam [23:0] BUTTON_BG     = 24'h49617E;
localparam [23:0] BUTTON_BORDER = 24'hDEE9F5;
localparam [23:0] WAVE_U_COLOR  = 24'h39E46F;
localparam [23:0] WAVE_I_COLOR  = 24'hFFD84E;
localparam [23:0] ACCENT_COLOR  = 24'h58B6FF;
localparam [23:0] SEPARATOR_CLR = 24'h243243;

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
localparam [10:0] GRID_Y_STEP = 11'd24;
localparam [10:0] GRID_X_1    = GRAPH_X + GRID_X_STEP;
localparam [10:0] GRID_X_2    = GRAPH_X + (GRID_X_STEP * 2);
localparam [10:0] GRID_X_3    = GRAPH_X + (GRID_X_STEP * 3);
localparam [10:0] GRID_Y_1    = GRAPH_Y + GRID_Y_STEP;
localparam [10:0] GRID_Y_2    = GRAPH_Y + (GRID_Y_STEP * 2);
localparam [10:0] GRID_Y_3    = GRAPH_Y + (GRID_Y_STEP * 3);
localparam [10:0] GRID_Y_4    = GRAPH_Y + (GRID_Y_STEP * 4);
localparam [10:0] GRID_Y_5    = GRAPH_Y + (GRID_Y_STEP * 5);
localparam [10:0] GRID_Y_6    = GRAPH_Y + (GRID_Y_STEP * 6);
localparam [10:0] GRID_Y_7    = GRAPH_Y + (GRID_Y_STEP * 7);
localparam [10:0] GRID_Y_8    = GRAPH_Y + (GRID_Y_STEP * 8);
localparam [10:0] GRID_Y_9    = GRAPH_Y + (GRID_Y_STEP * 9);
localparam [10:0] BTN_X       = 11'd572;
localparam [10:0] BTN_Y       = 11'd6;
localparam [10:0] BTN_W       = 11'd102;
localparam [10:0] BTN_H       = 11'd32;
localparam [10:0] AUTO_X      = 11'd692;
localparam [10:0] AUTO_Y      = 11'd6;
localparam [10:0] AUTO_W      = 11'd80;
localparam [10:0] AUTO_H      = 11'd32;
localparam [10:0] LINE_Y0     = 11'd144;
localparam [10:0] LINE_STEP   = 11'd30;

wire graph_inner;

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

always @(*) begin
    base_color = BG_COLOR;

    if (pixel_ypos < TITLE_BAR_H)
        base_color = TITLE_BG;

    if ((pixel_ypos == TITLE_BAR_H - 1) && (pixel_xpos < 11'd800))
        base_color = ACCENT_COLOR;

    if (in_rect(LEFT_X, LEFT_Y, LEFT_W, LEFT_H))
        base_color = PANEL_BG;

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
        base_color = BUTTON_BG;

    if (on_rect_border(AUTO_X, AUTO_Y, AUTO_W, AUTO_H))
        base_color = BUTTON_BORDER;

    if (in_rect(GRAPH_X, GRAPH_Y, GRAPH_W, GRAPH_H))
        base_color = GRAPH_BG;

    if (on_rect_border(GRAPH_X, GRAPH_Y, GRAPH_W, GRAPH_H))
        base_color = PANEL_BORDER;

    if (graph_inner &&
        ((pixel_xpos == GRID_X_1) || (pixel_xpos == GRID_X_2) || (pixel_xpos == GRID_X_3) ||
         (pixel_ypos == GRID_Y_1) || (pixel_ypos == GRID_Y_2) || (pixel_ypos == GRID_Y_3) ||
         (pixel_ypos == GRID_Y_4) || (pixel_ypos == GRID_Y_5) || (pixel_ypos == GRID_Y_6) ||
         (pixel_ypos == GRID_Y_7) || (pixel_ypos == GRID_Y_8) || (pixel_ypos == GRID_Y_9)))
        base_color = GRAPH_GRID;

    if (((pixel_xpos > GRAPH_X) && (pixel_xpos < GRAPH_X + GRAPH_W - 1)) &&
        (pixel_ypos == GRAPH_CY))
        base_color = GRAPH_AXIS;

    if (((pixel_ypos > GRAPH_Y) && (pixel_ypos < GRAPH_Y + GRAPH_H - 1)) &&
        ((pixel_xpos == GRAPH_X) || (pixel_xpos == GRAPH_X + GRAPH_W - 1)))
        base_color = GRAPH_Y_AXIS;

    if (in_rect(11'd522, 11'd125, 11'd28, 11'd4))
        base_color = WAVE_U_COLOR;

    if (in_rect(11'd638, 11'd125, 11'd28, 11'd4))
        base_color = WAVE_I_COLOR;

    if ((pixel_xpos >= RIGHT_X + 11'd12) && (pixel_xpos < RIGHT_X + RIGHT_W - 11'd12) &&
        ((pixel_ypos == LINE_Y0 + 11'd24) ||
         (pixel_ypos == LINE_Y0 + LINE_STEP + 11'd24) ||
         (pixel_ypos == LINE_Y0 + (LINE_STEP * 2) + 11'd24)))
        base_color = SEPARATOR_CLR;
end

endmodule
