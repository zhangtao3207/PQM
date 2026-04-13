/*
 * 模块: lcd_rgb_char
 * 功能:
 *   LCD 显示顶层，整合面板识别、像素时钟、显示内容与屏驱时序。
 *
 * 输入:
 *   sys_clk: 系统时钟。
 *   sys_rst_n: 低有效系统复位信号。
 *   data: 模块输出数据。
 *   touch_state_bits: 信号。
 *   touch_start_x: 触摸起点 X 坐标。
 *   touch_start_y: 触摸起点 Y 坐标。
 *   touch_press_time_ms: 当前按压持续时间，单位 ms。
 *   rx_line_ascii: 信号。
 *   wave_clk: 波形处理时钟。
 *   u_wave_sample_valid: 有效标志。
 *   u_wave_sample_code: 信号。
 *   u_wave_zero_code: 信号。
 *   u_wave_zero_valid: 有效标志。
 *   i_wave_sample_valid: 有效标志。
 *   i_wave_sample_code: 信号。
 *   i_wave_zero_code: 信号。
 *   i_wave_zero_valid: 有效标志。
 *
 * 输出:
 *   lcd_hs: LCD 行同步输出。
 *   lcd_vs: LCD 场同步输出。
 *   lcd_de: LCD 数据有效信号。
 *   lcd_bl: LCD 背光使能输出。
 *   lcd_clk: LCD 时钟输出。
 *   lcd_rst_n: 低有效复位信号。
 *   lcd_id: LCD 面板 ID。
 *
 * 双向:
 *   lcd_rgb: LCD RGB 数据总线。
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

// 茅隆碌茅聺垄忙赂虏忙聼聯氓聮聦氓颅聴莽卢娄忙聵戮莽陇潞茅聯戮盲陆驴莽聰篓氓聢掳莽職聞盲赂颅茅聴麓盲驴隆氓聫路茫聙聜
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

// 茅聺垄忙聺驴 ID 猫炉禄氓聫聳忙篓隆氓聺聴茂录職盲赂聤莽聰碌氓聬聨猫炉聠氓聢芦 LCD 氓聻聥氓聫路茫聙聜
rd_id u_rd_id(
    .clk          (sys_clk),
    .rst_n        (sys_rst_n),
    .lcd_rgb      (lcd_rgb),
    .lcd_id       (lcd_id)
);

// 忙聽鹿忙聧庐茅聺垄忙聺驴 ID 茅聙聣忙聥漏氓聝聫莽麓聽忙聴露茅聮聼茫聙聜
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

// 茅隆碌茅聺垄忙赂虏忙聼聯忙篓隆氓聺聴茂录職猫戮聯氓聡潞氓陆聯氓聣聧氓聝聫莽麓聽茅垄聹猫聣虏茫聙聜
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

// LCD 忙聴露氓潞聫茅漏卤氓聤篓忙篓隆氓聺聴茂录職忙聤聤氓聝聫莽麓聽茅垄聹猫聣虏茅聙聛氓聢掳 LCD 莽聣漏莽聬聠忙聨楼氓聫拢茫聙聜
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
