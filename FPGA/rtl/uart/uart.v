/*
 * 模块: uart
 * 功能:
 *   UART 收发顶层封装，统一参数后实例化接收器和发送器。
 *
 * 输入:
 *   clk: 系统时钟。
 *   rst_n: 低有效复位信号。
 *   uart_rxd: UART 串行接收输入。
 *   tx_en: 发送启动脉冲。
 *   tx_data: 待发送字节数据。
 *
 * 输出:
 *   uart_txd: UART 串行发送输出。
 *   tx_busy: UART 发送忙标志。
 *   rx_data: UART 接收字节数据。
 *   rx_done: UART 接收完成脉冲。
 */
module uart (
    input  wire       clk,
    input  wire       rst_n,

    input  wire       uart_rxd,
    output wire       uart_txd,

    input  wire       tx_en,
    input  wire [7:0] tx_data,
    output wire       tx_busy,

    output wire [7:0] rx_data,
    output wire       rx_done
);

parameter integer CLK_FREQ     = 50_000_000;
parameter integer UART_BPS     = 115200;
parameter integer BAUD_CNT_MAX = CLK_FREQ / UART_BPS;

// UART 接收子模块，完成串行输入到字节数据的转换。
uart_rx #(
    .CLK_FREQ     (CLK_FREQ),
    .UART_BPS     (UART_BPS),
    .BAUD_CNT_MAX (BAUD_CNT_MAX)
) u_uart_rx (
    .clk          (clk),
    .rst_n        (rst_n),
    .uart_rxd     (uart_rxd),
    .uart_rx_data (rx_data),
    .uart_rx_done (rx_done)
);

// UART 发送子模块，将待发字节按 8N1 格式串行输出。
uart_tx #(
    .CLK_FREQ     (CLK_FREQ),
    .UART_BPS     (UART_BPS),
    .BAUD_CNT_MAX (BAUD_CNT_MAX)
) u_uart_tx (
    .clk          (clk),
    .rst_n        (rst_n),
    .uart_tx_en   (tx_en),
    .uart_tx_data (tx_data),
    .uart_txd     (uart_txd),
    .uart_tx_busy (tx_busy)
);

endmodule
