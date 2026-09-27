`timescale 1ns / 1ps

/*
 * 模块: phase_vector_calc
 * 功能:
 *   接收 0~500 次谐波统计结果，计算 U-I 相位差的 atan2 输入向量。
 *   输出 dot/cross，其中 U-I 相位差等于 atan2(cross, dot)。
 *
 * 输入:
 *   clk: 频域相位向量计算时钟，通常接频域工作时钟。
 *   rst_n: 低有效复位信号。
 *   enable: 相位向量计算使能，拉低时清空待输出结果。
 *   s_harmonic_valid: 上游谐波统计结果有效标志。
 *   s_harmonic_last: 0~500 次谐波统计结果的最后一项标志。
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
 *   m_harmonic_ready: 下游带相位向量的谐波结果接收就绪标志。
 *
 * 输出:
 *   s_harmonic_ready: 本模块对上游谐波统计结果的接收就绪标志。
 *   m_harmonic_valid: 带相位向量的谐波结果有效标志。
 *   m_harmonic_last: 带相位向量结果的最后一项标志。
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
 *   m_phase_vector_valid: 当前 dot/cross 是否可用于 atan2 相位差计算。
 *   m_phase_dot: U 与 I 的同相投影，等于 Ur*Ir + Ui*Ii。
 *   m_phase_cross: U 与 I 的正交投影，等于 Ui*Ir - Ur*Ii。
 */
module phase_vector_calc (
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
    output wire signed [32:0] m_phase_cross
);

wire signed [31:0] ur_ir_product;
wire signed [31:0] ui_ii_product;
wire signed [31:0] ui_ir_product;
wire signed [31:0] ur_ii_product;
wire signed [32:0] phase_dot_next;
wire signed [32:0] phase_cross_next;
wire               input_fire;
wire               output_fire;
wire               output_can_accept;
wire               phase_vector_valid_next;

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

// 组合生成 ready/valid 握手，保证 dot/cross 与谐波统计结果同拍对齐。
assign output_can_accept = !m_harmonic_valid_reg || m_harmonic_ready;
assign s_harmonic_ready  = !enable || output_can_accept;
assign input_fire        = s_harmonic_valid && s_harmonic_ready && enable;
assign output_fire       = m_harmonic_valid_reg && m_harmonic_ready;

// 组合生成 U-I 相位差的 atan2 输入向量，乘法项由 BasicMath 乘法器完成。
assign phase_dot_next =
    {ur_ir_product[31], ur_ir_product} + {ui_ii_product[31], ui_ii_product};
assign phase_cross_next =
    {ui_ir_product[31], ui_ir_product} - {ur_ii_product[31], ur_ii_product};
assign phase_vector_valid_next =
    s_harmonic_present && (s_u_mag != 17'd0) && (s_i_mag != 17'd0);

// 对外导出带相位向量的谐波结果流。
assign m_harmonic_valid    = m_harmonic_valid_reg;
assign m_harmonic_last     = m_harmonic_last_reg;
assign m_harmonic_order    = m_harmonic_order_reg;
assign m_harmonic_present  = m_harmonic_present_reg;
assign m_u_real            = m_u_real_reg;
assign m_u_imag            = m_u_imag_reg;
assign m_i_real            = m_i_real_reg;
assign m_i_imag            = m_i_imag_reg;
assign m_u_mag             = m_u_mag_reg;
assign m_i_mag             = m_i_mag_reg;
assign m_u_pct_x100        = m_u_pct_x100_reg;
assign m_i_pct_x100        = m_i_pct_x100_reg;
assign m_phase_vector_valid = m_phase_vector_valid_reg;
assign m_phase_dot         = m_phase_dot_reg;
assign m_phase_cross       = m_phase_cross_reg;

// 实例化 Ur*Ir 乘法器，生成同相投影的第一项。
multiplier_signed #(
    .A_WIDTH(16),
    .B_WIDTH(16)
) u_mul_ur_ir (
    .multiplicand(s_u_real),
    .multiplier  (s_i_real),
    .product     (ur_ir_product)
);

// 实例化 Ui*Ii 乘法器，生成同相投影的第二项。
multiplier_signed #(
    .A_WIDTH(16),
    .B_WIDTH(16)
) u_mul_ui_ii (
    .multiplicand(s_u_imag),
    .multiplier  (s_i_imag),
    .product     (ui_ii_product)
);

// 实例化 Ui*Ir 乘法器，生成正交投影的第一项。
multiplier_signed #(
    .A_WIDTH(16),
    .B_WIDTH(16)
) u_mul_ui_ir (
    .multiplicand(s_u_imag),
    .multiplier  (s_i_real),
    .product     (ui_ir_product)
);

// 实例化 Ur*Ii 乘法器，生成正交投影的第二项。
multiplier_signed #(
    .A_WIDTH(16),
    .B_WIDTH(16)
) u_mul_ur_ii (
    .multiplicand(s_u_real),
    .multiplier  (s_i_imag),
    .product     (ur_ii_product)
);

// 在频域时钟域锁存谐波统计结果和相位向量，供后续 atan2/CORDIC 模块使用。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
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
    end else begin
        if (!enable) begin
            m_harmonic_valid_reg     <= 1'b0;
            m_harmonic_last_reg      <= 1'b0;
            m_phase_vector_valid_reg <= 1'b0;
        end else if (input_fire) begin
            m_harmonic_valid_reg     <= 1'b1;
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
            m_phase_vector_valid_reg <= phase_vector_valid_next;
            m_phase_dot_reg          <= phase_dot_next;
            m_phase_cross_reg        <= phase_cross_next;
        end else if (output_fire) begin
            m_harmonic_valid_reg     <= 1'b0;
            m_harmonic_last_reg      <= 1'b0;
            m_phase_vector_valid_reg <= 1'b0;
        end
    end
end

endmodule
