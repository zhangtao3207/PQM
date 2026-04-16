`timescale 1ns / 1ps

/*
 * 模块: fft_magnitude_calc
 * 功能:
 *   接收筛选后的 FFT 频点复数结果，计算电压和电流通道的幅值平方和幅值，
 *   并把同一频点的 real/imag 与幅值结果对齐透传。
 *   本模块只处理单个频点流，不做谐波选择、THD 累加、相位计算或显示格式转换。
 *
 * 输入:
 *   clk: 频域计算时钟，通常接 fft_clk。
 *   rst_n: 低有效复位信号。
 *   enable: 幅值计算使能，拉低时丢弃输入流并清空待输出结果。
 *   s_bin_valid: 上游频点结果有效标志。
 *   s_bin_last: 上游正半谱帧尾标志。
 *   s_bin_index: 上游频点索引。
 *   s_u_real: 电压通道频点实部。
 *   s_u_imag: 电压通道频点虚部。
 *   s_i_real: 电流通道频点实部。
 *   s_i_imag: 电流通道频点虚部。
 *   m_mag_ready: 下游幅值结果接收就绪标志。
 *
 * 输出:
 *   s_bin_ready: 本模块对上游频点流的接收就绪标志。
 *   m_mag_valid: 幅值结果有效标志。
 *   m_mag_last: 正半谱幅值结果帧尾标志。
 *   m_bin_index: 幅值结果对应的频点索引。
 *   m_u_real: 与幅值结果对齐的电压通道频点实部。
 *   m_u_imag: 与幅值结果对齐的电压通道频点虚部。
 *   m_i_real: 与幅值结果对齐的电流通道频点实部。
 *   m_i_imag: 与幅值结果对齐的电流通道频点虚部。
 *   m_u_mag_sq: 电压通道幅值平方和，等于 real^2 + imag^2。
 *   m_u_mag: 电压通道幅值，等于 sqrt(real^2 + imag^2)。
 *   m_i_mag_sq: 电流通道幅值平方和，等于 real^2 + imag^2。
 *   m_i_mag: 电流通道幅值，等于 sqrt(real^2 + imag^2)。
 *   calc_busy: 当前存在正在计算或等待下游接收的幅值结果。
 *   mag_frame_done: 一帧正半谱幅值结果已被下游取完的单周期脉冲。
 *   mag_frame_count: 已完整输出的正半谱幅值帧计数。
 */
module fft_magnitude_calc (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               enable,
    input  wire               s_bin_valid,
    output wire               s_bin_ready,
    input  wire               s_bin_last,
    input  wire [10:0]        s_bin_index,
    input  wire signed [15:0] s_u_real,
    input  wire signed [15:0] s_u_imag,
    input  wire signed [15:0] s_i_real,
    input  wire signed [15:0] s_i_imag,
    input  wire               m_mag_ready,
    output wire               m_mag_valid,
    output wire               m_mag_last,
    output wire [10:0]        m_bin_index,
    output wire signed [15:0] m_u_real,
    output wire signed [15:0] m_u_imag,
    output wire signed [15:0] m_i_real,
    output wire signed [15:0] m_i_imag,
    output wire [32:0]        m_u_mag_sq,
    output wire [16:0]        m_u_mag,
    output wire [32:0]        m_i_mag_sq,
    output wire [16:0]        m_i_mag,
    output wire               calc_busy,
    output wire               mag_frame_done,
    output reg  [15:0]        mag_frame_count
);

wire signed [31:0] u_real_sq_product;
wire signed [31:0] u_imag_sq_product;
wire signed [31:0] i_real_sq_product;
wire signed [31:0] i_imag_sq_product;
wire [32:0]        u_mag_sq_next;
wire [32:0]        i_mag_sq_next;
wire               output_can_accept;
wire               input_fire;
wire               output_fire;
wire               sqrt_start;
wire               u_sqrt_busy;
wire               i_sqrt_busy;
wire               u_sqrt_done;
wire               i_sqrt_done;
wire [16:0]        u_sqrt_root;
wire [16:0]        i_sqrt_root;
wire               calc_done;

reg                calc_active;
reg [10:0]         calc_bin_index_reg;
reg                calc_bin_last_reg;
reg signed [15:0]  calc_u_real_reg;
reg signed [15:0]  calc_u_imag_reg;
reg signed [15:0]  calc_i_real_reg;
reg signed [15:0]  calc_i_imag_reg;
reg [32:0]         calc_u_mag_sq_reg;
reg [32:0]         calc_i_mag_sq_reg;
reg                m_mag_valid_reg;
reg                m_mag_last_reg;
reg [10:0]         m_bin_index_reg;
reg signed [15:0]  m_u_real_reg;
reg signed [15:0]  m_u_imag_reg;
reg signed [15:0]  m_i_real_reg;
reg signed [15:0]  m_i_imag_reg;
reg [32:0]         m_u_mag_sq_reg;
reg [16:0]         m_u_mag_reg;
reg [32:0]         m_i_mag_sq_reg;
reg [16:0]         m_i_mag_reg;
reg                mag_frame_done_reg;

// 组合生成输入接收条件和输出握手，禁用时保持 ready 以便丢弃上游频点流。
assign output_can_accept = !m_mag_valid_reg || m_mag_ready;
assign s_bin_ready =
    !enable || (!calc_active && !u_sqrt_busy && !i_sqrt_busy && output_can_accept);
assign input_fire  = s_bin_valid && s_bin_ready && enable;
assign output_fire = m_mag_valid_reg && m_mag_ready;
assign sqrt_start  = input_fire;
assign calc_done   = calc_active && u_sqrt_done && i_sqrt_done;

// 组合生成两路通道的幅值平方和，平方运算由 BasicMath 乘法器完成。
assign u_mag_sq_next = {1'b0, u_real_sq_product[31:0]} + {1'b0, u_imag_sq_product[31:0]};
assign i_mag_sq_next = {1'b0, i_real_sq_product[31:0]} + {1'b0, i_imag_sq_product[31:0]};

// 对外导出幅值结果流和模块忙状态。
assign m_mag_valid    = m_mag_valid_reg;
assign m_mag_last     = m_mag_last_reg;
assign m_bin_index    = m_bin_index_reg;
assign m_u_real       = m_u_real_reg;
assign m_u_imag       = m_u_imag_reg;
assign m_i_real       = m_i_real_reg;
assign m_i_imag       = m_i_imag_reg;
assign m_u_mag_sq     = m_u_mag_sq_reg;
assign m_u_mag        = m_u_mag_reg;
assign m_i_mag_sq     = m_i_mag_sq_reg;
assign m_i_mag        = m_i_mag_reg;
assign calc_busy      = calc_active || u_sqrt_busy || i_sqrt_busy || m_mag_valid_reg;
assign mag_frame_done = mag_frame_done_reg;

// 实例化电压实部平方乘法器，避免在频域模块中直接写乘法表达式。
multiplier_signed #(
    .A_WIDTH(16),
    .B_WIDTH(16)
) u_mul_u_real_sq (
    .multiplicand(s_u_real),
    .multiplier  (s_u_real),
    .product     (u_real_sq_product)
);

// 实例化电压虚部平方乘法器，生成电压幅值平方和的一项。
multiplier_signed #(
    .A_WIDTH(16),
    .B_WIDTH(16)
) u_mul_u_imag_sq (
    .multiplicand(s_u_imag),
    .multiplier  (s_u_imag),
    .product     (u_imag_sq_product)
);

// 实例化电流实部平方乘法器，生成电流幅值平方和的一项。
multiplier_signed #(
    .A_WIDTH(16),
    .B_WIDTH(16)
) u_mul_i_real_sq (
    .multiplicand(s_i_real),
    .multiplier  (s_i_real),
    .product     (i_real_sq_product)
);

// 实例化电流虚部平方乘法器，生成电流幅值平方和的一项。
multiplier_signed #(
    .A_WIDTH(16),
    .B_WIDTH(16)
) u_mul_i_imag_sq (
    .multiplicand(s_i_imag),
    .multiplier  (s_i_imag),
    .product     (i_imag_sq_product)
);

// 实例化电压幅值开方器，把 real^2 + imag^2 转成幅值。
sqrt_unsigned #(
    .RADICAND_WIDTH(33),
    .ROOT_WIDTH    (17)
) u_sqrt_u_mag (
    .clk     (clk),
    .rst_n   (rst_n),
    .start   (sqrt_start),
    .radicand(u_mag_sq_next),
    .busy    (u_sqrt_busy),
    .done    (u_sqrt_done),
    .root    (u_sqrt_root)
);

// 实例化电流幅值开方器，把 real^2 + imag^2 转成幅值。
sqrt_unsigned #(
    .RADICAND_WIDTH(33),
    .ROOT_WIDTH    (17)
) u_sqrt_i_mag (
    .clk     (clk),
    .rst_n   (rst_n),
    .start   (sqrt_start),
    .radicand(i_mag_sq_next),
    .busy    (i_sqrt_busy),
    .done    (i_sqrt_done),
    .root    (i_sqrt_root)
);

// 在频域计算时钟域保存输入频点元信息，并在开方完成后输出幅值结果。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        calc_active       <= 1'b0;
        calc_bin_index_reg<= 11'd0;
        calc_bin_last_reg <= 1'b0;
        calc_u_real_reg   <= 16'sd0;
        calc_u_imag_reg   <= 16'sd0;
        calc_i_real_reg   <= 16'sd0;
        calc_i_imag_reg   <= 16'sd0;
        calc_u_mag_sq_reg <= 33'd0;
        calc_i_mag_sq_reg <= 33'd0;
        m_mag_valid_reg   <= 1'b0;
        m_mag_last_reg    <= 1'b0;
        m_bin_index_reg   <= 11'd0;
        m_u_real_reg      <= 16'sd0;
        m_u_imag_reg      <= 16'sd0;
        m_i_real_reg      <= 16'sd0;
        m_i_imag_reg      <= 16'sd0;
        m_u_mag_sq_reg    <= 33'd0;
        m_u_mag_reg       <= 17'd0;
        m_i_mag_sq_reg    <= 33'd0;
        m_i_mag_reg       <= 17'd0;
        mag_frame_done_reg<= 1'b0;
        mag_frame_count   <= 16'd0;
    end else begin
        mag_frame_done_reg <= 1'b0;

        if (!enable) begin
            calc_active       <= 1'b0;
            m_mag_valid_reg   <= 1'b0;
            m_mag_last_reg    <= 1'b0;
        end else begin
            if (output_fire) begin
                m_mag_valid_reg <= 1'b0;
                m_mag_last_reg  <= 1'b0;

                if (m_mag_last_reg) begin
                    mag_frame_done_reg <= 1'b1;
                    mag_frame_count    <= mag_frame_count + 16'd1;
                end
            end

            if (input_fire) begin
                calc_active        <= 1'b1;
                calc_bin_index_reg <= s_bin_index;
                calc_bin_last_reg  <= s_bin_last;
                calc_u_real_reg    <= s_u_real;
                calc_u_imag_reg    <= s_u_imag;
                calc_i_real_reg    <= s_i_real;
                calc_i_imag_reg    <= s_i_imag;
                calc_u_mag_sq_reg  <= u_mag_sq_next;
                calc_i_mag_sq_reg  <= i_mag_sq_next;
            end

            if (calc_done) begin
                calc_active     <= 1'b0;
                m_mag_valid_reg <= 1'b1;
                m_mag_last_reg  <= calc_bin_last_reg;
                m_bin_index_reg <= calc_bin_index_reg;
                m_u_real_reg    <= calc_u_real_reg;
                m_u_imag_reg    <= calc_u_imag_reg;
                m_i_real_reg    <= calc_i_real_reg;
                m_i_imag_reg    <= calc_i_imag_reg;
                m_u_mag_sq_reg  <= calc_u_mag_sq_reg;
                m_u_mag_reg     <= u_sqrt_root;
                m_i_mag_sq_reg  <= calc_i_mag_sq_reg;
                m_i_mag_reg     <= i_sqrt_root;
            end
        end
    end
end

endmodule
