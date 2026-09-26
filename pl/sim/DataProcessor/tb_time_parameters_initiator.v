`timescale 1ns / 1ps

/*
 * 模块: tb_time_parameters_initiator
 * 功能:
 *   time_parameters_initiator 的单元测试平台：它把 p2p、相位、频率、RMS/平均有功
 *   这五路 raw 测量在同一采样窗口内并行启动，等 RMS 也稳定后再启动功率衍生模块。
 *
 *   本用例喂一路 64 点周期的整数正弦（幅度 10000、零点 32768，U/I 同相），
 *   窗口取 256 点 = 4 个整周期。各子模块的数值行为已在各自用例里逐条验证过，
 *   这里验证的是**集成与调度**：
 *     - 五路子模块是否都被启动、六路 raw 结果是否都拿到 valid
 *     - 调度顺序：只有 RMS 与相位都有效时才会进入功率 stage
 *     - 数值量级是否符合预期（正弦幅度 10000 的理论值）
 *     - 没有采样时不得给出 done，busy 必须保持
 *
 *   理论值（64 点正弦表实测）：
 *     p2p         = 20000
 *     RMS         = sqrt(50000461.5) = 7071
 *     平均有功    = 50000461（同相，等于均方值）
 *     频率周期    = 64 个采样/时钟
 *     相位偏移    = 0（U/I 同相）
 */

module tb_time_parameters_initiator;

    localparam integer CLK_PERIOD  = 10;      // 100 MHz
    localparam integer WATCHDOG_NS = 5000000; // 5 ms 兜底
    localparam integer FRAME       = 256;     // 窗口点数（4 个整周期）
    localparam integer MAX_FRAME   = 512;
    localparam [15:0]  ZERO_CODE   = 16'd32768;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg start = 1'b0;
    reg u_sample_valid = 1'b0;
    reg [15:0] u_sample_code = 16'd0;
    reg [15:0] u_zero_code = ZERO_CODE;
    reg u_zero_valid = 1'b1;
    reg i_sample_valid = 1'b0;
    reg [15:0] i_sample_code = 16'd0;
    reg [15:0] i_zero_code = ZERO_CODE;
    reg i_zero_valid = 1'b1;

    wire               busy;
    wire               done;
    wire signed [31:0] u_rms_raw;
    wire signed [31:0] i_rms_raw;
    wire               rms_valid;
    wire signed [31:0] u_pp_raw;
    wire               u_pp_valid;
    wire signed [31:0] i_pp_raw;
    wire               i_pp_valid;
    wire signed [31:0] phase_offset_raw;
    wire signed [31:0] phase_period_raw;
    wire               phase_valid;
    wire signed [31:0] freq_period_raw;
    wire               freq_valid;
    wire signed [31:0] active_p_raw;
    wire signed [31:0] reactive_q_raw;
    wire signed [31:0] apparent_s_raw;
    wire signed [31:0] power_factor_raw;
    wire               power_metrics_valid;

    integer errors = 0;
    integer i;
    reg     ok;

    // 64 点正弦码表：32768 + round(10000*sin(2*pi*n/64))
    reg [15:0] sine_code [0:63];
    integer    n;

    always #(CLK_PERIOD / 2) clk = ~clk;

    time_parameters_initiator #(
        .SAMPLE_WIDTH          (16),
        .MAX_FRAME_SAMPLES     (MAX_FRAME),
        .MEASURE_FRAME_SAMPLES (FRAME)
    ) dut (
        .clk(clk), .rst_n(rst_n), .start(start),
        .u_sample_valid(u_sample_valid), .u_sample_code(u_sample_code),
        .u_zero_code(u_zero_code), .u_zero_valid(u_zero_valid),
        .i_sample_valid(i_sample_valid), .i_sample_code(i_sample_code),
        .i_zero_code(i_zero_code), .i_zero_valid(i_zero_valid),
        .busy(busy), .done(done),
        .u_rms_raw(u_rms_raw), .i_rms_raw(i_rms_raw), .rms_valid(rms_valid),
        .u_pp_raw(u_pp_raw), .u_pp_valid(u_pp_valid),
        .i_pp_raw(i_pp_raw), .i_pp_valid(i_pp_valid),
        .phase_offset_raw(phase_offset_raw), .phase_period_raw(phase_period_raw),
        .phase_valid(phase_valid),
        .freq_period_raw(freq_period_raw), .freq_valid(freq_valid),
        .active_p_raw(active_p_raw), .reactive_q_raw(reactive_q_raw),
        .apparent_s_raw(apparent_s_raw), .power_factor_raw(power_factor_raw),
        .power_metrics_valid(power_metrics_valid)
    );

    // 采样计数器：本用例里 sample_valid 恒为高，所以每拍推进一个采样点。
    always @(posedge clk) begin
        if (u_sample_valid)
            n <= n + 1;
    end

    always @(*) begin
        u_sample_code = sine_code[n[5:0]];
        i_sample_code = sine_code[n[5:0]];   // U/I 同相
    end

    task init_sine;
        begin
            sine_code[ 0]=16'd32768; sine_code[ 1]=16'd33748; sine_code[ 2]=16'd34719; sine_code[ 3]=16'd35671;
            sine_code[ 4]=16'd36595; sine_code[ 5]=16'd37482; sine_code[ 6]=16'd38324; sine_code[ 7]=16'd39112;
            sine_code[ 8]=16'd39839; sine_code[ 9]=16'd40498; sine_code[10]=16'd41083; sine_code[11]=16'd41587;
            sine_code[12]=16'd42007; sine_code[13]=16'd42337; sine_code[14]=16'd42576; sine_code[15]=16'd42720;
            sine_code[16]=16'd42768; sine_code[17]=16'd42720; sine_code[18]=16'd42576; sine_code[19]=16'd42337;
            sine_code[20]=16'd42007; sine_code[21]=16'd41587; sine_code[22]=16'd41083; sine_code[23]=16'd40498;
            sine_code[24]=16'd39839; sine_code[25]=16'd39112; sine_code[26]=16'd38324; sine_code[27]=16'd37482;
            sine_code[28]=16'd36595; sine_code[29]=16'd35671; sine_code[30]=16'd34719; sine_code[31]=16'd33748;
            sine_code[32]=16'd32768; sine_code[33]=16'd31788; sine_code[34]=16'd30817; sine_code[35]=16'd29865;
            sine_code[36]=16'd28941; sine_code[37]=16'd28054; sine_code[38]=16'd27212; sine_code[39]=16'd26424;
            sine_code[40]=16'd25697; sine_code[41]=16'd25038; sine_code[42]=16'd24453; sine_code[43]=16'd23949;
            sine_code[44]=16'd23529; sine_code[45]=16'd23199; sine_code[46]=16'd22960; sine_code[47]=16'd22816;
            sine_code[48]=16'd22768; sine_code[49]=16'd22816; sine_code[50]=16'd22960; sine_code[51]=16'd23199;
            sine_code[52]=16'd23529; sine_code[53]=16'd23949; sine_code[54]=16'd24453; sine_code[55]=16'd25038;
            sine_code[56]=16'd25697; sine_code[57]=16'd26424; sine_code[58]=16'd27212; sine_code[59]=16'd28054;
            sine_code[60]=16'd28941; sine_code[61]=16'd29865; sine_code[62]=16'd30817; sine_code[63]=16'd31788;
        end
    endtask

    task check_range;
        input signed [31:0] actual;
        input signed [31:0] lo;
        input signed [31:0] hi;
        input [255:0] tag;
        begin
            if (actual < lo || actual > hi) begin
                $display("FAIL: %0s = %0d，期望落在 [%0d, %0d]", tag, actual, lo, hi);
                errors = errors + 1;
            end
        end
    endtask

    task check_flag;
        input actual;
        input expected;
        input [255:0] tag;
        begin
            if (actual !== expected) begin
                $display("FAIL: %0s = %0b，期望 %0b", tag, actual, expected);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        init_sine;
        n = 0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);

        // ---------------- 场景 1：正常窗口，六路 raw 都应有效 ----------------
        u_sample_valid = 1'b1;
        i_sample_valid = 1'b1;

        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        if (busy !== 1'b1) begin
            $display("FAIL: start 之后 busy 应为 1");
            errors = errors + 1;
        end

        ok = 1'b0;
        for (i = 0; i < 20000 && !ok; i = i + 1) begin
            @(negedge clk);
            if (done) ok = 1'b1;
        end

        if (!ok) begin
            $display("FAIL: 正常窗口下等不到 done");
            errors = errors + 1;
        end
        u_sample_valid = 1'b0;
        i_sample_valid = 1'b0;
        repeat (4) @(negedge clk);

        if (busy !== 1'b0) begin
            $display("FAIL: done 之后 busy 应回到 0");
            errors = errors + 1;
        end

        check_flag(rms_valid,           1'b1, "rms_valid");
        check_flag(u_pp_valid,          1'b1, "u_pp_valid");
        check_flag(i_pp_valid,          1'b1, "i_pp_valid");
        check_flag(phase_valid,         1'b1, "phase_valid");
        check_flag(freq_valid,          1'b1, "freq_valid");
        check_flag(power_metrics_valid, 1'b1, "power_metrics_valid");

        check_range(u_rms_raw,      32'sd6900,    32'sd7250,    "u_rms_raw");
        check_range(i_rms_raw,      32'sd6900,    32'sd7250,    "i_rms_raw");
        check_range(u_pp_raw,       32'sd19500,   32'sd20500,   "u_pp_raw");
        check_range(i_pp_raw,       32'sd19500,   32'sd20500,   "i_pp_raw");
        check_range(freq_period_raw,32'sd62,      32'sd66,      "freq_period_raw");
        check_range(phase_period_raw,32'sd62,     32'sd66,      "phase_period_raw");
        check_range(phase_offset_raw,-32'sd3,     32'sd3,       "phase_offset_raw");
        check_range(active_p_raw,   32'sd48000000,32'sd52000000,"active_p_raw");
        check_range(apparent_s_raw, 32'sd48000000,32'sd52000000,"apparent_s_raw");
        check_range(power_factor_raw,32'sd9500,   32'sd10000,   "power_factor_raw");
        check_range(reactive_q_raw, -32'sd5000000, 32'sd5000000,"reactive_q_raw");

        // ---------------- 场景 2：没有采样时不得给出 done ----------------
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);

        u_sample_valid = 1'b0;
        i_sample_valid = 1'b0;

        @(negedge clk);
        start = 1'b1;
        @(negedge clk);
        start = 1'b0;

        for (i = 0; i < 2000; i = i + 1) begin
            @(negedge clk);
            if (done) begin
                $display("FAIL: 没有采样时第 %0d 拍就给出了 done", i);
                errors = errors + 1;
                i = 2000;
            end
        end
        if (busy !== 1'b1) begin
            $display("FAIL: 无采样期间 busy 应保持为 1");
            errors = errors + 1;
        end

        // 复位后必须能恢复
        rst_n = 1'b0;
        repeat (5) @(posedge clk);
        if (busy !== 1'b0) begin
            $display("FAIL: 复位后 busy 应为 0");
            errors = errors + 1;
        end
        rst_n = 1'b1;

        if (errors == 0) begin
            $display("PASS: time_parameters_initiator");
        end else begin
            $display("FAIL: time_parameters_initiator，共 %0d 处不符", errors);
            $fatal(1, "time_parameters_initiator 用例未通过");
        end
        $finish;
    end

    initial begin
        #WATCHDOG_NS;
        $display("FAIL: 仿真看门狗超时");
        $fatal(1, "仿真超时");
    end

endmodule
