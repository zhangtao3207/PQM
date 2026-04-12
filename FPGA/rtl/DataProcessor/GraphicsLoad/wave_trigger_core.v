`timescale 1ns / 1ps

/*
 * 模块: wave_trigger_core
 * 功能:
 *   对输入波形执行中心值跟踪、滞回阈值生成与触发判定。
 *   模块使用原始样本更新中心估计，使用显示重采样节拍更新触发判定输入，
 *   并在提交显示点时完成 armed 状态机判断，输出单拍触发脉冲。
 *
 * 输入:
 *   clk: 模块工作时钟
 *   rst_n: 低有效复位
 *   sample_valid: 原始样本有效标志
 *   sample_code: 原始样本码值，用于中心跟踪
 *   trigger_sample_valid: 触发采样更新使能
 *   trigger_sample_code: 参与触发平滑的当前采样值
 *   point_commit_valid: 一个显示点提交完成标志
 *   point_commit_code: 本次提交显示点对应的采样码值
 *   clear_armed: 外部请求清除 armed 状态
 *
 * 输出:
 *   center_code: 当前跟踪得到的中心码值
 *   trigger_fire: 触发命中脉冲，高电平持续一个时钟周期
 */
module wave_trigger_core #(
    parameter integer WIDTH              = 16,
    parameter integer CENTER_IIR_SHIFT   = 22,
    parameter [WIDTH-1:0] TRIGGER_HYST   = {WIDTH{1'b0}},
    parameter [WIDTH-1:0] CENTER_DEFAULT = {1'b1, {(WIDTH - 1){1'b0}}}
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             sample_valid,
    input  wire [WIDTH-1:0] sample_code,
    input  wire             trigger_sample_valid,
    input  wire [WIDTH-1:0] trigger_sample_code,
    input  wire             point_commit_valid,
    input  wire [WIDTH-1:0] point_commit_code,
    input  wire             clear_armed,
    output wire [WIDTH-1:0] center_code,
    output reg              trigger_fire
);

// 中心跟踪累加器位宽，保存放大 2^CENTER_IIR_SHIFT 后的中心估计值。
localparam integer CENTER_ACC_W = WIDTH + CENTER_IIR_SHIFT + 2;

// 中心跟踪状态与触发判定状态。
reg [CENTER_ACC_W-1:0] center_acc;
reg                    trigger_armed;
reg [WIDTH-1:0]        trigger_code_d0;
reg [WIDTH-1:0]        trigger_code_d1;
reg [WIDTH-1:0]        trigger_code_d2;
reg [WIDTH-1:0]        trigger_code_pending;

// 由中心值生成上下滞回门限，并对最近 4 个触发采样做平均。
wire [WIDTH-1:0] trigger_low;
wire [WIDTH-1:0] trigger_high;
wire [WIDTH+1:0] trigger_sum;

assign center_code  = center_acc[CENTER_IIR_SHIFT + WIDTH - 1:CENTER_IIR_SHIFT];
assign trigger_low  = (center_code > TRIGGER_HYST) ? (center_code - TRIGGER_HYST) : {WIDTH{1'b0}};
assign trigger_high = (center_code < ({WIDTH{1'b1}} - TRIGGER_HYST)) ? (center_code + TRIGGER_HYST) : {WIDTH{1'b1}};
assign trigger_sum  = {2'b00, trigger_sample_code} +
                      {2'b00, trigger_code_d0} +
                      {2'b00, trigger_code_d1} +
                      {2'b00, trigger_code_d2};

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 复位后以缺省中心值初始化，避免触发门限悬空。
        center_acc           <= {CENTER_DEFAULT, {CENTER_IIR_SHIFT{1'b0}}};
        trigger_armed        <= 1'b0;
        trigger_code_d0      <= CENTER_DEFAULT;
        trigger_code_d1      <= CENTER_DEFAULT;
        trigger_code_d2      <= CENTER_DEFAULT;
        trigger_code_pending <= CENTER_DEFAULT;
        trigger_fire         <= 1'b0;
    end else begin
        // 触发输出为单拍脉冲，默认每拍拉低。
        trigger_fire <= 1'b0;

        if (sample_valid) begin
            // 一阶 IIR 中心跟踪：逐步逼近输入波形的直流中心。
            center_acc <= center_acc +
                          {{(CENTER_ACC_W - WIDTH){1'b0}}, sample_code} -
                          {{(CENTER_ACC_W - WIDTH){1'b0}}, center_code};
        end

        if (trigger_sample_valid) begin
            // 对当前样本与前三个提交点做 4 点平均，降低触发抖动。
            trigger_code_pending <= (trigger_sum + {{WIDTH{1'b0}}, 2'd2}) >> 2;
        end

        if (point_commit_valid) begin
            // 提交一个显示点后，刷新触发历史窗口。
            trigger_code_d2 <= trigger_code_d1;
            trigger_code_d1 <= trigger_code_d0;
            trigger_code_d0 <= point_commit_code;

            if (trigger_code_pending >= trigger_high) begin
                if (trigger_armed) begin
                    // 仅在已布防状态下穿越高门限时输出触发脉冲。
                    trigger_fire  <= 1'b1;
                    trigger_armed <= 1'b0;
                end
            end else if (trigger_code_pending <= trigger_low) begin
                // 跌破低门限后重新布防，等待下一次上穿触发。
                trigger_armed <= 1'b1;
            end
        end

        if (clear_armed) begin
            // 外部在强制触发或首帧抓取后清除布防状态。
            trigger_armed <= 1'b0;
        end
    end
end

endmodule
