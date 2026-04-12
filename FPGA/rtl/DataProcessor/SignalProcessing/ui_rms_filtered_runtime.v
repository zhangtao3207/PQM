`timescale 1ns / 1ps

/*
 * 模块: ui_rms_filtered_runtime
 * 功能:
 *   对输入的 U/I 两路 ADC 原始补码采样流执行“先 8 点窗口均值滤波，再计算 RMS”的双通道处理。
 *   模块内部包含原始帧采集、逐帧读出、U/I 两路均值滤波与 U/I 两路 RMS 计算，
 *   最终输出两个 16bit 补码 RMS 结果。
 *
 * 处理链路:
 *   1. adc_frame_capture_runtime: 采集 N 组 {U,I} 原始样本
 *   2. mean_filter_decim8_runtime x2: 分别对 U、I 执行 8 点均值滤波
 *   3. rms_signed_runtime x2: 分别对滤波后的 U、I 样本计算 RMS
 *
 * 使用约定:
 *   - frame_samples_n 为运行时指定的原始样本数 N
 *   - 为保证滤波后样本数严格等于 N/8，要求 N 为 8 的整数倍
 *   - sample_valid 每来一拍就向采集器写入一组 {U,I} 原始样本
 *   - rms_valid 在 U/I 两路 RMS 都就绪时拉高 1 拍
 *
 * 输入:
 *   clk: 模块工作时钟
 *   rst_n: 低有效复位
 *   frame_samples_n: 原始采样帧长度 N
 *   sample_valid: 原始样本有效标志
 *   u_sample_in: 电压通道原始补码样本
 *   i_sample_in: 电流通道原始补码样本
 *
 * 输出:
 *   busy: 模块正在处理或存在待处理帧
 *   rms_valid: U/I 两路 RMS 结果同时就绪脉冲
 *   config_error: 当 N 不是 8 的整数倍时拉高 1 拍，当前帧不参与滤波 RMS 计算
 *   frame_overflow: 当待处理队列已满又有新帧完成时拉高 1 拍
 *   u_rms_out: 电压通道滤波后的 RMS 补码值
 *   i_rms_out: 电流通道滤波后的 RMS 补码值
 */
module ui_rms_filtered_runtime #(
    parameter integer DATA_WIDTH        = 16,
    parameter integer MAX_FRAME_SAMPLES = 4096,
    parameter integer N_WIDTH           = (MAX_FRAME_SAMPLES <= 2) ? 2 : $clog2(MAX_FRAME_SAMPLES)
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire [N_WIDTH-1:0]           frame_samples_n,
    input  wire                         sample_valid,
    input  wire signed [DATA_WIDTH-1:0] u_sample_in,
    input  wire signed [DATA_WIDTH-1:0] i_sample_in,
    output reg                          busy,
    output reg                          rms_valid,
    output reg                          config_error,
    output reg                          frame_overflow,
    output reg  signed [DATA_WIDTH-1:0] u_rms_out,
    output reg  signed [DATA_WIDTH-1:0] i_rms_out
);

localparam integer CAPTURE_DATA_WIDTH = DATA_WIDTH * 2;
localparam [N_WIDTH-1:0] ZERO_COUNT   = {N_WIDTH{1'b0}};

// 原始帧采集器输出：双缓冲存储完成后的 bank 编号、样本数与同步读口数据
wire                     cap_frame_ready;
wire                     cap_ready_bank;
wire [N_WIDTH-1:0]       cap_ready_sample_count;
wire [CAPTURE_DATA_WIDTH-1:0] cap_rd_data;

// 采集器读口控制：按地址顺序从某一帧中依次读出 {U,I} 原始样本
reg                      cap_rd_en;
reg                      cap_rd_bank;
reg  [N_WIDTH-1:0]       cap_rd_addr;
reg                      cap_rd_valid_d1;

// 单帧待处理队列：缓存一帧已采满但尚未开始计算的 bank 信息
reg                      pending_valid;
reg                      pending_bank;
reg  [N_WIDTH-1:0]       pending_count;

// 当前正在处理的帧信息与读帧进度
reg                      proc_active;
reg                      proc_start_pending;
reg                      read_active;
reg                      proc_bank;
reg  [N_WIDTH-1:0]       proc_count;
reg  [N_WIDTH-1:0]       proc_filtered_count;
reg  [N_WIDTH-1:0]       read_req_count;
reg                      start_processing_pulse;

// U/I 两路均值滤波结果
wire                     u_mean_busy;
wire                     u_mean_out_valid;
wire signed [DATA_WIDTH-1:0] u_mean_out;
wire                     i_mean_busy;
wire                     i_mean_out_valid;
wire signed [DATA_WIDTH-1:0] i_mean_out;

// U/I 两路 RMS 结果
wire                     u_rms_core_busy;
wire                     u_rms_core_valid;
wire signed [DATA_WIDTH-1:0] u_rms_core_out;
wire                     i_rms_core_busy;
wire                     i_rms_core_valid;
wire signed [DATA_WIDTH-1:0] i_rms_core_out;

reg                      u_rms_done_latched;
reg                      i_rms_done_latched;
reg  signed [DATA_WIDTH-1:0] u_rms_latched;
reg  signed [DATA_WIDTH-1:0] i_rms_latched;

adc_frame_capture_runtime #(
    .DATA_WIDTH       (CAPTURE_DATA_WIDTH),
    .MAX_FRAME_SAMPLES(MAX_FRAME_SAMPLES),
    .ADDR_WIDTH       (N_WIDTH)
) u_adc_frame_capture_runtime (
    .clk               (clk),
    .rst_n             (rst_n),
    .frame_samples_n   (frame_samples_n),
    .sample_valid      (sample_valid),
    .sample_data       ({u_sample_in, i_sample_in}),
    .rd_en             (cap_rd_en),
    .rd_bank           (cap_rd_bank),
    .rd_addr           (cap_rd_addr),
    .frame_ready       (cap_frame_ready),
    .ready_bank        (cap_ready_bank),
    .ready_sample_count(cap_ready_sample_count),
    .wr_bank_active    (),
    .wr_addr_active    (),
    .rd_data           (cap_rd_data)
);

mean_filter_decim8_runtime #(
    .DATA_WIDTH(DATA_WIDTH),
    .N_WIDTH   (N_WIDTH)
) u_u_mean_filter (
    .clk             (clk),
    .rst_n           (rst_n),
    .frame_start     (start_processing_pulse),
    .sample_count_n  (proc_count),
    .sample_valid    (cap_rd_valid_d1),
    .sample_in       (cap_rd_data[CAPTURE_DATA_WIDTH-1:DATA_WIDTH]),
    .busy            (u_mean_busy),
    .sample_out_valid(u_mean_out_valid),
    .sample_out      (u_mean_out),
    .frame_done      ()
);

mean_filter_decim8_runtime #(
    .DATA_WIDTH(DATA_WIDTH),
    .N_WIDTH   (N_WIDTH)
) u_i_mean_filter (
    .clk             (clk),
    .rst_n           (rst_n),
    .frame_start     (start_processing_pulse),
    .sample_count_n  (proc_count),
    .sample_valid    (cap_rd_valid_d1),
    .sample_in       (cap_rd_data[DATA_WIDTH-1:0]),
    .busy            (i_mean_busy),
    .sample_out_valid(i_mean_out_valid),
    .sample_out      (i_mean_out),
    .frame_done      ()
);

rms_signed_runtime #(
    .DATA_WIDTH(DATA_WIDTH),
    .N_WIDTH   (N_WIDTH)
) u_u_rms_core (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (start_processing_pulse),
    .sample_count_n(proc_filtered_count),
    .sample_valid  (u_mean_out_valid),
    .sample_in     (u_mean_out),
    .busy          (u_rms_core_busy),
    .rms_valid     (u_rms_core_valid),
    .rms_out       (u_rms_core_out)
);

rms_signed_runtime #(
    .DATA_WIDTH(DATA_WIDTH),
    .N_WIDTH   (N_WIDTH)
) u_i_rms_core (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (start_processing_pulse),
    .sample_count_n(proc_filtered_count),
    .sample_valid  (i_mean_out_valid),
    .sample_in     (i_mean_out),
    .busy          (i_rms_core_busy),
    .rms_valid     (i_rms_core_valid),
    .rms_out       (i_rms_core_out)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        busy                  <= 1'b0;
        rms_valid             <= 1'b0;
        config_error          <= 1'b0;
        frame_overflow        <= 1'b0;
        u_rms_out             <= {DATA_WIDTH{1'b0}};
        i_rms_out             <= {DATA_WIDTH{1'b0}};
        cap_rd_en             <= 1'b0;
        cap_rd_bank           <= 1'b0;
        cap_rd_addr           <= ZERO_COUNT;
        cap_rd_valid_d1       <= 1'b0;
        pending_valid         <= 1'b0;
        pending_bank          <= 1'b0;
        pending_count         <= ZERO_COUNT;
        proc_active           <= 1'b0;
        proc_start_pending    <= 1'b0;
        read_active           <= 1'b0;
        proc_bank             <= 1'b0;
        proc_count            <= ZERO_COUNT;
        proc_filtered_count   <= ZERO_COUNT;
        read_req_count        <= ZERO_COUNT;
        start_processing_pulse<= 1'b0;
        u_rms_done_latched    <= 1'b0;
        i_rms_done_latched    <= 1'b0;
        u_rms_latched         <= {DATA_WIDTH{1'b0}};
        i_rms_latched         <= {DATA_WIDTH{1'b0}};
    end else begin
        rms_valid              <= 1'b0;
        config_error           <= 1'b0;
        frame_overflow         <= 1'b0;
        start_processing_pulse <= 1'b0;

        // 读口有效延迟 1 拍，对齐采集器同步读出的 rd_data
        cap_rd_valid_d1 <= cap_rd_en;

        // 默认读口关闭，只有处于读帧阶段才打开
        cap_rd_en <= 1'b0;

        // 锁存采集完成的一帧；若待处理队列已满则标记溢出
        if (cap_frame_ready) begin
            if (!pending_valid) begin
                pending_valid <= 1'b1;
                pending_bank  <= cap_ready_bank;
                pending_count <= cap_ready_sample_count;
            end else begin
                frame_overflow <= 1'b1;
            end
        end

        // 当前没有正在处理的帧时，从待处理队列取一帧开始计算
        if (!proc_active && pending_valid) begin
            pending_valid <= 1'b0;

            if (pending_count[2:0] != 3'b000) begin
                // 滤波版要求 N 为 8 的整数倍，否则当前帧不参与计算
                config_error <= 1'b1;
            end else begin
                proc_active            <= 1'b1;
                proc_start_pending     <= 1'b1;
                proc_bank              <= pending_bank;
                proc_count             <= pending_count;
                proc_filtered_count    <= pending_count >> 3;
                read_req_count         <= ZERO_COUNT;
                cap_rd_bank            <= pending_bank;
                cap_rd_addr            <= ZERO_COUNT;
                u_rms_done_latched     <= 1'b0;
                i_rms_done_latched     <= 1'b0;
            end
        end

        // 在参数锁存完成后的下一拍启动均值滤波与 RMS 计算，并打开读帧通路
        if (proc_start_pending) begin
            proc_start_pending     <= 1'b0;
            read_active            <= 1'b1;
            start_processing_pulse <= 1'b1;
            read_req_count         <= ZERO_COUNT;
            cap_rd_bank            <= proc_bank;
            cap_rd_addr            <= ZERO_COUNT;
        end

        // 逐拍从采集缓冲中顺序读出一整帧原始样本，送入 U/I 两路均值滤波器
        if (read_active) begin
            cap_rd_en   <= 1'b1;
            cap_rd_bank <= proc_bank;
            cap_rd_addr <= read_req_count;

            if (read_req_count == (proc_count - 1'b1)) begin
                read_active     <= 1'b0;
                read_req_count  <= ZERO_COUNT;
            end else begin
                read_req_count  <= read_req_count + {{(N_WIDTH - 1){1'b0}}, 1'b1};
            end
        end

        // 分别锁存 U/I 两路 RMS 结果，等待两路都完成后统一对外提交
        if (u_rms_core_valid) begin
            u_rms_done_latched <= 1'b1;
            u_rms_latched      <= u_rms_core_out;
        end

        if (i_rms_core_valid) begin
            i_rms_done_latched <= 1'b1;
            i_rms_latched      <= i_rms_core_out;
        end

        if ((u_rms_done_latched || u_rms_core_valid) &&
            (i_rms_done_latched || i_rms_core_valid) &&
            proc_active) begin
            u_rms_out   <= u_rms_core_valid ? u_rms_core_out : u_rms_latched;
            i_rms_out   <= i_rms_core_valid ? i_rms_core_out : i_rms_latched;
            rms_valid   <= 1'b1;
            proc_active <= 1'b0;
        end

        busy <= pending_valid || proc_active || read_active ||
                proc_start_pending ||
                u_mean_busy || i_mean_busy || u_rms_core_busy || i_rms_core_busy;
    end
end

endmodule
