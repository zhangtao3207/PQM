`timescale 1ns / 1ps

/*
 * 模块: freq_harmonic_iir_filter
 * 功能:
 *   对 0~500 次谐波流做一阶 IIR 平滑，输出作为后续频域显示和 raw 指标计算的唯一谐波接口。
 *   平滑系数为 1/16，通过右移实现，避免使用大规模滑动窗口。
 * 输入:
 *   clk: 频域分析工作时钟。
 *   rst_n: 低有效复位信号。
 *   enable: 滤波链路使能，拉低时停止接收并清空待输出状态。
 *   s_harmonic_valid: 上游谐波结果有效标志。
 *   s_harmonic_last: 当前输入是否为一帧谐波结果的最后一项。
 *   s_harmonic_order: 当前输入谐波次数。
 *   s_harmonic_present: 当前谐波在本帧中是否有效。
 *   s_u1_real: 当前谐波U1通道实部。
 *   s_u1_imag: 当前谐波U1通道虚部。
 *   s_u2_real: 当前谐波U2通道实部。
 *   s_u2_imag: 当前谐波U2通道虚部。
 *   s_u1_mag: 当前谐波U1幅值。
 *   s_u2_mag: 当前谐波U2幅值。
 *   s_u1_pct_x100: 当前谐波U1幅值占比，单位为百分比 x100。
 *   s_u2_pct_x100: 当前谐波U2幅值占比，单位为百分比 x100。
 *   s_phase_vector_valid: 当前 dot/cross 相位向量是否有效。
 *   s_phase_dot: 当前谐波 U1-U2 相位差 atan2 的同相投影。
 *   s_phase_cross: 当前谐波 U1-U2 相位差 atan2 的正交投影。
 *   s_phase_diff_valid: 当前相位差角度是否有效。
 *   s_phase_diff_deg_x100: 当前谐波 U1-U2 相位差角度，单位为度 x100。
 *   m_harmonic_ready: 下游接收滤波后谐波结果的 ready。
 * 输出:
 *   s_harmonic_ready: 本模块对上游谐波结果的 ready。
 *   m_harmonic_valid: 滤波后谐波结果有效标志。
 *   m_harmonic_last: 滤波后当前项是否为一帧最后一项。
 *   m_harmonic_order: 滤波后结果对应的谐波次数。
 *   m_harmonic_present: 滤波后结果是否有效。
 *   m_u1_real: 滤波后的U1通道实部。
 *   m_u1_imag: 滤波后的U1通道虚部。
 *   m_u2_real: 滤波后的U2通道实部。
 *   m_u2_imag: 滤波后的U2通道虚部。
 *   m_u1_mag: 滤波后的U1幅值。
 *   m_u2_mag: 滤波后的U2幅值。
 *   m_u1_pct_x100: 滤波后的U1幅值占比。
 *   m_u2_pct_x100: 滤波后的U2幅值占比。
 *   m_phase_vector_valid: 滤波后 dot/cross 是否有效。
 *   m_phase_dot: 滤波后的同相投影。
 *   m_phase_cross: 滤波后的正交投影。
 *   m_phase_diff_valid: 滤波后相位差角度是否有效。
 *   m_phase_diff_deg_x100: 滤波后的 U1-U2 相位差角度。
 *   filtered_frame_count: 已输出完整滤波帧计数。
 */
module freq_harmonic_iir_filter (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               enable,
    input  wire               s_harmonic_valid,
    output wire               s_harmonic_ready,
    input  wire               s_harmonic_last,
    input  wire [8:0]         s_harmonic_order,
    input  wire               s_harmonic_present,
    input  wire signed [15:0] s_u1_real,
    input  wire signed [15:0] s_u1_imag,
    input  wire signed [15:0] s_u2_real,
    input  wire signed [15:0] s_u2_imag,
    input  wire [16:0]        s_u1_mag,
    input  wire [16:0]        s_u2_mag,
    input  wire [15:0]        s_u1_pct_x100,
    input  wire [15:0]        s_u2_pct_x100,
    input  wire               s_phase_vector_valid,
    input  wire signed [32:0] s_phase_dot,
    input  wire signed [32:0] s_phase_cross,
    input  wire               s_phase_diff_valid,
    input  wire signed [15:0] s_phase_diff_deg_x100,
    input  wire               m_harmonic_ready,
    output wire               m_harmonic_valid,
    output wire               m_harmonic_last,
    output wire [8:0]         m_harmonic_order,
    output wire               m_harmonic_present,
    output wire signed [15:0] m_u1_real,
    output wire signed [15:0] m_u1_imag,
    output wire signed [15:0] m_u2_real,
    output wire signed [15:0] m_u2_imag,
    output wire [16:0]        m_u1_mag,
    output wire [16:0]        m_u2_mag,
    output wire [15:0]        m_u1_pct_x100,
    output wire [15:0]        m_u2_pct_x100,
    output wire               m_phase_vector_valid,
    output wire signed [32:0] m_phase_dot,
    output wire signed [32:0] m_phase_cross,
    output wire               m_phase_diff_valid,
    output wire signed [15:0] m_phase_diff_deg_x100,
    output reg  [15:0]        filtered_frame_count
);

localparam [8:0] LAST_HARMONIC_ORDER = 9'd500;
localparam integer IIR_SHIFT = 4;
localparam signed [17:0] PHASE_180_X100 = 18'sd18000;
localparam signed [17:0] PHASE_360_X100 = 18'sd36000;
localparam signed [18:0] PHASE_180_X100_WIDE = 19'sd18000;
localparam signed [18:0] PHASE_360_X100_WIDE = 19'sd36000;

localparam integer WORD_U1_REAL_LSB = 0;
localparam integer WORD_U1_REAL_MSB = 15;
localparam integer WORD_U1_IMAG_LSB = 16;
localparam integer WORD_U1_IMAG_MSB = 31;
localparam integer WORD_U2_REAL_LSB = 32;
localparam integer WORD_U2_REAL_MSB = 47;
localparam integer WORD_U2_IMAG_LSB = 48;
localparam integer WORD_U2_IMAG_MSB = 63;
localparam integer WORD_U1_MAG_LSB = 64;
localparam integer WORD_U1_MAG_MSB = 80;
localparam integer WORD_U2_MAG_LSB = 81;
localparam integer WORD_U2_MAG_MSB = 97;
localparam integer WORD_U1_PCT_LSB = 98;
localparam integer WORD_U1_PCT_MSB = 113;
localparam integer WORD_U2_PCT_LSB = 114;
localparam integer WORD_U2_PCT_MSB = 129;
localparam integer WORD_PHASE_DOT_LSB = 130;
localparam integer WORD_PHASE_DOT_MSB = 162;
localparam integer WORD_PHASE_CROSS_LSB = 163;
localparam integer WORD_PHASE_CROSS_MSB = 195;
localparam integer WORD_PHASE_LSB = 196;
localparam integer WORD_PHASE_MSB = 211;
localparam integer WORD_VECTOR_VALID_BIT = 212;
localparam integer WORD_PHASE_VALID_BIT = 213;
localparam integer WORD_INIT_BIT = 214;
localparam integer FILTER_WORD_WIDTH = 215;

(* ram_style = "block" *) reg [FILTER_WORD_WIDTH-1:0] state_mem [0:500];

reg [8:0]         clear_index;
reg               init_done;
reg               stage_valid;
reg               stage_last;
reg [8:0]         stage_order;
reg               stage_in_range;
reg               stage_present;
reg signed [15:0] stage_u1_real;
reg signed [15:0] stage_u1_imag;
reg signed [15:0] stage_u2_real;
reg signed [15:0] stage_u2_imag;
reg [16:0]        stage_u1_mag;
reg [16:0]        stage_u2_mag;
reg [15:0]        stage_u1_pct_x100;
reg [15:0]        stage_u2_pct_x100;
reg               stage_phase_vector_valid;
reg signed [32:0] stage_phase_dot;
reg signed [32:0] stage_phase_cross;
reg               stage_phase_diff_valid;
reg signed [15:0] stage_phase_diff_deg_x100;
reg [FILTER_WORD_WIDTH-1:0] state_word_reg;

reg               m_harmonic_valid_reg;
reg               m_harmonic_last_reg;
reg [8:0]         m_harmonic_order_reg;
reg               m_harmonic_present_reg;
reg signed [15:0] m_u1_real_reg;
reg signed [15:0] m_u1_imag_reg;
reg signed [15:0] m_u2_real_reg;
reg signed [15:0] m_u2_imag_reg;
reg [16:0]        m_u1_mag_reg;
reg [16:0]        m_u2_mag_reg;
reg [15:0]        m_u1_pct_x100_reg;
reg [15:0]        m_u2_pct_x100_reg;
reg               m_phase_vector_valid_reg;
reg signed [32:0] m_phase_dot_reg;
reg signed [32:0] m_phase_cross_reg;
reg               m_phase_diff_valid_reg;
reg signed [15:0] m_phase_diff_deg_x100_reg;

wire              output_can_accept;
wire              input_fire;
wire [8:0]        input_index;
wire              mem_write_enable;
wire [8:0]        mem_write_addr;
wire [FILTER_WORD_WIDTH-1:0] mem_write_data;
wire              mem_read_enable;
wire [8:0]        mem_read_addr;
wire              old_init;
wire              old_vector_state_valid;
wire              old_phase_state_valid;
wire              clean_present;
wire signed [15:0] clean_u1_real;
wire signed [15:0] clean_u1_imag;
wire signed [15:0] clean_u2_real;
wire signed [15:0] clean_u2_imag;
wire [16:0]       clean_u1_mag;
wire [16:0]       clean_u2_mag;
wire [15:0]       clean_u1_pct_x100;
wire [15:0]       clean_u2_pct_x100;
wire              clean_phase_vector_valid;
wire signed [32:0] clean_phase_dot;
wire signed [32:0] clean_phase_cross;
wire              clean_phase_valid;
wire signed [15:0] clean_phase_x100;
wire signed [15:0] old_u1_real;
wire signed [15:0] old_u1_imag;
wire signed [15:0] old_u2_real;
wire signed [15:0] old_u2_imag;
wire [16:0]       old_u1_mag;
wire [16:0]       old_u2_mag;
wire [15:0]       old_u1_pct_x100;
wire [15:0]       old_u2_pct_x100;
wire signed [32:0] old_phase_dot;
wire signed [32:0] old_phase_cross;
wire signed [15:0] old_phase_x100;
wire signed [15:0] next_u1_real;
wire signed [15:0] next_u1_imag;
wire signed [15:0] next_u2_real;
wire signed [15:0] next_u2_imag;
wire [16:0]       next_u1_mag;
wire [16:0]       next_u2_mag;
wire [15:0]       next_u1_pct_x100;
wire [15:0]       next_u2_pct_x100;
wire signed [32:0] next_phase_dot;
wire signed [32:0] next_phase_cross;
wire signed [17:0] unwrapped_phase_x100;
wire signed [18:0] old_phase_ext_x100;
wire signed [18:0] unwrapped_phase_ext_x100;
wire signed [18:0] phase_delta_x100;
wire signed [18:0] phase_iir_raw_x100;
wire signed [15:0] next_phase_x100;
wire              next_vector_state_valid;
wire              next_phase_state_valid;
wire [FILTER_WORD_WIDTH-1:0] next_state_word;

// 对有符号 16 bit 量执行 1/16 IIR 平滑。
function signed [15:0] smooth_signed16;
    input              initialized;
    input signed [15:0] old_value;
    input signed [15:0] input_value;
    reg signed [16:0] old_ext;
    reg signed [16:0] input_ext;
    reg signed [16:0] delta_ext;
    reg signed [16:0] next_ext;
    begin
        old_ext   = {old_value[15], old_value};
        input_ext = {input_value[15], input_value};
        delta_ext = input_ext - old_ext;
        next_ext  = initialized ? (old_ext + (delta_ext >>> IIR_SHIFT)) : input_ext;
        smooth_signed16 = next_ext[15:0];
    end
endfunction

// 对无符号 17 bit 幅值执行 1/16 IIR 平滑。
function [16:0] smooth_unsigned17;
    input        initialized;
    input [16:0] old_value;
    input [16:0] input_value;
    reg signed [17:0] old_ext;
    reg signed [17:0] input_ext;
    reg signed [17:0] delta_ext;
    reg signed [17:0] next_ext;
    begin
        old_ext   = {1'b0, old_value};
        input_ext = {1'b0, input_value};
        delta_ext = input_ext - old_ext;
        next_ext  = initialized ? (old_ext + (delta_ext >>> IIR_SHIFT)) : input_ext;
        smooth_unsigned17 = next_ext[17] ? 17'd0 : next_ext[16:0];
    end
endfunction

// 对无符号 16 bit 占比执行 1/16 IIR 平滑。
function [15:0] smooth_unsigned16;
    input        initialized;
    input [15:0] old_value;
    input [15:0] input_value;
    reg signed [16:0] old_ext;
    reg signed [16:0] input_ext;
    reg signed [16:0] delta_ext;
    reg signed [16:0] next_ext;
    begin
        old_ext   = {1'b0, old_value};
        input_ext = {1'b0, input_value};
        delta_ext = input_ext - old_ext;
        next_ext  = initialized ? (old_ext + (delta_ext >>> IIR_SHIFT)) : input_ext;
        smooth_unsigned16 = next_ext[16] ? 16'd0 : next_ext[15:0];
    end
endfunction

// 对有符号 33 bit 相位向量执行 1/16 IIR 平滑。
function signed [32:0] smooth_signed33;
    input              initialized;
    input signed [32:0] old_value;
    input signed [32:0] input_value;
    reg signed [33:0] old_ext;
    reg signed [33:0] input_ext;
    reg signed [33:0] delta_ext;
    reg signed [33:0] next_ext;
    begin
        old_ext   = {old_value[32], old_value};
        input_ext = {input_value[32], input_value};
        delta_ext = input_ext - old_ext;
        next_ext  = initialized ? (old_ext + (delta_ext >>> IIR_SHIFT)) : input_ext;
        smooth_signed33 = next_ext[32:0];
    end
endfunction

// 相位输入先相对上一滤波值展开，避免 +180/-180 边界两侧被错误平均。
function signed [17:0] unwrap_phase18;
    input              old_valid;
    input signed [15:0] old_phase;
    input signed [15:0] input_phase;
    reg signed [17:0] old_ext;
    reg signed [17:0] input_ext;
    reg signed [17:0] delta_ext;
    begin
        old_ext   = {{2{old_phase[15]}}, old_phase};
        input_ext = {{2{input_phase[15]}}, input_phase};
        delta_ext = input_ext - old_ext;

        if (!old_valid)
            unwrap_phase18 = input_ext;
        else if (delta_ext > PHASE_180_X100)
            unwrap_phase18 = input_ext - PHASE_360_X100;
        else if (delta_ext < -PHASE_180_X100)
            unwrap_phase18 = input_ext + PHASE_360_X100;
        else
            unwrap_phase18 = input_ext;
    end
endfunction

// 相位滤波后重新折回 -180.00 到 +180.00 度范围。
function signed [15:0] wrap_phase16;
    input signed [18:0] phase_value;
    reg signed [18:0] phase_minus;
    reg signed [18:0] phase_plus;
    begin
        phase_minus = phase_value - PHASE_360_X100_WIDE;
        phase_plus  = phase_value + PHASE_360_X100_WIDE;

        if (phase_value > PHASE_180_X100_WIDE)
            wrap_phase16 = phase_minus[15:0];
        else if (phase_value < -PHASE_180_X100_WIDE)
            wrap_phase16 = phase_plus[15:0];
        else
            wrap_phase16 = phase_value[15:0];
    end
endfunction

// 组合生成输入握手条件，IIR 状态 RAM 清零完成后才接收上游数据。
assign output_can_accept = !m_harmonic_valid_reg || m_harmonic_ready;
assign s_harmonic_ready  = enable && init_done && !stage_valid && output_can_accept;
assign input_fire        = s_harmonic_valid && s_harmonic_ready;
assign input_index       = (s_harmonic_order <= LAST_HARMONIC_ORDER) ? s_harmonic_order : LAST_HARMONIC_ORDER;

// 组合生成 RAM 同步读写端口，保持 RAM 访问模板简单，避免 Vivado 将状态存储拆成触发器。
assign mem_write_enable = !init_done || (stage_valid && output_can_accept);
assign mem_write_addr   = !init_done ? clear_index : stage_order;
assign mem_write_data   = !init_done ? {FILTER_WORD_WIDTH{1'b0}} : next_state_word;
assign mem_read_enable  = input_fire;
assign mem_read_addr    = input_index;

// 组合拆出上一帧滤波状态，并对无效谐波输入归零，避免显示和统计残留旧值。
assign old_init              = state_word_reg[WORD_INIT_BIT];
assign old_vector_state_valid = old_init && state_word_reg[WORD_VECTOR_VALID_BIT];
assign old_phase_state_valid = old_init && state_word_reg[WORD_PHASE_VALID_BIT];
assign old_u1_real            = state_word_reg[WORD_U1_REAL_MSB:WORD_U1_REAL_LSB];
assign old_u1_imag            = state_word_reg[WORD_U1_IMAG_MSB:WORD_U1_IMAG_LSB];
assign old_u2_real            = state_word_reg[WORD_U2_REAL_MSB:WORD_U2_REAL_LSB];
assign old_u2_imag            = state_word_reg[WORD_U2_IMAG_MSB:WORD_U2_IMAG_LSB];
assign old_u1_mag             = state_word_reg[WORD_U1_MAG_MSB:WORD_U1_MAG_LSB];
assign old_u2_mag             = state_word_reg[WORD_U2_MAG_MSB:WORD_U2_MAG_LSB];
assign old_u1_pct_x100        = state_word_reg[WORD_U1_PCT_MSB:WORD_U1_PCT_LSB];
assign old_u2_pct_x100        = state_word_reg[WORD_U2_PCT_MSB:WORD_U2_PCT_LSB];
assign old_phase_dot         = state_word_reg[WORD_PHASE_DOT_MSB:WORD_PHASE_DOT_LSB];
assign old_phase_cross       = state_word_reg[WORD_PHASE_CROSS_MSB:WORD_PHASE_CROSS_LSB];
assign old_phase_x100        = state_word_reg[WORD_PHASE_MSB:WORD_PHASE_LSB];

assign clean_present            = stage_present && stage_in_range;
assign clean_u1_real             = clean_present ? stage_u1_real : 16'sd0;
assign clean_u1_imag             = clean_present ? stage_u1_imag : 16'sd0;
assign clean_u2_real             = clean_present ? stage_u2_real : 16'sd0;
assign clean_u2_imag             = clean_present ? stage_u2_imag : 16'sd0;
assign clean_u1_mag              = clean_present ? stage_u1_mag : 17'd0;
assign clean_u2_mag              = clean_present ? stage_u2_mag : 17'd0;
assign clean_u1_pct_x100         = clean_present ? stage_u1_pct_x100 : 16'd0;
assign clean_u2_pct_x100         = clean_present ? stage_u2_pct_x100 : 16'd0;
assign clean_phase_vector_valid = clean_present && stage_phase_vector_valid;
assign clean_phase_dot          = clean_phase_vector_valid ? stage_phase_dot : 33'sd0;
assign clean_phase_cross        = clean_phase_vector_valid ? stage_phase_cross : 33'sd0;
assign clean_phase_valid        = clean_present && stage_phase_diff_valid;
assign clean_phase_x100         = clean_phase_valid ? stage_phase_diff_deg_x100 : 16'sd0;

// 组合计算各字段下一次 IIR 状态；相位无效时保留上一有效相位状态。
assign next_u1_real      = smooth_signed16(old_init, old_u1_real, clean_u1_real);
assign next_u1_imag      = smooth_signed16(old_init, old_u1_imag, clean_u1_imag);
assign next_u2_real      = smooth_signed16(old_init, old_u2_real, clean_u2_real);
assign next_u2_imag      = smooth_signed16(old_init, old_u2_imag, clean_u2_imag);
assign next_u1_mag       = smooth_unsigned17(old_init, old_u1_mag, clean_u1_mag);
assign next_u2_mag       = smooth_unsigned17(old_init, old_u2_mag, clean_u2_mag);
assign next_u1_pct_x100  = smooth_unsigned16(old_init, old_u1_pct_x100, clean_u1_pct_x100);
assign next_u2_pct_x100  = smooth_unsigned16(old_init, old_u2_pct_x100, clean_u2_pct_x100);
assign next_phase_dot   = clean_phase_vector_valid ? smooth_signed33(old_vector_state_valid, old_phase_dot, clean_phase_dot) : old_phase_dot;
assign next_phase_cross = clean_phase_vector_valid ? smooth_signed33(old_vector_state_valid, old_phase_cross, clean_phase_cross) : old_phase_cross;

assign unwrapped_phase_x100     = unwrap_phase18(old_phase_state_valid, old_phase_x100, clean_phase_x100);
assign old_phase_ext_x100       = {{3{old_phase_x100[15]}}, old_phase_x100};
assign unwrapped_phase_ext_x100 = {unwrapped_phase_x100[17], unwrapped_phase_x100};
assign phase_delta_x100         = unwrapped_phase_ext_x100 - old_phase_ext_x100;
assign phase_iir_raw_x100       = old_phase_state_valid ?
                                  (old_phase_ext_x100 + (phase_delta_x100 >>> IIR_SHIFT)) :
                                  unwrapped_phase_ext_x100;
assign next_phase_x100          = clean_phase_valid ? wrap_phase16(phase_iir_raw_x100) : old_phase_x100;
assign next_vector_state_valid  = old_vector_state_valid || clean_phase_vector_valid;
assign next_phase_state_valid   = old_phase_state_valid || clean_phase_valid;
assign next_state_word          = {
    1'b1,
    next_phase_state_valid,
    next_vector_state_valid,
    next_phase_x100,
    next_phase_cross,
    next_phase_dot,
    next_u2_pct_x100,
    next_u1_pct_x100,
    next_u2_mag,
    next_u1_mag,
    next_u2_imag,
    next_u2_real,
    next_u1_imag,
    next_u1_real
};

// 对外导出滤波后的谐波流寄存器。
assign m_harmonic_valid      = m_harmonic_valid_reg;
assign m_harmonic_last       = m_harmonic_last_reg;
assign m_harmonic_order      = m_harmonic_order_reg;
assign m_harmonic_present    = m_harmonic_present_reg;
assign m_u1_real              = m_u1_real_reg;
assign m_u1_imag              = m_u1_imag_reg;
assign m_u2_real              = m_u2_real_reg;
assign m_u2_imag              = m_u2_imag_reg;
assign m_u1_mag               = m_u1_mag_reg;
assign m_u2_mag               = m_u2_mag_reg;
assign m_u1_pct_x100          = m_u1_pct_x100_reg;
assign m_u2_pct_x100          = m_u2_pct_x100_reg;
assign m_phase_vector_valid  = m_phase_vector_valid_reg;
assign m_phase_dot           = m_phase_dot_reg;
assign m_phase_cross         = m_phase_cross_reg;
assign m_phase_diff_valid    = m_phase_diff_valid_reg;
assign m_phase_diff_deg_x100 = m_phase_diff_deg_x100_reg;

// 使用无异步复位的同步 RAM 模板保存每个谐波次数的 IIR 状态。
always @(posedge clk) begin
    if (mem_write_enable)
        state_mem[mem_write_addr] <= mem_write_data;

    if (mem_read_enable)
        state_word_reg <= state_mem[mem_read_addr];
end

// 在频域时钟域先顺序清零状态 RAM，随后以两拍流水读取旧状态并写回 IIR 新状态。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        clear_index                 <= 9'd0;
        init_done                   <= 1'b0;
        stage_valid                 <= 1'b0;
        stage_last                  <= 1'b0;
        stage_order                 <= 9'd0;
        stage_in_range              <= 1'b0;
        stage_present               <= 1'b0;
        stage_u1_real                <= 16'sd0;
        stage_u1_imag                <= 16'sd0;
        stage_u2_real                <= 16'sd0;
        stage_u2_imag                <= 16'sd0;
        stage_u1_mag                 <= 17'd0;
        stage_u2_mag                 <= 17'd0;
        stage_u1_pct_x100            <= 16'd0;
        stage_u2_pct_x100            <= 16'd0;
        stage_phase_vector_valid    <= 1'b0;
        stage_phase_dot             <= 33'sd0;
        stage_phase_cross           <= 33'sd0;
        stage_phase_diff_valid      <= 1'b0;
        stage_phase_diff_deg_x100   <= 16'sd0;
        m_harmonic_valid_reg        <= 1'b0;
        m_harmonic_last_reg         <= 1'b0;
        m_harmonic_order_reg        <= 9'd0;
        m_harmonic_present_reg      <= 1'b0;
        m_u1_real_reg                <= 16'sd0;
        m_u1_imag_reg                <= 16'sd0;
        m_u2_real_reg                <= 16'sd0;
        m_u2_imag_reg                <= 16'sd0;
        m_u1_mag_reg                 <= 17'd0;
        m_u2_mag_reg                 <= 17'd0;
        m_u1_pct_x100_reg            <= 16'd0;
        m_u2_pct_x100_reg            <= 16'd0;
        m_phase_vector_valid_reg    <= 1'b0;
        m_phase_dot_reg             <= 33'sd0;
        m_phase_cross_reg           <= 33'sd0;
        m_phase_diff_valid_reg      <= 1'b0;
        m_phase_diff_deg_x100_reg   <= 16'sd0;
        filtered_frame_count        <= 16'd0;
    end else if (!init_done) begin
        if (clear_index == LAST_HARMONIC_ORDER) begin
            clear_index <= 9'd0;
            init_done   <= 1'b1;
        end else begin
            clear_index <= clear_index + 9'd1;
        end
    end else begin
        if (!enable) begin
            stage_valid          <= 1'b0;
            m_harmonic_valid_reg <= 1'b0;
        end else begin
            if (m_harmonic_valid_reg && m_harmonic_ready)
                m_harmonic_valid_reg <= 1'b0;

            if (stage_valid && output_can_accept) begin
                stage_valid                 <= 1'b0;
                m_harmonic_valid_reg        <= 1'b1;
                m_harmonic_last_reg         <= stage_last;
                m_harmonic_order_reg        <= stage_order;
                m_harmonic_present_reg      <= clean_present;
                m_u1_real_reg                <= next_u1_real;
                m_u1_imag_reg                <= next_u1_imag;
                m_u2_real_reg                <= next_u2_real;
                m_u2_imag_reg                <= next_u2_imag;
                m_u1_mag_reg                 <= next_u1_mag;
                m_u2_mag_reg                 <= next_u2_mag;
                m_u1_pct_x100_reg            <= next_u1_pct_x100;
                m_u2_pct_x100_reg            <= next_u2_pct_x100;
                m_phase_vector_valid_reg    <= clean_phase_vector_valid;
                m_phase_dot_reg             <= clean_phase_vector_valid ? next_phase_dot : 33'sd0;
                m_phase_cross_reg           <= clean_phase_vector_valid ? next_phase_cross : 33'sd0;
                m_phase_diff_valid_reg      <= clean_phase_valid;
                m_phase_diff_deg_x100_reg   <= clean_phase_valid ? next_phase_x100 : 16'sd0;

                if (stage_last)
                    filtered_frame_count <= filtered_frame_count + 16'd1;
            end else if (input_fire) begin
                stage_valid               <= 1'b1;
                stage_last                <= s_harmonic_last;
                stage_order               <= input_index;
                stage_in_range            <= (s_harmonic_order <= LAST_HARMONIC_ORDER);
                stage_present             <= s_harmonic_present;
                stage_u1_real              <= s_u1_real;
                stage_u1_imag              <= s_u1_imag;
                stage_u2_real              <= s_u2_real;
                stage_u2_imag              <= s_u2_imag;
                stage_u1_mag               <= s_u1_mag;
                stage_u2_mag               <= s_u2_mag;
                stage_u1_pct_x100          <= s_u1_pct_x100;
                stage_u2_pct_x100          <= s_u2_pct_x100;
                stage_phase_vector_valid  <= s_phase_vector_valid;
                stage_phase_dot           <= s_phase_dot;
                stage_phase_cross         <= s_phase_cross;
                stage_phase_diff_valid    <= s_phase_diff_valid;
                stage_phase_diff_deg_x100 <= s_phase_diff_deg_x100;
            end
        end
    end
end

endmodule
