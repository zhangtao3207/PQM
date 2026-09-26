`timescale 1ns / 1ps

/*
 * 模块: tb_frequency_measure
 * 功能:
 *   frequency_measure 的单元测试平台：在采样窗口内检测电压正向峰值，
 *   输出相邻两次峰值之间的时钟计数。
 *
 *   计数约定：sample_clk_cnt 在进入采集后每拍加一，第 k 个采样时可见值为 k-1；
 *   峰值候选锁存的是当时的计数值，所以两次峰值所在的采样序号之差就是输出周期。
 *   实测：峰值落在第 5 与第 13 个采样时，freq_period_raw = 12 - 4 = 8。
 *
 *   峰值门限：进入门限 code_high = ref + 512；确认回落门限 = 候选峰值 - 512。
 *   检测前需要先采到 <= ref 才算"武装"（启动时强制武装一次）。
 *
 *   四个场景（每拍一个有效采样，窗口 16 拍）：
 *     1) 峰值在第 5、13 拍                -> freq_period_raw=8, freq_valid=1
 *     2) 窗口内只有一次峰值                -> 只给 done，不给 valid
 *     3) 零点参考无效 -> 退回中心码 0x8000  -> 同场景 1
 *     4) 码值始终够不到进入门限            -> 只给 done，不给 valid
 */

module tb_frequency_measure;

    localparam integer CLK_PERIOD  = 10;      // 100 MHz
    localparam integer WATCHDOG_NS = 2000000; // 2 ms 兜底
    localparam integer N_WIDTH     = 12;      // MAX_FRAME_SAMPLES=4096 时的 N_WIDTH

    localparam [15:0] REF_CODE  = 16'h8000;
    localparam [15:0] LOW_CODE  = 16'h7000;   // 低于 ref，用于武装
    localparam [15:0] STEP_CODE = 16'h8300;   // 高于 ref+512，启动峰值跟踪
    localparam [15:0] PEAK_CODE = 16'h9000;   // 峰值
    localparam [15:0] DROP_CODE = 16'h8E00;   // 等于 峰值-512，确认峰值

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg start = 1'b0;
    reg [N_WIDTH-1:0] sample_count_n = {N_WIDTH{1'b0}};
    reg sample_valid = 1'b0;
    reg [15:0] sample_code = REF_CODE;
    reg [15:0] zero_code = REF_CODE;
    reg zero_valid = 1'b1;

    wire               busy;
    wire               done;
    wire signed [31:0] freq_period_raw;
    wire               freq_valid;

    integer errors = 0;

    // done / freq_valid 都只有一拍，必须在脉冲当拍抓
    integer    done_count;
    integer    valid_count;
    reg signed [31:0] period_at_done;

    always #(CLK_PERIOD / 2) clk = ~clk;

    frequency_measure dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .sample_count_n(sample_count_n),
        .sample_valid(sample_valid),
        .sample_code(sample_code),
        .zero_code(zero_code),
        .zero_valid(zero_valid),
        .busy(busy),
        .done(done),
        .freq_period_raw(freq_period_raw),
        .freq_valid(freq_valid)
    );

    always @(posedge clk) begin
        if (rst_n && done) begin
            done_count     <= done_count + 1;
            period_at_done <= freq_period_raw;
            if (freq_valid)
                valid_count <= valid_count + 1;
        end
    end

    // 在时钟低电平期间改变激励，避免与 posedge 采样撞在同一个时间步里
    task issue_start;
        input [N_WIDTH-1:0] count;
        begin
            @(negedge clk);
            done_count     = 0;
            valid_count    = 0;
            period_at_done = 32'sd0;
            sample_count_n = count;
            start          = 1'b1;
            sample_valid   = 1'b0;
            @(negedge clk);
            start          = 1'b0;
        end
    endtask

    task send;
        input [15:0] code;
        begin
            @(negedge clk);
            sample_code  = code;
            sample_valid = 1'b1;
        end
    endtask

    task end_window;
        begin
            @(negedge clk);
            sample_valid = 1'b0;
        end
    endtask

    task settle;
        begin
            repeat (10) @(posedge clk);
        end
    endtask

    task check_value;
        input signed [31:0] actual;
        input signed [31:0] expected;
        input [127:0] tag;
        begin
            if (actual !== expected) begin
                $display("FAIL: %0s = %0d，期望 %0d", tag, actual, expected);
                errors = errors + 1;
            end
        end
    endtask

    // 峰值在第 5、13 拍，第 6、14 拍确认回落
    task run_two_peaks;
        begin
            send(LOW_CODE);    // 1
            send(LOW_CODE);    // 2
            send(LOW_CODE);    // 3
            send(STEP_CODE);   // 4  启动跟踪
            send(PEAK_CODE);   // 5  峰值候选
            send(DROP_CODE);   // 6  确认峰值（第一次）
            send(LOW_CODE);    // 7  重新武装
            send(LOW_CODE);    // 8
            send(LOW_CODE);    // 9
            send(LOW_CODE);    // 10
            send(LOW_CODE);    // 11
            send(STEP_CODE);   // 12 启动跟踪
            send(PEAK_CODE);   // 13 峰值候选
            send(DROP_CODE);   // 14 确认峰值（第二次）-> 锁存
            send(LOW_CODE);    // 15
            send(LOW_CODE);    // 16
        end
    endtask

    initial begin
        done_count  = 0;
        valid_count = 0;

        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        if (busy !== 1'b0 || done !== 1'b0) begin
            $display("FAIL: 复位后 busy/done 应为 0");
            errors = errors + 1;
        end

        // ---------------- 场景 1：两个峰值 ----------------
        issue_start(12'd16);
        repeat (3) @(posedge clk);
        if (busy !== 1'b1) begin
            $display("FAIL: 启动后 busy=%b，期望 1", busy);
            errors = errors + 1;
        end
        run_two_peaks;
        end_window;
        settle;
        if (done_count !== 1) begin
            $display("FAIL: 场景 1 的 done 脉冲次数 = %0d，期望 1", done_count);
            errors = errors + 1;
        end
        if (valid_count !== 1) begin
            $display("FAIL: 场景 1 的 freq_valid 次数 = %0d，期望 1", valid_count);
            errors = errors + 1;
        end
        check_value(period_at_done, 32'sd8, "场景1 freq_period_raw");
        settle;

        // ---------------- 场景 2：窗口内只有一次峰值 ----------------
        issue_start(12'd16);
        send(LOW_CODE);    // 1
        send(LOW_CODE);    // 2
        send(LOW_CODE);    // 3
        send(STEP_CODE);   // 4
        send(PEAK_CODE);   // 5
        send(DROP_CODE);   // 6  第一次峰值
        send(LOW_CODE);    // 7
        send(LOW_CODE);    // 8
        send(LOW_CODE);    // 9
        send(LOW_CODE);    // 10
        send(LOW_CODE);    // 11
        send(LOW_CODE);    // 12
        send(LOW_CODE);    // 13
        send(LOW_CODE);    // 14
        send(LOW_CODE);    // 15
        send(LOW_CODE);    // 16
        end_window;
        settle;
        if (done_count !== 1) begin
            $display("FAIL: 场景 2 的 done 脉冲次数 = %0d，期望 1", done_count);
            errors = errors + 1;
        end
        if (valid_count !== 0) begin
            $display("FAIL: 场景 2 只有一次峰值，不应给出 freq_valid（实际 %0d 次）", valid_count);
            errors = errors + 1;
        end
        settle;

        // ---------------- 场景 3：零点参考无效，退回中心码 ----------------
        zero_valid = 1'b0;
        issue_start(12'd16);
        run_two_peaks;
        end_window;
        settle;
        if (valid_count !== 1) begin
            $display("FAIL: 场景 3 的 freq_valid 次数 = %0d，期望 1", valid_count);
            errors = errors + 1;
        end
        check_value(period_at_done, 32'sd8, "场景3 freq_period_raw");
        zero_valid = 1'b1;
        settle;

        // ---------------- 场景 4：码值够不到进入门限 ----------------
        // 0x7F00 低于 ref+512(0x8200)，虽然启动时强制武装，但永远不会进入跟踪
        issue_start(12'd16);
        send(16'h7F00);
        send(16'h7F00);
        send(16'h7F00);
        send(16'h7F00);
        send(16'h7F00);
        send(16'h7F00);
        send(16'h7F00);
        send(16'h7F00);
        send(16'h7F00);
        send(16'h7F00);
        send(16'h7F00);
        send(16'h7F00);
        send(16'h7F00);
        send(16'h7F00);
        send(16'h7F00);
        send(16'h7F00);
        end_window;
        settle;
        if (done_count !== 1) begin
            $display("FAIL: 场景 4 的 done 脉冲次数 = %0d，期望 1", done_count);
            errors = errors + 1;
        end
        if (valid_count !== 0) begin
            $display("FAIL: 场景 4 没有峰值，不应给出 freq_valid（实际 %0d 次）", valid_count);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PASS: frequency_measure");
        end else begin
            $display("FAIL: frequency_measure，共 %0d 处不符", errors);
            $fatal(1, "frequency_measure 用例未通过");
        end
        $finish;
    end

    initial begin
        #WATCHDOG_NS;
        $display("FAIL: 仿真看门狗超时");
        $fatal(1, "仿真超时");
    end

endmodule
