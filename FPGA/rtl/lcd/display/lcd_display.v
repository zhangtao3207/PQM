/*
 * 模块: lcd_display
 * 功能:
 *   LCD 页面顶层合成器。该模块将仅显示逻辑保留在 LCD 树中，同时重用 DataProcessor 中的通用波形捕获模块
 *   用于电压/电流波形帧和 RMS 值。
 *
 * 详细说明:
 *   这是当前 LCD 页面的总合成模块。它调用 DataProcessor 中的通用波形处理模块获取 U/I 两路波形帧、RMS、峰峰值、
 *   频率和相位差，然后在 `lcd_pclk` 时钟域中将背景层、文字层、字符 ROM 和波形 RAM 合成成最终像素颜色。
 *
 * 模块边界:
 *   - 波形分析与数值计算在 DataProcessor 完成
 *   - 本模块只负责显示数据锁存、RAM 读取和像素优先级合成
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
    output reg [23:0]  pixel_data
);

// 页面渲染使用到的基本常量
localparam [5:0]  BIG_CHAR_W    = 6'd16;
localparam [5:0]  SMALL_CHAR_W  = 6'd10;
localparam [6:0]  FONT_BLANK    = 7'd127;
localparam [23:0] BG_COLOR      = 24'h0B1524;
localparam [23:0] TEXT_WHITE    = 24'hF2F6FA;
localparam [23:0] WAVE_U_COLOR  = 24'h39E46F;
localparam [23:0] WAVE_I_COLOR  = 24'hFFD84E;
localparam integer TEXT_REFRESH_CYCLES = 1_250_000;  // 25ms @ 50MHz wave_clk
localparam [10:0] GRAPH_X       = 11'd36;
localparam [10:0] GRAPH_Y       = 11'd144;
localparam [10:0] GRAPH_W       = 11'd384;
localparam [10:0] GRAPH_H       = 11'd240;
localparam [10:0] FREEZE_BTN_X  = 11'd672;
localparam [10:0] FREEZE_BTN_Y  = 11'd6;
localparam [10:0] FREEZE_BTN_W  = 11'd110;
localparam [10:0] FREEZE_BTN_H  = 11'd32;
localparam integer TOUCH_PRESSED_BIT   = 4;
localparam [15:0] FREEZE_MIN_PRESS_MS  = 16'd30;
localparam [15:0] FREEZE_MAX_PRESS_MS  = 16'd500;
localparam integer TEXT_PACKET_WIDTH   = 339;

// LCD 像素时钟域中的一级流水线寄存器，用于对齐背景、文字和波形像素
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
reg  [7:0]  u_pp_tens_lcd;
reg  [7:0]  u_pp_units_lcd;
reg  [7:0]  u_pp_decile_lcd;
reg  [7:0]  u_pp_percentiles_lcd;
reg         u_pp_digits_valid_lcd;
reg  [7:0]  i_pp_tens_lcd;
reg  [7:0]  i_pp_units_lcd;
reg  [7:0]  i_pp_decile_lcd;
reg  [7:0]  i_pp_percentiles_lcd;
reg         i_pp_digits_valid_lcd;
reg         active_p_neg_lcd;
reg  [7:0]  active_p_tens_lcd;
reg  [7:0]  active_p_units_lcd;
reg  [7:0]  active_p_decile_lcd;
reg  [7:0]  active_p_percentiles_lcd;
reg         reactive_q_neg_lcd;
reg  [7:0]  reactive_q_tens_lcd;
reg  [7:0]  reactive_q_units_lcd;
reg  [7:0]  reactive_q_decile_lcd;
reg  [7:0]  reactive_q_percentiles_lcd;
reg  [7:0]  apparent_s_tens_lcd;
reg  [7:0]  apparent_s_units_lcd;
reg  [7:0]  apparent_s_decile_lcd;
reg  [7:0]  apparent_s_percentiles_lcd;
reg         power_factor_neg_lcd;
reg  [7:0]  power_factor_units_lcd;
reg  [7:0]  power_factor_decile_lcd;
reg  [7:0]  power_factor_percentiles_lcd;
reg         power_metrics_valid_lcd;
reg         graph_en_d1;
reg  [8:0]  graph_col_d1;
reg  [10:0] graph_row_d1;
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
reg         i_wave_display_bank_sync1;
reg         i_wave_display_bank_sync2;
reg         i_wave_frame_valid_sync1;
reg         i_wave_frame_valid_sync2;
reg         freeze_active_lcd;
reg         touch_pressed_sync1;
reg         touch_pressed_sync2;
reg         touch_pressed_sync3;
reg         lcd_frame_done_toggle_d1;
reg         freeze_active_wave_sync1;
reg         freeze_active_wave_sync2;

// 子模块输出与波形双口 RAM 接口信号
wire [23:0] base_color;
wire [23:0] text_color;
wire        text_en;
wire        text_font_small;
wire [6:0]  text_char_idx;
wire [5:0]  text_rel_x;
wire [5:0]  text_rel_y;
wire        text_blank;
wire        text_pixel_on;

wire [7:0]  u_rms_tens;
wire [7:0]  u_rms_units;
wire [7:0]  u_rms_decile;
wire [7:0]  u_rms_percentiles;
wire        u_rms_digits_valid;
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

wire [7:0]  i_rms_tens;
wire [7:0]  i_rms_units;
wire [7:0]  i_rms_decile;
wire [7:0]  i_rms_percentiles;
wire        i_rms_digits_valid;
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
wire [7:0]  active_p_tens;
wire [7:0]  active_p_units;
wire [7:0]  active_p_decile;
wire [7:0]  active_p_percentiles;
wire        reactive_q_neg;
wire [7:0]  reactive_q_tens;
wire [7:0]  reactive_q_units;
wire [7:0]  reactive_q_decile;
wire [7:0]  reactive_q_percentiles;
wire [7:0]  apparent_s_tens;
wire [7:0]  apparent_s_units;
wire [7:0]  apparent_s_decile;
wire [7:0]  apparent_s_percentiles;
wire        power_factor_neg;
wire [7:0]  power_factor_units;
wire [7:0]  power_factor_decile;
wire [7:0]  power_factor_percentiles;
wire        power_metrics_valid;
wire        u_trigger_pulse;
wire [8:0]  u_trigger_snapshot_ptr;

wire        graph_en;
wire [10:0] graph_col_ext;
wire [8:0]  graph_col;
wire        touch_pressed_lcd;
wire        touch_pressed_fall_lcd;
wire        freeze_button_touch_hit;
wire        freeze_button_start_hit;
wire        freeze_button_pressed;
wire        freeze_button_click_qualified;
wire        freeze_active_wave;
wire        u_wave_sample_valid_gated;
wire        i_wave_sample_valid_gated;
wire        frame_edge_lcd;
wire [TEXT_PACKET_WIDTH-1:0] text_packet_wave;
wire [TEXT_PACKET_WIDTH-1:0] text_packet_front_lcd;

wire [6:0]  font_char_idx;
wire        text_result_commit_toggle;
wire        text_commit_pending_lcd;
wire        text_swap_ack_toggle_lcd;

wire [11:0] font_addr_16x32;
wire [10:0] font_addr_10x20;
wire [15:0] font_row_16x32_rom;
wire [11:0] font_row_10x20_rom;

assign font_addr_16x32 = text_blank ? 12'd0 : ({5'd0, font_char_idx} << 5) + {6'd0, text_rel_y[4:0]};
assign font_addr_10x20 = text_blank ? 11'd0 : (({4'd0, font_char_idx} << 4) + ({6'd0, font_char_idx} << 2) + {5'd0, text_rel_y[4:0]});
assign text_packet_wave = {
    u_rms_tens, u_rms_units, u_rms_decile, u_rms_percentiles, u_rms_digits_valid,
    i_rms_tens, i_rms_units, i_rms_decile, i_rms_percentiles, i_rms_digits_valid,
    phase_neg, phase_hundreds, phase_tens, phase_units, phase_decile, phase_percentiles, phase_valid,
    freq_hundreds, freq_tens, freq_units, freq_decile, freq_percentiles, freq_valid,
    u_pp_tens, u_pp_units, u_pp_decile, u_pp_percentiles, u_pp_digits_valid,
    i_pp_tens, i_pp_units, i_pp_decile, i_pp_percentiles, i_pp_digits_valid,
    active_p_neg, active_p_tens, active_p_units, active_p_decile, active_p_percentiles,
    reactive_q_neg, reactive_q_tens, reactive_q_units, reactive_q_decile, reactive_q_percentiles,
    apparent_s_tens, apparent_s_units, apparent_s_decile, apparent_s_percentiles,
    power_factor_neg, power_factor_units, power_factor_decile, power_factor_percentiles,
    power_metrics_valid
};

blk_mem_gen_font_16x32 u_font_16x32_rom(
    .clka  (lcd_pclk),
    .addra (font_addr_16x32),
    .douta (font_row_16x32_rom)
);

blk_mem_gen_font_10x20 u_font_10x20_rom(
    .clka  (lcd_pclk),
    .ena   (1'b1),
    .addra (font_addr_10x20),
    .douta (font_row_10x20_rom)
);
// 电压通道：生成电压波形帧、U_rms 和 Upp
wave_display_capture #(
    .VERT_SCALE_NUM     (5),
    .VERT_SCALE_DEN     (6)
) u_u_wave_display_capture (
    .wave_clk          (wave_clk),
    .sys_rst_n         (sys_rst_n),
    .wave_sample_valid (u_wave_sample_valid_gated),
    .wave_sample_code  (u_wave_sample_code),
    .wave_zero_code    (u_wave_zero_code),
    .wave_zero_valid   (u_wave_zero_valid),
    .trigger_force     (1'b0),
    .trigger_force_snapshot_ptr(9'd0),
    .trigger_use_external(1'b0),
    .wave_frame_valid  (u_wave_frame_valid),
    .wave_display_bank (u_wave_display_bank),
    .wave_ram_we       (u_wave_ram_we),
    .wave_ram_waddr    (u_wave_ram_waddr),
    .wave_ram_wdata    (u_wave_ram_wdata),
    .trigger_pulse     (u_trigger_pulse),
    .trigger_snapshot_ptr(u_trigger_snapshot_ptr)
);

// 电流通道：共享电压触发时刻，生成 I_rms 和 Ipp
wave_display_capture #(
    .VERT_SCALE_NUM     (1),
    .VERT_SCALE_DEN     (1)
) u_i_wave_display_capture (
    .wave_clk          (wave_clk),
    .sys_rst_n         (sys_rst_n),
    .wave_sample_valid (i_wave_sample_valid_gated),
    .wave_sample_code  (i_wave_sample_code),
    .wave_zero_code    (i_wave_zero_code),
    .wave_zero_valid   (i_wave_zero_valid),
    .trigger_force     (u_trigger_pulse),
    .trigger_force_snapshot_ptr(u_trigger_snapshot_ptr),
    .trigger_use_external(1'b1),
    .wave_frame_valid  (i_wave_frame_valid),
    .wave_display_bank (i_wave_display_bank),
    .wave_ram_we       (i_wave_ram_we),
    .wave_ram_waddr    (i_wave_ram_waddr),
    .wave_ram_wdata    (i_wave_ram_wdata),
    .trigger_pulse     (),
    .trigger_snapshot_ptr()
);

text_display_preprocess #(
    .SAMPLE_WIDTH      (16),
    .U_FULL_SCALE_X100 (1000),
    .I_FULL_SCALE_X100 (30),
    .START_DELAY_CYCLES(TEXT_REFRESH_CYCLES)
) u_text_display_preprocess (
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
    .text_result_commit_toggle(text_result_commit_toggle),
    .u_rms_tens        (u_rms_tens),
    .u_rms_units       (u_rms_units),
    .u_rms_decile      (u_rms_decile),
    .u_rms_percentiles (u_rms_percentiles),
    .u_rms_digits_valid(u_rms_digits_valid),
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
    .u_pp_tens         (u_pp_tens),
    .u_pp_units        (u_pp_units),
    .u_pp_decile       (u_pp_decile),
    .u_pp_percentiles  (u_pp_percentiles),
    .u_pp_digits_valid (u_pp_digits_valid),
    .i_pp_tens         (i_pp_tens),
    .i_pp_units        (i_pp_units),
    .i_pp_decile       (i_pp_decile),
    .i_pp_percentiles  (i_pp_percentiles),
    .i_pp_digits_valid (i_pp_digits_valid),
    .active_p_neg      (active_p_neg),
    .active_p_tens     (active_p_tens),
    .active_p_units    (active_p_units),
    .active_p_decile   (active_p_decile),
    .active_p_percentiles(active_p_percentiles),
    .reactive_q_neg    (reactive_q_neg),
    .reactive_q_tens   (reactive_q_tens),
    .reactive_q_units  (reactive_q_units),
    .reactive_q_decile (reactive_q_decile),
    .reactive_q_percentiles(reactive_q_percentiles),
    .apparent_s_tens   (apparent_s_tens),
    .apparent_s_units  (apparent_s_units),
    .apparent_s_decile (apparent_s_decile),
    .apparent_s_percentiles(apparent_s_percentiles),
    .power_factor_neg  (power_factor_neg),
    .power_factor_units(power_factor_units),
    .power_factor_decile(power_factor_decile),
    .power_factor_percentiles(power_factor_percentiles),
    .power_metrics_valid(power_metrics_valid)
);

// 相位与频率分析：以电压为参考计算频率和电压相对电流的相位差
// 文字结果采用前后台双缓冲，跨域仅同步提交与切换控制位
text_packet_double_buffer #(
    .PACKET_WIDTH (TEXT_PACKET_WIDTH)
) u_text_packet_double_buffer (
    .wave_clk                  (wave_clk),
    .lcd_pclk                  (lcd_pclk),
    .rst_n                     (sys_rst_n),
    .packet_in_wave            (text_packet_wave),
    .packet_commit_toggle_wave (text_result_commit_toggle),
    .frame_edge_lcd            (frame_edge_lcd),
    .lcd_swap_ack_toggle       (text_swap_ack_toggle_lcd),
    .packet_pending_lcd        (text_commit_pending_lcd),
    .packet_front_lcd          (text_packet_front_lcd)
);

always @(posedge wave_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        freeze_active_wave_sync1 <= 1'b0;
        freeze_active_wave_sync2 <= 1'b0;
    end else begin
        freeze_active_wave_sync1 <= freeze_active_lcd;
        freeze_active_wave_sync2 <= freeze_active_wave_sync1;
    end
end

lcd_display_bg u_lcd_display_bg(
    .pixel_xpos            (pixel_xpos),
    .pixel_ypos            (pixel_ypos),
    .freeze_button_pressed (freeze_button_pressed),
    .base_color            (base_color)
);

lcd_display_text u_lcd_display_text(
    .pixel_xpos          (pixel_xpos),
    .pixel_ypos          (pixel_ypos),
    .u_rms_tens          (u_rms_tens_lcd),
    .u_rms_units         (u_rms_units_lcd),
    .u_rms_decile        (u_rms_decile_lcd),
    .u_rms_percentiles   (u_rms_percentiles_lcd),
    .u_rms_digits_valid  (u_rms_digits_valid_lcd),
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
    .u_pp_tens           (u_pp_tens_lcd),
    .u_pp_units          (u_pp_units_lcd),
    .u_pp_decile         (u_pp_decile_lcd),
    .u_pp_percentiles    (u_pp_percentiles_lcd),
    .u_pp_digits_valid   (u_pp_digits_valid_lcd),
    .i_pp_tens           (i_pp_tens_lcd),
    .i_pp_units          (i_pp_units_lcd),
    .i_pp_decile         (i_pp_decile_lcd),
    .i_pp_percentiles    (i_pp_percentiles_lcd),
    .i_pp_digits_valid   (i_pp_digits_valid_lcd),
    .active_p_neg        (active_p_neg_lcd),
    .active_p_tens       (active_p_tens_lcd),
    .active_p_units      (active_p_units_lcd),
    .active_p_decile     (active_p_decile_lcd),
    .active_p_percentiles(active_p_percentiles_lcd),
    .reactive_q_neg      (reactive_q_neg_lcd),
    .reactive_q_tens     (reactive_q_tens_lcd),
    .reactive_q_units    (reactive_q_units_lcd),
    .reactive_q_decile   (reactive_q_decile_lcd),
    .reactive_q_percentiles(reactive_q_percentiles_lcd),
    .apparent_s_tens     (apparent_s_tens_lcd),
    .apparent_s_units    (apparent_s_units_lcd),
    .apparent_s_decile   (apparent_s_decile_lcd),
    .apparent_s_percentiles(apparent_s_percentiles_lcd),
    .power_factor_neg    (power_factor_neg_lcd),
    .power_factor_units  (power_factor_units_lcd),
    .power_factor_decile (power_factor_decile_lcd),
    .power_factor_percentiles(power_factor_percentiles_lcd),
    .power_metrics_valid (power_metrics_valid_lcd),
    .freeze_active       (freeze_active_lcd),
    .text_en             (text_en),
    .text_font_small     (text_font_small),
    .text_char_idx       (text_char_idx),
    .text_rel_x          (text_rel_x),
    .text_rel_y          (text_rel_y),
    .text_color          (text_color)
);

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

assign text_blank        = (text_char_idx == FONT_BLANK);
assign font_char_idx     = text_blank ? 7'd0 : text_char_idx;
assign frame_edge_lcd    = lcd_frame_done_toggle ^ lcd_frame_done_toggle_d1;
assign touch_pressed_lcd = touch_pressed_sync2;
assign touch_pressed_fall_lcd = touch_pressed_sync3 && !touch_pressed_sync2;
assign freeze_button_touch_hit =
    (touch_x >= FREEZE_BTN_X) && (touch_x < (FREEZE_BTN_X + FREEZE_BTN_W)) &&
    (touch_y >= FREEZE_BTN_Y) && (touch_y < (FREEZE_BTN_Y + FREEZE_BTN_H));
assign freeze_button_start_hit =
    (touch_start_x >= FREEZE_BTN_X) && (touch_start_x < (FREEZE_BTN_X + FREEZE_BTN_W)) &&
    (touch_start_y >= FREEZE_BTN_Y) && (touch_start_y < (FREEZE_BTN_Y + FREEZE_BTN_H));
assign freeze_button_pressed = touch_pressed_lcd && freeze_button_touch_hit;
assign freeze_button_click_qualified =
    touch_pressed_fall_lcd &&
    freeze_button_start_hit &&
    (touch_press_time_ms >= FREEZE_MIN_PRESS_MS) &&
    (touch_press_time_ms <= FREEZE_MAX_PRESS_MS);
assign freeze_active_wave = freeze_active_wave_sync2;
assign u_wave_sample_valid_gated = u_wave_sample_valid && !freeze_active_wave;
assign i_wave_sample_valid_gated = i_wave_sample_valid && !freeze_active_wave;

assign graph_en      = (pixel_xpos >= GRAPH_X) && (pixel_xpos < (GRAPH_X + GRAPH_W)) &&
                       (pixel_ypos > GRAPH_Y) && (pixel_ypos < (GRAPH_Y + GRAPH_H - 1));
assign graph_col_ext = pixel_xpos - GRAPH_X;
assign graph_col     = graph_col_ext[8:0];
assign u_wave_ram_raddr = graph_en ? {u_wave_display_bank_sync2, graph_col} :
                                     {u_wave_display_bank_sync2, 9'd0};
assign i_wave_ram_raddr = graph_en ? {i_wave_display_bank_sync2, graph_col} :
                                     {i_wave_display_bank_sync2, 9'd0};

// ========== 波形像素检测（参数化）==========
// 电压通道 (U)
wave_pixel_detector #(
    .GRAPH_Y(GRAPH_Y)
) u_wave_pixel_detector_u (
    .graph_en_d1          (graph_en_d1),
    .wave_frame_valid_sync(u_wave_frame_valid_sync2),
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

// 电流通道 (I)
wave_pixel_detector #(
    .GRAPH_Y(GRAPH_Y)
) u_wave_pixel_detector_i (
    .graph_en_d1          (graph_en_d1),
    .wave_frame_valid_sync(i_wave_frame_valid_sync2),
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

assign text_pixel_on =
    text_en_d1 && !text_blank_d1 &&
    (text_font_small_d1 ?
        ((text_rel_x_d1 < SMALL_CHAR_W) ? font_row_10x20_rom[9 - text_rel_x_d1[3:0]] : 1'b0) :
        ((text_rel_x_d1 < BIG_CHAR_W)   ? font_row_16x32_rom[15 - text_rel_x_d1[3:0]] : 1'b0));

// U and I waveform pixel signals now come from wave_pixel_detector modules
assign u_wave_pixel_on = u_wave_pixel_on_internal;
assign i_wave_pixel_on = i_wave_pixel_on_internal;

always @(posedge lcd_pclk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        base_color_d1         <= BG_COLOR;
        text_color_d1         <= TEXT_WHITE;
        text_en_d1            <= 1'b0;
        text_font_small_d1    <= 1'b0;
        text_rel_x_d1         <= 6'd0;
        text_blank_d1         <= 1'b1;
        u_rms_tens_lcd        <= 8'd0;
        u_rms_units_lcd       <= 8'd0;
        u_rms_decile_lcd      <= 8'd0;
        u_rms_percentiles_lcd <= 8'd0;
        u_rms_digits_valid_lcd <= 1'b0;
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
        u_pp_tens_lcd         <= 8'd0;
        u_pp_units_lcd        <= 8'd0;
        u_pp_decile_lcd       <= 8'd0;
        u_pp_percentiles_lcd  <= 8'd0;
        u_pp_digits_valid_lcd <= 1'b0;
        i_pp_tens_lcd         <= 8'd0;
        i_pp_units_lcd        <= 8'd0;
        i_pp_decile_lcd       <= 8'd0;
        i_pp_percentiles_lcd  <= 8'd0;
        i_pp_digits_valid_lcd <= 1'b0;
        active_p_neg_lcd      <= 1'b0;
        active_p_tens_lcd     <= 8'd0;
        active_p_units_lcd    <= 8'd0;
        active_p_decile_lcd   <= 8'd0;
        active_p_percentiles_lcd <= 8'd0;
        reactive_q_neg_lcd    <= 1'b0;
        reactive_q_tens_lcd   <= 8'd0;
        reactive_q_units_lcd  <= 8'd0;
        reactive_q_decile_lcd <= 8'd0;
        reactive_q_percentiles_lcd <= 8'd0;
        apparent_s_tens_lcd   <= 8'd0;
        apparent_s_units_lcd  <= 8'd0;
        apparent_s_decile_lcd <= 8'd0;
        apparent_s_percentiles_lcd <= 8'd0;
        power_factor_neg_lcd  <= 1'b0;
        power_factor_units_lcd <= 8'd0;
        power_factor_decile_lcd <= 8'd0;
        power_factor_percentiles_lcd <= 8'd0;
        power_metrics_valid_lcd <= 1'b0;
        graph_en_d1           <= 1'b0;
        graph_col_d1          <= 9'd0;
        graph_row_d1          <= 11'd0;
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
        i_wave_display_bank_sync1 <= 1'b0;
        i_wave_display_bank_sync2 <= 1'b0;
        i_wave_frame_valid_sync1  <= 1'b0;
        i_wave_frame_valid_sync2  <= 1'b0;
        freeze_active_lcd         <= 1'b0;
        touch_pressed_sync1       <= 1'b0;
        touch_pressed_sync2       <= 1'b0;
        touch_pressed_sync3       <= 1'b0;
        lcd_frame_done_toggle_d1  <= 1'b0;
        pixel_data            <= BG_COLOR;
    end else begin
        touch_pressed_sync1       <= touch_state_bits[TOUCH_PRESSED_BIT];
        touch_pressed_sync2       <= touch_pressed_sync1;
        touch_pressed_sync3       <= touch_pressed_sync2;
        if (freeze_button_click_qualified)
            freeze_active_lcd <= ~freeze_active_lcd;

        u_wave_display_bank_sync1 <= u_wave_display_bank;
        u_wave_display_bank_sync2 <= u_wave_display_bank_sync1;
        u_wave_frame_valid_sync1  <= u_wave_frame_valid;
        u_wave_frame_valid_sync2  <= u_wave_frame_valid_sync1;
        i_wave_display_bank_sync1 <= i_wave_display_bank;
        i_wave_display_bank_sync2 <= i_wave_display_bank_sync1;
        i_wave_frame_valid_sync1  <= i_wave_frame_valid;
        i_wave_frame_valid_sync2  <= i_wave_frame_valid_sync1;
        lcd_frame_done_toggle_d1   <= lcd_frame_done_toggle;

        base_color_d1      <= base_color;
        text_color_d1      <= text_color;
        text_en_d1         <= text_en;
        text_font_small_d1 <= text_font_small;
        text_rel_x_d1      <= text_rel_x;
        text_blank_d1      <= text_blank;
        {
            u_rms_tens_lcd, u_rms_units_lcd, u_rms_decile_lcd, u_rms_percentiles_lcd, u_rms_digits_valid_lcd,
            i_rms_tens_lcd, i_rms_units_lcd, i_rms_decile_lcd, i_rms_percentiles_lcd, i_rms_digits_valid_lcd,
            phase_neg_lcd, phase_hundreds_lcd, phase_tens_lcd, phase_units_lcd, phase_decile_lcd, phase_percentiles_lcd, phase_valid_lcd,
            freq_hundreds_lcd, freq_tens_lcd, freq_units_lcd, freq_decile_lcd, freq_percentiles_lcd, freq_valid_lcd,
            u_pp_tens_lcd, u_pp_units_lcd, u_pp_decile_lcd, u_pp_percentiles_lcd, u_pp_digits_valid_lcd,
            i_pp_tens_lcd, i_pp_units_lcd, i_pp_decile_lcd, i_pp_percentiles_lcd, i_pp_digits_valid_lcd,
            active_p_neg_lcd, active_p_tens_lcd, active_p_units_lcd, active_p_decile_lcd, active_p_percentiles_lcd,
            reactive_q_neg_lcd, reactive_q_tens_lcd, reactive_q_units_lcd, reactive_q_decile_lcd, reactive_q_percentiles_lcd,
            apparent_s_tens_lcd, apparent_s_units_lcd, apparent_s_decile_lcd, apparent_s_percentiles_lcd,
            power_factor_neg_lcd, power_factor_units_lcd, power_factor_decile_lcd, power_factor_percentiles_lcd,
            power_metrics_valid_lcd
        } <= text_packet_front_lcd;

        graph_en_d1  <= graph_en;
        graph_col_d1 <= graph_col;
        graph_row_d1 <= pixel_ypos;

        if (graph_en_d1 && u_wave_frame_valid_sync2) begin
            u_wave_prev_valid_d1 <= 1'b1;
            u_wave_prev_y_d1     <= u_wave_ram_doutb;
            u_wave_prev_col_d1   <= graph_col_d1;
            u_wave_prev_row_d1   <= graph_row_d1;
        end else begin
            u_wave_prev_valid_d1 <= 1'b0;
        end

        if (graph_en_d1 && i_wave_frame_valid_sync2) begin
            i_wave_prev_valid_d1 <= 1'b1;
            i_wave_prev_y_d1     <= i_wave_ram_doutb;
            i_wave_prev_col_d1   <= graph_col_d1;
            i_wave_prev_row_d1   <= graph_row_d1;
        end else begin
            i_wave_prev_valid_d1 <= 1'b0;
        end

        if (text_pixel_on)
            pixel_data <= text_color_d1;
        else if (i_wave_pixel_on)
            pixel_data <= WAVE_I_COLOR;
        else if (u_wave_pixel_on)
            pixel_data <= WAVE_U_COLOR;
        else
            pixel_data <= base_color_d1;
    end
end


endmodule
