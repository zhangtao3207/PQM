`timescale 1ns / 1ps

/*
 * 模块名称：pqm_axis_sample_stream
 * 功能说明：将连续 ADC 样本封装为带源序号的 AXI4-Stream，反压时丢弃新样本而不阻塞采集链路。
 * 参数说明：
 *   FRAME_SAMPLES：每个 DMA 帧包含的已接收样本数。
 * 输入端口：
 *   clk：AXI 样本流时钟。
 *   rst_n：低有效同步逻辑复位。
 *   sample_valid：ADC U1 和 U2样本有效脉冲。
 *   u1_sample：16 位U1原始样本。
 *   u2_sample：16 位U2原始样本。
 *   m_axis_tready：下游允许接收当前 AXI 数据。
 * 输出端口：
 *   source_sequence：下一个源样本的递增序号。
 *   drop_count：因下游反压而丢弃的饱和计数。
 *   m_axis_tdata：源序号、U2和U1组成的 64 位数据。
 *   m_axis_tvalid：当前 AXI 数据有效标志。
 *   m_axis_tlast：每 FRAME_SAMPLES 个已接收样本产生的帧尾标志。
 * 双向端口：无。
 */
module pqm_axis_sample_stream #(
    parameter integer FRAME_SAMPLES = 2048
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sample_valid,
    input  wire [15:0] u1_sample,
    input  wire [15:0] u2_sample,
    output reg  [31:0] source_sequence,
    output reg  [31:0] drop_count,
    output reg  [63:0] m_axis_tdata,
    output reg         m_axis_tvalid,
    input  wire        m_axis_tready,
    output reg         m_axis_tlast
);

localparam [31:0] LAST_FRAME_POSITION = FRAME_SAMPLES - 1;

reg  [31:0] frame_position;
wire        axis_transfer;
wire        output_available;
wire [31:0] load_frame_position;
wire        load_tlast;

// 标记当前输出寄存器是否在本拍完成握手。
assign axis_transfer = m_axis_tvalid && m_axis_tready;

// 输出为空或本拍将被接收时，允许装入一个新源样本。
assign output_available = !m_axis_tvalid || m_axis_tready;

// 计算新装入样本在当前 DMA 帧中的零基位置。
assign load_frame_position = axis_transfer
                           ? (m_axis_tlast ? 32'd0 : (frame_position + 1'b1))
                           : frame_position;

// 新装入样本位于帧末位置时随数据锁存 TLAST。
assign load_tlast = (load_frame_position == LAST_FRAME_POSITION);

// 维护源序号、丢样计数、已接收帧位置和单项 AXI 输出寄存器。
always @(posedge clk) begin
    if (!rst_n) begin
        source_sequence <= 32'd0;
        drop_count      <= 32'd0;
        frame_position  <= 32'd0;
        m_axis_tdata    <= 64'd0;
        m_axis_tvalid   <= 1'b0;
        m_axis_tlast    <= 1'b0;
    end else begin
        if (sample_valid) begin
            source_sequence <= source_sequence + 1'b1;
        end

        if (sample_valid && m_axis_tvalid && !m_axis_tready) begin
            if (drop_count != 32'hFFFF_FFFF) begin
                drop_count <= drop_count + 1'b1;
            end
        end

        if (axis_transfer) begin
            if (m_axis_tlast) begin
                frame_position <= 32'd0;
            end else begin
                frame_position <= frame_position + 1'b1;
            end
        end

        if (sample_valid && output_available) begin
            m_axis_tdata  <= {source_sequence, u2_sample, u1_sample};
            m_axis_tvalid <= 1'b1;
            m_axis_tlast  <= load_tlast;
        end else if (axis_transfer) begin
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;
        end
    end
end

endmodule
