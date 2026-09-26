`timescale 1ns / 1ps

/*
 * 模块: tb_power_metrics_calc
 * 功能:
 *   power_metrics_calc 的单元测试平台：由 U/I 的 RMS raw、同窗口平均有功功率 raw
 *   和时域相位 raw 算出视在功率、无功功率与功率因数。
 *
 *   激励选取：u_rms=1000、i_rms=500 时 S=500000；取 P=400000 则
 *     PF = |P|/S = 0.8，量纲 x10000 即 8000；
 *     Q  = sqrt(S^2 - P^2) = sqrt(500000^2 - 400000^2) = 300000。
 *   全是整数，可以精确手算。
 *
 *   相位只用来定 Q 的符号：phase_offset 绝对值大于半周期且小于整周期时判为负。
 *
 *   六个场景：
 *     1) 超前（offset=200/period=1000）  -> S=500000, Q=+300000, PF=+8000, P=+400000
 *     2) 滞后（offset=800/period=1000）  -> Q=-300000，其余同场景 1
 *     3) 有功为负 P=-400000             -> PF=-8000, P=-400000, Q=+300000
 *     4) PF 超过 1（P=600000 > S）       -> PF 裁到 +10000，Q=0
 *     5) S=0（i_rms=0）                 -> PF=0, Q=0, S=0
 *     6) 有效标志缺失                    -> 只给 done，不给 valid
 */

module tb_power_metrics_calc;

    localparam integer CLK_PERIOD  = 10;      // 100 MHz
    localparam integer WATCHDOG_NS = 2000000; // 2 ms 兜底

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg start = 1'b0;
    reg rms_valid = 1'b1;
    reg active_p_valid = 1'b1;
    reg signed [15:0] u_rms_code = 16'sd0;
    reg signed [15:0] i_rms_code = 16'sd0;
    reg signed [31:0] active_p_input_raw = 32'sd0;
    reg signed [31:0] phase_offset_raw = 32'sd0;
    reg signed [31:0] phase_period_raw = 32'sd1000;
    reg phase_valid = 1'b1;

    wire               busy;
    wire               done;
    wire signed [31:0] active_p_raw;
    wire signed [31:0] reactive_q_raw;
    wire signed [31:0] apparent_s_raw;
    wire signed [31:0] power_factor_raw;
    wire               power_metrics_valid;

    integer errors = 0;
    integer i;
    integer waited;
    reg valid_at_done;

    always #(CLK_PERIOD / 2) clk = ~clk;

    power_metrics_calc dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .rms_valid(rms_valid),
        .active_p_valid(active_p_valid),
        .u_rms_code(u_rms_code),
        .i_rms_code(i_rms_code),
        .active_p_input_raw(active_p_input_raw),
        .phase_offset_raw(phase_offset_raw),
        .phase_period_raw(phase_period_raw),
        .phase_valid(phase_valid),
        .busy(busy),
        .done(done),
        .active_p_raw(active_p_raw),
        .reactive_q_raw(reactive_q_raw),
        .apparent_s_raw(apparent_s_raw),
        .power_factor_raw(power_factor_raw),
        .power_metrics_valid(power_metrics_valid)
    );

    // 在时钟低电平期间改变激励，避免与 posedge 采样撞在同一个时间步里
    task issue_start;
        input signed [15:0] u_code;
        input signed [15:0] i_code;
        input signed [31:0] p_raw;
        input signed [31:0] off_raw;
        input signed [31:0] per_raw;
        input rms_v;
        input ap_v;
        input ph_v;
        begin
            @(negedge clk);
            u_rms_code          = u_code;
            i_rms_code          = i_code;
            active_p_input_raw  = p_raw;
            phase_offset_raw    = off_raw;
            phase_period_raw    = per_raw;
            rms_valid           = rms_v;
            active_p_valid      = ap_v;
            phase_valid         = ph_v;
            start               = 1'b1;
            @(negedge clk);
            start               = 1'b0;
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
                    valid_at_done = power_metrics_valid;
                end
            end
            if (!seen) cycles = -1;
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

    initial begin
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        if (busy !== 1'b0 || done !== 1'b0) begin
            $display("FAIL: 复位后 busy/done 应为 0");
            errors = errors + 1;
        end

        // ---------------- 场景 1：超前，Q 为正 ----------------
        issue_start(16'sd1000, 16'sd500, 32'sd400000, 32'sd200, 32'sd1000, 1'b1, 1'b1, 1'b1);
        repeat (3) @(posedge clk);
        if (busy !== 1'b1) begin
            $display("FAIL: 启动后 busy=%b，期望 1", busy);
            errors = errors + 1;
        end
        wait_done(4000, waited);
        repeat (3) @(posedge clk);
        if (waited < 0) begin
            $display("FAIL: 场景 1 没有等到 done");
            errors = errors + 1;
        end else begin
            if (!valid_at_done) begin
                $display("FAIL: 场景 1 done 没有与 power_metrics_valid 同拍");
                errors = errors + 1;
            end
            check_value(apparent_s_raw,   32'sd500000, "场景1 apparent_s_raw");
            check_value(active_p_raw,     32'sd400000, "场景1 active_p_raw");
            check_value(reactive_q_raw,   32'sd300000, "场景1 reactive_q_raw");
            check_value(power_factor_raw, 32'sd8000,   "场景1 power_factor_raw");
        end
        repeat (10) @(posedge clk);

        // ---------------- 场景 2：滞后，Q 为负 ----------------
        issue_start(16'sd1000, 16'sd500, 32'sd400000, 32'sd800, 32'sd1000, 1'b1, 1'b1, 1'b1);
        wait_done(4000, waited);
        repeat (3) @(posedge clk);
        if (waited < 0) begin
            $display("FAIL: 场景 2 没有等到 done");
            errors = errors + 1;
        end else begin
            check_value(apparent_s_raw,   32'sd500000,  "场景2 apparent_s_raw");
            check_value(reactive_q_raw,  -32'sd300000,  "场景2 reactive_q_raw");
            check_value(power_factor_raw, 32'sd8000,    "场景2 power_factor_raw");
        end
        repeat (10) @(posedge clk);

        // ---------------- 场景 3：有功为负 ----------------
        issue_start(16'sd1000, 16'sd500, -32'sd400000, 32'sd200, 32'sd1000, 1'b1, 1'b1, 1'b1);
        wait_done(4000, waited);
        repeat (3) @(posedge clk);
        if (waited < 0) begin
            $display("FAIL: 场景 3 没有等到 done");
            errors = errors + 1;
        end else begin
            check_value(active_p_raw,    -32'sd400000, "场景3 active_p_raw");
            check_value(power_factor_raw, -32'sd8000,  "场景3 power_factor_raw");
            check_value(reactive_q_raw,    32'sd300000, "场景3 reactive_q_raw");
        end
        repeat (10) @(posedge clk);

        // ---------------- 场景 4：PF 超过 1 应裁剪 ----------------
        issue_start(16'sd1000, 16'sd500, 32'sd600000, 32'sd200, 32'sd1000, 1'b1, 1'b1, 1'b1);
        wait_done(4000, waited);
        repeat (3) @(posedge clk);
        if (waited < 0) begin
            $display("FAIL: 场景 4 没有等到 done");
            errors = errors + 1;
        end else begin
            check_value(power_factor_raw, 32'sd10000, "场景4 PF 应裁剪到 10000");
            check_value(reactive_q_raw,   32'sd0,     "场景4 S^2<P^2，Q 应为 0");
            check_value(apparent_s_raw,   32'sd500000, "场景4 apparent_s_raw");
        end
        repeat (10) @(posedge clk);

        // ---------------- 场景 5：S=0 ----------------
        issue_start(16'sd1000, 16'sd0, 32'sd400000, 32'sd200, 32'sd1000, 1'b1, 1'b1, 1'b1);
        wait_done(4000, waited);
        repeat (3) @(posedge clk);
        if (waited < 0) begin
            $display("FAIL: 场景 5 没有等到 done");
            errors = errors + 1;
        end else begin
            check_value(apparent_s_raw,   32'sd0, "场景5 S 应为 0");
            check_value(power_factor_raw, 32'sd0, "场景5 除数为 0，PF 应为 0");
            check_value(reactive_q_raw,   32'sd0, "场景5 Q 应为 0");
        end
        repeat (10) @(posedge clk);

        // ---------------- 场景 6：有效标志缺失 ----------------
        issue_start(16'sd1000, 16'sd500, 32'sd400000, 32'sd200, 32'sd1000, 1'b0, 1'b1, 1'b1);
        wait_done(4000, waited);
        repeat (3) @(posedge clk);
        if (waited < 0) begin
            $display("FAIL: 场景 6 没有等到 done");
            errors = errors + 1;
        end else begin
            if (valid_at_done) begin
                $display("FAIL: 场景 6 输入无效时不应给出 power_metrics_valid");
                errors = errors + 1;
            end
        end
        rms_valid = 1'b1;

        if (errors == 0) begin
            $display("PASS: power_metrics_calc");
        end else begin
            $display("FAIL: power_metrics_calc，共 %0d 处不符", errors);
            $fatal(1, "power_metrics_calc 用例未通过");
        end
        $finish;
    end

    initial begin
        #WATCHDOG_NS;
        $display("FAIL: 仿真看门狗超时");
        $fatal(1, "仿真超时");
    end

endmodule
