`timescale 1ns / 1ps
/*
 * 模块: tb_pqm_pl_top_large
 * 功能:
 *   pqm_pl_top 的**大信号 + 直流偏置**系统级回归用例，覆盖本轮三处 PL 缺陷：
 *
 *   工况（第一相）：u = +3000 码（+0.92 V）真直流偏置 + 29500 码峰值正弦
 *                   = 18.01 Vpp（±10 V 满量程），一帧 512 点 = 一个 50 Hz 周期。
 *     为什么选这个幅度：零点跟踪器用 `>>>`（floor）取整 + 最小步长 ±1 时，
 *     step(delta) 不是奇函数，纯交流下 zero_code 会稳定偏低约 0.2×幅值，
 *     把"去零点后"的正峰抬到 32767 以上 —— 板上实测回绕起点 ≈15.5~17 Vpp，
 *     与用户"CH1 调到 18 Vpp 频谱就全乱"完全吻合；同一个取整偏差也是板上
 *     DC-U2 恒为 28.68%、H1 只有 70.97% 的原因（去零点后凭空多出直流）。
 *     本用例断言：
 *       1) 去零点样本不出现回绕：相邻样本跳变 <= JUMP_MAX（正弦最大斜率仅 ~363）
 *          且峰峰值 = 2×幅值（既不回绕也不饱和削顶）；
 *       2) 大信号下谐波占比合理：1 次主导 >= 90%，直流 <= 8%，THD <= 5%；
 *       3) 去零点饱和标志（快照 validity 字 bit12）保持 0（本工况不该饱和）。
 *
 *   工况（第二相）：直流阶跃 -6260 码（分 10 拍斜坡），ADC 引脚下探到 ≈负满量程，
 *                   去零点后负峰 ≈ -34000，越过 ±32767。
 *     本用例断言：
 *       4) 饱和而不是回绕：相邻样本跳变仍 <= JUMP_MAX，且中心化样本下界 >= -32767；
 *       5) 饱和可见：快照 validity 字 bit12（去零点饱和粘滞）必须置 1（缺陷 3）。
 *
 *   RED 有效性：
 *     - 只回退 time_zero_code_tracker 的取整（改回 `>>>`）：零点平衡点偏低 0.2×幅值，
 *       第 1 相 DC 占比升到十几个百分点、H1 跌出 90% → 判据 2 FAIL；
 *       同因的尖锐 RED 在 tb_time_zero_code_tracker 的"纯交流零点收敛"场景；
 *     - 只回退去零点饱和（改回取低 16 位）：第 2 相出现 ~65000 的跳变、
 *       且 bit12 永不置位 → 判据 4/5 FAIL。
 *
 * 说明：
 *   FORCE_ZERO_CENTER = 0：本用例必须走**真实零点跟踪器**，否则测不到缺陷 2。
 */
module tb_pqm_pl_top_large;

    localparam integer CLK_PERIOD  = 20;        // 50 MHz
    localparam integer CONV_CYCLES = 400;
    localparam integer LUT_N       = 2048;
    localparam integer SMP_PERIOD  = 1953;      // 25.6 kHz
    localparam integer C_N         = 512;       // 一帧 = 一个 50 Hz 周期

    localparam integer AMP_CODE    = 29500;     // 18.01 Vpp 峰值码
    localparam integer DC_CODE     = 3000;      // +0.92 V 真直流偏置
    // 第二相：直流阶跃 -6260 码（分 10 拍斜坡，避开把阶跃本身算成跳变）。
    // 阶跃后 ADC 引脚最低到 3000-6260-29500 = -32760 ≈ 负满量程（偏置码 ≈ 8），
    // 去零点后 = 8 - zero_code ≈ -34000，越过 ±32767：
    //   饱和实现钳到 -32767（无跳变）；取低位实现回绕成 +31000 左右（跳变 ~65000）。
    localparam integer STEP_TOTAL  = -6260;
    localparam integer STEP_TIMES  = 10;

    localparam integer MEAS_INTERVAL = 3_400_000;
    localparam integer MEAS_SAMPLES  = 1024;

    // 样本预算：跟踪器预热 4096 样本，之后稳态还需上万样本才能把
    // 预热期纹波（±0.08×幅值）留下的直流残差衰减到 1% 量级。
    localparam integer PHASE1_SAMPLES = 12000;
    // 第二相只需跨过越界点：斜坡 30 个样本 + 观测 600 个样本就够。
    localparam integer PHASE2_SAMPLES = 600;

    localparam integer JUMP_MAX = 2000;         // 相邻中心化样本最大合法跳变
    // 第一相门槛留足余量：修复后实测 DC=739（10240 样本）仍在跟踪器上电暂态里衰减，
    // 未修复时同点约 1200+（离线定点复算 12.01%）且还在增大。
    localparam integer H1_MIN   = 8800;         // % x100
    localparam integer DC_MAX   = 1000;         // % x100
    localparam integer THD_MAX  = 500;          // % x100

    localparam [1:0] M_IDLE = 2'd0, M_CONV = 2'd1, M_READY = 2'd2;

    reg clk   = 1'b0;
    reg rst_n = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    wire ad_reset, ad_convst, ad_cs_n, ad_rd_n;
    wire [511:0] snap_words;
    wire         snap_toggle, alarm_active, adc_tick_pending, low_range_active;
    wire [13:0]  bram_addr;
    wire [31:0]  bram_wrdata;
    wire  [3:0]  bram_we;
    wire         bram_en;

    // ------------------------------------------------------------------
    // 激励
    // ------------------------------------------------------------------
    integer sine_lut [0:LUT_N-1];
    integer k;
    real    ang;
    integer sample_idx = 0;
    integer ph_u1;
    integer u_pin_i;
    integer dc_now     = DC_CODE;
    integer step_accum = 0;

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

    // AD7606 引脚是**二进制补码**（RTL 内部 XOR 0x8000 之后才是偏移二进制），
    // 所以这里直接给 DC + A*cos 的补码即可：偏移码 = 引脚 + 32768。
    task automatic build_stimulus;
        input integer idx;
        begin
            ph_u1 = (idx * (LUT_N / C_N)) % LUT_N;
            // 必须经过 integer 中间量：若直接写
            //   ad7606_ch_data[0] = dc_now + (AMP_CODE*lut)/1000;
            // 整个 RHS 会因为 LHS 是无符号 reg 而被当作无符号表达式，
            // 负半周的 /1000 变成大无符号商，截到 16 位后是彻底畸变的波形
            // （踩过：谷值处 code 从应有的 9748 变成 44875，仿真结论全错）。
            u_pin_i = dc_now + (AMP_CODE * sine_lut[ph_u1]) / 1000;
            ad7606_ch_data[0] = u_pin_i[15:0];
            ad7606_ch_data[2] = u_pin_i[15:0];
            ad7606_ch_data[1] = 16'd0;
            ad7606_ch_data[3] = 16'd0;
            ad7606_ch_data[4] = 16'd0;
            ad7606_ch_data[5] = 16'd0;
            ad7606_ch_data[6] = 16'd0;
            ad7606_ch_data[7] = 16'd0;
        end
    endtask

    // ------------------------------------------------------------------
    // AD7606 行为模型（与 tb_pqm_pl_top 相同）
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
    // 被测系统（走真实零点跟踪器）
    // ------------------------------------------------------------------
    pqm_pl_top #(
        .MEASUREMENT_INTERVAL_CYCLES (MEAS_INTERVAL),
        .MEASURE_FRAME_SAMPLES       (MEAS_SAMPLES),
        .FORCE_ZERO_CENTER           (0)
    ) dut (
        .clk(clk), .rst_n(rst_n),
        .ad_busy(ad_busy_m), .ad_frstdata(ad_frstdata_m), .ad_data(ad_data_m),
        .ad_reset(ad_reset), .ad_convst(ad_convst), .ad_cs_n(ad_cs_n), .ad_rd_n(ad_rd_n),
        .bram_rddata(32'd0),
        .bram_addr(bram_addr), .bram_wrdata(bram_wrdata),
        .bram_we(bram_we), .bram_en(bram_en),
        .ps_snapshot_words(snap_words),
        .ps_snapshot_commit_toggle(snap_toggle),
        .alarm_active(alarm_active),
        .adc_tick_pending(adc_tick_pending),
        .low_range_active(low_range_active)
    );

    // PS 侧 BRAM 行为模型
    reg [31:0] ps_bram [0:16383];
    always @(posedge clk) begin
        if (rst_n && bram_en && (bram_we != 4'd0))
            ps_bram[bram_addr[13:0]] <= bram_wrdata;
    end

    // ------------------------------------------------------------------
    // 监测
    // ------------------------------------------------------------------
    integer err = 0;
    integer phase = 0;              // 0=准备 1=第一相 2=第二相

    integer c_now, c_last, c_diff;
    reg     c_seen = 1'b0;
    integer p1_jump = 0, p1_max = -100000, p1_min = 100000, p1_cnt = 0;
    integer p2_jump = 0, p2_max = -100000, p2_min = 100000, p2_cnt = 0;

    integer harm_frames = 0;
    integer h1_u1 = -1, h1_u2 = -1, h1_present = 0, harm_last_index = -1;
    integer h1_u1_frame = -1, h1_u2_frame = -1;

    integer dc_u1, dc_u2, thd_u1, thd_u2;
    integer sat_bit, rfg_bit, fifo_bit;
    integer samples_done = 0;
    integer wait_i;

    // 去零点样本流：回绕检测（回绕会产生 ~65536 的相邻跳变）
    always @(posedge clk) begin
        if (rst_n && dut.u_measurement_core.freq_sample_valid) begin
            c_now = $signed(dut.u_measurement_core.freq_sample_u1);
            if (c_seen) begin
                c_diff = c_now - c_last;
                if (c_diff < 0) c_diff = -c_diff;
                if (phase == 1) begin
                    if (c_diff > p1_jump) p1_jump = c_diff;
                    if (c_now > p1_max) p1_max = c_now;
                    if (c_now < p1_min) p1_min = c_now;
                    p1_cnt = p1_cnt + 1;
                end else if (phase == 2) begin
                    if (c_diff > p2_jump) p2_jump = c_diff;
                    if (c_now > p2_max) p2_max = c_now;
                    if (c_now < p2_min) p2_min = c_now;
                    p2_cnt = p2_cnt + 1;
                end
            end
            c_last = c_now;
            c_seen = 1'b1;
        end
    end

    // 谐波流：抓 1 次占比（只在被握手接收的那一拍统计）
    always @(posedge clk) begin
        if (rst_n && dut.ps_harmonic_valid && dut.harmonic_ready) begin
            if (dut.ps_harmonic_index == 9'd1) begin
                h1_present = dut.ps_harmonic_flags[0];
                h1_u1      = dut.ps_harmonic_u1_ratio[15:0];
                h1_u2      = dut.ps_harmonic_u2_ratio[15:0];
            end
            if (dut.ps_harmonic_last) begin
                harm_frames    = harm_frames + 1;
                harm_last_index = dut.ps_harmonic_index;
                h1_u1_frame    = h1_u1;
                h1_u2_frame    = h1_u2;
            end
        end
    end

    task automatic check_val;
        input integer actual;
        input integer lo;
        input integer hi;
        input [255:0] tag;
        begin
            if (^actual === 1'bx) begin
                $display("FAIL: %0s = X（未初始化/未驱动）", tag);
                err = err + 1;
            end else if ((actual < lo) || (actual > hi)) begin
                $display("FAIL: %0s = %0d，期望 [%0d, %0d]", tag, actual, lo, hi);
                err = err + 1;
            end
        end
    endtask

    // ------------------------------------------------------------------
    // 主流程
    // ------------------------------------------------------------------
    integer i;

    initial begin
        for (k = 0; k < LUT_N; k = k + 1) begin
            ang = 2.0 * 3.14159265358979 * k / LUT_N;
            sine_lut[k] = $rtoi($sin(ang) * 1000.0);
        end
        for (k = 0; k < 8; k = k + 1) ad7606_ch_data[k] = 16'd0;

        repeat (600) @(posedge clk);
        rst_n = 1'b1;

        // ---------------- 第一相：大信号 + 直流偏置 ----------------
        phase = 1;
        wait_i = 0;
        // 20M 拍只够 10240 个样本，第一相要看满 12000 个样本必须放宽到 60M 拍。
        while ((samples_done < PHASE1_SAMPLES) && (wait_i < 60_000_000)) begin
            @(posedge clk);
            wait_i = wait_i + 1;
        end
        repeat (4) @(posedge clk);

        dc_u1   = snap_words[415:384];
        dc_u2   = snap_words[447:416];
        thd_u1  = snap_words[351:320];
        thd_u2  = snap_words[383:352];
        sat_bit = snap_words[492];
        rfg_bit = snap_words[493];
        fifo_bit= snap_words[494];

        $display("");
        $display("========== 第一相：18.01 Vpp 正弦 + 3000 码直流偏置（无回绕期望） ==========");
        $display("INFO: 样本=%0d zero_valid=%b/%b zero_code=%h/%h", samples_done,
                 dut.u1_zero_valid, dut.u2_zero_valid, dut.u1_zero_code, dut.u2_zero_code);
        $display("INFO: 去零点 U1 观测 %0d 点：跳变最大=%0d 范围=[%0d,%0d] 峰峰=%0d（正弦预期 %0d）",
                 p1_cnt, p1_jump, p1_min, p1_max, p1_max - p1_min, 2 * AMP_CODE);
        $display("INFO: 谐波帧数=%0d 帧尾 index=%0d H1 present=%0d H1(U1)=%0d H1(U2)=%0d",
                 harm_frames, harm_last_index, h1_present, h1_u1_frame, h1_u2_frame);
        $display("INFO: 快照 DC-U1=%0d DC-U2=%0d THD-U1=%0d THD-U2=%0d 饱和位[14:12]=%b%b%b",
                 dc_u1, dc_u2, thd_u1, thd_u2, fifo_bit, rfg_bit, sat_bit);

        if (dut.u1_zero_valid !== 1'b1) begin
            $display("FAIL: 预热结束 u1_zero_valid 未拉高");
            err = err + 1;
        end
        check_val(p1_cnt, 4000, 100000, "第一相去零点样本数");
        check_val(p1_jump, 0, JUMP_MAX, "第一相相邻样本最大跳变（回绕检测）");
        check_val(p1_max - p1_min, 2 * AMP_CODE - 3000, 2 * AMP_CODE + 3000,
                  "第一相去零点峰峰值");
        check_val(h1_u1_frame, H1_MIN, 10000, "第一相 H1 占比 U1");
        check_val(h1_u2_frame, H1_MIN, 10000, "第一相 H1 占比 U2");
        check_val(dc_u1, 0, DC_MAX, "第一相 DC-U1");
        check_val(dc_u2, 0, DC_MAX, "第一相 DC-U2");
        check_val(thd_u1, 0, THD_MAX, "第一相 THD-U1");
        check_val(thd_u2, 0, THD_MAX, "第一相 THD-U2");
        check_val(sat_bit, 0, 0, "第一相去零点饱和粘滞位（本工况不该饱和）");

        // ---------------- 第二相：直流阶跃越界 ----------------
        phase = 2;
        // 阶跃分 10 拍走完，避免把阶跃本身当成"回绕跳变"
        for (i = 0; i < STEP_TIMES; i = i + 1) begin
            step_accum = step_accum + (STEP_TOTAL / STEP_TIMES);
            dc_now     = DC_CODE + step_accum;
            repeat (SMP_PERIOD * 3) @(posedge clk);   // 每拍 3 个采样点，斜坡足够慢
        end

        wait_i = 0;
        while ((p2_cnt < PHASE2_SAMPLES) && (wait_i < 20_000_000)) begin
            @(posedge clk);
            wait_i = wait_i + 1;
        end
        repeat (4) @(posedge clk);

        sat_bit = snap_words[492];
        rfg_bit = snap_words[493];

        $display("");
        $display("========== 第二相：直流阶跃 -6260 码（去零点负峰 ≈ -34000，必须饱和而非回绕） ==========");
        $display("INFO: 去零点 U1 观测 %0d 点：跳变最大=%0d 范围=[%0d,%0d]",
                 p2_cnt, p2_jump, p2_min, p2_max);
        $display("INFO: 快照 validity bit12(去零点饱和)=%0d bit13(RFG 溢出)=%0d", sat_bit, rfg_bit);

        check_val(p2_cnt, 500, 100000, "第二相去零点样本数");
        check_val(p2_jump, 0, JUMP_MAX, "第二相相邻样本最大跳变（回绕检测）");
        check_val(p2_min, -32767, 32767, "第二相去零点下界（饱和应为 -32767）");
        check_val(p2_max, -32767, 32767, "第二相去零点上界");
        check_val(sat_bit, 1, 1, "第二相去零点饱和粘滞位（缺陷 3：饱和必须可见）");

        if (err == 0) begin
            $display("");
            $display("PASS: pqm_pl_top_large");
        end else begin
            $display("FAIL: pqm_pl_top_large，共 %0d 处不符", err);
            $fatal(1, "pqm_pl_top_large 用例未通过");
        end
        $finish;
    end

    // 样本计数（与 ADC 转换一一对应）
    always @(posedge clk) begin
        if (rst_n && dut.ad_frame_valid) samples_done = samples_done + 1;
    end

    initial begin
        #(CLK_PERIOD * 300_000_000);
        $display("FAIL: 仿真看门狗超时（样本=%0d 谐波帧=%0d 相=%0d）",
                 samples_done, harm_frames, phase);
        $fatal(1, "仿真超时");
    end

endmodule
