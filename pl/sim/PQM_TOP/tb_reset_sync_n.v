`timescale 1ns / 1ps

/*
 * 模块: tb_reset_sync_n
 * 功能:
 *   验证低有效复位同步器 reset_sync_n 的两条时序契约：
 *   1) 异步置位：async_reset_n 拉低后 reset_n_out 立刻为 0，**不需要任何时钟沿**
 *      （用一个"可以停住的时钟"把这条证明干净：时钟停住时置位也必须生效）。
 *   2) 同步释放：async_reset_n 拉高后，reset_n_out 仍保持 0 **两个时钟沿**，
 *      第 2 个时钟沿之后才变 1；且释放相位无关（扫描 4 个不同的释放相位）。
 *   另外做两件事：
 *   3) 输出永不出现 X（数值检查一律带 X 守卫）。
 *   4) 每一次"解除复位"的跳变都必须落在时钟沿上（有毛刺或异步解除都会被抓到）。
 *
 *   判据全部用 $fatal 收尾，不依赖日志扫描。
 */

module tb_reset_sync_n;

    localparam integer CLK_PERIOD = 10;
    localparam integer HALF       = CLK_PERIOD / 2;

    reg  clk           = 1'b1;
    reg  clk_run       = 1'b1;      // 0 时时钟停住，用于验证异步置位
    reg  async_reset_n = 1'b0;
    wire reset_n_out;

    integer errors      = 0;
    integer rise_errors = 0;
    integer edge_count  = 0;
    integer out_rise_count = 0;
    integer round;
    integer base;
    integer expected_rises;

    // 可控时钟：clk_run=0 时保持当前电平，不再翻转。
    always begin
        #(HALF);
        if (clk_run) clk = ~clk;
    end

    // 时钟沿计数与"上一沿时刻"，供释放时序与跳变位置检查使用。
    time last_edge_time = 0;
    always @(posedge clk) begin
        edge_count     = edge_count + 1;
        last_edge_time = $time;
    end

    // 输出解除（低->高）的监视器：既统计次数，也检查它落在时钟沿上。
    always @(posedge reset_n_out) begin
        out_rise_count = out_rise_count + 1;
        if ($time !== last_edge_time) begin
            $display("FAIL: 输出解除发生在 t=%0t，不落在任何时钟沿上（上一沿 t=%0t）",
                     $time, last_edge_time);
            rise_errors = rise_errors + 1;
        end
    end

    reset_sync_n dut (
        .clk           (clk),
        .async_reset_n (async_reset_n),
        .reset_n_out   (reset_n_out)
    );

    task check_bit;
        input         actual;
        input         expected;
        input [255:0] tag;
        begin
            if (actual === 1'bx) begin
                $display("FAIL: %0s = X（未初始化/未驱动）", tag);
                errors = errors + 1;
            end else if (actual !== expected) begin
                $display("FAIL: %0s = %b，期望 %b", tag, actual, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $display("");
        $display("========== reset_sync_n（异步置位 / 同步释放） ==========");

        // ---- 1) 复位期间输出恒为 0 ----
        repeat (3) @(posedge clk);
        #1;
        check_bit(reset_n_out, 1'b0, "复位期间输出");

        // ---- 2) 同步释放：释放后必须再等 2 个时钟沿 ----
        base = edge_count;
        async_reset_n = 1'b1;
        #1;
        check_bit(reset_n_out, 1'b0, "释放后未过时钟沿");
        @(posedge clk); #1;
        check_bit(reset_n_out, 1'b0, "释放后第 1 个时钟沿");
        @(posedge clk); #1;
        check_bit(reset_n_out, 1'b1, "释放后第 2 个时钟沿");
        if (edge_count - base !== 2) begin
            $display("FAIL: 释放到解除经过 %0d 个时钟沿，期望 2", edge_count - base);
            errors = errors + 1;
        end

        // ---- 3) 取消复位后输出保持 1（无毛刺）----
        repeat (5) @(posedge clk);
        #1;
        check_bit(reset_n_out, 1'b1, "取消复位后输出应保持 1");

        // ---- 4) 异步置位：时钟停住时也必须立刻生效 ----
        @(posedge clk);
        #2;
        clk_run = 1'b0;                  // 停时钟，此后没有任何时钟沿
        #(CLK_PERIOD);
        check_bit(reset_n_out, 1'b1, "停时钟后输出应仍为 1");
        async_reset_n = 1'b0;            // 停时钟时置位
        #1;
        check_bit(reset_n_out, 1'b0, "停时钟时置位（异步置位）");
        async_reset_n = 1'b1;            // 停时钟时释放
        #(4 * CLK_PERIOD);
        check_bit(reset_n_out, 1'b0, "停时钟时释放不应立刻解除（同步释放）");
        clk_run = 1'b1;

        // ---- 5) 恢复时钟后，释放仍需 2 个时钟沿 ----
        @(posedge clk); #1;
        check_bit(reset_n_out, 1'b0, "恢复时钟后第 1 个沿");
        @(posedge clk); #1;
        check_bit(reset_n_out, 1'b1, "恢复时钟后第 2 个沿");

        // ---- 6) 释放相位无关性：4 个不同相位释放，都恰好隔 2 个时钟沿 ----
        expected_rises = 2;              // 上面第 2 段 1 次 + 第 4/5 段 1 次
        for (round = 0; round < 4; round = round + 1) begin
            async_reset_n = 1'b0;
            repeat (3) @(posedge clk);
            #(round + 1);
            check_bit(reset_n_out, 1'b0, "相位扫描：复位期间输出");
            base = edge_count;
            async_reset_n = 1'b1;
            wait (reset_n_out === 1'b1);
            #1;
            if (edge_count - base !== 2) begin
                $display("FAIL: 相位扫描第 %0d 轮：释放到解除经过 %0d 个时钟沿，期望 2",
                         round, edge_count - base);
                errors = errors + 1;
            end
            expected_rises = expected_rises + 1;
        end

        // ---- 7) 解除次数必须与预期一致（多出来的就是毛刺）----
        if (out_rise_count !== expected_rises) begin
            $display("FAIL: 输出解除次数 = %0d，期望 %0d（多出来的是毛刺）",
                     out_rise_count, expected_rises);
            errors = errors + 1;
        end

        errors = errors + rise_errors;

        if (errors == 0) begin
            $display("解除复位次数 = %0d，时钟沿总数 = %0d", out_rise_count, edge_count);
            $display("");
            $display("PASS: reset_sync_n");
        end else begin
            $display("FAIL: reset_sync_n，共 %0d 处不符", errors);
            $fatal(1, "reset_sync_n 用例未通过");
        end
        $finish;
    end

    initial begin
        #2000000;
        $display("FAIL: 仿真看门狗超时");
        $fatal(1, "仿真超时");
    end

endmodule
