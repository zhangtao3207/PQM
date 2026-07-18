`timescale 1ns / 1ps
/*
 * 模块: lcd_display
 * 功能:
 *   LCD 显示顶层混合渲染模块。负责把时域波形、频域柱图、测量文本、触摸状态和串口测量帧组织到同一显示链路。
 *
 * 输入:
 *   lcd_pclk              - LCD 像素时钟域，用于背景、文字和显示 RAM 读出。
 *   sys_rst_n             - 全局低有效复位。
 *   data                  - 预留的 32 位显示输入，当前未参与主要绘制。
 *   touch_x               - 当前触摸 X 坐标。
 *   touch_y               - 当前触摸 Y 坐标。
 *   touch_state_bits      - 触摸状态位，其中 TOUCH_PRESSED_BIT 表示按下状态。
 *   touch_start_x         - 本次触摸起始 X 坐标。
 *   touch_start_y         - 本次触摸起始 Y 坐标。
 *   touch_press_time_ms   - 本次按压持续时间，单位 ms。
 *   rx_line_ascii         - 外部输入的 ASCII 文本行。
 *   lcd_frame_done_toggle - LCD 帧结束翻转信号，用于双缓冲交换。
 *   wave_clk              - 波形采集与测量处理时钟域。
 *   uart_tx_busy          - UART 发送忙信号，用于串口测量流节流。
 *   u_wave_sample_valid   - 电压波形样本有效。
 *   u_wave_sample_code    - 电压原始采样码。
 *   u_wave_zero_code      - 电压零点参考码。
 *   u_wave_zero_valid     - 电压零点参考有效。
 *   i_wave_sample_valid   - 电流波形样本有效。
 *   i_wave_sample_code    - 电流原始采样码。
 *   i_wave_zero_code      - 电流零点参考码。
 *   i_wave_zero_valid     - 电流零点参考有效。
 *   pixel_xpos            - 当前像素 X 坐标。
 *   pixel_ypos            - 当前像素 Y 坐标。
 * 输出:
 *   pixel_data            - 当前像素 RGB 数据。
 *   alarm_active          - 尖峰告警输出。
 *   uart_stream_tx_en     - UART 测量串流发送使能。
 *   uart_stream_tx_data   - UART 测量串流发送字节。
 */
module lcd_display(
    input              lcd_pclk,
    input              sys_rst_n,
    input      [31:0]  data,
    input      [15:0]  touch_x,
    input      [15:0]  touch_y,
    input      [4:0]   touch_state_bits,
    input      [15:0]  touch_start_x,
    input      [15:0]  touch_start_y,
    input      [15:0]  touch_press_time_ms,
    input      [127:0] rx_line_ascii,
    input              lcd_frame_done_toggle,
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
    input      [10:0]  pixel_xpos,
    input      [10:0]  pixel_ypos,
    output reg [23:0]  pixel_data,
    output             alarm_active,
    output             uart_stream_tx_en,
    output     [7:0]   uart_stream_tx_data
);

// 界面字符尺寸、主题色、布局坐标和显示量程参数。
localparam [5:0]  BIG_CHAR_W    = 6'd16;
localparam [5:0]  SMALL_CHAR_W  = 6'd10;
localparam [6:0]  FONT_BLANK    = 7'd127;
localparam [23:0] BG_COLOR      = 24'h0B1524;
localparam [23:0] TEXT_WHITE    = 24'hF2F6FA;
localparam [23:0] WAVE_U_COLOR  = 24'h39E46F;
localparam [23:0] WAVE_I_COLOR  = 24'hFFD84E;
localparam [23:0] ACCENT_COLOR  = 24'h58B6FF;
localparam [23:0] PHASE_NEG_COLOR = 24'hFF5A5F;
localparam integer TEXT_REFRESH_CYCLES = 1_000_000;  // 50MHz wave_clk 下约 20ms 刷新一次文本结果
localparam integer U_FULL_SCALE_HIGH_X100 = 35000;    // 高量程电压，单位 0.01V，对应 350.00V
localparam integer I_FULL_SCALE_HIGH_X100 = 3000;     // 高量程电流，单位 0.01A，对应 30.00A
localparam integer U_FULL_SCALE_LOW_X100  = 1000;     // 低量程电压，单位 0.01V，对应 10.00V
localparam integer I_FULL_SCALE_LOW_X100  = 300;      // 低量程电流，单位 0.01A，对应 3.00A
localparam integer WAVE_FULL_SCALE_CODE = 32767;         // 16 位双极性 ADC 的单边满量程差值，对应约 ±10V 输入
localparam [10:0] GRAPH_X       = 11'd66;
localparam [10:0] GRAPH_Y       = 11'd144;
localparam [10:0] GRAPH_W       = 11'd354;
localparam [10:0] GRAPH_H       = 11'd240;
localparam [10:0] MODE_BTN_X    = 11'd572;
localparam [10:0] MODE_BTN_Y    = 11'd6;
localparam [10:0] MODE_BTN_W    = 11'd87;
localparam [10:0] MODE_BTN_H    = 11'd32;
localparam [10:0] FREEZE_BTN_X  = 11'd672;
localparam [10:0] FREEZE_BTN_Y  = 11'd6;
localparam [10:0] FREEZE_BTN_W  = 11'd110;
localparam [10:0] FREEZE_BTN_H  = 11'd32;
localparam [10:0] HARM_PREV_X   = 11'd325;
localparam [10:0] HARM_NEXT_X   = 11'd375;
localparam [10:0] HARM_BTN_Y    = 11'd180;
localparam [10:0] HARM_BTN_W    = 11'd38;
localparam [10:0] HARM_BTN_H    = 11'd28;
localparam [10:0] FREQ_GRAPH_X  = 11'd50;
localparam [10:0] FREQ_GRAPH_W  = 11'd440;
localparam [10:0] FREQ_MAG_Y    = 11'd144;
localparam [10:0] FREQ_MAG_BASE_Y = 11'd324;
localparam [10:0] FREQ_PHASE_Y  = 11'd344;
localparam [10:0] FREQ_PHASE_BASE_Y = 11'd422;
localparam [4:0]  HARMONIC_MAX_WINDOW_INDEX = 5'd19;
localparam integer TOUCH_PRESSED_BIT   = 4;
localparam [15:0] FREEZE_MIN_PRESS_MS  = 16'd30;
localparam [15:0] FREEZE_MAX_PRESS_MS  = 16'd500;
localparam [15:0] HARMONIC_LONG_PRESS_MS = 16'd700;
localparam integer TEXT_PACKET_WIDTH   = 1086;

// LCD 像素域、跨时钟缓存和绘图过程使用的中间寄存器。
reg  [23:0] base_color_d1;
reg  [23:0] text_color_d1;
reg         text_en_d1;
reg         text_font_small_d1;
reg  [6:0]  text_char_idx_d1;
reg  [5:0]  text_rel_x_d1;
reg         text_blank_d1;
reg  [7:0]  u_rms_hundreds_lcd;
reg  [7:0]  u_rms_tens_lcd;
reg  [7:0]  u_rms_units_lcd;
reg  [7:0]  u_rms_decile_lcd;
reg  [7:0]  u_rms_percentiles_lcd;
reg         u_rms_digits_valid_lcd;
reg  [7:0]  i_rms_hundreds_lcd;
reg  [7:0]  i_rms_tens_lcd;
reg  [7:0]  i_rms_units_lcd;
reg  [7:0]  i_rms_decile_lcd;
reg  [7:0]  i_rms_percentiles_lcd;
reg         i_rms_digits_valid_lcd;
reg         phase_neg_lcd;
reg  [7:0]  phase_hundreds_lcd;
reg  [7:0]  phase_tens_lcd;
reg  [7:0]  phase_units_lcd;
reg  [7:0]  phase_decile_lcd;
reg  [7:0]  phase_percentiles_lcd;
reg         phase_valid_lcd;
reg  [7:0]  freq_hundreds_lcd;
reg  [7:0]  freq_tens_lcd;
reg  [7:0]  freq_units_lcd;
reg  [7:0]  freq_decile_lcd;
reg  [7:0]  freq_percentiles_lcd;
reg         freq_valid_lcd;
reg  [7:0]  u_pp_hundreds_lcd;
reg  [7:0]  u_pp_tens_lcd;
reg  [7:0]  u_pp_units_lcd;
reg  [7:0]  u_pp_decile_lcd;
reg  [7:0]  u_pp_percentiles_lcd;
reg         u_pp_digits_valid_lcd;
reg  [7:0]  i_pp_hundreds_lcd;
reg  [7:0]  i_pp_tens_lcd;
reg  [7:0]  i_pp_units_lcd;
reg  [7:0]  i_pp_decile_lcd;
reg  [7:0]  i_pp_percentiles_lcd;
reg         i_pp_digits_valid_lcd;
reg         active_p_neg_lcd;
reg  [7:0]  active_p_hundreds_lcd;
reg  [7:0]  active_p_tens_lcd;
reg  [7:0]  active_p_units_lcd;
reg  [7:0]  active_p_decile_lcd;
reg  [7:0]  active_p_percentiles_lcd;
reg         reactive_q_neg_lcd;
reg  [7:0]  reactive_q_hundreds_lcd;
reg  [7:0]  reactive_q_tens_lcd;
reg  [7:0]  reactive_q_units_lcd;
reg  [7:0]  reactive_q_decile_lcd;
reg  [7:0]  reactive_q_percentiles_lcd;
reg  [7:0]  apparent_s_hundreds_lcd;
reg  [7:0]  apparent_s_tens_lcd;
reg  [7:0]  apparent_s_units_lcd;
reg  [7:0]  apparent_s_decile_lcd;
reg  [7:0]  apparent_s_percentiles_lcd;
reg         power_factor_neg_lcd;
reg  [7:0]  power_factor_units_lcd;
reg  [7:0]  power_factor_decile_lcd;
reg  [7:0]  power_factor_percentiles_lcd;
reg         power_metrics_valid_lcd;
reg  [2:0]  sharp_alarm_code_lcd;
reg  [7:0]  freq_thd_u_hundreds_lcd;
reg  [7:0]  freq_thd_u_tens_lcd;
reg  [7:0]  freq_thd_u_units_lcd;
reg  [7:0]  freq_thd_u_decile_lcd;
reg  [7:0]  freq_thd_u_percentiles_lcd;
reg         freq_thd_u_valid_lcd;
reg  [7:0]  freq_thd_i_hundreds_lcd;
reg  [7:0]  freq_thd_i_tens_lcd;
reg  [7:0]  freq_thd_i_units_lcd;
reg  [7:0]  freq_thd_i_decile_lcd;
reg  [7:0]  freq_thd_i_percentiles_lcd;
reg         freq_thd_i_valid_lcd;
reg  [7:0]  freq_u1_mag_hundreds_lcd;
reg  [7:0]  freq_u1_mag_tens_lcd;
reg  [7:0]  freq_u1_mag_units_lcd;
reg  [7:0]  freq_u1_mag_decile_lcd;
reg  [7:0]  freq_u1_mag_percentiles_lcd;
reg         freq_u1_mag_valid_lcd;
reg  [7:0]  freq_i1_mag_hundreds_lcd;
reg  [7:0]  freq_i1_mag_tens_lcd;
reg  [7:0]  freq_i1_mag_units_lcd;
reg  [7:0]  freq_i1_mag_decile_lcd;
reg  [7:0]  freq_i1_mag_percentiles_lcd;
reg         freq_i1_mag_valid_lcd;
reg         freq_phase1_neg_lcd;
reg  [7:0]  freq_phase1_hundreds_lcd;
reg  [7:0]  freq_phase1_tens_lcd;
reg  [7:0]  freq_phase1_units_lcd;
reg  [7:0]  freq_phase1_decile_lcd;
reg  [7:0]  freq_phase1_percentiles_lcd;
reg         freq_phase1_valid_lcd;
reg  [7:0]  freq_dc_u_hundreds_lcd;
reg  [7:0]  freq_dc_u_tens_lcd;
reg  [7:0]  freq_dc_u_units_lcd;
reg  [7:0]  freq_dc_u_decile_lcd;
reg  [7:0]  freq_dc_u_percentiles_lcd;
reg         freq_dc_u_valid_lcd;
reg  [7:0]  freq_dc_i_hundreds_lcd;
reg  [7:0]  freq_dc_i_tens_lcd;
reg  [7:0]  freq_dc_i_units_lcd;
reg  [7:0]  freq_dc_i_decile_lcd;
reg  [7:0]  freq_dc_i_percentiles_lcd;
reg         freq_dc_i_valid_lcd;
reg  [199:0] freq_dh_order_u_text_lcd;
reg  [199:0] freq_dh_order_i_text_lcd;
reg         graph_en_d1;
reg  [8:0]  graph_col_d1;
reg  [10:0] graph_row_d1;
reg         freq_mag_u_pixel_on_d1;
reg         freq_mag_i_pixel_on_d1;
reg         freq_phase_pixel_on_d1;
reg         freq_phase_negative_d1;
reg         freq_display_bank_sync1;
reg         freq_display_bank_sync2;
reg         freq_frame_valid_sync1;
reg         freq_frame_valid_sync2;
reg         freq_front_bank_lcd;
reg         freq_front_valid_lcd;
reg         freq_front_bank_wave_sync1;
reg         freq_front_bank_wave_sync2;
reg         u_wave_prev_valid_d1;
reg  [7:0]  u_wave_prev_y_d1;
reg  [8:0]  u_wave_prev_col_d1;
reg  [10:0] u_wave_prev_row_d1;
reg         i_wave_prev_valid_d1;
reg  [7:0]  i_wave_prev_y_d1;
reg  [8:0]  i_wave_prev_col_d1;
reg  [10:0] i_wave_prev_row_d1;
reg         u_wave_display_bank_sync1;
reg         u_wave_display_bank_sync2;
reg         u_wave_frame_valid_sync1;
reg         u_wave_frame_valid_sync2;
reg         u_wave_front_bank_lcd;
reg         u_wave_front_valid_lcd;
reg         i_wave_display_bank_sync1;
reg         i_wave_display_bank_sync2;
reg         i_wave_frame_valid_sync1;
reg         i_wave_frame_valid_sync2;
reg         i_wave_front_bank_lcd;
reg         i_wave_front_valid_lcd;
reg         freeze_active_lcd;
reg         frequency_page_active_lcd;
reg  [4:0]  harmonic_window_index_lcd;
reg         touch_pressed_sync1;
reg         touch_pressed_sync2;
reg         touch_pressed_sync3;
reg         full_scale_low_range_sync1_lcd;
reg         full_scale_low_range_active_lcd;
reg         lcd_frame_done_toggle_d1;
reg         freeze_active_wave_sync1;
reg         freeze_active_wave_sync2;

wire [23:0] base_color;
wire [23:0] text_color;
wire        text_en;
wire        text_font_small;
wire [6:0]  text_char_idx;
wire [5:0]  text_rel_x;
wire [5:0]  text_rel_y;
wire        text_blank;
wire        text_pixel_on;

wire [7:0]  u_rms_hundreds;
wire [7:0]  u_rms_tens;
wire [7:0]  u_rms_units;
wire [7:0]  u_rms_decile;
wire [7:0]  u_rms_percentiles;
wire        u_rms_digits_valid;
wire [7:0]  u_pp_hundreds;
wire [7:0]  u_pp_tens;
wire [7:0]  u_pp_units;
wire [7:0]  u_pp_decile;
wire [7:0]  u_pp_percentiles;
wire        u_pp_digits_valid;
wire        u_wave_frame_valid;
wire        u_wave_display_bank;
wire        u_wave_ram_we;
wire [9:0]  u_wave_ram_waddr;
wire [7:0]  u_wave_ram_wdata;
wire [7:0]  u_wave_ram_douta;
wire [7:0]  u_wave_ram_doutb;
wire [9:0]  u_wave_ram_raddr;
wire [10:0] u_wave_y_curr_abs;
wire [10:0] u_wave_y_prev_abs;
wire        u_wave_seg_valid;
wire [10:0] u_wave_seg_lo_abs;
wire [10:0] u_wave_seg_hi_abs;
wire        u_wave_pixel_on;
wire        u_wave_pixel_on_internal;  // From wave_pixel_detector module

wire [7:0]  i_rms_hundreds;
wire [7:0]  i_rms_tens;
wire [7:0]  i_rms_units;
wire [7:0]  i_rms_decile;
wire [7:0]  i_rms_percentiles;
wire        i_rms_digits_valid;
wire [7:0]  i_pp_hundreds;
wire [7:0]  i_pp_tens;
wire [7:0]  i_pp_units;
wire [7:0]  i_pp_decile;
wire [7:0]  i_pp_percentiles;
wire        i_pp_digits_valid;
wire        i_wave_frame_valid;
wire        i_wave_display_bank;
wire        i_wave_ram_we;
wire [9:0]  i_wave_ram_waddr;
wire [7:0]  i_wave_ram_wdata;
wire [7:0]  i_wave_ram_douta;
wire [7:0]  i_wave_ram_doutb;
wire [9:0]  i_wave_ram_raddr;
wire [10:0] i_wave_y_curr_abs;
wire [10:0] i_wave_y_prev_abs;
wire        i_wave_seg_valid;
wire [10:0] i_wave_seg_lo_abs;
wire [10:0] i_wave_seg_hi_abs;
wire        i_wave_pixel_on;
wire        i_wave_pixel_on_internal;  // From wave_pixel_detector module

wire        phase_neg;
wire signed [16:0] phase_x100_signed;
wire [7:0]  phase_hundreds;
wire [7:0]  phase_tens;
wire [7:0]  phase_units;
wire [7:0]  phase_decile;
wire [7:0]  phase_percentiles;
wire        phase_valid;
wire [7:0]  freq_hundreds;
wire [7:0]  freq_tens;
wire [7:0]  freq_units;
wire [7:0]  freq_decile;
wire [7:0]  freq_percentiles;
wire        freq_valid;
wire        active_p_neg;
wire [7:0]  active_p_hundreds;
wire [7:0]  active_p_tens;
wire [7:0]  active_p_units;
wire [7:0]  active_p_decile;
wire [7:0]  active_p_percentiles;
wire        reactive_q_neg;
wire [7:0]  reactive_q_hundreds;
wire [7:0]  reactive_q_tens;
wire [7:0]  reactive_q_units;
wire [7:0]  reactive_q_decile;
wire [7:0]  reactive_q_percentiles;
wire [7:0]  apparent_s_hundreds;
wire [7:0]  apparent_s_tens;
wire [7:0]  apparent_s_units;
wire [7:0]  apparent_s_decile;
wire [7:0]  apparent_s_percentiles;
wire        power_factor_neg;
wire [7:0]  power_factor_units;
wire [7:0]  power_factor_decile;
wire [7:0]  power_factor_percentiles;
wire        power_metrics_valid;
wire        sharp_alarm_active;
wire [2:0]  sharp_alarm_code;
wire [7:0]  freq_thd_u_hundreds;
wire [7:0]  freq_thd_u_tens;
wire [7:0]  freq_thd_u_units;
wire [7:0]  freq_thd_u_decile;
wire [7:0]  freq_thd_u_percentiles;
wire        freq_thd_u_valid;
wire [7:0]  freq_thd_i_hundreds;
wire [7:0]  freq_thd_i_tens;
wire [7:0]  freq_thd_i_units;
wire [7:0]  freq_thd_i_decile;
wire [7:0]  freq_thd_i_percentiles;
wire        freq_thd_i_valid;
wire [7:0]  freq_u1_mag_hundreds;
wire [7:0]  freq_u1_mag_tens;
wire [7:0]  freq_u1_mag_units;
wire [7:0]  freq_u1_mag_decile;
wire [7:0]  freq_u1_mag_percentiles;
wire        freq_u1_mag_valid;
wire [7:0]  freq_i1_mag_hundreds;
wire [7:0]  freq_i1_mag_tens;
wire [7:0]  freq_i1_mag_units;
wire [7:0]  freq_i1_mag_decile;
wire [7:0]  freq_i1_mag_percentiles;
wire        freq_i1_mag_valid;
wire        freq_phase1_neg;
wire [7:0]  freq_phase1_hundreds;
wire [7:0]  freq_phase1_tens;
wire [7:0]  freq_phase1_units;
wire [7:0]  freq_phase1_decile;
wire [7:0]  freq_phase1_percentiles;
wire        freq_phase1_valid;
wire [7:0]  freq_dc_u_hundreds;
wire [7:0]  freq_dc_u_tens;
wire [7:0]  freq_dc_u_units;
wire [7:0]  freq_dc_u_decile;
wire [7:0]  freq_dc_u_percentiles;
wire        freq_dc_u_valid;
wire [7:0]  freq_dc_i_hundreds;
wire [7:0]  freq_dc_i_tens;
wire [7:0]  freq_dc_i_units;
wire [7:0]  freq_dc_i_decile;
wire [7:0]  freq_dc_i_percentiles;
wire        freq_dc_i_valid;
wire [199:0] freq_dh_order_u_text;
wire [199:0] freq_dh_order_i_text;
wire        u_trigger_pulse;
wire [8:0]  u_trigger_snapshot_ptr;

wire        graph_en;
wire        time_graph_en;
wire [10:0] graph_col_ext;
wire [8:0]  graph_col;
wire        touch_pressed_lcd;
wire        touch_pressed_fall_lcd;
wire        mode_button_touch_hit;
wire        mode_button_start_hit;
wire        mode_button_pressed;
wire        mode_button_click_qualified;
wire        freeze_button_touch_hit;
wire        freeze_button_start_hit;
wire        freeze_button_pressed;
wire        freeze_button_click_qualified;
wire        harmonic_prev_touch_hit;
wire        harmonic_next_touch_hit;
wire        harmonic_prev_start_hit;
wire        harmonic_next_start_hit;
wire        harmonic_prev_pressed;
wire        harmonic_next_pressed;
wire        harmonic_prev_click_qualified;
wire        harmonic_next_click_qualified;
wire        harmonic_home_qualified;
wire        freeze_active_next_lcd;
wire        screen_update_enable_lcd;
wire        freeze_active_wave;
wire        frame_edge_lcd;
wire [TEXT_PACKET_WIDTH-1:0] text_packet_wave;
wire [TEXT_PACKET_WIDTH-1:0] text_packet_front_lcd;

wire [6:0]  font_char_idx;
wire        text_result_commit_toggle;
reg         text_result_commit_toggle_d1_wave;
reg         freq_text_result_commit_toggle_d1_wave;
reg         text_packet_commit_toggle_wave;
wire        text_commit_pending_lcd;
wire        text_swap_ack_toggle_lcd;
wire        text_result_commit_edge_wave;
wire        freq_text_result_commit_edge_wave;

wire [11:0] font_addr_16x32;
wire [10:0] font_addr_10x20;
wire [15:0] font_row_16x32_rom;
wire [11:0] font_row_10x20_rom;
wire [3:0]  font_10x20_bit_idx;
wire        freq_mag_u_pixel_on;
wire        freq_mag_i_pixel_on;
wire        freq_phase_pixel_on;
wire        freq_phase_negative;
wire [10:0] freq_mag_col_ext;
wire [10:0] freq_phase_col_ext;
wire [4:0]  freq_mag_bucket;
wire [4:0]  freq_mag_sub_col;
wire [4:0]  freq_phase_sub_col;
wire [7:0]  freq_u_bar_height;
wire [7:0]  freq_i_bar_height;
wire [7:0]  freq_phase_bar_height;
wire        freq_sample_valid;
wire        freq_harmonic_ready;
wire        freq_harmonic_valid;
wire        freq_harmonic_last;
wire [8:0]  freq_harmonic_order_stream;
wire        freq_harmonic_present_stream;
wire [16:0] freq_harmonic_u_mag;
wire [16:0] freq_harmonic_i_mag;
wire [15:0] freq_harmonic_u_pct_x100;
wire [15:0] freq_harmonic_i_pct_x100;
wire        freq_phase_diff_valid_stream;
wire signed [15:0] freq_phase_diff_deg_x100;
wire        freq_harmonic_fire;
wire [31:0] freq_thd_u_raw_x100;
wire [31:0] freq_thd_i_raw_x100;
wire        freq_thd_u_raw_valid;
wire        freq_thd_i_raw_valid;
wire [31:0] freq_u1_mag_raw_x100;
wire [31:0] freq_i1_mag_raw_x100;
wire        freq_u1_mag_raw_valid;
wire        freq_i1_mag_raw_valid;
wire signed [31:0] freq_phase1_raw_x100;
wire        freq_phase1_raw_valid;
wire signed [31:0] fft_fund_freq_period_raw;
wire        fft_fund_freq_valid;
wire [31:0] freq_dc_u_raw_x100;
wire [31:0] freq_dc_i_raw_x100;
wire        freq_dc_u_raw_valid;
wire        freq_dc_i_raw_valid;
wire [44:0] freq_dh_order_u_list_raw;
wire [44:0] freq_dh_order_i_list_raw;
wire [2:0]  freq_dh_order_u_count_raw;
wire [2:0]  freq_dh_order_i_count_raw;
wire        freq_dh_order_u_raw_valid;
wire        freq_dh_order_i_raw_valid;
wire        freq_metrics_raw_valid;
wire        freq_metrics_raw_commit_toggle;
wire        freq_text_result_commit_toggle;
wire        freq_display_bank;
wire        freq_frame_valid;
wire        freq_ram_we;
wire [9:0]  freq_ram_waddr;
wire [9:0]  freq_ram_raddr;
wire [7:0]  freq_u_mag_wdata;
wire [7:0]  freq_i_mag_wdata;
wire [7:0]  freq_phase_wdata;
wire [7:0]  freq_flag_wdata;
wire        freq_ram_store_we;
wire [7:0]  freq_u_mag_ram_doutb;
wire [7:0]  freq_i_mag_ram_doutb;
wire [7:0]  freq_phase_ram_doutb;
wire [7:0]  freq_flag_ram_doutb;
wire [8:0]  freq_window_base;
wire [8:0]  freq_display_harmonic_order;
wire        freq_harmonic_present_lcd;
wire        freq_phase_valid_lcd;
wire        uart_stream_tx_en_wire;
wire [7:0]  uart_stream_tx_data_wire;
wire [31:0] u_full_scale_x100_wave;
wire [31:0] i_full_scale_x100_wave;

// 组合生成字体 ROM 地址、文本提交沿和顶层告警/UART 输出映射。
assign font_addr_16x32 = text_blank ? 12'd0 : ({5'd0, font_char_idx} << 5) + {6'd0, text_rel_y[4:0]};
assign font_addr_10x20 = text_blank ? 11'd0 : (({4'd0, font_char_idx} << 4) + ({6'd0, font_char_idx} << 2) + {5'd0, text_rel_y[4:0]});
assign text_result_commit_edge_wave = text_result_commit_toggle ^ text_result_commit_toggle_d1_wave;
assign freq_text_result_commit_edge_wave = freq_text_result_commit_toggle ^ freq_text_result_commit_toggle_d1_wave;
assign alarm_active = sharp_alarm_active;
assign uart_stream_tx_en   = uart_stream_tx_en_wire;
assign uart_stream_tx_data = uart_stream_tx_data_wire;
assign u_full_scale_x100_wave = full_scale_low_range_active ? U_FULL_SCALE_LOW_X100 : U_FULL_SCALE_HIGH_X100;
assign i_full_scale_x100_wave = full_scale_low_range_active ? I_FULL_SCALE_LOW_X100 : I_FULL_SCALE_HIGH_X100;
// 将时域与频域测量字段打包成统一文本包，供 LCD 和 UART 复用。
assign text_packet_wave = {
    u_rms_hundreds, u_rms_tens, u_rms_units, u_rms_decile, u_rms_percentiles, u_rms_digits_valid,
    i_rms_hundreds, i_rms_tens, i_rms_units, i_rms_decile, i_rms_percentiles, i_rms_digits_valid,
    phase_neg, phase_hundreds, phase_tens, phase_units, phase_decile, phase_percentiles, phase_valid,
    freq_hundreds, freq_tens, freq_units, freq_decile, freq_percentiles, freq_valid,
    u_pp_hundreds, u_pp_tens, u_pp_units, u_pp_decile, u_pp_percentiles, u_pp_digits_valid,
    i_pp_hundreds, i_pp_tens, i_pp_units, i_pp_decile, i_pp_percentiles, i_pp_digits_valid,
    active_p_neg, active_p_hundreds, active_p_tens, active_p_units, active_p_decile, active_p_percentiles,
    reactive_q_neg, reactive_q_hundreds, reactive_q_tens, reactive_q_units, reactive_q_decile, reactive_q_percentiles,
    apparent_s_hundreds, apparent_s_tens, apparent_s_units, apparent_s_decile, apparent_s_percentiles,
    power_factor_neg, power_factor_units, power_factor_decile, power_factor_percentiles,
    power_metrics_valid,
    sharp_alarm_code,
    freq_thd_u_hundreds, freq_thd_u_tens, freq_thd_u_units, freq_thd_u_decile, freq_thd_u_percentiles, freq_thd_u_valid,
    freq_thd_i_hundreds, freq_thd_i_tens, freq_thd_i_units, freq_thd_i_decile, freq_thd_i_percentiles, freq_thd_i_valid,
    freq_u1_mag_hundreds, freq_u1_mag_tens, freq_u1_mag_units, freq_u1_mag_decile, freq_u1_mag_percentiles, freq_u1_mag_valid,
    freq_i1_mag_hundreds, freq_i1_mag_tens, freq_i1_mag_units, freq_i1_mag_decile, freq_i1_mag_percentiles, freq_i1_mag_valid,
    freq_phase1_neg, freq_phase1_hundreds, freq_phase1_tens, freq_phase1_units, freq_phase1_decile, freq_phase1_percentiles, freq_phase1_valid,
    freq_dc_u_hundreds, freq_dc_u_tens, freq_dc_u_units, freq_dc_u_decile, freq_dc_u_percentiles, freq_dc_u_valid,
    freq_dc_i_hundreds, freq_dc_i_tens, freq_dc_i_units, freq_dc_i_decile, freq_dc_i_percentiles, freq_dc_i_valid,
    freq_dh_order_u_text,
    freq_dh_order_i_text
};

// 大字号字模 ROM，供主要数值和标题字符渲染。
blk_mem_gen_font_16x32 u_font_16x32_rom(
    .clka  (lcd_pclk),
    .addra (font_addr_16x32),
    .douta (font_row_16x32_rom)
);

// 小字号字模 ROM，供单位和辅助文本渲染。
blk_mem_gen_font_10x20 u_font_10x20_rom(
    .clka  (lcd_pclk),
    .ena   (1'b1),
    .addra (font_addr_10x20),
    .douta (font_row_10x20_rom)
);
// 电压时域波形捕获模块，生成电压显示 RAM 帧。
time_wave_display_capture #(
    .FULL_SCALE_CODE(WAVE_FULL_SCALE_CODE)
) u_u_time_wave_display_capture (
    .wave_clk          (wave_clk),
    .sys_rst_n         (sys_rst_n),
    .wave_sample_valid (u_wave_sample_valid),
    .wave_sample_code  (u_wave_sample_code),
    .wave_zero_code    (u_wave_zero_code),
    .wave_zero_valid   (u_wave_zero_valid),
    .trigger_force     (1'b0),
    .trigger_force_snapshot_ptr(9'd0),
    .trigger_use_external(1'b0),
    .display_freeze    (freeze_active_wave),
    .wave_frame_valid  (u_wave_frame_valid),
    .wave_display_bank (u_wave_display_bank),
    .wave_ram_we       (u_wave_ram_we),
    .wave_ram_waddr    (u_wave_ram_waddr),
    .wave_ram_wdata    (u_wave_ram_wdata),
    .trigger_pulse     (u_trigger_pulse),
    .trigger_snapshot_ptr(u_trigger_snapshot_ptr)
);

// 电流时域波形捕获模块，跟随电压触发对齐刷新。
time_wave_display_capture #(
    .FULL_SCALE_CODE(WAVE_FULL_SCALE_CODE)
) u_i_time_wave_display_capture (
    .wave_clk          (wave_clk),
    .sys_rst_n         (sys_rst_n),
    .wave_sample_valid (i_wave_sample_valid),
    .wave_sample_code  (i_wave_sample_code),
    .wave_zero_code    (i_wave_zero_code),
    .wave_zero_valid   (i_wave_zero_valid),
    .trigger_force     (u_trigger_pulse),
    .trigger_force_snapshot_ptr(u_trigger_snapshot_ptr),
    .trigger_use_external(1'b1),
    .display_freeze    (freeze_active_wave),
    .wave_frame_valid  (i_wave_frame_valid),
    .wave_display_bank (i_wave_display_bank),
    .wave_ram_we       (i_wave_ram_we),
    .wave_ram_waddr    (i_wave_ram_waddr),
    .wave_ram_wdata    (i_wave_ram_wdata),
    .trigger_pulse     (),
    .trigger_snapshot_ptr()
);

// 时域测量预处理模块，生成 RMS、频率、功率等文本字段。
time_text_display_preprocess #(
    .SAMPLE_WIDTH      (16),
    .START_DELAY_CYCLES(TEXT_REFRESH_CYCLES)
) u_time_text_display_preprocess (
    .clk               (wave_clk),
    .rst_n             (sys_rst_n),
    .lcd_frame_done_toggle(lcd_frame_done_toggle),
    .lcd_swap_ack_toggle(text_swap_ack_toggle_lcd),
    .u_sample_valid    (u_wave_sample_valid),
    .u_sample_code     (u_wave_sample_code),
    .u_zero_code       (u_wave_zero_code),
    .u_zero_valid      (u_wave_zero_valid),
    .i_sample_valid    (i_wave_sample_valid),
    .i_sample_code     (i_wave_sample_code),
    .i_zero_code       (i_wave_zero_code),
    .i_zero_valid      (i_wave_zero_valid),
    .u_full_scale_x100 (u_full_scale_x100_wave),
    .i_full_scale_x100 (i_full_scale_x100_wave),
    .fft_freq_period_raw(fft_fund_freq_period_raw),
    .fft_freq_valid    (fft_fund_freq_valid),
    .fft_phase1_raw_x100(freq_phase1_raw_x100),
    .fft_phase1_valid  (freq_phase1_raw_valid),
    .text_result_commit_toggle(text_result_commit_toggle),
    .u_rms_hundreds    (u_rms_hundreds),
    .u_rms_tens        (u_rms_tens),
    .u_rms_units       (u_rms_units),
    .u_rms_decile      (u_rms_decile),
    .u_rms_percentiles (u_rms_percentiles),
    .u_rms_digits_valid(u_rms_digits_valid),
    .i_rms_hundreds    (i_rms_hundreds),
    .i_rms_tens        (i_rms_tens),
    .i_rms_units       (i_rms_units),
    .i_rms_decile      (i_rms_decile),
    .i_rms_percentiles (i_rms_percentiles),
    .i_rms_digits_valid(i_rms_digits_valid),
    .phase_hundreds    (phase_hundreds),
    .phase_tens        (phase_tens),
    .phase_units       (phase_units),
    .phase_decile      (phase_decile),
    .phase_percentiles (phase_percentiles),
    .phase_x100_signed (phase_x100_signed),
    .phase_neg         (phase_neg),
    .phase_valid       (phase_valid),
    .freq_hundreds     (freq_hundreds),
    .freq_tens         (freq_tens),
    .freq_units        (freq_units),
    .freq_decile       (freq_decile),
    .freq_percentiles  (freq_percentiles),
    .freq_valid        (freq_valid),
    .u_pp_hundreds     (u_pp_hundreds),
    .u_pp_tens         (u_pp_tens),
    .u_pp_units        (u_pp_units),
    .u_pp_decile       (u_pp_decile),
    .u_pp_percentiles  (u_pp_percentiles),
    .u_pp_digits_valid (u_pp_digits_valid),
    .i_pp_hundreds     (i_pp_hundreds),
    .i_pp_tens         (i_pp_tens),
    .i_pp_units        (i_pp_units),
    .i_pp_decile       (i_pp_decile),
    .i_pp_percentiles  (i_pp_percentiles),
    .i_pp_digits_valid (i_pp_digits_valid),
    .active_p_neg      (active_p_neg),
    .active_p_hundreds (active_p_hundreds),
    .active_p_tens     (active_p_tens),
    .active_p_units    (active_p_units),
    .active_p_decile   (active_p_decile),
    .active_p_percentiles(active_p_percentiles),
    .reactive_q_neg    (reactive_q_neg),
    .reactive_q_hundreds(reactive_q_hundreds),
    .reactive_q_tens   (reactive_q_tens),
    .reactive_q_units  (reactive_q_units),
    .reactive_q_decile (reactive_q_decile),
    .reactive_q_percentiles(reactive_q_percentiles),
    .apparent_s_hundreds(apparent_s_hundreds),
    .apparent_s_tens   (apparent_s_tens),
    .apparent_s_units  (apparent_s_units),
    .apparent_s_decile (apparent_s_decile),
    .apparent_s_percentiles(apparent_s_percentiles),
    .power_factor_neg  (power_factor_neg),
    .power_factor_units(power_factor_units),
    .power_factor_decile(power_factor_decile),
    .power_factor_percentiles(power_factor_percentiles),
    .power_metrics_valid(power_metrics_valid),
    .sharp_alarm_active(sharp_alarm_active),
    .sharp_alarm_code (sharp_alarm_code)
);

// 在 wave_clk 域合并时域和频域文本提交沿，驱动文本包交换。
always @(posedge wave_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        text_result_commit_toggle_d1_wave      <= 1'b0;
        freq_text_result_commit_toggle_d1_wave <= 1'b0;
        text_packet_commit_toggle_wave         <= 1'b0;
    end else begin
        text_result_commit_toggle_d1_wave      <= text_result_commit_toggle;
        freq_text_result_commit_toggle_d1_wave <= freq_text_result_commit_toggle;

        if (text_result_commit_edge_wave || freq_text_result_commit_edge_wave)
            text_packet_commit_toggle_wave <= ~text_packet_commit_toggle_wave;
    end
end

// UART 测量串流模块，将文本包和谐波信息序列化输出。
uart_measurement_streamer #(
    .PACKET_WIDTH    (TEXT_PACKET_WIDTH),
    .CLK_FREQ        (50_000_000),
    .SEND_GAP_CYCLES (5_000_000)
) u_uart_measurement_streamer (
    .clk                     (wave_clk),
    .rst_n                   (sys_rst_n),
    .text_packet             (text_packet_wave),
    .text_packet_commit_toggle(text_packet_commit_toggle_wave),
    .harmonic_fire           (freq_harmonic_fire),
    .harmonic_last           (freq_harmonic_last),
    .harmonic_order          (freq_harmonic_order_stream),
    .harmonic_present        (freq_harmonic_present_stream),
    .harmonic_u_pct_x100     (freq_harmonic_u_pct_x100),
    .harmonic_i_pct_x100     (freq_harmonic_i_pct_x100),
    .harmonic_phase_diff_valid(freq_phase_diff_valid_stream),
    .harmonic_phase_diff_deg_x100(freq_phase_diff_deg_x100),
    .uart_tx_busy            (uart_tx_busy),
    .uart_tx_en              (uart_stream_tx_en_wire),
    .uart_tx_data            (uart_stream_tx_data_wire)
);

// 文本包双缓冲模块，在 wave_clk 与 lcd_pclk 之间安全交换整包数据。
text_packet_double_buffer #(
    .PACKET_WIDTH (TEXT_PACKET_WIDTH)
) u_text_packet_double_buffer (
    .wave_clk                  (wave_clk),
    .lcd_pclk                  (lcd_pclk),
    .rst_n                     (sys_rst_n),
    .packet_in_wave            (text_packet_wave),
    .packet_commit_toggle_wave (text_packet_commit_toggle_wave),
    .frame_edge_lcd            (frame_edge_lcd),
    .lcd_swap_ack_toggle       (text_swap_ack_toggle_lcd),
    .packet_pending_lcd        (text_commit_pending_lcd),
    .packet_front_lcd          (text_packet_front_lcd)
);

// 频域分析顶层，输出基波频率、谐波幅值和相位差流。
freq_analysis_top u_freq_analysis_top (
    .sample_clk                 (wave_clk),
    .fft_clk                    (wave_clk),
    .rst_n                      (sys_rst_n),
    .analysis_enable            (1'b1),
    .sample_valid               (freq_sample_valid),
    .sample_frame_marker        (freq_sample_valid),
    .u_sample_code              (u_wave_sample_code),
    .u_zero_code                (u_wave_zero_code),
    .u_zero_valid               (u_wave_zero_valid),
    .i_sample_code              (i_wave_sample_code),
    .i_zero_code                (i_wave_zero_code),
    .i_zero_valid               (i_wave_zero_valid),
    .m_mag_ready                (1'b1),
    .m_harmonic_ready           (freq_harmonic_ready),
    .sample_accepted            (),
    .sample_dropped             (),
    .fifo_full                  (),
    .fifo_prog_full             (),
    .fifo_empty                 (),
    .fifo_prog_empty            (),
    .fifo_overflow_warn         (),
    .fifo_overflow              (),
    .fifo_underflow_warn        (),
    .fifo_underflow             (),
    .fifo_fft_frame_ready       (),
    .fifo_wr_data_count         (),
    .fifo_rd_data_count         (),
    .fifo_wr_marker_count       (),
    .fifo_rd_marker_count       (),
    .fifo_wr_fft_frame_count    (),
    .fifo_rd_fft_frame_count    (),
    .fft_config_done            (),
    .fft_input_busy             (),
    .fft_input_tvalid           (),
    .fft_input_tready           (),
    .fft_input_tlast            (),
    .fft_output_valid           (),
    .fft_output_last            (),
    .fft_bin_index              (),
    .fft_status_tdata           (),
    .fft_status_valid           (),
    .event_frame_started        (),
    .event_tlast_unexpected     (),
    .event_tlast_missing        (),
    .event_fft_overflow         (),
    .event_status_channel_halt  (),
    .event_data_in_channel_halt (),
    .event_data_out_channel_halt(),
    .selected_raw_frame_active  (),
    .selected_raw_frame_done    (),
    .selected_frame_done        (),
    .selected_raw_bin_count     (),
    .selected_bin_count         (),
    .selected_last_raw_bin_count(),
    .selected_last_bin_count    (),
    .selected_frame_count       (),
    .m_mag_valid                (),
    .m_mag_last                 (),
    .m_bin_index                (),
    .m_u_real                   (),
    .m_u_imag                   (),
    .m_i_real                   (),
    .m_i_imag                   (),
    .m_u_mag_sq                 (),
    .m_u_mag                    (),
    .m_i_mag_sq                 (),
    .m_i_mag                    (),
    .mag_calc_busy              (),
    .mag_frame_done             (),
    .mag_frame_count            (),
    .fund_freq_period_raw       (fft_fund_freq_period_raw),
    .fund_freq_valid            (fft_fund_freq_valid),
    .m_harmonic_valid           (freq_harmonic_valid),
    .m_harmonic_last            (freq_harmonic_last),
    .m_harmonic_order           (freq_harmonic_order_stream),
    .m_harmonic_present         (freq_harmonic_present_stream),
    .m_harmonic_u_real          (),
    .m_harmonic_u_imag          (),
    .m_harmonic_i_real          (),
    .m_harmonic_i_imag          (),
    .m_harmonic_u_mag           (freq_harmonic_u_mag),
    .m_harmonic_i_mag           (freq_harmonic_i_mag),
    .m_harmonic_u_pct_x100      (freq_harmonic_u_pct_x100),
    .m_harmonic_i_pct_x100      (freq_harmonic_i_pct_x100),
    .m_phase_vector_valid       (),
    .m_phase_dot                (),
    .m_phase_cross              (),
    .m_phase_diff_valid         (freq_phase_diff_valid_stream),
    .m_phase_diff_deg_x100      (freq_phase_diff_deg_x100),
    .harmonic_stats_busy        (),
    .harmonic_capture_frame_done(),
    .harmonic_frame_done        (),
    .harmonic_frame_count       (),
    .harmonic_u_total_mag       (),
    .harmonic_i_total_mag       (),
    .phase_deg_busy             (),
    .phase_deg_frame_done       (),
    .phase_deg_frame_count      ()
);

// 当谐波结果有效且下游准备就绪时，发出一次谐波拍。
assign freq_harmonic_fire = freq_harmonic_valid && freq_harmonic_ready;

// 将谐波流聚合为 THD、基波幅值、直流分量等原始指标。
freq_metrics_raw_calc u_freq_metrics_raw_calc (
    .clk                    (wave_clk),
    .rst_n                  (sys_rst_n),
    .enable                 (1'b1),
    .s_harmonic_fire        (freq_harmonic_fire),
    .s_harmonic_last        (freq_harmonic_last),
    .s_harmonic_order       (freq_harmonic_order_stream),
    .s_harmonic_present     (freq_harmonic_present_stream),
    .s_u_mag                (freq_harmonic_u_mag),
    .s_i_mag                (freq_harmonic_i_mag),
    .s_u_pct_x100           (freq_harmonic_u_pct_x100),
    .s_i_pct_x100           (freq_harmonic_i_pct_x100),
    .s_phase_diff_valid     (freq_phase_diff_valid_stream),
    .s_phase_diff_deg_x100  (freq_phase_diff_deg_x100),
    .raw_result_commit_toggle(freq_metrics_raw_commit_toggle),
    .thd_u_raw_x100         (freq_thd_u_raw_x100),
    .thd_i_raw_x100         (freq_thd_i_raw_x100),
    .thd_u_valid            (freq_thd_u_raw_valid),
    .thd_i_valid            (freq_thd_i_raw_valid),
    .u1_mag_raw_x100        (freq_u1_mag_raw_x100),
    .i1_mag_raw_x100        (freq_i1_mag_raw_x100),
    .u1_mag_valid           (freq_u1_mag_raw_valid),
    .i1_mag_valid           (freq_i1_mag_raw_valid),
    .phase1_raw_x100        (freq_phase1_raw_x100),
    .phase1_valid           (freq_phase1_raw_valid),
    .dc_u_raw_x100          (freq_dc_u_raw_x100),
    .dc_i_raw_x100          (freq_dc_i_raw_x100),
    .dc_u_valid             (freq_dc_u_raw_valid),
    .dc_i_valid             (freq_dc_i_raw_valid),
    .dh_order_u_list_raw    (freq_dh_order_u_list_raw),
    .dh_order_i_list_raw    (freq_dh_order_i_list_raw),
    .dh_order_u_count_raw   (freq_dh_order_u_count_raw),
    .dh_order_i_count_raw   (freq_dh_order_i_count_raw),
    .dh_order_u_valid       (freq_dh_order_u_raw_valid),
    .dh_order_i_valid       (freq_dh_order_i_raw_valid),
    .metrics_valid          (freq_metrics_raw_valid)
);

// 频域文本预处理模块，把原始指标转换成 LCD 文本字段。
freq_text_display_preprocess u_freq_text_display_preprocess (
    .clk                    (wave_clk),
    .rst_n                  (sys_rst_n),
    .lcd_frame_done_toggle  (lcd_frame_done_toggle),
    .lcd_swap_ack_toggle    (text_swap_ack_toggle_lcd),
    .raw_result_commit_toggle(freq_metrics_raw_commit_toggle),
    .thd_u_raw_x100         (freq_thd_u_raw_x100),
    .thd_i_raw_x100         (freq_thd_i_raw_x100),
    .thd_u_valid_in         (freq_thd_u_raw_valid),
    .thd_i_valid_in         (freq_thd_i_raw_valid),
    .u1_mag_raw_x100        (freq_u1_mag_raw_x100),
    .i1_mag_raw_x100        (freq_i1_mag_raw_x100),
    .u1_mag_valid_in        (freq_u1_mag_raw_valid),
    .i1_mag_valid_in        (freq_i1_mag_raw_valid),
    .phase1_raw_x100        (freq_phase1_raw_x100),
    .phase1_valid_in        (freq_phase1_raw_valid),
    .dc_u_raw_x100          (freq_dc_u_raw_x100),
    .dc_i_raw_x100          (freq_dc_i_raw_x100),
    .dc_u_valid_in          (freq_dc_u_raw_valid),
    .dc_i_valid_in          (freq_dc_i_raw_valid),
    .dh_order_u_list_raw    (freq_dh_order_u_list_raw),
    .dh_order_i_list_raw    (freq_dh_order_i_list_raw),
    .dh_order_u_count_raw   (freq_dh_order_u_count_raw),
    .dh_order_i_count_raw   (freq_dh_order_i_count_raw),
    .dh_order_u_valid_in    (freq_dh_order_u_raw_valid),
    .dh_order_i_valid_in    (freq_dh_order_i_raw_valid),
    .freq_text_result_commit_toggle(freq_text_result_commit_toggle),
    .thd_u_hundreds         (freq_thd_u_hundreds),
    .thd_u_tens             (freq_thd_u_tens),
    .thd_u_units            (freq_thd_u_units),
    .thd_u_decile           (freq_thd_u_decile),
    .thd_u_percentiles      (freq_thd_u_percentiles),
    .thd_u_valid            (freq_thd_u_valid),
    .thd_i_hundreds         (freq_thd_i_hundreds),
    .thd_i_tens             (freq_thd_i_tens),
    .thd_i_units            (freq_thd_i_units),
    .thd_i_decile           (freq_thd_i_decile),
    .thd_i_percentiles      (freq_thd_i_percentiles),
    .thd_i_valid            (freq_thd_i_valid),
    .u1_mag_hundreds        (freq_u1_mag_hundreds),
    .u1_mag_tens            (freq_u1_mag_tens),
    .u1_mag_units           (freq_u1_mag_units),
    .u1_mag_decile          (freq_u1_mag_decile),
    .u1_mag_percentiles     (freq_u1_mag_percentiles),
    .u1_mag_valid           (freq_u1_mag_valid),
    .i1_mag_hundreds        (freq_i1_mag_hundreds),
    .i1_mag_tens            (freq_i1_mag_tens),
    .i1_mag_units           (freq_i1_mag_units),
    .i1_mag_decile          (freq_i1_mag_decile),
    .i1_mag_percentiles     (freq_i1_mag_percentiles),
    .i1_mag_valid           (freq_i1_mag_valid),
    .phase1_neg             (freq_phase1_neg),
    .phase1_hundreds        (freq_phase1_hundreds),
    .phase1_tens            (freq_phase1_tens),
    .phase1_units           (freq_phase1_units),
    .phase1_decile          (freq_phase1_decile),
    .phase1_percentiles     (freq_phase1_percentiles),
    .phase1_valid           (freq_phase1_valid),
    .dc_u_hundreds          (freq_dc_u_hundreds),
    .dc_u_tens              (freq_dc_u_tens),
    .dc_u_units             (freq_dc_u_units),
    .dc_u_decile            (freq_dc_u_decile),
    .dc_u_percentiles       (freq_dc_u_percentiles),
    .dc_u_valid             (freq_dc_u_valid),
    .dc_i_hundreds          (freq_dc_i_hundreds),
    .dc_i_tens              (freq_dc_i_tens),
    .dc_i_units             (freq_dc_i_units),
    .dc_i_decile            (freq_dc_i_decile),
    .dc_i_percentiles       (freq_dc_i_percentiles),
    .dc_i_valid             (freq_dc_i_valid),
    .dh_order_u_text        (freq_dh_order_u_text),
    .dh_order_i_text        (freq_dh_order_i_text)
);

// 频域显示适配模块，把谐波流压缩为柱图和相位图 RAM 数据。
freq_display_adapter u_freq_display_adapter (
    .clk                    (wave_clk),
    .rst_n                  (sys_rst_n),
    .enable                 (1'b1),
    .s_harmonic_valid       (freq_harmonic_valid),
    .s_harmonic_ready       (freq_harmonic_ready),
    .s_harmonic_last        (freq_harmonic_last),
    .s_harmonic_order       (freq_harmonic_order_stream),
    .s_harmonic_present     (freq_harmonic_present_stream),
    .s_u_pct_x100           (freq_harmonic_u_pct_x100),
    .s_i_pct_x100           (freq_harmonic_i_pct_x100),
    .s_phase_diff_valid     (freq_phase_diff_valid_stream),
    .s_phase_diff_deg_x100  (freq_phase_diff_deg_x100),
    .freq_ram_we            (freq_ram_we),
    .freq_ram_waddr         (freq_ram_waddr),
    .freq_u_mag_wdata       (freq_u_mag_wdata),
    .freq_i_mag_wdata       (freq_i_mag_wdata),
    .freq_phase_wdata       (freq_phase_wdata),
    .freq_flag_wdata        (freq_flag_wdata),
    .display_bank           (freq_display_bank),
    .frame_valid            (freq_frame_valid),
    .frame_sequence         ()
);

// 在 wave_clk 域同步冻结状态和频域前台 bank。
always @(posedge wave_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        freeze_active_wave_sync1    <= 1'b0;
        freeze_active_wave_sync2    <= 1'b0;
        freq_front_bank_wave_sync1  <= 1'b0;
        freq_front_bank_wave_sync2  <= 1'b0;
    end else begin
        freeze_active_wave_sync1    <= freeze_active_lcd;
        freeze_active_wave_sync2    <= freeze_active_wave_sync1;
        freq_front_bank_wave_sync1  <= freq_front_bank_lcd;
        freq_front_bank_wave_sync2  <= freq_front_bank_wave_sync1;
    end
end

// 背景层模块，生成页面底色、边框和按钮底图。
lcd_display_bg u_lcd_display_bg(
    .pixel_xpos            (pixel_xpos),
    .pixel_ypos            (pixel_ypos),
    .frequency_page_active (frequency_page_active_lcd),
    .mode_button_pressed   (mode_button_pressed),
    .freeze_button_pressed (freeze_button_pressed),
    .harmonic_prev_pressed (harmonic_prev_pressed),
    .harmonic_next_pressed (harmonic_next_pressed),
    .base_color            (base_color)
);

// 文本布局模块，根据页面状态输出字符索引、位置和颜色。
lcd_display_text u_lcd_display_text(
    .pixel_xpos          (pixel_xpos),
    .pixel_ypos          (pixel_ypos),
    .u_rms_hundreds      (u_rms_hundreds_lcd),
    .u_rms_tens          (u_rms_tens_lcd),
    .u_rms_units         (u_rms_units_lcd),
    .u_rms_decile        (u_rms_decile_lcd),
    .u_rms_percentiles   (u_rms_percentiles_lcd),
    .u_rms_digits_valid  (u_rms_digits_valid_lcd),
    .i_rms_hundreds      (i_rms_hundreds_lcd),
    .i_rms_tens          (i_rms_tens_lcd),
    .i_rms_units         (i_rms_units_lcd),
    .i_rms_decile        (i_rms_decile_lcd),
    .i_rms_percentiles   (i_rms_percentiles_lcd),
    .i_rms_digits_valid  (i_rms_digits_valid_lcd),
    .phase_neg           (phase_neg_lcd),
    .phase_hundreds      (phase_hundreds_lcd),
    .phase_tens          (phase_tens_lcd),
    .phase_units         (phase_units_lcd),
    .phase_decile        (phase_decile_lcd),
    .phase_percentiles   (phase_percentiles_lcd),
    .phase_valid         (phase_valid_lcd),
    .freq_hundreds       (freq_hundreds_lcd),
    .freq_tens           (freq_tens_lcd),
    .freq_units          (freq_units_lcd),
    .freq_decile         (freq_decile_lcd),
    .freq_percentiles    (freq_percentiles_lcd),
    .freq_valid          (freq_valid_lcd),
    .u_pp_hundreds       (u_pp_hundreds_lcd),
    .u_pp_tens           (u_pp_tens_lcd),
    .u_pp_units          (u_pp_units_lcd),
    .u_pp_decile         (u_pp_decile_lcd),
    .u_pp_percentiles    (u_pp_percentiles_lcd),
    .u_pp_digits_valid   (u_pp_digits_valid_lcd),
    .i_pp_hundreds       (i_pp_hundreds_lcd),
    .i_pp_tens           (i_pp_tens_lcd),
    .i_pp_units          (i_pp_units_lcd),
    .i_pp_decile         (i_pp_decile_lcd),
    .i_pp_percentiles    (i_pp_percentiles_lcd),
    .i_pp_digits_valid   (i_pp_digits_valid_lcd),
    .active_p_neg        (active_p_neg_lcd),
    .active_p_hundreds   (active_p_hundreds_lcd),
    .active_p_tens       (active_p_tens_lcd),
    .active_p_units      (active_p_units_lcd),
    .active_p_decile     (active_p_decile_lcd),
    .active_p_percentiles(active_p_percentiles_lcd),
    .reactive_q_neg      (reactive_q_neg_lcd),
    .reactive_q_hundreds (reactive_q_hundreds_lcd),
    .reactive_q_tens     (reactive_q_tens_lcd),
    .reactive_q_units    (reactive_q_units_lcd),
    .reactive_q_decile   (reactive_q_decile_lcd),
    .reactive_q_percentiles(reactive_q_percentiles_lcd),
    .apparent_s_hundreds (apparent_s_hundreds_lcd),
    .apparent_s_tens     (apparent_s_tens_lcd),
    .apparent_s_units    (apparent_s_units_lcd),
    .apparent_s_decile   (apparent_s_decile_lcd),
    .apparent_s_percentiles(apparent_s_percentiles_lcd),
    .power_factor_neg    (power_factor_neg_lcd),
    .power_factor_units  (power_factor_units_lcd),
    .power_factor_decile (power_factor_decile_lcd),
    .power_factor_percentiles(power_factor_percentiles_lcd),
    .power_metrics_valid (power_metrics_valid_lcd),
    .sharp_alarm_code    (sharp_alarm_code_lcd),
    .freq_thd_u_hundreds (freq_thd_u_hundreds_lcd),
    .freq_thd_u_tens     (freq_thd_u_tens_lcd),
    .freq_thd_u_units    (freq_thd_u_units_lcd),
    .freq_thd_u_decile   (freq_thd_u_decile_lcd),
    .freq_thd_u_percentiles(freq_thd_u_percentiles_lcd),
    .freq_thd_u_valid    (freq_thd_u_valid_lcd),
    .freq_thd_i_hundreds (freq_thd_i_hundreds_lcd),
    .freq_thd_i_tens     (freq_thd_i_tens_lcd),
    .freq_thd_i_units    (freq_thd_i_units_lcd),
    .freq_thd_i_decile   (freq_thd_i_decile_lcd),
    .freq_thd_i_percentiles(freq_thd_i_percentiles_lcd),
    .freq_thd_i_valid    (freq_thd_i_valid_lcd),
    .freq_u1_mag_hundreds(freq_u1_mag_hundreds_lcd),
    .freq_u1_mag_tens    (freq_u1_mag_tens_lcd),
    .freq_u1_mag_units   (freq_u1_mag_units_lcd),
    .freq_u1_mag_decile  (freq_u1_mag_decile_lcd),
    .freq_u1_mag_percentiles(freq_u1_mag_percentiles_lcd),
    .freq_u1_mag_valid   (freq_u1_mag_valid_lcd),
    .freq_i1_mag_hundreds(freq_i1_mag_hundreds_lcd),
    .freq_i1_mag_tens    (freq_i1_mag_tens_lcd),
    .freq_i1_mag_units   (freq_i1_mag_units_lcd),
    .freq_i1_mag_decile  (freq_i1_mag_decile_lcd),
    .freq_i1_mag_percentiles(freq_i1_mag_percentiles_lcd),
    .freq_i1_mag_valid   (freq_i1_mag_valid_lcd),
    .freq_phase1_neg     (freq_phase1_neg_lcd),
    .freq_phase1_hundreds(freq_phase1_hundreds_lcd),
    .freq_phase1_tens    (freq_phase1_tens_lcd),
    .freq_phase1_units   (freq_phase1_units_lcd),
    .freq_phase1_decile  (freq_phase1_decile_lcd),
    .freq_phase1_percentiles(freq_phase1_percentiles_lcd),
    .freq_phase1_valid   (freq_phase1_valid_lcd),
    .freq_dc_u_hundreds  (freq_dc_u_hundreds_lcd),
    .freq_dc_u_tens      (freq_dc_u_tens_lcd),
    .freq_dc_u_units     (freq_dc_u_units_lcd),
    .freq_dc_u_decile    (freq_dc_u_decile_lcd),
    .freq_dc_u_percentiles(freq_dc_u_percentiles_lcd),
    .freq_dc_u_valid     (freq_dc_u_valid_lcd),
    .freq_dc_i_hundreds  (freq_dc_i_hundreds_lcd),
    .freq_dc_i_tens      (freq_dc_i_tens_lcd),
    .freq_dc_i_units     (freq_dc_i_units_lcd),
    .freq_dc_i_decile    (freq_dc_i_decile_lcd),
    .freq_dc_i_percentiles(freq_dc_i_percentiles_lcd),
    .freq_dc_i_valid     (freq_dc_i_valid_lcd),
    .freq_dh_order_u_text(freq_dh_order_u_text_lcd),
    .freq_dh_order_i_text(freq_dh_order_i_text_lcd),
    .full_scale_low_range_active(full_scale_low_range_active_lcd),
    .freeze_active       (freeze_active_lcd),
    .frequency_page_active(frequency_page_active_lcd),
    .harmonic_window_index(harmonic_window_index_lcd),
    .text_en             (text_en),
    .text_font_small     (text_font_small),
    .text_char_idx       (text_char_idx),
    .text_rel_x          (text_rel_x),
    .text_rel_y          (text_rel_y),
    .text_color          (text_color)
);

// 电压波形双口显示 RAM：wave_clk 写入，lcd_pclk 读出。
blk_mem_gen_ram0 u_u_wave_frame_ram(
    .clka  (wave_clk),
    .ena   (1'b1),
    .wea   ({u_wave_ram_we}),
    .addra (u_wave_ram_waddr),
    .dina  (u_wave_ram_wdata),
    .douta (u_wave_ram_douta),
    .clkb  (lcd_pclk),
    .web   ({1'b0}),
    .addrb (u_wave_ram_raddr),
    .dinb  (8'd0),
    .doutb (u_wave_ram_doutb)
);

// 电流波形双口显示 RAM：wave_clk 写入，lcd_pclk 读出。
blk_mem_gen_ram0 u_i_wave_frame_ram(
    .clka  (wave_clk),
    .ena   (1'b1),
    .wea   ({i_wave_ram_we}),
    .addra (i_wave_ram_waddr),
    .dina  (i_wave_ram_wdata),
    .douta (i_wave_ram_douta),
    .clkb  (lcd_pclk),
    .web   ({1'b0}),
    .addrb (i_wave_ram_raddr),
    .dinb  (8'd0),
    .doutb (i_wave_ram_doutb)
);

// 频域电压幅值显示 RAM。
blk_mem_gen_ram0 u_freq_u_mag_display_ram(
    .clka  (wave_clk),
    .ena   (1'b1),
    .wea   ({freq_ram_store_we}),
    .addra (freq_ram_waddr),
    .dina  (freq_u_mag_wdata),
    .douta (),
    .clkb  (lcd_pclk),
    .web   ({1'b0}),
    .addrb (freq_ram_raddr),
    .dinb  (8'd0),
    .doutb (freq_u_mag_ram_doutb)
);

// 频域电流幅值显示 RAM。
blk_mem_gen_ram0 u_freq_i_mag_display_ram(
    .clka  (wave_clk),
    .ena   (1'b1),
    .wea   ({freq_ram_store_we}),
    .addra (freq_ram_waddr),
    .dina  (freq_i_mag_wdata),
    .douta (),
    .clkb  (lcd_pclk),
    .web   ({1'b0}),
    .addrb (freq_ram_raddr),
    .dinb  (8'd0),
    .doutb (freq_i_mag_ram_doutb)
);

// 频域相位柱高显示 RAM。
blk_mem_gen_ram0 u_freq_phase_display_ram(
    .clka  (wave_clk),
    .ena   (1'b1),
    .wea   ({freq_ram_store_we}),
    .addra (freq_ram_waddr),
    .dina  (freq_phase_wdata),
    .douta (),
    .clkb  (lcd_pclk),
    .web   ({1'b0}),
    .addrb (freq_ram_raddr),
    .dinb  (8'd0),
    .doutb (freq_phase_ram_doutb)
);

// 频域标志显示 RAM，保存谐波存在位和相位符号位。
blk_mem_gen_ram0 u_freq_flag_display_ram(
    .clka  (wave_clk),
    .ena   (1'b1),
    .wea   ({freq_ram_store_we}),
    .addra (freq_ram_waddr),
    .dina  (freq_flag_wdata),
    .douta (),
    .clkb  (lcd_pclk),
    .web   ({1'b0}),
    .addrb (freq_ram_raddr),
    .dinb  (8'd0),
    .doutb (freq_flag_ram_doutb)
);

// 将频谱图区列坐标映射为 0~25 的谐波桶索引。
function [4:0] freq_bucket_from_col;
    input [10:0] col_value;
    begin
        if (col_value < 11'd17)
            freq_bucket_from_col = 5'd0;
        else if (col_value < 11'd34)
            freq_bucket_from_col = 5'd1;
        else if (col_value < 11'd51)
            freq_bucket_from_col = 5'd2;
        else if (col_value < 11'd68)
            freq_bucket_from_col = 5'd3;
        else if (col_value < 11'd85)
            freq_bucket_from_col = 5'd4;
        else if (col_value < 11'd102)
            freq_bucket_from_col = 5'd5;
        else if (col_value < 11'd119)
            freq_bucket_from_col = 5'd6;
        else if (col_value < 11'd136)
            freq_bucket_from_col = 5'd7;
        else if (col_value < 11'd153)
            freq_bucket_from_col = 5'd8;
        else if (col_value < 11'd170)
            freq_bucket_from_col = 5'd9;
        else if (col_value < 11'd187)
            freq_bucket_from_col = 5'd10;
        else if (col_value < 11'd204)
            freq_bucket_from_col = 5'd11;
        else if (col_value < 11'd221)
            freq_bucket_from_col = 5'd12;
        else if (col_value < 11'd238)
            freq_bucket_from_col = 5'd13;
        else if (col_value < 11'd255)
            freq_bucket_from_col = 5'd14;
        else if (col_value < 11'd272)
            freq_bucket_from_col = 5'd15;
        else if (col_value < 11'd289)
            freq_bucket_from_col = 5'd16;
        else if (col_value < 11'd306)
            freq_bucket_from_col = 5'd17;
        else if (col_value < 11'd323)
            freq_bucket_from_col = 5'd18;
        else if (col_value < 11'd340)
            freq_bucket_from_col = 5'd19;
        else if (col_value < 11'd357)
            freq_bucket_from_col = 5'd20;
        else if (col_value < 11'd374)
            freq_bucket_from_col = 5'd21;
        else if (col_value < 11'd391)
            freq_bucket_from_col = 5'd22;
        else if (col_value < 11'd408)
            freq_bucket_from_col = 5'd23;
        else if (col_value < 11'd425)
            freq_bucket_from_col = 5'd24;
        else
            freq_bucket_from_col = 5'd25;
    end
endfunction

// 计算当前谐波桶内部的子列偏移。
function [4:0] freq_sub_col_from_col;
    input [10:0] col_value;
    begin
        if (col_value < 11'd17)
            freq_sub_col_from_col = col_value;
        else if (col_value < 11'd34)
            freq_sub_col_from_col = col_value - 11'd17;
        else if (col_value < 11'd51)
            freq_sub_col_from_col = col_value - 11'd34;
        else if (col_value < 11'd68)
            freq_sub_col_from_col = col_value - 11'd51;
        else if (col_value < 11'd85)
            freq_sub_col_from_col = col_value - 11'd68;
        else if (col_value < 11'd102)
            freq_sub_col_from_col = col_value - 11'd85;
        else if (col_value < 11'd119)
            freq_sub_col_from_col = col_value - 11'd102;
        else if (col_value < 11'd136)
            freq_sub_col_from_col = col_value - 11'd119;
        else if (col_value < 11'd153)
            freq_sub_col_from_col = col_value - 11'd136;
        else if (col_value < 11'd170)
            freq_sub_col_from_col = col_value - 11'd153;
        else if (col_value < 11'd187)
            freq_sub_col_from_col = col_value - 11'd170;
        else if (col_value < 11'd204)
            freq_sub_col_from_col = col_value - 11'd187;
        else if (col_value < 11'd221)
            freq_sub_col_from_col = col_value - 11'd204;
        else if (col_value < 11'd238)
            freq_sub_col_from_col = col_value - 11'd221;
        else if (col_value < 11'd255)
            freq_sub_col_from_col = col_value - 11'd238;
        else if (col_value < 11'd272)
            freq_sub_col_from_col = col_value - 11'd255;
        else if (col_value < 11'd289)
            freq_sub_col_from_col = col_value - 11'd272;
        else if (col_value < 11'd306)
            freq_sub_col_from_col = col_value - 11'd289;
        else if (col_value < 11'd323)
            freq_sub_col_from_col = col_value - 11'd306;
        else if (col_value < 11'd340)
            freq_sub_col_from_col = col_value - 11'd323;
        else if (col_value < 11'd357)
            freq_sub_col_from_col = col_value - 11'd340;
        else if (col_value < 11'd374)
            freq_sub_col_from_col = col_value - 11'd357;
        else if (col_value < 11'd391)
            freq_sub_col_from_col = col_value - 11'd374;
        else if (col_value < 11'd408)
            freq_sub_col_from_col = col_value - 11'd391;
        else if (col_value < 11'd425)
            freq_sub_col_from_col = col_value - 11'd408;
        else
            freq_sub_col_from_col = col_value - 11'd425;
    end
endfunction

// 生成空白字符保护和字体索引。
assign text_blank        = (text_char_idx == FONT_BLANK);
assign font_char_idx     = text_blank ? 7'd0 : text_char_idx;
// 10x20 字模每行有效位使用 bit[10:1]，因此位索引从 10 递减。
assign font_10x20_bit_idx = 4'd10 - text_rel_x_d1[3:0];
// 生成 LCD 帧边沿、频域采样有效和频域 RAM 写使能。
assign frame_edge_lcd    = lcd_frame_done_toggle ^ lcd_frame_done_toggle_d1;
assign freq_sample_valid = u_wave_sample_valid && i_wave_sample_valid;
assign freq_ram_store_we = freq_ram_we &&
                           (!freeze_active_wave ||
                            (freq_ram_waddr[9] != freq_front_bank_wave_sync2));
// 触摸同步、按钮命中和点击资格判定。
assign touch_pressed_lcd = touch_pressed_sync2;
assign touch_pressed_fall_lcd = touch_pressed_sync3 && !touch_pressed_sync2;
assign mode_button_touch_hit =
    (touch_x >= MODE_BTN_X) && (touch_x < (MODE_BTN_X + MODE_BTN_W)) &&
    (touch_y >= MODE_BTN_Y) && (touch_y < (MODE_BTN_Y + MODE_BTN_H));
assign mode_button_start_hit =
    (touch_start_x >= MODE_BTN_X) && (touch_start_x < (MODE_BTN_X + MODE_BTN_W)) &&
    (touch_start_y >= MODE_BTN_Y) && (touch_start_y < (MODE_BTN_Y + MODE_BTN_H));
assign mode_button_pressed = touch_pressed_lcd && mode_button_touch_hit;
assign mode_button_click_qualified =
    touch_pressed_fall_lcd &&
    mode_button_touch_hit &&
    mode_button_start_hit &&
    (touch_press_time_ms >= FREEZE_MIN_PRESS_MS) &&
    (touch_press_time_ms <= FREEZE_MAX_PRESS_MS);
assign freeze_button_touch_hit =
    (touch_x >= FREEZE_BTN_X) && (touch_x < (FREEZE_BTN_X + FREEZE_BTN_W)) &&
    (touch_y >= FREEZE_BTN_Y) && (touch_y < (FREEZE_BTN_Y + FREEZE_BTN_H));
assign freeze_button_start_hit =
    (touch_start_x >= FREEZE_BTN_X) && (touch_start_x < (FREEZE_BTN_X + FREEZE_BTN_W)) &&
    (touch_start_y >= FREEZE_BTN_Y) && (touch_start_y < (FREEZE_BTN_Y + FREEZE_BTN_H));
assign freeze_button_pressed = touch_pressed_lcd && freeze_button_touch_hit;
assign freeze_button_click_qualified =
    touch_pressed_fall_lcd &&
    freeze_button_touch_hit &&
    freeze_button_start_hit &&
    (touch_press_time_ms >= FREEZE_MIN_PRESS_MS) &&
    (touch_press_time_ms <= FREEZE_MAX_PRESS_MS);
assign harmonic_prev_touch_hit =
    frequency_page_active_lcd &&
    (touch_x >= HARM_PREV_X) && (touch_x < (HARM_PREV_X + HARM_BTN_W)) &&
    (touch_y >= HARM_BTN_Y) && (touch_y < (HARM_BTN_Y + HARM_BTN_H));
assign harmonic_next_touch_hit =
    frequency_page_active_lcd &&
    (touch_x >= HARM_NEXT_X) && (touch_x < (HARM_NEXT_X + HARM_BTN_W)) &&
    (touch_y >= HARM_BTN_Y) && (touch_y < (HARM_BTN_Y + HARM_BTN_H));
assign harmonic_prev_start_hit =
    (touch_start_x >= HARM_PREV_X) && (touch_start_x < (HARM_PREV_X + HARM_BTN_W)) &&
    (touch_start_y >= HARM_BTN_Y) && (touch_start_y < (HARM_BTN_Y + HARM_BTN_H));
assign harmonic_next_start_hit =
    (touch_start_x >= HARM_NEXT_X) && (touch_start_x < (HARM_NEXT_X + HARM_BTN_W)) &&
    (touch_start_y >= HARM_BTN_Y) && (touch_start_y < (HARM_BTN_Y + HARM_BTN_H));
assign harmonic_prev_pressed = touch_pressed_lcd && harmonic_prev_touch_hit;
assign harmonic_next_pressed = touch_pressed_lcd && harmonic_next_touch_hit;
assign harmonic_home_qualified =
    touch_pressed_fall_lcd &&
    harmonic_prev_touch_hit &&
    harmonic_prev_start_hit &&
    (touch_press_time_ms >= HARMONIC_LONG_PRESS_MS);
assign harmonic_prev_click_qualified =
    touch_pressed_fall_lcd &&
    harmonic_prev_touch_hit &&
    harmonic_prev_start_hit &&
    (touch_press_time_ms >= FREEZE_MIN_PRESS_MS) &&
    (touch_press_time_ms <= FREEZE_MAX_PRESS_MS);
assign harmonic_next_click_qualified =
    touch_pressed_fall_lcd &&
    harmonic_next_touch_hit &&
    harmonic_next_start_hit &&
    (touch_press_time_ms >= FREEZE_MIN_PRESS_MS) &&
    (touch_press_time_ms <= FREEZE_MAX_PRESS_MS);
// 计算冻结状态以及屏幕是否允许接收新数据。
assign freeze_active_next_lcd = freeze_button_click_qualified ? ~freeze_active_lcd : freeze_active_lcd;
assign screen_update_enable_lcd = !freeze_active_next_lcd;
assign freeze_active_wave = freeze_active_wave_sync2;

// 计算图形区使能以及时域页的列地址。
assign graph_en      = (pixel_xpos >= GRAPH_X) && (pixel_xpos < (GRAPH_X + GRAPH_W)) &&
                       (pixel_ypos > GRAPH_Y) && (pixel_ypos < (GRAPH_Y + GRAPH_H - 1));
assign time_graph_en = !frequency_page_active_lcd && graph_en;
assign graph_col_ext = pixel_xpos - GRAPH_X;
assign graph_col     = graph_col_ext[8:0];
// 根据当前列地址读取前台波形 RAM。
assign u_wave_ram_raddr = time_graph_en ? {u_wave_front_bank_lcd, graph_col} :
                                     {u_wave_front_bank_lcd, 9'd0};
assign i_wave_ram_raddr = time_graph_en ? {i_wave_front_bank_lcd, graph_col} :
                                     {i_wave_front_bank_lcd, 9'd0};

// 将像素列映射为频谱桶、子列和前台频域 RAM 地址。
assign freq_mag_col_ext   = pixel_xpos - FREQ_GRAPH_X;
assign freq_phase_col_ext = pixel_xpos - FREQ_GRAPH_X;
assign freq_mag_bucket    = freq_bucket_from_col(freq_mag_col_ext);
assign freq_mag_sub_col   = freq_sub_col_from_col(freq_mag_col_ext);
assign freq_phase_sub_col = freq_sub_col_from_col(freq_phase_col_ext);
assign freq_window_base = {harmonic_window_index_lcd, 4'b0000} +
                          {1'b0, harmonic_window_index_lcd, 3'b000} +
                          {4'b0000, harmonic_window_index_lcd};
assign freq_display_harmonic_order = freq_window_base + {4'd0, freq_mag_bucket};
assign freq_ram_raddr = {freq_front_bank_lcd, freq_display_harmonic_order};
assign freq_harmonic_present_lcd = freq_front_valid_lcd && freq_flag_ram_doutb[0];
assign freq_phase_valid_lcd = freq_harmonic_present_lcd && freq_flag_ram_doutb[1];
assign freq_u_bar_height = freq_u_mag_ram_doutb;
assign freq_i_bar_height = freq_i_mag_ram_doutb;
assign freq_phase_bar_height = freq_phase_ram_doutb;
assign freq_phase_negative = freq_flag_ram_doutb[2];
assign freq_mag_u_pixel_on =
    frequency_page_active_lcd &&
    freq_harmonic_present_lcd &&
    (pixel_xpos >= FREQ_GRAPH_X) && (pixel_xpos < (FREQ_GRAPH_X + FREQ_GRAPH_W)) &&
    (pixel_ypos >= (FREQ_MAG_BASE_Y - {3'd0, freq_u_bar_height})) &&
    (pixel_ypos < FREQ_MAG_BASE_Y) &&
    (freq_mag_sub_col <= 4'd3);
assign freq_mag_i_pixel_on =
    frequency_page_active_lcd &&
    freq_harmonic_present_lcd &&
    (pixel_xpos >= FREQ_GRAPH_X) && (pixel_xpos < (FREQ_GRAPH_X + FREQ_GRAPH_W)) &&
    (pixel_ypos >= (FREQ_MAG_BASE_Y - {3'd0, freq_i_bar_height})) &&
    (pixel_ypos < FREQ_MAG_BASE_Y) &&
    (freq_mag_sub_col >= 4'd5) && (freq_mag_sub_col <= 4'd8);
assign freq_phase_pixel_on =
    frequency_page_active_lcd &&
    freq_phase_valid_lcd &&
    (pixel_xpos >= FREQ_GRAPH_X) && (pixel_xpos < (FREQ_GRAPH_X + FREQ_GRAPH_W)) &&
    (pixel_ypos >= (FREQ_PHASE_BASE_Y - {3'd0, freq_phase_bar_height})) &&
    (pixel_ypos < FREQ_PHASE_BASE_Y) &&
    (freq_phase_sub_col <= 4'd6);

// 电压波形像素检测模块，根据当前列和相邻点生成连线像素。
wave_pixel_detector #(
    .GRAPH_Y(GRAPH_Y)
) u_wave_pixel_detector_u (
    .graph_en_d1          (graph_en_d1),
    .wave_frame_valid_sync(u_wave_front_valid_lcd),
    .wave_ram_dout        (u_wave_ram_doutb),
    .wave_prev_valid_d1   (u_wave_prev_valid_d1),
    .wave_prev_y_d1       (u_wave_prev_y_d1),
    .wave_prev_col_d1     (u_wave_prev_col_d1),
    .wave_prev_row_d1     (u_wave_prev_row_d1),
    .graph_col_d1         (graph_col_d1),
    .graph_row_d1         (graph_row_d1),
    .wave_y_curr_abs      (u_wave_y_curr_abs),
    .wave_y_prev_abs      (u_wave_y_prev_abs),
    .wave_seg_valid       (u_wave_seg_valid),
    .wave_seg_lo_abs      (u_wave_seg_lo_abs),
    .wave_seg_hi_abs      (u_wave_seg_hi_abs),
    .wave_pixel_on        (u_wave_pixel_on_internal)
);

// 电流波形像素检测模块，根据当前列和相邻点生成连线像素。
wave_pixel_detector #(
    .GRAPH_Y(GRAPH_Y)
) u_wave_pixel_detector_i (
    .graph_en_d1          (graph_en_d1),
    .wave_frame_valid_sync(i_wave_front_valid_lcd),
    .wave_ram_dout        (i_wave_ram_doutb),
    .wave_prev_valid_d1   (i_wave_prev_valid_d1),
    .wave_prev_y_d1       (i_wave_prev_y_d1),
    .wave_prev_col_d1     (i_wave_prev_col_d1),
    .wave_prev_row_d1     (i_wave_prev_row_d1),
    .graph_col_d1         (graph_col_d1),
    .graph_row_d1         (graph_row_d1),
    .wave_y_curr_abs      (i_wave_y_curr_abs),
    .wave_y_prev_abs      (i_wave_y_prev_abs),
    .wave_seg_valid       (i_wave_seg_valid),
    .wave_seg_lo_abs      (i_wave_seg_lo_abs),
    .wave_seg_hi_abs      (i_wave_seg_hi_abs),
    .wave_pixel_on        (i_wave_pixel_on_internal)
);

// 根据字体 ROM 输出生成最终文字像素。
assign text_pixel_on =
    text_en_d1 && !text_blank_d1 &&
    (text_font_small_d1 ?
        ((text_rel_x_d1 < SMALL_CHAR_W) ? font_row_10x20_rom[font_10x20_bit_idx] : 1'b0) :
        ((text_rel_x_d1 < BIG_CHAR_W)   ? font_row_16x32_rom[15 - text_rel_x_d1[3:0]] : 1'b0));

// 时域波形像素由 wave_pixel_detector 模块输出。
assign u_wave_pixel_on = u_wave_pixel_on_internal;
assign i_wave_pixel_on = i_wave_pixel_on_internal;

// LCD 像素域主时序：锁存前台显示数据、切换 front bank 并输出像素颜色。
always @(posedge lcd_pclk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        base_color_d1         <= BG_COLOR;
        text_color_d1         <= TEXT_WHITE;
        text_en_d1            <= 1'b0;
        text_font_small_d1    <= 1'b0;
        text_char_idx_d1      <= 7'd0;
        text_rel_x_d1         <= 6'd0;
        text_blank_d1         <= 1'b1;
        u_rms_hundreds_lcd    <= 8'd0;
        u_rms_tens_lcd        <= 8'd0;
        u_rms_units_lcd       <= 8'd0;
        u_rms_decile_lcd      <= 8'd0;
        u_rms_percentiles_lcd <= 8'd0;
        u_rms_digits_valid_lcd <= 1'b0;
        i_rms_hundreds_lcd    <= 8'd0;
        i_rms_tens_lcd        <= 8'd0;
        i_rms_units_lcd       <= 8'd0;
        i_rms_decile_lcd      <= 8'd0;
        i_rms_percentiles_lcd <= 8'd0;
        i_rms_digits_valid_lcd <= 1'b0;
        phase_neg_lcd         <= 1'b0;
        phase_hundreds_lcd    <= 8'd0;
        phase_tens_lcd        <= 8'd0;
        phase_units_lcd       <= 8'd0;
        phase_decile_lcd      <= 8'd0;
        phase_percentiles_lcd <= 8'd0;
        phase_valid_lcd       <= 1'b0;
        freq_hundreds_lcd     <= 8'd0;
        freq_tens_lcd         <= 8'd0;
        freq_units_lcd        <= 8'd0;
        freq_decile_lcd       <= 8'd0;
        freq_percentiles_lcd  <= 8'd0;
        freq_valid_lcd        <= 1'b0;
        u_pp_hundreds_lcd     <= 8'd0;
        u_pp_tens_lcd         <= 8'd0;
        u_pp_units_lcd        <= 8'd0;
        u_pp_decile_lcd       <= 8'd0;
        u_pp_percentiles_lcd  <= 8'd0;
        u_pp_digits_valid_lcd <= 1'b0;
        i_pp_hundreds_lcd     <= 8'd0;
        i_pp_tens_lcd         <= 8'd0;
        i_pp_units_lcd        <= 8'd0;
        i_pp_decile_lcd       <= 8'd0;
        i_pp_percentiles_lcd  <= 8'd0;
        i_pp_digits_valid_lcd <= 1'b0;
        active_p_neg_lcd      <= 1'b0;
        active_p_hundreds_lcd <= 8'd0;
        active_p_tens_lcd     <= 8'd0;
        active_p_units_lcd    <= 8'd0;
        active_p_decile_lcd   <= 8'd0;
        active_p_percentiles_lcd <= 8'd0;
        reactive_q_neg_lcd    <= 1'b0;
        reactive_q_hundreds_lcd <= 8'd0;
        reactive_q_tens_lcd   <= 8'd0;
        reactive_q_units_lcd  <= 8'd0;
        reactive_q_decile_lcd <= 8'd0;
        reactive_q_percentiles_lcd <= 8'd0;
        apparent_s_hundreds_lcd <= 8'd0;
        apparent_s_tens_lcd   <= 8'd0;
        apparent_s_units_lcd  <= 8'd0;
        apparent_s_decile_lcd <= 8'd0;
        apparent_s_percentiles_lcd <= 8'd0;
        power_factor_neg_lcd  <= 1'b0;
        power_factor_units_lcd <= 8'd0;
        power_factor_decile_lcd <= 8'd0;
        power_factor_percentiles_lcd <= 8'd0;
        power_metrics_valid_lcd <= 1'b0;
        sharp_alarm_code_lcd   <= 3'd0;
        freq_thd_u_hundreds_lcd <= 8'd0;
        freq_thd_u_tens_lcd     <= 8'd0;
        freq_thd_u_units_lcd    <= 8'd0;
        freq_thd_u_decile_lcd   <= 8'd0;
        freq_thd_u_percentiles_lcd <= 8'd0;
        freq_thd_u_valid_lcd    <= 1'b0;
        freq_thd_i_hundreds_lcd <= 8'd0;
        freq_thd_i_tens_lcd     <= 8'd0;
        freq_thd_i_units_lcd    <= 8'd0;
        freq_thd_i_decile_lcd   <= 8'd0;
        freq_thd_i_percentiles_lcd <= 8'd0;
        freq_thd_i_valid_lcd    <= 1'b0;
        freq_u1_mag_hundreds_lcd <= 8'd0;
        freq_u1_mag_tens_lcd    <= 8'd0;
        freq_u1_mag_units_lcd   <= 8'd0;
        freq_u1_mag_decile_lcd  <= 8'd0;
        freq_u1_mag_percentiles_lcd <= 8'd0;
        freq_u1_mag_valid_lcd   <= 1'b0;
        freq_i1_mag_hundreds_lcd <= 8'd0;
        freq_i1_mag_tens_lcd    <= 8'd0;
        freq_i1_mag_units_lcd   <= 8'd0;
        freq_i1_mag_decile_lcd  <= 8'd0;
        freq_i1_mag_percentiles_lcd <= 8'd0;
        freq_i1_mag_valid_lcd   <= 1'b0;
        freq_phase1_neg_lcd     <= 1'b0;
        freq_phase1_hundreds_lcd <= 8'd0;
        freq_phase1_tens_lcd    <= 8'd0;
        freq_phase1_units_lcd   <= 8'd0;
        freq_phase1_decile_lcd  <= 8'd0;
        freq_phase1_percentiles_lcd <= 8'd0;
        freq_phase1_valid_lcd   <= 1'b0;
        freq_dc_u_hundreds_lcd  <= 8'd0;
        freq_dc_u_tens_lcd      <= 8'd0;
        freq_dc_u_units_lcd     <= 8'd0;
        freq_dc_u_decile_lcd    <= 8'd0;
        freq_dc_u_percentiles_lcd <= 8'd0;
        freq_dc_u_valid_lcd     <= 1'b0;
        freq_dc_i_hundreds_lcd  <= 8'd0;
        freq_dc_i_tens_lcd      <= 8'd0;
        freq_dc_i_units_lcd     <= 8'd0;
        freq_dc_i_decile_lcd    <= 8'd0;
        freq_dc_i_percentiles_lcd <= 8'd0;
        freq_dc_i_valid_lcd     <= 1'b0;
        freq_dh_order_u_text_lcd <= {25{8'h20}};
        freq_dh_order_i_text_lcd <= {25{8'h20}};
        graph_en_d1           <= 1'b0;
        graph_col_d1          <= 9'd0;
        graph_row_d1          <= 11'd0;
        freq_mag_u_pixel_on_d1 <= 1'b0;
        freq_mag_i_pixel_on_d1 <= 1'b0;
        freq_phase_pixel_on_d1 <= 1'b0;
        freq_phase_negative_d1 <= 1'b0;
        freq_display_bank_sync1 <= 1'b0;
        freq_display_bank_sync2 <= 1'b0;
        freq_frame_valid_sync1  <= 1'b0;
        freq_frame_valid_sync2  <= 1'b0;
        freq_front_bank_lcd     <= 1'b0;
        freq_front_valid_lcd    <= 1'b0;
        u_wave_prev_valid_d1  <= 1'b0;
        u_wave_prev_y_d1      <= 8'd0;
        u_wave_prev_col_d1    <= 9'd0;
        u_wave_prev_row_d1    <= 11'd0;
        i_wave_prev_valid_d1  <= 1'b0;
        i_wave_prev_y_d1      <= 8'd0;
        i_wave_prev_col_d1    <= 9'd0;
        i_wave_prev_row_d1    <= 11'd0;
        u_wave_display_bank_sync1 <= 1'b0;
        u_wave_display_bank_sync2 <= 1'b0;
        u_wave_frame_valid_sync1  <= 1'b0;
        u_wave_frame_valid_sync2  <= 1'b0;
        u_wave_front_bank_lcd     <= 1'b0;
        u_wave_front_valid_lcd    <= 1'b0;
        i_wave_display_bank_sync1 <= 1'b0;
        i_wave_display_bank_sync2 <= 1'b0;
        i_wave_frame_valid_sync1  <= 1'b0;
        i_wave_frame_valid_sync2  <= 1'b0;
        i_wave_front_bank_lcd     <= 1'b0;
        i_wave_front_valid_lcd    <= 1'b0;
        freeze_active_lcd         <= 1'b0;
        frequency_page_active_lcd <= 1'b0;
        harmonic_window_index_lcd <= 5'd0;
        touch_pressed_sync1       <= 1'b0;
        touch_pressed_sync2       <= 1'b0;
        touch_pressed_sync3       <= 1'b0;
        full_scale_low_range_sync1_lcd <= 1'b0;
        full_scale_low_range_active_lcd <= 1'b0;
        lcd_frame_done_toggle_d1  <= 1'b0;
        pixel_data            <= BG_COLOR;
    end else begin
        touch_pressed_sync1       <= touch_state_bits[TOUCH_PRESSED_BIT];
        touch_pressed_sync2       <= touch_pressed_sync1;
        touch_pressed_sync3       <= touch_pressed_sync2;
        full_scale_low_range_sync1_lcd <= full_scale_low_range_active;
        full_scale_low_range_active_lcd <= full_scale_low_range_sync1_lcd;
        if (freeze_button_click_qualified)
            freeze_active_lcd <= freeze_active_next_lcd;
        if (mode_button_click_qualified)
            frequency_page_active_lcd <= ~frequency_page_active_lcd;
        if (harmonic_home_qualified)
            harmonic_window_index_lcd <= 5'd0;
        else if (harmonic_prev_click_qualified && (harmonic_window_index_lcd != 5'd0))
            harmonic_window_index_lcd <= harmonic_window_index_lcd - 5'd1;
        else if (harmonic_next_click_qualified && (harmonic_window_index_lcd < HARMONIC_MAX_WINDOW_INDEX))
            harmonic_window_index_lcd <= harmonic_window_index_lcd + 5'd1;

        u_wave_display_bank_sync1 <= u_wave_display_bank;
        u_wave_display_bank_sync2 <= u_wave_display_bank_sync1;
        u_wave_frame_valid_sync1  <= u_wave_frame_valid;
        u_wave_frame_valid_sync2  <= u_wave_frame_valid_sync1;
        i_wave_display_bank_sync1 <= i_wave_display_bank;
        i_wave_display_bank_sync2 <= i_wave_display_bank_sync1;
        i_wave_frame_valid_sync1  <= i_wave_frame_valid;
        i_wave_frame_valid_sync2  <= i_wave_frame_valid_sync1;
        freq_display_bank_sync1   <= freq_display_bank;
        freq_display_bank_sync2   <= freq_display_bank_sync1;
        freq_frame_valid_sync1    <= freq_frame_valid;
        freq_frame_valid_sync2    <= freq_frame_valid_sync1;
        lcd_frame_done_toggle_d1   <= lcd_frame_done_toggle;

        // 在帧边界且允许刷新时切换到最新时域前台 bank；首次无有效帧时直接接管。
        if ((screen_update_enable_lcd && frame_edge_lcd) || !u_wave_front_valid_lcd) begin
            u_wave_front_bank_lcd  <= u_wave_display_bank_sync2;
            u_wave_front_valid_lcd <= u_wave_frame_valid_sync2;
        end

        if ((screen_update_enable_lcd && frame_edge_lcd) || !i_wave_front_valid_lcd) begin
            i_wave_front_bank_lcd  <= i_wave_display_bank_sync2;
            i_wave_front_valid_lcd <= i_wave_frame_valid_sync2;
        end

        // 频域页面使用独立 front bank，同样只在允许刷新时接收新帧。
        if ((screen_update_enable_lcd && frame_edge_lcd) || !freq_front_valid_lcd) begin
            freq_front_bank_lcd  <= freq_display_bank_sync2;
            freq_front_valid_lcd <= freq_frame_valid_sync2;
        end

        base_color_d1      <= base_color;
        text_color_d1      <= text_color;
        text_en_d1         <= text_en;
        text_font_small_d1 <= text_font_small;
        text_char_idx_d1   <= text_char_idx;
        text_rel_x_d1      <= text_rel_x;
        text_blank_d1      <= text_blank;
        // 未冻结时锁存最新文本包；冻结后保持屏幕文字稳定。
        if (screen_update_enable_lcd) begin
            {
                u_rms_hundreds_lcd, u_rms_tens_lcd, u_rms_units_lcd, u_rms_decile_lcd, u_rms_percentiles_lcd, u_rms_digits_valid_lcd,
                i_rms_hundreds_lcd, i_rms_tens_lcd, i_rms_units_lcd, i_rms_decile_lcd, i_rms_percentiles_lcd, i_rms_digits_valid_lcd,
                phase_neg_lcd, phase_hundreds_lcd, phase_tens_lcd, phase_units_lcd, phase_decile_lcd, phase_percentiles_lcd, phase_valid_lcd,
                freq_hundreds_lcd, freq_tens_lcd, freq_units_lcd, freq_decile_lcd, freq_percentiles_lcd, freq_valid_lcd,
                u_pp_hundreds_lcd, u_pp_tens_lcd, u_pp_units_lcd, u_pp_decile_lcd, u_pp_percentiles_lcd, u_pp_digits_valid_lcd,
                i_pp_hundreds_lcd, i_pp_tens_lcd, i_pp_units_lcd, i_pp_decile_lcd, i_pp_percentiles_lcd, i_pp_digits_valid_lcd,
                active_p_neg_lcd, active_p_hundreds_lcd, active_p_tens_lcd, active_p_units_lcd, active_p_decile_lcd, active_p_percentiles_lcd,
                reactive_q_neg_lcd, reactive_q_hundreds_lcd, reactive_q_tens_lcd, reactive_q_units_lcd, reactive_q_decile_lcd, reactive_q_percentiles_lcd,
                apparent_s_hundreds_lcd, apparent_s_tens_lcd, apparent_s_units_lcd, apparent_s_decile_lcd, apparent_s_percentiles_lcd,
                power_factor_neg_lcd, power_factor_units_lcd, power_factor_decile_lcd, power_factor_percentiles_lcd,
                power_metrics_valid_lcd,
                sharp_alarm_code_lcd,
                freq_thd_u_hundreds_lcd, freq_thd_u_tens_lcd, freq_thd_u_units_lcd, freq_thd_u_decile_lcd, freq_thd_u_percentiles_lcd, freq_thd_u_valid_lcd,
                freq_thd_i_hundreds_lcd, freq_thd_i_tens_lcd, freq_thd_i_units_lcd, freq_thd_i_decile_lcd, freq_thd_i_percentiles_lcd, freq_thd_i_valid_lcd,
                freq_u1_mag_hundreds_lcd, freq_u1_mag_tens_lcd, freq_u1_mag_units_lcd, freq_u1_mag_decile_lcd, freq_u1_mag_percentiles_lcd, freq_u1_mag_valid_lcd,
                freq_i1_mag_hundreds_lcd, freq_i1_mag_tens_lcd, freq_i1_mag_units_lcd, freq_i1_mag_decile_lcd, freq_i1_mag_percentiles_lcd, freq_i1_mag_valid_lcd,
                freq_phase1_neg_lcd, freq_phase1_hundreds_lcd, freq_phase1_tens_lcd, freq_phase1_units_lcd, freq_phase1_decile_lcd, freq_phase1_percentiles_lcd, freq_phase1_valid_lcd,
                freq_dc_u_hundreds_lcd, freq_dc_u_tens_lcd, freq_dc_u_units_lcd, freq_dc_u_decile_lcd, freq_dc_u_percentiles_lcd, freq_dc_u_valid_lcd,
                freq_dc_i_hundreds_lcd, freq_dc_i_tens_lcd, freq_dc_i_units_lcd, freq_dc_i_decile_lcd, freq_dc_i_percentiles_lcd, freq_dc_i_valid_lcd,
                freq_dh_order_u_text_lcd,
                freq_dh_order_i_text_lcd
            } <= text_packet_front_lcd;
        end

        graph_en_d1  <= time_graph_en;
        graph_col_d1 <= graph_col;
        graph_row_d1 <= pixel_ypos;
        freq_mag_u_pixel_on_d1 <= freq_mag_u_pixel_on;
        freq_mag_i_pixel_on_d1 <= freq_mag_i_pixel_on;
        freq_phase_pixel_on_d1 <= freq_phase_pixel_on;
        freq_phase_negative_d1 <= freq_phase_negative;

        if (graph_en_d1 && u_wave_front_valid_lcd) begin
            u_wave_prev_valid_d1 <= 1'b1;
            u_wave_prev_y_d1     <= u_wave_ram_doutb;
            u_wave_prev_col_d1   <= graph_col_d1;
            u_wave_prev_row_d1   <= graph_row_d1;
        end else begin
            u_wave_prev_valid_d1 <= 1'b0;
        end

        if (graph_en_d1 && i_wave_front_valid_lcd) begin
            i_wave_prev_valid_d1 <= 1'b1;
            i_wave_prev_y_d1     <= i_wave_ram_doutb;
            i_wave_prev_col_d1   <= graph_col_d1;
            i_wave_prev_row_d1   <= graph_row_d1;
        end else begin
            i_wave_prev_valid_d1 <= 1'b0;
        end

        // 按文字、频域相位、频域柱图、时域波形、背景的优先级输出像素颜色。
        if (text_pixel_on)
            pixel_data <= text_color_d1;
        else if (freq_phase_pixel_on_d1)
            pixel_data <= freq_phase_negative_d1 ? PHASE_NEG_COLOR : ACCENT_COLOR;
        else if (freq_mag_i_pixel_on_d1)
            pixel_data <= WAVE_I_COLOR;
        else if (freq_mag_u_pixel_on_d1)
            pixel_data <= WAVE_U_COLOR;
        else if (!frequency_page_active_lcd && i_wave_pixel_on)
            pixel_data <= WAVE_I_COLOR;
        else if (!frequency_page_active_lcd && u_wave_pixel_on)
            pixel_data <= WAVE_U_COLOR;
        else
            pixel_data <= base_color_d1;
    end
end


endmodule
