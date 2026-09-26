`timescale 1ns / 1ps

/*
 * 模块: tb_xfft_probe
 * 功能:
 *   对真实 xfft_0（Radix-2 Burst I/O、2048 点、双通道、scaled、bit_reversed_order、
 *   使能 XK_INDEX 与 OVFLO）做一次**语义探针**，用来判定一件事：
 *
 *     m_axis_data_tuser[10:0]（XK_INDEX）报的是**自然频点号**，
 *     还是**输出流里的位置**？
 *
 *   这个问题无法从文档确认（本机没有 PG109，IP 源码是加密 VHDL），只能实测。
 *   它很重要：fft_stream_adapter.v:193 直接写
 *     assign fft_bin_index = fft_output_tuser[10:0];
 *   下游 fft_result_receiver 用它按“0~1024 正半谱”筛频点、fft_harmonic_stats 用它
 *   当作谐波次数。若 XK_INDEX 其实是流位置，则谐波次数整体错位。
 *
 *   激励用**周期整除 2048 的方波**（不需要正弦表，且频谱只有谐波线、没有泄漏）：
 *     通道 0（u，实信号）：周期 256 点 -> 基波落在 bin 8；bitrev11(8)  = 128
 *     通道 1（i，实信号）：周期 128 点 -> 基波落在 bin 16；bitrev11(16) = 64
 *   于是：
 *     - 若峰值处 tuser = 8 / 16   -> XK_INDEX 是自然频点号（设计假设成立）
 *     - 若峰值处 tuser = 128 / 64 -> XK_INDEX 是输出流位置（设计假设不成立）
 *   同时打印峰值出现的**流位置**，它独立地说明输出到底是不是位反转序。
 *
 *   配置字与 fft_stream_adapter.v 里的常量完全一致：
 *     48'h{2'b00, 22'h155555, 22'h155555, 2'b11}
 *   （2 bit 每级的缩放=1 bit，共 11 级 => 总缩放 1/2048，正好抵消 2048 点 FFT 的增长）
 */

module tb_xfft_probe;

    localparam integer N        = 2048;
    localparam integer A_U      = 8000;   // 通道 0 方波幅度
    localparam integer A_I      = 4000;   // 通道 1 方波幅度
    localparam integer BIN_U    = 8;      // 通道 0 基波频点
    localparam integer BIN_I    = 16;     // 通道 1 基波频点
    localparam integer BITREV_U = 128;    // bitrev11(8)
    localparam integer BITREV_I = 64;     // bitrev11(16)
    localparam [47:0] CFG_TDATA = {2'b00, 22'h155555, 22'h155555, 2'b11};

    reg aclk = 1'b0;
    reg aresetn = 1'b0;

    reg  [47:0] cfg_tdata  = CFG_TDATA;
    reg         cfg_tvalid = 1'b0;
    wire        cfg_tready;

    reg  [11:0] in_idx   = 12'd0;
    reg         in_valid = 1'b0;
    wire        in_tready;
    wire [63:0] in_tdata;

    wire [63:0] out_tdata;
    wire [23:0] out_tuser;
    wire        out_valid;
    reg         out_ready = 1'b1;
    wire        out_last;

    wire [7:0]  st_tdata;
    wire        st_tvalid;
    reg         st_tready = 1'b1;

    wire ev_frame_started;
    wire ev_tlast_unexpected;
    wire ev_tlast_missing;
    wire ev_fft_overflow;
    wire ev_status_halt;
    wire ev_din_halt;
    wire ev_dout_halt;

    // 两路实信号（虚部给 0）：方波，周期整除 2048
    wire signed [15:0] u_sample = (in_idx[7:0] < 8'd128) ? 16'sd8000 : -16'sd8000;
    wire signed [15:0] i_sample = (in_idx[6:0] < 7'd64)  ? 16'sd4000 : -16'sd4000;

    // 2 通道、每通道 {虚部, 实部}，通道 0 在低 32 位
    assign in_tdata = {16'sd0, i_sample, 16'sd0, u_sample};

    // 输出统计
    integer out_count      = 0;
    integer tlast_count    = 0;
    integer ovf_pulses     = 0;
    integer tlast_miss     = 0;
    integer tlast_unexp    = 0;
    integer frame_started  = 0;

    integer peak_u_mag   = -1;
    integer peak_u_pos   = -1;
    integer peak_u_tuser = -1;
    integer peak_u_re    = 0;
    integer peak_u_im    = 0;

    integer peak_i_mag   = -1;
    integer peak_i_pos   = -1;
    integer peak_i_tuser = -1;
    integer peak_i_re    = 0;
    integer peak_i_im    = 0;

    integer nonzero_bins   = 0;
    integer max_abs_sample = 0;

    integer errors = 0;
    integer i;
    reg     ok;

    // tuser 观察到的取值范围（便于判断字段位置是否如预期）
    integer tuser_min = 999999;
    integer tuser_max = -1;

    always #5 aclk = ~aclk;

    xfft_0 dut (
        .aclk                        (aclk),
        .aresetn                     (aresetn),
        .s_axis_config_tdata         (cfg_tdata),
        .s_axis_config_tvalid        (cfg_tvalid),
        .s_axis_config_tready        (cfg_tready),
        .s_axis_data_tdata           (in_tdata),
        .s_axis_data_tvalid          (in_valid),
        .s_axis_data_tready          (in_tready),
        .s_axis_data_tlast           (in_idx == N - 1),
        .m_axis_data_tdata           (out_tdata),
        .m_axis_data_tuser           (out_tuser),
        .m_axis_data_tvalid          (out_valid),
        .m_axis_data_tready          (out_ready),
        .m_axis_data_tlast           (out_last),
        .m_axis_status_tdata         (st_tdata),
        .m_axis_status_tvalid        (st_tvalid),
        .m_axis_status_tready        (st_tready),
        .event_frame_started         (ev_frame_started),
        .event_tlast_unexpected      (ev_tlast_unexpected),
        .event_tlast_missing         (ev_tlast_missing),
        .event_fft_overflow          (ev_fft_overflow),
        .event_status_channel_halt   (ev_status_halt),
        .event_data_in_channel_halt  (ev_din_halt),
        .event_data_out_channel_halt (ev_dout_halt)
    );

    // 输入侧：valid 一直给，由 tready 反压推进
    always @(posedge aclk) begin
        if (aresetn && in_valid && in_tready) begin
            if (in_idx == N - 1)
                in_valid <= 1'b0;
            else
                in_idx <= in_idx + 12'd1;
        end
    end

    always @(posedge aclk) begin
        if (!aresetn) begin
            // 复位期间清计数
        end else begin
            if (ev_frame_started)    frame_started  = frame_started + 1;
            if (ev_tlast_missing)    tlast_miss     = tlast_miss + 1;
            if (ev_tlast_unexpected) tlast_unexp    = tlast_unexp + 1;
            if (ev_fft_overflow)     ovf_pulses     = ovf_pulses + 1;
        end
    end

    // 输出侧：记录每个通道的峰值（用 L1 范数 |re|+|im|，与实虚部排列无关）
    integer u_re, u_im, i_re, i_im;
    integer u_mag, i_mag;
    integer tv;

    always @(posedge aclk) begin
        if (aresetn && out_valid && out_ready) begin
            u_re = $signed(out_tdata[15:0]);
            u_im = $signed(out_tdata[31:16]);
            i_re = $signed(out_tdata[47:32]);
            i_im = $signed(out_tdata[63:48]);

            u_mag = (u_re < 0 ? -u_re : u_re) + (u_im < 0 ? -u_im : u_im);
            i_mag = (i_re < 0 ? -i_re : i_re) + (i_im < 0 ? -i_im : i_im);
            tv    = out_tuser[10:0];

            if (u_mag != 0 || i_mag != 0) nonzero_bins = nonzero_bins + 1;
            if (tv < tuser_min) tuser_min = tv;
            if (tv > tuser_max) tuser_max = tv;

            if (u_mag > peak_u_mag) begin
                peak_u_mag   = u_mag;
                peak_u_pos   = out_count;
                peak_u_tuser = tv;
                peak_u_re    = u_re;
                peak_u_im    = u_im;
            end

            if (i_mag > peak_i_mag) begin
                peak_i_mag   = i_mag;
                peak_i_pos   = out_count;
                peak_i_tuser = tv;
                peak_i_re    = i_re;
                peak_i_im    = i_im;
            end

            if (out_last) tlast_count = tlast_count + 1;
            out_count = out_count + 1;
        end
    end

    task report;
        begin
            $display("");
            $display("================ xfft 探针结果 ================");
            $display("输出样本数        = %0d（期望 2048）", out_count);
            $display("m_axis tlast 次数 = %0d（期望 1）", tlast_count);
            $display("tuser[10:0] 范围  = %0d .. %0d", tuser_min, tuser_max);
            $display("非零频点数        = %0d", nonzero_bins);
            $display("event: frame_started=%0d tlast_missing=%0d tlast_unexpected=%0d fft_overflow=%0d",
                     frame_started, tlast_miss, tlast_unexp, ovf_pulses);
            $display("");
            $display("通道 0（周期 256 -> 基波 bin %0d，bitrev = %0d）", BIN_U, BITREV_U);
            $display("  峰值 |re|+|im| = %0d  (re=%0d im=%0d)", peak_u_mag, peak_u_re, peak_u_im);
            $display("  峰值流位置     = %0d", peak_u_pos);
            $display("  峰值处 tuser   = %0d", peak_u_tuser);
            $display("");
            $display("通道 1（周期 128 -> 基波 bin %0d，bitrev = %0d）", BIN_I, BITREV_I);
            $display("  峰值 |re|+|im| = %0d  (re=%0d im=%0d)", peak_i_mag, peak_i_re, peak_i_im);
            $display("  峰值流位置     = %0d", peak_i_pos);
            $display("  峰值处 tuser   = %0d", peak_i_tuser);
            $display("===============================================");
            $display("");
        end
    endtask

    initial begin
        // 复位
        aresetn = 1'b0;
        repeat (20) @(posedge aclk);
        aresetn = 1'b1;
        repeat (10) @(posedge aclk);

        // 送配置字（与 fft_stream_adapter 同一个常量），等握手
        cfg_tvalid = 1'b1;
        ok = 1'b0;
        for (i = 0; i < 200 && !ok; i = i + 1) begin
            @(posedge aclk);
            if (cfg_tready) ok = 1'b1;
        end
        if (!ok) begin
            $display("FAIL: 配置通道一直不 ready");
            errors = errors + 1;
        end
        @(negedge aclk);
        cfg_tvalid = 1'b0;

        // 送 2048 点
        in_idx   = 12'd0;
        in_valid = 1'b1;

        // 等 2048 个输出样本
        ok = 1'b0;
        for (i = 0; i < 500000 && !ok; i = i + 1) begin
            @(posedge aclk);
            if (out_count >= N) ok = 1'b1;
        end
        if (!ok) begin
            $display("FAIL: 等不到 2048 个输出样本（当前 %0d）", out_count);
            errors = errors + 1;
        end

        repeat (20) @(posedge aclk);
        report;

        // 判定
        if (peak_u_tuser == BIN_U && peak_i_tuser == BIN_I) begin
            $display("结论: XK_INDEX = 自然频点号，fft_bin_index = tuser[10:0] 的假设成立。");
        end else if (peak_u_tuser == BITREV_U && peak_i_tuser == BITREV_I) begin
            $display("结论: XK_INDEX = 输出流位置（位反转序），fft_bin_index = tuser[10:0] 的假设**不成立**。");
        end else begin
            $display("结论: 两种假设都对不上，需要人工看上面的峰值/tuser 数据。");
        end

        if (peak_u_mag <= 0 || peak_i_mag <= 0) begin
            $display("FAIL: 峰值幅度非正，激励或数据通路有问题");
            errors = errors + 1;
        end
        if (out_count != N) begin
            $display("FAIL: 输出样本数 %0d，期望 %0d", out_count, N);
            errors = errors + 1;
        end
        if (tlast_count != 1) begin
            $display("FAIL: m_axis tlast 次数 %0d，期望 1", tlast_count);
            errors = errors + 1;
        end
        if (ovf_pulses != 0) begin
            $display("FAIL: 出现 %0d 次 FFT 溢出", ovf_pulses);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PASS: xfft_probe");
        end else begin
            $display("FAIL: xfft_probe，共 %0d 处不符", errors);
            $fatal(1, "xfft_probe 用例未通过");
        end
        $finish;
    end

    initial begin
        #2000000;
        $display("FAIL: 仿真看门狗超时");
        $fatal(1, "仿真超时");
    end

endmodule
