`timescale 1ns / 1ps

/*
 * 模块: tb_magnitude_calc
 * 功能:
 *   magnitude_calc 的单元测试平台：对每个频点算 real^2+imag^2 与 sqrt，
 *   并把频点索引、帧尾标志和原始 real/imag 对齐透传。
 *
 *   激励取勾股数，期望值全是精确整数：
 *     (3,4)   -> 25,   5
 *     (5,12)  -> 169,  13
 *     (6,8)   -> 100,  10
 *     (100,0) -> 10000,100
 *   负号不影响平方和（(-3,-4) 与 (3,4) 同结果）。
 *
 *   三个场景：
 *     1) 连送两个频点（第二个带帧尾），检查透传字段、幅值、以及帧计数与帧尾脉冲
 *     2) enable=0 时输入被丢弃（ready 保持高），且不产生输出
 *     3) 另一组频点，检查不同量级下的开方结果
 */

module tb_magnitude_calc;

    localparam integer CLK_PERIOD  = 10;      // 100 MHz
    localparam integer WATCHDOG_NS = 2000000; // 2 ms 兜底

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg enable = 1'b1;
    reg s_bin_valid = 1'b0;
    reg s_bin_last = 1'b0;
    reg [10:0] s_bin_index = 11'd0;
    reg signed [15:0] s_u1_real = 16'sd0;
    reg signed [15:0] s_u1_imag = 16'sd0;
    reg signed [15:0] s_u2_real = 16'sd0;
    reg signed [15:0] s_u2_imag = 16'sd0;
    reg m_mag_ready = 1'b0;

    wire               s_bin_ready;
    wire               m_mag_valid;
    wire               m_mag_last;
    wire [10:0]        m_bin_index;
    wire signed [15:0] m_u1_real;
    wire signed [15:0] m_u1_imag;
    wire signed [15:0] m_u2_real;
    wire signed [15:0] m_u2_imag;
    wire [32:0]        m_u1_mag_sq;
    wire [16:0]        m_u1_mag;
    wire [32:0]        m_u2_mag_sq;
    wire [16:0]        m_u2_mag;
    wire               calc_busy;
    wire               mag_frame_done;
    wire [15:0]        mag_frame_count;

    integer errors = 0;
    integer i;
    integer frame_done_pulses;
    reg     ok;

    always #(CLK_PERIOD / 2) clk = ~clk;

    magnitude_calc dut (
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable),
        .s_bin_valid(s_bin_valid),
        .s_bin_ready(s_bin_ready),
        .s_bin_last(s_bin_last),
        .s_bin_index(s_bin_index),
        .s_u1_real(s_u1_real),
        .s_u1_imag(s_u1_imag),
        .s_u2_real(s_u2_real),
        .s_u2_imag(s_u2_imag),
        .m_mag_ready(m_mag_ready),
        .m_mag_valid(m_mag_valid),
        .m_mag_last(m_mag_last),
        .m_bin_index(m_bin_index),
        .m_u1_real(m_u1_real),
        .m_u1_imag(m_u1_imag),
        .m_u2_real(m_u2_real),
        .m_u2_imag(m_u2_imag),
        .m_u1_mag_sq(m_u1_mag_sq),
        .m_u1_mag(m_u1_mag),
        .m_u2_mag_sq(m_u2_mag_sq),
        .m_u2_mag(m_u2_mag),
        .calc_busy(calc_busy),
        .mag_frame_done(mag_frame_done),
        .mag_frame_count(mag_frame_count)
    );

    always @(posedge clk) begin
        if (rst_n && mag_frame_done)
            frame_done_pulses <= frame_done_pulses + 1;
    end

    task check_eq32;
        input [32:0] actual;
        input [32:0] expected;
        input [127:0] tag;
        begin
            if (actual !== expected) begin
                $display("FAIL: %0s = %0d，期望 %0d", tag, actual, expected);
                errors = errors + 1;
            end
        end
    endtask

    task check_eq17;
        input [16:0] actual;
        input [16:0] expected;
        input [127:0] tag;
        begin
            if (actual !== expected) begin
                $display("FAIL: %0s = %0d，期望 %0d", tag, actual, expected);
                errors = errors + 1;
            end
        end
    endtask

    // 送一个频点并消费它的输出；期望值由调用方给出
    task send_and_check;
        input [10:0]        index;
        input               last;
        input signed [15:0] ur;
        input signed [15:0] ui;
        input signed [15:0] ir;
        input signed [15:0] ii;
        input [32:0]        exp_u1_sq;
        input [16:0]        exp_u1_mag;
        input [32:0]        exp_u2_sq;
        input [16:0]        exp_u2_mag;
        begin
            // 等本模块可以接收（在时钟低电平期间采样组合就绪）
            ok = 1'b0;
            for (i = 0; i < 400 && !ok; i = i + 1) begin
                @(negedge clk);
                if (s_bin_ready) ok = 1'b1;
            end
            if (!ok) begin
                $display("FAIL: s_bin_ready 一直不拉高，无法送入频点");
                errors = errors + 1;
            end

            // 同一拍把输入摆上，下一个 posedge 完成握手
            s_bin_index = index;
            s_bin_last  = last;
            s_u1_real    = ur;
            s_u1_imag    = ui;
            s_u2_real    = ir;
            s_u2_imag    = ii;
            s_bin_valid = 1'b1;
            @(negedge clk);
            s_bin_valid = 1'b0;

            // 等输出
            ok = 1'b0;
            for (i = 0; i < 400 && !ok; i = i + 1) begin
                @(posedge clk);
                if (m_mag_valid) ok = 1'b1;
            end
            if (!ok) begin
                $display("FAIL: m_mag_valid 未出现");
                errors = errors + 1;
            end else begin
                if (m_bin_index !== index) begin
                    $display("FAIL: m_bin_index=%0d，期望 %0d", m_bin_index, index);
                    errors = errors + 1;
                end
                if (m_mag_last !== last) begin
                    $display("FAIL: m_mag_last=%b，期望 %b", m_mag_last, last);
                    errors = errors + 1;
                end
                if (m_u1_real !== ur || m_u1_imag !== ui) begin
                    $display("FAIL: U1 real/imag 透传不符：%0d/%0d，期望 %0d/%0d",
                             m_u1_real, m_u1_imag, ur, ui);
                    errors = errors + 1;
                end
                if (m_u2_real !== ir || m_u2_imag !== ii) begin
                    $display("FAIL: U2 real/imag 透传不符：%0d/%0d，期望 %0d/%0d",
                             m_u2_real, m_u2_imag, ir, ii);
                    errors = errors + 1;
                end
                check_eq32(m_u1_mag_sq, exp_u1_sq,  "U1幅值平方和");
                check_eq17(m_u1_mag,    exp_u1_mag, "U1幅值");
                check_eq32(m_u2_mag_sq, exp_u2_sq,  "U2幅值平方和");
                check_eq17(m_u2_mag,    exp_u2_mag, "U2幅值");
            end

            // 消费掉这条输出
            @(negedge clk);
            m_mag_ready = 1'b1;
            @(negedge clk);
            m_mag_ready = 1'b0;
        end
    endtask

    initial begin
        frame_done_pulses = 0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;
        repeat (5) @(posedge clk);

        if (mag_frame_count !== 16'd0) begin
            $display("FAIL: 复位后 mag_frame_count 应为 0");
            errors = errors + 1;
        end

        // ---------------- 场景 1：两个频点，第二个带帧尾 ----------------
        send_and_check(11'd1, 1'b0, 16'sd3,  16'sd4,  16'sd5,  16'sd12,
                       33'd25,  17'd5,  33'd169,  17'd13);
        send_and_check(11'd2, 1'b1, -16'sd3, -16'sd4, 16'sd0,  16'sd0,
                       33'd25,  17'd5,  33'd0,    17'd0);

        repeat (10) @(posedge clk);
        if (mag_frame_count !== 16'd1) begin
            $display("FAIL: 场景 1 结束后 mag_frame_count=%0d，期望 1", mag_frame_count);
            errors = errors + 1;
        end
        if (frame_done_pulses !== 1) begin
            $display("FAIL: 场景 1 的 mag_frame_done 脉冲次数=%0d，期望 1", frame_done_pulses);
            errors = errors + 1;
        end

        // ---------------- 场景 2：enable=0 时丢弃输入 ----------------
        enable = 1'b0;
        repeat (3) @(negedge clk);
        if (s_bin_ready !== 1'b1) begin
            $display("FAIL: enable=0 时 s_bin_ready 应保持为 1");
            errors = errors + 1;
        end
        s_bin_index = 11'd7;
        s_bin_last  = 1'b0;
        s_u1_real    = 16'sd6;
        s_u1_imag    = 16'sd8;
        s_u2_real    = 16'sd6;
        s_u2_imag    = 16'sd8;
        s_bin_valid = 1'b1;
        @(negedge clk);
        s_bin_valid = 1'b0;
        repeat (30) @(posedge clk);
        if (m_mag_valid !== 1'b0) begin
            $display("FAIL: enable=0 时不应产生输出");
            errors = errors + 1;
        end
        enable = 1'b1;
        repeat (3) @(negedge clk);

        // ---------------- 场景 3：另一组频点 ----------------
        send_and_check(11'd3, 1'b0, 16'sd6,   16'sd8,  16'sd100, 16'sd0,
                       33'd100,  17'd10, 33'd10000, 17'd100);
        send_and_check(11'd4, 1'b1, 16'sd0,   16'sd0,  16'sd20,  16'sd21,
                       33'd0,    17'd0,  33'd841,   17'd29);

        repeat (10) @(posedge clk);
        if (mag_frame_count !== 16'd2) begin
            $display("FAIL: 场景 3 结束后 mag_frame_count=%0d，期望 2", mag_frame_count);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PASS: magnitude_calc");
        end else begin
            $display("FAIL: magnitude_calc，共 %0d 处不符", errors);
            $fatal(1, "magnitude_calc 用例未通过");
        end
        $finish;
    end

    initial begin
        frame_done_pulses = 0;
        #WATCHDOG_NS;
        $display("FAIL: 仿真看门狗超时");
        $fatal(1, "仿真超时");
    end

endmodule
