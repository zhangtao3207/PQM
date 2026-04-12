`timescale 1ns / 1ps

/*
 * 模块: wave_frame_writer
 * 功能:
 *   在收到抓帧请求后，从波形历史缓存的快照位置开始顺序读取显示点，
 *   并将一整帧波形数据写入外部显示 RAM 的非显示 bank。
 *   模块内部维护整帧拷贝状态机，对外输出历史缓存读地址、RAM 写口以及帧提交结果。
 *
 * 输入:
 *   clk: 模块工作时钟
 *   rst_n: 低有效复位
 *   start_copy: 启动一次整帧拷贝
 *   snapshot_ptr: 本次抓帧对应的历史缓存快照写指针
 *   last_y: 本次抓帧最后一个显示点的 Y 坐标
 *   display_bank: 当前正在显示的 RAM bank
 *   hist_rd_data: 按 hist_rd_idx 读出的历史缓存点数据
 *
 * 输出:
 *   active: 当前正在执行整帧拷贝
 *   hist_rd_idx: 需要从历史缓存读取的点索引
 *   commit_valid: 一整帧写完后的提交脉冲
 *   commit_bank: 本次写完后应切换到的显示 bank
 *   wave_ram_we: 显示 RAM 写使能
 *   wave_ram_waddr: 显示 RAM 写地址
 *   wave_ram_wdata: 显示 RAM 写数据
 */
module wave_frame_writer #(
    parameter integer POINT_COUNT      = 384,
    parameter integer POINT_ADDR_WIDTH = 9,
    parameter integer RAM_ADDR_WIDTH   = 10,
    parameter integer Y_WIDTH          = 8,
    parameter [Y_WIDTH-1:0] Y_RESET    = 8'd120
)(
    input  wire                        clk,
    input  wire                        rst_n,
    input  wire                        start_copy,
    input  wire [POINT_ADDR_WIDTH-1:0] snapshot_ptr,
    input  wire [Y_WIDTH-1:0]          last_y,
    input  wire                        display_bank,
    input  wire [Y_WIDTH-1:0]          hist_rd_data,
    output reg                         active,
    output wire [POINT_ADDR_WIDTH-1:0] hist_rd_idx,
    output reg                         commit_valid,
    output reg                         commit_bank,
    output reg                         wave_ram_we,
    output reg  [RAM_ADDR_WIDTH-1:0]   wave_ram_waddr,
    output reg  [Y_WIDTH-1:0]          wave_ram_wdata
);

// 整帧写出状态寄存器：记录当前写入位置、目标 bank 与抓帧快照信息
reg [POINT_ADDR_WIDTH-1:0] copy_idx;
reg                        copy_bank;
reg [POINT_ADDR_WIDTH-1:0] copy_wr_ptr_snapshot;
reg [Y_WIDTH-1:0]          copy_last_y;

// 根据快照位置与当前写入序号生成历史缓存读地址
wire [POINT_ADDR_WIDTH:0] hist_rd_sum;

assign hist_rd_sum = {1'b0, copy_wr_ptr_snapshot} + {1'b0, copy_idx} + 1'b1;
assign hist_rd_idx = (hist_rd_sum >= POINT_COUNT) ?
                     (hist_rd_sum - POINT_COUNT) :
                     hist_rd_sum[POINT_ADDR_WIDTH-1:0];

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        active         <= 1'b0;
        copy_idx       <= {POINT_ADDR_WIDTH{1'b0}};
        copy_bank      <= 1'b0;
        copy_wr_ptr_snapshot <= {POINT_ADDR_WIDTH{1'b0}};
        copy_last_y    <= Y_RESET;
        commit_valid   <= 1'b0;
        commit_bank    <= 1'b0;
        wave_ram_we    <= 1'b0;
        wave_ram_waddr <= {RAM_ADDR_WIDTH{1'b0}};
        wave_ram_wdata <= Y_RESET;
    end else begin
        // 默认拉低单拍控制信号
        wave_ram_we  <= 1'b0;
        commit_valid <= 1'b0;

        if (!active && start_copy) begin
            // 锁存本次抓帧参数，下一拍开始顺序写出整帧数据
            active               <= 1'b1;
            copy_idx             <= {POINT_ADDR_WIDTH{1'b0}};
            copy_bank            <= ~display_bank;
            copy_wr_ptr_snapshot <= snapshot_ptr;
            copy_last_y          <= last_y;
        end

        if (active) begin
            wave_ram_we    <= 1'b1;
            wave_ram_waddr <= {copy_bank, copy_idx};

            if (copy_idx == (POINT_COUNT - 1)) begin
                // 最后一个点直接写入抓帧时锁存的末点坐标
                wave_ram_wdata <= copy_last_y;
                active         <= 1'b0;
                commit_valid   <= 1'b1;
                commit_bank    <= copy_bank;
            end else begin
                // 其余点从历史缓存按环形顺序依次搬运到显示 RAM
                wave_ram_wdata <= hist_rd_data;
                copy_idx       <= copy_idx + 1'b1;
            end
        end
    end
end

endmodule
