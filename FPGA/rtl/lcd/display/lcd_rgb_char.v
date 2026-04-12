/*
 * Module: lcd_rgb_char
 * æ¦è¿°:
 *   æ¾ç¤ºå­ç³»ç»å°è£ï¼ID è¯»åãåç´ æ¶éåé¢ãæ°å¼BCDè½¬æ¢ãå­ç¬¦æ æ ¼æ¸²æä¸LCDé©±å¨ã
 *   å½åçæ¬æ¥æ¶ä¸»é¾è·¯éæ¥ççµå/çµæµä¸¤è·¯æ³¢å½¢æ ·æ¬ä¸é¶ç¹åèï¼å¹¶è½¬åç»
 *   lcd_display ç¨äºå·¦ä¾§åæ³¢å½¢åå³ä¾§ U_rms / I_rms çå®æ¶æ¾ç¤ºã
 */
/*
 * è¯¦ç»è¯´æï¼
 *   LCD æ¾ç¤ºé¾çé¡¶å±å°è£ãå®æé¢æ¿ ID è¯å«ãåç´ æ¶ééæ©ãé¡µé¢åç´ æ¸²æ
 *   å LCD æ¶åºé©±å¨ä¸²èµ·æ¥ï¼å¯¹å¤æä¾å®æ´ç LCD æ¥å£ã
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
    input              wave_clk,
    input              u_wave_sample_valid,
    input      [15:0]  u_wave_sample_code,
    input      [15:0]  u_wave_zero_code,
    input              u_wave_zero_valid,
    input              i_wave_sample_valid,
    input      [15:0]  i_wave_sample_code,
    input      [15:0]  i_wave_zero_code,
    input              i_wave_zero_valid,

    output             lcd_hs,
    output             lcd_vs,
    output             lcd_de,
    inout      [23:0]  lcd_rgb,
    output             lcd_bl,
    output             lcd_clk,
    output             lcd_rst_n,
    output     [15:0]  lcd_id
);

// é¡µé¢æ¸²æåå­ç¬¦æ¾ç¤ºé¾ä½¿ç¨å°çä¸­é´ä¿¡å·ã
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
wire          frame_done_toggle_w;

assign lcd_rgb = lcd_de ? lcd_rgb_o : {24{1'bz}};

// é¢æ¿ ID è¯»åæ¨¡åï¼ä¸çµåè¯å« LCD åå·ã
rd_id u_rd_id(
    .clk          (sys_clk),
    .rst_n        (sys_rst_n),
    .lcd_rgb      (lcd_rgb),
    .lcd_id       (lcd_id)
);

// æ ¹æ®é¢æ¿ ID éæ©åç´ æ¶éã
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

// é¡µé¢æ¸²ææ¨¡åï¼è¾åºå½ååç´ é¢è²ã
lcd_display u_lcd_display(
    .lcd_pclk       (lcd_pclk),
    .sys_rst_n      (sys_rst_n),
    .data           ({bcd_data_x,bcd_data_y}),
    .touch_x        (data[31:16]),
    .touch_y        (data[15:0]),
    .touch_state_bits(touch_state_bits),
    .touch_start_x  (touch_start_x),
    .touch_start_y  (touch_start_y),
    .touch_press_time_ms(touch_press_time_ms),
    .rx_line_ascii  (rx_line_ascii),
    .lcd_frame_done_toggle(frame_done_toggle_w),
    .wave_clk       (wave_clk),
    .u_wave_sample_valid(u_wave_sample_valid),
    .u_wave_sample_code (u_wave_sample_code),
    .u_wave_zero_code   (u_wave_zero_code),
    .u_wave_zero_valid  (u_wave_zero_valid),
    .i_wave_sample_valid(i_wave_sample_valid),
    .i_wave_sample_code (i_wave_sample_code),
    .i_wave_zero_code   (i_wave_zero_code),
    .i_wave_zero_valid  (i_wave_zero_valid),
    .pixel_xpos     (pixel_xpos_w),
    .pixel_ypos     (pixel_ypos_w),
    .pixel_data     (pixel_data_w)
);

// LCD æ¶åºé©±å¨æ¨¡åï¼æåç´ é¢è²éå° LCD ç©çæ¥å£ã
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
    .pixel_ypos     (pixel_ypos_w),
    .frame_done_toggle(frame_done_toggle_w)
);

endmodule
