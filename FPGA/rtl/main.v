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

    input            ad_busy,
    input            ad_frstdata,
    input   [15:0]   ad_data,
    output           ad_rst,
    output wire      ad_convst,
    output wire      ad_cs_n,
    output wire      ad_rd_n
);

//==========================================================================
// Parameters
//==========================================================================
localparam integer CLK_FREQ               = 50_000_000;
localparam integer UART_BPS               = 115200;

localparam integer ADC_RESET_HIGH_CYCLES   = 500;
localparam integer ADC_CONVST_LOW_CYCLES   = 20;
localparam integer ADC_RD_LOW_CYCLES       = 16;
localparam integer ADC_RD_HIGH_CYCLES      = 16;
localparam integer ADC_BUSY_TIMEOUT_CYCLES = 100000;
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
reg   [7:0]  uart_tx_data;
reg          uart_tx_en;
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
reg          adc_start;
reg          adc_idle_seen;
reg  [15:0]  adc_startup_wait_cnt;
wire         adc_startup_wait_done;

assign rst_n                  = sys_rst_n & locked;
assign adc_startup_wait_done  = (adc_startup_wait_cnt >= ADC_STARTUP_WAIT_CYCLES - 1);

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
uart #(
    .CLK_FREQ(CLK_FREQ),
    .UART_BPS(UART_BPS)
) u_uart (
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
    end
end

//==========================================================================
// ADC instance: switched to parallel mode
//==========================================================================
AD7606_Parallel_DRIVER #(
    .RESET_HIGH_CYCLES  (ADC_RESET_HIGH_CYCLES),
    .CONVST_LOW_CYCLES  (ADC_CONVST_LOW_CYCLES),
    .RD_LOW_CYCLES      (ADC_RD_LOW_CYCLES),
    .RD_HIGH_CYCLES     (ADC_RD_HIGH_CYCLES),
    .BUSY_TIMEOUT_CYCLES(ADC_BUSY_TIMEOUT_CYCLES)
) u_AD7606_Parallel_DRIVER (
    .clk          (sys_clk),
    .rst_n        (rst_n),
    .start        (adc_start),
    .soft_reset   (1'b0),
    .ad_busy      (ad_busy),
    .ad_frstdata  (ad_frstdata),
    .ad_data      (ad_data),
    .ad_reset     (ad_rst),
    .ad_convst    (ad_convst),
    .ad_cs_n      (ad_cs_n),
    .ad_rd_n      (ad_rd_n),
    .ch1_data     (AD_DATA_1),
    .ch2_data     (AD_DATA_2),
    .ch3_data     (AD_DATA_3),
    .ch4_data     (AD_DATA_4),
    .ch5_data     (AD_DATA_5),
    .ch6_data     (AD_DATA_6),
    .ch7_data     (AD_DATA_7),
    .ch8_data     (AD_DATA_8),
    .data_frame   (),
    .data_valid   (),
    .sample_active(adc_sample_active),
    .timeout      (),
    .ad_channal   (AD_CHANNAL),
    .ad_state     (AD_STATE)
);

//==========================================================================
// ILA debug instance
// Probe order for the reconfigured ILA_ADC_DRIVER:
// probe0  -> ad_rst
// probe1  -> ad_convst
// probe2  -> ad_rd_n
// probe3  -> ad_cs_n
// probe4  -> ad_busy
// probe5  -> ad_frstdata
// probe6  -> AD_DATA_1
// probe7  -> AD_DATA_2
// probe8  -> AD_DATA_3
// probe9  -> AD_DATA_4
// probe10 -> AD_DATA_5
// probe11 -> AD_DATA_6
// probe12 -> AD_DATA_7
// probe13 -> AD_DATA_8
// probe14 -> AD_CHANNAL
// probe15 -> AD_STATE
// Note:
//   AD_CHANNAL is the dynamic binary channel number currently being read.
//   AD_STATE uses 3 bits because the parallel controller currently has 7 states.
//==========================================================================
ILA_ADC_DRIVER u_ila_adc_driver (
    .clk    (sys_clk),
    .probe0 (ad_rst),
    .probe1 (ad_convst),
    .probe2 (ad_rd_n),
    .probe3 (ad_cs_n),
    .probe4 (ad_busy),
    .probe5 (ad_frstdata),
    .probe6 (AD_DATA_1),
    .probe7 (AD_DATA_2),
    .probe8 (AD_DATA_3),
    .probe9 (AD_DATA_4),
    .probe10(AD_DATA_5),
    .probe11(AD_DATA_6),
    .probe12(AD_DATA_7),
    .probe13(AD_DATA_8),
    .probe14(AD_CHANNAL),
    .probe15(AD_STATE)
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
