`timescale 1ns / 1ps

/*
 * 模块: tb_freq_thd_raw_calc
 * 功能:
 *   freq_thd_raw_calc 的单元测试平台：由 2 次及以上谐波幅值平方和与基波幅值算出
 *   U1/U2 总谐波畸变率 THD，输出单位是 % x100。
 *
 *   计算链：sqrt(平方和) -> *10000 -> /基波幅值，最后钳位到 99999。
 *
 *   用例：
 *     1) 正常：u sqrt=3、基波 100 -> 300；i sqrt=4、基波 200 -> 200
 *     2) U1基波无效（有效标志应跟着为 0、结果旁路为 0），U2正常 -> 1000
 *     3) 基波幅值为 0 -> 旁路为 0 但 valid 仍跟随基波有效标志；U2平方和为 0
 *        （开方根为 0）同样旁路为 0
 *     4) 溢出钳位：u sqrt=1000、基波 1 -> 10,000,000 应被钳到 99999；
 *        同时给一个刚低于钳位门限的U2值 90000，确认没被误钳
 *
 *   U1/U2 两路各自独立判断旁路与有效标志，用例 2、3 专门覆盖这种不对称。
 */

module tb_freq_thd_raw_calc;

    localparam integer CLK_PERIOD  = 10;      // 100 MHz
    localparam integer WATCHDOG_NS = 2000000; // 2 ms 兜底
    localparam [31:0]  THD_CLIP    = 32'd99999;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg start = 1'b0;
    reg [45:0] u1_harmonic_square_sum = 46'd0;
    reg [45:0] u2_harmonic_square_sum = 46'd0;
    reg [16:0] u1_fund_mag = 17'd0;
    reg [16:0] u2_fund_mag = 17'd0;
    reg u1_fund_valid = 1'b0;
    reg u2_fund_valid = 1'b0;

    wire        busy;
    wire        done;
    wire [31:0] thd_u1_raw_x100;
    wire [31:0] thd_u2_raw_x100;
    wire        thd_u1_valid;
    wire        thd_u2_valid;

    integer errors = 0;
    integer i;
    reg     ok;

    always #(CLK_PERIOD / 2) clk = ~clk;

    freq_thd_raw_calc dut (
        .clk                  (clk),
        .rst_n                (rst_n),
        .start                (start),
        .u1_harmonic_square_sum(u1_harmonic_square_sum),
        .u2_harmonic_square_sum(u2_harmonic_square_sum),
        .u1_fund_mag           (u1_fund_mag),
        .u2_fund_mag           (u2_fund_mag),
        .u1_fund_valid         (u1_fund_valid),
        .u2_fund_valid         (u2_fund_valid),
        .busy                 (busy),
        .done                 (done),
        .thd_u1_raw_x100       (thd_u1_raw_x100),
        .thd_u2_raw_x100       (thd_u2_raw_x100),
        .thd_u1_valid          (thd_u1_valid),
        .thd_u2_valid          (thd_u2_valid)
    );

    task run_case;
        input [45:0]   u1_sum;
        input [45:0]   u2_sum;
        input [16:0]   u1_fund;
        input [16:0]   u2_fund;
        input          u1_fv;
        input          u2_fv;
        input [31:0]   exp_u1;
        input [31:0]   exp_u2;
        input          exp_uv;
        input          exp_iv;
        input [255:0]  tag;
        begin
            @(negedge clk);
            u1_harmonic_square_sum = u1_sum;
            u2_harmonic_square_sum = u2_sum;
            u1_fund_mag            = u1_fund;
            u2_fund_mag            = u2_fund;
            u1_fund_valid          = u1_fv;
            u2_fund_valid          = u2_fv;
            start                 = 1'b1;
            @(negedge clk);
            start                 = 1'b0;

            if (busy !== 1'b1) begin
                $display("FAIL: %0s start 之后 busy 应为 1", tag);
                errors = errors + 1;
            end

            // 等 done（单周期脉冲，可在 negedge 采到）
            ok = 1'b0;
            for (i = 0; i < 5000 && !ok; i = i + 1) begin
                @(negedge clk);
                if (done) ok = 1'b1;
            end

            if (!ok) begin
                $display("FAIL: %0s 等不到 done", tag);
                errors = errors + 1;
            end else begin
                @(negedge clk);
                if (thd_u1_raw_x100 !== exp_u1) begin
                    $display("FAIL: %0s thd_u_raw_x100=%0d，期望 %0d", tag, thd_u1_raw_x100, exp_u1);
                    errors = errors + 1;
                end
                if (thd_u2_raw_x100 !== exp_u2) begin
                    $display("FAIL: %0s thd_i_raw_x100=%0d，期望 %0d", tag, thd_u2_raw_x100, exp_u2);
                    errors = errors + 1;
                end
                if (thd_u1_valid !== exp_uv) begin
                    $display("FAIL: %0s thd_u_valid=%0b，期望 %0b", tag, thd_u1_valid, exp_uv);
                    errors = errors + 1;
                end
                if (thd_u2_valid !== exp_iv) begin
                    $display("FAIL: %0s thd_i_valid=%0b，期望 %0b", tag, thd_u2_valid, exp_iv);
                    errors = errors + 1;
                end
            end

            repeat (4) @(negedge clk);
            if (busy !== 1'b0) begin
                $display("FAIL: %0s 完成后 busy 应回到 0", tag);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);

        // 1) 正常：3/100 -> 300，4/200 -> 200
        run_case(46'd9, 46'd16, 17'd100, 17'd200, 1'b1, 1'b1,
                 32'd300, 32'd200, 1'b1, 1'b1, "正常");

        // 2) U1基波无效 -> 旁路为 0 且 valid=0；U2 5/50 -> 1000
        run_case(46'd100, 46'd25, 17'd50, 17'd50, 1'b0, 1'b1,
                 32'd0, 32'd1000, 1'b0, 1'b1, "U1基波无效");

        // 3) 基波幅值为 0 -> 旁路为 0、valid 跟随基波有效标志；U2根为 0 同样旁路
        run_case(46'd9, 46'd0, 17'd0, 17'd100, 1'b1, 1'b1,
                 32'd0, 32'd0, 1'b1, 1'b1, "基波为 0 / 根为 0");

        // 4) 钳位：1000/1 -> 10,000,000 钳到 99999；9/1 -> 90000 不钳
        run_case(46'd1000000, 46'd81, 17'd1, 17'd1, 1'b1, 1'b1,
                 THD_CLIP, 32'd90000, 1'b1, 1'b1, "溢出钳位与门限下沿");

        if (errors == 0) begin
            $display("PASS: freq_thd_raw_calc");
        end else begin
            $display("FAIL: freq_thd_raw_calc，共 %0d 处不符", errors);
            $fatal(1, "freq_thd_raw_calc 用例未通过");
        end
        $finish;
    end

    initial begin
        #WATCHDOG_NS;
        $display("FAIL: 仿真看门狗超时");
        $fatal(1, "仿真超时");
    end

endmodule
