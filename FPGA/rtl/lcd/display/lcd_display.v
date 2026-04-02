/*
 * Module: lcd_display
 * Function:
 *   Thin top-level wrapper for the LCD page. The module keeps the original
 *   external interface, while delegating waveform capture, background drawing
 *   and text decoding to dedicated submodules.
 */
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
    input      [7:0]   wave_sample_code,
    input      [7:0]   wave_zero_code,
    input              wave_zero_valid,
    input      [10:0]  pixel_xpos,
    input      [10:0]  pixel_ypos,
    output reg [23:0]  pixel_data
);

localparam [5:0] BIG_CHAR_W   = 6'd16;
localparam [5:0] SMALL_CHAR_W = 6'd10;
localparam [6:0] FONT_BLANK   = 7'd127;
localparam [23:0] BG_COLOR    = 24'h0B1524;
localparam [23:0] TEXT_WHITE  = 24'hF2F6FA;
localparam [23:0] WAVE_U_COLOR = 24'h39E46F;
localparam [10:0] GRAPH_X      = 11'd36;
localparam [10:0] GRAPH_Y      = 11'd144;
localparam [10:0] GRAPH_W      = 11'd384;
localparam [10:0] GRAPH_H      = 11'd240;

reg  [23:0] base_color_d1;
reg  [23:0] text_color_d1;
reg         text_en_d1;
reg         text_font_small_d1;
reg  [5:0]  text_rel_x_d1;
reg         text_blank_d1;
reg  [7:0]  u_rms_tens_lcd;
reg  [7:0]  u_rms_units_lcd;
reg  [7:0]  u_rms_decile_lcd;
reg  [7:0]  u_rms_percentiles_lcd;
reg         u_rms_digits_valid_lcd;
reg         wave_graph_en_d1;
reg  [8:0]  wave_graph_col_d1;
reg  [10:0] wave_pixel_y_d1;
reg         wave_prev_valid_d1;
reg  [7:0]  wave_prev_y_d1;
reg  [8:0]  wave_prev_col_d1;
reg  [10:0] wave_prev_row_d1;
reg         wave_display_bank_sync1;
reg         wave_display_bank_sync2;
reg         wave_frame_valid_sync1;
reg         wave_frame_valid_sync2;

wire [23:0] base_color;
wire [23:0] text_color;
wire        text_en;
wire        text_font_small;
wire [6:0]  text_char_idx;
wire [5:0]  text_rel_x;
wire [5:0]  text_rel_y;
wire        text_blank;
wire        text_pixel_on;
wire        wave_frame_valid;
wire        wave_display_bank;
wire [7:0]  u_rms_tens;
wire [7:0]  u_rms_units;
wire [7:0]  u_rms_decile;
wire [7:0]  u_rms_percentiles;
wire        u_rms_digits_valid;
wire        wave_ram_we;
wire [9:0]  wave_ram_waddr;
wire [7:0]  wave_ram_wdata;
wire [7:0]  wave_ram_douta;
wire [7:0]  wave_ram_doutb;
wire        wave_graph_en;
wire [10:0] wave_graph_col_ext;
wire [8:0]  wave_graph_col;
wire [9:0]  wave_ram_raddr;
wire [10:0] wave_y_curr_abs;
wire [10:0] wave_y_prev_abs;
wire        wave_seg_valid;
wire [10:0] wave_seg_lo_abs;
wire [10:0] wave_seg_hi_abs;
wire        wave_pixel_on;

wire [11:0] text_char_idx_ext;
wire [11:0] font_addr_16x32;
wire [11:0] font_addr_10x20_wide;
wire [15:0] font_row_16x32;
wire [11:0] font_row_10x20_raw;
wire [9:0]  font_row_10x20;

