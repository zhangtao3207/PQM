//============================================================================
// 模块名称: main
//============================================================================
module main(
    input            sys_clk,     // 系统时钟输入
    input            sys_rst_n,   // 系统复位输入，低有效

    input            uart_rxd,    // UART接收引脚
    output           uart_txd,    // UART发送引脚

    input            adc_busy,    // ADC忙信号
    input            adc_frstdata,// ADC首通道标志
    input            adc_douta,   // ADC串行数据输出A
    input            adc_doutb,   // ADC串行数据输出B
    output           adc_reset,   // ADC复位信号
    output           adc_convst,  // ADC启动转换信号
    output           adc_sclk,    // ADC串行时钟
    output           adc_cs,      // ADC片选信号

    inout            touch_sda,   // 触摸I2C数据线
    output           touch_scl,   // 触摸I2C时钟线
    inout            touch_int,   // 触摸中断/握手引脚
    output           touch_rst_n, // 触摸复位引脚，低有效

    output           lcd_de,      // LCD数据使能
    output           lcd_hs,      // LCD行同步
    output           lcd_vs,      // LCD场同步
    output           lcd_bl,      // LCD背光控制
    output           lcd_clk,     // LCD像素时钟
    output           lcd_rst_n,   // LCD复位引脚，低有效
    inout   [23:0]   lcd_rgb     // LCD RGB数据总线/读ID复用总线

);

//==========================================================================
// 参数定义
//==========================================================================
localparam integer CLK_FREQ               = 50_000_000; // 系统时钟频率
localparam integer UART_BPS               = 115200;     // UART波特率
localparam integer ADC_RST_RELEASE_CYCLES = CLK_FREQ / 1000;

//==========================================================================
// 内部信号
//==========================================================================
wire  [15:0]  lcd_id;              // LCD屏ID
wire  [31:0]  data;                // 触摸坐标BCD数据
wire          touch_pressed;       // 按下脉冲
wire          touch_unpressed;     // 松开脉冲
wire          touch_click;         // 单击脉冲
wire          touch_long_press;    // 长按脉冲
wire          touch_drag;          // 拖动脉冲
wire          touch_click_state;   // 单击状态
wire          touch_long_state;    // 长按状态
wire          touch_drag_state;    // 拖动状态
wire  [15:0]  touch_start_x;       // 触摸起始X坐标
wire  [15:0]  touch_start_y;       // 触摸起始Y坐标
wire  [15:0]  touch_end_x;         // 触摸结束X坐标
wire  [15:0]  touch_end_y;         // 触摸结束Y坐标
wire  [15:0]  touch_press_time_ms; // 按压时长
wire  [4:0]   touch_state_bits;    // 触摸状态打包位
wire  [7:0]   uart_rx_data;        // UART接收字节
wire          uart_rx_done;        // UART接收完成脉冲
wire          uart_tx_busy;        // UART发送忙标志
reg   [7:0]   uart_tx_data;        // UART发送数据
reg           uart_tx_en;          // UART发送使能
reg   [127:0] rx_line_ascii;       // LCD显示的接收ASCII缓存
reg   [3:0]   rx_pos;              // 接收缓存写入位置
wire  [15:0]  adc_v1_data;         // ADC通道V1数据
wire  [15:0]  adc_v2_data;         // ADC通道V2数据
wire          adc_data_valid;      // ADC数据有效脉冲

wire        clk_50m;         // PLL输出50MHz
wire        clk_25m;         // PLL输出25MHz
wire        clk_25m_deg120;  // PLL输出25MHz相移时钟
wire        locked;          // PLL锁定标志
wire        rst_n;           // 锁定后的系统复位
reg         adc_rst_n;
reg  [31:0] adc_rst_cnt;

assign rst_n = sys_rst_n & locked;

always @(posedge sys_clk or negedge rst_n) begin
    if(!rst_n) begin
        adc_rst_n   <= 1'b0;
        adc_rst_cnt <= 32'd0;
    end
    else if(adc_rst_cnt >= ADC_RST_RELEASE_CYCLES - 1) begin
        adc_rst_n <= 1'b1;
    end
    else begin
        adc_rst_n   <= 1'b0;
        adc_rst_cnt <= adc_rst_cnt + 32'd1;
    end
