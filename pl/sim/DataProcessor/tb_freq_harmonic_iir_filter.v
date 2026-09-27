`timescale 1ns / 1ps

/*
 * 模块: tb_freq_harmonic_iir_filter
 * 功能:
 *   freq_harmonic_iir_filter 的单元测试平台：对 0~500 次谐波流做 1/16 一阶 IIR 平滑。
 *
 *   每帧 4 项，谐波次数分别为 0、1、2、600：
 *     - order 0 只带 u1_real（有符号，用来验证 delta 右移是算术右移/向下取整）
 *     - order 1 只带 u_mag（无符号 17 bit）
 *     - order 2 只带 u1_pct_x100（无符号 16 bit）与相位差（deg x100，带跨 ±180 的展开）
 *     - order 600 超出 0~500 范围，应被当作"未捕获"（present=0、各数值归零、
 *       次数被钳到 500），用来验证 stage_in_range 与 input_index 的钳位
 *   各 order 只带一个字段、其余为 0，这样任何跨 order 的状态串扰都会被查出来。
 *
 *   三帧的手算期望：
 *     u1_real  (有符号，算术右移向下取整)：100 -> 100+((-100)>>4)=93
 *                                          -> 93+((-1693)>>4)=93-106=-13
 *     u_mag   1600 -> 1600+(3200>>4)=1800 -> 1800+(3000>>4)=1987
 *     u1_pct   1000 -> 1000+(17>>4)=1001  -> 1001+((-1)>>4)=1000
 *     phase   17000 -> 展开到 19000 后 17000+(2000>>4)=17125
 *                    -> 再展开到 19000 后 17125+(1875>>4)=17242
 *
 *   场景：
 *     1) 复位后状态 RAM 清零期间不得接收（s_harmonic_ready 必须为 0）
 *     2) 第一帧：old_init=0，输出应等于输入（不平滑）
 *     3) 第二帧：IIR 生效，比对上面手算值
 *     4) enable=0 清空待输出结果；恢复后第三帧继续沿用上一帧状态
 *     5) filtered_frame_count 应等于帧数
 */

module tb_freq_harmonic_iir_filter;

    localparam integer CLK_PERIOD  = 10;      // 100 MHz
    localparam integer WATCHDOG_NS = 2000000; // 2 ms 兜底
    localparam integer ITEMS       = 4;       // 每帧 4 项
    localparam integer FRAMES      = 3;
    localparam integer TOTAL       = ITEMS * FRAMES;

    // 超出 0~500 范围的次数（9 bit 字段，只能用 501 这种刚过界的值），
    // 用来验证钳位与 present=0
    localparam integer OUT_OF_RANGE_ORDER = 501;
    localparam integer CLAMPED_ORDER      = 500;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg enable = 1'b1;
    reg s_harmonic_valid = 1'b0;
    reg s_harmonic_last = 1'b0;
    reg [8:0] s_harmonic_order = 9'd0;
    reg s_harmonic_present = 1'b0;
    reg signed [15:0] s_u1_real = 16'sd0;
    reg signed [15:0] s_u1_imag = 16'sd0;
    reg signed [15:0] s_u2_real = 16'sd0;
    reg signed [15:0] s_u2_imag = 16'sd0;
    reg [16:0] s_u1_mag = 17'd0;
    reg [16:0] s_u2_mag = 17'd0;
    reg [15:0] s_u1_pct_x100 = 16'd0;
    reg [15:0] s_u2_pct_x100 = 16'd0;
    reg s_phase_vector_valid = 1'b0;
    reg signed [32:0] s_phase_dot = 33'sd0;
    reg signed [32:0] s_phase_cross = 33'sd0;
    reg s_phase_diff_valid = 1'b0;
    reg signed [15:0] s_phase_diff_deg_x100 = 16'sd0;
    reg m_harmonic_ready = 1'b0;

    wire               s_harmonic_ready;
    wire               m_harmonic_valid;
    wire               m_harmonic_last;
    wire [8:0]         m_harmonic_order;
    wire               m_harmonic_present;
    wire signed [15:0] m_u1_real;
    wire signed [15:0] m_u1_imag;
    wire signed [15:0] m_u2_real;
    wire signed [15:0] m_u2_imag;
    wire [16:0]        m_u1_mag;
    wire [16:0]        m_u2_mag;
    wire [15:0]        m_u1_pct_x100;
    wire [15:0]        m_u2_pct_x100;
    wire               m_phase_vector_valid;
    wire signed [32:0] m_phase_dot;
    wire signed [32:0] m_phase_cross;
    wire               m_phase_diff_valid;
    wire signed [15:0] m_phase_diff_deg_x100;
    wire [15:0]        filtered_frame_count;

    // 每帧每项的激励：次数固定为 0/1/2/600
    reg [8:0]  in_order [0:ITEMS-1];
    // 逐项（跨帧展平）激励
    reg               in_present [0:TOTAL-1];
    reg               in_pvec [0:TOTAL-1];
    reg               in_pvalid [0:TOTAL-1];
    reg signed [15:0] in_ureal [0:TOTAL-1];
    reg [16:0]        in_umag [0:TOTAL-1];
    reg [15:0]        in_upct [0:TOTAL-1];
    reg signed [15:0] in_phase [0:TOTAL-1];
    // 逐项期望输出
    reg [8:0]         exp_order [0:TOTAL-1];
    reg               exp_present [0:TOTAL-1];
    reg               exp_pvec [0:TOTAL-1];
    reg               exp_pvalid [0:TOTAL-1];
    reg signed [15:0] exp_ureal [0:TOTAL-1];
    reg [16:0]        exp_umag [0:TOTAL-1];
    reg [15:0]        exp_upct [0:TOTAL-1];
    reg signed [15:0] exp_phase [0:TOTAL-1];

    integer errors = 0;
    integer i;
    integer m;                  // drive_frame 专用下标（与 consume_frame 并行，不能共用）
    integer k;                  // consume_frame 专用下标
    integer target;
    integer input_fires = 0;
    reg     ok;

    always #(CLK_PERIOD / 2) clk = ~clk;

    freq_harmonic_iir_filter dut (
        .clk                      (clk),
        .rst_n                    (rst_n),
        .enable                   (enable),
        .s_harmonic_valid         (s_harmonic_valid),
        .s_harmonic_ready         (s_harmonic_ready),
        .s_harmonic_last          (s_harmonic_last),
        .s_harmonic_order         (s_harmonic_order),
        .s_harmonic_present       (s_harmonic_present),
        .s_u1_real                 (s_u1_real),
        .s_u1_imag                 (s_u1_imag),
        .s_u2_real                 (s_u2_real),
        .s_u2_imag                 (s_u2_imag),
        .s_u1_mag                  (s_u1_mag),
        .s_u2_mag                  (s_u2_mag),
        .s_u1_pct_x100             (s_u1_pct_x100),
        .s_u2_pct_x100             (s_u2_pct_x100),
        .s_phase_vector_valid     (s_phase_vector_valid),
        .s_phase_dot              (s_phase_dot),
        .s_phase_cross            (s_phase_cross),
        .s_phase_diff_valid       (s_phase_diff_valid),
        .s_phase_diff_deg_x100    (s_phase_diff_deg_x100),
        .m_harmonic_ready         (m_harmonic_ready),
        .m_harmonic_valid         (m_harmonic_valid),
        .m_harmonic_last          (m_harmonic_last),
        .m_harmonic_order         (m_harmonic_order),
        .m_harmonic_present       (m_harmonic_present),
        .m_u1_real                 (m_u1_real),
        .m_u1_imag                 (m_u1_imag),
        .m_u2_real                 (m_u2_real),
        .m_u2_imag                 (m_u2_imag),
        .m_u1_mag                  (m_u1_mag),
        .m_u2_mag                  (m_u2_mag),
        .m_u1_pct_x100             (m_u1_pct_x100),
        .m_u2_pct_x100             (m_u2_pct_x100),
        .m_phase_vector_valid     (m_phase_vector_valid),
        .m_phase_dot              (m_phase_dot),
        .m_phase_cross            (m_phase_cross),
        .m_phase_diff_valid       (m_phase_diff_valid),
        .m_phase_diff_deg_x100    (m_phase_diff_deg_x100),
        .filtered_frame_count     (filtered_frame_count)
    );

    always @(posedge clk) begin
        if (rst_n && s_harmonic_valid && s_harmonic_ready)
            input_fires <= input_fires + 1;
    end

    task init_vectors;
        begin
            in_order[0] = 9'd0;
            in_order[1] = 9'd1;
            in_order[2] = 9'd2;
            in_order[3] = OUT_OF_RANGE_ORDER[8:0];

            // ---- 第一帧：old_init=0，输出应等于输入 ----
            // idx0 order0
            in_present[0]=1'b1; in_pvec[0]=1'b1; in_pvalid[0]=1'b1;
            in_ureal[0]= 16'sd100; in_umag[0]=17'd0;    in_upct[0]=16'd0;    in_phase[0]= 16'sd0;
            exp_order[0]=9'd0; exp_present[0]=1'b1; exp_pvec[0]=1'b1; exp_pvalid[0]=1'b1;
            exp_ureal[0]= 16'sd100; exp_umag[0]=17'd0; exp_upct[0]=16'd0; exp_phase[0]= 16'sd0;
            // idx1 order1
            in_present[1]=1'b1; in_pvec[1]=1'b1; in_pvalid[1]=1'b1;
            in_ureal[1]= 16'sd0;   in_umag[1]=17'd1600; in_upct[1]=16'd0;   in_phase[1]= 16'sd0;
            exp_order[1]=9'd1; exp_present[1]=1'b1; exp_pvec[1]=1'b1; exp_pvalid[1]=1'b1;
            exp_ureal[1]= 16'sd0; exp_umag[1]=17'd1600; exp_upct[1]=16'd0; exp_phase[1]= 16'sd0;
            // idx2 order2
            in_present[2]=1'b1; in_pvec[2]=1'b1; in_pvalid[2]=1'b1;
            in_ureal[2]= 16'sd0;   in_umag[2]=17'd0;    in_upct[2]=16'd1000; in_phase[2]= 16'sd17000;
            exp_order[2]=9'd2; exp_present[2]=1'b1; exp_pvec[2]=1'b1; exp_pvalid[2]=1'b1;
            exp_ureal[2]= 16'sd0; exp_umag[2]=17'd0; exp_upct[2]=16'd1000; exp_phase[2]= 16'sd17000;
            // idx3 order600（超范围）
            in_present[3]=1'b1; in_pvec[3]=1'b0; in_pvalid[3]=1'b0;
            in_ureal[3]= 16'sd0;   in_umag[3]=17'd0;    in_upct[3]=16'd0;    in_phase[3]= 16'sd0;
            exp_order[3]=CLAMPED_ORDER[8:0]; exp_present[3]=1'b0; exp_pvec[3]=1'b0; exp_pvalid[3]=1'b0;
            exp_ureal[3]= 16'sd0; exp_umag[3]=17'd0; exp_upct[3]=16'd0; exp_phase[3]= 16'sd0;

            // ---- 第二帧 ----
            in_present[4]=1'b1; in_pvec[4]=1'b1; in_pvalid[4]=1'b1;
            in_ureal[4]= 16'sd0;   in_umag[4]=17'd0;    in_upct[4]=16'd0;    in_phase[4]= 16'sd0;
            exp_order[4]=9'd0; exp_present[4]=1'b1; exp_pvec[4]=1'b1; exp_pvalid[4]=1'b1;
            exp_ureal[4]= 16'sd93; exp_umag[4]=17'd0; exp_upct[4]=16'd0; exp_phase[4]= 16'sd0;

            in_present[5]=1'b1; in_pvec[5]=1'b1; in_pvalid[5]=1'b1;
            in_ureal[5]= 16'sd0;   in_umag[5]=17'd4800; in_upct[5]=16'd0;    in_phase[5]= 16'sd0;
            exp_order[5]=9'd1; exp_present[5]=1'b1; exp_pvec[5]=1'b1; exp_pvalid[5]=1'b1;
            exp_ureal[5]= 16'sd0; exp_umag[5]=17'd1800; exp_upct[5]=16'd0; exp_phase[5]= 16'sd0;

            in_present[6]=1'b1; in_pvec[6]=1'b1; in_pvalid[6]=1'b1;
            in_ureal[6]= 16'sd0;   in_umag[6]=17'd0;    in_upct[6]=16'd1017; in_phase[6]= -16'sd17000;
            exp_order[6]=9'd2; exp_present[6]=1'b1; exp_pvec[6]=1'b1; exp_pvalid[6]=1'b1;
            exp_ureal[6]= 16'sd0; exp_umag[6]=17'd0; exp_upct[6]=16'd1001; exp_phase[6]= 16'sd17125;

            in_present[7]=1'b1; in_pvec[7]=1'b0; in_pvalid[7]=1'b0;
            in_ureal[7]= 16'sd0;   in_umag[7]=17'd0;    in_upct[7]=16'd0;    in_phase[7]= 16'sd0;
            exp_order[7]=CLAMPED_ORDER[8:0]; exp_present[7]=1'b0; exp_pvec[7]=1'b0; exp_pvalid[7]=1'b0;
            exp_ureal[7]= 16'sd0; exp_umag[7]=17'd0; exp_upct[7]=16'd0; exp_phase[7]= 16'sd0;

            // ---- 第三帧 ----
            in_present[8]=1'b1; in_pvec[8]=1'b1; in_pvalid[8]=1'b1;
            in_ureal[8]= -16'sd1600; in_umag[8]=17'd0;   in_upct[8]=16'd0;    in_phase[8]= 16'sd0;
            exp_order[8]=9'd0; exp_present[8]=1'b1; exp_pvec[8]=1'b1; exp_pvalid[8]=1'b1;
            exp_ureal[8]= -16'sd13; exp_umag[8]=17'd0; exp_upct[8]=16'd0; exp_phase[8]= 16'sd0;

            in_present[9]=1'b1; in_pvec[9]=1'b1; in_pvalid[9]=1'b1;
            in_ureal[9]= 16'sd0;   in_umag[9]=17'd4800;  in_upct[9]=16'd0;    in_phase[9]= 16'sd0;
            exp_order[9]=9'd1; exp_present[9]=1'b1; exp_pvec[9]=1'b1; exp_pvalid[9]=1'b1;
            exp_ureal[9]= 16'sd0; exp_umag[9]=17'd1987; exp_upct[9]=16'd0; exp_phase[9]= 16'sd0;

            in_present[10]=1'b1; in_pvec[10]=1'b1; in_pvalid[10]=1'b1;
            in_ureal[10]= 16'sd0;  in_umag[10]=17'd0;    in_upct[10]=16'd1000; in_phase[10]= -16'sd17000;
            exp_order[10]=9'd2; exp_present[10]=1'b1; exp_pvec[10]=1'b1; exp_pvalid[10]=1'b1;
            exp_ureal[10]= 16'sd0; exp_umag[10]=17'd0; exp_upct[10]=16'd1000; exp_phase[10]= 16'sd17242;

            in_present[11]=1'b1; in_pvec[11]=1'b0; in_pvalid[11]=1'b0;
            in_ureal[11]= 16'sd0;  in_umag[11]=17'd0;    in_upct[11]=16'd0;    in_phase[11]= 16'sd0;
            exp_order[11]=CLAMPED_ORDER[8:0]; exp_present[11]=1'b0; exp_pvec[11]=1'b0; exp_pvalid[11]=1'b0;
            exp_ureal[11]= 16'sd0; exp_umag[11]=17'd0; exp_upct[11]=16'd0; exp_phase[11]= 16'sd0;
        end
    endtask

    // 送一帧：帧内第 idx_base+0..3 项
    task drive_frame;
        input integer idx_base;
        begin
            for (m = 0; m < ITEMS; m = m + 1) begin
                @(negedge clk);
                s_harmonic_order        = in_order[m];
                s_harmonic_last         = (m == ITEMS - 1);
                s_harmonic_present      = in_present[idx_base + m];
                s_u1_real                = in_ureal[idx_base + m];
                s_u1_imag                = 16'sd0;
                s_u2_real                = 16'sd0;
                s_u2_imag                = 16'sd0;
                s_u1_mag                 = in_umag[idx_base + m];
                s_u2_mag                 = 17'd0;
                s_u1_pct_x100            = in_upct[idx_base + m];
                s_u2_pct_x100            = 16'd0;
                s_phase_vector_valid    = in_pvec[idx_base + m];
                s_phase_dot             = 33'sd0;
                s_phase_cross           = 33'sd0;
                s_phase_diff_valid      = in_pvalid[idx_base + m];
                s_phase_diff_deg_x100   = in_phase[idx_base + m];
                s_harmonic_valid        = 1'b1;
                target                  = input_fires + 1;
                wait (input_fires == target);
            end

            @(negedge clk);
            s_harmonic_valid = 1'b0;
            s_harmonic_last  = 1'b0;
        end
    endtask

    task consume_frame;
        input integer idx_base;
        input [127:0] tag;
        begin
            for (k = 0; k < ITEMS; k = k + 1) begin
                ok = 1'b0;
                for (i = 0; i < 800 && !ok; i = i + 1) begin
                    @(negedge clk);
                    if (m_harmonic_valid) ok = 1'b1;
                end

                if (!ok) begin
                    $display("FAIL: %0s 第 %0d 项没有等到 m_harmonic_valid", tag, k);
                    errors = errors + 1;
                end else begin
                    if (m_harmonic_order !== exp_order[idx_base + k]) begin
                        $display("FAIL: %0s 第 %0d 项 order=%0d，期望 %0d",
                                 tag, k, m_harmonic_order, exp_order[idx_base + k]);
                        errors = errors + 1;
                    end
                    if (m_harmonic_present !== exp_present[idx_base + k]) begin
                        $display("FAIL: %0s 第 %0d 项 present=%0b，期望 %0b",
                                 tag, k, m_harmonic_present, exp_present[idx_base + k]);
                        errors = errors + 1;
                    end
                    if (m_u1_real !== exp_ureal[idx_base + k]) begin
                        $display("FAIL: %0s 第 %0d 项 u_real=%0d，期望 %0d",
                                 tag, k, m_u1_real, exp_ureal[idx_base + k]);
                        errors = errors + 1;
                    end
                    if (m_u1_mag !== exp_umag[idx_base + k]) begin
                        $display("FAIL: %0s 第 %0d 项 u_mag=%0d，期望 %0d",
                                 tag, k, m_u1_mag, exp_umag[idx_base + k]);
                        errors = errors + 1;
                    end
                    if (m_u1_pct_x100 !== exp_upct[idx_base + k]) begin
                        $display("FAIL: %0s 第 %0d 项 u_pct_x100=%0d，期望 %0d",
                                 tag, k, m_u1_pct_x100, exp_upct[idx_base + k]);
                        errors = errors + 1;
                    end
                    if (m_phase_diff_deg_x100 !== exp_phase[idx_base + k]) begin
                        $display("FAIL: %0s 第 %0d 项 phase_diff_deg_x100=%0d，期望 %0d",
                                 tag, k, m_phase_diff_deg_x100, exp_phase[idx_base + k]);
                        errors = errors + 1;
                    end
                    if (m_phase_vector_valid !== exp_pvec[idx_base + k]) begin
                        $display("FAIL: %0s 第 %0d 项 phase_vector_valid=%0b，期望 %0b",
                                 tag, k, m_phase_vector_valid, exp_pvec[idx_base + k]);
                        errors = errors + 1;
                    end
                    if (m_phase_diff_valid !== exp_pvalid[idx_base + k]) begin
                        $display("FAIL: %0s 第 %0d 项 phase_diff_valid=%0b，期望 %0b",
                                 tag, k, m_phase_diff_valid, exp_pvalid[idx_base + k]);
                        errors = errors + 1;
                    end
                    // 本用例里恒为 0 的字段：验证没有跨 order 的状态串扰、也没有残留旧值
                    if (m_u1_imag !== 16'sd0 || m_u2_real !== 16'sd0 || m_u2_imag !== 16'sd0 ||
                        m_u2_mag !== 17'd0 || m_u2_pct_x100 !== 16'd0 ||
                        m_phase_dot !== 33'sd0 || m_phase_cross !== 33'sd0) begin
                        $display("FAIL: %0s 第 %0d 项出现非零的 i 通道/向量字段（u_imag=%0d i_real=%0d i_imag=%0d i_mag=%0d i_pct=%0d dot=%0d cross=%0d）",
                                 tag, k, m_u1_imag, m_u2_real, m_u2_imag, m_u2_mag, m_u2_pct_x100,
                                 m_phase_dot, m_phase_cross);
                        errors = errors + 1;
                    end
                    if (m_harmonic_last !== ((k == ITEMS - 1) ? 1'b1 : 1'b0)) begin
                        $display("FAIL: %0s 第 %0d 项 m_harmonic_last=%0b，期望 %0b",
                                 tag, k, m_harmonic_last, (k == ITEMS - 1));
                        errors = errors + 1;
                    end
                end

                // 取走一项后空一拍 ready，制造反压
                @(negedge clk);
                m_harmonic_ready = 1'b1;
                @(negedge clk);
                m_harmonic_ready = 1'b0;
            end
        end
    endtask

    initial begin
        init_vectors;
        repeat (10) @(posedge clk);
        rst_n = 1'b1;

        // ---------------- 场景 1：状态 RAM 清零期间不得接收 ----------------
        for (i = 0; i < 100; i = i + 1) begin
            @(negedge clk);
            if (s_harmonic_ready !== 1'b0) begin
                $display("FAIL: 复位后第 %0d 拍 s_harmonic_ready 已拉高，清 RAM 尚未完成", i);
                errors = errors + 1;
            end
        end
        // 等状态 RAM 清零完成（s_harmonic_ready 拉高）后再开帧；
        // 否则第一个输出要等 ~503 拍，消费者一侧的等待窗口容易先超时。
        ok = 1'b0;
        for (i = 0; i < 2000 && !ok; i = i + 1) begin
            @(negedge clk);
            if (s_harmonic_ready) ok = 1'b1;
        end
        if (!ok) begin
            $display("FAIL: 等不到 s_harmonic_ready 拉高，状态 RAM 清零可能未完成");
            errors = errors + 1;
        end

        // ---------------- 场景 2：第一帧（init 拷贝） ----------------
        fork
            drive_frame(0);
            consume_frame(0, "第一帧");
        join
        repeat (10) @(posedge clk);

        // ---------------- 场景 3：第二帧（IIR 生效） ----------------
        fork
            drive_frame(ITEMS);
            consume_frame(ITEMS, "第二帧");
        join
        repeat (10) @(posedge clk);

        // ---------------- 场景 4：enable=0 清空，恢复后第三帧沿用旧状态 ----------------
        enable = 1'b0;
        repeat (20) @(posedge clk);
        if (m_harmonic_valid !== 1'b0) begin
            $display("FAIL: enable=0 时不应有 m_harmonic_valid");
            errors = errors + 1;
        end
        enable = 1'b1;
        repeat (20) @(posedge clk);

        fork
            drive_frame(ITEMS * 2);
            consume_frame(ITEMS * 2, "第三帧");
        join
        repeat (10) @(posedge clk);

        if (filtered_frame_count !== 16'd3) begin
            $display("FAIL: filtered_frame_count=%0d，期望 3", filtered_frame_count);
            errors = errors + 1;
        end

        if (errors == 0) begin
            $display("PASS: freq_harmonic_iir_filter");
        end else begin
            $display("FAIL: freq_harmonic_iir_filter，共 %0d 处不符", errors);
            $fatal(1, "freq_harmonic_iir_filter 用例未通过");
        end
        $finish;
    end

    initial begin
        #WATCHDOG_NS;
        $display("FAIL: 仿真看门狗超时");
        $fatal(1, "仿真超时");
    end

endmodule
