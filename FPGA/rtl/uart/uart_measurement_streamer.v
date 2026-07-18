`timescale 1ns / 1ps

/*
 * 模块: uart_measurement_streamer
 * 功能:
 *   复用显示链路提交的文本快照与完整 `0..500` 次谐波结果，在 `clk` 域内按固定 ASCII 协议输出 UART 字节。
 *   模块只在“已拿到至少一份文本快照”且“已缓存一整帧谐波结果”后启动一次完整发送。
 *   为降低 LUT/寄存器开销，谐波缓存改为 BRAM 风格时分读写，`x100 -> digits` 也改为单实例顺序格式化。
 *
 * 输入:
 *   clk: UART 串流状态机与谐波缓存工作时钟。
 *   rst_n: 低有效复位信号。
 *   text_packet: 来自显示链路的文本快照总线。
 *   text_packet_commit_toggle: 文本快照每次提交后翻转一次。
 *   harmonic_fire: 当前谐波结果在本拍被下游接收。
 *   harmonic_last: 当前谐波结果是否为整帧帧尾。
 *   harmonic_order: 当前谐波阶次。
 *   harmonic_present: 当前谐波是否有效。
 *   harmonic_u_pct_x100: 当前谐波电压幅值占比，单位 `% x100`。
 *   harmonic_i_pct_x100: 当前谐波电流幅值占比，单位 `% x100`。
 *   harmonic_phase_diff_valid: 当前谐波相位差是否有效。
 *   harmonic_phase_diff_deg_x100: 当前谐波相位差，单位 `deg x100`。
 *   uart_tx_busy: 底层 UART 发送器忙标志。
 *
 * 输出:
 *   uart_tx_en: 向底层 UART 发起单字节发送请求的单周期脉冲。
 *   uart_tx_data: 本拍请求发送的 ASCII 字节。
 */
module uart_measurement_streamer #(
    parameter integer PACKET_WIDTH            = 1086,
    parameter integer CLK_FREQ                = 50000000,
    parameter integer SEND_GAP_CYCLES         = CLK_FREQ / 10,
    parameter integer UART_HARMONIC_MAX_ORDER = 500
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire [PACKET_WIDTH-1:0] text_packet,
    input  wire                    text_packet_commit_toggle,
    input  wire                    harmonic_fire,
    input  wire                    harmonic_last,
    input  wire [8:0]              harmonic_order,
    input  wire                    harmonic_present,
    input  wire [15:0]             harmonic_u_pct_x100,
    input  wire [15:0]             harmonic_i_pct_x100,
    input  wire                    harmonic_phase_diff_valid,
    input  wire signed [15:0]      harmonic_phase_diff_deg_x100,
    input  wire                    uart_tx_busy,
    output reg                     uart_tx_en,
    output reg  [7:0]              uart_tx_data
);

localparam [4:0] ST_IDLE            = 5'd0;
localparam [4:0] ST_SEND_P2P        = 5'd1;
localparam [4:0] ST_SEND_RMS        = 5'd2;
localparam [4:0] ST_SEND_PA         = 5'd3;
localparam [4:0] ST_SEND_POWER      = 5'd4;
localparam [4:0] ST_SEND_THD        = 5'd5;
localparam [4:0] ST_SEND_MAG_LABEL  = 5'd6;
localparam [4:0] ST_READ_MAG_WORD   = 5'd7;
localparam [4:0] ST_LATCH_MAG_WORD  = 5'd8;
localparam [4:0] ST_WAIT_MAG_FORMAT = 5'd9;
localparam [4:0] ST_SEND_MAG_VALUE  = 5'd10;
localparam [4:0] ST_SEND_MAG_COMMA  = 5'd11;
localparam [4:0] ST_SEND_MAG_CR     = 5'd12;
localparam [4:0] ST_SEND_MAG_LF     = 5'd13;
localparam [4:0] ST_SEND_PH_LABEL   = 5'd14;
localparam [4:0] ST_READ_PH_WORD    = 5'd15;
localparam [4:0] ST_LATCH_PH_WORD   = 5'd16;
localparam [4:0] ST_WAIT_PH_FORMAT  = 5'd17;
localparam [4:0] ST_SEND_PH_VALUE   = 5'd18;
localparam [4:0] ST_SEND_PH_COMMA   = 5'd19;
localparam [4:0] ST_SEND_PH_CR      = 5'd20;
localparam [4:0] ST_SEND_PH_LF      = 5'd21;
localparam [4:0] ST_COOLDOWN        = 5'd22;

localparam integer EFFECTIVE_SEND_GAP_CYCLES = (SEND_GAP_CYCLES < 1) ? 1 : SEND_GAP_CYCLES;
localparam integer P2P_LINE_BYTES            = 19;
localparam integer RMS_LINE_BYTES            = 19;
localparam integer PA_LINE_BYTES             = 12;
localparam integer POWER_LINE_BYTES          = 32;
localparam integer THD_LINE_BYTES            = 19;
localparam integer MAG_VALUE_BYTES           = 6;
localparam integer PH_VALUE_BYTES            = 8;
localparam integer SUMMARY_WIDTH             = 439;

localparam [8:0] CAPTURE_START_ORDER        = 9'd0;
localparam [8:0] UART_HARMONIC_FIRST_ORDER  = 9'd1;
localparam [8:0] UART_HARMONIC_MAX_ORDER_9B = UART_HARMONIC_MAX_ORDER;

localparam integer HARMONIC_U_PCT_LSB       = 0;
localparam integer HARMONIC_U_PCT_MSB       = 15;
localparam integer HARMONIC_I_PCT_LSB       = 16;
localparam integer HARMONIC_I_PCT_MSB       = 31;
localparam integer HARMONIC_PHASE_LSB       = 32;
localparam integer HARMONIC_PHASE_MSB       = 47;
localparam integer HARMONIC_PHASE_VALID_BIT = 48;
localparam integer HARMONIC_WORD_WIDTH      = 49;

localparam integer SUMMARY_THD_I_LSB        = 0;
localparam integer SUMMARY_THD_I_MSB        = 40;
localparam integer SUMMARY_THD_U_LSB        = 41;
localparam integer SUMMARY_THD_U_MSB        = 81;
localparam integer SUMMARY_PF_LSB           = 82;
localparam integer SUMMARY_PF_MSB           = 107;
localparam integer SUMMARY_APPARENT_S_LSB   = 108;
localparam integer SUMMARY_APPARENT_S_MSB   = 148;
localparam integer SUMMARY_REACTIVE_Q_LSB   = 149;
localparam integer SUMMARY_REACTIVE_Q_MSB   = 190;
localparam integer SUMMARY_ACTIVE_P_LSB     = 191;
localparam integer SUMMARY_ACTIVE_P_MSB     = 232;
localparam integer SUMMARY_I_PP_LSB         = 233;
localparam integer SUMMARY_I_PP_MSB         = 273;
localparam integer SUMMARY_U_PP_LSB         = 274;
localparam integer SUMMARY_U_PP_MSB         = 314;
localparam integer SUMMARY_PHASE_LSB        = 315;
localparam integer SUMMARY_PHASE_MSB        = 356;
localparam integer SUMMARY_I_RMS_LSB        = 357;
localparam integer SUMMARY_I_RMS_MSB        = 397;
localparam integer SUMMARY_U_RMS_LSB        = 398;
localparam integer SUMMARY_U_RMS_MSB        = 438;

reg  [4:0]                    state;
reg  [5:0]                    line_char_idx;
reg  [2:0]                    value_char_idx;
reg  [8:0]                    harmonic_send_order;
reg                           mag_value_is_i;
reg  [31:0]                   cooldown_cnt;
reg                           capture_active;
reg                           harmonic_frame_ready;
reg                           summary_packet_ready;
reg                           text_packet_commit_toggle_d1;
reg  [SUMMARY_WIDTH-1:0]      pending_summary_packet;
reg  [SUMMARY_WIDTH-1:0]      active_summary_packet;
reg  [HARMONIC_WORD_WIDTH-1:0] current_harmonic_word;
reg                           formatter_start;
reg  [15:0]                   formatter_value_x100;
reg                           harmonic_mem_we;
reg  [8:0]                    harmonic_mem_waddr;
reg  [HARMONIC_WORD_WIDTH-1:0] harmonic_mem_wdata;
reg  [HARMONIC_WORD_WIDTH-1:0] harmonic_mem_dout;

(* ram_style = "block" *) reg [HARMONIC_WORD_WIDTH-1:0] harmonic_mem [0:UART_HARMONIC_MAX_ORDER];

wire                          text_packet_commit_edge;
wire [SUMMARY_WIDTH-1:0]      summary_packet_in;
wire [40:0]                   u_rms_field_snap;
wire [40:0]                   i_rms_field_snap;
wire [41:0]                   phase_field_snap;
wire [40:0]                   u_pp_field_snap;
wire [40:0]                   i_pp_field_snap;
wire [41:0]                   active_p_field_snap;
wire [41:0]                   reactive_q_field_snap;
wire [40:0]                   apparent_s_field_snap;
wire [25:0]                   power_factor_field_snap;
wire [40:0]                   thd_u_field_snap;
wire [40:0]                   thd_i_field_snap;

wire [15:0]                   current_harmonic_u_pct_x100;
wire [15:0]                   current_harmonic_i_pct_x100;
wire signed [15:0]            current_harmonic_phase_diff_deg_x100;
wire                          current_harmonic_phase_valid;
wire                          current_harmonic_phase_neg;
wire [15:0]                   current_harmonic_phase_abs_x100;

wire                          formatter_busy;
wire                          formatter_done;
wire [3:0]                    formatter_hundreds;
wire [3:0]                    formatter_tens;
wire [3:0]                    formatter_units;
wire [3:0]                    formatter_decile;
wire [3:0]                    formatter_percentiles;

// 计算 `deg x100` 的绝对值，用于复用无符号顺序格式化器。
function [15:0] abs_signed16;
    input signed [15:0] value;
    begin
        abs_signed16 = value[15] ? (~value + 16'd1) : value[15:0];
    end
endfunction

// 把一位十进制数字转换成 ASCII 字符。
function [7:0] digit_to_ascii;
    input [3:0] digit_value;
    begin
        digit_to_ascii = 8'd48 + {4'd0, digit_value};
    end
endfunction

// 从 `DDD.DD` 类型的显示字段中取出指定位置字符。
function [7:0] unsigned5_ascii_char;
    input [40:0] field_bus;
    input [2:0]  char_index;
    begin
        case (char_index)
            3'd0: unsigned5_ascii_char = field_bus[0] ? digit_to_ascii(field_bus[36:33]) : "0";
            3'd1: unsigned5_ascii_char = field_bus[0] ? digit_to_ascii(field_bus[28:25]) : "0";
            3'd2: unsigned5_ascii_char = field_bus[0] ? digit_to_ascii(field_bus[20:17]) : "0";
            3'd3: unsigned5_ascii_char = ".";
            3'd4: unsigned5_ascii_char = field_bus[0] ? digit_to_ascii(field_bus[12:9])  : "0";
            default: unsigned5_ascii_char = field_bus[0] ? digit_to_ascii(field_bus[4:1]) : "0";
        endcase
    end
endfunction

// 从 `SDDD.DD` 类型的显示字段中取出指定位置字符。
function [7:0] signed5_ascii_char;
    input [41:0] field_bus;
    input [2:0]  char_index;
    begin
        case (char_index)
            3'd0: signed5_ascii_char = (field_bus[0] && field_bus[41]) ? "-" : "+";
            3'd1: signed5_ascii_char = field_bus[0] ? digit_to_ascii(field_bus[36:33]) : "0";
            3'd2: signed5_ascii_char = field_bus[0] ? digit_to_ascii(field_bus[28:25]) : "0";
            3'd3: signed5_ascii_char = field_bus[0] ? digit_to_ascii(field_bus[20:17]) : "0";
            3'd4: signed5_ascii_char = ".";
            3'd5: signed5_ascii_char = field_bus[0] ? digit_to_ascii(field_bus[12:9])  : "0";
            default: signed5_ascii_char = field_bus[0] ? digit_to_ascii(field_bus[4:1]) : "0";
        endcase
    end
endfunction

// 从 `SX.XX` 类型的功率因数字段中取出指定位置字符。
function [7:0] signed3_ascii_char;
    input [25:0] field_bus;
    input [2:0]  char_index;
    begin
        case (char_index)
            3'd0: signed3_ascii_char = (field_bus[0] && field_bus[25]) ? "-" : "+";
            3'd1: signed3_ascii_char = field_bus[0] ? digit_to_ascii(field_bus[20:17]) : "0";
            3'd2: signed3_ascii_char = ".";
            3'd3: signed3_ascii_char = field_bus[0] ? digit_to_ascii(field_bus[12:9])  : "0";
            default: signed3_ascii_char = field_bus[0] ? digit_to_ascii(field_bus[4:1]) : "0";
        endcase
    end
endfunction

// 按 `DDD.DD` 形式输出共享顺序格式化器拆出的结果。
function [7:0] digits_x100_ascii_char;
    input [3:0] hundreds;
    input [3:0] tens;
    input [3:0] units;
    input [3:0] decile;
    input [3:0] percentiles;
    input [2:0] char_index;
    begin
        case (char_index)
            3'd0: digits_x100_ascii_char = digit_to_ascii(hundreds);
            3'd1: digits_x100_ascii_char = digit_to_ascii(tens);
            3'd2: digits_x100_ascii_char = digit_to_ascii(units);
            3'd3: digits_x100_ascii_char = ".";
            3'd4: digits_x100_ascii_char = digit_to_ascii(decile);
            default: digits_x100_ascii_char = digit_to_ascii(percentiles);
        endcase
    end
endfunction

// 按 `SDDD.DDD` 形式输出共享顺序格式化器拆出的相位差结果，第三位小数固定补 `0`。
function [7:0] signed_phase_ascii_char;
    input       phase_negative;
    input       phase_valid;
    input [3:0] hundreds;
    input [3:0] tens;
    input [3:0] units;
    input [3:0] decile;
    input [3:0] percentiles;
    input [2:0] char_index;
    begin
        case (char_index)
            3'd0: signed_phase_ascii_char = (phase_valid && phase_negative) ? "-" : "+";
            3'd1: signed_phase_ascii_char = phase_valid ? digit_to_ascii(hundreds)    : "0";
            3'd2: signed_phase_ascii_char = phase_valid ? digit_to_ascii(tens)        : "0";
            3'd3: signed_phase_ascii_char = phase_valid ? digit_to_ascii(units)       : "0";
            3'd4: signed_phase_ascii_char = ".";
            3'd5: signed_phase_ascii_char = phase_valid ? digit_to_ascii(decile)      : "0";
            3'd6: signed_phase_ascii_char = phase_valid ? digit_to_ascii(percentiles) : "0";
            default: signed_phase_ascii_char = "0";
        endcase
    end
endfunction

// 从大文本包中抽取 UART 实际要发的字段，避免缓存整包 `1086` bit 数据。
assign summary_packet_in = {
    text_packet[1085:1045],
    text_packet[1044:1004],
    text_packet[1003:962],
    text_packet[920:880],
    text_packet[879:839],
    {text_packet[838:798], text_packet[691]},
    {text_packet[797:757], text_packet[691]},
    {text_packet[756:717], text_packet[691]},
    text_packet[716:691],
    text_packet[687:647],
    text_packet[646:606]
};

// 生成文本提交沿，并把当前发送快照拆回字段视图供 ASCII 状态机直接取字。
assign text_packet_commit_edge = text_packet_commit_toggle ^ text_packet_commit_toggle_d1;
assign u_rms_field_snap        = active_summary_packet[SUMMARY_U_RMS_MSB:SUMMARY_U_RMS_LSB];
assign i_rms_field_snap        = active_summary_packet[SUMMARY_I_RMS_MSB:SUMMARY_I_RMS_LSB];
assign phase_field_snap        = active_summary_packet[SUMMARY_PHASE_MSB:SUMMARY_PHASE_LSB];
assign u_pp_field_snap         = active_summary_packet[SUMMARY_U_PP_MSB:SUMMARY_U_PP_LSB];
assign i_pp_field_snap         = active_summary_packet[SUMMARY_I_PP_MSB:SUMMARY_I_PP_LSB];
assign active_p_field_snap     = active_summary_packet[SUMMARY_ACTIVE_P_MSB:SUMMARY_ACTIVE_P_LSB];
assign reactive_q_field_snap   = active_summary_packet[SUMMARY_REACTIVE_Q_MSB:SUMMARY_REACTIVE_Q_LSB];
assign apparent_s_field_snap   = active_summary_packet[SUMMARY_APPARENT_S_MSB:SUMMARY_APPARENT_S_LSB];
assign power_factor_field_snap = active_summary_packet[SUMMARY_PF_MSB:SUMMARY_PF_LSB];
assign thd_u_field_snap        = active_summary_packet[SUMMARY_THD_U_MSB:SUMMARY_THD_U_LSB];
assign thd_i_field_snap        = active_summary_packet[SUMMARY_THD_I_MSB:SUMMARY_THD_I_LSB];

// 把当前谐波缓存字拆成幅值与相位字段，供发送控制和共享格式化器复用。
assign current_harmonic_u_pct_x100          = current_harmonic_word[HARMONIC_U_PCT_MSB:HARMONIC_U_PCT_LSB];
assign current_harmonic_i_pct_x100          = current_harmonic_word[HARMONIC_I_PCT_MSB:HARMONIC_I_PCT_LSB];
assign current_harmonic_phase_diff_deg_x100 = current_harmonic_word[HARMONIC_PHASE_MSB:HARMONIC_PHASE_LSB];
assign current_harmonic_phase_valid         = current_harmonic_word[HARMONIC_PHASE_VALID_BIT];
assign current_harmonic_phase_neg           = current_harmonic_phase_valid && current_harmonic_phase_diff_deg_x100[15];
assign current_harmonic_phase_abs_x100      =
    current_harmonic_phase_valid ? abs_signed16(current_harmonic_phase_diff_deg_x100) : 16'd0;

// 使用单个顺序格式化器按需拆位谐波幅值与相位差，替代原来的三个并行组合拆位实例。
uart_value_x100_formatter u_uart_value_x100_formatter (
    .clk         (clk),
    .rst_n       (rst_n),
    .start       (formatter_start),
    .value_x100  (formatter_value_x100),
    .busy        (formatter_busy),
    .done        (formatter_done),
    .hundreds    (formatter_hundreds),
    .tens        (formatter_tens),
    .units       (formatter_units),
    .decile      (formatter_decile),
    .percentiles (formatter_percentiles)
);

// 以 BRAM 风格时分读写谐波缓存：空闲/冷却阶段写入完整新帧，发送阶段按阶次顺序同步读出。
always @(posedge clk) begin
    if (harmonic_mem_we)
        harmonic_mem[harmonic_mem_waddr] <= harmonic_mem_wdata;

    harmonic_mem_dout <= harmonic_mem[harmonic_send_order];
end

// 串行组织文本快照、谐波缓存和共享格式化器的握手，只在完整帧就绪后启动 UART 发送。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state                        <= ST_IDLE;
        line_char_idx                <= 6'd0;
        value_char_idx               <= 3'd0;
        harmonic_send_order          <= UART_HARMONIC_FIRST_ORDER;
        mag_value_is_i               <= 1'b0;
        cooldown_cnt                 <= 32'd0;
        capture_active               <= 1'b0;
        harmonic_frame_ready         <= 1'b0;
        summary_packet_ready         <= 1'b0;
        text_packet_commit_toggle_d1 <= 1'b0;
        pending_summary_packet       <= {SUMMARY_WIDTH{1'b0}};
        active_summary_packet        <= {SUMMARY_WIDTH{1'b0}};
        current_harmonic_word        <= {HARMONIC_WORD_WIDTH{1'b0}};
        formatter_start              <= 1'b0;
        formatter_value_x100         <= 16'd0;
        harmonic_mem_we              <= 1'b0;
        harmonic_mem_waddr           <= 9'd0;
        harmonic_mem_wdata           <= {HARMONIC_WORD_WIDTH{1'b0}};
        uart_tx_en                   <= 1'b0;
        uart_tx_data                 <= 8'h00;
    end else begin
        uart_tx_en                   <= 1'b0;
        formatter_start              <= 1'b0;
        harmonic_mem_we              <= 1'b0;
        text_packet_commit_toggle_d1 <= text_packet_commit_toggle;

        if (text_packet_commit_edge) begin
            pending_summary_packet <= summary_packet_in;
            summary_packet_ready   <= 1'b1;
        end

        if (((state == ST_IDLE) || (state == ST_COOLDOWN)) && harmonic_fire) begin
            if (harmonic_order == CAPTURE_START_ORDER)
                capture_active <= 1'b1;

            if ((capture_active || (harmonic_order == CAPTURE_START_ORDER)) &&
                (harmonic_order <= UART_HARMONIC_MAX_ORDER_9B)) begin
                harmonic_mem_we    <= 1'b1;
                harmonic_mem_waddr <= harmonic_order;
                harmonic_mem_wdata <= harmonic_present ? {
                    harmonic_phase_diff_valid,
                    harmonic_phase_diff_valid ? harmonic_phase_diff_deg_x100 : 16'sd0,
                    harmonic_i_pct_x100,
                    harmonic_u_pct_x100
                } : {HARMONIC_WORD_WIDTH{1'b0}};
            end

            if (harmonic_last && (capture_active || (harmonic_order == CAPTURE_START_ORDER))) begin
                capture_active       <= 1'b0;
                harmonic_frame_ready <= 1'b1;
            end
        end

        case (state)
            ST_IDLE: begin
                if (summary_packet_ready && harmonic_frame_ready) begin
                    active_summary_packet <= text_packet_commit_edge ? summary_packet_in : pending_summary_packet;
                    line_char_idx         <= 6'd0;
                    value_char_idx        <= 3'd0;
                    harmonic_send_order   <= UART_HARMONIC_FIRST_ORDER;
                    mag_value_is_i        <= 1'b0;
                    cooldown_cnt          <= 32'd0;
                    harmonic_frame_ready  <= 1'b0;
                    state                 <= ST_SEND_P2P;
                end
            end

            ST_SEND_P2P: begin
                if (!uart_tx_busy) begin
                    uart_tx_en <= 1'b1;
                    case (line_char_idx)
                        6'd0:  uart_tx_data <= "p";
                        6'd1:  uart_tx_data <= "2";
                        6'd2:  uart_tx_data <= "p";
                        6'd3:  uart_tx_data <= ":";
                        6'd4:  uart_tx_data <= unsigned5_ascii_char(u_pp_field_snap, 3'd0);
                        6'd5:  uart_tx_data <= unsigned5_ascii_char(u_pp_field_snap, 3'd1);
                        6'd6:  uart_tx_data <= unsigned5_ascii_char(u_pp_field_snap, 3'd2);
                        6'd7:  uart_tx_data <= unsigned5_ascii_char(u_pp_field_snap, 3'd3);
                        6'd8:  uart_tx_data <= unsigned5_ascii_char(u_pp_field_snap, 3'd4);
                        6'd9:  uart_tx_data <= unsigned5_ascii_char(u_pp_field_snap, 3'd5);
                        6'd10: uart_tx_data <= ",";
                        6'd11: uart_tx_data <= unsigned5_ascii_char(i_pp_field_snap, 3'd0);
                        6'd12: uart_tx_data <= unsigned5_ascii_char(i_pp_field_snap, 3'd1);
                        6'd13: uart_tx_data <= unsigned5_ascii_char(i_pp_field_snap, 3'd2);
                        6'd14: uart_tx_data <= unsigned5_ascii_char(i_pp_field_snap, 3'd3);
                        6'd15: uart_tx_data <= unsigned5_ascii_char(i_pp_field_snap, 3'd4);
                        6'd16: uart_tx_data <= unsigned5_ascii_char(i_pp_field_snap, 3'd5);
                        6'd17: uart_tx_data <= 8'h0D;
                        default: uart_tx_data <= 8'h0A;
                    endcase

                    if (line_char_idx == (P2P_LINE_BYTES - 1)) begin
                        line_char_idx <= 6'd0;
                        state         <= ST_SEND_RMS;
                    end else begin
                        line_char_idx <= line_char_idx + 6'd1;
                    end
                end
            end

            ST_SEND_RMS: begin
                if (!uart_tx_busy) begin
                    uart_tx_en <= 1'b1;
                    case (line_char_idx)
                        6'd0:  uart_tx_data <= "r";
                        6'd1:  uart_tx_data <= "m";
                        6'd2:  uart_tx_data <= "s";
                        6'd3:  uart_tx_data <= ":";
                        6'd4:  uart_tx_data <= unsigned5_ascii_char(u_rms_field_snap, 3'd0);
                        6'd5:  uart_tx_data <= unsigned5_ascii_char(u_rms_field_snap, 3'd1);
                        6'd6:  uart_tx_data <= unsigned5_ascii_char(u_rms_field_snap, 3'd2);
                        6'd7:  uart_tx_data <= unsigned5_ascii_char(u_rms_field_snap, 3'd3);
                        6'd8:  uart_tx_data <= unsigned5_ascii_char(u_rms_field_snap, 3'd4);
                        6'd9:  uart_tx_data <= unsigned5_ascii_char(u_rms_field_snap, 3'd5);
                        6'd10: uart_tx_data <= ",";
                        6'd11: uart_tx_data <= unsigned5_ascii_char(i_rms_field_snap, 3'd0);
                        6'd12: uart_tx_data <= unsigned5_ascii_char(i_rms_field_snap, 3'd1);
                        6'd13: uart_tx_data <= unsigned5_ascii_char(i_rms_field_snap, 3'd2);
                        6'd14: uart_tx_data <= unsigned5_ascii_char(i_rms_field_snap, 3'd3);
                        6'd15: uart_tx_data <= unsigned5_ascii_char(i_rms_field_snap, 3'd4);
                        6'd16: uart_tx_data <= unsigned5_ascii_char(i_rms_field_snap, 3'd5);
                        6'd17: uart_tx_data <= 8'h0D;
                        default: uart_tx_data <= 8'h0A;
                    endcase

                    if (line_char_idx == (RMS_LINE_BYTES - 1)) begin
                        line_char_idx <= 6'd0;
                        state         <= ST_SEND_PA;
                    end else begin
                        line_char_idx <= line_char_idx + 6'd1;
                    end
                end
            end

            ST_SEND_PA: begin
                if (!uart_tx_busy) begin
                    uart_tx_en <= 1'b1;
                    case (line_char_idx)
                        6'd0:  uart_tx_data <= "p";
                        6'd1:  uart_tx_data <= "a";
                        6'd2:  uart_tx_data <= ":";
                        6'd3:  uart_tx_data <= signed5_ascii_char(phase_field_snap, 3'd0);
                        6'd4:  uart_tx_data <= signed5_ascii_char(phase_field_snap, 3'd1);
                        6'd5:  uart_tx_data <= signed5_ascii_char(phase_field_snap, 3'd2);
                        6'd6:  uart_tx_data <= signed5_ascii_char(phase_field_snap, 3'd3);
                        6'd7:  uart_tx_data <= signed5_ascii_char(phase_field_snap, 3'd4);
                        6'd8:  uart_tx_data <= signed5_ascii_char(phase_field_snap, 3'd5);
                        6'd9:  uart_tx_data <= signed5_ascii_char(phase_field_snap, 3'd6);
                        6'd10: uart_tx_data <= 8'h0D;
                        default: uart_tx_data <= 8'h0A;
                    endcase

                    if (line_char_idx == (PA_LINE_BYTES - 1)) begin
                        line_char_idx <= 6'd0;
                        state         <= ST_SEND_POWER;
                    end else begin
                        line_char_idx <= line_char_idx + 6'd1;
                    end
                end
            end

            ST_SEND_POWER: begin
                if (!uart_tx_busy) begin
                    uart_tx_en <= 1'b1;
                    case (line_char_idx)
                        6'd0:  uart_tx_data <= "p";
                        6'd1:  uart_tx_data <= ":";
                        6'd2:  uart_tx_data <= signed5_ascii_char(active_p_field_snap, 3'd0);
                        6'd3:  uart_tx_data <= signed5_ascii_char(active_p_field_snap, 3'd1);
                        6'd4:  uart_tx_data <= signed5_ascii_char(active_p_field_snap, 3'd2);
                        6'd5:  uart_tx_data <= signed5_ascii_char(active_p_field_snap, 3'd3);
                        6'd6:  uart_tx_data <= signed5_ascii_char(active_p_field_snap, 3'd4);
                        6'd7:  uart_tx_data <= signed5_ascii_char(active_p_field_snap, 3'd5);
                        6'd8:  uart_tx_data <= signed5_ascii_char(active_p_field_snap, 3'd6);
                        6'd9:  uart_tx_data <= ",";
                        6'd10: uart_tx_data <= signed5_ascii_char(reactive_q_field_snap, 3'd0);
                        6'd11: uart_tx_data <= signed5_ascii_char(reactive_q_field_snap, 3'd1);
                        6'd12: uart_tx_data <= signed5_ascii_char(reactive_q_field_snap, 3'd2);
                        6'd13: uart_tx_data <= signed5_ascii_char(reactive_q_field_snap, 3'd3);
                        6'd14: uart_tx_data <= signed5_ascii_char(reactive_q_field_snap, 3'd4);
                        6'd15: uart_tx_data <= signed5_ascii_char(reactive_q_field_snap, 3'd5);
                        6'd16: uart_tx_data <= signed5_ascii_char(reactive_q_field_snap, 3'd6);
                        6'd17: uart_tx_data <= ",";
                        6'd18: uart_tx_data <= unsigned5_ascii_char(apparent_s_field_snap, 3'd0);
                        6'd19: uart_tx_data <= unsigned5_ascii_char(apparent_s_field_snap, 3'd1);
                        6'd20: uart_tx_data <= unsigned5_ascii_char(apparent_s_field_snap, 3'd2);
                        6'd21: uart_tx_data <= unsigned5_ascii_char(apparent_s_field_snap, 3'd3);
                        6'd22: uart_tx_data <= unsigned5_ascii_char(apparent_s_field_snap, 3'd4);
                        6'd23: uart_tx_data <= unsigned5_ascii_char(apparent_s_field_snap, 3'd5);
                        6'd24: uart_tx_data <= ",";
                        6'd25: uart_tx_data <= signed3_ascii_char(power_factor_field_snap, 3'd0);
                        6'd26: uart_tx_data <= signed3_ascii_char(power_factor_field_snap, 3'd1);
                        6'd27: uart_tx_data <= signed3_ascii_char(power_factor_field_snap, 3'd2);
                        6'd28: uart_tx_data <= signed3_ascii_char(power_factor_field_snap, 3'd3);
                        6'd29: uart_tx_data <= signed3_ascii_char(power_factor_field_snap, 3'd4);
                        6'd30: uart_tx_data <= 8'h0D;
                        default: uart_tx_data <= 8'h0A;
                    endcase

                    if (line_char_idx == (POWER_LINE_BYTES - 1)) begin
                        line_char_idx <= 6'd0;
                        state         <= ST_SEND_THD;
                    end else begin
                        line_char_idx <= line_char_idx + 6'd1;
                    end
                end
            end

            ST_SEND_THD: begin
                if (!uart_tx_busy) begin
                    uart_tx_en <= 1'b1;
                    case (line_char_idx)
                        6'd0:  uart_tx_data <= "T";
                        6'd1:  uart_tx_data <= "H";
                        6'd2:  uart_tx_data <= "D";
                        6'd3:  uart_tx_data <= ":";
                        6'd4:  uart_tx_data <= unsigned5_ascii_char(thd_u_field_snap, 3'd0);
                        6'd5:  uart_tx_data <= unsigned5_ascii_char(thd_u_field_snap, 3'd1);
                        6'd6:  uart_tx_data <= unsigned5_ascii_char(thd_u_field_snap, 3'd2);
                        6'd7:  uart_tx_data <= unsigned5_ascii_char(thd_u_field_snap, 3'd3);
                        6'd8:  uart_tx_data <= unsigned5_ascii_char(thd_u_field_snap, 3'd4);
                        6'd9:  uart_tx_data <= unsigned5_ascii_char(thd_u_field_snap, 3'd5);
                        6'd10: uart_tx_data <= ",";
                        6'd11: uart_tx_data <= unsigned5_ascii_char(thd_i_field_snap, 3'd0);
                        6'd12: uart_tx_data <= unsigned5_ascii_char(thd_i_field_snap, 3'd1);
                        6'd13: uart_tx_data <= unsigned5_ascii_char(thd_i_field_snap, 3'd2);
                        6'd14: uart_tx_data <= unsigned5_ascii_char(thd_i_field_snap, 3'd3);
                        6'd15: uart_tx_data <= unsigned5_ascii_char(thd_i_field_snap, 3'd4);
                        6'd16: uart_tx_data <= unsigned5_ascii_char(thd_i_field_snap, 3'd5);
                        6'd17: uart_tx_data <= 8'h0D;
                        default: uart_tx_data <= 8'h0A;
                    endcase

                    if (line_char_idx == (THD_LINE_BYTES - 1)) begin
                        line_char_idx      <= 6'd0;
                        harmonic_send_order <= UART_HARMONIC_FIRST_ORDER;
                        mag_value_is_i     <= 1'b0;
                        state              <= ST_SEND_MAG_LABEL;
                    end else begin
                        line_char_idx <= line_char_idx + 6'd1;
                    end
                end
            end

            ST_SEND_MAG_LABEL: begin
                if (!uart_tx_busy) begin
                    uart_tx_en <= 1'b1;
                    case (line_char_idx)
                        6'd0: uart_tx_data <= "M";
                        6'd1: uart_tx_data <= "a";
                        6'd2: uart_tx_data <= "g";
                        default: uart_tx_data <= ":";
                    endcase

                    if (line_char_idx == 6'd3) begin
                        line_char_idx <= 6'd0;
                        state         <= ST_READ_MAG_WORD;
                    end else begin
                        line_char_idx <= line_char_idx + 6'd1;
                    end
                end
            end

            ST_READ_MAG_WORD: begin
                state <= ST_LATCH_MAG_WORD;
            end

            ST_LATCH_MAG_WORD: begin
                current_harmonic_word <= harmonic_mem_dout;
                formatter_value_x100  <= mag_value_is_i
                    ? harmonic_mem_dout[HARMONIC_I_PCT_MSB:HARMONIC_I_PCT_LSB]
                    : harmonic_mem_dout[HARMONIC_U_PCT_MSB:HARMONIC_U_PCT_LSB];
                formatter_start       <= 1'b1;
                value_char_idx        <= 3'd0;
                state                 <= ST_WAIT_MAG_FORMAT;
            end

            ST_WAIT_MAG_FORMAT: begin
                if (formatter_done)
                    state <= ST_SEND_MAG_VALUE;
            end

            ST_SEND_MAG_VALUE: begin
                if (!uart_tx_busy) begin
                    uart_tx_en   <= 1'b1;
                    uart_tx_data <= digits_x100_ascii_char(
                        formatter_hundreds,
                        formatter_tens,
                        formatter_units,
                        formatter_decile,
                        formatter_percentiles,
                        value_char_idx
                    );

                    if (value_char_idx == (MAG_VALUE_BYTES - 1)) begin
                        if ((harmonic_send_order == UART_HARMONIC_MAX_ORDER_9B) && mag_value_is_i)
                            state <= ST_SEND_MAG_CR;
                        else
                            state <= ST_SEND_MAG_COMMA;
                    end else begin
                        value_char_idx <= value_char_idx + 3'd1;
                    end
                end
            end

            ST_SEND_MAG_COMMA: begin
                if (!uart_tx_busy) begin
                    uart_tx_en   <= 1'b1;
                    uart_tx_data <= ",";

                    if (!mag_value_is_i) begin
                        mag_value_is_i      <= 1'b1;
                        formatter_value_x100 <= current_harmonic_i_pct_x100;
                        formatter_start     <= 1'b1;
                        value_char_idx      <= 3'd0;
                        state               <= ST_WAIT_MAG_FORMAT;
                    end else begin
                        mag_value_is_i      <= 1'b0;
                        harmonic_send_order <= harmonic_send_order + 9'd1;
                        state               <= ST_READ_MAG_WORD;
                    end
                end
            end

            ST_SEND_MAG_CR: begin
                if (!uart_tx_busy) begin
                    uart_tx_en   <= 1'b1;
                    uart_tx_data <= 8'h0D;
                    state        <= ST_SEND_MAG_LF;
                end
            end

            ST_SEND_MAG_LF: begin
                if (!uart_tx_busy) begin
                    uart_tx_en          <= 1'b1;
                    uart_tx_data        <= 8'h0A;
                    line_char_idx       <= 6'd0;
                    harmonic_send_order <= UART_HARMONIC_FIRST_ORDER;
                    state               <= ST_SEND_PH_LABEL;
                end
            end

            ST_SEND_PH_LABEL: begin
                if (!uart_tx_busy) begin
                    uart_tx_en <= 1'b1;
                    case (line_char_idx)
                        6'd0: uart_tx_data <= "P";
                        6'd1: uart_tx_data <= "h";
                        default: uart_tx_data <= ":";
                    endcase

                    if (line_char_idx == 6'd2) begin
                        line_char_idx <= 6'd0;
                        state         <= ST_READ_PH_WORD;
                    end else begin
                        line_char_idx <= line_char_idx + 6'd1;
                    end
                end
            end

            ST_READ_PH_WORD: begin
                state <= ST_LATCH_PH_WORD;
            end

            ST_LATCH_PH_WORD: begin
                current_harmonic_word <= harmonic_mem_dout;
                formatter_value_x100  <= harmonic_mem_dout[HARMONIC_PHASE_VALID_BIT]
                    ? abs_signed16(harmonic_mem_dout[HARMONIC_PHASE_MSB:HARMONIC_PHASE_LSB])
                    : 16'd0;
                formatter_start       <= 1'b1;
                value_char_idx        <= 3'd0;
                state                 <= ST_WAIT_PH_FORMAT;
            end

            ST_WAIT_PH_FORMAT: begin
                if (formatter_done)
                    state <= ST_SEND_PH_VALUE;
            end

            ST_SEND_PH_VALUE: begin
                if (!uart_tx_busy) begin
                    uart_tx_en   <= 1'b1;
                    uart_tx_data <= signed_phase_ascii_char(
                        current_harmonic_phase_neg,
                        current_harmonic_phase_valid,
                        formatter_hundreds,
                        formatter_tens,
                        formatter_units,
                        formatter_decile,
                        formatter_percentiles,
                        value_char_idx
                    );

                    if (value_char_idx == (PH_VALUE_BYTES - 1)) begin
                        if (harmonic_send_order == UART_HARMONIC_MAX_ORDER_9B)
                            state <= ST_SEND_PH_CR;
                        else
                            state <= ST_SEND_PH_COMMA;
                    end else begin
                        value_char_idx <= value_char_idx + 3'd1;
                    end
                end
            end

            ST_SEND_PH_COMMA: begin
                if (!uart_tx_busy) begin
                    uart_tx_en          <= 1'b1;
                    uart_tx_data        <= ",";
                    harmonic_send_order <= harmonic_send_order + 9'd1;
                    state               <= ST_READ_PH_WORD;
                end
            end

            ST_SEND_PH_CR: begin
                if (!uart_tx_busy) begin
                    uart_tx_en   <= 1'b1;
                    uart_tx_data <= 8'h0D;
                    state        <= ST_SEND_PH_LF;
                end
            end

            ST_SEND_PH_LF: begin
                if (!uart_tx_busy) begin
                    uart_tx_en   <= 1'b1;
                    uart_tx_data <= 8'h0A;
                    cooldown_cnt <= 32'd0;
                    state        <= ST_COOLDOWN;
                end
            end

            ST_COOLDOWN: begin
                if (cooldown_cnt == (EFFECTIVE_SEND_GAP_CYCLES - 1)) begin
                    cooldown_cnt <= 32'd0;
                    state        <= ST_IDLE;
                end else begin
                    cooldown_cnt <= cooldown_cnt + 32'd1;
                end
            end

            default: begin
                state <= ST_IDLE;
            end
        endcase
    end
end

endmodule
