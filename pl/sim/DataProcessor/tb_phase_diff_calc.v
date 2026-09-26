`timescale 1ns / 1ps

/*
 * 模块: tb_phase_diff_calc
 * 功能:
 *   phase_diff_calc 的单元测试平台：在采样窗口内检测 U/I 的同向过零，
 *   输出电流过零相对电压过零的偏移计数与电压过零周期计数。
 *
 *   计数约定（按实现，用例照此断言）：两个计数器都在各自过零的那一拍清零，
 *   而同拍的自增被清零覆盖，所以读出的是"两次过零之间的拍数**减一**"。
 *   实测：过零间隔 5 拍时 period=4；电流比电压晚 3 拍过零时 offset=2。
 *
 *   这个减一不影响任何输出数值，原因已核实：
 *     1) time_x100_normalizer 把 phase_offset_raw/phase_period_raw 锁存后从未读取，
 *        最终功率角是用 |Q|/(|P|+|Q|) 查 atan 表得到的；
 *     2) 这两个计数只用于 phase_valid 门控与 power_metrics_calc 里 Q 的符号判据，
 *        而符号判据是 offset > period/2 && offset < period —— 两边同时减一，
 *        在整数比较里完全抵消。
 *
 *   注意：done 只有一拍。锁存可能发生在窗口中途（例如第 10 拍），所以不能等采样送完
 *   再轮询，必须用监视进程在脉冲当拍抓取结果。
 *
 *   过零门限带迟滞：先要采到 <= ref-512 才算"武装"，之后采到 >= ref+512 才判为过零。
 *
 *   五个场景（每拍一个有效采样，窗口 16 拍）：
 *     1) 同相：U/I 都在第 5、10 拍过零        -> offset=0,  period=4
 *     2) 电流晚 3 拍过零（第 7 拍）            -> offset=2,  period=4
 *     3) 窗口内只有一次 U 过零                -> 只给 done，不给 valid
 *     4) 零点参考无效 -> 退回中心码 0x8000     -> 同场景 2
 *     5) 码值只在迟滞带内抖动，不构成过零      -> 只给 done，不给 valid
 */

module tb_phase_diff_calc;

    localparam integer CLK_PERIOD  = 10;      // 100 MHz
    localparam integer WATCHDOG_NS = 2000000; // 2 ms 兜底
    localparam integer N_WIDTH     = 12;      // MAX_FRAME_SAMPLES=4096 时的 N_WIDTH

    // 迟滞带外的两个码值：0x7000 低于 ref-512，0x9000 高于 ref+512
    localparam [15:0] LOW_CODE  = 16'h7000;
    localparam [15:0] HIGH_CODE = 16'h9000;
    localparam [15:0] MID_CODE  = 16'h8000;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg start = 1'b0;
    reg [N_WIDTH-1:0] sample_count_n = {N_WIDTH{1'b0}};
    reg sample_valid = 1'b0;
    reg [15:0] u_sample_code = MID_CODE;
    reg [15:0] u_zero_code = MID_CODE;
    reg u_zero_valid = 1'b1;
    reg [15:0] i_sample_code = MID_CODE;
    reg [15:0] i_zero_code = MID_CODE;
    reg i_zero_valid = 1'b1;

    wire               busy;
    wire               done;
    wire signed [31:0] phase_offset_raw;
    wire signed [31:0] phase_period_raw;
    wire               phase_valid;

    integer errors = 0;

    // 监视进程抓取的单拍脉冲与当时的锁存值
    integer    done_count;
    integer    valid_count;
    reg signed [31:0] offset_at_done;
    reg signed [31:0] period_at_done;

    always #(CLK_PERIOD / 2) clk = ~clk;

    phase_diff_calc dut (
        .clk(clk),
        .rst_n(rst_n),
        .start(start),
        .sample_count_n(sample_count_n),
        .sample_valid(sample_valid),
        .u_sample_code(u_sample_code),
        .u_zero_code(u_zero_code),
        .u_zero_valid(u_zero_valid),
        .i_sample_code(i_sample_code),
        .i_zero_code(i_zero_code),
        .i_zero_valid(i_zero_valid),
        .busy(busy),
        .done(done),
        .phase_offset_raw(phase_offset_raw),
        .phase_period_raw(phase_period_raw),
        .phase_valid(phase_valid)
    );

    // done / phase_valid 都只有一拍，必须在脉冲当拍抓，事后再轮询会漏掉
    always @(posedge clk) begin
        if (rst_n && done) begin
            done_count      <= done_count + 1;
            offset_at_done  <= phase_offset_raw;
            period_at_done  <= phase_period_raw;
            if (phase_valid)
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
            offset_at_done = 32'sd0;
            period_at_done = 32'sd0;
            sample_count_n = count;
            start          = 1'b1;
            sample_valid   = 1'b0;
            @(negedge clk);
            start          = 1'b0;
        end
    endtask

    // 送一个有效采样；调用一次推进一拍
    task send;
        input [15:0] u_code;
        input [15:0] i_code;
        begin
            @(negedge clk);
            u_sample_code = u_code;
            i_sample_code = i_code;
            sample_valid  = 1'b1;
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

    task expect_done_once;
        input [127:0] tag;
        begin
            if (done_count !== 1) begin
                $display("FAIL: %0s 的 done 脉冲次数 = %0d，期望 1", tag, done_count);
                errors = errors + 1;
            end
        end
    endtask

    // 送 16 拍采样：u_seq 用位选决定，避免写十六行
    task run_window_no_u_cross;
        begin
            send(LOW_CODE,  LOW_CODE);
            send(LOW_CODE,  LOW_CODE);
            send(LOW_CODE,  LOW_CODE);
            send(LOW_CODE,  LOW_CODE);
            send(HIGH_CODE, HIGH_CODE);
            send(LOW_CODE,  LOW_CODE);
            send(LOW_CODE,  LOW_CODE);
            send(LOW_CODE,  LOW_CODE);
            send(LOW_CODE,  LOW_CODE);
            send(LOW_CODE,  LOW_CODE);
            send(LOW_CODE,  LOW_CODE);
            send(LOW_CODE,  LOW_CODE);
            send(LOW_CODE,  LOW_CODE);
            send(LOW_CODE,  LOW_CODE);
            send(LOW_CODE,  LOW_CODE);
            send(LOW_CODE,  LOW_CODE);
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

        // ---------------- 场景 1：同相 ----------------
        issue_start(12'd16);
        send(LOW_CODE,  LOW_CODE);    // 1
        send(LOW_CODE,  LOW_CODE);    // 2
        send(LOW_CODE,  LOW_CODE);    // 3
        send(LOW_CODE,  LOW_CODE);    // 4
        send(HIGH_CODE, HIGH_CODE);   // 5  U/I 同时过零
        send(LOW_CODE,  LOW_CODE);    // 6
        send(LOW_CODE,  LOW_CODE);    // 7
        send(LOW_CODE,  LOW_CODE);    // 8
        send(LOW_CODE,  LOW_CODE);    // 9
        send(HIGH_CODE, HIGH_CODE);   // 10 U/I 再次同时过零 -> 锁存
        send(MID_CODE,  MID_CODE);    // 11
        send(MID_CODE,  MID_CODE);    // 12
        send(MID_CODE,  MID_CODE);    // 13
        send(MID_CODE,  MID_CODE);    // 14
        send(MID_CODE,  MID_CODE);    // 15
        send(MID_CODE,  MID_CODE);    // 16
        end_window;
        settle;
        expect_done_once("场景1");
        if (valid_count !== 1) begin
            $display("FAIL: 场景 1 的 phase_valid 次数 = %0d，期望 1", valid_count);
            errors = errors + 1;
        end
        check_value(offset_at_done, 32'sd0, "场景1 phase_offset_raw");
        check_value(period_at_done, 32'sd4, "场景1 phase_period_raw");
        settle;

        // ---------------- 场景 2：电流晚 3 拍过零 ----------------
        issue_start(12'd16);
        send(LOW_CODE,  LOW_CODE);    // 1
        send(LOW_CODE,  LOW_CODE);    // 2
        send(LOW_CODE,  LOW_CODE);    // 3
        send(LOW_CODE,  LOW_CODE);    // 4
        send(HIGH_CODE, LOW_CODE);    // 5  U 第一次过零
        send(LOW_CODE,  LOW_CODE);    // 6
        send(LOW_CODE,  HIGH_CODE);   // 7  I 过零（比 U 晚 3 拍）
        send(LOW_CODE,  LOW_CODE);    // 8
        send(LOW_CODE,  LOW_CODE);    // 9
        send(HIGH_CODE, LOW_CODE);    // 10 U 第二次过零 -> 锁存
        send(MID_CODE,  MID_CODE);    // 11
        send(MID_CODE,  MID_CODE);    // 12
        send(MID_CODE,  MID_CODE);    // 13
        send(MID_CODE,  MID_CODE);    // 14
        send(MID_CODE,  MID_CODE);    // 15
        send(MID_CODE,  MID_CODE);    // 16
        end_window;
        settle;
        expect_done_once("场景2");
        if (valid_count !== 1) begin
            $display("FAIL: 场景 2 的 phase_valid 次数 = %0d，期望 1", valid_count);
            errors = errors + 1;
        end
        check_value(offset_at_done, 32'sd2, "场景2 phase_offset_raw");
        check_value(period_at_done, 32'sd4, "场景2 phase_period_raw");
        settle;

        // ---------------- 场景 3：窗口内只有一次 U 过零 ----------------
        issue_start(12'd16);
        run_window_no_u_cross;
        end_window;
        settle;
        expect_done_once("场景3");
        if (valid_count !== 0) begin
            $display("FAIL: 场景 3 只有一次过零，不应给出 phase_valid（实际 %0d 次）", valid_count);
            errors = errors + 1;
        end
        settle;

        // ---------------- 场景 4：零点参考无效，退回中心码 ----------------
        u_zero_valid = 1'b0;
        i_zero_valid = 1'b0;
        issue_start(12'd16);
        send(LOW_CODE,  LOW_CODE);    // 1
        send(LOW_CODE,  LOW_CODE);    // 2
        send(LOW_CODE,  LOW_CODE);    // 3
        send(LOW_CODE,  LOW_CODE);    // 4
        send(HIGH_CODE, LOW_CODE);    // 5
        send(LOW_CODE,  LOW_CODE);    // 6
        send(LOW_CODE,  HIGH_CODE);   // 7
        send(LOW_CODE,  LOW_CODE);    // 8
        send(LOW_CODE,  LOW_CODE);    // 9
        send(HIGH_CODE, LOW_CODE);    // 10
        send(MID_CODE,  MID_CODE);    // 11
        send(MID_CODE,  MID_CODE);    // 12
        send(MID_CODE,  MID_CODE);    // 13
        send(MID_CODE,  MID_CODE);    // 14
        send(MID_CODE,  MID_CODE);    // 15
        send(MID_CODE,  MID_CODE);    // 16
        end_window;
        settle;
        expect_done_once("场景4");
        check_value(offset_at_done, 32'sd2, "场景4 phase_offset_raw");
        check_value(period_at_done, 32'sd4, "场景4 phase_period_raw");
        u_zero_valid = 1'b1;
        i_zero_valid = 1'b1;
        settle;

        // ---------------- 场景 5：码值只在迟滞带内抖动 ----------------
        // 0x7F00 高于 ref-512(0x7E00)，永远不会"武装"；0x8100 低于 ref+512(0x8200)，
        // 即使武装了也不会触发。所以整个窗口没有 U 过零。
        issue_start(12'd16);
        send(16'h7F00, LOW_CODE);     // 1
        send(16'h7F00, LOW_CODE);     // 2
        send(16'h7F00, LOW_CODE);     // 3
        send(16'h7F00, LOW_CODE);     // 4
        send(16'h8100, HIGH_CODE);    // 5
        send(16'h7F00, LOW_CODE);     // 6
        send(16'h7F00, LOW_CODE);     // 7
        send(16'h7F00, LOW_CODE);     // 8
        send(16'h7F00, LOW_CODE);     // 9
        send(16'h8100, HIGH_CODE);    // 10
        send(16'h7F00, LOW_CODE);     // 11
        send(16'h7F00, LOW_CODE);     // 12
        send(16'h7F00, LOW_CODE);     // 13
        send(16'h7F00, LOW_CODE);     // 14
        send(16'h7F00, LOW_CODE);     // 15
        send(16'h7F00, LOW_CODE);     // 16
        end_window;
        settle;
        expect_done_once("场景5");
        if (valid_count !== 0) begin
            $display("FAIL: 场景 5 码值未越过迟滞带，不应给出 phase_valid（实际 %0d 次）", valid_count);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PASS: phase_diff_calc");
        end else begin
            $display("FAIL: phase_diff_calc，共 %0d 处不符", errors);
            $fatal(1, "phase_diff_calc 用例未通过");
        end
        $finish;
    end

    initial begin
        #WATCHDOG_NS;
        $display("FAIL: 仿真看门狗超时");
        $fatal(1, "仿真超时");
    end

endmodule
