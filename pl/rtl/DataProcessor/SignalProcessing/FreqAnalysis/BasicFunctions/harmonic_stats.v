`timescale 1ns / 1ps

/*
 * 模块: harmonic_stats
 * 功能:
 *   接收一帧正半谱幅值结果，统计 0~500 次谐波的 U1/U2 幅值及其占总幅值百分比，
 *   并按 MAX_ORDER 输出 0~63 次条目（RFG 取点 C_K=64，64 次以上无信息量）。
 *   本模块同时用块 RAM 缓存每次谐波的 real/imag，供后续 U1-U2 相位差计算模块使用。
 *
 * 输入:
 *   clk: 频域统计时钟，通常接频域工作时钟。
 *   rst_n: 低有效复位信号。
 *   enable: 谐波统计使能，拉低时停止接收并清空输出状态。
 *   s_mag_valid: 上游幅值结果有效标志。
 *   s_mag_last: 上游正半谱幅值结果帧尾标志。
 *   s_bin_index: 上游幅值结果对应的频点号。
 *   s_u1_real: 与幅值结果对齐的U1通道频点实部。
 *   s_u1_imag: 与幅值结果对齐的U1通道频点虚部。
 *   s_u2_real: 与幅值结果对齐的U2通道频点实部。
 *   s_u2_imag: 与幅值结果对齐的U2通道频点虚部。
 *   s_u1_mag: U1通道当前频点幅值。
 *   s_u2_mag: U2通道当前频点幅值。
 *   m_harmonic_ready: 下游谐波结果接收就绪标志。
 *
 * 输出:
 *   s_mag_ready: 本模块对上游幅值结果流的接收就绪标志。
 *   m_harmonic_valid: 谐波统计结果有效标志。
 *   m_harmonic_last: 0~MAX_ORDER（63）次谐波统计结果的最后一项标志。
 *   m_harmonic_order: 当前输出的谐波次数。
 *   m_harmonic_present: 当前谐波在本帧中是否被捕获。
 *   m_u1_real: 当前谐波U1通道实部。
 *   m_u1_imag: 当前谐波U1通道虚部。
 *   m_u2_real: 当前谐波U2通道实部。
 *   m_u2_imag: 当前谐波U2通道虚部。
 *   m_u1_mag: 当前谐波U1通道幅值。
 *   m_u2_mag: 当前谐波U2通道幅值。
 *   m_u1_pct_x100: 当前谐波U1幅值占本帧U1总幅值的百分比，100.00% 表示为 10000。
 *   m_u2_pct_x100: 当前谐波U2幅值占本帧U2总幅值的百分比，100.00% 表示为 10000。
 *   stats_busy: 当前正在接收、归一化或输出一帧谐波统计结果。
 *   capture_frame_done: 已捕获一帧上游幅值结果的单周期脉冲。
 *   harmonic_frame_done: 0~MAX_ORDER（63）次谐波统计结果已输出完毕的单周期脉冲。
 *   harmonic_frame_count: 已输出完成的谐波统计帧计数。
 *   u1_total_mag: 本帧 0~500 次谐波的U1幅值总和。
 *   u2_total_mag: 本帧 0~500 次谐波的U2幅值总和。
 */
module harmonic_stats #(
    parameter [10:0] FUND_BIN = 11'd1
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               enable,
    input  wire               s_mag_valid,
    output wire               s_mag_ready,
    input  wire               s_mag_last,
    input  wire [10:0]        s_bin_index,
    input  wire signed [15:0] s_u1_real,
    input  wire signed [15:0] s_u1_imag,
    input  wire signed [15:0] s_u2_real,
    input  wire signed [15:0] s_u2_imag,
    input  wire [16:0]        s_u1_mag,
    input  wire [16:0]        s_u2_mag,
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
    output wire               stats_busy,
    output wire               capture_frame_done,
    output wire               harmonic_frame_done,
    output reg  [15:0]        harmonic_frame_count,
    output reg  [31:0]        u1_total_mag,
    output reg  [31:0]        u2_total_mag
);

localparam [2:0] ST_CLEAR    = 3'd0;
localparam [2:0] ST_IDLE     = 3'd1;
localparam [2:0] ST_CAPTURE  = 3'd2;
localparam [2:0] ST_READ     = 3'd3;
localparam [2:0] ST_LOAD     = 3'd4;
localparam [2:0] ST_DIVIDE   = 3'd5;
localparam [2:0] ST_OUTPUT   = 3'd6;
localparam [8:0] MAX_ORDER   = 9'd63;
localparam [10:0] MAX_BIN_FUND1 = 11'd500;
localparam [10:0] MAX_BIN_FUND2 = 11'd1000;
localparam signed [15:0] PERCENT_SCALE = 16'sd10000;
localparam integer HARMONIC_WORD_WIDTH = 130;
localparam integer HARMONIC_TAG_MSB    = 129;
localparam integer HARMONIC_TAG_LSB    = 98;
localparam integer HARMONIC_U1_MAG_MSB  = 97;
localparam integer HARMONIC_U1_MAG_LSB  = 81;
localparam integer HARMONIC_U2_MAG_MSB  = 80;
localparam integer HARMONIC_U2_MAG_LSB  = 64;
localparam integer HARMONIC_U1_REAL_MSB = 63;
localparam integer HARMONIC_U1_REAL_LSB = 48;
localparam integer HARMONIC_U1_IMAG_MSB = 47;
localparam integer HARMONIC_U1_IMAG_LSB = 32;
localparam integer HARMONIC_U2_REAL_MSB = 31;
localparam integer HARMONIC_U2_REAL_LSB = 16;
localparam integer HARMONIC_U2_IMAG_MSB = 15;
localparam integer HARMONIC_U2_IMAG_LSB = 0;

reg [2:0]         state;
reg [31:0]        frame_tag;
reg [8:0]         clear_order;
reg [8:0]         output_order;
reg               capture_frame_done_reg;
reg               harmonic_frame_done_reg;
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
reg               u1_div_start_reg;
reg               u2_div_start_reg;
reg               u1_pct_bypass_reg;
reg               u2_pct_bypass_reg;

// 缓存按 bin 号索引（FUND_BIN=1 时最大 bin = MAX_BIN_FUND1 = 500），因此深度必须保持 501；
// 与输出条目数 MAX_ORDER 无关，MAX_ORDER 只约束输出扫描范围 0..63；
// 因此 ST_CLEAR 只清 0..63（64 拍），64..500 的残留不会被读（输出只扫 0..63）。
(* ram_style = "block" *) reg [HARMONIC_WORD_WIDTH-1:0] harmonic_mem [0:500];
reg [HARMONIC_WORD_WIDTH-1:0] harmonic_read_data;

wire              input_fire;
wire              output_fire;
wire              mem_write_enable;
wire [8:0]        mem_write_addr;
wire [HARMONIC_WORD_WIDTH-1:0] mem_write_data;
wire [HARMONIC_WORD_WIDTH-1:0] harmonic_write_data;
wire [31:0]       next_frame_tag;
wire              target_fund1;
wire              target_fund2;
wire              target_harmonic;
wire [8:0]        target_order;
wire              current_present;
wire signed [15:0] current_u1_real;
wire signed [15:0] current_u1_imag;
wire signed [15:0] current_u2_real;
wire signed [15:0] current_u2_imag;
wire [16:0]       current_u1_mag;
wire [16:0]       current_u2_mag;
wire signed [16:0] u1_mag_mul_value;
wire signed [16:0] u2_mag_mul_value;
wire signed [32:0] u1_pct_product;
wire signed [32:0] u2_pct_product;
wire [32:0]       u1_pct_dividend;
wire [32:0]       u2_pct_dividend;
wire [32:0]       u1_pct_divisor;
wire [32:0]       u2_pct_divisor;
wire              u1_div_busy;
wire              u2_div_busy;
wire              u1_div_done;
wire              u2_div_done;
wire              u1_div_zero;
wire              u2_div_zero;
wire [32:0]       u1_div_quotient;
wire [32:0]       u2_div_quotient;
wire              divide_done;

// 组合识别当前 bin 是否为目标谐波；当前只支持基波位于 bin 1 或 bin 2 的 0~500 次统计。
assign target_fund1 =
    (FUND_BIN == 11'd1) && (s_bin_index <= MAX_BIN_FUND1);
assign target_fund2 =
    (FUND_BIN == 11'd2) && (s_bin_index <= MAX_BIN_FUND2) && (s_bin_index[0] == 1'b0);
assign target_harmonic = target_fund1 || target_fund2;
assign target_order    = target_fund1 ? s_bin_index[8:0] : s_bin_index[9:1];

// 组合生成谐波缓存 RAM 的写端口控制，复位后先顺序清 RAM，再写入当前帧捕获结果。
assign mem_write_enable  = (state == ST_CLEAR) || (input_fire && target_harmonic);
assign mem_write_addr    = (state == ST_CLEAR) ? clear_order : target_order;
assign mem_write_data    = (state == ST_CLEAR) ? {HARMONIC_WORD_WIDTH{1'b0}} : harmonic_write_data;
assign harmonic_write_data = {
    frame_tag,
    s_u1_mag,
    s_u2_mag,
    s_u1_real,
    s_u1_imag,
    s_u2_real,
    s_u2_imag
};

// 组合生成非零帧标签，避免清零后的 RAM 内容被误判为有效谐波。
assign next_frame_tag = (frame_tag == 32'hFFFF_FFFF) ? 32'd1 : (frame_tag + 32'd1);

// 组合生成上游和下游握手状态。
assign s_mag_ready = (state == ST_CAPTURE);
assign input_fire  = s_mag_valid && s_mag_ready;
assign output_fire = m_harmonic_valid_reg && m_harmonic_ready;
assign stats_busy  = (state != ST_IDLE) || m_harmonic_valid_reg;

// 组合拆包同步读出的谐波缓存字，供输出和百分比计算使用。
assign current_present = (harmonic_read_data[HARMONIC_TAG_MSB:HARMONIC_TAG_LSB] == frame_tag);
assign current_u1_mag   = harmonic_read_data[HARMONIC_U1_MAG_MSB:HARMONIC_U1_MAG_LSB];
assign current_u2_mag   = harmonic_read_data[HARMONIC_U2_MAG_MSB:HARMONIC_U2_MAG_LSB];
assign current_u1_real  = harmonic_read_data[HARMONIC_U1_REAL_MSB:HARMONIC_U1_REAL_LSB];
assign current_u1_imag  = harmonic_read_data[HARMONIC_U1_IMAG_MSB:HARMONIC_U1_IMAG_LSB];
assign current_u2_real  = harmonic_read_data[HARMONIC_U2_REAL_MSB:HARMONIC_U2_REAL_LSB];
assign current_u2_imag  = harmonic_read_data[HARMONIC_U2_IMAG_MSB:HARMONIC_U2_IMAG_LSB];

// 组合生成百分比计算的乘法器输入，乘法器输出再送入无符号除法器。
assign u1_mag_mul_value = m_u1_mag_reg;
assign u2_mag_mul_value = m_u2_mag_reg;
assign u1_pct_dividend  = u1_pct_product[32:0];
assign u2_pct_dividend  = u2_pct_product[32:0];
assign u1_pct_divisor   = {1'b0, u1_total_mag};
assign u2_pct_divisor   = {1'b0, u2_total_mag};
assign divide_done =
    (u1_pct_bypass_reg || u1_div_done) && (u2_pct_bypass_reg || u2_div_done);

// 对外导出谐波统计结果流。
assign m_harmonic_valid   = m_harmonic_valid_reg;
assign m_harmonic_last    = m_harmonic_last_reg;
assign m_harmonic_order   = m_harmonic_order_reg;
assign m_harmonic_present = m_harmonic_present_reg;
assign m_u1_real           = m_u1_real_reg;
assign m_u1_imag           = m_u1_imag_reg;
assign m_u2_real           = m_u2_real_reg;
assign m_u2_imag           = m_u2_imag_reg;
assign m_u1_mag            = m_u1_mag_reg;
assign m_u2_mag            = m_u2_mag_reg;
assign m_u1_pct_x100       = m_u1_pct_x100_reg;
assign m_u2_pct_x100       = m_u2_pct_x100_reg;
assign capture_frame_done = capture_frame_done_reg;
assign harmonic_frame_done = harmonic_frame_done_reg;

// 实例化U1幅值百分比乘法器，计算 mag * 10000 的被除数。
multiplier_signed #(
    .A_WIDTH(17),
    .B_WIDTH(16)
) u_mul_u1_percent (
    .multiplicand(u1_mag_mul_value),
    .multiplier  (PERCENT_SCALE),
    .product     (u1_pct_product)
);

// 实例化U2幅值百分比乘法器，计算 mag * 10000 的被除数。
multiplier_signed #(
    .A_WIDTH(17),
    .B_WIDTH(16)
) u_mul_u2_percent (
    .multiplicand(u2_mag_mul_value),
    .multiplier  (PERCENT_SCALE),
    .product     (u2_pct_product)
);

// 实例化U1幅值百分比除法器，计算当前谐波占U1总幅值的 x100 百分比。
divider_unsigned #(
    .WIDTH(33)
) u_div_u1_percent (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (u1_div_start_reg),
    .dividend      (u1_pct_dividend),
    .divisor       (u1_pct_divisor),
    .busy          (u1_div_busy),
    .done          (u1_div_done),
    .divide_by_zero(u1_div_zero),
    .quotient      (u1_div_quotient)
);

// 实例化U2幅值百分比除法器，计算当前谐波占U2总幅值的 x100 百分比。
divider_unsigned #(
    .WIDTH(33)
) u_div_u2_percent (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (u2_div_start_reg),
    .dividend      (u2_pct_dividend),
    .divisor       (u2_pct_divisor),
    .busy          (u2_div_busy),
    .done          (u2_div_done),
    .divide_by_zero(u2_div_zero),
    .quotient      (u2_div_quotient)
);

// 用同步读写模板实现谐波结果缓存，避免 501 组结果被综合成触发器和大规模 mux。
always @(posedge clk) begin
    if (mem_write_enable) begin
        harmonic_mem[mem_write_addr] <= mem_write_data;
    end

    if (state == ST_READ) begin
        harmonic_read_data <= harmonic_mem[output_order];
    end
end

// 在频域统计时钟域完成 RAM 清零、幅值捕获、百分比归一化和逐项输出。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state                   <= ST_CLEAR;
        frame_tag               <= 32'd0;
        clear_order             <= 9'd0;
        output_order            <= 9'd0;
        capture_frame_done_reg  <= 1'b0;
        harmonic_frame_done_reg <= 1'b0;
        m_harmonic_valid_reg    <= 1'b0;
        m_harmonic_last_reg     <= 1'b0;
        m_harmonic_order_reg    <= 9'd0;
        m_harmonic_present_reg  <= 1'b0;
        m_u1_real_reg            <= 16'sd0;
        m_u1_imag_reg            <= 16'sd0;
        m_u2_real_reg            <= 16'sd0;
        m_u2_imag_reg            <= 16'sd0;
        m_u1_mag_reg             <= 17'd0;
        m_u2_mag_reg             <= 17'd0;
        m_u1_pct_x100_reg        <= 16'd0;
        m_u2_pct_x100_reg        <= 16'd0;
        u1_div_start_reg         <= 1'b0;
        u2_div_start_reg         <= 1'b0;
        u1_pct_bypass_reg        <= 1'b0;
        u2_pct_bypass_reg        <= 1'b0;
        harmonic_frame_count    <= 16'd0;
        u1_total_mag             <= 32'd0;
        u2_total_mag             <= 32'd0;
    end else begin
        capture_frame_done_reg  <= 1'b0;
        harmonic_frame_done_reg <= 1'b0;
        u1_div_start_reg         <= 1'b0;
        u2_div_start_reg         <= 1'b0;

        if (state == ST_CLEAR) begin
            m_harmonic_valid_reg <= 1'b0;
            m_harmonic_last_reg  <= 1'b0;
            output_order         <= 9'd0;
            u1_total_mag          <= 32'd0;
            u2_total_mag          <= 32'd0;

            if (clear_order == MAX_ORDER) begin
                clear_order <= 9'd0;
                state       <= ST_IDLE;
            end else begin
                clear_order <= clear_order + 9'd1;
            end
        end else if (!enable) begin
            state                <= ST_IDLE;
            m_harmonic_valid_reg <= 1'b0;
            m_harmonic_last_reg  <= 1'b0;
            output_order         <= 9'd0;
            u1_total_mag          <= 32'd0;
            u2_total_mag          <= 32'd0;
        end else begin
            case (state)
                ST_IDLE: begin
                    frame_tag            <= next_frame_tag;
                    output_order         <= 9'd0;
                    u1_total_mag          <= 32'd0;
                    u2_total_mag          <= 32'd0;
                    m_harmonic_valid_reg <= 1'b0;
                    m_harmonic_last_reg  <= 1'b0;
                    state                <= ST_CAPTURE;
                end

                ST_CAPTURE: begin
                    if (input_fire) begin
                        if (target_harmonic) begin
                            u1_total_mag <= u1_total_mag + {15'd0, s_u1_mag};
                            u2_total_mag <= u2_total_mag + {15'd0, s_u2_mag};
                        end

                        if (s_mag_last) begin
                            capture_frame_done_reg <= 1'b1;
                            output_order           <= 9'd0;
                            state                  <= ST_READ;
                        end
                    end
                end

                ST_READ: begin
                    state <= ST_LOAD;
                end

                ST_LOAD: begin
                    m_harmonic_order_reg   <= output_order;
                    m_harmonic_last_reg    <= (output_order == MAX_ORDER);
                    m_harmonic_present_reg <= current_present;

                    if (current_present) begin
                        m_u1_real_reg <= current_u1_real;
                        m_u1_imag_reg <= current_u1_imag;
                        m_u2_real_reg <= current_u2_real;
                        m_u2_imag_reg <= current_u2_imag;
                        m_u1_mag_reg  <= current_u1_mag;
                        m_u2_mag_reg  <= current_u2_mag;
                    end else begin
                        m_u1_real_reg <= 16'sd0;
                        m_u1_imag_reg <= 16'sd0;
                        m_u2_real_reg <= 16'sd0;
                        m_u2_imag_reg <= 16'sd0;
                        m_u1_mag_reg  <= 17'd0;
                        m_u2_mag_reg  <= 17'd0;
                    end

                    m_u1_pct_x100_reg <= 16'd0;
                    m_u2_pct_x100_reg <= 16'd0;
                    state            <= ST_DIVIDE;
                end

                ST_DIVIDE: begin
                    u1_pct_bypass_reg <= !m_harmonic_present_reg || (u1_total_mag == 32'd0) || (m_u1_mag_reg == 17'd0);
                    u2_pct_bypass_reg <= !m_harmonic_present_reg || (u2_total_mag == 32'd0) || (m_u2_mag_reg == 17'd0);
                    u1_div_start_reg  <= m_harmonic_present_reg && (u1_total_mag != 32'd0) && (m_u1_mag_reg != 17'd0);
                    u2_div_start_reg  <= m_harmonic_present_reg && (u2_total_mag != 32'd0) && (m_u2_mag_reg != 17'd0);
                    state            <= ST_OUTPUT;
                end

                ST_OUTPUT: begin
                    if (!m_harmonic_valid_reg && divide_done) begin
                        if (u1_pct_bypass_reg || u1_div_zero)
                            m_u1_pct_x100_reg <= 16'd0;
                        else
                            m_u1_pct_x100_reg <= u1_div_quotient[15:0];

                        if (u2_pct_bypass_reg || u2_div_zero)
                            m_u2_pct_x100_reg <= 16'd0;
                        else
                            m_u2_pct_x100_reg <= u2_div_quotient[15:0];

                        m_harmonic_valid_reg <= 1'b1;
                    end else if (output_fire) begin
                        m_harmonic_valid_reg <= 1'b0;

                        if (m_harmonic_last_reg) begin
                            harmonic_frame_done_reg <= 1'b1;
                            harmonic_frame_count    <= harmonic_frame_count + 16'd1;
                            state                   <= ST_IDLE;
                        end else begin
                            output_order <= output_order + 9'd1;
                            state        <= ST_READ;
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
