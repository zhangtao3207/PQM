/*
 * 模块：pqm_pl_core
 * 功能：完成AD7606采集、零点跟踪、时域/频域测量和告警，并向PS发布原始样本、
 *       标量快照及谐波流；显示、触摸和页面交互全部由ARM负责。
 * 输入：
 *   sys_clk：板级50 MHz参考时钟，仅送入MMCM。
 *   sys_rst_n：板级低有效复位。
 *   ps_low_range_active：PS命令确认后的高低量程状态。
 *   Busy：AD7606转换忙状态。
 *   Frstdata：AD7606首通道数据标志。
 *   DB0：AD7606并行数据位0。
 *   DB1：AD7606并行数据位1。
 *   DB2：AD7606并行数据位2。
 *   DB3：AD7606并行数据位3。
 *   DB4：AD7606并行数据位4。
 *   DB5：AD7606并行数据位5。
 *   DB6：AD7606并行数据位6。
 *   DB7：AD7606并行数据位7。
 *   DB8：AD7606并行数据位8。
 *   DB9：AD7606并行数据位9。
 *   DB10：AD7606并行数据位10。
 *   DB11：AD7606并行数据位11。
 *   DB12：AD7606并行数据位12。
 *   DB13：AD7606并行数据位13。
 *   DB14：AD7606并行数据位14。
 *   DB15：AD7606并行数据位15。
 *   ps_harmonic_ready：共享内存桥允许接收下一项谐波。
 * 输出：
 *   led：告警闪烁指示。
 *   buzzer：告警蜂鸣器控制。
 *   OS1：AD7606过采样配置位1。
 *   OS0：AD7606过采样配置位0。
 *   OS2：AD7606过采样配置位2。
 *   Convst：AD7606转换启动。
 *   RD：AD7606读选通。
 *   RESET：AD7606硬件复位。
 *   cs：AD7606片选。
 *   Range：AD7606输入范围选择。
 *   ps_adc_u_sample：送往PS DMA的电压原始样本。
 *   ps_adc_i_sample：送往PS DMA的电流原始样本。
 *   ps_adc_frame_valid：八通道采样帧完成脉冲。
 *   ps_adc_timeout：AD7606采集超时标志。
 *   ps_pl_clk：MMCM输出的PL工作时钟。
 *   ps_pl_reset_n：MMCM锁定后的PL低有效复位。
 *   ps_snapshot_words：按共享内存ABI排列的16个标量字。
 *   ps_snapshot_commit_toggle：标量快照提交翻转信号。
 *   ps_harmonic_valid：谐波条目有效。
 *   ps_harmonic_last：谐波帧最后一项标志。
 *   ps_harmonic_index：当前谐波阶次。
 *   ps_harmonic_u_ratio：当前电压谐波占比。
 *   ps_harmonic_i_ratio：当前电流谐波占比。
 *   ps_harmonic_phase：当前电压电流相位差。
 *   ps_harmonic_flags：当前谐波存在及相位有效标志。
 */
module pqm_pl_core (
    input            sys_clk,
    input            sys_rst_n,
    input            ps_low_range_active,

    output           led,
    output           buzzer,
    output           OS1,
    output           OS0,
    output           OS2,
    output           Convst,
    output           RD,
    output           RESET,
    input            Busy,
    output           cs,
    output           Range,
    input            Frstdata,
    input            DB0,
    input            DB1,
    input            DB2,
    input            DB3,
    input            DB4,
    input            DB5,
    input            DB6,
    input            DB7,
    input            DB8,
    input            DB9,
    input            DB10,
    input            DB11,
    input            DB12,
    input            DB13,
    input            DB14,
    input            DB15,

    output  [15:0]   ps_adc_u_sample,
    output  [15:0]   ps_adc_i_sample,
    output           ps_adc_frame_valid,
    output           ps_adc_timeout,
    output           ps_pl_clk,
    output           ps_pl_reset_n,
    output [511:0]   ps_snapshot_words,
    output           ps_snapshot_commit_toggle,
    output           ps_harmonic_valid,
    input            ps_harmonic_ready,
    output           ps_harmonic_last,
    output   [8:0]   ps_harmonic_index,
    output  [31:0]   ps_harmonic_u_ratio,
    output  [31:0]   ps_harmonic_i_ratio,
    output  [31:0]   ps_harmonic_phase,
    output  [31:0]   ps_harmonic_flags
);

//==========================================================================
// Parameters
//==========================================================================


