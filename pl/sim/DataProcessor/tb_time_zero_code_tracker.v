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

    // ---- 场景 6 专用：生产参数实例的激励与统计 ----
    reg  [15:0] z6_sample_code  = 16'h8000;
    reg         z6_sample_valid = 1'b0;
    wire [15:0] z6_zero_code;
    wire        z6_zero_valid;
    integer     sine_lut6 [0:511];
    integer     n6;
    integer     acc6;
    integer     avg6;
    integer     z6_code_i;

    always #(CLK_PERIOD / 2) clk = ~clk;

    time_zero_code_tracker dut (
        .clk(clk),
        .rst_n(rst_n),
        .sample_valid(sample_valid),
        .sample_code(sample_code),
        .zero_code(zero_code),
        .zero_valid(zero_valid)
    );

    // 生产参数（与 pqm_pl_top 的 u_zero_tracker_u1/u2 完全一致）：
    // 默认参数（EST_SHIFT=8）下跟踪器纹波高达 ±0.32×幅值，与最小步长规则耦合后
    // 会长时间单向漂移，不适合做“平衡点”判据，所以场景 6 必须用这组参数。
    time_zero_code_tracker #(
        .WIDTH(16), .EST_SHIFT(14), .WARMUP_SHIFT(10), .WARMUP_SAMPLES(4096)
    ) dut_prod (
        .clk(clk), .rst_n(rst_n),
        .sample_valid(z6_sample_valid), .sample_code(z6_sample_code),
        .zero_code(z6_zero_code), .zero_valid(z6_zero_valid)
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

        // ---------------- 场景 6：生产参数下"纯交流"零点必须收敛到真实均值 ----------------
        // 回归缺陷 2（"去零点后恒有 ~29% 直流"的根因）：
        //   原实现 zero_step = delta >>> SHIFT，`>>>` 对负数等价于向下取整（floor），
        //   同样幅度的 delta 负方向步长恒比正方向大 1 LSB；配合下面的"最小步长 ±1"
        //   规则，step(delta) 不再是奇函数 → 纯交流输入下 E[step] < 0，
        //   zero_code 稳定偏低，直到偏移把不对称补偿掉才停。
        //   板上实测：14.05 Vpp 纯正弦下 DC-U2 = 28.68%、H1 = 70.97%。
        // 本场景用 pqm_pl_top 的生产参数（EST_SHIFT=14 / WARMUP_SHIFT=10 / 4096），
        // 喂 0x8000 零直流 + 23020 码幅值（= 14.05 Vpp）的正弦，跑 120000 个样本，
        // 在平衡点取一整周期（512 点）zero_code 平均，必须落在 0x8000 ± 500 码内。
        // 离线定点复算：修复后 = 32705（偏离 63）；未修复 = 28196（偏离 4572）。
        for (i = 0; i < 512; i = i + 1)
            sine_lut6[i] = $rtoi($sin(2.0 * 3.14159265358979 * i / 512.0) * 1000.0);

        do_reset;
        acc6 = 0;
        for (n6 = 0; n6 < 120000; n6 = n6 + 1) begin
            @(negedge clk);
            // 注意：必须经过 integer 中间量。若直接写
            //   z6_sample_code = 16'h8000 + ((23020*lut)/1000);
            // 整个 RHS 会因为 LHS 是无符号 reg 而被当成无符号表达式，
            // 负半周的除法变成大无符号商，截到 16 位后是一个彻底畸变的波形
            // （实测谷值处 code 从应有的 9748 变成 44875）。
            z6_code_i = 16'sh8000 + ((23020 * sine_lut6[n6 % 512]) / 1000);
            z6_sample_code  = z6_code_i[15:0];
            z6_sample_valid = 1'b1;
            if (n6 >= (120000 - 512)) acc6 = acc6 + z6_zero_code;
        end
        @(negedge clk);
        z6_sample_valid = 1'b0;
        avg6 = acc6 / 512;

        $display("INFO: 场景 6 纯交流（幅值 23020 码、零直流）平衡点 zero_code 均值 = %0d（0x%04h），偏离 0x8000 共 %0d 码",
                 avg6, avg6[15:0], (avg6 > 32768) ? (avg6 - 32768) : (32768 - avg6));
        if (z6_zero_valid !== 1'b1) begin
            $display("FAIL: 场景 6 预热结束后 zero_valid 应为 1");
            errors = errors + 1;
        end
        if (^avg6 === 1'bx) begin
            $display("FAIL: 场景 6 zero_code 均值为 X（未初始化/未驱动）");
            errors = errors + 1;
        end else if ((avg6 > 32768 + 500) || (avg6 < 32768 - 500)) begin
            $display("FAIL: 场景 6 纯交流下 zero_code 平衡点 = %0d，偏离真实均值 0x8000 超过 500 码（去零点后会凭空多出直流）",
                     avg6);
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
