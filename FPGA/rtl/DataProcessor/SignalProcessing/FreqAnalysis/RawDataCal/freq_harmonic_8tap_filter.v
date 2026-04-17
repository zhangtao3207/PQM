`timescale 1ns / 1ps

/*
 * 模块: freq_harmonic_8tap_filter
 * 功能:
 *   对频域谐波流中的 U/I 幅值、幅值占比和 U-I 相位差做 8 帧滑动平均，
 *   输出仍保持原有 ready/valid 谐波流格式，供频域柱状图和后续 raw 指标统计使用。
 * 输入:
 *   clk: 频域分析和显示适配工作时钟。
 *   rst_n: 低有效复位信号。
 *   enable: 滤波链路使能，拉低时停止接收新谐波数据。
 *   s_harmonic_valid: 上游谐波结果有效标志。
 *   s_harmonic_last: 当前输入是否为一帧谐波结果的最后一项。
 *   s_harmonic_order: 当前输入的谐波次数。
 *   s_harmonic_present: 当前谐波在本帧中是否有效。
 *   s_u_mag: 当前谐波电压幅值原始量。
 *   s_i_mag: 当前谐波电流幅值原始量。
 *   s_u_pct_x100: 当前谐波电压幅值占比，单位为百分比 x100。
 *   s_i_pct_x100: 当前谐波电流幅值占比，单位为百分比 x100。
 *   s_phase_diff_valid: 当前谐波相位差是否有效。
 *   s_phase_diff_deg_x100: 当前谐波 U-I 相位差，单位为度 x100。
 *   m_harmonic_ready: 下游接收滤波后谐波结果的 ready。
 * 输出:
 *   s_harmonic_ready: 本模块对上游谐波结果的 ready。
 *   m_harmonic_valid: 滤波后谐波结果有效标志。
 *   m_harmonic_last: 滤波后当前项是否为一帧最后一项。
 *   m_harmonic_order: 滤波后结果对应的谐波次数。
 *   m_harmonic_present: 滤波后结果是否有效。
 *   m_u_mag: 8 帧滤波后的电压幅值原始量。
 *   m_i_mag: 8 帧滤波后的电流幅值原始量。
 *   m_u_pct_x100: 8 帧滤波后的电压幅值占比。
 *   m_i_pct_x100: 8 帧滤波后的电流幅值占比。
 *   m_phase_diff_valid: 滤波后相位差是否有效。
 *   m_phase_diff_deg_x100: 8 帧滤波后的 U-I 相位差。
 *   filtered_frame_count: 已完成滤波输出的帧计数。
 */
module freq_harmonic_8tap_filter (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               enable,
    input  wire               s_harmonic_valid,
    output wire               s_harmonic_ready,
    input  wire               s_harmonic_last,
    input  wire [8:0]         s_harmonic_order,
    input  wire               s_harmonic_present,
    input  wire [16:0]        s_u_mag,
    input  wire [16:0]        s_i_mag,
    input  wire [15:0]        s_u_pct_x100,
    input  wire [15:0]        s_i_pct_x100,
    input  wire               s_phase_diff_valid,
    input  wire signed [15:0] s_phase_diff_deg_x100,
    input  wire               m_harmonic_ready,
    output wire               m_harmonic_valid,
    output wire               m_harmonic_last,
    output wire [8:0]         m_harmonic_order,
    output wire               m_harmonic_present,
    output wire [16:0]        m_u_mag,
    output wire [16:0]        m_i_mag,
    output wire [15:0]        m_u_pct_x100,
    output wire [15:0]        m_i_pct_x100,
    output wire               m_phase_diff_valid,
    output wire signed [15:0] m_phase_diff_deg_x100,
    output reg  [15:0]        filtered_frame_count
);

localparam integer FILTER_WORD_WIDTH = 84;
localparam integer WORD_PRESENT_BIT  = 83;
localparam integer WORD_PHASE_VALID_BIT = 82;
localparam integer WORD_PHASE_MSB    = 81;
localparam integer WORD_PHASE_LSB    = 66;
localparam integer WORD_I_PCT_MSB    = 65;
localparam integer WORD_I_PCT_LSB    = 50;
localparam integer WORD_U_PCT_MSB    = 49;
localparam integer WORD_U_PCT_LSB    = 34;
localparam integer WORD_I_MAG_MSB    = 33;
localparam integer WORD_I_MAG_LSB    = 17;
localparam integer WORD_U_MAG_MSB    = 16;
localparam integer WORD_U_MAG_LSB    = 0;
localparam [8:0]   LAST_HARMONIC_ORDER = 9'd500;

reg [FILTER_WORD_WIDTH-1:0] hist0 [0:500];
reg [FILTER_WORD_WIDTH-1:0] hist1 [0:500];
reg [FILTER_WORD_WIDTH-1:0] hist2 [0:500];
reg [FILTER_WORD_WIDTH-1:0] hist3 [0:500];
reg [FILTER_WORD_WIDTH-1:0] hist4 [0:500];
reg [FILTER_WORD_WIDTH-1:0] hist5 [0:500];
reg [FILTER_WORD_WIDTH-1:0] hist6 [0:500];
reg [FILTER_WORD_WIDTH-1:0] hist7 [0:500];

reg [19:0]        u_mag_sum [0:500];
reg [19:0]        i_mag_sum [0:500];
reg [19:0]        u_pct_sum [0:500];
reg [19:0]        i_pct_sum [0:500];
reg signed [20:0] phase_sum [0:500];

reg [8:0]         clear_index;
reg               init_done;
reg [2:0]         frame_slot;
reg [2:0]         frame_fill_count;
reg               filter_ready_reg;
reg               m_harmonic_valid_reg;
reg               m_harmonic_last_reg;
reg [8:0]         m_harmonic_order_reg;
reg               m_harmonic_present_reg;
reg [16:0]        m_u_mag_reg;
reg [16:0]        m_i_mag_reg;
reg [15:0]        m_u_pct_x100_reg;
reg [15:0]        m_i_pct_x100_reg;
reg               m_phase_diff_valid_reg;
reg signed [15:0] m_phase_diff_deg_x100_reg;

reg [FILTER_WORD_WIDTH-1:0] old_word;

wire              output_can_accept;
wire              input_fire;
wire              input_in_range;
wire [16:0]       clean_u_mag;
wire [16:0]       clean_i_mag;
wire [15:0]       clean_u_pct_x100;
wire [15:0]       clean_i_pct_x100;
wire              clean_phase_valid;
wire signed [15:0] clean_phase_x100;
wire [FILTER_WORD_WIDTH-1:0] new_word;
wire [16:0]       old_u_mag;
wire [16:0]       old_i_mag;
wire [15:0]       old_u_pct_x100;
wire [15:0]       old_i_pct_x100;
wire signed [15:0] old_phase_x100;
wire [19:0]       u_mag_sum_next;
wire [19:0]       i_mag_sum_next;
wire [19:0]       u_pct_sum_next;
wire [19:0]       i_pct_sum_next;
wire signed [20:0] phase_sum_next;
wire signed [20:0] phase_avg_next;

// 根据下游 ready 和本地输出寄存器状态生成流控，初始化清零期间不接收上游数据。
assign output_can_accept = !m_harmonic_valid_reg || m_harmonic_ready;
assign s_harmonic_ready  = enable && init_done && output_can_accept;
assign input_fire        = s_harmonic_valid && s_harmonic_ready;
assign input_in_range    = (s_harmonic_order <= LAST_HARMONIC_ORDER);

// 无效谐波写入零值，让滑动和自然衰减，避免显示残留上一帧数据。
assign clean_u_mag        = (s_harmonic_present && input_in_range) ? s_u_mag : 17'd0;
assign clean_i_mag        = (s_harmonic_present && input_in_range) ? s_i_mag : 17'd0;
assign clean_u_pct_x100   = (s_harmonic_present && input_in_range) ? s_u_pct_x100 : 16'd0;
assign clean_i_pct_x100   = (s_harmonic_present && input_in_range) ? s_i_pct_x100 : 16'd0;
assign clean_phase_valid  = s_harmonic_present && input_in_range && s_phase_diff_valid;
assign clean_phase_x100   = clean_phase_valid ? s_phase_diff_deg_x100 : 16'sd0;
assign new_word           = {
    s_harmonic_present && input_in_range,
    clean_phase_valid,
    clean_phase_x100,
    clean_i_pct_x100,
    clean_u_pct_x100,
    clean_i_mag,
    clean_u_mag
};

// 拆出当前环形槽位中的旧样本，更新每个谐波次数对应的滑动和。
assign old_u_mag        = old_word[WORD_U_MAG_MSB:WORD_U_MAG_LSB];
assign old_i_mag        = old_word[WORD_I_MAG_MSB:WORD_I_MAG_LSB];
assign old_u_pct_x100   = old_word[WORD_U_PCT_MSB:WORD_U_PCT_LSB];
assign old_i_pct_x100   = old_word[WORD_I_PCT_MSB:WORD_I_PCT_LSB];
assign old_phase_x100   = old_word[WORD_PHASE_MSB:WORD_PHASE_LSB];
assign u_mag_sum_next   = u_mag_sum[s_harmonic_order] - {3'd0, old_u_mag} + {3'd0, clean_u_mag};
assign i_mag_sum_next   = i_mag_sum[s_harmonic_order] - {3'd0, old_i_mag} + {3'd0, clean_i_mag};
assign u_pct_sum_next   = u_pct_sum[s_harmonic_order] - {4'd0, old_u_pct_x100} + {4'd0, clean_u_pct_x100};
assign i_pct_sum_next   = i_pct_sum[s_harmonic_order] - {4'd0, old_i_pct_x100} + {4'd0, clean_i_pct_x100};
assign phase_sum_next   = phase_sum[s_harmonic_order]
                         - {{5{old_phase_x100[15]}}, old_phase_x100}
                         + {{5{clean_phase_x100[15]}}, clean_phase_x100};
assign phase_avg_next   = phase_sum_next >>> 3;

// 读取当前 frame_slot 对应的历史槽位，供同一拍的滑动和更新使用。
always @(*) begin
    case (frame_slot)
        3'd0: old_word = hist0[s_harmonic_order];
        3'd1: old_word = hist1[s_harmonic_order];
        3'd2: old_word = hist2[s_harmonic_order];
        3'd3: old_word = hist3[s_harmonic_order];
        3'd4: old_word = hist4[s_harmonic_order];
        3'd5: old_word = hist5[s_harmonic_order];
        3'd6: old_word = hist6[s_harmonic_order];
        default: old_word = hist7[s_harmonic_order];
    endcase
end

assign m_harmonic_valid       = m_harmonic_valid_reg;
assign m_harmonic_last        = m_harmonic_last_reg;
assign m_harmonic_order       = m_harmonic_order_reg;
assign m_harmonic_present     = m_harmonic_present_reg;
assign m_u_mag                = m_u_mag_reg;
assign m_i_mag                = m_i_mag_reg;
assign m_u_pct_x100           = m_u_pct_x100_reg;
assign m_i_pct_x100           = m_i_pct_x100_reg;
assign m_phase_diff_valid     = m_phase_diff_valid_reg;
assign m_phase_diff_deg_x100  = m_phase_diff_deg_x100_reg;

// 在频域时钟域清零历史 RAM，随后按谐波次数维护 8 帧环形缓存和滑动平均输出。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        clear_index                 <= 9'd0;
        init_done                   <= 1'b0;
        frame_slot                  <= 3'd0;
        frame_fill_count            <= 3'd0;
        filter_ready_reg            <= 1'b0;
        m_harmonic_valid_reg        <= 1'b0;
        m_harmonic_last_reg         <= 1'b0;
        m_harmonic_order_reg        <= 9'd0;
        m_harmonic_present_reg      <= 1'b0;
        m_u_mag_reg                 <= 17'd0;
        m_i_mag_reg                 <= 17'd0;
        m_u_pct_x100_reg            <= 16'd0;
        m_i_pct_x100_reg            <= 16'd0;
        m_phase_diff_valid_reg      <= 1'b0;
        m_phase_diff_deg_x100_reg   <= 16'sd0;
        filtered_frame_count        <= 16'd0;
    end else if (!init_done) begin
        hist0[clear_index]          <= {FILTER_WORD_WIDTH{1'b0}};
        hist1[clear_index]          <= {FILTER_WORD_WIDTH{1'b0}};
        hist2[clear_index]          <= {FILTER_WORD_WIDTH{1'b0}};
        hist3[clear_index]          <= {FILTER_WORD_WIDTH{1'b0}};
        hist4[clear_index]          <= {FILTER_WORD_WIDTH{1'b0}};
        hist5[clear_index]          <= {FILTER_WORD_WIDTH{1'b0}};
        hist6[clear_index]          <= {FILTER_WORD_WIDTH{1'b0}};
        hist7[clear_index]          <= {FILTER_WORD_WIDTH{1'b0}};
        u_mag_sum[clear_index]      <= 20'd0;
        i_mag_sum[clear_index]      <= 20'd0;
        u_pct_sum[clear_index]      <= 20'd0;
        i_pct_sum[clear_index]      <= 20'd0;
        phase_sum[clear_index]      <= 21'sd0;

        if (clear_index == LAST_HARMONIC_ORDER) begin
            clear_index <= 9'd0;
            init_done   <= 1'b1;
        end else begin
            clear_index <= clear_index + 9'd1;
        end
    end else begin
        if (!enable) begin
            m_harmonic_valid_reg <= 1'b0;
        end else begin
            if (m_harmonic_valid_reg && m_harmonic_ready)
                m_harmonic_valid_reg <= 1'b0;

            if (input_fire) begin
                case (frame_slot)
                    3'd0: hist0[s_harmonic_order] <= new_word;
                    3'd1: hist1[s_harmonic_order] <= new_word;
                    3'd2: hist2[s_harmonic_order] <= new_word;
                    3'd3: hist3[s_harmonic_order] <= new_word;
                    3'd4: hist4[s_harmonic_order] <= new_word;
                    3'd5: hist5[s_harmonic_order] <= new_word;
                    3'd6: hist6[s_harmonic_order] <= new_word;
                    default: hist7[s_harmonic_order] <= new_word;
                endcase

                u_mag_sum[s_harmonic_order] <= u_mag_sum_next;
                i_mag_sum[s_harmonic_order] <= i_mag_sum_next;
                u_pct_sum[s_harmonic_order] <= u_pct_sum_next;
                i_pct_sum[s_harmonic_order] <= i_pct_sum_next;
                phase_sum[s_harmonic_order] <= phase_sum_next;

                m_harmonic_valid_reg   <= 1'b1;
                m_harmonic_last_reg    <= s_harmonic_last;
                m_harmonic_order_reg   <= s_harmonic_order;
                m_harmonic_present_reg <= s_harmonic_present && input_in_range;

                if (filter_ready_reg) begin
                    m_u_mag_reg              <= u_mag_sum_next[19:3];
                    m_i_mag_reg              <= i_mag_sum_next[19:3];
                    m_u_pct_x100_reg         <= u_pct_sum_next[18:3];
                    m_i_pct_x100_reg         <= i_pct_sum_next[18:3];
                    m_phase_diff_deg_x100_reg<= phase_avg_next[15:0];
                end else begin
                    m_u_mag_reg              <= clean_u_mag;
                    m_i_mag_reg              <= clean_i_mag;
                    m_u_pct_x100_reg         <= clean_u_pct_x100;
                    m_i_pct_x100_reg         <= clean_i_pct_x100;
                    m_phase_diff_deg_x100_reg<= clean_phase_x100;
                end

                m_phase_diff_valid_reg <= clean_phase_valid;

                if (s_harmonic_last) begin
                    frame_slot <= (frame_slot == 3'd7) ? 3'd0 : (frame_slot + 3'd1);

                    if (!filter_ready_reg) begin
                        if (frame_fill_count == 3'd7)
                            filter_ready_reg <= 1'b1;
                        else
                            frame_fill_count <= frame_fill_count + 3'd1;
                    end

                    filtered_frame_count <= filtered_frame_count + 16'd1;
                end
            end
        end
    end
end

endmodule
