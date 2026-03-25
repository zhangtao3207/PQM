/*
 * Module: lcd_rgb_char
 * 概述:
 *   显示子系统封装：ID 读取、像素时钟分频、数值BCD转换、字符栅格渲染与LCD驱动。
 *   第四行用于显示 UART 接收文本（rx_line_ascii），长度 16 字符。
 */
module lcd_rgb_char(
    input              sys_clk,
    input              sys_rst_n,
    input      [31:0]  data,
    input      [4:0]   touch_state_bits,
    input      [15:0]  touch_start_x,
    input      [15:0]  touch_start_y,
    input      [15:0]  touch_press_time_ms,
    input      [127:0] rx_line_ascii,

    output             lcd_hs,
    output             lcd_vs,
    output             lcd_de,
    inout      [23:0]  lcd_rgb,
    output             lcd_bl,
    output             lcd_clk,
    output             lcd_rst_n,
    output     [15:0]  lcd_id
);

wire  [10:0]  pixel_xpos_w;
wire  [10:0]  pixel_ypos_w;
wire  [23:0]  pixel_data_w;
wire  [23:0]  lcd_rgb_o;
wire          lcd_pclk;
wire  [15:0]  bcd_data_x;
wire  [15:0]  bcd_data_y;
wire  [15:0]  bcd_start_x;
wire  [15:0]  bcd_start_y;
wire  [15:0]  bcd_time_ms;

assign lcd_rgb = lcd_de ? lcd_rgb_o : {24{1'bz}};

rd_id u_rd_id(
    .clk          (sys_clk),
    .rst_n        (sys_rst_n),
    .lcd_rgb      (lcd_rgb),
    .lcd_id       (lcd_id)
);

clk_div u_clk_div(
    .clk          (sys_clk),
    .rst_n        (sys_rst_n),
    .lcd_id       (lcd_id),
    .lcd_pclk     (lcd_pclk)
);

binary2bcd u_binary2bcd_x(
    .sys_clk      (sys_clk),
    .sys_rst_n    (sys_rst_n),
    .data         (data[31:16]),
    .bcd_data     (bcd_data_x)
);

binary2bcd u_binary2bcd_y(
    .sys_clk      (sys_clk),
    .sys_rst_n    (sys_rst_n),
    .data         (data[15:0]),
    .bcd_data     (bcd_data_y)
);

binary2bcd u_binary2bcd_sx(
    .sys_clk      (sys_clk),
    .sys_rst_n    (sys_rst_n),
    .data         (touch_start_x),
    .bcd_data     (bcd_start_x)
);

binary2bcd u_binary2bcd_sy(
    .sys_clk      (sys_clk),
    .sys_rst_n    (sys_rst_n),
    .data         (touch_start_y),
    .bcd_data     (bcd_start_y)
);

binary2bcd u_binary2bcd_tm(
    .sys_clk      (sys_clk),
    .sys_rst_n    (sys_rst_n),
    .data         (touch_press_time_ms),
    .bcd_data     (bcd_time_ms)
);

lcd_display u_lcd_display(
    .lcd_pclk       (lcd_pclk),
    .sys_rst_n      (sys_rst_n),
    .data           ({bcd_data_x,bcd_data_y}),
    .touch_x        (data[31:16]),
    .touch_y        (data[15:0]),
    .touch_state_bits(touch_state_bits),
    .start_x_bcd    (bcd_start_x),
    .start_y_bcd    (bcd_start_y),
    .press_time_bcd (bcd_time_ms),
    .rx_line_ascii  (rx_line_ascii),
    .pixel_xpos     (pixel_xpos_w),
    .pixel_ypos     (pixel_ypos_w),
    .pixel_data     (pixel_data_w)
);

lcd_driver u_lcd_driver(
    .lcd_pclk       (lcd_pclk),
    .rst_n          (sys_rst_n),
    .lcd_id         (lcd_id),
    .lcd_hs         (lcd_hs),
    .lcd_vs         (lcd_vs),
    .lcd_de         (lcd_de),
    .lcd_bl         (lcd_bl),
    .lcd_clk        (lcd_clk),
    .lcd_rgb        (lcd_rgb_o),
    .lcd_rst        (lcd_rst_n),
    .data_req       (),
    .h_disp         (),
    .v_disp         (),
    .pixel_data     (pixel_data_w),
    .pixel_xpos     (pixel_xpos_w),
    .pixel_ypos     (pixel_ypos_w)
);

endmodule