end

//==========================================================================
// 函数：sanitize_char
//==========================================================================
function [7:0] sanitize_char;
    input [7:0] c;
    begin
        if(c < 8'h20 || c > 8'h7E)
            sanitize_char = 8'h20;
        else
            sanitize_char = c;
    end
endfunction

//==========================================================================
// UART模块实例化
//==========================================================================
uart #(
    .CLK_FREQ(CLK_FREQ),
    .UART_BPS(UART_BPS)
) u_uart (
    .clk         (sys_clk),
    .rst_n       (sys_rst_n),
    .uart_rxd    (uart_rxd),
    .uart_txd    (uart_txd),
    .tx_en       (uart_tx_en),
    .tx_data     (uart_tx_data),
    .tx_busy     (uart_tx_busy),
    .rx_data     (uart_rx_data),
    .rx_done     (uart_rx_done)
);

//==========================================================================
// Touch模块实例化
//==========================================================================
touch_top  u_touch_top(
    .clk              (sys_clk),
    .rst_n            (sys_rst_n),
    .touch_rst_n      (touch_rst_n),
    .touch_int        (touch_int),
    .touch_scl        (touch_scl),
    .touch_sda        (touch_sda),
    .lcd_id           (lcd_id),
    .data             (data),
    .touch_pressed    (touch_pressed),
    .touch_unpressed  (touch_unpressed),
    .touch_click      (touch_click),
    .touch_long_press (touch_long_press),
    .touch_drag       (touch_drag),
    .touch_click_state(touch_click_state),
    .touch_long_state (touch_long_state),
    .touch_drag_state (touch_drag_state),
    .touch_start_x    (touch_start_x),
    .touch_start_y    (touch_start_y),
    .touch_end_x      (touch_end_x),
    .touch_end_y      (touch_end_y),
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
// UART接收行缓冲
//==========================================================================
always @(posedge sys_clk or negedge sys_rst_n) begin
    if(!sys_rst_n) begin
        rx_line_ascii <= {16{8'h20}};
        rx_pos        <= 4'd0;
    end
    else if(uart_rx_done) begin
        if(uart_rx_data == 8'h0D || uart_rx_data == 8'h0A) begin
            rx_line_ascii <= {16{8'h20}};
            rx_pos        <= 4'd0;
        end
        else begin
            case(rx_pos)
                4'd0 : rx_line_ascii[127:120] <= sanitize_char(uart_rx_data);
                4'd1 : rx_line_ascii[119:112] <= sanitize_char(uart_rx_data);
                4'd2 : rx_line_ascii[111:104] <= sanitize_char(uart_rx_data);
                4'd3 : rx_line_ascii[103:96]    <= sanitize_char(uart_rx_data);
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
            if(rx_pos != 4'd15)
                rx_pos <= rx_pos + 4'd1;
        end
    end
end

//==========================================================================
// ADC模块实例化
//==========================================================================


//==========================================================================
// LCD显示模块
//==========================================================================
lcd_rgb_char  u_lcd_rgb_char(
   .sys_clk           (sys_clk),
   .sys_rst_n         (sys_rst_n),
   .data              (data),
   .touch_state_bits  (touch_state_bits),
   .touch_start_x     (touch_start_x),
   .touch_start_y     (touch_start_y),
   .touch_press_time_ms(touch_press_time_ms),
   .rx_line_ascii     (rx_line_ascii),
   .lcd_id            (lcd_id),
   .lcd_hs            (lcd_hs),
   .lcd_vs            (lcd_vs),
   .lcd_de            (lcd_de),
   .lcd_rgb           (lcd_rgb),
   .lcd_bl            (lcd_bl),
   .lcd_rst_n         (lcd_rst_n),
   .lcd_clk           (lcd_clk)
);

//==========================================================================
// PLL时钟向导
//==========================================================================
clk_wiz_0 u_clk_wiz_0(
    .clk_out1  (clk_50m),
    .clk_out2  (clk_25m),
    .clk_out3  (clk_25m_deg120),
    .locked    (locked),
    .clk_in1   (sys_clk)
);



endmodule
