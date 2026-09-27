`timescale 1ns / 1ps

/*
 * 模块: tb_time_x100_normalizer
 * 功能:
 *   time_x100_normalizer 的单元测试平台：把时域链路的 raw 结果统一换算成 x100 工程量。
 *   一次 start 会依次跑完 RMS、峰峰值、频率、相位、功率五段，最后给出 done。
 *
 *   相位段依赖 IP rom_atan_lut_1024，这里用 pl/sim/models/rom_atan_lut_1024.v
 *   这个行为级等价模型（同一份 COE 生成的 1025x14、读延迟 1 拍的 ROM）。
 *   因此本用例覆盖的是地址计算与象限修正，不是 ROM 表内容本身的正确性。
 *
 *   CLK_FREQ_X100 参数在用例里改成 100000000（1 MHz 的 x100），让频率结果好核对。
 *
 *   三组用例（期望值由离线整数运算算出，脚本口径与 RTL 完全一致）：
 *
 *   第一组：u1_rms=16384 u2_rms=8192 pp_u1=65536 pp_u2=32768 freq_period=2000
 *           P=1000000 Q=-1000000 S=1500000 PF=9500 全有效
 *      u1_rms_x100  = (16384*10000+16384)/32767 = 5000
 *      u2_rms_x100  = ( 8192*10000+16384)/32767 = 2500
 *      u1_pp_x100   = (65536*10000+16384)/32768 = 20000
 *      u2_pp_x100   = (32768*10000+16384)/32768 = 10000
 *      freq_x100   = (100000000+1000)/2000      = 50000
 *      相位：|P|=|Q| -> 地址 (1000000*1024)/2000000 = 512 -> ROM[512]=4500；
 *            P>0、Q<0 -> 第四象限 -> -4500
 *      P/Q/S/PF 走 96 位除法（除数常量 107367628900）：931 / -931 / 1397 / 95
 *
 *   第二组：rms_valid=0、pp_u1 越界钳位、u2_pp_valid=0、freq_valid=0、
 *           P=Q=-1000000、S=0、PF=-9500
 *      u1_rms=u2_rms=0、u1_pp=99999、u2_pp=0、freq=0、
 *      相位：P<0、Q<0 -> 第三象限 -> -18000+4500 = -13500
 *      P=-931、Q=-931、S=0、PF=-95
 *
 *   第三组：P=Q=0 且各路 valid 全 0
 *      相位分母为 0 -> 相位无效 -> 0；其余输出全 0
 */

module tb_time_x100_normalizer;

    localparam integer CLK_PERIOD  = 10;      // 100 MHz
    localparam integer WATCHDOG_NS = 5000000; // 5 ms 兜底（含多个 96 位除法）
    localparam [39:0]  CLK_FREQ_X100 = 40'd100000000;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg start = 1'b0;
    reg signed [31:0] u1_rms_raw = 32'sd0;
    reg signed [31:0] u2_rms_raw = 32'sd0;
    reg rms_valid = 1'b0;
    reg signed [31:0] u1_pp_raw = 32'sd0;
    reg signed [31:0] u2_pp_raw = 32'sd0;
    reg u1_pp_valid = 1'b0;
    reg u2_pp_valid = 1'b0;
    reg signed [31:0] phase_offset_raw = 32'sd0;
    reg signed [31:0] phase_period_raw = 32'sd0;
    reg phase_valid = 1'b0;
    reg signed [31:0] freq_period_raw = 32'sd0;
    reg freq_valid = 1'b0;
    reg signed [31:0] active_p_raw = 32'sd0;
    reg signed [31:0] reactive_q_raw = 32'sd0;
    reg signed [31:0] apparent_s_raw = 32'sd0;
    reg signed [31:0] power_factor_raw = 32'sd0;
    reg [31:0] u1_full_scale_x100 = 32'd10000;
    reg [31:0] u2_full_scale_x100 = 32'd10000;
    reg power_metrics_valid = 1'b0;

    wire               done;
    wire signed [31:0] u1_rms_x100;
    wire signed [31:0] u2_rms_x100;
    wire signed [31:0] u1_pp_x100;
    wire signed [31:0] u2_pp_x100;
    wire signed [31:0] phase_x100;
    wire signed [31:0] freq_x100;
    wire signed [31:0] active_p_x100;
    wire signed [31:0] reactive_q_x100;
    wire signed [31:0] apparent_s_x100;
    wire signed [31:0] power_factor_x100;

    integer errors = 0;
    integer i;
    reg     ok;

    always #(CLK_PERIOD / 2) clk = ~clk;

    time_x100_normalizer #(
        .CODE_WIDTH(16),
        .CLK_FREQ_X100(CLK_FREQ_X100)
    ) dut (
        .clk                  (clk),
        .rst_n                (rst_n),
        .start                (start),
        .u1_rms_raw            (u1_rms_raw),
        .u2_rms_raw            (u2_rms_raw),
        .rms_valid            (rms_valid),
        .u1_pp_raw             (u1_pp_raw),
        .u2_pp_raw             (u2_pp_raw),
        .u1_pp_valid           (u1_pp_valid),
        .u2_pp_valid           (u2_pp_valid),
        .phase_offset_raw     (phase_offset_raw),
        .phase_period_raw     (phase_period_raw),
        .phase_valid          (phase_valid),
        .freq_period_raw      (freq_period_raw),
        .freq_valid           (freq_valid),
        .active_p_raw         (active_p_raw),
        .reactive_q_raw       (reactive_q_raw),
        .apparent_s_raw       (apparent_s_raw),
        .power_factor_raw     (power_factor_raw),
        .u1_full_scale_x100    (u1_full_scale_x100),
        .u2_full_scale_x100    (u2_full_scale_x100),
        .power_metrics_valid  (power_metrics_valid),
        .done                 (done),
        .u1_rms_x100           (u1_rms_x100),
        .u2_rms_x100           (u2_rms_x100),
        .u1_pp_x100            (u1_pp_x100),
        .u2_pp_x100            (u2_pp_x100),
        .phase_x100           (phase_x100),
        .freq_x100            (freq_x100),
        .active_p_x100        (active_p_x100),
        .reactive_q_x100      (reactive_q_x100),
        .apparent_s_x100      (apparent_s_x100),
        .power_factor_x100    (power_factor_x100)
    );

    task check32;
        input signed [31:0] actual;
        input signed [31:0] expected;
        input [255:0] tag;
        input [95:0]  what;
        begin
            if (actual !== expected) begin
                $display("FAIL: %0s %0s = %0d，期望 %0d", tag, what, actual, expected);
                errors = errors + 1;
            end
        end
    endtask

    // 打一拍 start，等 done，然后核对 10 个输出
    task run_case;
        input [255:0] tag;
        input signed [31:0] exp_urms;
        input signed [31:0] exp_irms;
        input signed [31:0] exp_upp;
        input signed [31:0] exp_ipp;
        input signed [31:0] exp_freq;
        input signed [31:0] exp_phase;
        input signed [31:0] exp_p;
        input signed [31:0] exp_q;
        input signed [31:0] exp_s;
        input signed [31:0] exp_pf;
        begin
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;

            ok = 1'b0;
            for (i = 0; i < 20000 && !ok; i = i + 1) begin
                @(negedge clk);
                if (done) ok = 1'b1;
            end

            if (!ok) begin
                $display("FAIL: %0s 等不到 done", tag);
                errors = errors + 1;
            end else begin
                @(negedge clk);
                check32(u1_rms_x100,        exp_urms,  tag, "u_rms_x100");
                check32(u2_rms_x100,        exp_irms,  tag, "i_rms_x100");
                check32(u1_pp_x100,         exp_upp,   tag, "u_pp_x100");
                check32(u2_pp_x100,         exp_ipp,   tag, "i_pp_x100");
                check32(freq_x100,         exp_freq,  tag, "freq_x100");
                check32(phase_x100,        exp_phase, tag, "phase_x100");
                check32(active_p_x100,     exp_p,     tag, "active_p_x100");
                check32(reactive_q_x100,   exp_q,     tag, "reactive_q_x100");
                check32(apparent_s_x100,   exp_s,     tag, "apparent_s_x100");
                check32(power_factor_x100, exp_pf,    tag, "power_factor_x100");
            end

            repeat (4) @(negedge clk);
        end
    endtask

    initial begin
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);

        // ---------------- 第一组 ----------------
        u1_rms_raw = 32'sd16384;   u2_rms_raw = 32'sd8192;
        rms_valid = 1'b1;
        u1_pp_raw = 32'sd65536;    u2_pp_raw = 32'sd32768;
        u1_pp_valid = 1'b1;        u2_pp_valid = 1'b1;
        freq_period_raw = 32'sd2000; freq_valid = 1'b1;
        phase_offset_raw = 32'sd0;   phase_period_raw = 32'sd2000;
        phase_valid = 1'b1;
        active_p_raw = 32'sd1000000;  reactive_q_raw = -32'sd1000000;
        apparent_s_raw = 32'sd1500000; power_factor_raw = 32'sd9500;
        power_metrics_valid = 1'b1;
        run_case("第一组",
                 32'sd5000, 32'sd2500, 32'sd20000, 32'sd10000, 32'sd50000,
                 -32'sd4500, 32'sd931, -32'sd931, 32'sd1397, 32'sd95);

        // ---------------- 第二组 ----------------
        u1_rms_raw = -32'sd1000;   u2_rms_raw = 32'sd100;
        rms_valid = 1'b0;                       // RMS 无效 -> 两路都 0
        u1_pp_raw = 32'sd100000000; u2_pp_raw = 32'sd32768;
        u1_pp_valid = 1'b1;        u2_pp_valid = 1'b0;  // U2峰峰值无效 -> 0
        freq_period_raw = 32'sd2000; freq_valid = 1'b0; // 频率无效 -> 0
        phase_valid = 1'b1;
        active_p_raw = -32'sd1000000; reactive_q_raw = -32'sd1000000;
        apparent_s_raw = 32'sd0;      power_factor_raw = -32'sd9500;
        power_metrics_valid = 1'b1;
        run_case("第二组",
                 32'sd0, 32'sd0, 32'sd99999, 32'sd0, 32'sd0,
                 -32'sd13500, -32'sd931, -32'sd931, 32'sd0, -32'sd95);

        // ---------------- 第三组：全部无效 ----------------
        u1_rms_raw = 32'sd0;       u2_rms_raw = 32'sd0;
        rms_valid = 1'b0;
        u1_pp_raw = 32'sd0;        u2_pp_raw = 32'sd0;
        u1_pp_valid = 1'b0;        u2_pp_valid = 1'b0;
        freq_period_raw = 32'sd0; freq_valid = 1'b0;
        phase_valid = 1'b0;
        active_p_raw = 32'sd0;    reactive_q_raw = 32'sd0;
        apparent_s_raw = 32'sd0;  power_factor_raw = 32'sd0;
        power_metrics_valid = 1'b0;
        run_case("第三组",
                 32'sd0, 32'sd0, 32'sd0, 32'sd0, 32'sd0,
                 32'sd0, 32'sd0, 32'sd0, 32'sd0, 32'sd0);

        if (errors == 0) begin
            $display("PASS: time_x100_normalizer");
        end else begin
            $display("FAIL: time_x100_normalizer，共 %0d 处不符", errors);
            $fatal(1, "time_x100_normalizer 用例未通过");
        end
        $finish;
    end

    initial begin
        #WATCHDOG_NS;
        $display("FAIL: 仿真看门狗超时");
        $fatal(1, "仿真超时");
    end

endmodule
