/*
 * 模块: uart_tx
 * 功能:
 *   UART 发送模块，按 8N1 格式输出串口字节流。
 *
 * 输入:
 *   clk: 系统时钟。
 *   rst_n: 低有效复位信号。
 *   uart_tx_en: UART 发送启动脉冲。
 *   uart_tx_data: UART 待发送字节。
 *
 * 输出:
 *   uart_txd: UART 串行发送输出。
 *   uart_tx_busy: UART 发送忙标志。
 */
module uart_tx #(
    parameter integer CLK_FREQ     = 50_000_000,
    parameter integer UART_BPS     = 115200,
    parameter integer BAUD_CNT_MAX = CLK_FREQ / UART_BPS
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       uart_tx_en,
    input  wire [7:0] uart_tx_data,

    output reg        uart_txd,
    output reg        uart_tx_busy
);

reg        uart_tx_en_d0;
reg [15:0] baud_cnt;
reg [3:0]  tx_cnt;
reg [7:0]  tx_data_t;

// 在空闲状态检测发送请求上升沿，生成一帧发送的启动条件。
wire tx_start  = uart_tx_en & ~uart_tx_en_d0 & ~uart_tx_busy;
wire baud_tick = (baud_cnt == BAUD_CNT_MAX - 1);

// 对发送使能打拍，用于检测单拍启动脉冲。
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        uart_tx_en_d0 <= 1'b0;
    else
        uart_tx_en_d0 <= uart_tx_en;
end

// 在启动时锁存待发字节，并维护发送忙标志。
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        uart_tx_busy <= 1'b0;
        tx_data_t    <= 8'd0;
    end
    else if(tx_start) begin
        uart_tx_busy <= 1'b1;
        tx_data_t    <= uart_tx_data;
    end
    else if(uart_tx_busy && tx_cnt == 4'd9 && baud_tick) begin
        uart_tx_busy <= 1'b0;
    end
end

// 按波特率对单个位时间计数。
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        baud_cnt <= 16'd0;
    else if(tx_start)                   // 起始位前清零位计数
        baud_cnt <= 16'd0;
    else if(uart_tx_busy) begin
        if(baud_tick)
            baud_cnt <= 16'd0;
        else
            baud_cnt <= baud_cnt + 16'd1;
    end
    else
        baud_cnt <= 16'd0;
end

// 记录当前发送到起始位、数据位还是停止位。
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        tx_cnt <= 4'd0;
    else if(tx_start)                   // 位计数从 0 开始: 0=起始位,1..8=数据位,9=停止位
        tx_cnt <= 4'd0;
    else if(uart_tx_busy && baud_tick)
        tx_cnt <= tx_cnt + 4'd1;
    else if(!uart_tx_busy)
        tx_cnt <= 4'd0;
end

// 按 8N1 帧格式在串口线上依次输出起始位、数据位和停止位。
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        uart_txd <= 1'b1;
    end
    else if(uart_tx_busy) begin
        case(tx_cnt)
            4'd0: uart_txd <= 1'b0;        // start
            4'd1: uart_txd <= tx_data_t[0];
            4'd2: uart_txd <= tx_data_t[1];
            4'd3: uart_txd <= tx_data_t[2];
            4'd4: uart_txd <= tx_data_t[3];
            4'd5: uart_txd <= tx_data_t[4];
            4'd6: uart_txd <= tx_data_t[5];
            4'd7: uart_txd <= tx_data_t[6];
            4'd8: uart_txd <= tx_data_t[7];
            4'd9: uart_txd <= 1'b1;        // stop
            default: uart_txd <= 1'b1;
        endcase
    end
    else begin
        uart_txd <= 1'b1;
    end
end

endmodule
