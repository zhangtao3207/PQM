/*
 * Module: lcd_display
 * 文本布局:
 *   Line1: X:xxxx   Y:yyyy
 *   Line2: STATE: <PRESSED/UNPRESSED/CLICK/LONG/DRAG>
 *   Line3: DRAG 时显示 START: X/Y；否则显示 PRESS TIME: ttttMS
 *   Line4: UART 接收文本（rx_line_ascii，16 字符，ASCII→字库索引映射）
 * 说明:
 *   - 字符大小 16x32，采用 font_rom 索引到 512b glyph 再做逐像素取样。
 *   - 槽位(slot*)由像素x坐标高位决定，用于选择本列字符索引。
 */
`include "font_rom.v"
module lcd_display(
    input             lcd_pclk,
    input             sys_rst_n,
    input      [31:0] data,
    input      [15:0] touch_x,
    input      [15:0] touch_y,
    input      [4:0]  touch_state_bits,
    input      [15:0] start_x_bcd,
    input      [15:0] start_y_bcd,
    input      [15:0] press_time_bcd,
    input      [127:0] rx_line_ascii,
    input      [10:0] pixel_xpos,
    input      [10:0] pixel_ypos,
    output reg [23:0] pixel_data
);

localparam CHAR_POS_X    = 11'd1;
localparam CHAR_POS_Y    = 11'd1;
localparam CHAR_WIDTH    = 11'd16;
localparam CHAR_HEIGHT   = 11'd32;
localparam LINE1_CHARS   = 11'd15;
localparam LINE2_CHARS   = 11'd16;
localparam LINE3_CHARS   = 11'd23;
localparam LINE4_CHARS   = 11'd16;
localparam LINE1_WIDTH   = LINE1_CHARS * CHAR_WIDTH;
localparam LINE2_WIDTH   = LINE2_CHARS * CHAR_WIDTH;
localparam LINE3_WIDTH   = LINE3_CHARS * CHAR_WIDTH;
localparam LINE4_WIDTH   = LINE4_CHARS * CHAR_WIDTH;
localparam LINE2_POS_Y   = CHAR_POS_Y + CHAR_HEIGHT + 11'd4;
localparam LINE3_POS_Y   = LINE2_POS_Y + CHAR_HEIGHT + 11'd4;
localparam LINE4_POS_Y   = LINE3_POS_Y + CHAR_HEIGHT + 11'd4;

localparam WHITE         = 24'hFFFFFF;
localparam BLACK         = 24'h000000;
localparam FONT_BLANK    = 7'd127;
localparam DRAW_X_SHIFT  = 3;
localparam DRAW_Y_SHIFT  = 3;
localparam DRAW_W        = 160;
localparam DRAW_H        = 100;
localparam DRAW_SIZE     = DRAW_W * DRAW_H;

wire [3:0] x3, x2, x1, x0;
wire [3:0] y3, y2, y1, y0;
wire [3:0] sx3, sx2, sx1, sx0;
wire [3:0] sy3, sy2, sy1, sy0;
wire [3:0] t3, t2, t1, t0;
wire [10:0] rel_x1, rel_x2, rel_x3, rel_x4;
wire [5:0] slot1, slot2, slot3, slot4;
wire in_line1, in_line2, in_line3, in_line4;
wire drag_state;
wire [7:0] draw_touch_x;
wire [6:0] draw_touch_y;
wire       draw_touch_valid;
wire [7:0] draw_pixel_x;
wire [6:0] draw_pixel_y;
wire       drag_pixel;

reg  [6:0] idx1, idx2, idx3, idx4;
reg  [2:0] state_sel;
reg         drag_state_d;
reg  [DRAW_SIZE-1:0] drag_bitmap;
wire [511:0] glyph1, glyph2, glyph3, glyph4;

assign x3 = data[31:28];
assign x2 = data[27:24];
assign x1 = data[23:20];
assign x0 = data[19:16];
assign y3 = data[15:12];
assign y2 = data[11:8];
assign y1 = data[7:4];
assign y0 = data[3:0];

assign sx3 = start_x_bcd[15:12];
assign sx2 = start_x_bcd[11:8];
assign sx1 = start_x_bcd[7:4];
assign sx0 = start_x_bcd[3:0];
assign sy3 = start_y_bcd[15:12];
assign sy2 = start_y_bcd[11:8];
assign sy1 = start_y_bcd[7:4];
assign sy0 = start_y_bcd[3:0];
assign t3  = press_time_bcd[15:12];
assign t2  = press_time_bcd[11:8];
assign t1  = press_time_bcd[7:4];
assign t0  = press_time_bcd[3:0];

assign rel_x1 = pixel_xpos - (CHAR_POS_X - 11'd1);
assign rel_x2 = rel_x1;
assign rel_x3 = rel_x1;
assign rel_x4 = rel_x1;
assign slot1  = rel_x1[10:4];
assign slot2  = rel_x2[10:4];
assign slot3  = rel_x3[10:4];
assign slot4  = rel_x4[10:4];
assign drag_state = touch_state_bits[0];
assign draw_touch_x = touch_x[15:DRAW_X_SHIFT];
assign draw_touch_y = touch_y[15:DRAW_Y_SHIFT];
assign draw_touch_valid = (touch_x < (DRAW_W << DRAW_X_SHIFT)) && (touch_y < (DRAW_H << DRAW_Y_SHIFT));
assign draw_pixel_x = pixel_xpos[10:DRAW_X_SHIFT];
assign draw_pixel_y = pixel_ypos[10:DRAW_Y_SHIFT];
assign drag_pixel = (draw_pixel_x < DRAW_W) && (draw_pixel_y < DRAW_H)
                 && drag_bitmap[draw_pixel_y * DRAW_W + draw_pixel_x];

assign in_line1 = (pixel_xpos >= CHAR_POS_X - 11'd1) && (pixel_xpos < CHAR_POS_X + LINE1_WIDTH - 11'd1)
               && (pixel_ypos >= CHAR_POS_Y) && (pixel_ypos < CHAR_POS_Y + CHAR_HEIGHT);
assign in_line2 = (pixel_xpos >= CHAR_POS_X - 11'd1) && (pixel_xpos < CHAR_POS_X + LINE2_WIDTH - 11'd1)
               && (pixel_ypos >= LINE2_POS_Y) && (pixel_ypos < LINE2_POS_Y + CHAR_HEIGHT);
assign in_line3 = (pixel_xpos >= CHAR_POS_X - 11'd1) && (pixel_xpos < CHAR_POS_X + LINE3_WIDTH - 11'd1)
               && (pixel_ypos >= LINE3_POS_Y) && (pixel_ypos < LINE3_POS_Y + CHAR_HEIGHT);
assign in_line4 = (pixel_xpos >= CHAR_POS_X - 11'd1) && (pixel_xpos < CHAR_POS_X + LINE4_WIDTH - 11'd1)
               && (pixel_ypos >= LINE4_POS_Y) && (pixel_ypos < LINE4_POS_Y + CHAR_HEIGHT);

font_rom u_font1(.char_idx(idx1), .glyph(glyph1));
font_rom u_font2(.char_idx(idx2), .glyph(glyph2));
font_rom u_font3(.char_idx(idx3), .glyph(glyph3));
font_rom u_font4(.char_idx(idx4), .glyph(glyph4));

always @(posedge lcd_pclk or negedge sys_rst_n) begin
    if(!sys_rst_n) begin
        drag_state_d <= 1'b0;
        drag_bitmap  <= {DRAW_SIZE{1'b0}};
    end
    else begin
        drag_state_d <= drag_state;

        if(!drag_state && drag_state_d) begin
            drag_bitmap <= {DRAW_SIZE{1'b0}};
        end
        else if(drag_state && draw_touch_valid) begin
            drag_bitmap[draw_touch_y * DRAW_W + draw_touch_x] <= 1'b1;
        end
    end
end

function [6:0] ascii_to_idx;
    input [7:0] ch;
    begin
        if(ch >= "0" && ch <= "9")
            ascii_to_idx = {3'd0, ch - "0"};
        else if(ch >= "A" && ch <= "Z")
            ascii_to_idx = 7'd10 + (ch - "A");
        else if(ch >= "a" && ch <= "z")
            ascii_to_idx = 7'd36 + (ch - "a");
        else if(ch == ":")
            ascii_to_idx = 7'd87;
        else if(ch == " ")
            ascii_to_idx = FONT_BLANK;
        else
            ascii_to_idx = FONT_BLANK;
    end
endfunction

always @(*) begin
    case(slot1)
        6'd0: idx1 = 7'd33; // X
        6'd1: idx1 = 7'd87; // :
        6'd2: idx1 = {3'd0, x3};
        6'd3: idx1 = {3'd0, x2};
        6'd4: idx1 = {3'd0, x1};
        6'd5: idx1 = {3'd0, x0};
        6'd6,6'd7,6'd8: idx1 = FONT_BLANK;
        6'd9: idx1 = 7'd34; // Y
        6'd10: idx1 = 7'd87; // :
        6'd11: idx1 = {3'd0, y3};
        6'd12: idx1 = {3'd0, y2};
        6'd13: idx1 = {3'd0, y1};
        6'd14: idx1 = {3'd0, y0};
        default: idx1 = FONT_BLANK;
    endcase
end

always @(*) begin
    if(touch_state_bits[0]) state_sel = 3'd1;
    else if(touch_state_bits[1]) state_sel = 3'd2;
    else if(touch_state_bits[2]) state_sel = 3'd3;
    else if(touch_state_bits[4]) state_sel = 3'd0;
    else state_sel = 3'd4;
end

always @(*) begin
    case(slot4)
        6'd0 : idx4 = ascii_to_idx(rx_line_ascii[ ( (LINE4_CHARS-1-6'd0)  *8) +:8]);
        6'd1 : idx4 = ascii_to_idx(rx_line_ascii[ ( (LINE4_CHARS-1-6'd1)  *8) +:8]);
        6'd2 : idx4 = ascii_to_idx(rx_line_ascii[ ( (LINE4_CHARS-1-6'd2)  *8) +:8]);
        6'd3 : idx4 = ascii_to_idx(rx_line_ascii[ ( (LINE4_CHARS-1-6'd3)  *8) +:8]);
        6'd4 : idx4 = ascii_to_idx(rx_line_ascii[ ( (LINE4_CHARS-1-6'd4)  *8) +:8]);
        6'd5 : idx4 = ascii_to_idx(rx_line_ascii[ ( (LINE4_CHARS-1-6'd5)  *8) +:8]);
        6'd6 : idx4 = ascii_to_idx(rx_line_ascii[ ( (LINE4_CHARS-1-6'd6)  *8) +:8]);
        6'd7 : idx4 = ascii_to_idx(rx_line_ascii[ ( (LINE4_CHARS-1-6'd7)  *8) +:8]);
        6'd8 : idx4 = ascii_to_idx(rx_line_ascii[ ( (LINE4_CHARS-1-6'd8)  *8) +:8]);
        6'd9 : idx4 = ascii_to_idx(rx_line_ascii[ ( (LINE4_CHARS-1-6'd9)  *8) +:8]);
        6'd10: idx4 = ascii_to_idx(rx_line_ascii[ ( (LINE4_CHARS-1-6'd10) *8) +:8]);
        6'd11: idx4 = ascii_to_idx(rx_line_ascii[ ( (LINE4_CHARS-1-6'd11) *8) +:8]);
        6'd12: idx4 = ascii_to_idx(rx_line_ascii[ ( (LINE4_CHARS-1-6'd12) *8) +:8]);
        6'd13: idx4 = ascii_to_idx(rx_line_ascii[ ( (LINE4_CHARS-1-6'd13) *8) +:8]);
        6'd14: idx4 = ascii_to_idx(rx_line_ascii[ ( (LINE4_CHARS-1-6'd14) *8) +:8]);
        6'd15: idx4 = ascii_to_idx(rx_line_ascii[ ( (LINE4_CHARS-1-6'd15) *8) +:8]);
        default: idx4 = FONT_BLANK;
    endcase
end

always @(*) begin
    case(slot2)
        6'd0: idx2 = 7'd28; // S
        6'd1: idx2 = 7'd29; // T
        6'd2: idx2 = 7'd10; // A
        6'd3: idx2 = 7'd29; // T
        6'd4: idx2 = 7'd14; // E
        6'd5: idx2 = 7'd87; // :
        6'd6: idx2 = FONT_BLANK;
        default: begin
            case(state_sel)
                3'd0: begin // PRESSED
                    case(slot2)
                        6'd7: idx2=7'd25; 6'd8: idx2=7'd27; 6'd9: idx2=7'd14;
                        6'd10: idx2=7'd28; 6'd11: idx2=7'd28; 6'd12: idx2=7'd14; 6'd13: idx2=7'd13;
                        default: idx2=FONT_BLANK;
                    endcase
                end
                3'd1: begin // DRAG
                    case(slot2)
                        6'd7: idx2=7'd13; 6'd8: idx2=7'd27; 6'd9: idx2=7'd10; 6'd10: idx2=7'd16;
                        default: idx2=FONT_BLANK;
                    endcase
                end
                3'd2: begin // LONG
                    case(slot2)
                        6'd7: idx2=7'd21; 6'd8: idx2=7'd24; 6'd9: idx2=7'd23; 6'd10: idx2=7'd16;
                        default: idx2=FONT_BLANK;
                    endcase
                end
                3'd3: begin // CLICK
                    case(slot2)
                        6'd7: idx2=7'd12; 6'd8: idx2=7'd21; 6'd9: idx2=7'd18; 6'd10: idx2=7'd12; 6'd11: idx2=7'd20;
                        default: idx2=FONT_BLANK;
                    endcase
                end
                default: begin // UNPRESSED
                    case(slot2)
                        6'd7: idx2=7'd30; 6'd8: idx2=7'd23; 6'd9: idx2=7'd25; 6'd10: idx2=7'd27;
                        6'd11: idx2=7'd14; 6'd12: idx2=7'd28; 6'd13: idx2=7'd28; 6'd14: idx2=7'd14; 6'd15: idx2=7'd13;
                        default: idx2=FONT_BLANK;
                    endcase
                end
            endcase
        end
    endcase
end

always @(*) begin
    if(drag_state) begin
        case(slot3)
            6'd0: idx3=7'd28; 6'd1: idx3=7'd29; 6'd2: idx3=7'd10; 6'd3: idx3=7'd27; 6'd4: idx3=7'd29;
            6'd5: idx3=7'd87; 6'd6,6'd7: idx3=FONT_BLANK;
            6'd8: idx3=7'd33; 6'd9: idx3=7'd87;
            6'd10: idx3={3'd0,sx3}; 6'd11: idx3={3'd0,sx2}; 6'd12: idx3={3'd0,sx1}; 6'd13: idx3={3'd0,sx0};
            6'd14,6'd15,6'd16: idx3=FONT_BLANK;
            6'd17: idx3=7'd34; 6'd18: idx3=7'd87;
            6'd19: idx3={3'd0,sy3}; 6'd20: idx3={3'd0,sy2}; 6'd21: idx3={3'd0,sy1}; 6'd22: idx3={3'd0,sy0};
            default: idx3=FONT_BLANK;
        endcase
    end else begin
        case(slot3)
            6'd0: idx3=7'd25; 6'd1: idx3=7'd27; 6'd2: idx3=7'd14; 6'd3: idx3=7'd28; 6'd4: idx3=7'd28;
            6'd5: idx3=FONT_BLANK;
            6'd6: idx3=7'd29; 6'd7: idx3=7'd18; 6'd8: idx3=7'd22; 6'd9: idx3=7'd14;
            6'd10: idx3=7'd87; 6'd11: idx3=FONT_BLANK;
            6'd12: idx3={3'd0,t3}; 6'd13: idx3={3'd0,t2}; 6'd14: idx3={3'd0,t1}; 6'd15: idx3={3'd0,t0};
            6'd16: idx3=7'd48; 6'd17: idx3=7'd54;
            default: idx3=FONT_BLANK;
        endcase
    end
end

always @(posedge lcd_pclk or negedge sys_rst_n) begin
    if(!sys_rst_n)
        pixel_data <= BLACK;
    else if(drag_pixel)
        pixel_data <= BLACK;
    else if(in_line1) begin
        if(glyph1[(CHAR_HEIGHT + CHAR_POS_Y - pixel_ypos) * 16 - (rel_x1 % 16) - 11'd1])
            pixel_data <= BLACK;
        else
            pixel_data <= WHITE;
    end
    else if(in_line2) begin
        if(glyph2[(CHAR_HEIGHT + LINE2_POS_Y - pixel_ypos) * 16 - (rel_x2 % 16) - 11'd1])
            pixel_data <= BLACK;
        else
            pixel_data <= WHITE;
    end
    else if(in_line3) begin
        if(glyph3[(CHAR_HEIGHT + LINE3_POS_Y - pixel_ypos) * 16 - (rel_x3 % 16) - 11'd1])
            pixel_data <= BLACK;
        else
            pixel_data <= WHITE;
    end
    else if(in_line4) begin
        if(glyph4[(CHAR_HEIGHT + LINE4_POS_Y - pixel_ypos) * 16 - (rel_x4 % 16) - 11'd1])
            pixel_data <= BLACK;
        else
            pixel_data <= WHITE;
    end
    else
        pixel_data <= WHITE;
end

endmodule
