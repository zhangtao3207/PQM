`timescale 1ns / 1ps

/*
 * 模块: tb_harmonic_stats
 * 功能:
 *   harmonic_stats 的单元测试平台：接收一帧正半谱幅值结果，
 *   累计 0~500 次谐波的总幅值，再把每一项占总幅值的百分比逐项输出。
 *
 *   测试帧（FUND_BIN=1，bin 号即谐波次数）：
 *     bin0: u_mag=0    i_mag=0
 *     bin1: u_mag=1000 i_mag=2000
 *     bin2: u_mag=500  i_mag=0
 *     bin3: u_mag=250  i_mag=500   （帧尾）
 *   总幅值 u=1750、i=2500。百分比为 mag*10000/total 的整除结果：
 *     order1: u=10000000/1750=5714   i=20000000/2500=8000
 *     order2: u= 5000000/1750=2857   i 幅值为 0 -> 旁路 -> 0
 *     order3: u= 2500000/1750=1428   i= 5000000/2500=2000
 *     order0: 被捕获但幅值为 0 -> 旁路 -> 0
 *     order4..500: 帧标签不匹配 -> present=0、百分比 0
 *
 *   三个场景：
 *     1) 一帧 501 项的完整输出：抽查 order 0/1/2/3/4/500 的 present 与百分比，
 *        并检查总幅值、帧计数、帧尾标志与 capture_frame_done
 *     2) enable=0 时不再产生有效输出
 *     3) 第二帧（同样内容）应能正常跑完，帧计数递增到 2
 */

module tb_harmonic_stats;

    localparam integer CLK_PERIOD  = 10;      // 100 MHz
    localparam integer WATCHDOG_NS = 20000000; // 20 ms 兜底（501 项逐项输出较慢）
    localparam integer MAX_ORDER   = 500;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg enable = 1'b1;
    reg s_mag_valid = 1'b0;
    reg s_mag_last = 1'b0;
    reg [10:0] s_bin_index = 11'd0;
    reg signed [15:0] s_u_real = 16'sd0;
    reg signed [15:0] s_u_imag = 16'sd0;
    reg signed [15:0] s_i_real = 16'sd0;
    reg signed [15:0] s_i_imag = 16'sd0;
    reg [16:0] s_u_mag = 17'd0;
    reg [16:0] s_i_mag = 17'd0;
    reg m_harmonic_ready = 1'b0;

    wire               s_mag_ready;
    wire               m_harmonic_valid;
    wire               m_harmonic_last;
    wire [8:0]         m_harmonic_order;
    wire               m_harmonic_present;
    wire signed [15:0] m_u_real;
    wire signed [15:0] m_u_imag;
    wire signed [15:0] m_i_real;
    wire signed [15:0] m_i_imag;
    wire [16:0]        m_u_mag;
    wire [16:0]        m_i_mag;
    wire [15:0]        m_u_pct_x100;
    wire [15:0]        m_i_pct_x100;
    wire               stats_busy;
    wire               capture_frame_done;
    wire               harmonic_frame_done;
    wire [15:0]        harmonic_frame_count;
    wire [31:0]        u_total_mag;
    wire [31:0]        i_total_mag;

    integer errors = 0;
    integer i;
    integer out_index;
    integer capture_done_pulses;
    reg [31:0] u_total_latched;
    reg [31:0] i_total_latched;
    reg     ok;
    always #(CLK_PERIOD / 2) clk = ~clk;

    harmonic_stats dut (
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable),
        .s_mag_valid(s_mag_valid),
        .s_mag_ready(s_mag_ready),
        .s_mag_last(s_mag_last),
        .s_bin_index(s_bin_index),
        .s_u_real(s_u_real),
        .s_u_imag(s_u_imag),
        .s_i_real(s_i_real),
        .s_i_imag(s_i_imag),
        .s_u_mag(s_u_mag),
        .s_i_mag(s_i_mag),
        .m_harmonic_ready(m_harmonic_ready),
        .m_harmonic_valid(m_harmonic_valid),
        .m_harmonic_last(m_harmonic_last),
        .m_harmonic_order(m_harmonic_order),
        .m_harmonic_present(m_harmonic_present),
        .m_u_real(m_u_real),
        .m_u_imag(m_u_imag),
        .m_i_real(m_i_real),
        .m_i_imag(m_i_imag),
        .m_u_mag(m_u_mag),
        .m_i_mag(m_i_mag),
        .m_u_pct_x100(m_u_pct_x100),
        .m_i_pct_x100(m_i_pct_x100),
        .stats_busy(stats_busy),
        .capture_frame_done(capture_frame_done),
        .harmonic_frame_done(harmonic_frame_done),
        .harmonic_frame_count(harmonic_frame_count),
        .u_total_mag(u_total_mag),
        .i_total_mag(i_total_mag)
    );

    always @(posedge clk) begin
        if (rst_n && capture_frame_done) begin
            capture_done_pulses <= capture_done_pulses + 1;
            // capture_frame_done 拉高的下一拍，累加结果仍保持有效（到 ST_IDLE 才清零）
            u_total_latched     <= u_total_mag;
            i_total_latched     <= i_total_mag;
        end
    end

    task send_bin;
        input [10:0]        index;
        input               last;
        input signed [15:0] ur;
        input signed [15:0] ui;
        input signed [15:0] ir;
        input signed [15:0] ii;
        input [16:0]        u_mag;
        input [16:0]        i_mag;
        begin
            ok = 1'b0;
            for (i = 0; i < 1200 && !ok; i = i + 1) begin
                @(negedge clk);
                if (s_mag_ready) ok = 1'b1;
            end
            if (!ok) begin
                $display("FAIL: s_mag_ready 一直不拉高");
                errors = errors + 1;
            end
            s_bin_index = index;
            s_mag_last  = last;
            s_u_real    = ur;
            s_u_imag    = ui;
            s_i_real    = ir;
            s_i_imag    = ii;
            s_u_mag     = u_mag;
            s_i_mag     = i_mag;
            s_mag_valid = 1'b1;
            @(negedge clk);
            s_mag_valid = 1'b0;
        end
    endtask

    // 送同样的四 bin 帧
    task send_frame;
        begin
            send_bin(11'd0, 1'b0, 16'sd0, 16'sd0, 16'sd0, 16'sd0, 17'd0,    17'd0);
            send_bin(11'd1, 1'b0, 16'sd1, 16'sd0, 16'sd2, 16'sd0, 17'd1000, 17'd2000);
            send_bin(11'd2, 1'b0, 16'sd0, 16'sd0, 16'sd0, 16'sd0, 17'd500,  17'd0);
            send_bin(11'd3, 1'b1, 16'sd0, 16'sd0, 16'sd1, 16'sd0, 17'd250,  17'd500);
        end
    endtask

    task check16;
        input [15:0] actual;
        input [15:0] expected;
        input [127:0] tag;
        begin
            if (actual !== expected) begin
                $display("FAIL: %0s = %0d，期望 %0d", tag, actual, expected);
                errors = errors + 1;
            end
        end
    endtask

    // 消费一整帧 501 项输出，抽查关键项
    task consume_frame;
        input [127:0] frame_tag_str;
        begin
            for (out_index = 0; out_index <= MAX_ORDER; out_index = out_index + 1) begin
                ok = 1'b0;
                for (i = 0; i < 400 && !ok; i = i + 1) begin
                    @(posedge clk);
                    if (m_harmonic_valid) ok = 1'b1;
                end
                if (!ok) begin
                    $display("FAIL: %0s 第 %0d 项没有等到 m_harmonic_valid", frame_tag_str, out_index);
                    errors = errors + 1;
                end else begin
                    if (m_harmonic_order !== out_index[8:0]) begin
                        $display("FAIL: %0s 第 %0d 项 order=%0d 不符", frame_tag_str, out_index, m_harmonic_order);
                        errors = errors + 1;
                    end
                    case (out_index)
                        1: begin
                            if (m_harmonic_present !== 1'b1) begin
                                $display("FAIL: %0s order1 present 应为 1", frame_tag_str);
                                errors = errors + 1;
                            end
                            check16(m_u_pct_x100, 16'd5714, "order1 u_pct_x100");
                            check16(m_i_pct_x100, 16'd8000, "order1 i_pct_x100");
                        end
                        2: begin
                            check16(m_u_pct_x100, 16'd2857, "order2 u_pct_x100");
                            check16(m_i_pct_x100, 16'd0,    "order2 i_pct_x100（幅值为 0）");
                        end
                        3: begin
                            check16(m_u_pct_x100, 16'd1428, "order3 u_pct_x100");
                            check16(m_i_pct_x100, 16'd2000, "order3 i_pct_x100");
                        end
                        4: begin
                            if (m_harmonic_present !== 1'b0) begin
                                $display("FAIL: %0s order4 未被捕获，present 应为 0", frame_tag_str);
                                errors = errors + 1;
                            end
                            check16(m_u_pct_x100, 16'd0, "order4 u_pct_x100");
                        end
                        MAX_ORDER: begin
                            if (m_harmonic_last !== 1'b1) begin
                                $display("FAIL: %0s order500 应带上帧尾标志", frame_tag_str);
                                errors = errors + 1;
                            end
                        end
                        default: ;
                    endcase
                end

                @(negedge clk);
                m_harmonic_ready = 1'b1;
                @(negedge clk);
                m_harmonic_ready = 1'b0;
            end
        end
    endtask

    initial begin
        capture_done_pulses = 0;
        u_total_latched     = 32'd0;
        i_total_latched     = 32'd0;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;

        // ---------------- 场景 1：第一帧 ----------------
        send_frame;
        consume_frame("第一帧");
        repeat (10) @(posedge clk);
        if (u_total_latched !== 32'd1750) begin
            $display("FAIL: 第一帧 u_total_mag=%0d，期望 1750", u_total_latched);
            errors = errors + 1;
        end
        if (i_total_latched !== 32'd2500) begin
            $display("FAIL: 第一帧 i_total_mag=%0d，期望 2500", i_total_latched);
            errors = errors + 1;
        end

        if (harmonic_frame_count !== 16'd1) begin
            $display("FAIL: 第一帧结束后 harmonic_frame_count=%0d，期望 1", harmonic_frame_count);
            errors = errors + 1;
        end
        if (capture_done_pulses !== 1) begin
            $display("FAIL: capture_frame_done 脉冲次数=%0d，期望 1", capture_done_pulses);
            errors = errors + 1;
        end

        // ---------------- 场景 2：enable=0 时不出结果 ----------------
        enable = 1'b0;
        repeat (20) @(posedge clk);
        if (m_harmonic_valid !== 1'b0) begin
            $display("FAIL: enable=0 时不应有 m_harmonic_valid");
            errors = errors + 1;
        end
        enable = 1'b1;
        repeat (20) @(posedge clk);

        // ---------------- 场景 3：第二帧 ----------------
        send_frame;
        consume_frame("第二帧");
        repeat (10) @(posedge clk);
        if (harmonic_frame_count !== 16'd2) begin
            $display("FAIL: 第二帧结束后 harmonic_frame_count=%0d，期望 2", harmonic_frame_count);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PASS: harmonic_stats");
        end else begin
            $display("FAIL: harmonic_stats，共 %0d 处不符", errors);
            $fatal(1, "harmonic_stats 用例未通过");
        end
        $finish;
    end

    initial begin
        capture_done_pulses = 0;
        #WATCHDOG_NS;
        $display("FAIL: 仿真看门狗超时");
        $fatal(1, "仿真超时");
    end

endmodule
