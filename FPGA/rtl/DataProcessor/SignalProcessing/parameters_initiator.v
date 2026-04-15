`timescale 1ns / 1ps

/*
 * 模块: parameters_initiator
 * 功能:
 *   作为文字刷新链路的原始测量调度器，统一启动 RawDataCal 下的 raw 测量模块。
 *   先获取同一采样窗口的 p2p、相位和频率 raw，再由 p2p 推导 RMS raw，最后由 RMS 和相位推导功率 raw。
 *   所有 raw 结果和 valid 标志锁存完成后，再向 text_display_preprocess 返回 done。
 * 输入:
 *   clk: 原始测量调度工作时钟。
 *   rst_n: 低有效异步复位。
 *   start: 启动一次文字参数 raw 测量批次。
 *   u_sample_valid: 电压采样码当前周期是否有效。
 *   u_sample_code: 电压通道 ADC 采样码。
 *   u_zero_code: 电压通道过零参考码。
 *   u_zero_valid: 电压通道过零参考码是否有效。
 *   i_sample_valid: 电流采样码当前周期是否有效。
 *   i_sample_code: 电流通道 ADC 采样码。
 *   i_zero_code: 电流通道过零参考码。
 *   i_zero_valid: 电流通道过零参考码是否有效。
 * 输出:
 *   busy: 当前 raw 测量批次是否仍在进行。
 *   done: 本次 raw 测量批次结束的单周期脉冲。
 *   u_rms_raw: 电压 RMS 的 32 位补码 raw 结果。
 *   i_rms_raw: 电流 RMS 的 32 位补码 raw 结果。
 *   rms_valid: U/I RMS raw 结果是否有效。
 *   u_pp_raw: 电压峰峰值 32 位补码 raw 结果。
 *   u_pp_valid: 电压峰峰值 raw 结果是否有效。
 *   i_pp_raw: 电流峰峰值 32 位补码 raw 结果。
 *   i_pp_valid: 电流峰峰值 raw 结果是否有效。
 *   phase_offset_raw: 电流过零相对电压过零的偏移 raw 计数。
 *   phase_period_raw: 电压相邻过零周期 raw 计数。
 *   phase_valid: 相位 raw 结果是否有效。
 *   freq_period_raw: 电压过零周期 raw 计数。
 *   freq_valid: 频率 raw 结果是否有效。
 *   active_p_raw: 有功功率 32 位补码 raw 结果。
 *   reactive_q_raw: 无功功率 32 位补码 raw 结果。
 *   apparent_s_raw: 视在功率 32 位补码 raw 结果。
 *   power_factor_raw: 功率因数 32 位补码 raw 结果。
 *   power_metrics_valid: 功率相关 raw 结果是否有效。
 */
module parameters_initiator #(
    parameter integer SAMPLE_WIDTH          = 16,
    parameter integer MAX_FRAME_SAMPLES     = 8192,
    parameter integer N_WIDTH               = (MAX_FRAME_SAMPLES <= 2) ? 2 : $clog2(MAX_FRAME_SAMPLES),
    parameter integer MEASURE_FRAME_SAMPLES = 6144
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         start,
    input  wire                         u_sample_valid,
    input  wire [SAMPLE_WIDTH-1:0]      u_sample_code,
    input  wire [SAMPLE_WIDTH-1:0]      u_zero_code,
    input  wire                         u_zero_valid,
    input  wire                         i_sample_valid,
    input  wire [SAMPLE_WIDTH-1:0]      i_sample_code,
    input  wire [SAMPLE_WIDTH-1:0]      i_zero_code,
    input  wire                         i_zero_valid,
    output wire                         busy,
    output reg                          done,
    output reg  signed [31:0]           u_rms_raw,
    output reg  signed [31:0]           i_rms_raw,
    output reg                          rms_valid,
    output reg  signed [31:0]           u_pp_raw,
    output reg                          u_pp_valid,
    output reg  signed [31:0]           i_pp_raw,
    output reg                          i_pp_valid,
    output reg  signed [31:0]           phase_offset_raw,
    output reg  signed [31:0]           phase_period_raw,
    output reg                          phase_valid,
    output reg  signed [31:0]           freq_period_raw,
    output reg                          freq_valid,
    output reg  signed [31:0]           active_p_raw,
    output reg  signed [31:0]           reactive_q_raw,
    output reg  signed [31:0]           apparent_s_raw,
    output reg  signed [31:0]           power_factor_raw,
    output reg                          power_metrics_valid
);

localparam [2:0] ST_IDLE         = 3'd0;
localparam [2:0] ST_WAIT_PRIMARY = 3'd1;
localparam [2:0] ST_RMS_START    = 3'd2;
localparam [2:0] ST_RMS_WAIT     = 3'd3;
localparam [2:0] ST_POWER_START  = 3'd4;
localparam [2:0] ST_POWER_WAIT   = 3'd5;
localparam [2:0] ST_DONE         = 3'd6;

localparam [N_WIDTH-1:0] MEASURE_FRAME_SAMPLES_VALUE = MEASURE_FRAME_SAMPLES;

reg [2:0] state;
reg       u_p2p_start;
reg       i_p2p_start;
reg       phase_start;
reg       freq_start;
reg       rms_start;
reg       power_start;
reg       u_p2p_done_seen;
reg       i_p2p_done_seen;
reg       phase_done_seen;
reg       freq_done_seen;

wire                         ui_sample_valid;
wire                         u_p2p_done;
wire signed [31:0]           u_pp_raw_wire;
wire                         u_pp_valid_wire;
wire                         i_p2p_done;
wire signed [31:0]           i_pp_raw_wire;
wire                         i_pp_valid_wire;
wire                         phase_done;
wire signed [31:0]           phase_offset_raw_wire;
wire signed [31:0]           phase_period_raw_wire;
wire                         phase_valid_wire;
wire                         freq_done;
wire signed [31:0]           freq_period_raw_wire;
wire                         freq_valid_wire;
wire                         primary_raw_done;
wire                         rms_done;
wire                         rms_valid_wire;
wire signed [31:0]           u_rms_raw_wire;
wire signed [31:0]           i_rms_raw_wire;
wire                         power_done;
wire signed [31:0]           active_p_raw_wire;
wire signed [31:0]           reactive_q_raw_wire;
wire signed [31:0]           apparent_s_raw_wire;
wire signed [31:0]           power_factor_raw_wire;
wire                         power_metrics_valid_wire;

// 只在 U/I 两路采样同时有效时推进 raw 测量窗口，保证同一批文字参数使用同一组采样节拍。
assign ui_sample_valid = u_sample_valid && i_sample_valid;

// 状态机离开空闲态即表示 raw 测量批次正在运行。
assign busy = (state != ST_IDLE);

// p2p、相位和频率均结束后，才能进入 RMS 和功率 raw 的派生阶段。
assign primary_raw_done = (u_p2p_done_seen || u_p2p_done) &&
                          (i_p2p_done_seen || i_p2p_done) &&
                          (phase_done_seen || phase_done) &&
                          (freq_done_seen || freq_done);

// 电压峰峰值 raw 测量实例，输出电压 p2p 原始码差。
p2p_measure #(
    .WIDTH(SAMPLE_WIDTH),
    .MAX_FRAME_SAMPLES(MAX_FRAME_SAMPLES),
    .N_WIDTH(N_WIDTH)
) u_u_p2p_measure (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (u_p2p_start),
    .sample_count_n(MEASURE_FRAME_SAMPLES_VALUE),
    .sample_valid  (ui_sample_valid),
    .sample_code   (u_sample_code),
    .busy          (),
    .done          (u_p2p_done),
    .p2p_raw       (u_pp_raw_wire),
    .p2p_valid     (u_pp_valid_wire)
);

// 电流峰峰值 raw 测量实例，输出电流 p2p 原始码差。
p2p_measure #(
    .WIDTH(SAMPLE_WIDTH),
    .MAX_FRAME_SAMPLES(MAX_FRAME_SAMPLES),
    .N_WIDTH(N_WIDTH)
) u_i_p2p_measure (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (i_p2p_start),
    .sample_count_n(MEASURE_FRAME_SAMPLES_VALUE),
    .sample_valid  (ui_sample_valid),
    .sample_code   (i_sample_code),
    .busy          (),
    .done          (i_p2p_done),
    .p2p_raw       (i_pp_raw_wire),
    .p2p_valid     (i_pp_valid_wire)
);

// U/I 相位差 raw 测量实例，输出相位偏移计数和电压过零周期计数。
phase_diff_calc #(
    .WIDTH(SAMPLE_WIDTH),
    .MAX_FRAME_SAMPLES(MAX_FRAME_SAMPLES),
    .N_WIDTH(N_WIDTH)
) u_phase_diff_calc (
    .clk             (clk),
    .rst_n           (rst_n),
    .start           (phase_start),
    .sample_count_n  (MEASURE_FRAME_SAMPLES_VALUE),
    .sample_valid    (ui_sample_valid),
    .u_sample_code   (u_sample_code),
    .u_zero_code     (u_zero_code),
    .u_zero_valid    (u_zero_valid),
    .i_sample_code   (i_sample_code),
    .i_zero_code     (i_zero_code),
    .i_zero_valid    (i_zero_valid),
    .busy            (),
    .done            (phase_done),
    .phase_offset_raw(phase_offset_raw_wire),
    .phase_period_raw(phase_period_raw_wire),
    .phase_valid     (phase_valid_wire)
);

// 电压频率 raw 测量实例，输出电压过零周期计数。
frequency_measure #(
    .WIDTH(SAMPLE_WIDTH),
    .MAX_FRAME_SAMPLES(MAX_FRAME_SAMPLES),
    .N_WIDTH(N_WIDTH)
) u_frequency_measure (
    .clk            (clk),
    .rst_n          (rst_n),
    .start          (freq_start),
    .sample_count_n (MEASURE_FRAME_SAMPLES_VALUE),
    .sample_valid   (ui_sample_valid),
    .sample_code    (u_sample_code),
    .zero_code      (u_zero_code),
    .zero_valid     (u_zero_valid),
    .busy           (),
    .done           (freq_done),
    .freq_period_raw(freq_period_raw_wire),
    .freq_valid     (freq_valid_wire)
);

// 由同一批 p2p raw 推导 U/I RMS raw。
ui_rms_measure #(
    .DATA_WIDTH(SAMPLE_WIDTH)
) u_ui_rms_measure (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (rms_start),
    .u_pp_raw      (u_pp_raw),
    .i_pp_raw      (i_pp_raw),
    .u_pp_valid    (u_pp_valid),
    .i_pp_valid    (i_pp_valid),
    .busy          (),
    .done          (rms_done),
    .rms_valid     (rms_valid_wire),
    .config_error  (),
    .frame_overflow(),
    .u_rms_raw     (u_rms_raw_wire),
    .i_rms_raw     (i_rms_raw_wire)
);

// 由同一批 RMS raw 和相位 raw 推导功率相关 raw。
power_metrics_calc #(
    .WIDTH(SAMPLE_WIDTH)
) u_power_metrics_calc (
    .clk                (clk),
    .rst_n              (rst_n),
    .start              (power_start),
    .rms_valid          (rms_valid),
    .u_rms_code         (u_rms_raw[SAMPLE_WIDTH-1:0]),
    .i_rms_code         (i_rms_raw[SAMPLE_WIDTH-1:0]),
    .phase_offset_raw   (phase_offset_raw),
    .phase_period_raw   (phase_period_raw),
    .phase_valid        (phase_valid),
    .busy               (),
    .done               (power_done),
    .active_p_raw       (active_p_raw_wire),
    .reactive_q_raw     (reactive_q_raw_wire),
    .apparent_s_raw     (apparent_s_raw_wire),
    .power_factor_raw   (power_factor_raw_wire),
    .power_metrics_valid(power_metrics_valid_wire)
);

// 在 clk 域统一启动 raw 测量、记录 done 脉冲、锁存有效 raw 输出，并在批次结束后返回 done。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state               <= ST_IDLE;
        u_p2p_start         <= 1'b0;
        i_p2p_start         <= 1'b0;
        phase_start         <= 1'b0;
        freq_start          <= 1'b0;
        rms_start           <= 1'b0;
        power_start         <= 1'b0;
        u_p2p_done_seen     <= 1'b0;
        i_p2p_done_seen     <= 1'b0;
        phase_done_seen     <= 1'b0;
        freq_done_seen      <= 1'b0;
        done                <= 1'b0;
        u_rms_raw           <= 32'sd0;
        i_rms_raw           <= 32'sd0;
        rms_valid           <= 1'b0;
        u_pp_raw            <= 32'sd0;
        u_pp_valid          <= 1'b0;
        i_pp_raw            <= 32'sd0;
        i_pp_valid          <= 1'b0;
        phase_offset_raw    <= 32'sd0;
        phase_period_raw    <= 32'sd0;
        phase_valid         <= 1'b0;
        freq_period_raw     <= 32'sd0;
        freq_valid          <= 1'b0;
        active_p_raw        <= 32'sd0;
        reactive_q_raw      <= 32'sd0;
        apparent_s_raw      <= 32'sd0;
        power_factor_raw    <= 32'sd0;
        power_metrics_valid <= 1'b0;
    end else begin
        done        <= 1'b0;
        u_p2p_start <= 1'b0;
        i_p2p_start <= 1'b0;
        phase_start <= 1'b0;
        freq_start  <= 1'b0;
        rms_start   <= 1'b0;
        power_start <= 1'b0;

        if (u_p2p_done)
            u_p2p_done_seen <= 1'b1;
        if (i_p2p_done)
            i_p2p_done_seen <= 1'b1;
        if (phase_done)
            phase_done_seen <= 1'b1;
        if (freq_done)
            freq_done_seen <= 1'b1;

        if (u_pp_valid_wire) begin
            u_pp_raw   <= u_pp_raw_wire;
            u_pp_valid <= 1'b1;
        end

        if (i_pp_valid_wire) begin
            i_pp_raw   <= i_pp_raw_wire;
            i_pp_valid <= 1'b1;
        end

        if (phase_valid_wire) begin
            phase_offset_raw <= phase_offset_raw_wire;
            phase_period_raw <= phase_period_raw_wire;
            phase_valid      <= 1'b1;
        end

        if (freq_valid_wire) begin
            freq_period_raw <= freq_period_raw_wire;
            freq_valid      <= 1'b1;
        end

        if (rms_valid_wire) begin
            u_rms_raw <= u_rms_raw_wire;
            i_rms_raw <= i_rms_raw_wire;
            rms_valid <= 1'b1;
        end

        if (power_metrics_valid_wire) begin
            active_p_raw        <= active_p_raw_wire;
            reactive_q_raw      <= reactive_q_raw_wire;
            apparent_s_raw      <= apparent_s_raw_wire;
            power_factor_raw    <= power_factor_raw_wire;
            power_metrics_valid <= 1'b1;
        end

        case (state)
            ST_IDLE: begin
                if (start) begin
                    u_p2p_start         <= 1'b1;
                    i_p2p_start         <= 1'b1;
                    phase_start         <= 1'b1;
                    freq_start          <= 1'b1;
                    u_p2p_done_seen     <= 1'b0;
                    i_p2p_done_seen     <= 1'b0;
                    phase_done_seen     <= 1'b0;
                    freq_done_seen      <= 1'b0;
                    u_rms_raw           <= 32'sd0;
                    i_rms_raw           <= 32'sd0;
                    rms_valid           <= 1'b0;
                    u_pp_raw            <= 32'sd0;
                    u_pp_valid          <= 1'b0;
                    i_pp_raw            <= 32'sd0;
                    i_pp_valid          <= 1'b0;
                    phase_offset_raw    <= 32'sd0;
                    phase_period_raw    <= 32'sd0;
                    phase_valid         <= 1'b0;
                    freq_period_raw     <= 32'sd0;
                    freq_valid          <= 1'b0;
                    active_p_raw        <= 32'sd0;
                    reactive_q_raw      <= 32'sd0;
                    apparent_s_raw      <= 32'sd0;
                    power_factor_raw    <= 32'sd0;
                    power_metrics_valid <= 1'b0;
                    state               <= ST_WAIT_PRIMARY;
                end
            end

            ST_WAIT_PRIMARY: begin
                if (primary_raw_done)
                    state <= ST_RMS_START;
            end

            ST_RMS_START: begin
                if (u_pp_valid && i_pp_valid) begin
                    rms_start <= 1'b1;
                    state     <= ST_RMS_WAIT;
                end else begin
                    u_rms_raw <= 32'sd0;
                    i_rms_raw <= 32'sd0;
                    rms_valid <= 1'b0;
                    state     <= ST_DONE;
                end
            end

            ST_RMS_WAIT: begin
                if (rms_done)
                    state <= ST_POWER_START;
            end

            ST_POWER_START: begin
                if (rms_valid && phase_valid) begin
                    power_start <= 1'b1;
                    state       <= ST_POWER_WAIT;
                end else begin
                    active_p_raw        <= 32'sd0;
                    reactive_q_raw      <= 32'sd0;
                    apparent_s_raw      <= 32'sd0;
                    power_factor_raw    <= 32'sd0;
                    power_metrics_valid <= 1'b0;
                    state               <= ST_DONE;
                end
            end

            ST_POWER_WAIT: begin
                if (power_done)
                    state <= ST_DONE;
            end

            ST_DONE: begin
                done  <= 1'b1;
                state <= ST_IDLE;
            end

            default: begin
                state <= ST_IDLE;
            end
        endcase
    end
end

endmodule
