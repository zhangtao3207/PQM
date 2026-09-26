`timescale 1ns / 1ps

/*
 * 模块: pqm_sample_fifo
 * 功能:
 *   频域链前置的小缓冲，每通道一个。存在的唯一理由（本轮实测发现）：
 *   RFG 只认**样本序列**、不认时间——它算的是"连续 N 个采样点的 DFT"。
 *   若上游在 RFG 未就绪时把采样丢掉（例如计算期 o_sample_ready 为低），
 *   一帧的 N 个点就不再连续、会跨多个周期，谱随之泄漏。本模块把 ADC 的
 *   连续采样流缓存下来，让 RFG 每次都能取到真正连续的 N 个点。
 *
 *   深度只需覆盖 RFG 的计算期：25.6 kSPS 下 L4/D1 的计算期 83840 拍
 *   ≈ 43 个采样，故 64 深足够（L16/D8 只要 3464 拍 ≈ 1.8 个采样，几级就够）。
 *   读写同钟（都是 50 MHz 工作时钟），因此不需要跨时钟处理。
 *
 *   溢出策略：写满时丢弃本次写入（不覆盖未读数据），并把 o_overflow 置起——
 *   丢一个采样只会让该帧的相位起点变一点，不会造成数据错位。
 *   内存用寄存器阵列实现（深度小，不需要 BRAM，更不依赖任何 IP）。
 */

module pqm_sample_fifo #(
    parameter integer DEPTH = 64,          // 必须是 2 的幂
    parameter integer AW    = 6            // = log2(DEPTH)
)(
    input  wire        clk,
    input  wire        rst_n,

    // 写侧：ADC 采样流
    input  wire        i_wr_en,
    input  wire [15:0] i_din,

    // 读侧：RFG 取样
    input  wire        i_rd_en,
    output wire [15:0] o_dout,

    output wire        o_empty,
    output wire        o_full,
    output reg         o_overflow,          // 写满丢样本（粘滞，由 rst_n 清）
    output wire [AW:0] o_count
);

    reg [15:0] mem [0:DEPTH-1];
    reg [AW:0] wr_ptr;                       // 多一位用于区分满/空
    reg [AW:0] rd_ptr;

    wire       full_w  = (wr_ptr[AW] != rd_ptr[AW]) && (wr_ptr[AW-1:0] == rd_ptr[AW-1:0]);
    wire       empty_w = (wr_ptr == rd_ptr);
    wire       do_wr   = i_wr_en && !full_w;
    wire       do_rd   = i_rd_en && !empty_w;

    assign o_dout  = mem[rd_ptr[AW-1:0]];
    assign o_empty = empty_w;
    assign o_full  = full_w;
    assign o_count = wr_ptr - rd_ptr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr      <= {(AW+1){1'b0}};
            rd_ptr      <= {(AW+1){1'b0}};
            o_overflow  <= 1'b0;
        end else begin
            if (do_wr) begin
                mem[wr_ptr[AW-1:0]] <= i_din;
                wr_ptr              <= wr_ptr + 1'b1;
            end else if (i_wr_en && full_w) begin
                o_overflow <= 1'b1;          // 写满丢样本，记录下来
            end

            if (do_rd)
                rd_ptr <= rd_ptr + 1'b1;
        end
    end

endmodule
