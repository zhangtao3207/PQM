`timescale 1ns / 1ps

/*
 * 模块: wave_display_capture
 * 功能:
 *   单通道波形显示预处理顶层，只负责波形抓帧与触发联动。
 *   输出内容仅包含:
 *   1. 波形显示 RAM 写口
 *   2. 显示帧有效标志与显示 bank
 *   3. 触发脉冲与触发快照位置
 *
 * 说明:
 *   - 文字显示相关预处理已统一移出到 text_display_preprocess
 *   - 波形触发、重采样、历史缓存和整帧写出均由独立子模块承担
 *   - display_freeze 只冻结显示帧提交，内部采样、重采样和历史缓存继续运行
 */
module wave_display_capture #(
    parameter integer SAMPLE_WIDTH    = 16,
    parameter integer FULL_SCALE_CODE = (1 << (SAMPLE_WIDTH - 1)) - 1
)(
    input                          wave_clk,
    input                          sys_rst_n,
    input                          wave_sample_valid,
    input      [SAMPLE_WIDTH-1:0]  wave_sample_code,
    input      [SAMPLE_WIDTH-1:0]  wave_zero_code,
    input                          wave_zero_valid,
    input                          trigger_force,
    input      [8:0]               trigger_force_snapshot_ptr,
    input                          trigger_use_external,
    input                          display_freeze,

    output reg                     wave_frame_valid,
    output reg                     wave_display_bank,
    output wire                    wave_ram_we,
    output wire [9:0]              wave_ram_waddr,
    output wire [7:0]              wave_ram_wdata,
    output reg                     trigger_pulse,
    output reg [8:0]               trigger_snapshot_ptr
);

localparam integer WAVE_POINT_COUNT      = 354;
localparam integer WAVE_FRAME_TICKS      = 3_000_000;
localparam integer GRAPH_H               = 240;
localparam integer GRAPH_HALF_H          = 120;
localparam integer WAVE_DIV_WIDTH        = 32;
localparam integer CENTER_IIR_SHIFT      = 22;
localparam integer WAVE_TRIGGER_HYST_INT = (SAMPLE_WIDTH >= 8) ? (2 << (SAMPLE_WIDTH - 8)) : 2;
localparam [SAMPLE_WIDTH-1:0] WAVE_TRIGGER_HYST = WAVE_TRIGGER_HYST_INT;
localparam [SAMPLE_WIDTH-1:0] CENTER_DEFAULT    = {1'b1, {(SAMPLE_WIDTH - 1){1'b0}}};

wire                    wave_resample_start;
wire                    wave_point_commit;
wire                    wave_trigger_clear;
wire                    wave_internal_trigger_fire;
wire                    wave_frame_copy_start;
wire                    wave_frame_copy_active;
wire                    wave_frame_commit_valid;
wire                    wave_frame_commit_bank;
wire [SAMPLE_WIDTH-1:0] wave_point_sample_code;
wire [7:0]              wave_point_y;
wire [8:0]              wave_wr_ptr;
wire                    wave_hist_full;
wire [7:0]              wave_last_hist_y;
wire [7:0]              wave_hist_rd_data;
wire [8:0]              wave_hist_rd_idx;
wire [8:0]              wave_frame_snapshot_ptr;
wire [7:0]              wave_frame_last_y;
wire                    wave_history_point_valid;
wire                    wave_resample_pending;
wire                    wave_internal_copy_start;
wire                    wave_first_frame_copy_start;
wire                    wave_external_copy_start;
wire                    wave_auto_copy_start;
wire                    display_update_enable;

assign display_update_enable = !display_freeze;
assign wave_external_copy_start =
    trigger_use_external && trigger_force && wave_hist_full &&
    display_update_enable && !wave_frame_copy_active && !wave_resample_pending;

assign wave_first_frame_copy_start =
    !trigger_use_external && wave_point_commit && !wave_frame_valid &&
    (wave_hist_full || (wave_wr_ptr == (WAVE_POINT_COUNT - 1))) &&
    display_update_enable && !wave_frame_copy_active;

assign wave_internal_copy_start =
    !trigger_use_external && wave_point_commit && wave_hist_full &&
    wave_internal_trigger_fire && !wave_first_frame_copy_start &&
    display_update_enable && !wave_frame_copy_active;

// 触发未命中时按完整历史缓冲轮次自动提交，避免波形只在复位后刷新一次。
assign wave_auto_copy_start =
    !trigger_use_external && wave_point_commit && wave_hist_full &&
    (wave_wr_ptr == (WAVE_POINT_COUNT - 1)) &&
    !wave_first_frame_copy_start && !wave_internal_copy_start &&
    display_update_enable && !wave_frame_copy_active;

assign wave_frame_copy_start    = wave_external_copy_start || wave_first_frame_copy_start ||
                                  wave_internal_copy_start || wave_auto_copy_start;
assign wave_frame_snapshot_ptr  = wave_external_copy_start ? trigger_force_snapshot_ptr : wave_wr_ptr;
assign wave_frame_last_y        = wave_external_copy_start ? wave_last_hist_y : wave_point_y;
assign wave_history_point_valid = wave_point_commit && !wave_frame_copy_active;

assign wave_trigger_clear =
    display_update_enable &&
    (wave_external_copy_start ||
    (!trigger_use_external && wave_point_commit && !wave_frame_valid &&
     (wave_hist_full || (wave_wr_ptr == (WAVE_POINT_COUNT - 1)))));

wave_trigger_core #(
    .WIDTH            (SAMPLE_WIDTH),
    .CENTER_IIR_SHIFT (CENTER_IIR_SHIFT),
    .TRIGGER_HYST     (WAVE_TRIGGER_HYST),
    .CENTER_DEFAULT   (CENTER_DEFAULT)
) u_wave_trigger_core (
    .clk                 (wave_clk),
    .rst_n               (sys_rst_n),
    .sample_valid        (wave_sample_valid),
    .sample_code         (wave_sample_code),
    .trigger_sample_valid(wave_resample_start),
    .trigger_sample_code (wave_sample_code),
    .point_commit_valid  (wave_point_commit),
    .point_commit_code   (wave_point_sample_code),
    .clear_armed         (wave_trigger_clear),
    .center_code         (),
    .trigger_fire        (wave_internal_trigger_fire)
);

wave_display_resampler #(
    .WIDTH         (SAMPLE_WIDTH),
    .POINT_COUNT   (WAVE_POINT_COUNT),
    .FRAME_TICKS   (WAVE_FRAME_TICKS),
    .GRAPH_H       (GRAPH_H),
    .GRAPH_HALF_H  (GRAPH_HALF_H),
    .DIV_WIDTH     (WAVE_DIV_WIDTH),
    .FULL_SCALE_CODE(FULL_SCALE_CODE),
    .CENTER_DEFAULT(CENTER_DEFAULT)
) u_wave_display_resampler (
    .clk                (wave_clk),
    .rst_n              (sys_rst_n),
    .sample_code        (wave_sample_code),
    .zero_code          (wave_zero_code),
    .zero_valid         (wave_zero_valid),
    .trigger_sample_valid(wave_resample_start),
    .point_valid        (wave_point_commit),
    .point_sample_code  (wave_point_sample_code),
    .point_y            (wave_point_y),
    .resample_pending   (wave_resample_pending)
);

wave_history_buffer #(
    .POINT_COUNT      (WAVE_POINT_COUNT),
    .POINT_ADDR_WIDTH (9),
    .Y_WIDTH          (8),
    .Y_RESET          (8'd120)
) u_wave_history_buffer (
    .clk        (wave_clk),
    .rst_n      (sys_rst_n),
    .point_valid(wave_history_point_valid),
    .point_y    (wave_point_y),
    .rd_idx     (wave_hist_rd_idx),
    .wr_ptr     (wave_wr_ptr),
    .hist_full  (wave_hist_full),
    .last_y     (wave_last_hist_y),
    .rd_data    (wave_hist_rd_data)
);

wave_frame_writer #(
    .POINT_COUNT      (WAVE_POINT_COUNT),
    .POINT_ADDR_WIDTH (9),
    .RAM_ADDR_WIDTH   (10),
    .Y_WIDTH          (8),
    .Y_RESET          (8'd120)
) u_wave_frame_writer (
    .clk          (wave_clk),
    .rst_n        (sys_rst_n),
    .start_copy   (wave_frame_copy_start),
    .snapshot_ptr (wave_frame_snapshot_ptr),
    .last_y       (wave_frame_last_y),
    .display_bank (wave_display_bank),
    .hist_rd_data (wave_hist_rd_data),
    .active       (wave_frame_copy_active),
    .hist_rd_idx  (wave_hist_rd_idx),
    .commit_valid (wave_frame_commit_valid),
    .commit_bank  (wave_frame_commit_bank),
    .wave_ram_we  (wave_ram_we),
    .wave_ram_waddr(wave_ram_waddr),
    .wave_ram_wdata(wave_ram_wdata)
);

always @(posedge wave_clk or negedge sys_rst_n) begin
    if (!sys_rst_n) begin
        wave_frame_valid     <= 1'b0;
        wave_display_bank    <= 1'b0;
        trigger_pulse        <= 1'b0;
        trigger_snapshot_ptr <= 9'd0;
    end else begin
        trigger_pulse <= 1'b0;

        if (wave_frame_commit_valid && display_update_enable) begin
            wave_display_bank <= wave_frame_commit_bank;
            wave_frame_valid  <= 1'b1;
        end

        if (wave_first_frame_copy_start || wave_internal_copy_start || wave_auto_copy_start) begin
            trigger_pulse        <= 1'b1;
            trigger_snapshot_ptr <= wave_wr_ptr;
        end
    end
end

endmodule
