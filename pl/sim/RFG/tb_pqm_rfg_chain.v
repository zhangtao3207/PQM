`timescale 1ns / 1ps

/*
 * 模块: tb_pqm_rfg_chain
 * 功能:
 *   RFG 频域整链验证：pqm_rfg_frontend -> pqm_rfg_scale -> magnitude_calc
 *   -> harmonic_stats，并直接核对**下游真正消费的量：谐波占比**。
 *
 *   这一步是"能否完全移出 FFT"的关键验收：
 *   后两个模块（magnitude_calc / harmonic_stats）是原 FFT 链上已验证过的
 *   模块，本用例证明它们**原样**就能吃 RFG 的流，且占比与解析值一致。
 *
 *   激励（同 tb_pqm_rfg_frontend，512 点 = 一个 50 Hz 周期）：
 *     u = 1000*cos(w n) + 400*cos(3w n)   -> 幅值比 1000 : 400，总 1400
 *     i =  800*sin(w n)                   -> 只有 1 次
 *   解析占比（x100）：
 *     u 1 次 = 1000/1400*10000 = 7142.9 -> 缩放截断后约 7139
 *     u 3 次 =  400/1400*10000 = 2857.1 -> 约 2861
 *     i 1 次 = 100%（单一谐波）
 *     0 次 = 0（零均值）；ABI 收敛后只输出 0..64 共 65 条，65 次以上不再出现在窗口内
 */

module tb_pqm_rfg_chain;

    localparam integer CLK_PERIOD  = 10;
    localparam integer WATCHDOG_NS = 20000000;
    localparam integer C_N         = 512;
    localparam integer C_K         = 64;
    localparam integer C_L         = 4;
    localparam integer C_D         = 1;
    localparam integer SHIFT       = 10;
    localparam integer HARM_ORDERS = 65;       // harmonic_stats 输出 0..64（ABI 条目 65 条）
    localparam integer FUND_BIN    = 1;        // 与 freq_analysis_top 一致

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    always #(CLK_PERIOD/2) clk = ~clk;

    reg        i_start = 1'b0;
    reg        i_sample_valid = 1'b0;
    reg [15:0] i_sample_u = 16'd0;
    reg [15:0] i_sample_i = 16'd0;
    wire [15:0] i_zero_code = 16'd0;

    // frontend
    wire        fe_item_valid, fe_item_ready;
    wire [8:0]  fe_order;
    wire signed [31:0] fe_u_real, fe_u_imag, fe_i_real, fe_i_imag;
    wire        fe_item_last, fe_frame_done, fe_sample_ready, fe_overflow, fe_channel_error;

    // scale（形状与 fft_result_receiver 一致）
    wire        sc_bin_valid, sc_bin_ready, sc_bin_last;
    wire [10:0] sc_bin_index;
    wire signed [15:0] sc_u_real, sc_u_imag, sc_i_real, sc_i_imag;
    wire        sc_frame_done;

    // magnitude
    wire        mag_valid, mag_last;
    wire        hs_s_mag_ready;      // harmonic_stats 的 s_mag_ready -> 幅值模块的 m_mag_ready
    wire [10:0] mag_bin_index;
    wire signed [15:0] mag_u_real, mag_u_imag, mag_i_real, mag_i_imag;
    wire [32:0] mag_u_mag_sq, mag_i_mag_sq;
    wire [16:0] mag_u_mag, mag_i_mag;
    wire        mag_busy, mag_frame_done;
    wire [15:0] mag_frame_count;

    // harmonic stats
    wire        hs_valid;
    reg         hs_ready = 1'b1;
    wire        hs_last;
    wire [8:0]  hs_order;
    wire        hs_present;
    wire signed [15:0] hs_u_real, hs_u_imag, hs_i_real, hs_i_imag;
    wire [16:0] hs_u_mag, hs_i_mag;
    wire [15:0] hs_u_pct, hs_i_pct;
    wire        hs_busy, hs_capture_done, hs_frame_done;
    wire [15:0] hs_frame_count;
    wire [31:0] hs_u_total, hs_i_total;

    reg [15:0] u_tab [0:C_N-1];
    reg [15:0] i_tab [0:C_N-1];

    integer errors = 0;
    integer i;
    integer hs_cnt = 0;
    integer upct [0:HARM_ORDERS-1];
    integer ipct [0:HARM_ORDERS-1];
    integer upres [0:HARM_ORDERS-1];
    reg     hs_done_seen = 1'b0;
    integer hs_last_order = -1;

    pqm_rfg_frontend #(.C_N(C_N), .C_K(C_K), .C_L(C_L), .C_D(C_D)) u_fe (
        .clk(clk), .rst_n(rst_n),
        .i_start(i_start), .i_sample_valid(i_sample_valid),
        .i_sample_u(i_sample_u), .i_sample_i(i_sample_i), .i_zero_code(i_zero_code),
        .o_sample_ready(fe_sample_ready),
        .o_item_valid(fe_item_valid), .i_item_ready(fe_item_ready), .o_order(fe_order),
        .o_u_real(fe_u_real), .o_u_imag(fe_u_imag),
        .o_i_real(fe_i_real), .o_i_imag(fe_i_imag),
        .o_item_last(fe_item_last), .o_frame_done(fe_frame_done),
        .o_overflow(fe_overflow), .o_channel_error(fe_channel_error)
    );

    pqm_rfg_scale #(.C_K(C_K), .SHIFT(SHIFT)) u_sc (
        .clk(clk), .rst_n(rst_n), .i_start(i_start),
        .i_item_valid(fe_item_valid), .o_item_ready(fe_item_ready), .i_order(fe_order),
        .i_u_real(fe_u_real), .i_u_imag(fe_u_imag),
        .i_i_real(fe_i_real), .i_i_imag(fe_i_imag), .i_item_last(fe_item_last),
        .m_bin_valid(sc_bin_valid), .m_bin_ready(sc_bin_ready),
        .m_bin_last(sc_bin_last), .m_bin_index(sc_bin_index),
        .m_u_real(sc_u_real), .m_u_imag(sc_u_imag),
        .m_i_real(sc_i_real), .m_i_imag(sc_i_imag),
        .o_frame_done(sc_frame_done)
    );

    magnitude_calc u_mag (
        .clk(clk), .rst_n(rst_n), .enable(1'b1),
        .s_bin_valid(sc_bin_valid), .s_bin_ready(sc_bin_ready),
        .s_bin_last(sc_bin_last), .s_bin_index(sc_bin_index),
        .s_u_real(sc_u_real), .s_u_imag(sc_u_imag),
        .s_i_real(sc_i_real), .s_i_imag(sc_i_imag),
        .m_mag_ready(hs_s_mag_ready), .m_mag_valid(mag_valid), .m_mag_last(mag_last),
        .m_bin_index(mag_bin_index),
        .m_u_real(mag_u_real), .m_u_imag(mag_u_imag),
        .m_i_real(mag_i_real), .m_i_imag(mag_i_imag),
        .m_u_mag_sq(mag_u_mag_sq), .m_u_mag(mag_u_mag),
        .m_i_mag_sq(mag_i_mag_sq), .m_i_mag(mag_i_mag),
        .calc_busy(mag_busy), .mag_frame_done(mag_frame_done),
        .mag_frame_count(mag_frame_count)
    );

    harmonic_stats #(.FUND_BIN(FUND_BIN[10:0])) u_hs (
        .clk(clk), .rst_n(rst_n), .enable(1'b1),
        .s_mag_valid(mag_valid), .s_mag_ready(hs_s_mag_ready),
        .s_mag_last(mag_last), .s_bin_index(mag_bin_index),
        .s_u_real(mag_u_real), .s_u_imag(mag_u_imag),
        .s_i_real(mag_i_real), .s_i_imag(mag_i_imag),
        .s_u_mag(mag_u_mag), .s_i_mag(mag_i_mag),
        .m_harmonic_ready(hs_ready),
        .m_harmonic_valid(hs_valid), .m_harmonic_last(hs_last),
        .m_harmonic_order(hs_order), .m_harmonic_present(hs_present),
        .m_u_real(hs_u_real), .m_u_imag(hs_u_imag),
        .m_i_real(hs_i_real), .m_i_imag(hs_i_imag),
        .m_u_mag(hs_u_mag), .m_i_mag(hs_i_mag),
        .m_u_pct_x100(hs_u_pct), .m_i_pct_x100(hs_i_pct),
        .stats_busy(hs_busy), .capture_frame_done(hs_capture_done),
        .harmonic_frame_done(hs_frame_done), .harmonic_frame_count(hs_frame_count),
        .u_total_mag(hs_u_total), .i_total_mag(hs_i_total)
    );

    always @(posedge clk) begin
        if (rst_n && hs_valid && hs_ready) begin
            if (hs_order > HARM_ORDERS - 1) begin
                $display("FAIL: 谐波次数 %0d 超出 ABI 窗口 0..%0d", hs_order, HARM_ORDERS - 1);
                errors = errors + 1;
            end else if (hs_cnt < HARM_ORDERS) begin
                upct[hs_order] = $signed(hs_u_pct);
                ipct[hs_order] = $signed(hs_i_pct);
                upres[hs_order] = {31'd0, hs_present};
            end
            if (hs_last) hs_last_order = hs_order;
            hs_cnt = hs_cnt + 1;
        end
        if (rst_n && hs_frame_done) hs_done_seen <= 1'b1;
    end

    task automatic start_frame;
        integer g;
        begin
            @(negedge clk); i_start = 1'b1;
            @(negedge clk); i_start = 1'b0;
            g = 0;
            while (!fe_sample_ready && g < 200000) begin @(negedge clk); g = g + 1; end
            if (!fe_sample_ready) begin
                $display("FAIL: start 之后 o_sample_ready 一直不拉高");
                errors = errors + 1;
            end
        end
    endtask

    task automatic drive_samples;
        integer k; integer g;
        begin
            k = 0; g = 0;
            while (k < C_N && g < 4000000) begin
                @(negedge clk);
                g = g + 1;
                i_start = 1'b0;
                if (fe_sample_ready) begin
                    i_sample_valid = 1'b1;
                    i_sample_u     = u_tab[k];
                    i_sample_i     = i_tab[k];
                    k = k + 1;
                end else begin
                    i_sample_valid = 1'b0;
                end
            end
            @(negedge clk);
            i_sample_valid = 1'b0;
        end
    endtask

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
        repeat (5) @(posedge clk);

        start_frame;
        hs_cnt = 0;
        drive_samples;

        i = 0;
        while (!(hs_done_seen && hs_cnt >= HARM_ORDERS) && i < 4000000) begin
            @(posedge clk); i = i + 1;
        end
        repeat (20) @(posedge clk);

        $display("");
        $display("========== RFG 整链：frontend -> scale -> magnitude -> harmonic_stats ==========");
        $display("谐波输出项数 = %0d（期望 %0d），帧计数 = %0d，frame_done = %0b",
                 hs_cnt, HARM_ORDERS, hs_frame_count, hs_done_seen);
        $display("次数 :  u_pct  i_pct  present");
        for (i = 0; i <= 5; i = i + 1)
            $display("  %0d  : %6d %6d     %0d", i, upct[i], ipct[i], upres[i]);
        $display("  64 : %6d %6d     %0d", upct[64], ipct[64], upres[64]);
        $display("  帧尾 order = %0d（期望 64）", hs_last_order);
        $display("u_total_mag = %0d，i_total_mag = %0d", hs_u_total, hs_i_total);

        // 结构
        if (hs_cnt != HARM_ORDERS) begin
            $display("FAIL: 谐波输出项数 %0d，期望 %0d", hs_cnt, HARM_ORDERS);
            errors = errors + 1;
        end
        if (hs_frame_count !== 16'd1) begin
            $display("FAIL: 谐波帧计数 %0d，期望 1", hs_frame_count);
            errors = errors + 1;
        end
        if (fe_channel_error !== 1'b0 || fe_overflow !== 1'b0) begin
            $display("FAIL: channel_error=%0b overflow=%0b", fe_channel_error, fe_overflow);
            errors = errors + 1;
        end

        // 占比（下游真正消费的量）
        check_val(upct[0],    0,   1, "0 次 u_pct（零均值）");
        check_val(ipct[0],    0,   1, "0 次 i_pct（零均值）");
        check_val(upct[1], 7139,  60, "1 次 u_pct");
        check_val(upct[3], 2861,  60, "3 次 u_pct");
        check_val(ipct[1], 9999,  20, "1 次 i_pct（单一谐波应≈10000）");
        for (i = 2; i <= C_K; i = i + 1) begin
            if (i == 3) continue;
            // RFG 的量化噪声底约 = 1 LSB（>>10 之后），单次占比 1*10000/total(~401) ≈ 24，
            // 所以静默次的门限放到 30（即允许 1 LSB 残留），这是精度特性不是缺陷。
            check_val(upct[i], 0, 30, "静默次 u_pct");
            check_val(ipct[i], 0, 30, "静默次 i_pct");
        end
        // ABI 收敛后不再输出 65..500 次条目，改为确认帧尾标志恰落在 64 次。
        check_val(hs_last_order, 64, 0, "帧尾 order");

        if (errors == 0) begin
            $display("");
            $display("PASS: pqm_rfg_chain");
        end else begin
            $display("FAIL: pqm_rfg_chain，共 %0d 处不符", errors);
            $fatal(1, "pqm_rfg_chain 用例未通过");
        end
        $finish;
    end

    initial begin
        #WATCHDOG_NS;
        $display("FAIL: 仿真看门狗超时");
        $fatal(1, "仿真超时");
    end

endmodule