wave_frame_capture u_wave_frame_capture(
    .wave_clk          (wave_clk),
    .sys_rst_n         (sys_rst_n),
    .wave_sample_code  (wave_sample_code),
    .wave_zero_code    (wave_zero_code),
    .wave_zero_valid   (wave_zero_valid),
    .u_rms_tens        (u_rms_tens),
    .u_rms_units       (u_rms_units),
    .u_rms_decile      (u_rms_decile),
    .u_rms_percentiles (u_rms_percentiles),
    .u_rms_digits_valid(u_rms_digits_valid),
    .wave_frame_valid  (wave_frame_valid),
    .wave_display_bank (wave_display_bank),
    .wave_ram_we       (wave_ram_we),
    .wave_ram_waddr    (wave_ram_waddr),
    .wave_ram_wdata    (wave_ram_wdata)
);

lcd_display_bg u_lcd_display_bg(
    .pixel_xpos (pixel_xpos),
    .pixel_ypos (pixel_ypos),
    .base_color (base_color)
);

lcd_display_text u_lcd_display_text(
    .pixel_xpos          (pixel_xpos),
    .pixel_ypos          (pixel_ypos),
    .u_rms_tens          (u_rms_tens_lcd),
    .u_rms_units         (u_rms_units_lcd),
    .u_rms_decile        (u_rms_decile_lcd),
    .u_rms_percentiles   (u_rms_percentiles_lcd),
    .u_rms_digits_valid  (u_rms_digits_valid_lcd),
    .text_en             (text_en),
    .text_font_small     (text_font_small),
    .text_char_idx       (text_char_idx),
    .text_rel_x          (text_rel_x),
    .text_rel_y          (text_rel_y),
    .text_color          (text_color)
);

blk_mem_gen_font_16x32 u_font_16x32(
    .clka (lcd_pclk),
    .addra(font_addr_16x32),
    .douta(font_row_16x32)
);