localparam integer ADC_STARTUP_WAIT_CYCLES = 50000;
localparam integer ALARM_BLINK_TOGGLE_CYCLES = 5000000;
wire         clk_50m;
wire         locked;
wire         rst_n;
wire [15:0]  AD_DATA_1;
wire [15:0]  AD_DATA_2;
wire [15:0]  AD_DATA_3;
wire [15:0]  AD_DATA_4;
wire [15:0]  AD_DATA_5;
wire [15:0]  AD_DATA_6;
wire [15:0]  AD_DATA_7;
wire [15:0]  AD_DATA_8;
wire [3:0]   AD_CHANNAL;
wire [2:0]   AD_STATE;
wire         adc_sample_active;
wire         adc_frame_valid;
wire         adc_timeout;
wire [15:0]  adc_data_bus;
wire         adc_startup_wait_done;
wire         ad_reset_int;
wire         ad_convst_int;
wire         ad_cs_n_int;
wire         ad_rd_n_int;
wire         adc_u_wave_sample_valid;
wire         adc_i_wave_sample_valid;
wire [15:0]  adc_u_zero_code;
wire [15:0]  adc_i_zero_code;
wire         adc_u_zero_valid;
wire         adc_i_zero_valid;
wire         display_alarm_active;
reg          adc_start;
reg          adc_idle_seen;
reg  [15:0]  adc_startup_wait_cnt;
reg  [15:0]  adc_u_wave_sample_code;
reg  [15:0]  adc_i_wave_sample_code;
reg  [22:0]  alarm_blink_cnt;
reg          led_blink_state;

assign rst_n                  = sys_rst_n & locked;
assign adc_startup_wait_done  = (adc_startup_wait_cnt >= ADC_STARTUP_WAIT_CYCLES - 1);
assign adc_data_bus           = {DB15, DB14, DB13, DB12, DB11, DB10, DB9, DB8,
                                 DB7, DB6, DB5, DB4, DB3, DB2, DB1, DB0};
assign adc_u_wave_sample_valid = adc_frame_valid;
assign adc_i_wave_sample_valid = adc_frame_valid;

assign OS0      = 1'b0;
assign OS1      = 1'b0;
assign OS2      = 1'b0;
assign RESET    = ad_reset_int;
assign Convst   = ad_convst_int;
assign Range    = 1'b1;
assign cs       = ad_cs_n_int;
assign RD       = ad_rd_n_int;
assign led      = display_alarm_active ? led_blink_state : 1'b0;
assign buzzer   = display_alarm_active;
// 向 SoC 顶层导出 AD7606 通道 1 原始样本。
assign ps_adc_u_sample = AD_DATA_1;

// 向 SoC 顶层导出 AD7606 通道 3 原始样本。
assign ps_adc_i_sample = AD_DATA_3;

// 向 SoC 顶层导出完整 ADC 帧有效脉冲。
assign ps_adc_frame_valid = adc_frame_valid;

// 向 SoC 顶层导出 ADC 采集超时标志。
assign ps_adc_timeout = adc_timeout;

// 向 SoC 顶层导出经过 MMCM 和 BUFG 的 50 MHz PL 工作时钟。
assign ps_pl_clk = clk_50m;

// MMCM 锁定且外部复位解除后，向 SoC 顶层释放 PL 工作复位。
assign ps_pl_reset_n = rst_n;

//==========================================================================
// ADC start generator
//==========================================================================
always @(posedge clk_50m or negedge rst_n) begin
    if (!rst_n) begin
        adc_start            <= 1'b0;
        adc_idle_seen        <= 1'b0;
        adc_startup_wait_cnt <= 16'd0;
        adc_u_wave_sample_code <= 16'h8000;
        adc_i_wave_sample_code <= 16'h8000;
    end else begin
        adc_start <= 1'b0;

        if (!adc_startup_wait_done) begin
            adc_startup_wait_cnt <= adc_startup_wait_cnt + 16'd1;
            adc_idle_seen        <= 1'b0;
        end else if (!adc_sample_active && !adc_idle_seen) begin
            adc_start     <= 1'b1;
            adc_idle_seen <= 1'b1;
        end else if (adc_sample_active) begin
            adc_idle_seen <= 1'b0;
        end

        if (adc_frame_valid) begin
            adc_u_wave_sample_code <= AD_DATA_1 ^ 16'h8000;
            adc_i_wave_sample_code <= AD_DATA_3 ^ 16'h8000;
        end
    end
end

