`timescale 1ns / 1ps

/*
 * 模块名称：tb_pqm_axis_rgb565_to_rgb888
 * 功能说明：验证 RGB565 扩展结果和随机反压下的 AXI 像素及边带稳定性。
 * 输入端口：无。
 * 输出端口：无。
 * 双向端口：无。
 */
module tb_pqm_axis_rgb565_to_rgb888;

reg         clk;
reg         rst_n;
reg  [15:0] s_axis_tdata;
reg         s_axis_tvalid;
wire        s_axis_tready;
reg         s_axis_tuser;
reg         s_axis_tlast;
wire [23:0] m_axis_tdata;
wire        m_axis_tvalid;
reg         m_axis_tready;
wire        m_axis_tuser;
wire        m_axis_tlast;

reg [23:0] expected_data [0:63];
reg        expected_user [0:63];
reg        expected_last [0:63];
integer send_count;
integer receive_count;
integer random_index;
reg [15:0] random_pixel;
reg  [7:0] ready_lfsr;
reg        stall_active;
reg [23:0] stalled_data;
reg        stalled_user;
reg        stalled_last;

// 将测试输入按与 DUT 相同的位复制规则换算为期望 RGB888。
function [23:0] expand_rgb565;
    input [15:0] rgb565;
    begin
        expand_rgb565 = {
            rgb565[15:11], rgb565[15:13],
            rgb565[10:5],  rgb565[10:9],
            rgb565[4:0],   rgb565[4:2]
        };
    end
endfunction

// 生成 100 MHz 仿真时钟。
always #5 clk = ~clk;

// 使用确定性 LFSR 产生输出端随机反压。
always @(posedge clk) begin
    if (!rst_n) begin
        ready_lfsr   <= 8'hA7;
        m_axis_tready <= 1'b0;
    end else begin
        ready_lfsr <= {ready_lfsr[6:0], ready_lfsr[7] ^ ready_lfsr[5] ^ ready_lfsr[4] ^ ready_lfsr[3]};
        m_axis_tready <= ready_lfsr[0] | ready_lfsr[3];
    end
end

// 校验每个已接收像素，并检查反压期间输出和边带保持稳定。
always @(posedge clk) begin
    if (!rst_n) begin
        receive_count <= 0;
        stall_active  <= 1'b0;
        stalled_data  <= 24'd0;
        stalled_user  <= 1'b0;
        stalled_last  <= 1'b0;
    end else begin
        if (m_axis_tvalid && !m_axis_tready) begin
            if (stall_active) begin
                if (m_axis_tdata != stalled_data) $fatal(1, "pixel changed while stalled");
                if (m_axis_tuser != stalled_user) $fatal(1, "TUSER changed while stalled");
                if (m_axis_tlast != stalled_last) $fatal(1, "TLAST changed while stalled");
            end else begin
                stalled_data <= m_axis_tdata;
                stalled_user <= m_axis_tuser;
                stalled_last <= m_axis_tlast;
                stall_active <= 1'b1;
            end
        end else begin
            stall_active <= 1'b0;
        end

        if (m_axis_tvalid && m_axis_tready) begin
            if (m_axis_tdata != expected_data[receive_count]) $fatal(1, "RGB expansion mismatch");
            if (m_axis_tuser != expected_user[receive_count]) $fatal(1, "TUSER mismatch");
            if (m_axis_tlast != expected_last[receive_count]) $fatal(1, "TLAST mismatch");
            receive_count <= receive_count + 1;
        end
    end
end

// 发送一个像素并保持输入，直到 DUT 完成 AXI 握手。
task send_pixel;
    input [15:0] pixel;
    input        user_flag;
    input        last_flag;
    begin
        expected_data[send_count] = expand_rgb565(pixel);
        expected_user[send_count] = user_flag;
        expected_last[send_count] = last_flag;
        @(negedge clk);
        s_axis_tdata  = pixel;
        s_axis_tuser  = user_flag;
        s_axis_tlast  = last_flag;
        s_axis_tvalid = 1'b1;
        while (!s_axis_tready) @(negedge clk);
        @(negedge clk);
        s_axis_tvalid = 1'b0;
        send_count = send_count + 1;
    end
endtask

// 被测模块：在保持 AXI 边带的同时把 RGB565 扩展为 RGB888。
pqm_axis_rgb565_to_rgb888 u_dut (
    .clk           (clk),
    .rst_n         (rst_n),
    .s_axis_tdata  (s_axis_tdata),
    .s_axis_tvalid (s_axis_tvalid),
    .s_axis_tready (s_axis_tready),
    .s_axis_tuser  (s_axis_tuser),
    .s_axis_tlast  (s_axis_tlast),
    .m_axis_tdata  (m_axis_tdata),
    .m_axis_tvalid (m_axis_tvalid),
    .m_axis_tready (m_axis_tready),
    .m_axis_tuser  (m_axis_tuser),
    .m_axis_tlast  (m_axis_tlast)
);

// 主测试流程：发送基准颜色和多组像素，等待全部随机停顿完成。
initial begin
    clk           = 1'b0;
    rst_n         = 1'b0;
    s_axis_tdata  = 16'd0;
    s_axis_tvalid = 1'b0;
    s_axis_tuser  = 1'b0;
    s_axis_tlast  = 1'b0;
    m_axis_tready = 1'b0;
    send_count    = 0;
    receive_count = 0;
    random_pixel  = 16'h1357;
    ready_lfsr    = 8'hA7;
    stall_active  = 1'b0;
    stalled_data  = 24'd0;
    stalled_user  = 1'b0;
    stalled_last  = 1'b0;

    repeat (4) @(negedge clk);
    rst_n = 1'b1;

    send_pixel(16'h0000, 1'b1, 1'b0);
    send_pixel(16'hFFFF, 1'b0, 1'b0);
    send_pixel(16'hF800, 1'b0, 1'b0);
    send_pixel(16'h07E0, 1'b0, 1'b0);
    send_pixel(16'h001F, 1'b0, 1'b0);
    send_pixel(16'h7BEF, 1'b0, 1'b1);

    for (random_index = 0; random_index < 32; random_index = random_index + 1) begin
        random_pixel = random_pixel + 16'h1F23;
        send_pixel(random_pixel, (random_index == 0), (random_index == 31));
    end

    wait (receive_count == send_count);
    repeat (4) @(posedge clk);
    if (expand_rgb565(16'h7BEF) != 24'h7B7D7B) $fatal(1, "mid-gray reference mismatch");
    $display("PASS: pqm_axis_rgb565_to_rgb888");
    $finish;
end

endmodule
