`timescale 1ns / 1ps

/*
 * 模块: fft_harmonic_stats
 * 功能:
 *   接收一帧正半谱 FFT 幅值结果，统计 0~500 次谐波的 U/I 幅值及其占总幅值百分比。
 *   本模块同时保留每次谐波的 real/imag，供后续 U-I 相位差计算模块使用。
 *
 * 输入:
 *   clk: 频域统计时钟，通常接 fft_clk。
 *   rst_n: 低有效复位信号。
 *   enable: 谐波统计使能，拉低时停止接收并清空输出状态。
 *   s_mag_valid: 上游幅值结果有效标志。
 *   s_mag_last: 上游正半谱幅值结果帧尾标志。
 *   s_bin_index: 上游幅值结果对应的 FFT bin。
 *   s_u_real: 与幅值结果对齐的电压通道频点实部。
 *   s_u_imag: 与幅值结果对齐的电压通道频点虚部。
 *   s_i_real: 与幅值结果对齐的电流通道频点实部。
 *   s_i_imag: 与幅值结果对齐的电流通道频点虚部。
 *   s_u_mag: 电压通道当前频点幅值。
 *   s_i_mag: 电流通道当前频点幅值。
 *   m_harmonic_ready: 下游谐波结果接收就绪标志。
 *
 * 输出:
 *   s_mag_ready: 本模块对上游幅值结果流的接收就绪标志。
 *   m_harmonic_valid: 谐波统计结果有效标志。
 *   m_harmonic_last: 0~500 次谐波统计结果的最后一项标志。
 *   m_harmonic_order: 当前输出的谐波次数。
 *   m_harmonic_present: 当前谐波在本帧中是否被捕获。
 *   m_u_real: 当前谐波电压通道实部。
 *   m_u_imag: 当前谐波电压通道虚部。
 *   m_i_real: 当前谐波电流通道实部。
 *   m_i_imag: 当前谐波电流通道虚部。
 *   m_u_mag: 当前谐波电压通道幅值。
 *   m_i_mag: 当前谐波电流通道幅值。
 *   m_u_pct_x100: 当前谐波电压幅值占本帧电压总幅值的百分比，100.00% 表示为 10000。
 *   m_i_pct_x100: 当前谐波电流幅值占本帧电流总幅值的百分比，100.00% 表示为 10000。
 *   stats_busy: 当前正在接收、归一化或输出一帧谐波统计结果。
 *   capture_frame_done: 已捕获一帧上游幅值结果的单周期脉冲。
 *   harmonic_frame_done: 0~500 次谐波统计结果已输出完毕的单周期脉冲。
 *   harmonic_frame_count: 已输出完成的谐波统计帧计数。
 *   u_total_mag: 本帧 0~500 次谐波的电压幅值总和。
 *   i_total_mag: 本帧 0~500 次谐波的电流幅值总和。
 */
module fft_harmonic_stats #(
    parameter [10:0] FUND_BIN = 11'd1
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               enable,
    input  wire               s_mag_valid,
    output wire               s_mag_ready,
    input  wire               s_mag_last,
    input  wire [10:0]        s_bin_index,
    input  wire signed [15:0] s_u_real,
    input  wire signed [15:0] s_u_imag,
    input  wire signed [15:0] s_i_real,
    input  wire signed [15:0] s_i_imag,
    input  wire [16:0]        s_u_mag,
    input  wire [16:0]        s_i_mag,
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
    output wire               stats_busy,
    output wire               capture_frame_done,
    output wire               harmonic_frame_done,
    output reg  [15:0]        harmonic_frame_count,
    output reg  [31:0]        u_total_mag,
    output reg  [31:0]        i_total_mag
);

localparam [2:0] ST_IDLE     = 3'd0;
localparam [2:0] ST_CAPTURE  = 3'd1;
localparam [2:0] ST_LOAD     = 3'd2;
localparam [2:0] ST_DIVIDE   = 3'd3;
localparam [2:0] ST_OUTPUT   = 3'd4;
localparam [8:0] MAX_ORDER   = 9'd500;
localparam [10:0] MAX_BIN_FUND1 = 11'd500;
localparam [10:0] MAX_BIN_FUND2 = 11'd1000;
localparam signed [15:0] PERCENT_SCALE = 16'sd10000;

reg [2:0]         state;
reg               frame_tag;
reg [8:0]         output_order;
reg               capture_frame_done_reg;
reg               harmonic_frame_done_reg;
reg               m_harmonic_valid_reg;
reg               m_harmonic_last_reg;
reg [8:0]         m_harmonic_order_reg;
reg               m_harmonic_present_reg;
reg signed [15:0] m_u_real_reg;
reg signed [15:0] m_u_imag_reg;
reg signed [15:0] m_i_real_reg;
reg signed [15:0] m_i_imag_reg;
reg [16:0]        m_u_mag_reg;
reg [16:0]        m_i_mag_reg;
reg [15:0]        m_u_pct_x100_reg;
reg [15:0]        m_i_pct_x100_reg;
reg               u_div_start_reg;
reg               i_div_start_reg;
reg               u_pct_bypass_reg;
reg               i_pct_bypass_reg;

reg [16:0]        u_mag_mem [0:500];
reg [16:0]        i_mag_mem [0:500];
reg signed [15:0] u_real_mem [0:500];
reg signed [15:0] u_imag_mem [0:500];
reg signed [15:0] i_real_mem [0:500];
reg signed [15:0] i_imag_mem [0:500];
reg               tag_mem [0:500];

integer init_idx;

wire              input_fire;
wire              output_fire;
wire              target_fund1;
wire              target_fund2;
wire              target_harmonic;
wire [8:0]        target_order;
wire              current_present;
wire signed [16:0] u_mag_mul_value;
wire signed [16:0] i_mag_mul_value;
wire signed [32:0] u_pct_product;
wire signed [32:0] i_pct_product;
wire [32:0]       u_pct_dividend;
wire [32:0]       i_pct_dividend;
wire [32:0]       u_pct_divisor;
wire [32:0]       i_pct_divisor;
wire              u_div_busy;
wire              i_div_busy;
wire              u_div_done;
wire              i_div_done;
wire              u_div_zero;
wire              i_div_zero;
wire [32:0]       u_div_quotient;
wire [32:0]       i_div_quotient;
wire              divide_done;

// 组合识别当前 bin 是否为目标谐波；当前只支持基波位于 bin 1 或 bin 2 的 0~500 次统计。
assign target_fund1 =
    (FUND_BIN == 11'd1) && (s_bin_index <= MAX_BIN_FUND1);
assign target_fund2 =
    (FUND_BIN == 11'd2) && (s_bin_index <= MAX_BIN_FUND2) && (s_bin_index[0] == 1'b0);
assign target_harmonic = target_fund1 || target_fund2;
assign target_order    = target_fund1 ? s_bin_index[8:0] : s_bin_index[9:1];

// 组合生成上游和下游握手状态。
assign s_mag_ready = (state == ST_CAPTURE);
assign input_fire  = s_mag_valid && s_mag_ready;
assign output_fire = m_harmonic_valid_reg && m_harmonic_ready;
assign stats_busy  = (state != ST_IDLE) || m_harmonic_valid_reg;

// 组合读取当前输出次数是否在本帧中被捕获。
assign current_present = (tag_mem[output_order] == frame_tag);

// 组合生成百分比计算的乘法器输入，乘法器输出再送入无符号除法器。
assign u_mag_mul_value = m_u_mag_reg;
assign i_mag_mul_value = m_i_mag_reg;
assign u_pct_dividend  = u_pct_product[32:0];
assign i_pct_dividend  = i_pct_product[32:0];
assign u_pct_divisor   = {1'b0, u_total_mag};
assign i_pct_divisor   = {1'b0, i_total_mag};
assign divide_done =
    (u_pct_bypass_reg || u_div_done) && (i_pct_bypass_reg || i_div_done);

// 对外导出谐波统计结果流。
assign m_harmonic_valid   = m_harmonic_valid_reg;
assign m_harmonic_last    = m_harmonic_last_reg;
assign m_harmonic_order   = m_harmonic_order_reg;
assign m_harmonic_present = m_harmonic_present_reg;
assign m_u_real           = m_u_real_reg;
assign m_u_imag           = m_u_imag_reg;
assign m_i_real           = m_i_real_reg;
assign m_i_imag           = m_i_imag_reg;
assign m_u_mag            = m_u_mag_reg;
assign m_i_mag            = m_i_mag_reg;
assign m_u_pct_x100       = m_u_pct_x100_reg;
assign m_i_pct_x100       = m_i_pct_x100_reg;
assign capture_frame_done = capture_frame_done_reg;
assign harmonic_frame_done = harmonic_frame_done_reg;

// 实例化电压幅值百分比乘法器，计算 mag * 10000 的被除数。
multiplier_signed #(
    .A_WIDTH(17),
    .B_WIDTH(16)
) u_mul_u_percent (
    .multiplicand(u_mag_mul_value),
    .multiplier  (PERCENT_SCALE),
    .product     (u_pct_product)
);

// 实例化电流幅值百分比乘法器，计算 mag * 10000 的被除数。
multiplier_signed #(
    .A_WIDTH(17),
    .B_WIDTH(16)
) u_mul_i_percent (
    .multiplicand(i_mag_mul_value),
    .multiplier  (PERCENT_SCALE),
    .product     (i_pct_product)
);

// 实例化电压幅值百分比除法器，计算当前谐波占电压总幅值的 x100 百分比。
divider_unsigned #(
    .WIDTH(33)
) u_div_u_percent (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (u_div_start_reg),
    .dividend      (u_pct_dividend),
    .divisor       (u_pct_divisor),
    .busy          (u_div_busy),
    .done          (u_div_done),
    .divide_by_zero(u_div_zero),
    .quotient      (u_div_quotient)
);

// 实例化电流幅值百分比除法器，计算当前谐波占电流总幅值的 x100 百分比。
divider_unsigned #(
    .WIDTH(33)
) u_div_i_percent (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (i_div_start_reg),
    .dividend      (i_pct_dividend),
    .divisor       (i_pct_divisor),
    .busy          (i_div_busy),
    .done          (i_div_done),
    .divide_by_zero(i_div_zero),
    .quotient      (i_div_quotient)
);

// 在频域统计时钟域完成一帧幅值捕获、百分比归一化和逐项输出。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state                   <= ST_IDLE;
        frame_tag               <= 1'b0;
        output_order            <= 9'd0;
        capture_frame_done_reg  <= 1'b0;
        harmonic_frame_done_reg <= 1'b0;
        m_harmonic_valid_reg    <= 1'b0;
        m_harmonic_last_reg     <= 1'b0;
        m_harmonic_order_reg    <= 9'd0;
        m_harmonic_present_reg  <= 1'b0;
        m_u_real_reg            <= 16'sd0;
        m_u_imag_reg            <= 16'sd0;
        m_i_real_reg            <= 16'sd0;
        m_i_imag_reg            <= 16'sd0;
        m_u_mag_reg             <= 17'd0;
        m_i_mag_reg             <= 17'd0;
        m_u_pct_x100_reg        <= 16'd0;
        m_i_pct_x100_reg        <= 16'd0;
        u_div_start_reg         <= 1'b0;
        i_div_start_reg         <= 1'b0;
        u_pct_bypass_reg        <= 1'b0;
        i_pct_bypass_reg        <= 1'b0;
        harmonic_frame_count    <= 16'd0;
        u_total_mag             <= 32'd0;
        i_total_mag             <= 32'd0;

        for (init_idx = 0; init_idx <= 500; init_idx = init_idx + 1) begin
            u_mag_mem[init_idx]  <= 17'd0;
            i_mag_mem[init_idx]  <= 17'd0;
            u_real_mem[init_idx] <= 16'sd0;
            u_imag_mem[init_idx] <= 16'sd0;
            i_real_mem[init_idx] <= 16'sd0;
            i_imag_mem[init_idx] <= 16'sd0;
            tag_mem[init_idx]    <= 1'b0;
        end
    end else begin
        capture_frame_done_reg  <= 1'b0;
        harmonic_frame_done_reg <= 1'b0;
        u_div_start_reg         <= 1'b0;
        i_div_start_reg         <= 1'b0;

        if (!enable) begin
            state                <= ST_IDLE;
            m_harmonic_valid_reg <= 1'b0;
            m_harmonic_last_reg  <= 1'b0;
            output_order         <= 9'd0;
            u_total_mag          <= 32'd0;
            i_total_mag          <= 32'd0;
        end else begin
            case (state)
                ST_IDLE: begin
                    frame_tag            <= !frame_tag;
                    output_order         <= 9'd0;
                    u_total_mag          <= 32'd0;
                    i_total_mag          <= 32'd0;
                    m_harmonic_valid_reg <= 1'b0;
                    m_harmonic_last_reg  <= 1'b0;
                    state                <= ST_CAPTURE;
                end

                ST_CAPTURE: begin
                    if (input_fire) begin
                        if (target_harmonic) begin
                            u_mag_mem[target_order]  <= s_u_mag;
                            i_mag_mem[target_order]  <= s_i_mag;
                            u_real_mem[target_order] <= s_u_real;
                            u_imag_mem[target_order] <= s_u_imag;
                            i_real_mem[target_order] <= s_i_real;
                            i_imag_mem[target_order] <= s_i_imag;
                            tag_mem[target_order]    <= frame_tag;
                            u_total_mag <= u_total_mag + {15'd0, s_u_mag};
                            i_total_mag <= i_total_mag + {15'd0, s_i_mag};
                        end

                        if (s_mag_last) begin
                            capture_frame_done_reg <= 1'b1;
                            output_order           <= 9'd0;
                            state                  <= ST_LOAD;
                        end
                    end
                end

                ST_LOAD: begin
                    m_harmonic_order_reg   <= output_order;
                    m_harmonic_last_reg    <= (output_order == MAX_ORDER);
                    m_harmonic_present_reg <= current_present;

                    if (current_present) begin
                        m_u_real_reg <= u_real_mem[output_order];
                        m_u_imag_reg <= u_imag_mem[output_order];
                        m_i_real_reg <= i_real_mem[output_order];
                        m_i_imag_reg <= i_imag_mem[output_order];
                        m_u_mag_reg  <= u_mag_mem[output_order];
                        m_i_mag_reg  <= i_mag_mem[output_order];
                    end else begin
                        m_u_real_reg <= 16'sd0;
                        m_u_imag_reg <= 16'sd0;
                        m_i_real_reg <= 16'sd0;
                        m_i_imag_reg <= 16'sd0;
                        m_u_mag_reg  <= 17'd0;
                        m_i_mag_reg  <= 17'd0;
                    end

                    m_u_pct_x100_reg <= 16'd0;
                    m_i_pct_x100_reg <= 16'd0;
                    state            <= ST_DIVIDE;
                end

                ST_DIVIDE: begin
                    u_pct_bypass_reg <= !m_harmonic_present_reg || (u_total_mag == 32'd0) || (m_u_mag_reg == 17'd0);
                    i_pct_bypass_reg <= !m_harmonic_present_reg || (i_total_mag == 32'd0) || (m_i_mag_reg == 17'd0);
                    u_div_start_reg  <= m_harmonic_present_reg && (u_total_mag != 32'd0) && (m_u_mag_reg != 17'd0);
                    i_div_start_reg  <= m_harmonic_present_reg && (i_total_mag != 32'd0) && (m_i_mag_reg != 17'd0);
                    state            <= ST_OUTPUT;
                end

                ST_OUTPUT: begin
                    if (!m_harmonic_valid_reg && divide_done) begin
                        if (u_pct_bypass_reg || u_div_zero)
                            m_u_pct_x100_reg <= 16'd0;
                        else
                            m_u_pct_x100_reg <= u_div_quotient[15:0];

                        if (i_pct_bypass_reg || i_div_zero)
                            m_i_pct_x100_reg <= 16'd0;
                        else
                            m_i_pct_x100_reg <= i_div_quotient[15:0];

                        m_harmonic_valid_reg <= 1'b1;
                    end else if (output_fire) begin
                        m_harmonic_valid_reg <= 1'b0;

                        if (m_harmonic_last_reg) begin
                            harmonic_frame_done_reg <= 1'b1;
                            harmonic_frame_count    <= harmonic_frame_count + 16'd1;
                            state                   <= ST_IDLE;
                        end else begin
                            output_order <= output_order + 9'd1;
                            state        <= ST_LOAD;
                        end
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
