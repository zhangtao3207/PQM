`timescale 1ns / 1ps

/*
 * 模块: reset_sync_n
 * 功能:
 *   低有效复位的同步器：**异步置位、同步释放**。
 *
 *   为什么需要它：
 *     vivado 顶层把 PL_SHARED_BRAM_rst 接成 ~(sys_rst_n & locked)，这是一个来自按键的
 *     异步复位；而该 BRAM 的 IP 配置是 Reset_Type: SYNC。异步复位去驱动同步复位的
 *     存储单元，释放边沿可能与时钟任意对齐：不同的触发器会在不同的时钟沿退出复位，
 *     造成"一部分已复位、一部分未复位"的中间态。复位释放必须同步到 BRAM 的工作时钟。
 *
 *   极性与参考实现：
 *     只读参考工程 B-20260803/rtl/measurement/reset_sync.v 是高有效版（异步请求高、
 *     输出高）。本模块是它的极性镜像：异步请求低、输出低有效。
 *     高有效：异步置位时链置 2'b11，释放时逐拍移入 0，第 2 拍输出 0。
 *     低有效：异步置位时链置 2'b00，释放时逐拍移入 1，第 2 拍输出 1。
 *
 *   行为（与参考实现一致，给出可验证的时序契约）：
 *     - 异步置位：async_reset_n 一拉低，reset_n_out 立刻为 0（不等时钟沿）。
 *     - 同步释放：async_reset_n 拉高后，reset_n_out 仍保持 0 **两个时钟沿**，
 *       第 2 个时钟沿之后才变 1。这样释放边沿永远对齐在工作时钟上。
 *
 *   例化位置（本轮未改，见交付说明）：
 *     vivado/src/pqm2_meas_top.v 里应改成
 *       reset_sync_n u_bram_reset_sync (.clk(pl_clk), .async_reset_n(pl_resetn),
 *                                       .reset_n_out(bram_reset_n));
 *       PL_SHARED_BRAM_rst = ~bram_reset_n;
 *     其中 pl_resetn = sys_rst_n & locked。
 *
 * 输入:
 *   clk: 目标时钟域时钟（BRAM 的工作时钟）。
 *   async_reset_n: 低有效、异步的原始复位请求。
 * 输出:
 *   reset_n_out: 异步置位、同步释放的低有效复位。
 */

module reset_sync_n (
    input  wire clk,
    input  wire async_reset_n,
    output wire reset_n_out
);

    // 两级同步链。ASYNC_REG 让综合把这两级放到同一个 slice、并按异步输入处理，
    // 避免布局把组合逻辑插进链里（与参考实现同一写法）。
    (* ASYNC_REG = "TRUE" *) reg [1:0] reset_sync_ff;

    always @(posedge clk or negedge async_reset_n) begin
        if (!async_reset_n)
            reset_sync_ff <= 2'b00;              // 异步置位：立刻进入复位
        else
            reset_sync_ff <= {reset_sync_ff[0], 1'b1};   // 同步释放：逐拍移入 1
    end

    assign reset_n_out = reset_sync_ff[1];

endmodule
