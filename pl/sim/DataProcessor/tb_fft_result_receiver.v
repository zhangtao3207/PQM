`timescale 1ns / 1ps

/*
 * 模块: tb_fft_result_receiver
 * 功能:
 *   fft_result_receiver 的单元测试平台：从一整帧原始 FFT 结果里筛出后续频域分析要用的
 *   正半谱频点，并统计每帧的原始/筛选频点数。
 *
 *   用例参数取 FIRST_BIN=3、LAST_BIN=7，原始帧给 0~11 共 12 个频点，
 *   于是应筛出 3、4、5、6、7 共 5 个频点，只有 bin7 带 m_bin_last。
 *
 *   三个场景：
 *     1) 一帧完整握手：筛选结果、频点索引、数据、帧尾标志、计数器与单周期脉冲全查
 *     2) enable=0：继续接收但不筛选，选中频点数为 0、不产生 m_bin_valid，帧计数照常递增
 *     3) 第二帧（enable 恢复）应能正常跑完，帧计数继续递增
 *
 *   下游 m_bin_ready 每收一项就空一拍，故意制造反压，顺带检查输出寄存器满载时
 *   选中的输入频点是否被正确反压（否则会丢掉未读走的频点）。
 */

module tb_fft_result_receiver;

    localparam integer CLK_PERIOD  = 10;       // 100 MHz
    localparam integer WATCHDOG_NS = 2000000;  // 2 ms 兜底
    localparam integer RAW_BINS    = 12;       // 原始帧频点数：bin 0~11
    localparam integer FIRST_BIN   = 3;
    localparam integer LAST_BIN    = 7;
    localparam integer SEL_BINS    = LAST_BIN - FIRST_BIN + 1; // 5

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
    reg m_bin_ready = 1'b0;

    wire               s_fft_ready;
    wire               m_bin_valid;
    wire               m_bin_last;
    wire [10:0]        m_bin_index;
    wire signed [15:0] m_u_real;
    wire signed [15:0] m_u_imag;
    wire signed [15:0] m_i_real;
    wire signed [15:0] m_i_imag;
    wire               raw_frame_active;
    wire               raw_frame_done;
    wire               selected_frame_done;
    wire [11:0]        raw_bin_count;
    wire [11:0]        selected_bin_count;
    wire [11:0]        last_frame_raw_bin_count;
    wire [11:0]        last_frame_selected_bin_count;
    wire [15:0]        frame_count;

    integer errors = 0;
    integer i;
    integer b;
    integer k;
    integer target;
    integer input_fires = 0;
    integer raw_done_pulses = 0;
    integer sel_done_pulses = 0;
    reg     ok;

    always #(CLK_PERIOD / 2) clk = ~clk;

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

    // 记录输入握手次数，供驱动任务按"握手后再换频点"推进。
    always @(posedge clk) begin
        if (rst_n && s_fft_valid && s_fft_ready)
            input_fires <= input_fires + 1;
    end

    always @(posedge clk) begin
        if (rst_n && raw_frame_done)
            raw_done_pulses <= raw_done_pulses + 1;
        if (rst_n && selected_frame_done)
            sel_done_pulses <= sel_done_pulses + 1;
    end

    // 背压检查：输出寄存器里还有没被取走的频点、下游又不取时，
    // 选中的输入频点必须被反压，否则未读走的频点会被覆盖。
    always begin
        @(negedge clk);
        #1;
        if (rst_n && enable && m_bin_valid && !m_bin_ready && s_fft_valid &&
            (s_bin_index >= FIRST_BIN) && (s_bin_index <= LAST_BIN)) begin
            if (!s_fft_ready) begin
                // 正确反压，无事发生
            end else begin
                $display("FAIL: 输出寄存器满载且下游未取走时，选中的输入频点仍在被接收（s_fft_ready 应为 0）");
                errors = errors + 1;
            end
        end
    end

    // 频点数据按索引线性编码，便于对照检查。
    task drive_raw_frame;
        begin
            for (b = 0; b < RAW_BINS; b = b + 1) begin
                @(negedge clk);
                s_bin_index = b;
                s_u_real    = b * 10;
                s_u_imag    = b * 10 + 1;
                s_i_real    = b * 10 + 2;
                s_i_imag    = b * 10 + 3;
                s_fft_last  = (b == RAW_BINS - 1);
                s_fft_valid = 1'b1;
                target      = input_fires + 1;
                wait (input_fires == target);
            end

            @(negedge clk);
            s_fft_valid = 1'b0;
            s_fft_last  = 1'b0;
        end
    endtask

    // 逐项取走筛选结果并比对
    task consume_selected;
        input [127:0] tag;
        begin
            for (k = 0; k < SEL_BINS; k = k + 1) begin
                ok = 1'b0;
                for (i = 0; i < 200 && !ok; i = i + 1) begin
                    @(negedge clk);
                    if (m_bin_valid) ok = 1'b1;
                end

                if (!ok) begin
                    $display("FAIL: %0s 第 %0d 个正半谱频点没有等到 m_bin_valid", tag, k);
                    errors = errors + 1;
                end else begin
                    if (m_bin_index !== (FIRST_BIN + k)) begin
                        $display("FAIL: %0s 第 %0d 项 bin_index=%0d，期望 %0d",
                                 tag, k, m_bin_index, FIRST_BIN + k);
                        errors = errors + 1;
                    end
                    if (m_u_real !== (FIRST_BIN + k) * 10) begin
                        $display("FAIL: %0s bin%0d u_real=%0d，期望 %0d",
                                 tag, FIRST_BIN + k, m_u_real, (FIRST_BIN + k) * 10);
                        errors = errors + 1;
                    end
                    if (m_i_imag !== (FIRST_BIN + k) * 10 + 3) begin
                        $display("FAIL: %0s bin%0d i_imag=%0d，期望 %0d",
                                 tag, FIRST_BIN + k, m_i_imag, (FIRST_BIN + k) * 10 + 3);
                        errors = errors + 1;
                    end
                    if (m_bin_last !== ((k == SEL_BINS - 1) ? 1'b1 : 1'b0)) begin
                        $display("FAIL: %0s 第 %0d 项 m_bin_last=%0b，期望 %0b",
                                 tag, k, m_bin_last, (k == SEL_BINS - 1));
                        errors = errors + 1;
                    end
                end

                // 取走一项后空一拍 ready，制造反压
                @(negedge clk);
                m_bin_ready = 1'b1;
                @(negedge clk);
                m_bin_ready = 1'b0;
            end
        end
    endtask

    task check16;
        input [15:0] actual;
        input [15:0] expected;
        input [127:0] tag;
        begin
            if (actual !== expected) begin
                $display("FAIL: %0s = %0d，期望 %0d", tag, actual, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        repeat (10) @(posedge clk);
        rst_n = 1'b1;

        // ---------------- 场景 1：一帧完整握手 ----------------
        fork
            drive_raw_frame;
            consume_selected("第一帧");
        join

        repeat (10) @(posedge clk);
        if (frame_count !== 16'd1) begin
            $display("FAIL: 第一帧结束后 frame_count=%0d，期望 1", frame_count);
            errors = errors + 1;
        end
        check16(last_frame_raw_bin_count,      RAW_BINS, "第一帧 last_frame_raw_bin_count");
        check16(last_frame_selected_bin_count, SEL_BINS, "第一帧 last_frame_selected_bin_count");
        check16(raw_bin_count,                 12'd0,    "第一帧后 raw_bin_count");
        check16(selected_bin_count,            12'd0,    "第一帧后 selected_bin_count");
        if (raw_frame_active !== 1'b0) begin
            $display("FAIL: 第一帧结束后 raw_frame_active 应为 0");
            errors = errors + 1;
        end
        if (raw_done_pulses !== 1) begin
            $display("FAIL: raw_frame_done 脉冲次数=%0d，期望 1", raw_done_pulses);
            errors = errors + 1;
        end
        if (sel_done_pulses !== 1) begin
            $display("FAIL: selected_frame_done 脉冲次数=%0d，期望 1", sel_done_pulses);
            errors = errors + 1;
        end

        // ---------------- 场景 2：enable=0 只收不筛 ----------------
        enable = 1'b0;
        drive_raw_frame;
        repeat (10) @(posedge clk);
        if (m_bin_valid !== 1'b0) begin
            $display("FAIL: enable=0 时不应出现 m_bin_valid");
            errors = errors + 1;
        end
        if (frame_count !== 16'd2) begin
            $display("FAIL: enable=0 帧结束后 frame_count=%0d，期望 2", frame_count);
            errors = errors + 1;
        end
        check16(last_frame_raw_bin_count,      12'd12, "enable=0 帧 last_frame_raw_bin_count");
        check16(last_frame_selected_bin_count, 12'd0,  "enable=0 帧 last_frame_selected_bin_count");
        if (sel_done_pulses !== 1) begin
            $display("FAIL: enable=0 时不应再产生 selected_frame_done（当前 %0d 次）", sel_done_pulses);
            errors = errors + 1;
        end
        enable = 1'b1;
        repeat (10) @(posedge clk);

        // ---------------- 场景 3：第二帧 ----------------
        fork
            drive_raw_frame;
            consume_selected("第二帧");
        join

        repeat (10) @(posedge clk);
        if (frame_count !== 16'd3) begin
            $display("FAIL: 第二帧结束后 frame_count=%0d，期望 3", frame_count);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PASS: fft_result_receiver");
        end else begin
            $display("FAIL: fft_result_receiver，共 %0d 处不符", errors);
            $fatal(1, "fft_result_receiver 用例未通过");
        end
        $finish;
    end

    initial begin
        #WATCHDOG_NS;
        $display("FAIL: 仿真看门狗超时");
        $fatal(1, "仿真超时");
    end

endmodule
