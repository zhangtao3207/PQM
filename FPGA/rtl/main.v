//============================================================================
// Module Name: main
//============================================================================
module main(
    input            sys_clk,
    input            sys_rst_n,

    input            uart_rxd,
    output           uart_txd,
    inout            touch_sda,
    output           touch_scl,
    inout            touch_int,
    output           touch_rst_n,

    output           lcd_de,
    output           lcd_hs,
    output           lcd_vs,
    output           lcd_bl,
    output           lcd_clk,
    output           lcd_rst_n,
    inout   [23:0]   lcd_rgb,

    output           OS1,
    output           OS0,
    output           OS2,
    output           Convst,
    output           RD,
    output           RESET,
    input            Busy,
    output           cs,
    output           Range,
    input            Frstdata,
    input            DB0,
    input            DB1,
    input            DB2,
    input            DB3,
    input            DB4,
    input            DB5,
    input            DB6,
    input            DB7,
    input            DB8,
    input            DB9,
    input            DB10,
    input            DB11,
    input            DB12,
    input            DB13,
    input            DB14,
    input            DB15
);

//==========================================================================
// Parameters
//==========================================================================


localparam integer ADC_STARTUP_WAIT_CYCLES = 50000;

//==========================================================================
// Internal signals
//==========================================================================
wire  [15:0] lcd_id;
wire  [31:0] data;
wire         touch_pressed;
wire         touch_unpressed;
wire         touch_click;
wire         touch_long_press;
wire         touch_drag;
wire         touch_click_state;
wire         touch_long_state;
wire         touch_drag_state;
wire  [15:0] touch_start_x;
wire  [15:0] touch_start_y;
wire  [15:0] touch_end_x;
wire  [15:0] touch_end_y;
wire  [15:0] touch_press_time_ms;
wire  [4:0]  touch_state_bits;
wire  [7:0]  uart_rx_data;
wire         uart_rx_done;
wire         uart_tx_busy;
wire  [7:0]  uart_tx_data;
wire         uart_tx_en;
reg   [127:0] rx_line_ascii;
reg   [3:0]  rx_pos;

wire         clk_50m;
wire         clk_25m;
wire         clk_25m_deg120;
wire         locked;
wire         rst_n;
wire [15:0]  AD_DATA_1;
wire [15:0]  AD_DATA_2;
wire [15:0]  AD_DATA_3;
wire [15:0]  AD_DATA_4;
wire [15:0]  AD_DATA_5;
wire [15:0]  AD_DATA_6;
wire [15:0]  AD_DATA_7;
wire [15:0]  AD_DATA_8;
wire [3:0]   AD_CHANNAL;
wire [2:0]   AD_STATE;
wire         adc_sample_active;
wire         adc_frame_valid;
wire         adc_timeout;
wire [15:0]  adc_data_bus;
wire         adc_startup_wait_done;
wire         ad_reset_int;
wire         ad_convst_int;
wire         ad_cs_n_int;
wire         ad_rd_n_int;
wire         adc_u_wave_sample_valid;
wire         adc_i_wave_sample_valid;
wire [15:0]  adc_u_zero_code;
wire [15:0]  adc_i_zero_code;
wire         adc_u_zero_valid;
wire         adc_i_zero_valid;
reg          adc_start;
reg          adc_idle_seen;
reg  [15:0]  adc_startup_wait_cnt;
reg  [15:0]  adc_u_wave_sample_code;
reg  [15:0]  adc_i_wave_sample_code;

assign rst_n                  = sys_rst_n & locked;
assign adc_startup_wait_done  = (adc_startup_wait_cnt >= ADC_STARTUP_WAIT_CYCLES - 1);
assign adc_data_bus           = {DB15, DB14, DB13, DB12, DB11, DB10, DB9, DB8,
                                 DB7, DB6, DB5, DB4, DB3, DB2, DB1, DB0};
assign adc_u_wave_sample_valid = adc_frame_valid;
assign adc_i_wave_sample_valid = adc_frame_valid;
assign uart_tx_data           = 8'h00;
assign uart_tx_en             = 1'b0;

assign OS0      = 1'b0;
assign OS1      = 1'b0;
assign OS2      = 1'b0;
assign RESET    = ad_reset_int;
assign Convst   = ad_convst_int;
assign Range    = 1'b1;
assign cs       = ad_cs_n_int;
assign RD       = ad_rd_n_int;

