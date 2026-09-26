`timescale 1ns / 1ps

/*
 * 模块: tb_ui_rms_measure
 * 功能:
 *   ui_rms_measure 的单元测试平台：同窗口内做去零点 RMS 与平均有功功率。
 *
 *   为什么用方波做激励：±A 各占一半的方波，均方值恰好等于 A²，开方就是 A；
 *   同相的电压/电流方波，乘积均值恰好等于 A_u·A_i。这些值可以精确手算，
 *   不依赖浮点近似。
 *
 *   输入码的约定：采样码是**偏移二进制**（0x8000 为零点），模块内部再做去零点。
 *
 *   五个场景：
 *     1) 同相：u=±1000, i=±500, 8 点  -> u_rms=1000, i_rms=500, active_p=500000
 *     2) 反相电流：i 取反              -> active_p=-500000，RMS 不变
 *     3) 零点参考无效                  -> 退回中心码 0x8000 作参考，结果同场景 1
 *     4) 窗口长度为 0                  -> 只给 done，不给 valid
 *     5) RMS 上限裁剪：零参考码 0x0000，采样 0xFFFF/0x0000 -> u_rms 裁到 32767
 */

module tb_ui_rms_measure;

    localparam integer CLK_PERIOD  = 10;      // 100 MHz
    localparam integer WATCHDOG_NS = 2000000; // 2 ms 兜底
    localparam integer N_WIDTH     = 13;      // MAX_FRAME_SAMPLES=8192 时的 N_WIDTH
    localparam [15:0]  ZERO_CODE   = 16'h8000;
    localparam [15:0]  U_HIGH      = 16'h83E8;  // 0x8000 + 1000
    localparam [15:0]  U_LOW       = 16'h7C18;  // 0x8000 - 1000
    localparam [15:0]  I_HIGH      = 16'h81F4;  // 0x8000 +  500
    localparam [15:0]  I_LOW       = 16'h7E0C;  // 0x8000 -  500

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg start = 1'b0;
    reg [N_WIDTH-1:0] sample_count_n = {N_WIDTH{1'b0}};
    reg sample_valid = 1'b0;
    reg [15:0] u_sample_code = 16'h0000;
    reg [15:0] u_zero_code = ZERO_CODE;
    reg u_zero_valid = 1'b1;
    reg [15:0] i_sample_code = 16'h0000;
    reg [15:0] i_zero_code = ZERO_CODE;
    reg i_zero_valid = 1'b1;

    wire               busy;
    wire               done;
    wire               rms_valid;
    wire               active_p_valid;
    wire               config_error;
    wire               frame_overflow;
    wire signed [31:0] u_rms_raw;
    wire signed [31:0] i_rms_raw;
    wire signed [31:0] active_p_raw;

    integer errors = 0;
    integer i;
    integer waited;
    reg rms_valid_at_done;
    reg ap_valid_at_done;

    always #(CLK_PERIOD / 2) clk = ~clk;

    ui_rms_measure dut (
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
        .rms_valid(rms_valid),
        .active_p_valid(active_p_valid),
        .config_error(config_error),
        .frame_overflow(frame_overflow),
        .u_rms_raw(u_rms_raw),
        .i_rms_raw(i_rms_raw),
        .active_p_raw(active_p_raw)
    );

    // 在时钟低电平期间改变激励，避免与 posedge 采样撞在同一个时间步里
    task issue_start;
        input [N_WIDTH-1:0] count;
        begin
            @(negedge clk);
            sample_count_n = count;
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
        end
    endtask

    task send_pair;
        input [15:0] u_code;
        input [15:0] i_code;
        begin
            @(negedge clk);
            u_sample_code = u_code;
            i_sample_code = i_code;
            sample_valid  = 1'b1;
            @(negedge clk);
            sample_valid  = 1'b0;
        end
    endtask

    task wait_done;
        input integer max_cycles;
        output integer cycles;
        reg seen;
        begin
            seen = 1'b0;
            cycles = 0;
            rms_valid_at_done = 1'b0;
            ap_valid_at_done  = 1'b0;
            for (i = 0; i < max_cycles && !seen; i = i + 1) begin
                @(posedge clk);
                cycles = cycles + 1;
                if (done) begin
                    seen = 1'b1;
                    rms_valid_at_done = rms_valid;
                    ap_valid_at_done  = active_p_valid;
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

    // 送 4 个正半周 + 4 个负半周（同相或反相由 u_code/i_code 组合决定）
    task send_square8;
        input [15:0] u_pos;
        input [15:0] u_neg;
        input [15:0] i_pos;
        input [15:0] i_neg;
        begin
            send_pair(u_pos, i_pos);
            send_pair(u_pos, i_pos);
            send_pair(u_pos, i_pos);
            send_pair(u_pos, i_pos);
            send_pair(u_neg, i_neg);
            send_pair(u_neg, i_neg);
            send_pair(u_neg, i_neg);
            send_pair(u_neg, i_neg);
        end
    endtask

    initial begin
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        if (busy !== 1'b0 || done !== 1'b0 || rms_valid !== 1'b0) begin
            $display("FAIL: 复位后 busy/done/rms_valid 应为 0");
            errors = errors + 1;
        end

        // ---------------- 场景 1：同相 ----------------
        issue_start(13'd8);
        repeat (3) @(posedge clk);
        if (busy !== 1'b1) begin
            $display("FAIL: 启动后 busy=%b，期望 1", busy);
            errors = errors + 1;
        end
        send_square8(U_HIGH, U_LOW, I_HIGH, I_LOW);
        wait_done(4000, waited);
        repeat (3) @(posedge clk);
        if (waited < 0) begin
            $display("FAIL: 场景 1 没有等到 done");
            errors = errors + 1;
        end else begin
            if (!rms_valid_at_done || !ap_valid_at_done) begin
                $display("FAIL: 场景 1 done 没有与 rms_valid/active_p_valid 同拍");
                errors = errors + 1;
            end
            check_value(u_rms_raw,    32'sd1000,   "场景1 u_rms_raw");
            check_value(i_rms_raw,    32'sd500,    "场景1 i_rms_raw");
            check_value(active_p_raw, 32'sd500000, "场景1 active_p_raw");
            if (busy !== 1'b0) begin
                $display("FAIL: 场景 1 结束后 busy 仍为 1");
                errors = errors + 1;
            end
        end
        repeat (10) @(posedge clk);

        // ---------------- 场景 2：电流反相 ----------------
        issue_start(13'd8);
        send_square8(U_HIGH, U_LOW, I_LOW, I_HIGH);
        wait_done(4000, waited);
        repeat (3) @(posedge clk);
        if (waited < 0) begin
            $display("FAIL: 场景 2 没有等到 done");
            errors = errors + 1;
        end else begin
            check_value(u_rms_raw,    32'sd1000,    "场景2 u_rms_raw");
            check_value(i_rms_raw,    32'sd500,     "场景2 i_rms_raw");
            check_value(active_p_raw, -32'sd500000, "场景2 active_p_raw");
        end
        repeat (10) @(posedge clk);

        // ---------------- 场景 3：零点参考无效，退回中心码 ----------------
        u_zero_valid = 1'b0;
        i_zero_valid = 1'b0;
        issue_start(13'd8);
        send_square8(U_HIGH, U_LOW, I_HIGH, I_LOW);
        wait_done(4000, waited);
        repeat (3) @(posedge clk);
        if (waited < 0) begin
            $display("FAIL: 场景 3 没有等到 done");
            errors = errors + 1;
        end else begin
            check_value(u_rms_raw,    32'sd1000,   "场景3 u_rms_raw");
            check_value(active_p_raw, 32'sd500000, "场景3 active_p_raw");
        end
        u_zero_valid = 1'b1;
        i_zero_valid = 1'b1;
        repeat (10) @(posedge clk);

        // ---------------- 场景 4：窗口长度为 0 ----------------
        issue_start(13'd0);
        wait_done(4000, waited);
        repeat (3) @(posedge clk);
        if (waited < 0) begin
            $display("FAIL: 场景 4 没有等到 done");
            errors = errors + 1;
        end else begin
            if (rms_valid_at_done) begin
                $display("FAIL: 场景 4 窗口长度为 0，不应给出 rms_valid");
                errors = errors + 1;
            end
        end
        repeat (10) @(posedge clk);

        // ---------------- 场景 5：RMS 上限裁剪 ----------------
        // 零参考码取 0x0000，采样在 0xFFFF 与 0x0000 之间跳变，去零点后幅度达 65535，
        // 计算出的 RMS 约 46340，超过 32767 上限，应被裁到 32767。
        u_zero_code = 16'h0000;
        i_zero_code = ZERO_CODE;
        issue_start(13'd8);
        send_pair(16'hFFFF, ZERO_CODE);
        send_pair(16'hFFFF, ZERO_CODE);
        send_pair(16'hFFFF, ZERO_CODE);
        send_pair(16'hFFFF, ZERO_CODE);
        send_pair(16'h0000, ZERO_CODE);
        send_pair(16'h0000, ZERO_CODE);
        send_pair(16'h0000, ZERO_CODE);
        send_pair(16'h0000, ZERO_CODE);
        wait_done(4000, waited);
        repeat (3) @(posedge clk);
        if (waited < 0) begin
            $display("FAIL: 场景 5 没有等到 done");
            errors = errors + 1;
        end else begin
            check_value(u_rms_raw,    32'sd32767, "场景5 u_rms_raw 应被裁剪到上限");
            check_value(i_rms_raw,    32'sd0,     "场景5 i_rms_raw（电流无交流分量）");
            check_value(active_p_raw, 32'sd0,     "场景5 active_p_raw（电流无交流分量）");
        end
        u_zero_code = ZERO_CODE;

        if (config_error !== 1'b0 || frame_overflow !== 1'b0) begin
            $display("FAIL: config_error/frame_overflow 应固定为 0");
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PASS: ui_rms_measure");
        end else begin
            $display("FAIL: ui_rms_measure，共 %0d 处不符", errors);
            $fatal(1, "ui_rms_measure 用例未通过");
        end
        $finish;
    end

    initial begin
        #WATCHDOG_NS;
        $display("FAIL: 仿真看门狗超时");
        $fatal(1, "仿真超时");
    end

endmodule
