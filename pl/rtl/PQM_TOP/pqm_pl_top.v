`timescale 1ns / 1ps

/*
 * 模块: pqm_pl_top
 * 功能:
 *   PQM2 的 PL 测量链顶层：把 ADC 采集、零点跟踪、时域测量、RFG 频域分析
 *   和共享内存 ABI 桥接成一条完整链路。视频显示段（VDMA 等）不在这里。
 *
 * 链路：
 *   AD7606 引脚
 *     -> AD7606_Parallel_DRIVER（一帧 8 通道）
 *     -> 补码 XOR 0x8000 转偏移二进制
 *     -> time_zero_code_tracker x2（U/I 各自跟踪零点）
 *     -> pqm_measurement_core
 *          ├─ 时域链：time_parameters_initiator -> time_x100_normalizer
 *          └─ 频域链：pqm_freq_analysis_rfg（内部自带 64 深取样 FIFO）
 *     -> 512 位标量快照 + 谐波流
 *     -> pqm_shared_memory_bridge <-> PS 侧 BRAM
 *
 * 采样节拍：
 *   pqm_adc_pacer 每 1953.125 拍（平均 25.6 kHz）产出一个 tick；
 *   本模块只看 AD7606 驱动空闲时把它转成 start 脉冲，tick 到来而驱动仍忙时
 *   置 adc_tick_pending 粘滞标志（正常时序下不应发生：一帧约占 700 拍，周期 1953 拍）。
 *   这样"平均 25.6 kHz"不被驱动忙闲破坏，同时丢掉样本这件事是**可见**的。
 *
 * 输入:
 *   clk / rst_n        : 50 MHz 工作时钟（与 AD7606 通路同域）与低有效复位。
 *   ad_busy/frstdata/data : AD7606 引脚输入。
 *   command_response_valid / bram_rddata : 共享内存桥的 PS 侧回应与读数据。
 *
 * 输出:
 *   ad_reset/convst/cs_n/rd_n : AD7606 控制引脚。
 *   bram_*                    : 共享内存（PS 侧 BRAM）接口。
 *   ps_snapshot_words         : 当前标量快照（便于系统级监测直接观察）。
 *
 * 参数:
 *   MEASUREMENT_INTERVAL_CYCLES: 时域测量启动间隔。时域链要填满 6144 个样本
 *     （25.6 kHz 下约 12 M 拍）才产出一次有效结果，所以默认值必须大于它，
 *     否则每次都在窗口没填满时启动、结果长期为 0。
 *   MEASURE_FRAME_SAMPLES: 传给 pqm_measurement_core 内部的测量窗口长度。
 */
module pqm_pl_top #(
    parameter integer MEASUREMENT_INTERVAL_CYCLES = 16_000_000,
    parameter integer MEASURE_FRAME_SAMPLES        = 6144,
    // 调试开关：为 1 时零点码固定为精确中心 0x8000，绕过零点跟踪器。
    // 用途：分离"奇次泄漏是零点偏移造成的"还是"链本身的"。生产用 0。
    parameter integer FORCE_ZERO_CENTER             = 0
)(
    input  wire         clk,
    input  wire         rst_n,

    // ---------------- AD7606 引脚 ----------------
    input  wire         ad_busy,
    input  wire         ad_frstdata,
    input  wire [15:0]  ad_data,
    output wire         ad_reset,
    output wire         ad_convst,
    output wire         ad_cs_n,
    output wire         ad_rd_n,

    // ---------------- 共享内存桥（PS 侧） ----------------
    input  wire         command_response_valid,
    input  wire [31:0]  bram_rddata,
    output wire [13:0]  bram_addr,
    output wire [31:0]  bram_wrdata,
    output wire  [3:0]  bram_we,
    output wire         bram_en,

    // ---------------- 监测引出（不参与功能） ----------------
    output wire [511:0] ps_snapshot_words,
    output wire         ps_snapshot_commit_toggle,
    output wire         alarm_active,
    output wire         adc_tick_pending,      // tick 撞上驱动忙：丢样本，正常应为 0
    output wire         low_range_active
);

    // ------------------------------------------------------------------
    // 采样节拍：pacer -> AD7606 启动
    // ------------------------------------------------------------------
    wire adc_tick;

    pqm_adc_pacer u_adc_pacer (
        .clk    (clk),
        .rst_n  (rst_n),
        .o_tick (adc_tick)
    );

    // AD7606 控制器的状态编码：3'd1 = ST_IDLE（见 ad7606_parallel_ctrl.v）
    wire [2:0]  ad_state;
    wire        ad_driver_idle = (ad_state == 3'd1);

    reg         adc_start;
    reg         adc_tick_pending_r;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            adc_start           <= 1'b0;
            adc_tick_pending_r  <= 1'b0;
        end else begin
            adc_start <= 1'b0;

            if (adc_tick) begin
                if (ad_driver_idle) begin
                    adc_start <= 1'b1;
                end else begin
                    // 驱动还没回到空闲：这一拍启动不了。记下来，别静默丢掉。
                    adc_tick_pending_r <= 1'b1;
                end
            end
        end
    end

    assign adc_tick_pending = adc_tick_pending_r;

    // ------------------------------------------------------------------
    // AD7606 采集
    // ------------------------------------------------------------------
    wire [15:0]  ad_ch1, ad_ch2, ad_ch3, ad_ch4;
    wire [15:0]  ad_ch5, ad_ch6, ad_ch7, ad_ch8;
    wire [127:0] ad_frame;
    wire         ad_frame_valid;
    wire         ad_sample_active;
    wire         ad_timeout;
    wire [3:0]   ad_channal;

    AD7606_Parallel_DRIVER u_ad7606 (
        .clk          (clk),
        .rst_n        (rst_n),
        .start        (adc_start),
        .soft_reset   (1'b0),
        .ad_busy      (ad_busy),
        .ad_frstdata  (ad_frstdata),
        .ad_data      (ad_data),
        .ad_reset     (ad_reset),
        .ad_convst    (ad_convst),
        .ad_cs_n      (ad_cs_n),
        .ad_rd_n      (ad_rd_n),
        .ch1_data     (ad_ch1),
        .ch2_data     (ad_ch2),
        .ch3_data     (ad_ch3),
        .ch4_data     (ad_ch4),
        .ch5_data     (ad_ch5),
        .ch6_data     (ad_ch6),
        .ch7_data     (ad_ch7),
        .ch8_data     (ad_ch8),
        .data_frame   (ad_frame),
        .data_valid   (ad_frame_valid),
        .sample_active(ad_sample_active),
        .timeout      (ad_timeout),
        .ad_channal   (ad_channal),
        .ad_state     (ad_state)
    );

    // ------------------------------------------------------------------
    // 补码 -> 偏移二进制，并打一拍与码值对齐
    //   驱动在 frame_valid 那一拍把码值锁进 ch*_data，所以下一拍读 ch*_data
    //   才是本帧的码值。旧工程 pqm_pl_core 用同样的写法。
    // ------------------------------------------------------------------
    // 采样代数（共两级，全部同步）：
    //   stage-1  sampler1：锁存本拍的有效码值 + 产出 padded frame_valid
    //   stage-2  sampler2：把码值、零点码、valid 三个量在**同一个 always 块里**
    //                      同一级寄存，保证下游拿到的三者严格同拍。
    // 为什么这样做：同步电路里每个寄存器都在同一时钟沿并行锁存，任何"用寄存器
    // 做组合运算"的地方读到的是上一拍的值。之前把码值、零码、valid 分在不同 always
    // 块里打不同级数的拍，于是核心的组合减法 u_sample_code - u_zero_code 拿到的是
    // 不同格的两个量，恒差 0x8000（实测 freq_sample_u = 真值 - 32768）。
    // 把三者放进同一个 always 块后，它们必然同格，该错位在结构上不可能再出现。
    reg  [15:0] u_wave_code;        // stage-1
    reg  [15:0] i_wave_code;        // stage-1
    reg         wave_sample_valid;  // stage-1
    reg  [15:0] u_wave_code_q;      // stage-2（送下游的码值）
    reg  [15:0] i_wave_code_q;      // stage-2
    reg  [15:0] u_zero_code;        // stage-2（送下游的零码）
    reg  [15:0] i_zero_code;        // stage-2
    reg         sample_valid_q;     // stage-2（送下游的 valid）

    // ---- 零点跟踪（用 stage-1 的码值与 valid，输出在 stage-2 与码值同拍寄存）----
    wire [15:0] u_zero_code_raw, i_zero_code_raw;
    wire        u_zero_valid, i_zero_valid;

    time_zero_code_tracker #(
        .WIDTH(16), .EST_SHIFT(14), .WARMUP_SHIFT(10), .WARMUP_SAMPLES(4096)
    ) u_zero_tracker_u (
        .clk(clk), .rst_n(rst_n),
        .sample_valid(wave_sample_valid), .sample_code(u_wave_code),
        .zero_code(u_zero_code_raw), .zero_valid(u_zero_valid)
    );

    time_zero_code_tracker #(
        .WIDTH(16), .EST_SHIFT(14), .WARMUP_SHIFT(10), .WARMUP_SAMPLES(4096)
    ) u_zero_tracker_i (
        .clk(clk), .rst_n(rst_n),
        .sample_valid(wave_sample_valid), .sample_code(i_wave_code),
        .zero_code(i_zero_code_raw), .zero_valid(i_zero_valid)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            u_wave_code       <= 16'h8000;
            i_wave_code       <= 16'h8000;
            wave_sample_valid <= 1'b0;
            u_wave_code_q     <= 16'h8000;
            i_wave_code_q     <= 16'h8000;
            u_zero_code       <= 16'h8000;
            i_zero_code       <= 16'h8000;
            sample_valid_q    <= 1'b0;
        end else begin
            // ---- stage-1 ----
            // 码值只在 frame_valid 那一拍锁存：那一拍 ad_ch1/ad_ch3 恰好是本帧值。
            if (ad_frame_valid) begin
                u_wave_code <= ad_ch1 ^ 16'h8000;
                i_wave_code <= ad_ch3 ^ 16'h8000;
            end
            // （首帧不再特殊抑制：TB 已在复位期把 ADC 模型初始化到中心码，
            //   首帧码值本身就是有效的；之前抑制首帧反而给跟踪器造出一个
            //   "从 0 跳到中心值"的巨大台阶，导致估计被带偏 32768。）
            wave_sample_valid <= ad_frame_valid;

            // ---- stage-2 ----
            u_wave_code_q <= u_wave_code;
            i_wave_code_q <= i_wave_code;
            u_zero_code   <= FORCE_ZERO_CENTER ? 16'h8000 : u_zero_code_raw;
            i_zero_code   <= FORCE_ZERO_CENTER ? 16'h8000 : i_zero_code_raw;
            sample_valid_q <= wave_sample_valid;
        end
    end


    // ------------------------------------------------------------------
    // 频域链取样口（仅作观察）
    //   pqm_measurement_core 内部把去直流后的样本直接喂给 pqm_freq_analysis_rfg，
    //   RFG 自带 64 深取样 FIFO（pqm_sample_fifo，DEPTH=64），实测从未写满，够用。
    //   核心前方原先还挂了一级 pqm_rfg_sample_pump(128 深)，但它的 o_sample_valid/
    //   o_sample_u/o_sample_i 在本链里没有任何消费者（纯死逻辑，综合会优化掉），已删除。
    // ------------------------------------------------------------------
    wire        rfg_sample_ready;

    // ------------------------------------------------------------------
    // 测量核心：时域链 + RFG 频域链 + 快照组装
    // ------------------------------------------------------------------
    wire         ps_harmonic_valid, ps_harmonic_last;
    wire [8:0]   ps_harmonic_index;
    wire [31:0]  ps_harmonic_u_ratio, ps_harmonic_i_ratio;
    wire [31:0]  ps_harmonic_phase, ps_harmonic_flags;
    wire         harmonic_ready;

    pqm_measurement_core #(
        .MEASUREMENT_INTERVAL_CYCLES (MEASUREMENT_INTERVAL_CYCLES),
        .MEASURE_FRAME_SAMPLES       (MEASURE_FRAME_SAMPLES)
    ) u_measurement_core (
        .clk                        (clk),
        .rst_n                      (rst_n),
        .full_scale_low_range_active(low_range_active),
        .u_sample_valid             (sample_valid_q),
        .u_sample_code              (u_wave_code_q),
        .u_zero_code                (u_zero_code),
        .u_zero_valid               (u_zero_valid),
        .i_sample_valid             (sample_valid_q),
        .i_sample_code              (i_wave_code_q),
        .i_zero_code                (i_zero_code),
        .i_zero_valid               (i_zero_valid),
        .ps_harmonic_ready          (harmonic_ready),
        .alarm_active               (alarm_active),
        .ps_snapshot_words          (ps_snapshot_words),
        .ps_snapshot_commit_toggle  (ps_snapshot_commit_toggle),
        .ps_harmonic_valid          (ps_harmonic_valid),
        .ps_harmonic_last           (ps_harmonic_last),
        .ps_harmonic_index          (ps_harmonic_index),
        .ps_harmonic_u_ratio        (ps_harmonic_u_ratio),
        .ps_harmonic_i_ratio        (ps_harmonic_i_ratio),
        .ps_harmonic_phase          (ps_harmonic_phase),
        .ps_harmonic_flags          (ps_harmonic_flags),
        .freq_sample_ready          (rfg_sample_ready)
    );

    // ------------------------------------------------------------------
    // 谐波帧头适配（关键，踩过）
    //   共享内存桥的协议是「先帧头、再逐条」：harmonic_ready 只在
    //   STATE_IDLE && harmonic_frame_active 时为高，而 frame_active 要靠
    //   harmonic_frame_start 置起。核心侧没有帧头信号，只有逐条的 last。
    //   若把 frame_start 直接接 last，则第一条永远拿不到 ready，下游全链
    //   反压死锁（实测：RFG 首帧算完后 scal=1/0、hs_ready=0 永久卡死）。
    //   帧头策略：检测到 index 0 时，把那条数据**扣住一拍**（hold 寄存器），
    //   同时把脉冲打一拍。于是桥先看到脉冲（置 frame_active）、下一拍收到首条数据。
    //   之前两版都不对：
    //     v1「index 0 同拍发脉冲并清数据」→ 帧头有效，但 H0 那条被永久丢弃
    //        （实测共享内存只有 k=1..63、无 k=0）。
    //     v2「末条发脉冲」→ 上电首帧没有"末条"可参考，核心卡在第一条，
    //        实测 hsp_seen=0、ps_harmonic_last 永不出现、流永久卡死。
    //   现在：脉冲与数据分两拍，首帧也能起步，且一条不丢。
    // ------------------------------------------------------------------
    reg        hrm_start_pulse_ff;
    reg        hrm_hold;
    reg        hrm_valid_d;
    reg [8:0]  hrm_index_d;
    reg [31:0] hrm_u_d, hrm_i_d, hrm_phase_d, hrm_flags_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hrm_hold           <= 1'b0;
            hrm_start_pulse_ff <= 1'b0;
            hrm_valid_d        <= 1'b0;
            hrm_index_d        <= 9'd0;
            hrm_u_d            <= 32'd0;
            hrm_i_d            <= 32'd0;
            hrm_phase_d        <= 32'd0;
            hrm_flags_d        <= 32'd0;
        end else begin
            if (hrm_hold) begin
                // 第二拍：重发被扣住的首条（此时桥已置起 frame_active）
                hrm_valid_d <= 1'b1;
                hrm_hold    <= 1'b0;
            end else if (ps_harmonic_valid && (ps_harmonic_index == 9'd0)) begin
                // 帧首：打一拍把脉冲送给桥，同时把这条数据扣进寄存器
                hrm_valid_d <= 1'b0;
                hrm_hold    <= 1'b1;

                hrm_index_d <= 9'd0;
                hrm_u_d     <= ps_harmonic_u_ratio;
                hrm_i_d     <= ps_harmonic_i_ratio;
                hrm_phase_d <= ps_harmonic_phase;
                hrm_flags_d <= ps_harmonic_flags;
            end else begin
                // 常规：整条流打一拍
                hrm_valid_d <= ps_harmonic_valid;
                hrm_index_d <= ps_harmonic_index;
                hrm_u_d     <= ps_harmonic_u_ratio;
                hrm_i_d     <= ps_harmonic_i_ratio;
                hrm_phase_d <= ps_harmonic_phase;
                hrm_flags_d <= ps_harmonic_flags;
            end

            hrm_start_pulse_ff <= ps_harmonic_valid && (ps_harmonic_index == 9'd0);
        end
    end

    // ------------------------------------------------------------------
    // 快照提交：toggle -> 单拍脉冲（关键，踩过）
    //   核心输出的是**每帧翻转一次的电平**（ps_snapshot_commit_toggle），
    //   而桥把 snapshot_commit 当**电平**用（STATE_IDLE 的 else-if 分支）。
    //   直接接一起 = commit 永久为高，桥永远在写快照，harmonic_ready 永远不真，
    //   谐波流永久得不到服务（实测卡在 STATE_SNAPSHOT_WRITE、act=0）。
    //   这里做边沿检测，只给桥一个单拍脉冲；对外仍暴露 toggle 供 PS 观察。
    // ------------------------------------------------------------------
    reg snap_toggle_d;
    reg snap_commit_pulse;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            snap_toggle_d     <= 1'b0;
            snap_commit_pulse <= 1'b0;
        end else begin
            snap_toggle_d     <= ps_snapshot_commit_toggle;
            snap_commit_pulse <= ps_snapshot_commit_toggle ^ snap_toggle_d;
        end
    end

    // ------------------------------------------------------------------
    // 共享内存 ABI 桥（PL 侧）
    // ------------------------------------------------------------------
    wire        snapshot_ready;
    wire        harmonic_start_ready;
    wire        command_valid;
    wire [31:0] command_code, command_argument, command_sequence;
    wire        command_response_ready;
    wire [31:0] command_response;
    wire [31:0] snapshot_sequence, harmonic_generation;
    wire        active_harmonic_bank;

    pqm_shared_memory_bridge u_shared_memory_bridge (
        .clk(clk), .rst_n(rst_n),
        .snapshot_commit(snap_commit_pulse),
        .snapshot_ready(snapshot_ready),
        .snapshot_words(ps_snapshot_words),
        .harmonic_frame_start(hrm_start_pulse_ff),
        .harmonic_start_ready(harmonic_start_ready),
        .harmonic_valid(hrm_valid_d),
        .harmonic_ready(harmonic_ready),
        .harmonic_index(hrm_index_d),
        .harmonic_u_ratio(hrm_u_d),
        .harmonic_i_ratio(hrm_i_d),
        .harmonic_phase(hrm_phase_d),
        .harmonic_flags(hrm_flags_d),
        .command_valid(command_valid),
        .command_code(command_code),
        .command_argument(command_argument),
        .command_sequence(command_sequence),
        .command_response_valid(command_response_valid),
        .command_response_ready(command_response_ready),
        .command_response(command_response),
        .snapshot_sequence(snapshot_sequence),
        .harmonic_generation(harmonic_generation),
        .active_harmonic_bank(active_harmonic_bank),
        .bram_addr(bram_addr),
        .bram_wrdata(bram_wrdata),
        .bram_we(bram_we),
        .bram_en(bram_en),
        .bram_rddata(bram_rddata)
    );

    // ------------------------------------------------------------------
    // 量程命令
    // ------------------------------------------------------------------
    pqm_range_command_controller u_range_command (
        .clk(clk), .rst_n(rst_n),
        .command_valid(command_valid),
        .command_code(command_code),
        .command_argument(command_argument),
        .response_valid(command_response_valid),
        .response_ready(command_response_ready),
        .response(command_response),
        .low_range_active(low_range_active)
    );

    // 频域链取样口 freq_sample_ready 由测量核心引出，只作系统级观察点（无 RTL 消费者）。

    // 未使用的监测信号，避免综合告警
    wire _unused = &{1'b0, ad_sample_active, ad_timeout, ad_channal,
                     snapshot_ready, harmonic_start_ready, command_sequence,
                     snapshot_sequence, harmonic_generation, active_harmonic_bank,
                     u_zero_valid, i_zero_valid, ad_frame};

endmodule