//==========================================================================
// Function: sanitize_char
//==========================================================================
function [7:0] sanitize_char;
    input [7:0] c;
    begin
        if (c < 8'h20 || c > 8'h7E)
            sanitize_char = 8'h20;
        else
            sanitize_char = c;
    end
endfunction

//==========================================================================
// UART instance
//==========================================================================
uart u_uart (
    .clk      (sys_clk),
    .rst_n    (sys_rst_n),
    .uart_rxd (uart_rxd),
    .uart_txd (uart_txd),
    .tx_en    (uart_tx_en),
    .tx_data  (uart_tx_data),
    .tx_busy  (uart_tx_busy),
    .rx_data  (uart_rx_data),
    .rx_done  (uart_rx_done)
);

//==========================================================================
// Touch instance
//==========================================================================
touch_top u_touch_top (
    .clk               (sys_clk),
    .rst_n             (sys_rst_n),
    .touch_rst_n       (touch_rst_n),
    .touch_int         (touch_int),
    .touch_scl         (touch_scl),
    .touch_sda         (touch_sda),
    .lcd_id            (lcd_id),
    .data              (data),
    .touch_pressed     (touch_pressed),
    .touch_unpressed   (touch_unpressed),
    .touch_click       (touch_click),
    .touch_long_press  (touch_long_press),
    .touch_drag        (touch_drag),
    .touch_click_state (touch_click_state),
    .touch_long_state  (touch_long_state),
    .touch_drag_state  (touch_drag_state),
    .touch_start_x     (touch_start_x),
    .touch_start_y     (touch_start_y),
    .touch_end_x       (touch_end_x),
    .touch_end_y       (touch_end_y),
    .touch_press_time_ms(touch_press_time_ms)
);

assign touch_state_bits = {
    touch_pressed,
    touch_unpressed,
    touch_click_state,
    touch_long_state,
    touch_drag_state
};

