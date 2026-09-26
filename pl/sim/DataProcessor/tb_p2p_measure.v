`timescale 1ns / 1ps

/*
 * 模块: tb_p2p_measure
 * 功能:
 *   p2p_measure 的单元测试平台：在一个采样窗口内统计输入码值的最大/最小值，
 *   输出峰峰值码差。
 *
 *   重要前提：本模块用无符号比较求最大/最小，因此要求输入是**单调**的码值。
 *   实际数据通路满足这个前提——pqm_pl_core 把 AD7606 的二进制补码经
 *   `AD_DATA_x ^ 16'h8000` 转成偏移二进制后才送进测量核心。本平台按偏移二进制
 *   喂数（0x8000 为零点）。
 *
 *   四个场景：
 *     1) 8 点窗口，中间插入无效周期，检查峰峰值与 done/valid 脉冲；
 *     2) 窗口长度为 1，只有单个采样，峰峰值应为 0；
 *     3) 窗口长度为 0，应只给 done、不给 valid；
 *     4) 无符号边界：窗口内出现 0x0000 与 0xFFFF，峰峰值应为 65535。
 */

module tb_p2p_measure;

    localparam integer CLK_PERIOD   = 10;      // 100 MHz
    localparam integer WATCHDOG_NS  = 1000000; // 1 ms 兜底
    localparam integer N_WIDTH      = 12;      // MAX_FRAME_SAMPLES=4096 时的 N_WIDTH

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg start = 1'b0;
    reg [N_WIDTH-1:0] sample_count_n = {N_WIDTH{1'b0}};
    reg sample_valid = 1'b0;
    reg [15:0] sample_code = 16'h0000;

    wire               busy;
    wire               done;
    wire signed [31:0] p2p_raw;
    wire               p2p_valid;

    integer errors = 0;
    integer i;
    integer waited;
    reg     valid_at_done;

    // 一帧内看到的 done / valid 次数，用来确认是"单拍脉冲"而不是一直拉高
    integer done_pulses;
    integer valid_pulses;

    always #(CLK_PERIOD / 2) clk = ~clk;

    p2p_measure dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .sample_count_n(sample_count_n),
        .sample_valid(sample_valid),
        .sample_code(sample_code),
        .busy(busy),
        .done(done),
        .p2p_raw(p2p_raw),
        .p2p_valid(p2p_valid)
    );

    // 统计脉冲个数：done 与 p2p_valid 都应当只拉高 1 拍
    always @(posedge clk) begin
        if (!rst_n) begin
            done_pulses  <= 0;
            valid_pulses <= 0;
        end else begin
            if (done)      done_pulses  <= done_pulses + 1;
            if (p2p_valid) valid_pulses <= valid_pulses + 1;
        end
    end

    // 在时钟低电平期间改变激励，避免与 posedge 采样撞在同一个时间步里
    task issue_start;
        input [N_WIDTH-1:0] count;
        begin
            @(negedge clk);
            sample_count_n = count;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
        end
    endtask

    task send_sample;
        input [15:0] code;
        begin
            @(negedge clk);
            sample_code  = code;
            sample_valid = 1'b1;
            @(negedge clk);
            sample_valid = 1'b0;
        end
    endtask

    task send_gap;
        begin
            @(negedge clk);
            sample_valid = 1'b0;
            @(negedge clk);
            sample_valid = 1'b0;
        end
    endtask

    task wait_done;
        input integer max_cycles;
        output integer cycles;
        reg seen;
        begin
            seen = 1'b0;
            cycles = 0;
            valid_at_done = 1'b0;
            for (i = 0; i < max_cycles && !seen; i = i + 1) begin
                @(posedge clk);
                cycles = cycles + 1;
                if (done) begin
                    seen = 1'b1;
                    valid_at_done = p2p_valid;
                end
            end
            if (!seen) cycles = -1;
        end
    endtask

    task check_raw;
        input [31:0] expected;
        input [127:0] tag;
        begin
            if (p2p_raw !== expected) begin
                $display("FAIL: %0s 的 p2p_raw=%0d，期望 %0d", tag, p2p_raw, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        if (busy !== 1'b0 || p2p_valid !== 1'b0) begin
            $display("FAIL: 复位后 busy=%b p2p_valid=%b，期望都为 0", busy, p2p_valid);
            errors = errors + 1;
        end

        // ---------------- 场景 1：8 点窗口（中间插入无效周期） ----------------
        issue_start(12'd8);

        // 启动后应当进入忙状态
        repeat (3) @(posedge clk);
        if (busy !== 1'b1) begin
            $display("FAIL: 启动后 busy=%b，期望 1", busy);
            errors = errors + 1;
        end

        done_pulses  = 0;
        valid_pulses = 0;

        send_sample(16'h8000);
        send_gap;
        send_sample(16'h5120);   // 0x8000 - 12000，窗口最小值
        send_sample(16'hAEE0);   // 0x8000 + 12000，窗口最大值
        send_gap;
        send_gap;
        send_sample(16'h8000);
        send_sample(16'h6000);
        send_sample(16'h9000);
        send_sample(16'h8001);
        send_sample(16'h7FFF);   // 共 8 个有效采样

        wait_done(200, waited);
        // done/valid 的计数用非阻塞赋值，同一个时间步里读到的是旧值，多等几拍再判
        repeat (3) @(posedge clk);
        if (waited < 0) begin
            $display("FAIL: 场景 1 没有等到 done");
            errors = errors + 1;
        end else begin
            if (!valid_at_done) begin
                $display("FAIL: 场景 1 的 done 与 p2p_valid 没有同拍给出");
                errors = errors + 1;
            end
            // 0xAEE0 - 0x5120 = 24000
            check_raw(32'd24000, "场景1");
            if (done_pulses !== 1 || valid_pulses !== 1) begin
                $display("FAIL: 场景 1 done/valid 脉冲次数=%0d/%0d，期望各 1 次",
                         done_pulses, valid_pulses);
                errors = errors + 1;
            end
            if (busy !== 1'b0) begin
                $display("FAIL: 场景 1 结束后 busy 仍为 1");
                errors = errors + 1;
            end
        end
        repeat (10) @(posedge clk);

        // ---------------- 场景 2：窗口长度为 1 ----------------
        issue_start(12'd1);
        send_sample(16'h8ABC);
        wait_done(200, waited);
        if (waited < 0) begin
            $display("FAIL: 场景 2 没有等到 done");
            errors = errors + 1;
        end else begin
            if (!valid_at_done) begin
                $display("FAIL: 场景 2 应当给出 p2p_valid");
                errors = errors + 1;
            end
            check_raw(32'd0, "场景2");
        end
        repeat (10) @(posedge clk);

        // ---------------- 场景 3：窗口长度为 0 ----------------
        issue_start(12'd0);
        wait_done(200, waited);
        if (waited < 0) begin
            $display("FAIL: 场景 3 没有等到 done");
            errors = errors + 1;
        end else begin
            if (valid_at_done) begin
                $display("FAIL: 场景 3 窗口长度为 0，不应给出 p2p_valid");
                errors = errors + 1;
            end
        end
        repeat (10) @(posedge clk);

        // ---------------- 场景 4：无符号边界 ----------------
        issue_start(12'd2);
        send_sample(16'hFFFF);   // 下界（最大）
        send_sample(16'h0000);   // 上界（最小）
        wait_done(200, waited);
        if (waited < 0) begin
            $display("FAIL: 场景 4 没有等到 done");
            errors = errors + 1;
        end else begin
            check_raw(32'd65535, "场景4");
        end

        if (errors == 0) begin
            $display("PASS: p2p_measure");
        end else begin
            $display("FAIL: p2p_measure，共 %0d 处不符", errors);
            $fatal(1, "p2p_measure 用例未通过");
        end
        $finish;
    end

    initial begin
        #WATCHDOG_NS;
        $display("FAIL: 仿真看门狗超时");
        $fatal(1, "仿真超时");
    end

endmodule