always @(posedge clk_50m or negedge rst_n) begin
    if (!rst_n) begin
        alarm_blink_cnt <= 23'd0;
        led_blink_state <= 1'b1;
    end else if (!display_alarm_active) begin
        alarm_blink_cnt <= 23'd0;
        led_blink_state <= 1'b1;
    end else if (alarm_blink_cnt == (ALARM_BLINK_TOGGLE_CYCLES - 1)) begin
        alarm_blink_cnt <= 23'd0;
        led_blink_state <= ~led_blink_state;
    end else begin
        alarm_blink_cnt <= alarm_blink_cnt + 23'd1;
    end
end

//==========================================================================
// ADC instance: AD7606 parallel mode
//==========================================================================
AD7606_Parallel_DRIVER  u_AD7606_Parallel_DRIVER (
    .clk          (clk_50m),
    .rst_n        (rst_n),
    .start        (adc_start),
    .soft_reset   (1'b0),
    .ad_busy      (Busy),
    .ad_frstdata  (Frstdata),
    .ad_data      (adc_data_bus),
    .ad_reset     (ad_reset_int),
    .ad_convst    (ad_convst_int),
    .ad_cs_n      (ad_cs_n_int),
    .ad_rd_n      (ad_rd_n_int),
    .ch1_data     (AD_DATA_1),
    .ch2_data     (AD_DATA_2),
    .ch3_data     (AD_DATA_3),
    .ch4_data     (AD_DATA_4),
    .ch5_data     (AD_DATA_5),
    .ch6_data     (AD_DATA_6),
    .ch7_data     (AD_DATA_7),
    .ch8_data     (AD_DATA_8),
    .data_frame   (),
    .data_valid   (adc_frame_valid),
    .sample_active(adc_sample_active),
    .timeout      (adc_timeout),
    .ad_channal   (AD_CHANNAL),
    .ad_state     (AD_STATE)
);

//==========================================================================
// ADC zero-code tracker
//==========================================================================
time_zero_code_tracker #(
    .WIDTH          (16),
    .EST_SHIFT      (14),
    .WARMUP_SHIFT   (10),
    .WARMUP_SAMPLES (4096)
) u_adc_u_time_zero_code_tracker (
    .clk           (clk_50m),
    .rst_n         (rst_n),
    .sample_valid  (adc_u_wave_sample_valid),
    .sample_code   (adc_u_wave_sample_code),
    .zero_code     (adc_u_zero_code),
    .zero_valid    (adc_u_zero_valid)
);

time_zero_code_tracker #(
    .WIDTH          (16),
    .EST_SHIFT      (14),
    .WARMUP_SHIFT   (10),
    .WARMUP_SAMPLES (4096)
) u_adc_i_time_zero_code_tracker (
    .clk           (clk_50m),
    .rst_n         (rst_n),
    .sample_valid  (adc_i_wave_sample_valid),
    .sample_code   (adc_i_wave_sample_code),
    .zero_code     (adc_i_zero_code),
    .zero_valid    (adc_i_zero_valid)
);

// 纯PL测量核心持续接收采样，并向共享内存桥发布标量和谐波。
pqm_measurement_core u_pqm_measurement_core (
    .clk(clk_50m),
    .rst_n(rst_n),
    .full_scale_low_range_active(ps_low_range_active),
    .u_sample_valid(adc_u_wave_sample_valid),
    .u_sample_code(adc_u_wave_sample_code),
    .u_zero_code(adc_u_zero_code),
    .u_zero_valid(adc_u_zero_valid),
    .i_sample_valid(adc_i_wave_sample_valid),
    .i_sample_code(adc_i_wave_sample_code),
    .i_zero_code(adc_i_zero_code),
    .i_zero_valid(adc_i_zero_valid),
    .ps_harmonic_ready(ps_harmonic_ready),
    .alarm_active(display_alarm_active),
    .ps_snapshot_words(ps_snapshot_words),
    .ps_snapshot_commit_toggle(ps_snapshot_commit_toggle),
    .ps_harmonic_valid(ps_harmonic_valid),
    .ps_harmonic_last(ps_harmonic_last),
    .ps_harmonic_index(ps_harmonic_index),
    .ps_harmonic_u_ratio(ps_harmonic_u_ratio),
    .ps_harmonic_i_ratio(ps_harmonic_i_ratio),
    .ps_harmonic_phase(ps_harmonic_phase),
    .ps_harmonic_flags(ps_harmonic_flags)
);

// MMCM为ADC和测量链提供统一缓冲时钟。
clk_wiz_0 u_clk_wiz_0 (
    .clk_out1 (clk_50m),
    .clk_out2 (),
    .clk_out3 (),
    .locked   (locked),
    .clk_in1  (sys_clk)
);

endmodule
