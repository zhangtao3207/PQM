`timescale 1ns / 1ps

/*
 * 模块: tb_frequency_measure
 * 功能:
 *   frequency_measure 的单元测试平台。喂入已知频率的合成信号（纯正弦 / 调幅 /
 *   谐波 / 直流偏置 / 噪声 / 非零起始相位），断言测得的基波频率落在真值
 *   ±0.05 Hz 以内；判据带 ^actual === 1'bx 守卫，任一处不符用 $fatal 收尾。
 *
 * 采样几何（与真实系统在无量纲意义上等价，只把时钟整体放慢 50 倍）：
 *   真实系统：50 MHz 时钟 / 25.6 kHz 采样 / 50 Hz 基波 -> 1953.125 拍/采样，512 采样/周期
 *   本用例  ： 1 MHz 时钟 / 25.6 kHz 采样 / 50 Hz 基波 ->   39.0625 拍/采样，512 采样/周期
 *   调幅 1 kHz（= 20 个基波周期）、迟滞 512 码对 8100 码幅度、窗口 6144 点（= 12 个基波
 *   周期）全部与真机一致。唯一差别是时钟慢 50 倍，插值分辨率与输出量化因此被放大 50 倍，
 *   所以本用例比真机更苛刻：能过即说明真机有 50 倍余量。
 *
 * 用例（真值均为基波频率，判据 |f_meas - f_true| <= 0.05 Hz）：
 *    1) 纯 50.000 Hz 正弦                        —— 旧的"找峰值"算法在此恒读 97.656 Hz
 *    2) 50 Hz + AM 20%@1kHz + THD 14%            —— 真机主要工况
 *    3) 45.000 Hz 纯正弦
 *    4) 47.500 Hz 纯正弦
 *    5) 52.500 Hz 纯正弦
 *    6) 55.000 Hz 纯正弦
 *    7) 50 Hz + 直流 +3276（5% 满量程）
 *    8) 50 Hz + 直流 -3276
 *    9) 50 Hz + 1% 幅度噪声
 *   10) 50 Hz + AM20%@1kHz + THD14% + 直流 + 噪声 + 非零起始相位
 *   11) 纯直流（窗口内不过零）        -> 只给 done，不给 freq_valid
 *   12) 3 Hz（窗口内不足两个过零）    -> 只给 done，不给 freq_valid
 */

module tb_frequency_measure;

    localparam integer CLK_PERIOD_NS = 1000;      // 1 MHz，见文件头说明
    localparam [63:0] WATCHDOG_NS = 64'd5_000_000_000; // 5 s 仿真时间兜底（单用例约 240 ms）
    localparam integer WINDOW        = 6144;      // 采样窗口点数 = 12 个 50 Hz 周期
    localparam integer N_WIDTH       = 13;        // MAX_FRAME_SAMPLES=8192 时的 N_WIDTH
    localparam integer STEP_NUM      = 625;       // 采样间隔 = 625/16 = 39.0625 拍
    localparam integer STEP_DEN      = 16;
    localparam real    TWO_PI        = 6.283185307179586;
    localparam real    AMP           = 8100.0;    // 基波幅度（码），约合 2.14 V RMS @ ±10V 档
    localparam integer TOL_X100      = 5;         // 判据 ±0.05 Hz

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg start = 1'b0;
    reg [N_WIDTH-1:0] sample_count_n = {N_WIDTH{1'b0}};
    reg sample_valid = 1'b0;
    reg [15:0] sample_code = 16'd32768;
    reg [15:0] zero_code = 16'd32768;
    reg zero_valid = 1'b1;

    wire               busy;
    wire               done;
    wire signed [31:0] freq_period_raw;
    wire               freq_valid;

    integer errors = 0;
    integer tb_tick = 0;

    // done / freq_valid 都只有一拍，必须在脉冲当拍抓
    integer    done_count;
    integer    valid_count;
    reg        valid_at_done;
    reg signed [31:0] period_at_done;

    // 合成信号参数（由 run_case 逐个用例设置）
    real g_f, g_amp, g_am, g_am_f, g_h3, g_h5, g_h7, g_dc, g_noise, g_phase0;

    reg [31:0] lcg;

    always #(CLK_PERIOD_NS / 2) clk = ~clk;
    always @(posedge clk) tb_tick = tb_tick + 1;

    frequency_measure #(
        .WIDTH(16),
        .MAX_FRAME_SAMPLES(8192),
        .N_WIDTH(N_WIDTH)
    ) dut (
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
            valid_at_done  <= freq_valid;
            if (freq_valid)
                valid_count <= valid_count + 1;
        end
    end

    // ---------------- 合成信号与辅助函数 ----------------

    function integer round_real;
        input real x;
        begin
            if (x >= 0.0) round_real = $rtoi(x + 0.5);
            else          round_real = -$rtoi(0.5 - x);
        end
    endfunction

    // 确定性均匀随机数，落在 [-0.5, 0.5)，用于可复现的噪声
    function real urand01;
        begin
            lcg = lcg * 32'd1103515245 + 32'd12345;
            urand01 = ($itor((lcg >> 8) & 32'h00FFFFFF) / 16777216.0) - 0.5;
        end
    endfunction

    // tk = 该采样点在 DUT 时钟计数轴上的绝对拍号；信号在真实时间 tk*1µs 上取值
    function [15:0] gen_code;
        input integer tk;
        real tt, ph, env, v;
        integer iv;
        begin
            tt  = $itor(tk) * 1.0e-6;
            ph  = TWO_PI * g_f * tt + g_phase0;
            env = 1.0 + g_am * $sin(TWO_PI * g_am_f * tt);
            v   = g_amp * env * $sin(ph)
                + g_amp * (g_h3 * $sin(3.0 * ph)
                         + g_h5 * $sin(5.0 * ph)
                         + g_h7 * $sin(7.0 * ph))
                + g_dc;
            if (g_noise > 0.0)
                v = v + g_noise * urand01();
            iv = round_real(32768.0 + v);
            if (iv < 0)     iv = 0;
            if (iv > 65535) iv = 65535;
            gen_code = iv[15:0];
        end
    endfunction

    // ---------------- 判据 ----------------

    task check_freq;
        input [255:0] tag;
        input integer expect_x100;
        reg [63:0] meas_x100;
        integer    diff;
        begin
            if (^period_at_done === 1'bx) begin
                $display("FAIL: %0s freq_period_raw = X（未初始化/未驱动）", tag);
                errors = errors + 1;
            end else if (done_count !== 1) begin
                $display("FAIL: %0s done 脉冲次数 = %0d，期望 1", tag, done_count);
                errors = errors + 1;
            end else if (valid_at_done !== 1'b1) begin
                $display("FAIL: %0s 未给出 freq_valid", tag);
                errors = errors + 1;
            end else if (period_at_done <= 0) begin
                $display("FAIL: %0s freq_period_raw = %0d，应为正数", tag, period_at_done);
                errors = errors + 1;
            end else begin
                meas_x100 = (64'd100000000 + ({32'd0, period_at_done[31:0]} >> 1))
                            / {32'd0, period_at_done[31:0]};
                diff = meas_x100 - expect_x100;
                $display("  %0s: period=%0d 拍 -> f=%0d.%02d Hz（真值 %0d.%02d Hz，偏差 %0d.%02d Hz）",
                         tag, period_at_done,
                         meas_x100 / 100, meas_x100 % 100,
                         expect_x100 / 100, expect_x100 % 100,
                         (diff < 0 ? -diff : diff) / 100, (diff < 0 ? -diff : diff) % 100);
                if (diff > TOL_X100 || diff < -TOL_X100) begin
                    $display("FAIL: %0s 测得 %0d.%02d Hz，偏离真值 %0d.%02d Hz 超过 ±0.05 Hz",
                             tag, meas_x100 / 100, meas_x100 % 100,
                             expect_x100 / 100, expect_x100 % 100);
                    errors = errors + 1;
                end
            end
        end
    endtask

    task check_no_valid;
        input [255:0] tag;
        begin
            if (done_count !== 1) begin
                $display("FAIL: %0s done 脉冲次数 = %0d，期望 1", tag, done_count);
                errors = errors + 1;
            end
            if (valid_at_done !== 1'b0) begin
                $display("FAIL: %0s 过零不足两个，不应给出 freq_valid（实际 %0b，period=%0d）",
                         tag, valid_at_done, period_at_done);
                errors = errors + 1;
            end
        end
    endtask

    // ---------------- 单次测量 ----------------

    task run_case;
        input real    f_sig;
        input real    am;
        input real    am_f;
        input real    h3;
        input real    h5;
        input real    h7;
        input real    dc;
        input real    noise;
        input real    phase0;
        integer tick_base, k, tgt, i;
        reg ok;
        begin
            g_f = f_sig; g_amp = AMP; g_am = am; g_am_f = am_f;
            g_h3 = h3; g_h5 = h5; g_h7 = h7;
            g_dc = dc; g_noise = noise; g_phase0 = phase0;
            lcg = 32'h1234_5678;

            done_count     = 0;
            valid_count    = 0;
            valid_at_done  = 1'bx;
            period_at_done = 32'sd0;

            @(negedge clk);
            sample_count_n = WINDOW[N_WIDTH-1:0];
            start          = 1'b1;
            sample_valid   = 1'b0;
            @(negedge clk);
            start = 1'b0;
            repeat (4) @(negedge clk);   // 等 DUT 进入 ST_CAPTURE

            tick_base = tb_tick;
            for (k = 0; k < WINDOW; k = k + 1) begin
                tgt = tick_base + (k * STEP_NUM + (STEP_DEN / 2)) / STEP_DEN;
                wait (tb_tick >= tgt);
                @(negedge clk);
                sample_code  = gen_code(tb_tick + 1);
                sample_valid = 1'b1;
                @(negedge clk);
                sample_valid = 1'b0;
            end

            ok = 1'b0;
            for (i = 0; i < 600 && !ok; i = i + 1) begin
                @(negedge clk);
                if (done_count != 0)
                    ok = 1'b1;
            end
            if (!ok) begin
                $display("FAIL: 窗口结束后等不到 done");
                errors = errors + 1;
            end
            repeat (4) @(negedge clk);
        end
    endtask

    // ---------------- 主流程 ----------------

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

        // 1) 纯 50.000 Hz
        run_case(50.000, 0.0, 1000.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0);
        check_freq("case01 pure 50.000Hz", 5000);

        // 2) 50 Hz + AM 20%@1kHz + THD 14%（3 次 11% / 5 次 7% / 7 次 5% -> THD 13.96%）
        run_case(50.000, 0.20, 1000.0, 0.11, 0.07, 0.05, 0.0, 0.0, 0.0);
        check_freq("case02 50Hz+AM20%+THD14%", 5000);

        // 3~6) 45 / 47.5 / 52.5 / 55 Hz
        run_case(45.000, 0.0, 1000.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.3);
        check_freq("case03 45.000Hz", 4500);

        run_case(47.500, 0.0, 1000.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.7);
        check_freq("case04 47.500Hz", 4750);

        run_case(52.500, 0.0, 1000.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.1);
        check_freq("case05 52.500Hz", 5250);

        run_case(55.000, 0.0, 1000.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.7);
        check_freq("case06 55.000Hz", 5500);

        // 7~8) 直流偏置 ±3276（5% 满量程）
        run_case(50.000, 0.0, 1000.0, 0.0, 0.0, 0.0, 3276.0, 0.0, 0.5);
        check_freq("case07 50Hz+DC+3276", 5000);

        run_case(50.000, 0.0, 1000.0, 0.0, 0.0, 0.0, -3276.0, 0.0, 2.2);
        check_freq("case08 50Hz+DC-3276", 5000);

        // 9) 1% 幅度噪声（峰峰值 ±81 码，低于 512 码迟滞）
        run_case(50.000, 0.0, 1000.0, 0.0, 0.0, 0.0, 0.0, 81.0, 0.9);
        check_freq("case09 50Hz+1pct noise", 5000);

        // 10) 最恶劣组合：调幅 + 谐波 + 直流 + 噪声 + 非零起始相位
        run_case(50.000, 0.20, 1000.0, 0.11, 0.07, 0.05, 1500.0, 81.0, 2.6);
        check_freq("case10 50Hz all disturbances", 5000);

        // 11) 纯直流：窗口内没有过零
        run_case(0.0, 0.0, 1000.0, 0.0, 0.0, 0.0, 1200.0, 0.0, 0.0);
        check_no_valid("case11 DC only, no zero crossing");

        // 12) 3 Hz：240 ms 窗口内不足两个过零
        run_case(3.000, 0.0, 1000.0, 0.0, 0.0, 0.0, 0.0, 0.0, 3.14159265);
        check_no_valid("case12 3Hz, less than 2 zero crossings");

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
