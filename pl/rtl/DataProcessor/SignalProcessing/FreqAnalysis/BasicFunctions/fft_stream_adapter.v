`timescale 1ns / 1ps

/*
 * 模块: fft_stream_adapter
 * 功能:
 *   FFT 数据流适配模块。该模块完成 U/I 采样去直流、写入双通道 FIFO、按 2048 点帧读取，
 *   并驱动 xfft_0 双通道 AXI-Stream FFT IP。后续谐波幅值、THD 和 LCD 显示模块可连接
 *   本模块导出的原始 FFT 结果流。
 *
 * 输入:
 *   sample_clk: 采样写入时钟，通常接 ADC 采样所在时钟域。
 *   fft_clk: FFT IP 工作时钟，也是 FIFO 读出时钟。
 *   rst_n: 低有效复位信号。
 *   fft_enable: FFT 帧启动使能，已开始的帧会继续送完。
 *   sample_valid: U/I 采样对当前周期有效。
 *   sample_frame_marker: 可选采样帧标记，传递给 FIFO 调试计数。
 *   u_sample_code: 电压通道原始偏置码。
 *   u_zero_code: 电压通道直流零点估计值。
 *   u_zero_valid: 电压通道零点估计有效标志。
 *   i_sample_code: 电流通道原始偏置码。
 *   i_zero_code: 电流通道直流零点估计值。
 *   i_zero_valid: 电流通道零点估计有效标志。
 *   fft_output_ready: 下游 FFT 结果接收就绪信号。
 *
 * 输出:
 *   sample_accepted: 当前采样对已写入 FIFO。
 *   sample_dropped: FIFO 满导致当前采样对被丢弃。
 *   fifo_full: FFT 输入 FIFO 满标志。
 *   fifo_prog_full: FFT 输入 FIFO 接近满标志。
 *   fifo_empty: FFT 输入 FIFO 空标志。
 *   fifo_prog_empty: FFT 输入 FIFO 接近空标志。
 *   fifo_overflow_warn: FFT 输入 FIFO 接近溢出告警。
 *   fifo_overflow: FFT 输入 FIFO 溢出标志。
 *   fifo_underflow_warn: FFT 输入 FIFO 接近欠载告警。
 *   fifo_underflow: FFT 输入 FIFO 欠载标志。
 *   fifo_fft_frame_ready: FIFO 中至少有一整帧 FFT 样本可读。
 *   fifo_wr_data_count: 写端视角 FIFO 数据量。
 *   fifo_rd_data_count: 读端视角 FIFO 数据量。
 *   fifo_wr_marker_count: FIFO 写端采样帧标记计数。
 *   fifo_rd_marker_count: FIFO 兼容调试计数，当前为已读 FFT 帧计数低 8 位。
 *   fifo_wr_fft_frame_count: FIFO 写端已写满的 FFT 帧计数。
 *   fifo_rd_fft_frame_count: FIFO 读端已读出的 FFT 帧计数。
 *   fft_config_done: xfft_0 配置通道已完成一次握手。
 *   fft_input_busy: FFT 输入侧正在读取或发送一帧。
 *   fft_input_tvalid: 送入 xfft_0 的数据有效标志。
 *   fft_input_tready: xfft_0 输入数据接收就绪标志。
 *   fft_input_tlast: 送入 xfft_0 的帧尾标志。
 *   fft_output_valid: xfft_0 输出数据有效标志。
 *   fft_output_last: xfft_0 输出帧尾标志。
 *   fft_bin_index: xfft_0 输出频点索引。
 *   u_fft_real: 电压通道 FFT 输出实部。
 *   u_fft_imag: 电压通道 FFT 输出虚部。
 *   i_fft_real: 电流通道 FFT 输出实部。
 *   i_fft_imag: 电流通道 FFT 输出虚部。
 *   fft_output_tdata: xfft_0 原始输出 TDATA。
 *   fft_output_tuser: xfft_0 原始输出 TUSER。
 *   fft_status_tdata: xfft_0 状态通道数据。
 *   fft_status_valid: xfft_0 状态通道有效标志。
 *   event_frame_started: xfft_0 帧启动事件。
 *   event_tlast_unexpected: xfft_0 输入 TLAST 过早事件。
 *   event_tlast_missing: xfft_0 输入 TLAST 缺失事件。
 *   event_fft_overflow: xfft_0 固定点运算溢出事件。
 *   event_status_channel_halt: xfft_0 状态通道阻塞事件。
 *   event_data_in_channel_halt: xfft_0 输入通道阻塞事件。
 *   event_data_out_channel_halt: xfft_0 输出通道阻塞事件。
 */
module fft_stream_adapter #(
    parameter integer FIFO_ADDR_WIDTH = 13
)(
    input  wire               sample_clk,
    input  wire               fft_clk,
    input  wire               rst_n,
    input  wire               fft_enable,
    input  wire               sample_valid,
    input  wire               sample_frame_marker,
    input  wire [15:0]        u_sample_code,
    input  wire [15:0]        u_zero_code,
    input  wire               u_zero_valid,
    input  wire [15:0]        i_sample_code,
    input  wire [15:0]        i_zero_code,
    input  wire               i_zero_valid,
    input  wire               fft_output_ready,
    output wire               sample_accepted,
    output wire               sample_dropped,
    output wire               fifo_full,
    output wire               fifo_prog_full,
    output wire               fifo_empty,
    output wire               fifo_prog_empty,
    output wire               fifo_overflow_warn,
    output wire               fifo_overflow,
    output wire               fifo_underflow_warn,
    output wire               fifo_underflow,
    output wire               fifo_fft_frame_ready,
    output wire [FIFO_ADDR_WIDTH:0] fifo_wr_data_count,
    output wire [FIFO_ADDR_WIDTH:0] fifo_rd_data_count,
    output wire [7:0]         fifo_wr_marker_count,
    output wire [7:0]         fifo_rd_marker_count,
    output wire [15:0]        fifo_wr_fft_frame_count,
    output wire [15:0]        fifo_rd_fft_frame_count,
    output wire               fft_config_done,
    output wire               fft_input_busy,
    output wire               fft_input_tvalid,
    output wire               fft_input_tready,
    output wire               fft_input_tlast,
    output wire               fft_output_valid,
    output wire               fft_output_last,
    output wire [10:0]        fft_bin_index,
    output wire signed [15:0] u_fft_real,
    output wire signed [15:0] u_fft_imag,
    output wire signed [15:0] i_fft_real,
    output wire signed [15:0] i_fft_imag,
    output wire [63:0]        fft_output_tdata,
    output wire [23:0]        fft_output_tuser,
    output wire [7:0]         fft_status_tdata,
    output wire               fft_status_valid,
    output wire               event_frame_started,
    output wire               event_tlast_unexpected,
    output wire               event_tlast_missing,
    output wire               event_fft_overflow,
    output wire               event_status_channel_halt,
    output wire               event_data_in_channel_halt,
    output wire               event_data_out_channel_halt
);

localparam [11:0] FFT_FRAME_LAST_INDEX = 12'd2047;
localparam [21:0] FFT_SCALE_SCHEDULE   = 22'h155555;
localparam [47:0] FFT_CONFIG_TDATA     = {2'b00, FFT_SCALE_SCHEDULE, FFT_SCALE_SCHEDULE, 2'b11};
localparam [15:0] CENTER_DEFAULT       = 16'h8000;

wire signed [16:0] u_centered_ext;
wire signed [16:0] i_centered_ext;
wire [15:0]        u_centered_sample;
wire [15:0]        i_centered_sample;
wire               fifo_wr_en;
wire [15:0]        u_zero_ref_code;
wire [15:0]        i_zero_ref_code;
wire [31:0]        fifo_din;
wire               fifo_rd_en;
wire [31:0]        fifo_dout;
wire               fifo_dout_valid;

reg                fft_config_valid_reg;
reg                fft_config_done_reg;
wire               fft_config_ready;
wire               fft_axis_fire;
wire [63:0]        fft_input_tdata;

reg                frame_active;
reg                fifo_read_pending;
reg                fifo_read_last_pending;
reg [11:0]         frame_read_index;
reg                fft_axis_valid_reg;
reg                fft_axis_last_reg;
reg [31:0]         fft_axis_sample_pair;

wire               stream_idle;
wire               start_frame;
wire               read_window_active;
wire [11:0]        issue_read_index;
wire               issue_read_last;

// FFT 输入链路按动态零点去直流，只保留交流分量进入频谱分析。
assign u_zero_ref_code   = u_zero_valid ? u_zero_code : CENTER_DEFAULT;
assign i_zero_ref_code   = i_zero_valid ? i_zero_code : CENTER_DEFAULT;
assign u_centered_ext    = $signed({1'b0, u_sample_code}) - $signed({1'b0, u_zero_ref_code});
assign i_centered_ext    = $signed({1'b0, i_sample_code}) - $signed({1'b0, i_zero_ref_code});
assign u_centered_sample = u_centered_ext[15:0];
assign i_centered_sample = i_centered_ext[15:0];

// FFT 写 FIFO 只依赖联合采样有效，保证去直流后的交流采样连续入帧。
assign fifo_wr_en      = sample_valid && !fifo_full;
assign fifo_din        = {u_centered_sample, i_centered_sample};
assign sample_accepted = fifo_wr_en;
assign sample_dropped  = sample_valid && fifo_full;

// FFT 输入读控制：一帧启动后连续从 FIFO 取 2048 个采样对。
assign stream_idle        = !frame_active && !fft_axis_valid_reg && !fifo_read_pending;
assign start_frame        = stream_idle && fft_enable && fft_config_done_reg && fifo_fft_frame_ready;
assign read_window_active = frame_active || start_frame;
assign issue_read_index   = start_frame ? 12'd0 : frame_read_index;
assign issue_read_last    = (issue_read_index == FFT_FRAME_LAST_INDEX);
assign fifo_rd_en         = read_window_active && !fifo_empty && !fft_axis_valid_reg && !fifo_read_pending;

// AXI-Stream 输入握手和 xfft_0 输出解析。
assign fft_axis_fire    = fft_axis_valid_reg && fft_input_tready;
assign fft_input_tvalid = fft_axis_valid_reg;
assign fft_input_tlast  = fft_axis_last_reg;
assign fft_input_busy   = frame_active || fft_axis_valid_reg || fifo_read_pending;
assign fft_config_done  = fft_config_done_reg;

// xfft_0 的 TDATA 从低位起依次为 channel0 real、channel0 imag、channel1 real、channel1 imag。
assign fft_input_tdata  = {16'd0, fft_axis_sample_pair[15:0], 16'd0, fft_axis_sample_pair[31:16]};
assign fft_bin_index    = fft_output_tuser[10:0];
assign u_fft_real       = fft_output_tdata[15:0];
assign u_fft_imag       = fft_output_tdata[31:16];
assign i_fft_real       = fft_output_tdata[47:32];
assign i_fft_imag       = fft_output_tdata[63:48];

// 实例化 FFT 输入 FIFO，隔离采样写入节拍和 xfft_0 输入握手。
data_fifo #(
    .DATA_WIDTH       (32),
    .ADDR_WIDTH       (FIFO_ADDR_WIDTH),
    .FFT_FRAME_SIZE   (2048)
) u_data_fifo (
    .rst_n             (rst_n),
    .wr_clk            (sample_clk),
    .wr_en             (fifo_wr_en),
    .din               (fifo_din),
    .frstdata          (sample_frame_marker),
    .full              (fifo_full),
    .prog_full         (fifo_prog_full),
    .overflow_warn     (fifo_overflow_warn),
    .overflow          (fifo_overflow),
    .wr_data_count     (fifo_wr_data_count),
    .wr_8ch_frame_count(fifo_wr_marker_count),
    .wr_fft_frame_count(fifo_wr_fft_frame_count),
    .rd_clk            (fft_clk),
    .rd_en             (fifo_rd_en),
    .dout              (fifo_dout),
    .dout_valid        (fifo_dout_valid),
    .empty             (fifo_empty),
    .prog_empty        (fifo_prog_empty),
    .underflow_warn    (fifo_underflow_warn),
    .underflow         (fifo_underflow),
    .rd_data_count     (fifo_rd_data_count),
    .rd_8ch_frame_count(fifo_rd_marker_count),
    .rd_fft_frame_count(fifo_rd_fft_frame_count),
    .fft_frame_ready   (fifo_fft_frame_ready)
);

// FFT 配置通道：复位释放后发送一次正向 FFT 配置，两路通道使用相同缩放调度。
always @(posedge fft_clk or negedge rst_n) begin
    if (!rst_n) begin
        fft_config_valid_reg <= 1'b0;
        fft_config_done_reg  <= 1'b0;
    end else begin
        if (!fft_config_done_reg && !fft_config_valid_reg)
            fft_config_valid_reg <= 1'b1;
        else if (fft_config_valid_reg && fft_config_ready) begin
            fft_config_valid_reg <= 1'b0;
            fft_config_done_reg  <= 1'b1;
        end
    end
end

// FFT 输入状态机：从 FIFO 取数后用单级保持寄存器适配 xfft_0 的 tready 反压。
always @(posedge fft_clk or negedge rst_n) begin
    if (!rst_n) begin
        frame_active           <= 1'b0;
        fifo_read_pending      <= 1'b0;
        fifo_read_last_pending <= 1'b0;
        frame_read_index       <= 12'd0;
        fft_axis_valid_reg     <= 1'b0;
        fft_axis_last_reg      <= 1'b0;
        fft_axis_sample_pair   <= 32'd0;
    end else begin
        if (fft_axis_fire)
            fft_axis_valid_reg <= 1'b0;

        if (fifo_rd_en) begin
            fifo_read_pending      <= 1'b1;
            fifo_read_last_pending <= issue_read_last;

            if (issue_read_last) begin
                frame_active     <= 1'b0;
                frame_read_index <= 12'd0;
            end else begin
                frame_active     <= 1'b1;
                frame_read_index <= issue_read_index + 12'd1;
            end
        end

        if (fifo_dout_valid) begin
            fifo_read_pending    <= 1'b0;
            fft_axis_sample_pair <= fifo_dout;
            fft_axis_last_reg    <= fifo_read_last_pending;
            fft_axis_valid_reg   <= 1'b1;
        end
    end
end

// 实例化 Xilinx xfft_0，当前作为双通道 2048 点固定点 FFT 计算核心。
xfft_0 u_xfft_0 (
    .aclk                       (fft_clk),
    .aresetn                    (rst_n),
    .s_axis_config_tdata        (FFT_CONFIG_TDATA),
    .s_axis_config_tvalid       (fft_config_valid_reg),
    .s_axis_config_tready       (fft_config_ready),
    .s_axis_data_tdata          (fft_input_tdata),
    .s_axis_data_tvalid         (fft_input_tvalid),
    .s_axis_data_tready         (fft_input_tready),
    .s_axis_data_tlast          (fft_input_tlast),
    .m_axis_data_tdata          (fft_output_tdata),
    .m_axis_data_tuser          (fft_output_tuser),
    .m_axis_data_tvalid         (fft_output_valid),
    .m_axis_data_tready         (fft_output_ready),
    .m_axis_data_tlast          (fft_output_last),
    .m_axis_status_tdata        (fft_status_tdata),
    .m_axis_status_tvalid       (fft_status_valid),
    .m_axis_status_tready       (1'b1),
    .event_frame_started        (event_frame_started),
    .event_tlast_unexpected     (event_tlast_unexpected),
    .event_tlast_missing        (event_tlast_missing),
    .event_fft_overflow         (event_fft_overflow),
    .event_status_channel_halt  (event_status_channel_halt),
    .event_data_in_channel_halt (event_data_in_channel_halt),
    .event_data_out_channel_halt(event_data_out_channel_halt)
);

endmodule
