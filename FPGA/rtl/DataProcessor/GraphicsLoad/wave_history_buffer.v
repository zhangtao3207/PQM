`timescale 1ns / 1ps

/*
 * 模块: wave_history_buffer
 * 功能:
 *   维护用于波形显示的环形历史缓存，在显示点提交时写入新的 Y 坐标，
 *   同时对外提供当前写指针、缓存写满标志、最后一个写入点以及随机读口。
 *
 * 输入:
 *   clk: 模块工作时钟
 *   rst_n: 低有效复位
 *   point_valid: 本拍有一个显示点需要写入历史缓存
 *   point_y: 本次写入的显示点 Y 坐标
 *   rd_idx: 需要读取的历史缓存点索引
 *
 * 输出:
 *   wr_ptr: 当前历史缓存写指针
 *   hist_full: 环形缓存是否已至少写满一圈
 *   last_y: 最近一次写入的显示点 Y 坐标
 *   rd_data: 按 rd_idx 读出的历史缓存点数据
 */
module wave_history_buffer #(
    parameter integer POINT_COUNT      = 384,
    parameter integer POINT_ADDR_WIDTH = 9,
    parameter integer Y_WIDTH          = 8,
    parameter [Y_WIDTH-1:0] Y_RESET    = 8'd120
)(
    input  wire                        clk,
    input  wire                        rst_n,
    input  wire                        point_valid,
    input  wire [Y_WIDTH-1:0]          point_y,
    input  wire [POINT_ADDR_WIDTH-1:0] rd_idx,
    output reg  [POINT_ADDR_WIDTH-1:0] wr_ptr,
    output reg                         hist_full,
    output reg  [Y_WIDTH-1:0]          last_y,
    output wire [Y_WIDTH-1:0]          rd_data
);

// 波形显示历史缓存，按环形队列方式存储一帧显示点
reg [Y_WIDTH-1:0] hist_mem [0:POINT_COUNT-1];

integer init_idx;

assign rd_data = hist_mem[rd_idx];

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        wr_ptr    <= {POINT_ADDR_WIDTH{1'b0}};
        hist_full <= 1'b0;
        last_y    <= Y_RESET;

        for (init_idx = 0; init_idx < POINT_COUNT; init_idx = init_idx + 1)
            hist_mem[init_idx] <= Y_RESET;
    end else begin
        if (point_valid) begin
            // 将当前显示点写入历史缓存，并推进环形写指针
            hist_mem[wr_ptr] <= point_y;
            last_y           <= point_y;

            if (wr_ptr == (POINT_COUNT - 1)) begin
                wr_ptr    <= {POINT_ADDR_WIDTH{1'b0}};
                hist_full <= 1'b1;
            end else begin
                wr_ptr    <= wr_ptr + 1'b1;
            end
        end
    end
end

endmodule
