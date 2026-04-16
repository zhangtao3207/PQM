`timescale 1ns / 1ps

/*
 * 模块: fft_harmonic_result_buffer
 * 功能:
 *   缓存频域分析输出的 0~500 次谐波结果。写端接收 freq_analysis_top 的谐波结果流，
 *   读端按谐波次数读取最新完整帧。内部使用双缓冲，避免显示或上位机读取时被新帧覆盖。
 *
 * 输入:
 *   clk: 谐波结果缓存工作时钟，通常接 fft_clk 或系统读取时钟。
 *   rst_n: 低有效复位信号。
 *   enable: 缓存写入使能，拉低时停止接收新结果，但保留已完成帧供读取。
 *   s_result_valid: 上游谐波结果有效标志。
 *   s_result_last: 上游 0~500 次谐波结果的最后一项标志。
 *   s_harmonic_order: 上游谐波次数。
 *   s_harmonic_present: 当前谐波在本帧中是否被捕获。
 *   s_u_mag: 当前谐波电压通道幅值。
 *   s_i_mag: 当前谐波电流通道幅值。
 *   s_u_pct_x100: 当前谐波电压幅值占比，100.00% 表示为 10000。
 *   s_i_pct_x100: 当前谐波电流幅值占比，100.00% 表示为 10000。
 *   s_phase_diff_valid: 当前谐波 U-I 相位差是否有效。
 *   s_phase_diff_deg_x100: 当前谐波 U-I 相位差角度，3025 表示 30.25 度。
 *   rd_en: 读端请求锁存一个谐波次数的缓存结果。
 *   rd_harmonic_order: 读端请求的谐波次数。
 *
 * 输出:
 *   s_result_ready: 本模块对上游谐波结果流的接收就绪标志。
 *   frame_available: 已经缓存至少一帧完整谐波结果。
 *   frame_update_pulse: 最新完整帧提交到读缓冲区的单周期脉冲。
 *   frame_sequence: 已提交完整帧计数。
 *   write_frame_active: 当前正在接收一帧谐波结果。
 *   last_write_count: 上一提交帧实际写入的结果数量。
 *   rd_valid: 读端输出数据有效标志，rd_en 后一拍更新。
 *   rd_harmonic_present: 读出谐波在最新完整帧中是否有效。
 *   rd_u_mag: 读出的电压通道幅值。
 *   rd_i_mag: 读出的电流通道幅值。
 *   rd_u_pct_x100: 读出的电压幅值占比。
 *   rd_i_pct_x100: 读出的电流幅值占比。
 *   rd_phase_diff_valid: 读出的 U-I 相位差是否有效。
 *   rd_phase_diff_deg_x100: 读出的 U-I 相位差角度。
 */
module fft_harmonic_result_buffer (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               enable,
    input  wire               s_result_valid,
    output wire               s_result_ready,
    input  wire               s_result_last,
    input  wire [8:0]         s_harmonic_order,
    input  wire               s_harmonic_present,
    input  wire [16:0]        s_u_mag,
    input  wire [16:0]        s_i_mag,
    input  wire [15:0]        s_u_pct_x100,
    input  wire [15:0]        s_i_pct_x100,
    input  wire               s_phase_diff_valid,
    input  wire signed [15:0] s_phase_diff_deg_x100,
    input  wire               rd_en,
    input  wire [8:0]         rd_harmonic_order,
    output wire               frame_available,
    output wire               frame_update_pulse,
    output reg  [15:0]        frame_sequence,
    output wire               write_frame_active,
    output reg  [9:0]         last_write_count,
    output reg                rd_valid,
    output reg                rd_harmonic_present,
    output reg  [16:0]        rd_u_mag,
    output reg  [16:0]        rd_i_mag,
    output reg  [15:0]        rd_u_pct_x100,
    output reg  [15:0]        rd_i_pct_x100,
    output reg                rd_phase_diff_valid,
    output reg  signed [15:0] rd_phase_diff_deg_x100
);

localparam [8:0] LAST_HARMONIC_ORDER = 9'd500;

reg [16:0]        u_mag_bank0 [0:500];
reg [16:0]        u_mag_bank1 [0:500];
reg [16:0]        i_mag_bank0 [0:500];
reg [16:0]        i_mag_bank1 [0:500];
reg [15:0]        u_pct_bank0 [0:500];
reg [15:0]        u_pct_bank1 [0:500];
reg [15:0]        i_pct_bank0 [0:500];
reg [15:0]        i_pct_bank1 [0:500];
reg signed [15:0] phase_bank0 [0:500];
reg signed [15:0] phase_bank1 [0:500];
reg               present_bank0 [0:500];
reg               present_bank1 [0:500];
reg               phase_valid_bank0 [0:500];
reg               phase_valid_bank1 [0:500];

reg               write_bank;
reg               read_bank;
reg               frame_available_reg;
reg               frame_update_pulse_reg;
reg               write_frame_active_reg;
reg [9:0]         write_count;

wire              input_fire;
wire              write_order_in_range;
wire              read_order_in_range;
wire [16:0]       clean_u_mag;
wire [16:0]       clean_i_mag;
wire [15:0]       clean_u_pct_x100;
wire [15:0]       clean_i_pct_x100;
wire signed [15:0] clean_phase_diff_deg_x100;
wire              clean_phase_diff_valid;

// 组合生成写端握手和地址范围判断，缓存模块每拍最多接收一条谐波结果。
assign s_result_ready      = enable;
assign input_fire          = s_result_valid && s_result_ready;
assign write_order_in_range = (s_harmonic_order <= LAST_HARMONIC_ORDER);
assign read_order_in_range  = (rd_harmonic_order <= LAST_HARMONIC_ORDER);

// 组合清理无效谐波的数据，避免读端看到上一帧残留值。
assign clean_u_mag = s_harmonic_present ? s_u_mag : 17'd0;
assign clean_i_mag = s_harmonic_present ? s_i_mag : 17'd0;
assign clean_u_pct_x100 = s_harmonic_present ? s_u_pct_x100 : 16'd0;
assign clean_i_pct_x100 = s_harmonic_present ? s_i_pct_x100 : 16'd0;
assign clean_phase_diff_valid = s_harmonic_present && s_phase_diff_valid;
assign clean_phase_diff_deg_x100 =
    clean_phase_diff_valid ? s_phase_diff_deg_x100 : 16'sd0;

// 对外导出帧状态。
assign frame_available   = frame_available_reg;
assign frame_update_pulse = frame_update_pulse_reg;
assign write_frame_active = write_frame_active_reg;

// 在统一时钟域写入谐波结果流，并在帧尾提交双缓冲读写银行切换。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        write_bank             <= 1'b0;
        read_bank              <= 1'b0;
        frame_available_reg    <= 1'b0;
        frame_update_pulse_reg <= 1'b0;
        write_frame_active_reg <= 1'b0;
        write_count            <= 10'd0;
        last_write_count       <= 10'd0;
        frame_sequence         <= 16'd0;
        rd_valid               <= 1'b0;
        rd_harmonic_present    <= 1'b0;
        rd_u_mag               <= 17'd0;
        rd_i_mag               <= 17'd0;
        rd_u_pct_x100          <= 16'd0;
        rd_i_pct_x100          <= 16'd0;
        rd_phase_diff_valid    <= 1'b0;
        rd_phase_diff_deg_x100 <= 16'sd0;
    end else begin
        frame_update_pulse_reg <= 1'b0;

        if (input_fire) begin
            write_frame_active_reg <= 1'b1;

            if (write_order_in_range) begin
                if (!write_bank) begin
                    u_mag_bank0[s_harmonic_order]        <= clean_u_mag;
                    i_mag_bank0[s_harmonic_order]        <= clean_i_mag;
                    u_pct_bank0[s_harmonic_order]        <= clean_u_pct_x100;
                    i_pct_bank0[s_harmonic_order]        <= clean_i_pct_x100;
                    phase_bank0[s_harmonic_order]        <= clean_phase_diff_deg_x100;
                    present_bank0[s_harmonic_order]      <= s_harmonic_present;
                    phase_valid_bank0[s_harmonic_order]  <= clean_phase_diff_valid;
                end else begin
                    u_mag_bank1[s_harmonic_order]        <= clean_u_mag;
                    i_mag_bank1[s_harmonic_order]        <= clean_i_mag;
                    u_pct_bank1[s_harmonic_order]        <= clean_u_pct_x100;
                    i_pct_bank1[s_harmonic_order]        <= clean_i_pct_x100;
                    phase_bank1[s_harmonic_order]        <= clean_phase_diff_deg_x100;
                    present_bank1[s_harmonic_order]      <= s_harmonic_present;
                    phase_valid_bank1[s_harmonic_order]  <= clean_phase_diff_valid;
                end
            end

            if (write_count != 10'h3FF)
                write_count <= write_count + 10'd1;

            if (s_result_last) begin
                read_bank              <= write_bank;
                write_bank             <= !write_bank;
                frame_available_reg    <= 1'b1;
                frame_update_pulse_reg <= 1'b1;
                write_frame_active_reg <= 1'b0;
                last_write_count       <= write_count + 10'd1;
                write_count            <= 10'd0;
                frame_sequence         <= frame_sequence + 16'd1;
            end
        end

        if (rd_en) begin
            rd_valid <= frame_available_reg && read_order_in_range;

            if (frame_available_reg && read_order_in_range) begin
                if (!read_bank) begin
                    rd_harmonic_present    <= present_bank0[rd_harmonic_order];
                    rd_u_mag               <= u_mag_bank0[rd_harmonic_order];
                    rd_i_mag               <= i_mag_bank0[rd_harmonic_order];
                    rd_u_pct_x100          <= u_pct_bank0[rd_harmonic_order];
                    rd_i_pct_x100          <= i_pct_bank0[rd_harmonic_order];
                    rd_phase_diff_valid    <= phase_valid_bank0[rd_harmonic_order];
                    rd_phase_diff_deg_x100 <= phase_bank0[rd_harmonic_order];
                end else begin
                    rd_harmonic_present    <= present_bank1[rd_harmonic_order];
                    rd_u_mag               <= u_mag_bank1[rd_harmonic_order];
                    rd_i_mag               <= i_mag_bank1[rd_harmonic_order];
                    rd_u_pct_x100          <= u_pct_bank1[rd_harmonic_order];
                    rd_i_pct_x100          <= i_pct_bank1[rd_harmonic_order];
                    rd_phase_diff_valid    <= phase_valid_bank1[rd_harmonic_order];
                    rd_phase_diff_deg_x100 <= phase_bank1[rd_harmonic_order];
                end
            end else begin
                rd_harmonic_present    <= 1'b0;
                rd_u_mag               <= 17'd0;
                rd_i_mag               <= 17'd0;
                rd_u_pct_x100          <= 16'd0;
                rd_i_pct_x100          <= 16'd0;
                rd_phase_diff_valid    <= 1'b0;
                rd_phase_diff_deg_x100 <= 16'sd0;
            end
        end else begin
            rd_valid <= 1'b0;
        end
    end
end

endmodule
