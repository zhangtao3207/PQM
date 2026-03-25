// uart_rx
// 功能:
//   接收 8N1 格式单字节数据。三拍同步+起始沿检测，位中采样，起止位校验。
// 参数:
//   CLK_FREQ/UART_BPS/BAUD_CNT_MAX 与发送端一致
// 接口:
//   clk, rst_n   - 时钟/异步复位（低有效）
//   uart_rxd     - 串行输入（空闲高）
//   uart_rx_data - 接收的 1 字节数据
//   uart_rx_done - 完成脉冲（帧有效且停止位为 1）
module uart_rx #(
    parameter integer CLK_FREQ     = 50_000_000,
    parameter integer UART_BPS     = 115200,
    parameter integer BAUD_CNT_MAX = CLK_FREQ / UART_BPS
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       uart_rxd,

    output reg [7:0]  uart_rx_data,
    output reg        uart_rx_done
);

reg        uart_rxd_d0;
reg        uart_rxd_d1;
reg        uart_rxd_d2;
reg        rx_flag;
reg [15:0] baud_cnt;
reg [3:0]  rx_cnt;
reg [7:0]  rx_data_t;
reg        frame_ok;

// 检测到高->低起始沿且未在接收中
wire start_edge = uart_rxd_d2 & ~uart_rxd_d1 & ~rx_flag;
wire baud_tick  = (baud_cnt == BAUD_CNT_MAX - 1);
wire mid_tick   = (baud_cnt == (BAUD_CNT_MAX >> 1) - 1);


always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        uart_rxd_d0 <= 1'b1;
        uart_rxd_d1 <= 1'b1;
        uart_rxd_d2 <= 1'b1;
    end
    else begin
        uart_rxd_d0 <= uart_rxd;
        uart_rxd_d1 <= uart_rxd_d0;
        uart_rxd_d2 <= uart_rxd_d1;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        rx_flag <= 1'b0;
    end
    else if(start_edge) begin
        rx_flag <= 1'b1;
    end
    else if(rx_flag && rx_cnt == 4'd9 && mid_tick) begin
        rx_flag <= 1'b0;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        baud_cnt <= 16'd0;
    end
    else if(rx_flag) begin
        if(baud_tick)
            baud_cnt <= 16'd0;
        else
            baud_cnt <= baud_cnt + 16'd1;
    end
    else begin
        baud_cnt <= 16'd0;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        rx_cnt <= 4'd0;
    end
    else if(rx_flag) begin
        if(baud_tick)
            rx_cnt <= rx_cnt + 4'd1;
    end
    else begin
        rx_cnt <= 4'd0;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        rx_data_t <= 8'd0;
        frame_ok  <= 1'b0;
    end
    else if(rx_flag && mid_tick) begin
        case(rx_cnt)
            4'd0: frame_ok <= ~uart_rxd_d2;      // 起始位中点仍为 0
            4'd1: rx_data_t[0] <= uart_rxd_d2;
            4'd2: rx_data_t[1] <= uart_rxd_d2;
            4'd3: rx_data_t[2] <= uart_rxd_d2;
            4'd4: rx_data_t[3] <= uart_rxd_d2;
            4'd5: rx_data_t[4] <= uart_rxd_d2;
            4'd6: rx_data_t[5] <= uart_rxd_d2;
            4'd7: rx_data_t[6] <= uart_rxd_d2;
            4'd8: rx_data_t[7] <= uart_rxd_d2;
            4'd9: frame_ok <= frame_ok & uart_rxd_d2; // 停止位应为 1
            default: ;
        endcase
    end
    else if(!rx_flag) begin
        frame_ok <= 1'b0;
    end
end

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        uart_rx_done <= 1'b0;
        uart_rx_data <= 8'd0;
    end
    else if(rx_flag && rx_cnt == 4'd9 && mid_tick && frame_ok && uart_rxd_d2) begin
        uart_rx_done <= 1'b1;
        uart_rx_data <= rx_data_t;
    end
    else begin
        uart_rx_done <= 1'b0;
    end
end

endmodule
