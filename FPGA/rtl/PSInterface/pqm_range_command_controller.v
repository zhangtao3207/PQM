`timescale 1ns / 1ps

/*
 * 模块: pqm_range_command_controller
 * 功能:
 *   解析 PS 共享内存命令中的量程设置请求，锁存实际量程状态，并保持响应
 *   直到共享内存桥完成握手；非法命令不会改变当前量程。
 * 输入:
 *   clk: PL 测量与共享内存命令使用的 50 MHz 工作时钟。
 *   rst_n: 低有效异步复位。
 *   command_valid: 共享内存桥送来的单拍命令有效脉冲。
 *   command_code: PS 请求的命令码。
 *   command_argument: PS 请求的命令参数。
 *   response_ready: 共享内存桥允许接收响应的握手信号。
 * 输出:
 *   response_valid: 响应数据有效标志，背压期间保持为高。
 *   response: 成功时回显实际量程，失败时返回全一错误码。
 *   low_range_active: 当前是否启用 10 V / 3 A 低量程。
 * 双向: 无。
 */
module pqm_range_command_controller (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         command_valid,
    input  wire [31:0]  command_code,
    input  wire [31:0]  command_argument,
    output reg          response_valid,
    input  wire         response_ready,
    output reg  [31:0]  response,
    output reg          low_range_active
);

localparam [31:0] COMMAND_SET_RANGE = 32'h0000_0001;
localparam [31:0] RANGE_HIGH = 32'h0000_0000;
localparam [31:0] RANGE_LOW = 32'h0000_0001;
localparam [31:0] RESPONSE_ERROR = 32'hFFFF_FFFF;

// 在命令到达时原子更新量程和响应，并在 ready 握手前保持 valid。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        response_valid <= 1'b0;
        response <= RANGE_HIGH;
        low_range_active <= 1'b0;
    end else begin
        if (command_valid && !response_valid) begin
            response_valid <= 1'b1;
            if ((command_code == COMMAND_SET_RANGE) &&
                ((command_argument == RANGE_HIGH) ||
                 (command_argument == RANGE_LOW))) begin
                low_range_active <= command_argument[0];
                response <= command_argument;
            end else begin
                response <= RESPONSE_ERROR;
            end
        end else if (response_valid && response_ready) begin
            response_valid <= 1'b0;
        end
    end
end

endmodule
