`timescale 1ns / 1ps

/*
 * 模块: phase_deg_lut_calc
 * 功能:
 *   接收 U-I 相位差的 dot/cross 向量，通过 atan 查表 ROM 输出带两位小数的角度结果。
 *   角度输出格式为 deg_x100，例如 3025 表示 30.25 度，-1550 表示 -15.50 度。
 *
 * 输入:
 *   clk: 频域相位角计算时钟，通常接 fft_clk。
 *   rst_n: 低有效复位信号。
 *   enable: 相位角计算使能，拉低时清空待输出结果。
 *   s_harmonic_valid: 上游带相位向量的谐波结果有效标志。
 *   s_harmonic_last: 上游 0~500 次谐波结果的最后一项标志。
 *   s_harmonic_order: 上游谐波次数。
 *   s_harmonic_present: 当前谐波在本帧中是否被捕获。
 *   s_u_real: 当前谐波电压通道实部。
 *   s_u_imag: 当前谐波电压通道虚部。
 *   s_i_real: 当前谐波电流通道实部。
 *   s_i_imag: 当前谐波电流通道虚部。
 *   s_u_mag: 当前谐波电压通道幅值。
 *   s_i_mag: 当前谐波电流通道幅值。
 *   s_u_pct_x100: 当前谐波电压幅值占比。
 *   s_i_pct_x100: 当前谐波电流幅值占比。
 *   s_phase_vector_valid: 当前 dot/cross 是否可用于相位角计算。
 *   s_phase_dot: U-I 相位差 atan2 的同相投影输入。
 *   s_phase_cross: U-I 相位差 atan2 的正交投影输入。
 *   m_harmonic_ready: 下游带相位角的谐波结果接收就绪标志。
 *
 * 输出:
 *   s_harmonic_ready: 本模块对上游带相位向量结果的接收就绪标志。
 *   m_harmonic_valid: 带相位角的谐波结果有效标志。
 *   m_harmonic_last: 带相位角结果的最后一项标志。
 *   m_harmonic_order: 当前输出的谐波次数。
 *   m_harmonic_present: 当前谐波在本帧中是否被捕获。
 *   m_u_real: 当前谐波电压通道实部。
 *   m_u_imag: 当前谐波电压通道虚部。
 *   m_i_real: 当前谐波电流通道实部。
 *   m_i_imag: 当前谐波电流通道虚部。
 *   m_u_mag: 当前谐波电压通道幅值。
 *   m_i_mag: 当前谐波电流通道幅值。
 *   m_u_pct_x100: 当前谐波电压幅值占比。
 *   m_i_pct_x100: 当前谐波电流幅值占比。
 *   m_phase_vector_valid: 当前 dot/cross 是否有效。
 *   m_phase_dot: 与角度结果对齐的 dot。
 *   m_phase_cross: 与角度结果对齐的 cross。
 *   m_phase_diff_valid: 当前相位差角度是否有效。
 *   m_phase_diff_deg_x100: U-I 相位差角度，范围约为 -18000 到 +18000。
 *   phase_deg_busy: 当前正在计算或等待输出相位角结果。
 *   phase_deg_frame_done: 一帧 0~500 次谐波相位角结果已输出完毕的单周期脉冲。
 *   phase_deg_frame_count: 已完整输出的相位角结果帧计数。
 */
module phase_deg_lut_calc (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               enable,
    input  wire               s_harmonic_valid,
    output wire               s_harmonic_ready,
    input  wire               s_harmonic_last,
    input  wire [8:0]         s_harmonic_order,
    input  wire               s_harmonic_present,
    input  wire signed [15:0] s_u_real,
    input  wire signed [15:0] s_u_imag,
    input  wire signed [15:0] s_i_real,
    input  wire signed [15:0] s_i_imag,
    input  wire [16:0]        s_u_mag,
    input  wire [16:0]        s_i_mag,
    input  wire [15:0]        s_u_pct_x100,
    input  wire [15:0]        s_i_pct_x100,
    input  wire               s_phase_vector_valid,
    input  wire signed [32:0] s_phase_dot,
    input  wire signed [32:0] s_phase_cross,
    input  wire               m_harmonic_ready,
    output wire               m_harmonic_valid,
    output wire               m_harmonic_last,
    output wire [8:0]         m_harmonic_order,
    output wire               m_harmonic_present,
    output wire signed [15:0] m_u_real,
    output wire signed [15:0] m_u_imag,
    output wire signed [15:0] m_i_real,
    output wire signed [15:0] m_i_imag,
    output wire [16:0]        m_u_mag,
    output wire [16:0]        m_i_mag,
    output wire [15:0]        m_u_pct_x100,
    output wire [15:0]        m_i_pct_x100,
    output wire               m_phase_vector_valid,
    output wire signed [32:0] m_phase_dot,
    output wire signed [32:0] m_phase_cross,
    output wire               m_phase_diff_valid,
    output wire signed [15:0] m_phase_diff_deg_x100,
    output wire               phase_deg_busy,
    output wire               phase_deg_frame_done,
    output reg  [15:0]        phase_deg_frame_count
);

localparam [2:0] ST_IDLE     = 3'd0;
localparam [2:0] ST_DIV_REQ  = 3'd1;
localparam [2:0] ST_DIV_WAIT = 3'd2;
localparam [2:0] ST_ROM_REQ  = 3'd3;
localparam [2:0] ST_ROM_WAIT = 3'd4;
localparam [2:0] ST_OUTPUT   = 3'd5;

localparam signed [15:0] PHASE_180_X100 = 16'sd18000;

reg [2:0]          state;
reg                m_harmonic_valid_reg;
reg                m_harmonic_last_reg;
reg [8:0]          m_harmonic_order_reg;
reg                m_harmonic_present_reg;
reg signed [15:0]  m_u_real_reg;
reg signed [15:0]  m_u_imag_reg;
reg signed [15:0]  m_i_real_reg;
reg signed [15:0]  m_i_imag_reg;
reg [16:0]         m_u_mag_reg;
reg [16:0]         m_i_mag_reg;
reg [15:0]         m_u_pct_x100_reg;
reg [15:0]         m_i_pct_x100_reg;
reg                m_phase_vector_valid_reg;
reg signed [32:0]  m_phase_dot_reg;
reg signed [32:0]  m_phase_cross_reg;
reg                m_phase_diff_valid_reg;
reg signed [15:0]  m_phase_diff_deg_x100_reg;
reg                phase_deg_frame_done_reg;
reg                dot_negative_reg;
reg                cross_negative_reg;
reg [43:0]         div_dividend_reg;
reg [43:0]         div_divisor_reg;
reg [10:0]         rom_addr_reg;

wire               input_fire;
wire               output_fire;
wire               div_start;
wire               div_busy;
wire               div_done;
wire               div_zero;
wire [43:0]        div_quotient;
wire               rom_en;
wire [13:0]        rom_angle_deg_x100;
wire [32:0]        abs_dot_next;
wire [32:0]        abs_cross_next;
wire [33:0]        denominator_next;
wire [43:0]        dividend_next;
wire [43:0]        divisor_next;
wire               phase_input_valid;
wire signed [15:0] angle_0_90_signed;
wire signed [15:0] phase_deg_next;
wire [10:0]        quotient_addr;

// 组合生成上游、下游握手以及除法器和 ROM 的启动条件。
assign s_harmonic_ready = enable && (state == ST_IDLE);
assign input_fire       = s_harmonic_valid && s_harmonic_ready;
assign output_fire      = m_harmonic_valid_reg && m_harmonic_ready;
assign div_start        = (state == ST_DIV_REQ);
assign rom_en           = (state == ST_ROM_REQ);
assign phase_deg_busy   = (state != ST_IDLE) || m_harmonic_valid_reg;

// 组合计算 dot/cross 的绝对值和 ROM 地址除法的被除数、除数。
assign abs_dot_next =
    s_phase_dot[32] ? ((~s_phase_dot[32:0]) + 33'd1) : s_phase_dot[32:0];
assign abs_cross_next =
    s_phase_cross[32] ? ((~s_phase_cross[32:0]) + 33'd1) : s_phase_cross[32:0];
assign denominator_next = {1'b0, abs_dot_next} + {1'b0, abs_cross_next};
assign dividend_next    = {1'b0, abs_cross_next, 10'd0};
assign divisor_next     = {10'd0, denominator_next};
assign phase_input_valid = s_phase_vector_valid && (denominator_next != 34'd0);

// 组合完成 ROM 输出角度的象限修正，得到 -180.00 到 +180.00 度范围的 x100 结果。
assign angle_0_90_signed = {2'b00, rom_angle_deg_x100};
assign phase_deg_next =
    !m_phase_diff_valid_reg ? 16'sd0 :
    (!dot_negative_reg && !cross_negative_reg) ? angle_0_90_signed :
    (!dot_negative_reg &&  cross_negative_reg) ? -angle_0_90_signed :
    ( dot_negative_reg && !cross_negative_reg) ? (PHASE_180_X100 - angle_0_90_signed) :
                                                  (-PHASE_180_X100 + angle_0_90_signed);
assign quotient_addr =
    (div_quotient[43:11] != 33'd0) ? 11'd1024 : div_quotient[10:0];

// 对外导出带最终相位角的谐波结果流。
assign m_harmonic_valid      = m_harmonic_valid_reg;
assign m_harmonic_last       = m_harmonic_last_reg;
assign m_harmonic_order      = m_harmonic_order_reg;
assign m_harmonic_present    = m_harmonic_present_reg;
assign m_u_real              = m_u_real_reg;
assign m_u_imag              = m_u_imag_reg;
assign m_i_real              = m_i_real_reg;
assign m_i_imag              = m_i_imag_reg;
assign m_u_mag               = m_u_mag_reg;
assign m_i_mag               = m_i_mag_reg;
assign m_u_pct_x100          = m_u_pct_x100_reg;
assign m_i_pct_x100          = m_i_pct_x100_reg;
assign m_phase_vector_valid  = m_phase_vector_valid_reg;
assign m_phase_dot           = m_phase_dot_reg;
assign m_phase_cross         = m_phase_cross_reg;
assign m_phase_diff_valid    = m_phase_diff_valid_reg;
assign m_phase_diff_deg_x100 = m_phase_diff_deg_x100_reg;
assign phase_deg_frame_done  = phase_deg_frame_done_reg;

// 实例化无符号除法器，计算 atan ROM 地址 abs_cross * 1024 / (abs_dot + abs_cross)。
divider_unsigned #(
    .WIDTH(44)
) u_phase_addr_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (div_start),
    .dividend      (div_dividend_reg),
    .divisor       (div_divisor_reg),
    .busy          (div_busy),
    .done          (div_done),
    .divide_by_zero(div_zero),
    .quotient      (div_quotient)
);

// 实例化 atan 查表 ROM，输入地址 0~1024，输出第一象限角度 deg_x100。
rom_atan_lut_1024 u_rom_atan_lut_1024 (
    .clka (clk),
    .ena  (rom_en),
    .addra(rom_addr_reg),
    .douta(rom_angle_deg_x100)
);

// 在频域时钟域完成地址计算、ROM 查表、象限修正和结果输出对齐。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state                     <= ST_IDLE;
        m_harmonic_valid_reg      <= 1'b0;
        m_harmonic_last_reg       <= 1'b0;
        m_harmonic_order_reg      <= 9'd0;
        m_harmonic_present_reg    <= 1'b0;
        m_u_real_reg              <= 16'sd0;
        m_u_imag_reg              <= 16'sd0;
        m_i_real_reg              <= 16'sd0;
        m_i_imag_reg              <= 16'sd0;
        m_u_mag_reg               <= 17'd0;
        m_i_mag_reg               <= 17'd0;
        m_u_pct_x100_reg          <= 16'd0;
        m_i_pct_x100_reg          <= 16'd0;
        m_phase_vector_valid_reg  <= 1'b0;
        m_phase_dot_reg           <= 33'sd0;
        m_phase_cross_reg         <= 33'sd0;
        m_phase_diff_valid_reg    <= 1'b0;
        m_phase_diff_deg_x100_reg <= 16'sd0;
        phase_deg_frame_done_reg  <= 1'b0;
        phase_deg_frame_count     <= 16'd0;
        dot_negative_reg          <= 1'b0;
        cross_negative_reg        <= 1'b0;
        div_dividend_reg          <= 44'd0;
        div_divisor_reg           <= 44'd0;
        rom_addr_reg              <= 11'd0;
    end else begin
        phase_deg_frame_done_reg <= 1'b0;

        if (!enable) begin
            state                     <= ST_IDLE;
            m_harmonic_valid_reg      <= 1'b0;
            m_harmonic_last_reg       <= 1'b0;
            m_phase_vector_valid_reg  <= 1'b0;
            m_phase_diff_valid_reg    <= 1'b0;
            m_phase_diff_deg_x100_reg <= 16'sd0;
        end else begin
            case (state)
                ST_IDLE: begin
                    if (input_fire) begin
                        m_harmonic_last_reg      <= s_harmonic_last;
                        m_harmonic_order_reg     <= s_harmonic_order;
                        m_harmonic_present_reg   <= s_harmonic_present;
                        m_u_real_reg             <= s_u_real;
                        m_u_imag_reg             <= s_u_imag;
                        m_i_real_reg             <= s_i_real;
                        m_i_imag_reg             <= s_i_imag;
                        m_u_mag_reg              <= s_u_mag;
                        m_i_mag_reg              <= s_i_mag;
                        m_u_pct_x100_reg         <= s_u_pct_x100;
                        m_i_pct_x100_reg         <= s_i_pct_x100;
                        m_phase_vector_valid_reg <= s_phase_vector_valid;
                        m_phase_dot_reg          <= s_phase_dot;
                        m_phase_cross_reg        <= s_phase_cross;
                        m_phase_diff_valid_reg   <= phase_input_valid;
                        dot_negative_reg         <= s_phase_dot[32];
                        cross_negative_reg       <= s_phase_cross[32];
                        div_dividend_reg         <= dividend_next;
                        div_divisor_reg          <= divisor_next;

                        if (phase_input_valid)
                            state <= ST_DIV_REQ;
                        else begin
                            m_harmonic_valid_reg      <= 1'b1;
                            m_phase_diff_deg_x100_reg <= 16'sd0;
                            state                     <= ST_OUTPUT;
                        end
                    end
                end

                ST_DIV_REQ: begin
                    state <= ST_DIV_WAIT;
                end

                ST_DIV_WAIT: begin
                    if (div_done) begin
                        if (div_zero) begin
                            m_harmonic_valid_reg      <= 1'b1;
                            m_phase_diff_valid_reg    <= 1'b0;
                            m_phase_diff_deg_x100_reg <= 16'sd0;
                            state                     <= ST_OUTPUT;
                        end else begin
                            rom_addr_reg <= quotient_addr;
                            state        <= ST_ROM_REQ;
                        end
                    end
                end

                ST_ROM_REQ: begin
                    state <= ST_ROM_WAIT;
                end

                ST_ROM_WAIT: begin
                    m_harmonic_valid_reg      <= 1'b1;
                    m_phase_diff_deg_x100_reg <= phase_deg_next;
                    state                     <= ST_OUTPUT;
                end

                ST_OUTPUT: begin
                    if (output_fire) begin
                        m_harmonic_valid_reg <= 1'b0;

                        if (m_harmonic_last_reg) begin
                            phase_deg_frame_done_reg <= 1'b1;
                            phase_deg_frame_count    <= phase_deg_frame_count + 16'd1;
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
