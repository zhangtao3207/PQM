/*
 * 模块: lcd_rgb_char
 * 功能: LCD 显示封装，连接面板识别、像素时钟、显示内容与屏驱时序。
 * 输入:
 *   sys_clk: 系统时钟。
 *   sys_rst_n: 低有效系统复位。
 *   data: 触摸坐标显示所用数据总线。
 *   touch_state_bits: 触摸状态位。
 *   touch_start_x: 触摸起点 X 坐标。
 *   touch_start_y: 触摸起点 Y 坐标。
 *   touch_press_time_ms: 触摸按压持续时间，单位 ms。
 *   rx_line_ascii: 串口接收文本快照。
 *   wave_clk: 波形/测量处理时钟。
 *   uart_tx_busy: UART 发送器忙标志。
 *   u_wave_sample_valid: 电压波形样本有效标志。
 *   u_wave_sample_code: 电压波形样本码值。
 *   u_wave_zero_code: 电压零点跟踪码值。
 *   u_wave_zero_valid: 电压零点跟踪有效标志。
 *   i_wave_sample_valid: 电流波形样本有效标志。
 *   i_wave_sample_code: 电流波形样本码值。
 *   i_wave_zero_code: 电流零点跟踪码值。
 *   i_wave_zero_valid: 电流零点跟踪有效标志。
 * 输出:
 *   lcd_hs: LCD 行同步。
 *   lcd_vs: LCD 场同步。
 *   lcd_de: LCD 数据有效。
 *   lcd_bl: LCD 背光使能。
 *   lcd_clk: LCD 像素时钟。
 *   lcd_rst_n: LCD 复位。
 *   lcd_id: LCD 面板 ID。
 *   alarm_active: 时域异常告警活动位。
 *   uart_stream_tx_en: 串口测量文本发送请求。
 *   uart_stream_tx_data: 串口测量文本发送字节。
 *   ps_snapshot_words: 按共享内存 ABI 排列的标量快照。
 *   ps_snapshot_commit_toggle: 标量快照提交 toggle。
 *   ps_harmonic_valid: 谐波条目有效标志。
 *   ps_harmonic_last: 谐波帧尾标志。
 *   ps_harmonic_index: 谐波阶次。
 *   ps_harmonic_u_ratio: 谐波电压幅值占比。
 *   ps_harmonic_i_ratio: 谐波电流幅值占比。
 *   ps_harmonic_phase: 谐波相位差。
 *   ps_harmonic_flags: 谐波有效性标志。
 * 输入:
 *   ps_harmonic_ready: PS 共享内存桥允许接收当前谐波条目。
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
    input              uart_tx_busy,
    input              full_scale_low_range_active,
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
    output     [15:0]  lcd_id,
    output             alarm_active,
    output             uart_stream_tx_en,
    output     [7:0]   uart_stream_tx_data,
    output    [511:0]  ps_snapshot_words,
    output             ps_snapshot_commit_toggle,
    output             ps_harmonic_valid,
    input              ps_harmonic_ready,
    output             ps_harmonic_last,
    output      [8:0]  ps_harmonic_index,
    output     [31:0]  ps_harmonic_u_ratio,
    output     [31:0]  ps_harmonic_i_ratio,
    output     [31:0]  ps_harmonic_phase,
    output     [31:0]  ps_harmonic_flags
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
wire          frame_done_toggle_w;

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
    .data           ({bcd_data_x, bcd_data_y}),
    .touch_x        (data[31:16]),
    .touch_y        (data[15:0]),
    .touch_state_bits(touch_state_bits),
    .touch_start_x  (touch_start_x),
    .touch_start_y  (touch_start_y),
    .touch_press_time_ms(touch_press_time_ms),
    .rx_line_ascii  (rx_line_ascii),
    .lcd_frame_done_toggle(frame_done_toggle_w),
    .wave_clk       (wave_clk),
    .uart_tx_busy   (uart_tx_busy),
    .full_scale_low_range_active(full_scale_low_range_active),
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
    .pixel_data     (pixel_data_w),
    .alarm_active   (alarm_active),
    .uart_stream_tx_en  (uart_stream_tx_en),
    .uart_stream_tx_data(uart_stream_tx_data),
    .ps_snapshot_words(ps_snapshot_words),
    .ps_snapshot_commit_toggle(ps_snapshot_commit_toggle),
    .ps_harmonic_valid(ps_harmonic_valid),
    .ps_harmonic_ready(ps_harmonic_ready),
    .ps_harmonic_last(ps_harmonic_last),
    .ps_harmonic_index(ps_harmonic_index),
    .ps_harmonic_u_ratio(ps_harmonic_u_ratio),
    .ps_harmonic_i_ratio(ps_harmonic_i_ratio),
    .ps_harmonic_phase(ps_harmonic_phase),
    .ps_harmonic_flags(ps_harmonic_flags)
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
    .pixel_ypos     (pixel_ypos_w),
    .frame_done_toggle(frame_done_toggle_w)
);

endmodule
