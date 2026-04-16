`timescale 1ns / 1ps

/*
 * 模块: freq_display_adapter
 * 功能:
 *   频域分析结果到 LCD 显示点的适配层。
 *   接收 freq_analysis_top 输出的 0~500 次谐波结果流，将 U/I 幅值占比和 U-I 相位角
 *   换算成频域页面直接使用的柱图高度，并写入后台显示 bank。
 *   一帧谐波结果全部写完后才提交 display_bank，界面切换不反向影响 FFT 采集和分析链路。
 *
 * 输入:
 *   clk: 频域显示适配工作时钟，通常与 FFT 计算时钟一致。
 *   rst_n: 低有效复位信号。
 *   enable: 适配层写入使能，拉低时停止接收新结果并保持已有显示 bank。
 *   s_harmonic_valid: 上游谐波结果有效标志。
 *   s_harmonic_last: 上游 0~500 次谐波结果的最后一项标志。
 *   s_harmonic_order: 当前谐波次数。
 *   s_harmonic_present: 当前谐波在本帧中是否被捕获。
 *   s_u_pct_x100: 当前谐波电压幅值占比，100.00% 表示为 10000。
 *   s_i_pct_x100: 当前谐波电流幅值占比，100.00% 表示为 10000。
 *   s_phase_diff_valid: 当前谐波 U-I 相位角是否有效。
 *   s_phase_diff_deg_x100: 当前谐波 U-I 相位角，单位为 deg_x100。
 *
 * 输出:
 *   s_harmonic_ready: 本模块对上游谐波结果的接收就绪标志。
 *   freq_ram_we: 频域显示 RAM 写使能。
 *   freq_ram_waddr: 频域显示 RAM 写地址，高位为 bank，低位为谐波次数。
 *   freq_u_mag_wdata: 电压幅值柱图高度。
 *   freq_i_mag_wdata: 电流幅值柱图高度。
 *   freq_phase_wdata: 相位柱图高度。
 *   freq_flag_wdata: 显示标志，bit0=present，bit1=phase_valid，bit2=phase_negative。
 *   display_bank: 最近一帧完整频域显示数据所在的前台 bank。
 *   frame_valid: 至少已有一帧完整频域显示数据可读。
 *   frame_sequence: 已提交完整频域显示帧计数。
 */
module freq_display_adapter (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               enable,
    input  wire               s_harmonic_valid,
    output wire               s_harmonic_ready,
    input  wire               s_harmonic_last,
    input  wire [8:0]         s_harmonic_order,
    input  wire               s_harmonic_present,
    input  wire [15:0]        s_u_pct_x100,
    input  wire [15:0]        s_i_pct_x100,
    input  wire               s_phase_diff_valid,
    input  wire signed [15:0] s_phase_diff_deg_x100,

    output reg                freq_ram_we,
    output reg  [9:0]         freq_ram_waddr,
    output reg  [7:0]         freq_u_mag_wdata,
    output reg  [7:0]         freq_i_mag_wdata,
    output reg  [7:0]         freq_phase_wdata,
    output reg  [7:0]         freq_flag_wdata,
    output reg                display_bank,
    output reg                frame_valid,
    output reg  [15:0]        frame_sequence
);

localparam [2:0]  ST_IDLE        = 3'd0;
localparam [2:0]  ST_SCALE_START = 3'd1;
localparam [2:0]  ST_SCALE_WAIT  = 3'd2;
localparam [2:0]  ST_WRITE       = 3'd3;
localparam [2:0]  ST_COMMIT      = 3'd4;
localparam [8:0]  LAST_HARMONIC_ORDER = 9'd500;
localparam [15:0] MAG_HEIGHT_MAX      = 16'd180;
localparam [15:0] MAG_SCALE_DEN       = 16'd10000;
localparam [31:0] MAG_SCALE_DEN_HALF  = 32'd5000;
localparam [15:0] PHASE_HEIGHT_MAX    = 16'd78;
localparam [15:0] PHASE_SCALE_DEN     = 16'd18000;
localparam [31:0] PHASE_SCALE_DEN_HALF = 32'd9000;

reg  [2:0]         state;
reg                write_bank;
reg                work_last;
reg  [8:0]         work_order;
reg                work_present;
reg  [15:0]        work_u_pct_x100;
reg  [15:0]        work_i_pct_x100;
reg                work_phase_valid;
reg                work_phase_neg;
reg signed [15:0]  work_phase_deg_x100;
reg                u_div_start;
reg                i_div_start;
reg                phase_div_start;
reg                u_div_done_seen;
reg                i_div_done_seen;
reg                phase_div_done_seen;

wire               input_fire;
wire               work_order_in_range;
wire [15:0]        u_pct_for_scale;
wire [15:0]        i_pct_for_scale;
wire [15:0]        phase_abs_x100;
wire [15:0]        phase_abs_for_scale;
wire signed [31:0] u_mag_product_signed;
wire signed [31:0] i_mag_product_signed;
wire signed [31:0] phase_product_signed;
wire [31:0]        u_mag_product_unsigned;
wire [31:0]        i_mag_product_unsigned;
wire [31:0]        phase_product_unsigned;
wire               u_mag_div_done;
wire               u_mag_div_zero;
wire [31:0]        u_mag_div_quotient;
wire               i_mag_div_done;
wire               i_mag_div_zero;
wire [31:0]        i_mag_div_quotient;
wire               phase_div_done;
wire               phase_div_zero;
wire [31:0]        phase_div_quotient;
wire               all_div_done;

// 空闲状态才接收新的谐波结果，缩放期间通过 ready 反压保持上游结果稳定。
assign s_harmonic_ready = enable && (state == ST_IDLE);
assign input_fire       = s_harmonic_valid && s_harmonic_ready;

// 只写入 0~500 次谐波对应的显示地址，越界结果被丢弃但 last 仍会提交帧。
assign work_order_in_range = (work_order <= LAST_HARMONIC_ORDER);

// 显示高度只需要 0~100.00% 和 0~180.00 度范围，超出部分按满幅显示处理。
assign u_pct_for_scale = (work_u_pct_x100 > MAG_SCALE_DEN) ? MAG_SCALE_DEN : work_u_pct_x100;
assign i_pct_for_scale = (work_i_pct_x100 > MAG_SCALE_DEN) ? MAG_SCALE_DEN : work_i_pct_x100;
assign phase_abs_x100 = work_phase_deg_x100[15] ?
                        (~work_phase_deg_x100[15:0] + 16'd1) :
                        work_phase_deg_x100[15:0];
assign phase_abs_for_scale = (phase_abs_x100 > PHASE_SCALE_DEN) ? PHASE_SCALE_DEN : phase_abs_x100;

// 将 U 通道幅值百分比换算为幅值图区域内的柱图高度。
multiplier_signed #(
    .A_WIDTH(16),
    .B_WIDTH(16)
) u_u_mag_height_multiplier (
    .multiplicand({1'b0, u_pct_for_scale[14:0]}),
    .multiplier  (MAG_HEIGHT_MAX),
    .product     (u_mag_product_signed)
);

// 将 I 通道幅值百分比换算为幅值图区域内的柱图高度。
multiplier_signed #(
    .A_WIDTH(16),
    .B_WIDTH(16)
) u_i_mag_height_multiplier (
    .multiplicand({1'b0, i_pct_for_scale[14:0]}),
    .multiplier  (MAG_HEIGHT_MAX),
    .product     (i_mag_product_signed)
);

// 将相位角幅值换算为相位图区域内的柱图高度。
multiplier_signed #(
    .A_WIDTH(16),
    .B_WIDTH(16)
) u_phase_height_multiplier (
    .multiplicand({1'b0, phase_abs_for_scale[14:0]}),
    .multiplier  (PHASE_HEIGHT_MAX),
    .product     (phase_product_signed)
);

// 负乘积保护为 0，正常输入均为非负显示量。
assign u_mag_product_unsigned = u_mag_product_signed[31] ? 32'd0 : u_mag_product_signed[31:0];
assign i_mag_product_unsigned = i_mag_product_signed[31] ? 32'd0 : i_mag_product_signed[31:0];
assign phase_product_unsigned = phase_product_signed[31] ? 32'd0 : phase_product_signed[31:0];

// 对 U 通道幅值显示高度做百分比归一化。
divider_unsigned #(
    .WIDTH(32)
) u_u_mag_height_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (u_div_start),
    .dividend      (u_mag_product_unsigned + MAG_SCALE_DEN_HALF),
    .divisor       ({16'd0, MAG_SCALE_DEN}),
    .busy          (),
    .done          (u_mag_div_done),
    .divide_by_zero(u_mag_div_zero),
    .quotient      (u_mag_div_quotient)
);

// 对 I 通道幅值显示高度做百分比归一化。
divider_unsigned #(
    .WIDTH(32)
) u_i_mag_height_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (i_div_start),
    .dividend      (i_mag_product_unsigned + MAG_SCALE_DEN_HALF),
    .divisor       ({16'd0, MAG_SCALE_DEN}),
    .busy          (),
    .done          (i_mag_div_done),
    .divide_by_zero(i_mag_div_zero),
    .quotient      (i_mag_div_quotient)
);

// 对相位显示高度做 0~180 度范围归一化。
divider_unsigned #(
    .WIDTH(32)
) u_phase_height_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (phase_div_start),
    .dividend      (phase_product_unsigned + PHASE_SCALE_DEN_HALF),
    .divisor       ({16'd0, PHASE_SCALE_DEN}),
    .busy          (),
    .done          (phase_div_done),
    .divide_by_zero(phase_div_zero),
    .quotient      (phase_div_quotient)
);

// 三路缩放均完成后，当前谐波显示点才允许写入后台 bank。
assign all_div_done = (u_div_done_seen || u_mag_div_done) &&
                      (i_div_done_seen || i_mag_div_done) &&
                      (phase_div_done_seen || phase_div_done);

// 顺序接收一个谐波结果，完成三路显示高度换算，再写入后台显示 RAM。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state               <= ST_IDLE;
        write_bank          <= 1'b1;
        work_last           <= 1'b0;
        work_order          <= 9'd0;
        work_present        <= 1'b0;
        work_u_pct_x100     <= 16'd0;
        work_i_pct_x100     <= 16'd0;
        work_phase_valid    <= 1'b0;
        work_phase_neg      <= 1'b0;
        work_phase_deg_x100 <= 16'sd0;
        u_div_start         <= 1'b0;
        i_div_start         <= 1'b0;
        phase_div_start     <= 1'b0;
        u_div_done_seen     <= 1'b0;
        i_div_done_seen     <= 1'b0;
        phase_div_done_seen <= 1'b0;
        freq_ram_we         <= 1'b0;
        freq_ram_waddr      <= 10'd0;
        freq_u_mag_wdata    <= 8'd0;
        freq_i_mag_wdata    <= 8'd0;
        freq_phase_wdata    <= 8'd0;
        freq_flag_wdata     <= 8'd0;
        display_bank        <= 1'b0;
        frame_valid         <= 1'b0;
        frame_sequence      <= 16'd0;
    end else begin
        u_div_start     <= 1'b0;
        i_div_start     <= 1'b0;
        phase_div_start <= 1'b0;
        freq_ram_we     <= 1'b0;

        if (u_mag_div_done)
            u_div_done_seen <= 1'b1;
        if (i_mag_div_done)
            i_div_done_seen <= 1'b1;
        if (phase_div_done)
            phase_div_done_seen <= 1'b1;

        case (state)
            ST_IDLE: begin
                if (!enable) begin
                    u_div_done_seen     <= 1'b0;
                    i_div_done_seen     <= 1'b0;
                    phase_div_done_seen <= 1'b0;
                end else if (input_fire) begin
                    work_last           <= s_harmonic_last;
                    work_order          <= s_harmonic_order;
                    work_present        <= s_harmonic_present;
                    work_u_pct_x100     <= s_harmonic_present ? s_u_pct_x100 : 16'd0;
                    work_i_pct_x100     <= s_harmonic_present ? s_i_pct_x100 : 16'd0;
                    work_phase_valid    <= s_harmonic_present && s_phase_diff_valid;
                    work_phase_neg      <= s_harmonic_present && s_phase_diff_valid && s_phase_diff_deg_x100[15];
                    work_phase_deg_x100 <= (s_harmonic_present && s_phase_diff_valid) ?
                                           s_phase_diff_deg_x100 : 16'sd0;
                    u_div_done_seen     <= 1'b0;
                    i_div_done_seen     <= 1'b0;
                    phase_div_done_seen <= 1'b0;
                    state               <= ST_SCALE_START;
                end
            end

            ST_SCALE_START: begin
                u_div_start     <= 1'b1;
                i_div_start     <= 1'b1;
                phase_div_start <= 1'b1;
                state           <= ST_SCALE_WAIT;
            end

            ST_SCALE_WAIT: begin
                if (all_div_done)
                    state <= ST_WRITE;
            end

            ST_WRITE: begin
                if (work_order_in_range) begin
                    freq_ram_we    <= 1'b1;
                    freq_ram_waddr <= {write_bank, work_order};

                    if (!work_present || u_mag_div_zero)
                        freq_u_mag_wdata <= 8'd0;
                    else if (u_mag_div_quotient > {16'd0, MAG_HEIGHT_MAX})
                        freq_u_mag_wdata <= MAG_HEIGHT_MAX[7:0];
                    else
                        freq_u_mag_wdata <= u_mag_div_quotient[7:0];

                    if (!work_present || i_mag_div_zero)
                        freq_i_mag_wdata <= 8'd0;
                    else if (i_mag_div_quotient > {16'd0, MAG_HEIGHT_MAX})
                        freq_i_mag_wdata <= MAG_HEIGHT_MAX[7:0];
                    else
                        freq_i_mag_wdata <= i_mag_div_quotient[7:0];

                    if (!work_phase_valid || phase_div_zero)
                        freq_phase_wdata <= 8'd0;
                    else if (phase_div_quotient > {16'd0, PHASE_HEIGHT_MAX})
                        freq_phase_wdata <= PHASE_HEIGHT_MAX[7:0];
                    else
                        freq_phase_wdata <= phase_div_quotient[7:0];

                    freq_flag_wdata <= {5'd0, work_phase_neg, work_phase_valid, work_present};
                end

                if (work_last)
                    state <= ST_COMMIT;
                else
                    state <= ST_IDLE;
            end

            ST_COMMIT: begin
                // 等待最后一个显示点被 RAM 写口采样后，再提交新的前台 bank。
                display_bank   <= write_bank;
                frame_valid    <= 1'b1;
                frame_sequence <= frame_sequence + 16'd1;
                write_bank     <= ~write_bank;
                state          <= ST_IDLE;
            end

            default: begin
                state <= ST_IDLE;
            end
        endcase
    end
end

endmodule