blk_mem_gen_font_10x20 u_font_10x20(
    .clka (lcd_pclk),
    .ena  (1'b1),
    .addra(font_addr_10x20_wide[10:0]),
    .douta(font_row_10x20_raw)
);

blk_mem_gen_ram0 u_wave_frame_ram(
    .clka  (wave_clk),
    .ena   (1'b1),
    .wea   ({wave_ram_we}),
    .addra (wave_ram_waddr),
    .dina  (wave_ram_wdata),
    .douta (wave_ram_douta),
    .clkb  (lcd_pclk),
    .web   ({1'b0}),
    .addrb (wave_ram_raddr),
    .dinb  (8'd0),
    .doutb (wave_ram_doutb)
);

assign text_blank        = (text_char_idx == FONT_BLANK);
assign text_char_idx_ext = text_blank ? 12'd0 : {5'd0, text_char_idx};
assign font_addr_16x32   = (text_char_idx_ext << 5) + {6'd0, text_rel_y};
assign font_addr_10x20_wide = (text_char_idx_ext << 4) + (text_char_idx_ext << 2) + {6'd0, text_rel_y};
assign font_row_10x20    = font_row_10x20_raw[9:0];
assign wave_graph_en     = (pixel_xpos >= GRAPH_X) && (pixel_xpos < (GRAPH_X + GRAPH_W)) &&
                           (pixel_ypos > GRAPH_Y) && (pixel_ypos < (GRAPH_Y + GRAPH_H - 1));
assign wave_graph_col_ext = pixel_xpos - GRAPH_X;
assign wave_graph_col    = wave_graph_col_ext[8:0];
assign wave_ram_raddr    = wave_graph_en ? {wave_display_bank_sync2, wave_graph_col} :
                                           {wave_display_bank_sync2, 9'd0};
assign wave_y_curr_abs   = GRAPH_Y + {3'd0, wave_ram_doutb};
assign wave_y_prev_abs   = GRAPH_Y + {3'd0, wave_prev_y_d1};
assign wave_seg_valid    = wave_prev_valid_d1 &&
                           wave_graph_en_d1 &&
                           (wave_prev_row_d1 == wave_pixel_y_d1) &&
                           ((wave_prev_col_d1 + 9'd1) == wave_graph_col_d1);
assign wave_seg_lo_abs   = (wave_y_curr_abs < wave_y_prev_abs) ? wave_y_curr_abs : wave_y_prev_abs;
assign wave_seg_hi_abs   = (wave_y_curr_abs < wave_y_prev_abs) ? wave_y_prev_abs : wave_y_curr_abs;

assign text_pixel_on =
    text_en_d1 && !text_blank_d1 &&
    (text_font_small_d1 ?
        ((text_rel_x_d1 < SMALL_CHAR_W) ? font_row_10x20[9 - text_rel_x_d1[3:0]] : 1'b0) :
        ((text_rel_x_d1 < BIG_CHAR_W)   ? font_row_16x32[15 - text_rel_x_d1[3:0]] : 1'b0));

assign wave_pixel_on =
    wave_graph_en_d1 && wave_frame_valid_sync2 &&
    (((wave_graph_col_d1 == 9'd0) || !wave_seg_valid) ?
        ((wave_pixel_y_d1 >= (wave_y_curr_abs - 11'd1)) &&
         (wave_pixel_y_d1 <= (wave_y_curr_abs + 11'd1))) :
        ((wave_pixel_y_d1 >= (wave_seg_lo_abs - 11'd1)) &&
         (wave_pixel_y_d1 <= (wave_seg_hi_abs + 11'd1))));

always @(posedge lcd_pclk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        base_color_d1      <= BG_COLOR;
        text_color_d1      <= TEXT_WHITE;
        text_en_d1         <= 1'b0;
        text_font_small_d1 <= 1'b0;
        text_rel_x_d1      <= 6'd0;
        text_blank_d1      <= 1'b1;
        u_rms_tens_lcd     <= 8'd0;
        u_rms_units_lcd    <= 8'd0;
        u_rms_decile_lcd   <= 8'd0;
        u_rms_percentiles_lcd <= 8'd0;
        u_rms_digits_valid_lcd <= 1'b0;
        wave_graph_en_d1   <= 1'b0;
        wave_graph_col_d1  <= 9'd0;
        wave_pixel_y_d1    <= 11'd0;
        wave_prev_valid_d1 <= 1'b0;
        wave_prev_y_d1     <= 8'd0;
        wave_prev_col_d1   <= 9'd0;
        wave_prev_row_d1   <= 11'd0;
        wave_display_bank_sync1 <= 1'b0;
        wave_display_bank_sync2 <= 1'b0;
        wave_frame_valid_sync1  <= 1'b0;
        wave_frame_valid_sync2  <= 1'b0;
        pixel_data         <= BG_COLOR;
    end else begin
        wave_display_bank_sync1 <= wave_display_bank;
        wave_display_bank_sync2 <= wave_display_bank_sync1;
        wave_frame_valid_sync1  <= wave_frame_valid;
        wave_frame_valid_sync2  <= wave_frame_valid_sync1;

        base_color_d1      <= base_color;
        text_color_d1      <= text_color;
        text_en_d1         <= text_en;
        text_font_small_d1 <= text_font_small;
        text_rel_x_d1      <= text_rel_x;
        text_blank_d1      <= text_blank;

        if (u_rms_digits_valid) begin
            u_rms_tens_lcd        <= u_rms_tens;
            u_rms_units_lcd       <= u_rms_units;
            u_rms_decile_lcd      <= u_rms_decile;
            u_rms_percentiles_lcd <= u_rms_percentiles;
            u_rms_digits_valid_lcd <= 1'b1;
        end

        wave_graph_en_d1   <= wave_graph_en;
        wave_graph_col_d1  <= wave_graph_col;
        wave_pixel_y_d1    <= pixel_ypos;

        if (wave_graph_en_d1 && wave_frame_valid_sync2) begin
            wave_prev_valid_d1 <= 1'b1;
            wave_prev_y_d1     <= wave_ram_doutb;
            wave_prev_col_d1   <= wave_graph_col_d1;
            wave_prev_row_d1   <= wave_pixel_y_d1;
        end else begin
            wave_prev_valid_d1 <= 1'b0;
        end

        if (text_pixel_on)
            pixel_data <= text_color_d1;
        else if (wave_pixel_on)
            pixel_data <= WAVE_U_COLOR;
        else
            pixel_data <= base_color_d1;
    end
end

endmodule
