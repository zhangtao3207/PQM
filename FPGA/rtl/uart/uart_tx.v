// uart_tx
// 功能:
//   将单字节数据按 8N1 格式发送。上升沿打拍使能，内部按波特计数整位输出。
// 参数:
//   CLK_FREQ    - 输入时钟频率（Hz）
//   UART_BPS    - 波特率（bits/s）
//   BAUD_CNT_MAX= CLK_FREQ/UART_BPS（位时间计数）
// 接口:
//   clk, rst_n      - 时钟/异步复位（低有效）
//   uart_tx_en      - 发送触发单脉冲（空闲时采样有效）
//   uart_tx_data[7:0]- 要发送的数据
//   uart_txd        - 串行输出（空闲高）
//   uart_tx_busy    - 发送忙标志（覆盖起始位到停止位全过程）
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

// 在空闲时沿检测触发一次发送
wire tx_start = uart_tx_en & ~uart_tx_en_d0 & ~uart_tx_busy;
wire baud_tick = (baud_cnt == BAUD_CNT_MAX - 1);


always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        uart_tx_en_d0 <= 1'b0;
    else
        uart_tx_en_d0 <= uart_tx_en;
end

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
