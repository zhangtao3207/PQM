`timescale 1ns / 1ps

/*
 * 模块: tb_pqm_freq_analysis_rfg
 * 功能:
 *   验证 RFG 版频域顶层（pqm_freq_analysis_rfg）本身：
 *   1) 谐波占比与解析值一致（u = 1 次 1000 + 3 次 400；i = 1 次 800）
 *   2) 1 次谐波的 U-I 相位差绝对值约 9000（i 相对 u 滞后 90 度）
 *   3) 帧节奏：连续跑两帧，filtered_frame_count 递增到 2
 *
 *   采样刻意**自由跑**：i_sample_valid 恒为 1，不看 o_sample_ready。
 *   这模拟真实 ADC（一直在产数据），也顺带验证关键性质：
 *   计算期间被跳过的采样不影响结果 —— 因为每帧仍是连续的 512 个采样点
 *   （= 一个 50 Hz 周期），帧内 DFT 与起点无关。
 */

module tb_pqm_freq_analysis_rfg;

    localparam integer CLK_PERIOD  = 10;
    localparam integer WATCHDOG_NS = 20000000;
    localparam integer C_N         = 512;
    localparam integer C_K         = 64;
    localparam integer HARM_ORDERS = 65;     // harmonic_stats 输出 0..64
    localparam integer FRAMES      = 2;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    reg        i_sample_valid = 1'b1;
    reg [15:0] i_sample_u = 16'd0;
    reg [15:0] i_sample_i = 16'd0;
    wire [15:0] i_u_zero_code = 16'h0000;   // 向量本身已中心化，零点码给 0
    wire        i_u_zero_valid = 1'b1;
    wire [15:0] i_i_zero_code = 16'h0000;
    wire        i_i_zero_valid = 1'b1;
    wire        o_sample_ready;

    reg         i_harmonic_ready = 1'b1;
    wire        m_harmonic_valid, m_harmonic_last, m_harmonic_present;
    wire [8:0]  m_harmonic_order;
    wire signed [15:0] m_u_real, m_u_imag, m_i_real, m_i_imag;
    wire [16:0] m_u_mag, m_i_mag;
    wire [15:0] m_u_pct_x100, m_i_pct_x100;
    wire        m_phase_vector_valid;
    wire signed [32:0] m_phase_dot, m_phase_cross;
    wire        m_phase_diff_valid;
    wire signed [15:0] m_phase_diff_deg_x100;
    wire [15:0] filtered_frame_count;

    reg [15:0] u_tab [0:C_N-1];
    reg [15:0] i_tab [0:C_N-1];

    integer errors = 0;
    integer i;
    integer sample_idx = 0;
    integer frame_no   = 0;
    integer item_in_frame = 0;
    integer upct [0:HARM_ORDERS-1];
    integer ipct [0:HARM_ORDERS-1];
    integer ph1        = 0;
    integer ph1_valid  = 0;
    integer f1_upct1   = 0;
    integer f1_upct3   = 0;
    integer f1_ipct1   = 0;

    pqm_freq_analysis_rfg #(
        .C_N(C_N), .C_K(C_K), .C_L(4), .C_D(1), .SHIFT(10), .HARMONIC_FUND_BIN(9'd1)
    ) dut (
        .clk(clk), .rst_n(rst_n), .enable(1'b1),
        .i_sample_valid(i_sample_valid),
        .i_sample_u(i_sample_u), .i_sample_i(i_sample_i),
        .i_u_zero_code(i_u_zero_code), .i_u_zero_valid(i_u_zero_valid),
        .i_i_zero_code(i_i_zero_code), .i_i_zero_valid(i_i_zero_valid),
        .o_sample_ready(o_sample_ready),
        .i_harmonic_ready(i_harmonic_ready),
        .m_harmonic_valid(m_harmonic_valid), .m_harmonic_last(m_harmonic_last),
        .m_harmonic_order(m_harmonic_order), .m_harmonic_present(m_harmonic_present),
        .m_u_real(m_u_real), .m_u_imag(m_u_imag),
        .m_i_real(m_i_real), .m_i_imag(m_i_imag),
        .m_u_mag(m_u_mag), .m_i_mag(m_i_mag),
        .m_u_pct_x100(m_u_pct_x100), .m_i_pct_x100(m_i_pct_x100),
        .m_phase_vector_valid(m_phase_vector_valid),
        .m_phase_dot(m_phase_dot), .m_phase_cross(m_phase_cross),
        .m_phase_diff_valid(m_phase_diff_valid),
        .m_phase_diff_deg_x100(m_phase_diff_deg_x100),
        .filtered_frame_count(filtered_frame_count)
    );

    // 自由跑的采样：每拍换一个（向量周期 512，与帧长一致）
    // 采样必须**按 ready 推进**：RFG 只认样本序列、不认时间，被跳过的点会破坏
    // "一帧 = 连续 512 点 = 一个周期" 这个前提（自由跑会让谱泄漏）。
    // 真实系统里这一点由输入 FIFO 保证，见 pl/rtl/RFG/README 的说明。
    always @(negedge clk) begin
        i_sample_u = u_tab[sample_idx % C_N];
        i_sample_i = i_tab[sample_idx % C_N];
        sample_idx = sample_idx + 1;   // 自由跑：ADC 一直在产数据，FIFO 负责不丢连续性
    end

    // 收谐波流；第一帧记录关键项
    always @(posedge clk) begin
        if (rst_n && m_harmonic_valid && i_harmonic_ready) begin
            if (frame_no == 0 && item_in_frame < HARM_ORDERS) begin
                upct[m_harmonic_order] = $signed(m_u_pct_x100);
                ipct[m_harmonic_order] = $signed(m_i_pct_x100);
                if (m_harmonic_order == 9'd1) begin
                    f1_upct1 = $signed(m_u_pct_x100);
                    f1_ipct1 = $signed(m_i_pct_x100);
                    ph1_valid = m_phase_diff_valid;
                    ph1 = $signed(m_phase_diff_deg_x100);
                end
                if (m_harmonic_order == 9'd3) f1_upct3 = $signed(m_u_pct_x100);
            end
            item_in_frame = item_in_frame + 1;
            if (m_harmonic_last) begin
                frame_no      = frame_no + 1;
                item_in_frame = 0;
            end
        end
    end

    task check_val;
        input integer actual;
        input integer expected;
        input integer tol;
        input [255:0] tag;
        begin
            if (^actual === 1'bx) begin
                $display("FAIL: %0s = X（未初始化/未驱动）", tag);
                errors = errors + 1;
            end else if (actual < expected - tol || actual > expected + tol) begin
                $display("FAIL: %0s = %0d，期望 %0d ± %0d", tag, actual, expected, tol);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $readmemh("u_q14.hex", u_tab);
        $readmemh("i_q14.hex", i_tab);

        repeat (10) @(posedge clk);
        rst_n = 1'b1;

        i = 0;
        while (frame_no < FRAMES && i < 4000000) begin
            @(posedge clk); i = i + 1;
        end
        repeat (20) @(posedge clk);

        $display("");
        $display("========== RFG 频域顶层（自由跑采样 + 前置 FIFO，%0d 帧） ==========", FRAMES);
        $display("帧数 = %0d（期望 %0d），filtered_frame_count = %0d",
                 frame_no, FRAMES, filtered_frame_count);
        $display("次数 :  u_pct  i_pct");
        for (i = 0; i <= 5; i = i + 1)
            $display("  %0d  : %6d %6d", i, upct[i], ipct[i]);
        $display("1 次相位差 = %0d（valid=%0d），绝对值期望约 9000", ph1, ph1_valid);

        if (frame_no < FRAMES) begin
            $display("FAIL: 只跑完 %0d 帧，期望 %0d", frame_no, FRAMES);
            errors = errors + 1;
        end
        if (filtered_frame_count !== FRAMES[15:0]) begin
            $display("FAIL: filtered_frame_count = %0d，期望 %0d", filtered_frame_count, FRAMES);
            errors = errors + 1;
        end

        check_val(f1_upct1, 7142, 40, "1 次 u_pct");
        check_val(f1_upct3, 2857, 40, "3 次 u_pct");
        check_val(f1_ipct1, 10000, 40, "1 次 i_pct");
        check_val(upct[0],  0, 5, "0 次 u_pct");
        if (ph1_valid !== 1) begin
            $display("FAIL: 1 次相位差 valid 应为 1");
            errors = errors + 1;
        end
        check_val((ph1 < 0) ? -ph1 : ph1, 9000, 200, "1 次相位差绝对值");

        if (errors == 0) begin
            $display("");
            $display("PASS: pqm_freq_analysis_rfg");
        end else begin
            $display("FAIL: pqm_freq_analysis_rfg，共 %0d 处不符", errors);
            $fatal(1, "pqm_freq_analysis_rfg 用例未通过");
        end
        $finish;
    end

    initial begin
        #WATCHDOG_NS;
        $display("FAIL: 仿真看门狗超时");
        $fatal(1, "仿真超时");
    end

endmodule
