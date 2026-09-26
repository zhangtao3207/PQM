`timescale 1ns / 1ps

/*
 * 模块: tb_time_zero_code_tracker
 * 功能:
 *   time_zero_code_tracker 的单元测试平台：对偏移二进制采样做动态零点跟踪。
 *
 *   期望值是先用同样的定点规则离线算准再写进来的（WIDTH=16、EST_SHIFT=8、
 *   WARMUP_SHIFT=4、WARMUP_SAMPLES=256）：
 *     恒定 0x9000 输入：第 1 拍 0x8100、第 2 拍 0x81F0、第 10 拍 0x8798、
 *                       第 100 拍 0x8FF5、第 255 拍收敛到 0x9000 且 zero_valid 仍为 0、
 *                       第 256 拍 zero_valid 拉高。
 *     恒定 0xFFFF 或 0x0000 输入：收敛到 0xFFFF / 0x0000（钳位正确，不外溢）。
 *
 *   五个场景：
 *     1) 预热期逐拍收敛（检查 1/2/10/100/255/256 拍的关键点与 zero_valid 的确切位置）
 *     2) 稳态步长：zero_valid 之后 delta=+512 应产生 +2 的步长
 *     3) 稳态小误差下步长至少为 1（delta=+1 也应前进 1）
 *     4) 恒定 0xFFFF 收敛且不越过上界
 *     5) 恒定 0x0000 收敛且不越过下界
 */

module tb_time_zero_code_tracker;

    localparam integer CLK_PERIOD  = 10;      // 100 MHz
    localparam integer WATCHDOG_NS = 5000000; // 5 ms 兜底

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg sample_valid = 1'b0;
    reg [15:0] sample_code = 16'h8000;

    wire [15:0] zero_code;
    wire        zero_valid;

    integer errors = 0;
    integer i;

    always #(CLK_PERIOD / 2) clk = ~clk;

    time_zero_code_tracker dut (
        .clk(clk),
        .rst_n(rst_n),
        .sample_valid(sample_valid),
        .sample_code(sample_code),
        .zero_code(zero_code),
        .zero_valid(zero_valid)
    );

    task do_reset;
        begin
            @(negedge clk);
            sample_valid = 1'b0;
            rst_n = 1'b0;
            repeat (5) @(negedge clk);
            rst_n = 1'b1;
            @(negedge clk);
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

    task send_n;
        input integer count;
        input [15:0] code;
        begin
            for (i = 0; i < count; i = i + 1)
                send(code);
        end
    endtask

    task stop_samples;
        begin
            @(negedge clk);
            sample_valid = 1'b0;
        end
    endtask

    task check_code;
        input [15:0] expected;
        input [127:0] tag;
        begin
            if (zero_code !== expected) begin
                $display("FAIL: %0s zero_code=0x%04X，期望 0x%04X", tag, zero_code, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        repeat (10) @(posedge clk);

        // ---------------- 场景 1：预热期逐拍收敛 ----------------
        do_reset;
        if (zero_code !== 16'h8000) begin
            $display("FAIL: 复位后 zero_code=0x%04X，期望 0x8000", zero_code);
            errors = errors + 1;
        end
        if (zero_valid !== 1'b0) begin
            $display("FAIL: 复位后 zero_valid 应为 0");
            errors = errors + 1;
        end

        send(16'h9000);              // 1
        stop_samples;
        check_code(16'h8100, "第 1 拍");

        send(16'h9000);              // 2
        stop_samples;
        check_code(16'h81F0, "第 2 拍");

        send_n(8, 16'h9000);         // 3..10
        stop_samples;
        check_code(16'h8798, "第 10 拍");

        send_n(90, 16'h9000);        // 11..100
        stop_samples;
        check_code(16'h8FF5, "第 100 拍");

        send_n(155, 16'h9000);       // 101..255
        stop_samples;
        check_code(16'h9000, "第 255 拍");
        if (zero_valid !== 1'b0) begin
            $display("FAIL: 第 255 拍 zero_valid 应为 0");
            errors = errors + 1;
        end

        send(16'h9000);              // 256
        stop_samples;
        check_code(16'h9000, "第 256 拍");
        if (zero_valid !== 1'b1) begin
            $display("FAIL: 第 256 拍 zero_valid 应拉高");
            errors = errors + 1;
        end

        // ---------------- 场景 2：稳态步长 delta=+512 -> +2 ----------------
        // 当前 zero_code=0x9000，喂 0x9200：delta=512，512>>8=2
        send(16'h9200);
        stop_samples;
        check_code(16'h9002, "稳态 +512");

        // ---------------- 场景 3：稳态小误差步长至少为 1 ----------------
        // 当前 zero_code=0x9002，喂 0x9003：delta=1，1>>8=0，应被强制为 +1
        send(16'h9003);
        stop_samples;
        check_code(16'h9003, "稳态 +1 强制步长");

        // ---------------- 场景 4：恒定 0xFFFF ----------------
        do_reset;
        send_n(256, 16'hFFFF);
        stop_samples;
        check_code(16'hFFFF, "恒定 0xFFFF");
        if (zero_valid !== 1'b1) begin
            $display("FAIL: 场景 4 第 256 拍 zero_valid 应拉高");
            errors = errors + 1;
        end

        // ---------------- 场景 5：恒定 0x0000 ----------------
        do_reset;
        send_n(256, 16'h0000);
        stop_samples;
        check_code(16'h0000, "恒定 0x0000");
        if (zero_valid !== 1'b1) begin
            $display("FAIL: 场景 5 第 256 拍 zero_valid 应拉高");
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PASS: time_zero_code_tracker");
        end else begin
            $display("FAIL: time_zero_code_tracker，共 %0d 处不符", errors);
            $fatal(1, "time_zero_code_tracker 用例未通过");
        end
        $finish;
    end

    initial begin
        #WATCHDOG_NS;
        $display("FAIL: 仿真看门狗超时");
        $fatal(1, "仿真超时");
    end

endmodule
