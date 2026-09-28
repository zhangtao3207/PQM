`timescale 1ns / 1ps

/*
 * 模块名称：pqm_axis_rgb565_to_rgb888
 * 功能说明：将 VDMA 的 RGB565 AXI4-Stream 扩展为视频输出使用的 RGB888，并保持帧边带。
 * 输入端口：
 *   clk：像素 AXI 流时钟。
 *   rst_n：低有效同步逻辑复位。
 *   s_axis_tdata：输入 RGB565 像素。
 *   s_axis_tvalid：输入像素有效标志。
 *   s_axis_tuser：输入帧首标志。
 *   s_axis_tlast：输入行末标志。
 *   m_axis_tready：下游允许接收输出像素。
 * 输出端口：
 *   s_axis_tready：本模块允许接收输入像素。
 *   m_axis_tdata：扩展后的 RGB888 像素。
 *   m_axis_tvalid：输出像素有效标志。
 *   m_axis_tuser：与输出像素配对的帧首标志。
 *   m_axis_tlast：与输出像素配对的行末标志。
 * 双向端口：无。
 */
module pqm_axis_rgb565_to_rgb888 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [15:0] s_axis_tdata,
    input  wire        s_axis_tvalid,
    output wire        s_axis_tready,
    input  wire        s_axis_tuser,
    input  wire        s_axis_tlast,
    output wire [23:0] m_axis_tdata,
    output wire        m_axis_tvalid,
    input  wire        m_axis_tready,
    output wire        m_axis_tuser,
    output wire        m_axis_tlast
);

wire [7:0] expanded_red;
wire [7:0] expanded_green;
wire [7:0] expanded_blue;
reg  [23:0] data_reg;
reg         valid_reg;
reg         user_reg;
reg         last_reg;

// 将 5 位红色通道高位复制为 8 位。
assign expanded_red = {s_axis_tdata[15:11], s_axis_tdata[15:13]};

// 将 6 位绿色通道高位复制为 8 位。
assign expanded_green = {s_axis_tdata[10:5], s_axis_tdata[10:9]};

// 将 5 位蓝色通道高位复制为 8 位。
assign expanded_blue = {s_axis_tdata[4:0], s_axis_tdata[4:2]};

// 输出为空或本拍将完成握手时允许装入新像素。
assign s_axis_tready = !valid_reg || m_axis_tready;

// 输出 RGB888 数据来自稳定的弹性寄存器。
assign m_axis_tdata = data_reg;

// 输出有效标志来自稳定的弹性寄存器。
assign m_axis_tvalid = valid_reg;

// 输出帧首标志与寄存像素保持配对。
assign m_axis_tuser = user_reg;

// 输出行末标志与寄存像素保持配对。
assign m_axis_tlast = last_reg;

// 仅在输出寄存器可更新时接收像素和对应边带，反压期间保持不变。
always @(posedge clk) begin
    if (!rst_n) begin
        data_reg  <= 24'd0;
        valid_reg <= 1'b0;
        user_reg  <= 1'b0;
        last_reg  <= 1'b0;
    end else if (s_axis_tready) begin
        valid_reg <= s_axis_tvalid;
        if (s_axis_tvalid) begin
            data_reg <= {expanded_red, expanded_green, expanded_blue};
            user_reg <= s_axis_tuser;
            last_reg <= s_axis_tlast;
        end
    end
end

endmodule
