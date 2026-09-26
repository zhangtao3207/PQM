`timescale 1ns / 1ps

/*
 * 模块: tb_freq_metrics_raw_calc
 * 功能:
 *   freq_metrics_raw_calc 的单元测试平台：从一帧 0~500 次谐波结果流里提取
 *   THD、基波占比、基波相位、DC 占比与前五大谐波次数列表。
 *
 *   帧的定义：order 0 是 DC（同时承担新一帧的累加器清零），order 1 是基波，
 *   order >= 2 且 present 才算失真项。帧内每一项由 s_harmonic_fire 单周期脉冲驱动，
 *   帧尾用 s_harmonic_last 标记。
 *
 *   第一帧（4 个失真项）：
 *     order:   0(DC)      1(基波)     2        3        4        5(帧尾)
 *     u_mag:   -          1000        300      400      100      200
 *     i_mag:   -          2000        50       700      20       900
 *     u_pct:   100        9000
 *     i_pct:   200        8000
 *     phase:               -3000
 *   失真项平方和 u = 90000+160000+10000+40000 = 300000 -> sqrt=547
 *               i = 2500+490000+400+810000   = 1302900 -> sqrt=1141
 *   THD u = 547*10000/1000 = 5470 (% x100)；THD i = 1141*10000/2000 = 5705
 *   前五大 U：400(3) > 300(2) > 200(5) > 100(4) -> 列表 3,2,5,4,0，共 4 项
 *   前五大 I：900(5) > 700(3) > 50(2)  > 20(4)  -> 列表 5,3,2,4,0，共 4 项
 *
 *   第二帧（含 present=0 的项、i_mag=0 的项、基波相位无效、不足 5 个失真项）：
 *     order 2 present=0（整项跳过）；order 3 u_mag=800 / i_mag=0；
 *     order 4 u_mag=100 / i_mag=300（帧尾）
 *   失真项平方和 u = 640000+10000 = 650000 -> sqrt=806；i = 90000 -> 300
 *   THD u = 806*10000/2000 = 4030；THD i = 300*10000/1000 = 3000
 *   前五大 U：800(3) > 100(4) -> 3,4,0,0,0，共 2 项
 *   前五大 I：300(4) -> 4,0,0,0,0，共 1 项
 */

module tb_freq_metrics_raw_calc;

    localparam integer CLK_PERIOD  = 10;      // 100 MHz
    localparam integer WATCHDOG_NS = 5000000; // 5 ms 兜底（含 THD 的开方与除法）

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg enable = 1'b1;
    reg s_harmonic_fire = 1'b0;
    reg s_harmonic_last = 1'b0;
    reg [8:0] s_harmonic_order = 9'd0;
    reg s_harmonic_present = 1'b0;
    reg [16:0] s_u_mag = 17'd0;
    reg [16:0] s_i_mag = 17'd0;
    reg [15:0] s_u_pct_x100 = 16'd0;
    reg [15:0] s_i_pct_x100 = 16'd0;
    reg s_phase_diff_valid = 1'b0;
    reg signed [15:0] s_phase_diff_deg_x100 = 16'sd0;

    wire               raw_result_commit_toggle;
    wire [31:0]        thd_u_raw_x100;
    wire [31:0]        thd_i_raw_x100;
    wire               thd_u_valid;
    wire               thd_i_valid;
    wire [31:0]        u1_mag_raw_x100;
    wire [31:0]        i1_mag_raw_x100;
    wire               u1_mag_valid;
    wire               i1_mag_valid;
    wire signed [31:0] phase1_raw_x100;
    wire               phase1_valid;
    wire [31:0]        dc_u_raw_x100;
    wire [31:0]        dc_i_raw_x100;
    wire               dc_u_valid;
    wire               dc_i_valid;
    wire               dh_order_u_valid;
    wire               dh_order_i_valid;
    wire [44:0]        dh_order_u_list_raw;
    wire [44:0]        dh_order_i_list_raw;
    wire [2:0]         dh_order_u_count_raw;
    wire [2:0]         dh_order_i_count_raw;
    wire               metrics_valid;

    integer errors = 0;
    integer i;
    integer toggle_baseline;
    reg     ok;

    always #(CLK_PERIOD / 2) clk = ~clk;

    freq_metrics_raw_calc dut (
        .clk                     (clk),
        .rst_n                   (rst_n),
        .enable                  (enable),
        .s_harmonic_fire         (s_harmonic_fire),
        .s_harmonic_last         (s_harmonic_last),
        .s_harmonic_order        (s_harmonic_order),
        .s_harmonic_present      (s_harmonic_present),
        .s_u_mag                 (s_u_mag),
        .s_i_mag                 (s_i_mag),
        .s_u_pct_x100            (s_u_pct_x100),
        .s_i_pct_x100            (s_i_pct_x100),
        .s_phase_diff_valid      (s_phase_diff_valid),
        .s_phase_diff_deg_x100   (s_phase_diff_deg_x100),
        .raw_result_commit_toggle(raw_result_commit_toggle),
        .thd_u_raw_x100          (thd_u_raw_x100),
        .thd_i_raw_x100          (thd_i_raw_x100),
        .thd_u_valid             (thd_u_valid),
        .thd_i_valid             (thd_i_valid),
        .u1_mag_raw_x100         (u1_mag_raw_x100),
        .i1_mag_raw_x100         (i1_mag_raw_x100),
        .u1_mag_valid            (u1_mag_valid),
        .i1_mag_valid            (i1_mag_valid),
        .phase1_raw_x100         (phase1_raw_x100),
        .phase1_valid            (phase1_valid),
        .dc_u_raw_x100           (dc_u_raw_x100),
        .dc_i_raw_x100           (dc_i_raw_x100),
        .dc_u_valid              (dc_u_valid),
        .dc_i_valid              (dc_i_valid),
        .dh_order_u_valid        (dh_order_u_valid),
        .dh_order_i_valid        (dh_order_i_valid),
        .dh_order_u_list_raw     (dh_order_u_list_raw),
        .dh_order_i_list_raw     (dh_order_i_list_raw),
        .dh_order_u_count_raw    (dh_order_u_count_raw),
        .dh_order_i_count_raw    (dh_order_i_count_raw),
        .metrics_valid           (metrics_valid)
    );

    task send_item;
        input [8:0]         order;
        input               present;
        input [16:0]        u_mag;
        input [16:0]        i_mag;
        input [15:0]        u_pct;
        input [15:0]        i_pct;
        input               phase_valid;
        input signed [15:0] phase;
        input               last;
        begin
            @(negedge clk);
            s_harmonic_order      = order;
            s_harmonic_present    = present;
            s_u_mag               = u_mag;
            s_i_mag               = i_mag;
            s_u_pct_x100          = u_pct;
            s_i_pct_x100          = i_pct;
            s_phase_diff_valid    = phase_valid;
            s_phase_diff_deg_x100 = phase;
            s_harmonic_last       = last;
            s_harmonic_fire       = 1'b1;
            @(negedge clk);
            s_harmonic_fire       = 1'b0;
            s_harmonic_last       = 1'b0;
            @(negedge clk);
        end
    endtask

    // 等 raw_result_commit_toggle 翻转，表示一帧 raw 指标已提交
    task wait_commit;
        input [127:0] tag;
        begin
            toggle_baseline = raw_result_commit_toggle;
            ok = 1'b0;
            for (i = 0; i < 100000 && !ok; i = i + 1) begin
                @(negedge clk);
                if (raw_result_commit_toggle !== toggle_baseline) ok = 1'b1;
            end
            if (!ok) begin
                $display("FAIL: %0s 等不到 raw_result_commit_toggle 翻转", tag);
                errors = errors + 1;
            end
        end
    endtask

    task check32;
        input [31:0] actual;
        input [31:0] expected;
        input [127:0] tag;
        begin
            if (actual !== expected) begin
                $display("FAIL: %0s = %0d，期望 %0d", tag, actual, expected);
                errors = errors + 1;
            end
        end
    endtask

    task send_frame1;
        begin
            send_item(9'd0, 1'b1, 17'd0,    17'd0,    16'd100,  16'd200,  1'b0, 16'sd0,    1'b0);
            send_item(9'd1, 1'b1, 17'd1000, 17'd2000, 16'd9000, 16'd8000, 1'b1, -16'sd3000, 1'b0);
            send_item(9'd2, 1'b1, 17'd300,  17'd50,   16'd0,    16'd0,    1'b0, 16'sd0,    1'b0);
            send_item(9'd3, 1'b1, 17'd400,  17'd700,  16'd0,    16'd0,    1'b0, 16'sd0,    1'b0);
            send_item(9'd4, 1'b1, 17'd100,  17'd20,   16'd0,    16'd0,    1'b0, 16'sd0,    1'b0);
            send_item(9'd5, 1'b1, 17'd200,  17'd900,  16'd0,    16'd0,    1'b0, 16'sd0,    1'b1);
        end
    endtask

    task send_frame2;
        begin
            send_item(9'd0, 1'b1, 17'd0,    17'd0,    16'd50,   16'd60,   1'b0, 16'sd0, 1'b0);
            send_item(9'd1, 1'b1, 17'd2000, 17'd1000, 16'd9500, 16'd9000, 1'b0, 16'sd0, 1'b0);
            // present=0：整项不参与统计，也不算失真项
            send_item(9'd2, 1'b0, 17'd7777, 17'd7777, 16'd0,    16'd0,    1'b0, 16'sd0, 1'b0);
            // i_mag=0：i 路平方和为 0、也不进电流前五列表
            send_item(9'd3, 1'b1, 17'd800,  17'd0,    16'd0,    16'd0,    1'b0, 16'sd0, 1'b0);
            send_item(9'd4, 1'b1, 17'd100,  17'd300,  16'd0,    16'd0,    1'b0, 16'sd0, 1'b1);
        end
    endtask

    task check_frame1;
        begin
            if (metrics_valid !== 1'b1) begin
                $display("FAIL: 第一帧提交后 metrics_valid 应为 1");
                errors = errors + 1;
            end

            check32(thd_u_raw_x100, 32'd5470, "第一帧 thd_u_raw_x100");
            check32(thd_i_raw_x100, 32'd5705, "第一帧 thd_i_raw_x100");
            check32(u1_mag_raw_x100, 32'd9000, "第一帧 u1_mag_raw_x100");
            check32(i1_mag_raw_x100, 32'd8000, "第一帧 i1_mag_raw_x100");
            check32(dc_u_raw_x100, 32'd100, "第一帧 dc_u_raw_x100");
            check32(dc_i_raw_x100, 32'd200, "第一帧 dc_i_raw_x100");
            if (phase1_raw_x100 !== -32'sd3000) begin
                $display("FAIL: 第一帧 phase1_raw_x100=%0d，期望 -3000", phase1_raw_x100);
                errors = errors + 1;
            end
            if (thd_u_valid !== 1'b1 || thd_i_valid !== 1'b1) begin
                $display("FAIL: 第一帧 thd_u_valid=%0b thd_i_valid=%0b，均应为 1", thd_u_valid, thd_i_valid);
                errors = errors + 1;
            end
            if (u1_mag_valid !== 1'b1 || i1_mag_valid !== 1'b1 || phase1_valid !== 1'b1 ||
                dc_u_valid !== 1'b1 || dc_i_valid !== 1'b1 ||
                dh_order_u_valid !== 1'b1 || dh_order_i_valid !== 1'b1) begin
                $display("FAIL: 第一帧有效标志不符（u1=%0b i1=%0b ph=%0b dcu=%0b dci=%0b dhu=%0b dhi=%0b）",
                         u1_mag_valid, i1_mag_valid, phase1_valid, dc_u_valid, dc_i_valid,
                         dh_order_u_valid, dh_order_i_valid);
                errors = errors + 1;
            end

            if (dh_order_u_count_raw !== 3'd4) begin
                $display("FAIL: 第一帧 dh_order_u_count_raw=%0d，期望 4", dh_order_u_count_raw);
                errors = errors + 1;
            end
            if (dh_order_i_count_raw !== 3'd4) begin
                $display("FAIL: 第一帧 dh_order_i_count_raw=%0d，期望 4", dh_order_i_count_raw);
                errors = errors + 1;
            end
            if (dh_order_u_list_raw[44:36] !== 9'd3 || dh_order_u_list_raw[35:27] !== 9'd2 ||
                dh_order_u_list_raw[26:18] !== 9'd5 || dh_order_u_list_raw[17:9]  !== 9'd4 ||
                dh_order_u_list_raw[8:0]   !== 9'd0) begin
                $display("FAIL: 第一帧 U 前五列表= %0d,%0d,%0d,%0d,%0d，期望 3,2,5,4,0",
                         dh_order_u_list_raw[44:36], dh_order_u_list_raw[35:27],
                         dh_order_u_list_raw[26:18], dh_order_u_list_raw[17:9],
                         dh_order_u_list_raw[8:0]);
                errors = errors + 1;
            end
            if (dh_order_i_list_raw[44:36] !== 9'd5 || dh_order_i_list_raw[35:27] !== 9'd3 ||
                dh_order_i_list_raw[26:18] !== 9'd2 || dh_order_i_list_raw[17:9]  !== 9'd4 ||
                dh_order_i_list_raw[8:0]   !== 9'd0) begin
                $display("FAIL: 第一帧 I 前五列表= %0d,%0d,%0d,%0d,%0d，期望 5,3,2,4,0",
                         dh_order_i_list_raw[44:36], dh_order_i_list_raw[35:27],
                         dh_order_i_list_raw[26:18], dh_order_i_list_raw[17:9],
                         dh_order_i_list_raw[8:0]);
                errors = errors + 1;
            end
        end
    endtask

    task check_frame2;
        begin
            check32(thd_u_raw_x100, 32'd4030, "第二帧 thd_u_raw_x100");
            check32(thd_i_raw_x100, 32'd3000, "第二帧 thd_i_raw_x100");
            check32(u1_mag_raw_x100, 32'd9500, "第二帧 u1_mag_raw_x100");
            check32(i1_mag_raw_x100, 32'd9000, "第二帧 i1_mag_raw_x100");
            check32(dc_u_raw_x100, 32'd50, "第二帧 dc_u_raw_x100");
            check32(dc_i_raw_x100, 32'd60, "第二帧 dc_i_raw_x100");
            if (phase1_raw_x100 !== 32'sd0) begin
                $display("FAIL: 第二帧 phase1_raw_x100=%0d，期望 0", phase1_raw_x100);
                errors = errors + 1;
            end
            if (phase1_valid !== 1'b0) begin
                $display("FAIL: 第二帧基波相位无效，phase1_valid 应为 0");
                errors = errors + 1;
            end
            if (dh_order_u_count_raw !== 3'd2) begin
                $display("FAIL: 第二帧 dh_order_u_count_raw=%0d，期望 2", dh_order_u_count_raw);
                errors = errors + 1;
            end
            if (dh_order_i_count_raw !== 3'd1) begin
                $display("FAIL: 第二帧 dh_order_i_count_raw=%0d，期望 1", dh_order_i_count_raw);
                errors = errors + 1;
            end
            if (dh_order_u_list_raw[44:36] !== 9'd3 || dh_order_u_list_raw[35:27] !== 9'd4 ||
                dh_order_u_list_raw[26:18] !== 9'd0 || dh_order_u_list_raw[17:9]  !== 9'd0 ||
                dh_order_u_list_raw[8:0]   !== 9'd0) begin
                $display("FAIL: 第二帧 U 前五列表= %0d,%0d,%0d,%0d,%0d，期望 3,4,0,0,0",
                         dh_order_u_list_raw[44:36], dh_order_u_list_raw[35:27],
                         dh_order_u_list_raw[26:18], dh_order_u_list_raw[17:9],
                         dh_order_u_list_raw[8:0]);
                errors = errors + 1;
            end
            if (dh_order_i_list_raw[44:36] !== 9'd4 || dh_order_i_list_raw[35:27] !== 9'd0 ||
                dh_order_i_list_raw[26:18] !== 9'd0 || dh_order_i_list_raw[17:9]  !== 9'd0 ||
                dh_order_i_list_raw[8:0]   !== 9'd0) begin
                $display("FAIL: 第二帧 I 前五列表= %0d,%0d,%0d,%0d,%0d，期望 4,0,0,0,0",
                         dh_order_i_list_raw[44:36], dh_order_i_list_raw[35:27],
                         dh_order_i_list_raw[26:18], dh_order_i_list_raw[17:9],
                         dh_order_i_list_raw[8:0]);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (10) @(posedge clk);

        // ---------------- 第一帧 ----------------
        send_frame1;
        wait_commit("第一帧");
        check_frame1;

        // ---------------- 第二帧 ----------------
        send_frame2;
        wait_commit("第二帧");
        check_frame2;

        // ---------------- enable=0 时有效标志清空 ----------------
        enable = 1'b0;
        repeat (20) @(posedge clk);
        if (metrics_valid !== 1'b0 || thd_u_valid !== 1'b0 || thd_i_valid !== 1'b0 ||
            u1_mag_valid !== 1'b0 || i1_mag_valid !== 1'b0 || phase1_valid !== 1'b0 ||
            dc_u_valid !== 1'b0 || dc_i_valid !== 1'b0 ||
            dh_order_u_valid !== 1'b0 || dh_order_i_valid !== 1'b0) begin
            $display("FAIL: enable=0 时各有效标志应全部清空");
            errors = errors + 1;
        end
        enable = 1'b1;
        repeat (10) @(posedge clk);

        if (errors == 0) begin
            $display("PASS: freq_metrics_raw_calc");
        end else begin
            $display("FAIL: freq_metrics_raw_calc，共 %0d 处不符", errors);
            $fatal(1, "freq_metrics_raw_calc 用例未通过");
        end
        $finish;
    end

    initial begin
        #WATCHDOG_NS;
        $display("FAIL: 仿真看门狗超时");
        $fatal(1, "仿真超时");
    end

endmodule
