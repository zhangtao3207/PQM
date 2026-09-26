`timescale 1ns / 1ps

/*
 * 模块: fft_fundamental_freq_tracker
 * 功能:
 *   监听 FFT 幅值流中的基波 bin 复相量，利用相邻两帧同一 bin 的相位增量估计基波频率，
 *   输出与时域文字区原有接口兼容的 `freq_period_raw` 周期计数。
 * 输入:
 *   clk: 频域计算时钟，当前工程中与 wave_clk 同域。
 *   rst_n: 低有效复位。
 *   enable: 跟踪器使能，拉低时清空锁存结果。
 *   s_mag_valid: FFT 幅值结果有效标志。
 *   s_bin_index: 当前幅值结果对应的 FFT bin。
 *   s_u_real: 电压通道当前 bin 的实部。
 *   s_u_imag: 电压通道当前 bin 的虚部。
 *   s_u_mag: 电压通道当前 bin 的幅值。
 * 输出:
 *   freq_period_raw: 估计得到的基波周期计数，量纲与旧时域 `frequency_measure` 保持一致。
 *   freq_valid: 周期估计是否已经锁定有效；该标志锁存保持，便于显示链任意时刻采样。
 */
module fft_fundamental_freq_tracker #(
    parameter [10:0] TRACK_BIN = 11'd1
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               enable,
    input  wire               s_mag_valid,
    input  wire               s_mag_ready,
    input  wire [10:0]        s_bin_index,
    input  wire signed [15:0] s_u_real,
    input  wire signed [15:0] s_u_imag,
    input  wire [16:0]        s_u_mag,
    output reg  signed [31:0] freq_period_raw,
    output reg                freq_valid
);

localparam [3:0] ST_IDLE            = 4'd0;
localparam [3:0] ST_PHASE_PREP      = 4'd1;
localparam [3:0] ST_PHASE_DIV_REQ   = 4'd2;
localparam [3:0] ST_PHASE_DIV_WAIT  = 4'd3;
localparam [3:0] ST_PHASE_ROM_REQ   = 4'd4;
localparam [3:0] ST_PHASE_ROM_WAIT  = 4'd5;
localparam [3:0] ST_PERIOD_DIV_REQ  = 4'd6;
localparam [3:0] ST_PERIOD_DIV_WAIT = 4'd7;

localparam signed [15:0] PHASE_180_X100 = 16'sd18000;
localparam signed [16:0] PHASE_360_X100 = 17'sd36000;

reg  [3:0]               state;
reg  [31:0]              clk_counter;
reg                      last_bin_valid;
reg  [31:0]              last_bin_clk;
reg  signed [15:0]       last_u_real;
reg  signed [15:0]       last_u_imag;
reg  [16:0]              last_u_mag;
reg  signed [15:0]       work_prev_u_real;
reg  signed [15:0]       work_prev_u_imag;
reg  signed [15:0]       work_curr_u_real;
reg  signed [15:0]       work_curr_u_imag;
reg  [31:0]              work_frame_period_clk;
reg                      phase_dot_negative_reg;
reg                      phase_cross_negative_reg;
reg                      phase_result_valid_reg;
reg  [43:0]              phase_dividend_reg;
reg  [43:0]              phase_divisor_reg;
reg  [10:0]              phase_rom_addr_reg;
reg  [16:0]              period_divisor_reg;
reg                      period_iir_valid_reg;
reg  [31:0]              period_iir_state_reg;

localparam integer PERIOD_IIR_SHIFT = 4;

wire                     track_fire;
wire                     track_sample_valid;
wire signed [31:0]       dot_rr_product;
wire signed [31:0]       dot_ii_product;
wire signed [31:0]       cross_ir_product;
wire signed [31:0]       cross_ri_product;
wire signed [32:0]       phase_dot_next;
wire signed [32:0]       phase_cross_next;
wire [32:0]              abs_dot_next;
wire [32:0]              abs_cross_next;
wire [33:0]              phase_denominator_next;
wire [43:0]              phase_dividend_next;
wire [43:0]              phase_divisor_next;
wire                     phase_input_valid;
wire                     phase_div_done;
wire                     phase_div_zero;
wire [43:0]              phase_div_q;
wire [10:0]              phase_div_addr;
wire [13:0]              phase_rom_angle_deg_x100;
wire signed [15:0]       phase_angle_0_90;
wire signed [15:0]       phase_angle_next;
wire signed [16:0]       period_divisor_next_signed;
wire                     period_divisor_valid;
wire signed [47:0]       frame_period_scale_product_signed;
wire [47:0]              frame_period_scale_product_unsigned;
wire                     period_div_done;
wire                     period_div_zero;
wire [47:0]              period_div_q;
wire [31:0]              period_candidate_next;
wire [31:0]              period_smoothed_next;

// 组合识别当前幅值流是否命中基波跟踪 bin，并要求该 bin 幅值非零后才发起新一轮估计。
assign track_fire         = enable && s_mag_valid && s_mag_ready && (s_bin_index == TRACK_BIN);
assign track_sample_valid = track_fire && (s_u_mag != 17'd0);

// 组合计算相邻两帧基波复相量的 dot/cross，用于后续 atan2 求相位增量。
assign phase_dot_next =
    {dot_rr_product[31], dot_rr_product} + {dot_ii_product[31], dot_ii_product};
assign phase_cross_next =
    {cross_ir_product[31], cross_ir_product} - {cross_ri_product[31], cross_ri_product};

// 组合提取相位向量绝对值并构造 atan ROM 地址除法器输入。
assign abs_dot_next =
    phase_dot_next[32] ? ((~phase_dot_next[32:0]) + 33'd1) : phase_dot_next[32:0];
assign abs_cross_next =
    phase_cross_next[32] ? ((~phase_cross_next[32:0]) + 33'd1) : phase_cross_next[32:0];
assign phase_denominator_next = {1'b0, abs_dot_next} + {1'b0, abs_cross_next};
assign phase_dividend_next    = {1'b0, abs_cross_next, 10'd0};
assign phase_divisor_next     = {10'd0, phase_denominator_next};
assign phase_input_valid      = (work_frame_period_clk != 32'd0) && (phase_denominator_next != 34'd0);

// 组合完成第一象限角度和象限修正，得到相邻两帧基波相位增量。
assign phase_div_addr   =
    (phase_div_q[43:11] != 33'd0) ? 11'd1024 : phase_div_q[10:0];
assign phase_angle_0_90 = {2'b00, phase_rom_angle_deg_x100};
assign phase_angle_next =
    !phase_result_valid_reg ? 16'sd0 :
    (!phase_dot_negative_reg && !phase_cross_negative_reg) ? phase_angle_0_90 :
    (!phase_dot_negative_reg &&  phase_cross_negative_reg) ? -phase_angle_0_90 :
    ( phase_dot_negative_reg && !phase_cross_negative_reg) ? (PHASE_180_X100 - phase_angle_0_90) :
                                                             (-PHASE_180_X100 + phase_angle_0_90);

// 组合把残余相位增量换算为每个完整基波周期对应的时钟计数比例因子。
assign period_divisor_next_signed = PHASE_360_X100 + {phase_angle_next[15], phase_angle_next};
assign period_divisor_valid       = !period_divisor_next_signed[16] && (period_divisor_next_signed != 17'sd0);

// 组合裁剪周期除法结果，并做 1/16 IIR 平滑，降低帧间抖动。
assign period_candidate_next =
    (period_div_q[47:32] != 16'd0) ? 32'hFFFF_FFFF : period_div_q[31:0];
assign period_smoothed_next =
    smooth_unsigned32(period_iir_valid_reg, period_iir_state_reg, period_candidate_next);

// 复用 BasicMath 乘法器计算当前帧与上一帧基波相位增量的同相投影第一项。
multiplier_signed #(
    .A_WIDTH(16),
    .B_WIDTH(16)
) u_dot_rr_multiplier (
    .multiplicand(work_curr_u_real),
    .multiplier  (work_prev_u_real),
    .product     (dot_rr_product)
);

// 复用 BasicMath 乘法器计算当前帧与上一帧基波相位增量的同相投影第二项。
multiplier_signed #(
    .A_WIDTH(16),
    .B_WIDTH(16)
) u_dot_ii_multiplier (
    .multiplicand(work_curr_u_imag),
    .multiplier  (work_prev_u_imag),
    .product     (dot_ii_product)
);

// 复用 BasicMath 乘法器计算当前帧与上一帧基波相位增量的正交投影第一项。
multiplier_signed #(
    .A_WIDTH(16),
    .B_WIDTH(16)
) u_cross_ir_multiplier (
    .multiplicand(work_curr_u_imag),
    .multiplier  (work_prev_u_real),
    .product     (cross_ir_product)
);

// 复用 BasicMath 乘法器计算当前帧与上一帧基波相位增量的正交投影第二项。
multiplier_signed #(
    .A_WIDTH(16),
    .B_WIDTH(16)
) u_cross_ri_multiplier (
    .multiplicand(work_curr_u_real),
    .multiplier  (work_prev_u_imag),
    .product     (cross_ri_product)
);

// 复用 BasicMath 无符号除法器，计算 atan ROM 地址 abs_cross * 1024 / (abs_dot + abs_cross)。
divider_unsigned #(
    .WIDTH(44)
) u_phase_addr_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (state == ST_PHASE_DIV_REQ),
    .dividend      (phase_dividend_reg),
    .divisor       (phase_divisor_reg),
    .busy          (),
    .done          (phase_div_done),
    .divide_by_zero(phase_div_zero),
    .quotient      (phase_div_q)
);

// 实例化 atan 查表 ROM，把相位增量向量换算为第一象限角度。
rom_atan_lut_1024 u_phase_inc_rom (
    .clka (clk),
    .ena  (state == ST_PHASE_ROM_REQ),
    .addra(phase_rom_addr_reg),
    .douta(phase_rom_angle_deg_x100)
);

// 复用 BasicMath 乘法器，把一帧时长乘以 360.00deg，构造周期换算除法器分子。
multiplier_signed #(
    .A_WIDTH(32),
    .B_WIDTH(16)
) u_frame_period_scale_multiplier (
    .multiplicand({1'b0, work_frame_period_clk[30:0]}),
    .multiplier  (16'sd36000),
    .product     (frame_period_scale_product_signed)
);

// 组合把周期换算分子转为无符号量，供后续无符号除法器使用。
assign frame_period_scale_product_unsigned =
    frame_period_scale_product_signed[47] ? 48'd0 : frame_period_scale_product_signed[47:0];

// 复用 BasicMath 无符号除法器，把帧时长按相位增量修正为单个基波周期时钟计数。
divider_unsigned #(
    .WIDTH(48)
) u_period_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (state == ST_PERIOD_DIV_REQ),
    .dividend      (frame_period_scale_product_unsigned + {31'd0, period_divisor_reg[16:1]}),
    .divisor       ({31'd0, period_divisor_reg}),
    .busy          (),
    .done          (period_div_done),
    .divide_by_zero(period_div_zero),
    .quotient      (period_div_q)
);

// 函数: smooth_unsigned32
// 功能: 对正值周期估计做 1/16 IIR 平滑，降低 FFT 帧间抖动。
function [31:0] smooth_unsigned32;
    input        initialized;
    input [31:0] old_value;
    input [31:0] input_value;
    reg signed [32:0] old_ext;
    reg signed [32:0] input_ext;
    reg signed [32:0] delta_ext;
    reg signed [32:0] next_ext;
    begin
        old_ext   = {1'b0, old_value};
        input_ext = {1'b0, input_value};
        delta_ext = input_ext - old_ext;
        next_ext  = initialized ? (old_ext + (delta_ext >>> PERIOD_IIR_SHIFT)) : input_ext;
        smooth_unsigned32 = next_ext[31:0];
    end
endfunction

// 在频域时钟域持续计数帧间时长，并在命中基波 bin 时发起一次新的频率估计。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state                    <= ST_IDLE;
        clk_counter              <= 32'd0;
        last_bin_valid           <= 1'b0;
        last_bin_clk             <= 32'd0;
        last_u_real              <= 16'sd0;
        last_u_imag              <= 16'sd0;
        last_u_mag               <= 17'd0;
        work_prev_u_real         <= 16'sd0;
        work_prev_u_imag         <= 16'sd0;
        work_curr_u_real         <= 16'sd0;
        work_curr_u_imag         <= 16'sd0;
        work_frame_period_clk    <= 32'd0;
        phase_dot_negative_reg   <= 1'b0;
        phase_cross_negative_reg <= 1'b0;
        phase_result_valid_reg   <= 1'b0;
        phase_dividend_reg       <= 44'd0;
        phase_divisor_reg        <= 44'd0;
        phase_rom_addr_reg       <= 11'd0;
        period_divisor_reg       <= 17'd0;
        period_iir_valid_reg     <= 1'b0;
        period_iir_state_reg     <= 32'd0;
        freq_period_raw          <= 32'sd0;
        freq_valid               <= 1'b0;
    end else begin
        clk_counter <= clk_counter + 32'd1;

        if (!enable) begin
            state                  <= ST_IDLE;
            last_bin_valid         <= 1'b0;
            phase_result_valid_reg <= 1'b0;
            period_iir_valid_reg   <= 1'b0;
            period_iir_state_reg   <= 32'd0;
            freq_period_raw        <= 32'sd0;
            freq_valid             <= 1'b0;
        end else begin
            // 在命中基波 bin 时更新上一帧缓存，并在空闲态发起新一轮频率估计。
            if (track_sample_valid) begin
                if ((state == ST_IDLE) && last_bin_valid && (last_u_mag != 17'd0)) begin
                    work_prev_u_real      <= last_u_real;
                    work_prev_u_imag      <= last_u_imag;
                    work_curr_u_real      <= s_u_real;
                    work_curr_u_imag      <= s_u_imag;
                    work_frame_period_clk <= clk_counter - last_bin_clk;
                    state                 <= ST_PHASE_PREP;
                end

                last_bin_valid <= 1'b1;
                last_bin_clk   <= clk_counter;
                last_u_real    <= s_u_real;
                last_u_imag    <= s_u_imag;
                last_u_mag     <= s_u_mag;
            end

            case (state)
                ST_IDLE: begin
                    phase_result_valid_reg <= 1'b0;
                end

                ST_PHASE_PREP: begin
                    phase_dot_negative_reg   <= phase_dot_next[32];
                    phase_cross_negative_reg <= phase_cross_next[32];
                    phase_result_valid_reg   <= phase_input_valid;
                    phase_dividend_reg       <= phase_dividend_next;
                    phase_divisor_reg        <= phase_divisor_next;

                    if (phase_input_valid)
                        state <= ST_PHASE_DIV_REQ;
                    else
                        state <= ST_IDLE;
                end

                ST_PHASE_DIV_REQ: begin
                    state <= ST_PHASE_DIV_WAIT;
                end

                ST_PHASE_DIV_WAIT: begin
                    if (phase_div_done) begin
                        if (phase_div_zero) begin
                            state <= ST_IDLE;
                        end else begin
                            phase_rom_addr_reg <= phase_div_addr;
                            state              <= ST_PHASE_ROM_REQ;
                        end
                    end
                end

                ST_PHASE_ROM_REQ: begin
                    state <= ST_PHASE_ROM_WAIT;
                end

                ST_PHASE_ROM_WAIT: begin
                    if (period_divisor_valid) begin
                        period_divisor_reg <= period_divisor_next_signed[16:0];
                        state              <= ST_PERIOD_DIV_REQ;
                    end else begin
                        state <= ST_IDLE;
                    end
                end

                ST_PERIOD_DIV_REQ: begin
                    state <= ST_PERIOD_DIV_WAIT;
                end

                ST_PERIOD_DIV_WAIT: begin
                    if (period_div_done) begin
                        if (!period_div_zero) begin
                            period_iir_state_reg <= period_smoothed_next;
                            period_iir_valid_reg <= 1'b1;
                            freq_period_raw      <= {1'b0, period_smoothed_next[30:0]};
                            freq_valid           <= 1'b1;
                        end

                        state <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end
end

endmodule
