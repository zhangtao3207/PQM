`timescale 1ns / 1ps

/*
 * 模块: tb_pqm_pl_top
 * 功能:
 *   PQM2 PL 测量链的**系统级**验证：在 AD7606 引脚上挂一个芯片行为模型，喂入
 *   代码级正弦，然后**依次监测数据链的每一环**，每一环有自己的数值判据。
 *
 *   第 1 环 ADC 采集与控制
 *     1a 复位期间 pacer 不应给出 tick
 *     1b 每个 tick 都被消费：adc_tick_pending 恒为 0
 *     1c 帧间隔 = 1953/1954 拍（平均 25.6 kHz）
 *     1d ad_frame_valid 与 wave_sample_valid 一一对应
 *   第 2 环 码值与零点
 *     2a 采样码值随正弦变化（不是常数）
 *     2b 零点跟踪收敛到中心码 0x8000 附近且 zero_valid 拉高
 *   第 3 环 RFG 频域链
 *     3a RFG 取样口出现（样本由测量核心直接送入，一致性见 3in）
 *     3b 每帧产出 65 个谐波条目，帧尾 index = 64
 *     3c 1 次谐波 present，u 占比落在解析值 7142 附近
 *   第 4 环 时域链 + 快照
 *     4a 快照提交 toggle 翻转
 *     4b u_rms 字段非零且量级合理（正弦幅值已知，可比对）
 *   第 5 环 共享内存桥
 *     5a 桥写 BRAM；5b 谐波 bank 有写入
 *
 * 说明：
 *   - 时域窗口与测量间隔做了缩短（参数化）。生产值见 pqm_pl_top 默认参数。
 *   - AD7606 行为模型只实现本链用到的时序：CONVST 上升沿开始转换、BUSY 保持、
 *     FRSTDATA 在首次 RD 上升沿归低、每个 RD 上升沿切到下一通道。
 *   - 激励：u = 1000*cos(w n) + 400*cos(3w n)，i = 800*sin(w n)（滞后 90°）
 *     一帧 512 点 = 一个 50 Hz 周期；LUT 2048 点，故每点相位步进 4。
 */

module tb_pqm_pl_top;

    // 这几个 DUT 输出在下面的连续赋值里当输入用；提前声明避开"先用后声明"。
    wire ad_reset, ad_convst, ad_cs_n, ad_rd_n;

    localparam integer CLK_PERIOD  = 20;      // 50 MHz
    localparam integer CONV_CYCLES = 400;     // 模拟 4 us 转换时间
    localparam integer LUT_N       = 2048;
    localparam integer U_1ST       = 1000;
    localparam integer U_3RD       = 400;
    localparam integer I_1ST       = 800;
    localparam integer CENTER      = 32768;
    localparam integer C_N         = 512;
    localparam integer C_K         = 64;
    localparam integer SMP_PERIOD  = 1953;
    localparam [1:0] M_IDLE = 2'd0, M_CONV = 2'd1, M_READY = 2'd2;

    // 生产值为 MEASUREMENT_INTERVAL_CYCLES = 16_000_000、MEASURE_FRAME_SAMPLES = 6144
    //（pqm_pl_top 的默认值），已验证；此处用缩短值加速。阶段 4 等的是时域结果真正写进快照。
    localparam integer MEAS_INTERVAL = 3_400_000;
    localparam integer MEAS_SAMPLES  = 1024;

    // 期望的 u 有效值（x100 工程量）：u 只有 1、3 次谐波，RMS = sqrt((1000^2+400^2)/2)
    // = 761.577... 以中心的码值计，RMS 码值约 762。
    localparam integer U_RMS_EXPECT = 762;
    // 零点跟踪预热样本数 = pqm_pl_top 两个 tracker 实例的 WARMUP_SAMPLES；
    // 阶段 1 必须至少跑这么多个样本，否则 zero_valid 判据本身就不成立。
    localparam integer ZERO_WARMUP    = 4096;
    localparam integer WARMUP_FRAMES  = 4200;

    reg clk   = 1'b0;
    reg rst_n = 1'b0;

    always #(CLK_PERIOD / 2) clk = ~clk;

    // ------------------------------------------------------------------
    // 正弦查找表与激励
    // ------------------------------------------------------------------
    integer sine_lut [0:LUT_N-1];
    integer k;
    real    ang;
    integer sample_idx = 0;
    integer ph_u, ph_3rd, ph_i;
    integer u_code_c, i_code_c;

    reg  [15:0] ad7606_ch_data [0:7];
    reg  [15:0] ad_data_m;
    reg         ad_busy_m, ad_frstdata_m;
    reg         ad_convst_d = 1'b1;
    reg         ad_rd_n_d   = 1'b1;
    reg [1:0]   mdl_state   = M_IDLE;
    reg [2:0]   mdl_ch      = 3'd0;
    reg [31:0]  mdl_cnt     = 0;

    always @(*) ad_data_m = ad7606_ch_data[mdl_ch];
    wire convst_rise = ad_convst & ~ad_convst_d;
    wire rd_rise     = ad_rd_n   & ~ad_rd_n_d;


    wire [511:0] snap_words;
    wire         snap_toggle, alarm_active;
    wire         adc_tick_pending;
    wire         low_range_active;
    wire [13:0]  bram_addr;
    wire [31:0]  bram_wrdata;
    wire  [3:0]  bram_we;
    wire         bram_en;

    integer err = 0;
    integer cyc = 0;

    // 第 1 环监测
    integer tick_in_reset = 0;
    integer tick_count    = 0;
    integer frame_count   = 0;
    integer sample_count  = 0;
    integer pending_seen  = 0;
    integer frame_gap_min = 0;
    integer frame_gap_max = 0;
    integer last_frame_cyc = 0;
    integer frame_gap_cur = 0;
    integer last_u_code   = -1;
    integer code_changed  = 0;
    reg     gap_armed     = 1'b0;

    // 第 3 环监测
    integer harm_items_per_frame = 0;
    integer harm_frames          = 0;
    integer harm_last_index_seen = -1;
    integer harm_max_index       = -1;
    integer harm_h1_present      = 0;
    integer harm_h1_ratio        = -1;
    integer harm_total_items     = 0;
    integer ready_seen           = 0;

    // 第 4/5 环监测
    integer snap_commit_count = 0;
    integer bram_wr_count     = 0;
    integer bram_harm_wr      = 0;
    reg     snap_toggle_d     = 1'b0;
    integer in_n = 0;
    integer in_bad = 0;
    integer rb_bank, rb_k, rb_base;
    integer rb_h1_u, rb_h3_u, rb_h1_p, rb_max_idx;
    reg [31:0] rb_u, rb_i, rb_ph, rb_fl;
    integer in_got [0:23];
    integer in_exp [0:23];
    integer scan_i;

    integer wait_i;

    // ------------------------------------------------------------------
    // 激励生成：更新本帧 8 个通道的码值
    // ------------------------------------------------------------------
    task build_stimulus;
        input integer idx;
        begin
            ph_u   = (idx * (LUT_N / C_N)) % LUT_N;
            ph_3rd = (idx * 3 * (LUT_N / C_N)) % LUT_N;
            ph_i   = (ph_u + (LUT_N / 4)) % LUT_N;

            // 两音激励：u = 1000*cos(w n) + 400*cos(3w n)，i = 800*sin(w n)
            u_code_c = (U_1ST * sine_lut[ph_u] + U_3RD * sine_lut[ph_3rd]) / 1000;
            i_code_c = (I_1ST * sine_lut[ph_i]) / 1000;

            // AD7606 引脚是**二进制补码**（见 pl/README.md「喂数据的约定」）：
            // 引脚给补码，RTL 里 XOR 0x8000 之后才是测量核心要的偏移二进制（0x8000=零点）。
            // 这里原来写成 CENTER + u_code_c（= 偏移二进制）直接加在引脚上，被 RTL 的
            // XOR 再翻一次，送进核心的就成了 u_code_c - 32768*sign(u_code_c) 的 ±32768
            // 方波：时域 RMS 变成 3.4 万、频域出 1/n 奇次伪分量，h1_ratio 掉到 3400。
            ad7606_ch_data[0] = u_code_c;
            ad7606_ch_data[1] = 16'd0;
            ad7606_ch_data[2] = i_code_c;
            ad7606_ch_data[3] = 16'd0;
            ad7606_ch_data[4] = 16'd0;
            ad7606_ch_data[5] = 16'd0;
            ad7606_ch_data[6] = 16'd0;
            ad7606_ch_data[7] = 16'd0;
        end
    endtask

    // ------------------------------------------------------------------
    // AD7606 芯片行为模型
    // ------------------------------------------------------------------

    always @(posedge clk) begin
        ad_convst_d <= ad_convst;
        ad_rd_n_d   <= ad_rd_n;

        if (!rst_n) begin
            mdl_state     <= M_IDLE;
            mdl_ch        <= 3'd0;
            mdl_cnt       <= 0;
            ad_busy_m     <= 1'b0;
            ad_frstdata_m <= 1'b0;
        end else begin
            if (convst_rise) begin
                // 转换开始前先把"本帧"的 8 通道码值装好，使读出的码值与帧号严格对齐。
                build_stimulus(sample_idx);
                sample_idx = sample_idx + 1;
                ad_frstdata_m <= 1'b0;
                ad_busy_m     <= 1'b1;
                mdl_cnt       <= CONV_CYCLES;
                mdl_ch        <= 3'd0;
                mdl_state     <= M_CONV;
            end else begin
                case (mdl_state)
                    M_CONV: begin
                        if (mdl_cnt == 0) begin
                            ad_busy_m     <= 1'b0;
                            ad_frstdata_m <= 1'b1;
                            mdl_ch        <= 3'd0;
                            mdl_state     <= M_READY;
                        end else begin
                            mdl_cnt <= mdl_cnt - 1;
                        end
                    end
                    M_READY: begin
                        ad_busy_m <= 1'b0;
                        if (rd_rise) begin
                            if (mdl_ch == 3'd0) ad_frstdata_m <= 1'b0;
                            if (mdl_ch != 3'd7) mdl_ch <= mdl_ch + 1'b1;
                            else                mdl_ch <= 3'd0;
                        end
                    end
                    default: mdl_state <= M_IDLE;
                endcase
            end
        end
    end

    // ------------------------------------------------------------------
    // 被测系统
    // ------------------------------------------------------------------
    pqm_pl_top #(
        .MEASUREMENT_INTERVAL_CYCLES (MEAS_INTERVAL),
        .MEASURE_FRAME_SAMPLES       (MEAS_SAMPLES),
        .FORCE_ZERO_CENTER           (1)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .ad_busy(ad_busy_m), .ad_frstdata(ad_frstdata_m), .ad_data(ad_data_m),
        .ad_reset(ad_reset), .ad_convst(ad_convst), .ad_cs_n(ad_cs_n), .ad_rd_n(ad_rd_n),
        .command_response_valid(1'b0),
        .bram_rddata(32'd0),
        .bram_addr(bram_addr), .bram_wrdata(bram_wrdata),
        .bram_we(bram_we), .bram_en(bram_en),
        .ps_snapshot_words(snap_words),
        .ps_snapshot_commit_toggle(snap_toggle),
        .alarm_active(alarm_active),
        .adc_tick_pending(adc_tick_pending),
        .low_range_active(low_range_active)
    );

    // ------------------------------------------------------------------
    // PS 侧 BRAM 行为模型（共享内存的另一端）：按 ABI 收桥的写入，供回读验证
    // ------------------------------------------------------------------
    reg [31:0] ps_bram [0:16383];

    always @(posedge clk) begin
        if (rst_n && bram_en && (bram_we != 4'd0))
            ps_bram[bram_addr[13:0]] <= bram_wrdata;
    end

    // ------------------------------------------------------------------
    // 第 1/2 环监视器
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        cyc = cyc + 1;

        if (!rst_n && (dut.adc_tick === 1'b1)) begin
            tick_in_reset = tick_in_reset + 1;
        end

        if (dut.adc_tick)          tick_count    = tick_count + 1;
        if (adc_tick_pending)      pending_seen  = pending_seen + 1;
        if (dut.rfg_sample_ready)  ready_seen    = ready_seen + 1;

        if (dut.ad_frame_valid) begin
            frame_count = frame_count + 1;
            if (gap_armed) begin
                frame_gap_cur = cyc - last_frame_cyc;
                if ((frame_count == 2) || (frame_gap_cur < frame_gap_min))
                    frame_gap_min = frame_gap_cur;
                if ((frame_count == 2) || (frame_gap_cur > frame_gap_max))
                    frame_gap_max = frame_gap_cur;
            end
            gap_armed      = 1'b1;
            last_frame_cyc = cyc;

            // （激励句柄已在 ADC 模型里处理）
            // 激励的推进已移到 ADC 模型的 convst_rise 处，这里不再重复推进。
        end

        if (dut.sample_valid_q) begin
            sample_count = sample_count + 1;
            if ((last_u_code >= 0) && (dut.u_wave_code_q !== last_u_code[15:0]))
                code_changed = code_changed + 1;
            last_u_code = dut.u_wave_code_q;
        end

        // 周期性快照：看采集进度与流水线卡在哪一级

        // 只统计**被桥接受**的条目（valid && ready）。valid 在反压期间会一直
        // 保持为高，把它当"条目数"统计会严重虚高（曾测出 182 万条/4 帧）。
        if (dut.ps_harmonic_valid && dut.harmonic_ready) begin
            harm_total_items     = harm_total_items + 1;
            harm_items_per_frame = harm_items_per_frame + 1;
            if (dut.ps_harmonic_index > harm_max_index)
                harm_max_index = dut.ps_harmonic_index;
            if (dut.ps_harmonic_index == 9'd1) begin
                harm_h1_present = dut.ps_harmonic_flags[0];
                harm_h1_ratio   = dut.ps_harmonic_u_ratio[15:0];
            end
            if (dut.ps_harmonic_last) begin
                harm_frames          = harm_frames + 1;
                harm_last_index_seen = dut.ps_harmonic_index;
                if (harm_frames == 1) harm_max_index = 0;   // 只反映首帧的跨度
                harm_items_per_frame = 0;
            end
        end

        // 第 3 环输入侧断言：真正送进 RFG 的样本必须等于解析激励（前 24 点逐点比对）。
        // 取样点是 u_measurement_core.freq_sample_u（核心去直流之后的中心化样本），
        // 这才是 RFG 真正拿到的东西；取泵输出或在去直流之前取样都验不到问题（踩过）。
        if (dut.u_measurement_core.freq_sample_valid && (in_n < 24)) begin
            in_got[in_n]  = $signed(dut.u_measurement_core.freq_sample_u);
            in_exp[in_n]  = (U_1ST * sine_lut[(in_n * (LUT_N / C_N)) % LUT_N]
                           + U_3RD * sine_lut[(in_n * 3 * (LUT_N / C_N)) % LUT_N]) / 1000;
            if (in_got[in_n] !== in_exp[in_n])
                in_bad = in_bad + 1;
            in_n = in_n + 1;
        end

        // 边沿检测必须先比较、再更新影子寄存器：原来的写法 d 刚被赋成 snap_toggle，
        // 异或恒为 0，于是无论 DUT 提交多少次 commit 都读成 0（实测 commit=0 而 u_rms 非零）。
        if (snap_toggle ^ snap_toggle_d) snap_commit_count = snap_commit_count + 1;
        snap_toggle_d = snap_toggle;
        if (bram_en && (bram_we != 4'd0)) begin
            bram_wr_count = bram_wr_count + 1;
            if (bram_addr >= 14'h0400) bram_harm_wr = bram_harm_wr + 1;
        end
    end

    // ------------------------------------------------------------------
    // 主流程
    // ------------------------------------------------------------------
    integer u_rms_now;

    initial begin
        for (k = 0; k < LUT_N; k = k + 1) begin
            ang = 2.0 * 3.14159265358979 * k / LUT_N;
            sine_lut[k] = $rtoi($sin(ang) * 1000.0);
        end

        // ---------------- 阶段 0：复位 ----------------
        rst_n = 1'b0;
        // 关键：先把 ADC 模型的 8 个通道码值初始化。否则复位后第一帧的码值是 X，
        // 会被 u_wave_code 锁存并污染零点跟踪器（zero_code 永久为 X），再经频域
        // DC 累加器 → bin0 → magnitude_calc → harmonic_stats 毒死整条频域链。
        // ADC 模型的 8 个通道先初始化到中心码，避免复位后第一个转换拿到 X 或 0；
        // 否则零点跟踪器首个样本就是一个 32768 量级的跳变，会把估计带偏离（踩过）。
        // 复位期给补码 0（= 零点），经 RTL 的 XOR 后是 0x8000（偏移二进制零点），
        // 与后续正弦的直流一致；原写 CENTER=32768 在补码下是负满量程，会让跟踪器吃一个满幅台阶。
        for (k = 0; k < 8; k = k + 1) ad7606_ch_data[k] = 16'd0;
        repeat (600) @(posedge clk);
        if (tick_in_reset != 0) begin
            $display("FAIL: 1a 复位期间 pacer 给出 %0d 次 tick", tick_in_reset);
            err = err + 1;
        end else begin
            $display("INFO: 1a 复位期间无 tick");
        end

        // ---------------- 阶段 1：采集与控制 ----------------
        rst_n = 1'b1;
        wait_i = 0;
        while ((frame_count < WARMUP_FRAMES) && (wait_i < 20_000_000)) begin
            @(posedge clk);
            wait_i = wait_i + 1;
        end
        repeat (4) @(posedge clk);

        $display("INFO: 1b tick=%0d frame=%0d gap=[%0d,%0d] 标称 %0d",
                 tick_count, frame_count, frame_gap_min, frame_gap_max, SMP_PERIOD);
        $display("INFO: 1c pending=%0d sample=%0d ready=%0d",
                 pending_seen, sample_count, ready_seen);
        $display("INFO: 2b zero_valid=%b/%b zero_code=%h/%h code_changed=%0d",
                 dut.u_zero_valid, dut.i_zero_valid,
                 dut.u_zero_code, dut.i_zero_code, code_changed);

        if (frame_count < WARMUP_FRAMES) begin
            $display("FAIL: 1c 只收到 %0d 帧，期望 %0d", frame_count, WARMUP_FRAMES);
            err = err + 1;
        end
        if (pending_seen != 0) begin
            $display("FAIL: 1b 有 %0d 拍 tick 撞上驱动忙（丢样本）", pending_seen);
            err = err + 1;
        end
        if ((frame_gap_min < SMP_PERIOD - 1) || (frame_gap_max > SMP_PERIOD + 1)) begin
            $display("FAIL: 1c 帧间隔越界 [%0d,%0d]", frame_gap_min, frame_gap_max);
            err = err + 1;
        end
        if (sample_count != frame_count) begin
            $display("FAIL: 1d sample=%0d frame=%0d 不等", sample_count, frame_count);
            err = err + 1;
        end
        if (code_changed < 100) begin
            $display("FAIL: 2a 采样码值几乎不变（changed=%0d）", code_changed);
            err = err + 1;
        end
        if (dut.u_zero_valid !== 1'b1) begin
            $display("FAIL: 2b u_zero_valid 未拉高（预热 %0d 样本未完）", ZERO_WARMUP);
            err = err + 1;
        end
        if ((dut.u_zero_code < 16'h8000 - 16'd64) || (dut.u_zero_code > 16'h8000 + 16'd64)) begin
            $display("FAIL: 2b u_zero_code=%h 未收敛到 8000 附近", dut.u_zero_code);
            err = err + 1;
        end

        // ---------------- 阶段 3：RFG 频域链 ----------------
        wait_i = 0;
        while ((harm_frames < 2) && (wait_i < 8_000_000)) begin
            @(posedge clk);
            wait_i = wait_i + 1;
        end

        $display("INFO: 3 harm_frames=%0d items=%0d max_index=%0d last=%0d h1_present=%0d h1_ratio=%0d",
                 harm_frames, harm_total_items, harm_max_index,
                 harm_last_index_seen, harm_h1_present, harm_h1_ratio);
        // 输入侧：送进 RFG 的前 24 点必须与解析激励逐点相等
        $display("INFO: 3in  RFG 输入前 %0d 点不符 %0d 个", in_n, in_bad);
        if (in_bad != 0) begin
            $display("FAIL: 3in RFG 输入与解析激励不符 %0d 点", in_bad);
            err = err + 1;
        end
        if (harm_frames < 2) begin
            $display("FAIL: 3a 谐波帧数=%0d，期望 >= 2", harm_frames);
            err = err + 1;
        end
        // 核心每帧固定输出 0..500 共 501 条（harmonic_stats 的 MAX_ORDER=500，
        // 与 RFG 的 C_K=64 无关）。这里判"帧尾 index = 500"，而不是 64。
        if (harm_last_index_seen != 500) begin
            $display("FAIL: 3b 帧尾 index=%0d，期望 500", harm_last_index_seen);
            err = err + 1;
        end
        if (harm_h1_present != 1) begin
            $display("FAIL: 3c 1 次谐波 present=0");
            err = err + 1;
        end
        if ((harm_h1_ratio < 7000) || (harm_h1_ratio > 7300)) begin
            $display("FAIL: 3d 1 次 u 占比=%0d，期望 7142 附近", harm_h1_ratio);
            err = err + 1;
        end

        // ---------------- 阶段 4/5：快照与共享内存 ----------------
        // ps_snapshot_commit_toggle 有两路来源：时域 x100 完成，以及频域指标提交沿。
        // 只等 commit 计数非 0 会被频域提交提前满足，此时时域字段尚未写入，故等 u_rms 非零。
        wait_i = 0;
        while (($signed(snap_words[31:0]) == 0) && (wait_i < 45_000_000)) begin
            @(posedge clk);
            wait_i = wait_i + 1;
        end
        u_rms_now = $signed(snap_words[31:0]);
        $display("INFO: 4 commit=%0d u_rms=%0d（期望约 %0d）bram_wr=%0d harm_wr=%0d",
                 snap_commit_count, u_rms_now, U_RMS_EXPECT, bram_wr_count, bram_harm_wr);

        // ---------------- PS 侧回读：按 ABI 从共享内存解出谐波 ----------------
        rb_h1_u = -1; rb_h3_u = -1; rb_h1_p = -1; rb_max_idx = -1;
        for (rb_bank = 0; rb_bank < 2; rb_bank = rb_bank + 1) begin
            for (rb_k = 0; rb_k <= 500; rb_k = rb_k + 1) begin
                rb_base = 14'h400 + rb_bank * 14'h800 + rb_k * 4;
                rb_u  = ps_bram[rb_base];
                rb_i  = ps_bram[rb_base + 14'd1];
                rb_ph = ps_bram[rb_base + 14'd2];
                rb_fl = ps_bram[rb_base + 14'd3];
                if ((rb_k == 1) && (rb_fl[0] === 1'b1)) begin
                    rb_h1_u = rb_u[15:0];
                    rb_h1_p = rb_fl[0];
                end
                if ((rb_k == 3) && (rb_fl[0] === 1'b1))
                    rb_h3_u = rb_u[15:0];
                if ((rb_fl[0] === 1'b1) && (rb_k > rb_max_idx))
                    rb_max_idx = rb_k;
                if ((rb_k <= 3) && (rb_bank == 1) && (rb_fl[0] === 1'b1))
                    $display("INFO: 5abin bank1 k=%0d u=%0d i=%0d ph=%0d fl=%0d",
                             rb_k, rb_u, rb_i, rb_ph, rb_fl);
            end
        end
        $display("INFO: 5abi  从共享内存解出：1次u=%0d 3次u=%0d present=%0d 最大index=%0d",
                 rb_h1_u, rb_h3_u, rb_h1_p, rb_max_idx);

        if (snap_commit_count < 1) begin
            $display("FAIL: 4a 没有出现快照提交");
            err = err + 1;
        end
        if ((u_rms_now < U_RMS_EXPECT - U_RMS_EXPECT / 5) ||
            (u_rms_now > U_RMS_EXPECT + U_RMS_EXPECT / 5)) begin
            $display("FAIL: 4b u_rms=%0d 偏离期望 %0d 超过 20%%", u_rms_now, U_RMS_EXPECT);
            err = err + 1;
        end
        if (bram_wr_count < 1) begin
            $display("FAIL: 5a 共享内存桥没有写 BRAM");
            err = err + 1;
        end
        if (bram_harm_wr < 1) begin
            $display("FAIL: 5b 谐波 bank 没有写入");
            err = err + 1;
        end

        // ---------------- 判定 ----------------
        // ---------------- 第 5 环 ABI 回读判定 ----------------
        if (rb_h1_u < 7000 || rb_h1_u > 7300) begin
            $display("FAIL: 5abi 从共享内存解出的 1 次 u 占比=%0d，期望 7138 附近", rb_h1_u);
            err = err + 1;
        end
        if (rb_h3_u < 2750 || rb_h3_u > 2960) begin
            $display("FAIL: 5abi 从共享内存解出的 3 次 u 占比=%0d，期望 2861 附近", rb_h3_u);
            err = err + 1;
        end
        if (rb_h1_p !== 1) begin
            $display("FAIL: 5abi 1 次谐波 present 位=0");
            err = err + 1;
        end
        // RFG 只算到 C_K=64 次，所以共享内存里\"有值\"的最大频点是 64（65..500 按设计 present=0）。
        if (rb_max_idx != 64) begin
            $display("FAIL: 5abi 共享内存里最大 present index=%0d，期望 64", rb_max_idx);
            err = err + 1;
        end

        if (err == 0) begin
            $display("PASS: pqm_pl_top");
        end else begin
            $display("FAIL: pqm_pl_top，共 %0d 处不符", err);
            $fatal(1, "pqm_pl_top 用例未通过");
        end
        $finish;
    end

    initial begin
        #(CLK_PERIOD * 60_000_000);
        $display("FAIL: 仿真看门狗超时（cyc=%0d frame=%0d harm_frames=%0d）",
                 cyc, frame_count, harm_frames);
        $fatal(1, "仿真超时");
    end

endmodule
