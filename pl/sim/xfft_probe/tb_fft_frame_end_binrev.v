`timescale 1ns / 1ps

/*
 * 模块: tb_fft_frame_end_binrev
 * 功能:
 *   复现一个由「真实 xfft 输出序」引出的缺陷：fft_result_receiver 用
 *     selected_last_input = selected_input && (s_bin_index == LAST_BIN)
 *   判定正半谱帧尾，而 freq_analysis_top 给的 LAST_ANALYSIS_BIN = 1024。
 *
 *   同一个工程的 xfft_0 配置是 output_ordering = bit_reversed_order，已由
 *   tb_xfft_probe 实测确认：输出流位置 p 上放的是自然频点 bitrev11(p)，
 *   tuser[10:0] 报的是自然频点号。于是流位置 1 上放的就是 bin 1024 ——
 *   帧尾标志会在**第二个**选中频点就拉高。
 *
 *   本用例按真实输出序（流位置 0..2047，bin = bitrev11(p)）喂 fft_result_receiver，
 *   统计：
 *     - 一帧里到底输出了多少个选中频点（正确应为 1025 个）
 *     - m_bin_last 在第几个选中频点上拉高（正确应只在最后一个）
 *
 *   EXPECT_DEFECT = 1 表示「当前 RTL 有这个缺陷」，此时用例以 DEFECT-CONFIRMED
 *   通过，保证全量回归仍可运行。**修好 RTL 之后必须把它改成 0**，届时本用例就变成
 *   正式的回归用例（缺陷消失 -> 断言成立 -> PASS）。
 */

module tb_fft_frame_end_binrev;

    localparam integer CLK_PERIOD     = 10;
    localparam integer WATCHDOG_NS    = 2000000;
    localparam integer N_BINS         = 2048;   // xfft 一帧输出 2048 个频点
    localparam integer FIRST_BIN      = 0;
    localparam integer LAST_BIN       = 1024;   // freq_analysis_top 的 LAST_ANALYSIS_BIN
    localparam integer EXPECT_SELECTED = LAST_BIN - FIRST_BIN + 1;  // 1025
    localparam integer EXPECT_DEFECT  = 1;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg enable = 1'b1;
    reg s_fft_valid = 1'b0;
    reg s_fft_last = 1'b0;
    reg [10:0] s_bin_index = 11'd0;
    reg signed [15:0] s_u_real = 16'sd0;
    reg signed [15:0] s_u_imag = 16'sd0;
    reg signed [15:0] s_i_real = 16'sd0;
    reg signed [15:0] s_i_imag = 16'sd0;
    reg m_bin_ready = 1'b1;

    wire s_fft_ready;
    wire m_bin_valid;
    wire m_bin_last;
    wire [10:0] m_bin_index;
    wire signed [15:0] m_u_real;
    wire signed [15:0] m_u_imag;
    wire signed [15:0] m_i_real;
    wire signed [15:0] m_i_imag;
    wire raw_frame_active;
    wire raw_frame_done;
    wire selected_frame_done;
    wire [11:0] raw_bin_count;
    wire [11:0] selected_bin_count;
    wire [11:0] last_frame_raw_bin_count;
    wire [11:0] last_frame_selected_bin_count;
    wire [15:0] frame_count;

    integer errors = 0;
    integer i;
    integer p;
    integer cur_pos = 0;        // 当前输出流位置（0..2047）
    integer sel_count    = 0;   // 收到的选中频点数
    integer last_at_sel  = -1;  // m_bin_last 拉高时是第几个选中频点（1 基）
    integer last_at_bin  = -1;  // m_bin_last 拉高时那一项的 bin（应该是 1024）
    integer last_pulses  = 0;   // m_bin_last 拉高总次数
    reg     ok;

    always #(CLK_PERIOD / 2) clk = ~clk;

    // 流位置 -> 自然频点：11 位位反转
    function [10:0] bitrev11;
        input [10:0] v;
        integer b;
        begin
            bitrev11 = 11'd0;
            for (b = 0; b < 11; b = b + 1)
                bitrev11[b] = v[10-b];
        end
    endfunction

    fft_result_receiver #(
        .FIRST_BIN(FIRST_BIN[10:0]),
        .LAST_BIN (LAST_BIN[10:0])
    ) dut (
        .clk                           (clk),
        .rst_n                         (rst_n),
        .enable                        (enable),
        .s_fft_valid                   (s_fft_valid),
        .s_fft_ready                   (s_fft_ready),
        .s_fft_last                    (s_fft_last),
        .s_bin_index                   (s_bin_index),
        .s_u_real                      (s_u_real),
        .s_u_imag                      (s_u_imag),
        .s_i_real                      (s_i_real),
        .s_i_imag                      (s_i_imag),
        .m_bin_ready                   (m_bin_ready),
        .m_bin_valid                   (m_bin_valid),
        .m_bin_last                    (m_bin_last),
        .m_bin_index                   (m_bin_index),
        .m_u_real                      (m_u_real),
        .m_u_imag                      (m_u_imag),
        .m_i_real                      (m_i_real),
        .m_i_imag                      (m_i_imag),
        .raw_frame_active              (raw_frame_active),
        .raw_frame_done                (raw_frame_done),
        .selected_frame_done           (selected_frame_done),
        .raw_bin_count                 (raw_bin_count),
        .selected_bin_count            (selected_bin_count),
        .last_frame_raw_bin_count      (last_frame_raw_bin_count),
        .last_frame_selected_bin_count (last_frame_selected_bin_count),
        .frame_count                   (frame_count)
    );

    // 消费侧：ready 常高，来一个收一个；记录帧尾标志出现的位置
    always @(posedge clk) begin
        if (rst_n && m_bin_valid && m_bin_ready) begin
            sel_count = sel_count + 1;
            if (m_bin_last) begin
                last_pulses = last_pulses + 1;
                if (last_at_sel < 0) begin
                    last_at_sel = sel_count;
                    last_at_bin = m_bin_index;
                end
            end
        end
    end

    // 按真实输出序喂一帧：流位置 cur_pos 上放 bin = bitrev11(cur_pos)
    always @(posedge clk) begin
        if (rst_n && s_fft_valid && s_fft_ready) begin
            if (cur_pos == N_BINS - 1)
                s_fft_valid <= 1'b0;
            cur_pos <= cur_pos + 1;
        end
    end

    always @(*) begin
        s_bin_index = bitrev11(cur_pos[10:0]);
        s_u_real    = 16'sd100;
        s_u_imag    = 16'sd0;
        s_i_real    = 16'sd100;
        s_i_imag    = 16'sd0;
        s_fft_last  = (cur_pos == N_BINS - 1);
    end

    initial begin
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        cur_pos     = 0;
        s_fft_valid = 1'b1;

        ok = 1'b0;
        for (i = 0; i < 200000 && !ok; i = i + 1) begin
            @(posedge clk);
            if (cur_pos >= N_BINS && selected_bin_count == 0) ok = 1'b1;
        end
        repeat (20) @(posedge clk);

        $display("");
        $display("========== 位反转输出序下的帧尾判定 ==========");
        $display("喂入频点数（一帧）      = %0d", N_BINS);
        $display("应选中的正半谱频点数    = %0d（bin %0d..%0d）", EXPECT_SELECTED, FIRST_BIN, LAST_BIN);
        $display("实际输出的选中频点数    = %0d", sel_count);
        $display("m_bin_last 拉高次数     = %0d", last_pulses);
        $display("首次拉高时是第几个频点  = %0d", last_at_sel);
        $display("首次拉高时那一项的 bin = %0d（若机制如分析，应等于 LAST_BIN=%0d）",
                 last_at_bin, LAST_BIN);
        $display("=============================================");

        if (last_pulses == 1 && last_at_sel == EXPECT_SELECTED && sel_count == EXPECT_SELECTED) begin
            if (EXPECT_DEFECT) begin
                $display("FAIL: 缺陷已消失（帧尾判定现在正确了）——请把 EXPECT_DEFECT 改成 0");
                errors = errors + 1;
            end
        end else begin
            if (EXPECT_DEFECT) begin
                $display("DEFECT-CONFIRMED: 帧尾标志在第 %0d 个（共 %0d 个）选中频点上就拉高了；",
                         last_at_sel, EXPECT_SELECTED);
                $display("                  下游 fft_harmonic_stats 会在 ST_CAPTURE 里提前退出，");
                $display("                  该帧剩下的 %0d 个频点不会被统计。", EXPECT_SELECTED - last_at_sel);
            end else begin
                $display("FAIL: 帧尾判定不符合预期（last 次数=%0d，位置=%0d，选中数=%0d）",
                         last_pulses, last_at_sel, sel_count);
                errors = errors + 1;
            end
        end

        if (errors == 0) begin
            $display("PASS: fft_frame_end_binrev");
        end else begin
            $display("FAIL: fft_frame_end_binrev，共 %0d 处不符", errors);
            $fatal(1, "fft_frame_end_binrev 用例未通过");
        end
        $finish;
    end

    initial begin
        #WATCHDOG_NS;
        $display("FAIL: 仿真看门狗超时");
        $fatal(1, "仿真超时");
    end

endmodule
