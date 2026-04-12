
//模块：串口模块顶层
//功能：将UART发送和接收功能进行集成封装
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