//==========================================================================
// UART receive line buffer
//==========================================================================
always @(posedge sys_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        rx_line_ascii <= {16{8'h20}};
        rx_pos        <= 4'd0;
    end else if (uart_rx_done) begin
        if (uart_rx_data == 8'h0D || uart_rx_data == 8'h0A) begin
            rx_line_ascii <= {16{8'h20}};
            rx_pos        <= 4'd0;
        end else begin
            case (rx_pos)
                4'd0 : rx_line_ascii[127:120] <= sanitize_char(uart_rx_data);
                4'd1 : rx_line_ascii[119:112] <= sanitize_char(uart_rx_data);
                4'd2 : rx_line_ascii[111:104] <= sanitize_char(uart_rx_data);
                4'd3 : rx_line_ascii[103:96]  <= sanitize_char(uart_rx_data);
                4'd4 : rx_line_ascii[95:88]   <= sanitize_char(uart_rx_data);
                4'd5 : rx_line_ascii[87:80]   <= sanitize_char(uart_rx_data);
                4'd6 : rx_line_ascii[79:72]   <= sanitize_char(uart_rx_data);
                4'd7 : rx_line_ascii[71:64]   <= sanitize_char(uart_rx_data);
                4'd8 : rx_line_ascii[63:56]   <= sanitize_char(uart_rx_data);
                4'd9 : rx_line_ascii[55:48]   <= sanitize_char(uart_rx_data);
                4'd10: rx_line_ascii[47:40]   <= sanitize_char(uart_rx_data);
                4'd11: rx_line_ascii[39:32]   <= sanitize_char(uart_rx_data);
                4'd12: rx_line_ascii[31:24]   <= sanitize_char(uart_rx_data);
                4'd13: rx_line_ascii[23:16]   <= sanitize_char(uart_rx_data);
                4'd14: rx_line_ascii[15:8]    <= sanitize_char(uart_rx_data);
                default: rx_line_ascii[7:0]   <= sanitize_char(uart_rx_data);
            endcase

            if (rx_pos != 4'd15)
                rx_pos <= rx_pos + 4'd1;
        end
    end
end

//==========================================================================
// ADC start generator
//==========================================================================
always @(posedge sys_clk or negedge rst_n) begin
    if (!rst_n) begin
        adc_start            <= 1'b0;
        adc_idle_seen        <= 1'b0;
        adc_startup_wait_cnt <= 16'd0;
        adc_u_wave_sample_code <= 16'h8000;
        adc_i_wave_sample_code <= 16'h8000;
    end else begin
        adc_start <= 1'b0;

        if (!adc_startup_wait_done) begin
            adc_startup_wait_cnt <= adc_startup_wait_cnt + 16'd1;
            adc_idle_seen        <= 1'b0;
        end else if (!adc_sample_active && !adc_idle_seen) begin
            adc_start     <= 1'b1;
            adc_idle_seen <= 1'b1;
        end else if (adc_sample_active) begin
            adc_idle_seen <= 1'b0;
        end

        if (adc_frame_valid) begin
            adc_u_wave_sample_code <= AD_DATA_1 ^ 16'h8000;
            adc_i_wave_sample_code <= AD_DATA_3 ^ 16'h8000;
        end
    end
end

//==========================================================================
// ADC instance: AD7606 parallel mode
//==========================================================================
AD7606_Parallel_DRIVER  u_AD7606_Parallel_DRIVER (
    .clk          (sys_clk),
    .rst_n        (rst_n),
    .start        (adc_start),
    .soft_reset   (1'b0),
    .ad_busy      (Busy),
    .ad_frstdata  (Frstdata),
    .ad_data      (adc_data_bus),
    .ad_reset     (ad_reset_int),
    .ad_convst    (ad_convst_int),
    .ad_cs_n      (ad_cs_n_int),
    .ad_rd_n      (ad_rd_n_int),
    .ch1_data     (AD_DATA_1),
    .ch2_data     (AD_DATA_2),
    .ch3_data     (AD_DATA_3),
    .ch4_data     (AD_DATA_4),
    .ch5_data     (AD_DATA_5),
    .ch6_data     (AD_DATA_6),
    .ch7_data     (AD_DATA_7),
    .ch8_data     (AD_DATA_8),
    .data_frame   (),
    .data_valid   (adc_frame_valid),
    .sample_active(adc_sample_active),
    .timeout      (adc_timeout),
    .ad_channal   (AD_CHANNAL),
    .ad_state     (AD_STATE)
);

//==========================================================================
// ADC zero-code tracker
//==========================================================================
zero_code_tracker #(
    .WIDTH          (16),
    .EST_SHIFT      (8),
    .WARMUP_SAMPLES (512)
) u_adc_u_zero_code_tracker (
    .clk           (sys_clk),
    .rst_n         (rst_n),
    .sample_valid  (adc_u_wave_sample_valid),
    .sample_code   (adc_u_wave_sample_code),
    .zero_code     (adc_u_zero_code),
    .zero_valid    (adc_u_zero_valid)
);

zero_code_tracker #(
    .WIDTH          (16),
    .EST_SHIFT      (8),
    .WARMUP_SAMPLES (512)
) u_adc_i_zero_code_tracker (
    .clk           (sys_clk),
    .rst_n         (rst_n),
    .sample_valid  (adc_i_wave_sample_valid),
    .sample_code   (adc_i_wave_sample_code),
    .zero_code     (adc_i_zero_code),
    .zero_valid    (adc_i_zero_valid)
);

//==========================================================================
// LCD display
//==========================================================================
lcd_rgb_char u_lcd_rgb_char (
    .sys_clk            (sys_clk),
    .sys_rst_n          (sys_rst_n),
    .data               (data),
    .touch_state_bits   (touch_state_bits),
    .touch_start_x      (touch_start_x),
    .touch_start_y      (touch_start_y),
    .touch_press_time_ms(touch_press_time_ms),
    .rx_line_ascii      (rx_line_ascii),
    .wave_clk           (sys_clk),
    .u_wave_sample_valid(adc_u_wave_sample_valid),
    .u_wave_sample_code (adc_u_wave_sample_code),
    .u_wave_zero_code   (adc_u_zero_code),
    .u_wave_zero_valid  (adc_u_zero_valid),
    .i_wave_sample_valid(adc_i_wave_sample_valid),
    .i_wave_sample_code (adc_i_wave_sample_code),
    .i_wave_zero_code   (adc_i_zero_code),
    .i_wave_zero_valid  (adc_i_zero_valid),
    .lcd_id             (lcd_id),
    .lcd_hs             (lcd_hs),
    .lcd_vs             (lcd_vs),
    .lcd_de             (lcd_de),
    .lcd_rgb            (lcd_rgb),
    .lcd_bl             (lcd_bl),
    .lcd_rst_n          (lcd_rst_n),
    .lcd_clk            (lcd_clk)
);

//==========================================================================
// PLL
//==========================================================================
clk_wiz_0 u_clk_wiz_0 (
    .clk_out1 (clk_50m),
    .clk_out2 (clk_25m),
    .clk_out3 (clk_25m_deg120),
    .locked   (locked),
    .clk_in1  (sys_clk)
);

endmodule
