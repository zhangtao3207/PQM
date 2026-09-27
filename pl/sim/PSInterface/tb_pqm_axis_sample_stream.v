`timescale 1ns / 1ps

/*
 * 模块名称：tb_pqm_axis_sample_stream
 * 功能说明：验证样本流在 DMA 反压期间丢弃新样本，并保持帧长度和源序号可追踪。
 * 输入端口：无。
 * 输出端口：无。
 * 双向端口：无。
 */
module tb_pqm_axis_sample_stream;

reg         clk;
reg         rst_n;
reg         sample_valid;
reg  [15:0] u1_sample;
reg  [15:0] u2_sample;
wire [31:0] source_sequence;
wire [31:0] drop_count;
wire [63:0] m_axis_tdata;
wire        m_axis_tvalid;
reg         m_axis_tready;
wire        m_axis_tlast;

integer source_index;
integer accepted_count;
integer tlast_count;
reg [31:0] last_sequence;
reg [31:0] previous_sequence;
reg        have_previous;
reg        gap_observed;

// 生成 100 MHz 仿真时钟。
always #5 clk = ~clk;

// 统计 AXI 握手、帧尾和接收序号断点。
always @(posedge clk) begin
    if (!rst_n) begin
        accepted_count  <= 0;
        tlast_count     <= 0;
        last_sequence   <= 32'd0;
        previous_sequence <= 32'd0;
        have_previous   <= 1'b0;
        gap_observed    <= 1'b0;
    end else if (m_axis_tvalid && m_axis_tready) begin
        accepted_count <= accepted_count + 1;
        last_sequence  <= m_axis_tdata[63:32];
        if (m_axis_tlast) begin
            tlast_count <= tlast_count + 1;
        end
        if (have_previous && (m_axis_tdata[63:32] != (previous_sequence + 1'b1))) begin
            gap_observed <= 1'b1;
        end
        previous_sequence <= m_axis_tdata[63:32];
        have_previous <= 1'b1;
    end
end

// 被测模块：将U1、U2和源序号打包为 64 位 AXI4-Stream。
pqm_axis_sample_stream #(
    .FRAME_SAMPLES (2048)
) u_dut (
    .clk             (clk),
    .rst_n           (rst_n),
    .sample_valid    (sample_valid),
    .u1_sample        (u1_sample),
    .u2_sample        (u2_sample),
    .source_sequence (source_sequence),
    .drop_count      (drop_count),
    .m_axis_tdata    (m_axis_tdata),
    .m_axis_tvalid   (m_axis_tvalid),
    .m_axis_tready   (m_axis_tready),
    .m_axis_tlast    (m_axis_tlast)
);

// 主测试流程：连续发送样本，并在序号 1000 至 1003 期间施加反压。
initial begin
    clk            = 1'b0;
    rst_n          = 1'b0;
    sample_valid   = 1'b0;
    u1_sample       = 16'd0;
    u2_sample       = 16'd0;
    m_axis_tready  = 1'b1;
    source_index   = 0;
    accepted_count = 0;
    tlast_count    = 0;
    last_sequence  = 32'd0;
    previous_sequence = 32'd0;
    have_previous  = 1'b0;
    gap_observed   = 1'b0;

    repeat (4) @(negedge clk);
    rst_n = 1'b1;

    for (source_index = 0; source_index < 2052; source_index = source_index + 1) begin
        @(negedge clk);
        sample_valid  = 1'b1;
        u1_sample      = source_index[15:0];
        u2_sample      = source_index[15:0] ^ 16'h5A5A;
        m_axis_tready = !((source_index >= 1000) && (source_index < 1004));
    end

    @(negedge clk);
    sample_valid  = 1'b0;
    m_axis_tready = 1'b1;
    repeat (3) @(posedge clk);

    if (accepted_count != 2048) $fatal(1, "accepted frame length mismatch");
    if (tlast_count != 1) $fatal(1, "TLAST count mismatch");
    if (drop_count != 4) $fatal(1, "drop counter mismatch");
    if (last_sequence != 32'd2051) $fatal(1, "source sequence did not advance");
    if (!gap_observed) $fatal(1, "accepted stream did not expose sequence gap");

    $display("PASS: pqm_axis_sample_stream");
    $finish;
end

endmodule
