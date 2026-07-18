`timescale 1ns / 1ps

/*
 * 模块: freq_text_display_preprocess
 * 功能:
 *   锁存最新频域 raw 指标，并在 LCD 帧完成事件到来后顺序完成 x100 规整、数字位拆分，
 *   以及 DH-U/DH-I 列表字符串格式化。
 *   其中 DH-U/DH-I 直接输出 25 字符 ASCII 总线，格式为 `DH-U: xxx,yyy,zzz,...`。
 * 输入:
 *   clk: 文本预处理时钟。
 *   rst_n: 低有效复位。
 *   lcd_frame_done_toggle: LCD 一帧绘制完成后的 toggle 事件。
 *   lcd_swap_ack_toggle: 文本结果切换应答 toggle，同步保留给显示握手链路使用。
 *   raw_result_commit_toggle: 一帧频域 raw 指标提交后的翻转事件。
 *   thd_u_raw_x100: 电压 THD raw。
 *   thd_i_raw_x100: 电流 THD raw。
 *   u1_mag_raw_x100: 电压基波占比 raw。
 *   i1_mag_raw_x100: 电流基波占比 raw。
 *   phase1_raw_x100: 基波相位差 raw。
 *   dc_u_raw_x100: 电压 DC 占比 raw。
 *   dc_i_raw_x100: 电流 DC 占比 raw。
 *   dh_order_u_valid_in: 电压 DH 列表是否有效。
 *   dh_order_i_valid_in: 电流 DH 列表是否有效。
 *   dh_order_u_list_raw: 电压前五大谐波次数列表。
 *   dh_order_i_list_raw: 电流前五大谐波次数列表。
 *   dh_order_u_count_raw: 电压列表有效项数量。
 *   dh_order_i_count_raw: 电流列表有效项数量。
 * 输出:
 *   freq_text_result_commit_toggle: 一批频域文本结果提交后翻转一次。
 *   其余 digit/valid 输出: 供 LCD 文本层直接显示的数值字段。
 *   dh_order_u_text: 电压 DH 文本整行 ASCII。
 *   dh_order_i_text: 电流 DH 文本整行 ASCII。
 */
module freq_text_display_preprocess (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               lcd_frame_done_toggle,
    input  wire               lcd_swap_ack_toggle,
    input  wire               raw_result_commit_toggle,
    input  wire [31:0]        thd_u_raw_x100,
    input  wire [31:0]        thd_i_raw_x100,
    input  wire               thd_u_valid_in,
    input  wire               thd_i_valid_in,
    input  wire [31:0]        u1_mag_raw_x100,
    input  wire [31:0]        i1_mag_raw_x100,
    input  wire               u1_mag_valid_in,
    input  wire               i1_mag_valid_in,
    input  wire signed [31:0] phase1_raw_x100,
    input  wire               phase1_valid_in,
    input  wire [31:0]        dc_u_raw_x100,
    input  wire [31:0]        dc_i_raw_x100,
    input  wire               dc_u_valid_in,
    input  wire               dc_i_valid_in,
    input  wire               dh_order_u_valid_in,
    input  wire               dh_order_i_valid_in,
    input  wire [44:0]        dh_order_u_list_raw,
    input  wire [44:0]        dh_order_i_list_raw,
    input  wire [2:0]         dh_order_u_count_raw,
    input  wire [2:0]         dh_order_i_count_raw,
    output reg                freq_text_result_commit_toggle,
    output reg  [7:0]         thd_u_hundreds,
    output reg  [7:0]         thd_u_tens,
    output reg  [7:0]         thd_u_units,
    output reg  [7:0]         thd_u_decile,
    output reg  [7:0]         thd_u_percentiles,
    output reg                thd_u_valid,
    output reg  [7:0]         thd_i_hundreds,
    output reg  [7:0]         thd_i_tens,
    output reg  [7:0]         thd_i_units,
    output reg  [7:0]         thd_i_decile,
    output reg  [7:0]         thd_i_percentiles,
    output reg                thd_i_valid,
    output reg  [7:0]         u1_mag_hundreds,
    output reg  [7:0]         u1_mag_tens,
    output reg  [7:0]         u1_mag_units,
    output reg  [7:0]         u1_mag_decile,
    output reg  [7:0]         u1_mag_percentiles,
    output reg                u1_mag_valid,
    output reg  [7:0]         i1_mag_hundreds,
    output reg  [7:0]         i1_mag_tens,
    output reg  [7:0]         i1_mag_units,
    output reg  [7:0]         i1_mag_decile,
    output reg  [7:0]         i1_mag_percentiles,
    output reg                i1_mag_valid,
    output reg                phase1_neg,
    output reg  [7:0]         phase1_hundreds,
    output reg  [7:0]         phase1_tens,
    output reg  [7:0]         phase1_units,
    output reg  [7:0]         phase1_decile,
    output reg  [7:0]         phase1_percentiles,
    output reg                phase1_valid,
    output reg  [7:0]         dc_u_hundreds,
    output reg  [7:0]         dc_u_tens,
    output reg  [7:0]         dc_u_units,
    output reg  [7:0]         dc_u_decile,
    output reg  [7:0]         dc_u_percentiles,
    output reg                dc_u_valid,
    output reg  [7:0]         dc_i_hundreds,
    output reg  [7:0]         dc_i_tens,
    output reg  [7:0]         dc_i_units,
    output reg  [7:0]         dc_i_decile,
    output reg  [7:0]         dc_i_percentiles,
    output reg                dc_i_valid,
    output reg  [199:0]       dh_order_u_text,
    output reg  [199:0]       dh_order_i_text
);

localparam [2:0] ST_WAIT_FRAME      = 3'd0;
localparam [2:0] ST_START_X100      = 3'd1;
localparam [2:0] ST_WAIT_X100       = 3'd2;
localparam [2:0] ST_START_SEPARATOR = 3'd3;
localparam [2:0] ST_WAIT_SEPARATOR  = 3'd4;
localparam [2:0] ST_COMMIT          = 3'd5;

reg [2:0] state;
reg       frame_toggle_sync1;
reg       frame_toggle_sync2;
reg       frame_toggle_sync3;
reg       swap_ack_sync1;
reg       swap_ack_sync2;
reg       swap_ack_sync3;
reg       raw_commit_sync1;
reg       raw_commit_sync2;
reg       raw_commit_sync3;
reg       x100_start;
reg       separator_start;
reg       raw_pending_valid;
reg [31:0]        thd_u_raw_pending;
reg [31:0]        thd_i_raw_pending;
reg               thd_u_valid_pending;
reg               thd_i_valid_pending;
reg [31:0]        u1_mag_raw_pending;
reg [31:0]        i1_mag_raw_pending;
reg               u1_mag_valid_pending;
reg               i1_mag_valid_pending;
reg signed [31:0] phase1_raw_pending;
reg               phase1_valid_pending;
reg [31:0]        dc_u_raw_pending;
reg [31:0]        dc_i_raw_pending;
reg               dc_u_valid_pending;
reg               dc_i_valid_pending;
reg               dh_order_u_valid_pending;
reg               dh_order_i_valid_pending;
reg [44:0]        dh_order_u_list_pending;
reg [44:0]        dh_order_i_list_pending;
reg [2:0]         dh_order_u_count_pending;
reg [2:0]         dh_order_i_count_pending;
reg [31:0]        thd_u_raw_active;
reg [31:0]        thd_i_raw_active;
reg               thd_u_valid_active;
reg               thd_i_valid_active;
reg [31:0]        u1_mag_raw_active;
reg [31:0]        i1_mag_raw_active;
reg               u1_mag_valid_active;
reg               i1_mag_valid_active;
reg signed [31:0] phase1_raw_active;
reg               phase1_valid_active;
reg [31:0]        dc_u_raw_active;
reg [31:0]        dc_i_raw_active;
reg               dc_u_valid_active;
reg               dc_i_valid_active;
reg               dh_order_u_valid_active;
reg               dh_order_i_valid_active;
reg [44:0]        dh_order_u_list_active;
reg [44:0]        dh_order_i_list_active;
reg [2:0]         dh_order_u_count_active;
reg [2:0]         dh_order_i_count_active;

// 对 LCD 帧完成和频域 raw 提交 toggle 做边沿检测，控制频域文字链按帧启动一次处理。
wire        frame_edge_wave;
wire        raw_commit_edge;
wire        x100_done;
wire        separator_done;
wire [31:0] thd_u_x100_wire;
wire [31:0] thd_i_x100_wire;
wire        thd_u_valid_x100;
wire        thd_i_valid_x100;
wire [31:0] u1_mag_x100_wire;
wire [31:0] i1_mag_x100_wire;
wire        u1_mag_valid_x100;
wire        i1_mag_valid_x100;
wire signed [31:0] phase1_x100_wire;
wire        phase1_valid_x100;
wire [31:0] dc_u_x100_wire;
wire [31:0] dc_i_x100_wire;
wire        dc_u_valid_x100;
wire        dc_i_valid_x100;
wire [7:0]  thd_u_hundreds_sep;
wire [7:0]  thd_u_tens_sep;
wire [7:0]  thd_u_units_sep;
wire [7:0]  thd_u_decile_sep;
wire [7:0]  thd_u_percentiles_sep;
wire        thd_u_valid_sep;
wire [7:0]  thd_i_hundreds_sep;
wire [7:0]  thd_i_tens_sep;
wire [7:0]  thd_i_units_sep;
wire [7:0]  thd_i_decile_sep;
wire [7:0]  thd_i_percentiles_sep;
wire        thd_i_valid_sep;
wire [7:0]  u1_mag_hundreds_sep;
wire [7:0]  u1_mag_tens_sep;
wire [7:0]  u1_mag_units_sep;
wire [7:0]  u1_mag_decile_sep;
wire [7:0]  u1_mag_percentiles_sep;
wire        u1_mag_valid_sep;
wire [7:0]  i1_mag_hundreds_sep;
wire [7:0]  i1_mag_tens_sep;
wire [7:0]  i1_mag_units_sep;
wire [7:0]  i1_mag_decile_sep;
wire [7:0]  i1_mag_percentiles_sep;
wire        i1_mag_valid_sep;
wire        phase1_neg_sep;
wire [7:0]  phase1_hundreds_sep;
wire [7:0]  phase1_tens_sep;
wire [7:0]  phase1_units_sep;
wire [7:0]  phase1_decile_sep;
wire [7:0]  phase1_percentiles_sep;
wire        phase1_valid_sep;
wire [7:0]  dc_u_hundreds_sep;
wire [7:0]  dc_u_tens_sep;
wire [7:0]  dc_u_units_sep;
wire [7:0]  dc_u_decile_sep;
wire [7:0]  dc_u_percentiles_sep;
wire        dc_u_valid_sep;
wire [7:0]  dc_i_hundreds_sep;
wire [7:0]  dc_i_tens_sep;
wire [7:0]  dc_i_units_sep;
wire [7:0]  dc_i_decile_sep;
wire [7:0]  dc_i_percentiles_sep;
wire        dc_i_valid_sep;

assign frame_edge_wave = frame_toggle_sync2 ^ frame_toggle_sync3;
assign raw_commit_edge = raw_commit_sync2 ^ raw_commit_sync3;

// 从 45 bit 列表中取出指定排名的谐波次数。
function [8:0] order_from_list;
    input [44:0] packed_list;
    input [2:0]  item_index;
    begin
        case (item_index)
            3'd0: order_from_list = packed_list[44:36];
            3'd1: order_from_list = packed_list[35:27];
            3'd2: order_from_list = packed_list[26:18];
            3'd3: order_from_list = packed_list[17:9];
            default: order_from_list = packed_list[8:0];
        endcase
    end
endfunction

// 把 0~9 的十进制数字映射到 ASCII。
function [7:0] digit_to_ascii;
    input [3:0] digit_value;
    begin
        digit_to_ascii = 8'd48 + {4'd0, digit_value};
    end
endfunction

// 取 0~500 次谐波的百位字符，未到百位时输出空格。
function [7:0] order_hundreds_ascii;
    input [8:0] order_value;
    begin
        if (order_value >= 9'd500)
            order_hundreds_ascii = "5";
        else if (order_value >= 9'd400)
            order_hundreds_ascii = "4";
        else if (order_value >= 9'd300)
            order_hundreds_ascii = "3";
        else if (order_value >= 9'd200)
            order_hundreds_ascii = "2";
        else if (order_value >= 9'd100)
            order_hundreds_ascii = "1";
        else
            order_hundreds_ascii = " ";
    end
endfunction

// 取 0~500 次谐波的十位字符，只有个位时输出空格。
function [7:0] order_tens_ascii;
    input [8:0] order_value;
    reg [8:0] remainder_value;
    begin
        if (order_value >= 9'd500)
            remainder_value = order_value - 9'd500;
        else if (order_value >= 9'd400)
            remainder_value = order_value - 9'd400;
        else if (order_value >= 9'd300)
            remainder_value = order_value - 9'd300;
        else if (order_value >= 9'd200)
            remainder_value = order_value - 9'd200;
        else if (order_value >= 9'd100)
            remainder_value = order_value - 9'd100;
        else
            remainder_value = order_value;

        if ((order_value < 9'd10))
            order_tens_ascii = " ";
        else if (remainder_value >= 9'd90)
            order_tens_ascii = "9";
        else if (remainder_value >= 9'd80)
            order_tens_ascii = "8";
        else if (remainder_value >= 9'd70)
            order_tens_ascii = "7";
        else if (remainder_value >= 9'd60)
            order_tens_ascii = "6";
        else if (remainder_value >= 9'd50)
            order_tens_ascii = "5";
        else if (remainder_value >= 9'd40)
            order_tens_ascii = "4";
        else if (remainder_value >= 9'd30)
            order_tens_ascii = "3";
        else if (remainder_value >= 9'd20)
            order_tens_ascii = "2";
        else if (remainder_value >= 9'd10)
            order_tens_ascii = "1";
        else
            order_tens_ascii = "0";
    end
endfunction

// 取 0~500 次谐波的个位字符。
function [7:0] order_units_ascii;
    input [8:0] order_value;
    reg [8:0] remainder_value;
    begin
        if (order_value >= 9'd500)
            remainder_value = order_value - 9'd500;
        else if (order_value >= 9'd400)
            remainder_value = order_value - 9'd400;
        else if (order_value >= 9'd300)
            remainder_value = order_value - 9'd300;
        else if (order_value >= 9'd200)
            remainder_value = order_value - 9'd200;
        else if (order_value >= 9'd100)
            remainder_value = order_value - 9'd100;
        else
            remainder_value = order_value;

        if (remainder_value >= 9'd90)
            remainder_value = remainder_value - 9'd90;
        else if (remainder_value >= 9'd80)
            remainder_value = remainder_value - 9'd80;
        else if (remainder_value >= 9'd70)
            remainder_value = remainder_value - 9'd70;
        else if (remainder_value >= 9'd60)
            remainder_value = remainder_value - 9'd60;
        else if (remainder_value >= 9'd50)
            remainder_value = remainder_value - 9'd50;
        else if (remainder_value >= 9'd40)
            remainder_value = remainder_value - 9'd40;
        else if (remainder_value >= 9'd30)
            remainder_value = remainder_value - 9'd30;
        else if (remainder_value >= 9'd20)
            remainder_value = remainder_value - 9'd20;
        else if (remainder_value >= 9'd10)
            remainder_value = remainder_value - 9'd10;

        order_units_ascii = digit_to_ascii(remainder_value[3:0]);
    end
endfunction

// 组装 DH-U/DH-I 一整行 25 字符文本，总线从高位到低位对应从左到右的字符。
function [199:0] build_dh_text;
    input [7:0]  channel_char;
    input        list_valid;
    input [44:0] packed_list;
    input [2:0]  item_count;
    reg   [199:0] text_value;
    reg   [8:0]   order_value;
    integer       item_index;
    integer       char_base;
    begin
        text_value = {25{8'h20}};
        text_value[199:192] = "D";
        text_value[191:184] = "H";
        text_value[183:176] = "-";
        text_value[175:168] = channel_char;
        text_value[167:160] = ":";
        text_value[159:152] = " ";

        if (list_valid && (item_count != 3'd0)) begin
            for (item_index = 0; item_index < 5; item_index = item_index + 1) begin
                if (item_index < item_count) begin
                    order_value = order_from_list(packed_list, item_index[2:0]);
                    char_base = 6 + (item_index * 4);
                    text_value[(25 - char_base) * 8 - 1 -: 8] = order_hundreds_ascii(order_value);
                    text_value[(24 - char_base) * 8 - 1 -: 8] = order_tens_ascii(order_value);
                    text_value[(23 - char_base) * 8 - 1 -: 8] = order_units_ascii(order_value);
                    if (item_index != 4 && ((item_index + 1) < item_count))
                        text_value[(22 - char_base) * 8 - 1 -: 8] = ",";
                end
            end
        end

        build_dh_text = text_value;
    end
endfunction

// x100 规整阶段只处理当前活动快照，避免处理过程中被新的 raw 提交覆盖。
freq_text_x100_normalizer u_freq_text_x100_normalizer (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .start                  (x100_start),
    .thd_u_raw_x100         (thd_u_raw_active),
    .thd_i_raw_x100         (thd_i_raw_active),
    .thd_u_valid_in         (thd_u_valid_active),
    .thd_i_valid_in         (thd_i_valid_active),
    .u1_mag_raw_x100        (u1_mag_raw_active),
    .i1_mag_raw_x100        (i1_mag_raw_active),
    .u1_mag_valid_in        (u1_mag_valid_active),
    .i1_mag_valid_in        (i1_mag_valid_active),
    .phase1_raw_x100        (phase1_raw_active),
    .phase1_valid_in        (phase1_valid_active),
    .dc_u_raw_x100          (dc_u_raw_active),
    .dc_i_raw_x100          (dc_i_raw_active),
    .dc_u_valid_in          (dc_u_valid_active),
    .dc_i_valid_in          (dc_i_valid_active),
    .dh_order_u_raw         (9'd0),
    .dh_order_i_raw         (9'd0),
    .dh_order_u_valid_in    (1'b0),
    .dh_order_i_valid_in    (1'b0),
    .done                   (x100_done),
    .thd_u_x100             (thd_u_x100_wire),
    .thd_i_x100             (thd_i_x100_wire),
    .thd_u_valid            (thd_u_valid_x100),
    .thd_i_valid            (thd_i_valid_x100),
    .u1_mag_x100            (u1_mag_x100_wire),
    .i1_mag_x100            (i1_mag_x100_wire),
    .u1_mag_valid           (u1_mag_valid_x100),
    .i1_mag_valid           (i1_mag_valid_x100),
    .phase1_x100            (phase1_x100_wire),
    .phase1_valid           (phase1_valid_x100),
    .dc_u_x100              (dc_u_x100_wire),
    .dc_i_x100              (dc_i_x100_wire),
    .dc_u_valid             (dc_u_valid_x100),
    .dc_i_valid             (dc_i_valid_x100),
    .dh_order_u             (),
    .dh_order_i             (),
    .dh_order_u_valid       (),
    .dh_order_i_valid       ()
);

// 数字位拆分阶段继续处理同一份活动快照，输出供 LCD 文本层直接消费的字符位。
freq_text_data_separator u_freq_text_data_separator (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .start                  (separator_start),
    .thd_u_x100             (thd_u_x100_wire),
    .thd_i_x100             (thd_i_x100_wire),
    .thd_u_valid_in         (thd_u_valid_x100),
    .thd_i_valid_in         (thd_i_valid_x100),
    .u1_mag_x100            (u1_mag_x100_wire),
    .i1_mag_x100            (i1_mag_x100_wire),
    .u1_mag_valid_in        (u1_mag_valid_x100),
    .i1_mag_valid_in        (i1_mag_valid_x100),
    .phase1_x100            (phase1_x100_wire),
    .phase1_valid_in        (phase1_valid_x100),
    .dc_u_x100              (dc_u_x100_wire),
    .dc_i_x100              (dc_i_x100_wire),
    .dc_u_valid_in          (dc_u_valid_x100),
    .dc_i_valid_in          (dc_i_valid_x100),
    .dh_order_u             (9'd0),
    .dh_order_i             (9'd0),
    .dh_order_u_valid_in    (1'b0),
    .dh_order_i_valid_in    (1'b0),
    .done                   (separator_done),
    .thd_u_hundreds         (thd_u_hundreds_sep),
    .thd_u_tens             (thd_u_tens_sep),
    .thd_u_units            (thd_u_units_sep),
    .thd_u_decile           (thd_u_decile_sep),
    .thd_u_percentiles      (thd_u_percentiles_sep),
    .thd_u_valid            (thd_u_valid_sep),
    .thd_i_hundreds         (thd_i_hundreds_sep),
    .thd_i_tens             (thd_i_tens_sep),
    .thd_i_units            (thd_i_units_sep),
    .thd_i_decile           (thd_i_decile_sep),
    .thd_i_percentiles      (thd_i_percentiles_sep),
    .thd_i_valid            (thd_i_valid_sep),
    .u1_mag_hundreds        (u1_mag_hundreds_sep),
    .u1_mag_tens            (u1_mag_tens_sep),
    .u1_mag_units           (u1_mag_units_sep),
    .u1_mag_decile          (u1_mag_decile_sep),
    .u1_mag_percentiles     (u1_mag_percentiles_sep),
    .u1_mag_valid           (u1_mag_valid_sep),
    .i1_mag_hundreds        (i1_mag_hundreds_sep),
    .i1_mag_tens            (i1_mag_tens_sep),
    .i1_mag_units           (i1_mag_units_sep),
    .i1_mag_decile          (i1_mag_decile_sep),
    .i1_mag_percentiles     (i1_mag_percentiles_sep),
    .i1_mag_valid           (i1_mag_valid_sep),
    .phase1_neg             (phase1_neg_sep),
    .phase1_hundreds        (phase1_hundreds_sep),
    .phase1_tens            (phase1_tens_sep),
    .phase1_units           (phase1_units_sep),
    .phase1_decile          (phase1_decile_sep),
    .phase1_percentiles     (phase1_percentiles_sep),
    .phase1_valid           (phase1_valid_sep),
    .dc_u_hundreds          (dc_u_hundreds_sep),
    .dc_u_tens              (dc_u_tens_sep),
    .dc_u_units             (dc_u_units_sep),
    .dc_u_decile            (dc_u_decile_sep),
    .dc_u_percentiles       (dc_u_percentiles_sep),
    .dc_u_valid             (dc_u_valid_sep),
    .dc_i_hundreds          (dc_i_hundreds_sep),
    .dc_i_tens              (dc_i_tens_sep),
    .dc_i_units             (dc_i_units_sep),
    .dc_i_decile            (dc_i_decile_sep),
    .dc_i_percentiles       (dc_i_percentiles_sep),
    .dc_i_valid             (dc_i_valid_sep),
    .dh_order_u_hundreds    (),
    .dh_order_u_tens        (),
    .dh_order_u_units       (),
    .dh_order_u_valid       (),
    .dh_order_i_hundreds    (),
    .dh_order_i_tens        (),
    .dh_order_i_units       (),
    .dh_order_i_valid       ()
);

// 先缓存最新 raw 指标，再仅在 LCD 帧边沿启动一次频域文字刷新，和时域文字区保持同节奏。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state                          <= ST_WAIT_FRAME;
        frame_toggle_sync1             <= 1'b0;
        frame_toggle_sync2             <= 1'b0;
        frame_toggle_sync3             <= 1'b0;
        swap_ack_sync1                 <= 1'b0;
        swap_ack_sync2                 <= 1'b0;
        swap_ack_sync3                 <= 1'b0;
        raw_commit_sync1               <= 1'b0;
        raw_commit_sync2               <= 1'b0;
        raw_commit_sync3               <= 1'b0;
        x100_start                     <= 1'b0;
        separator_start                <= 1'b0;
        raw_pending_valid              <= 1'b0;
        thd_u_raw_pending              <= 32'd0;
        thd_i_raw_pending              <= 32'd0;
        thd_u_valid_pending            <= 1'b0;
        thd_i_valid_pending            <= 1'b0;
        u1_mag_raw_pending             <= 32'd0;
        i1_mag_raw_pending             <= 32'd0;
        u1_mag_valid_pending           <= 1'b0;
        i1_mag_valid_pending           <= 1'b0;
        phase1_raw_pending             <= 32'sd0;
        phase1_valid_pending           <= 1'b0;
        dc_u_raw_pending               <= 32'd0;
        dc_i_raw_pending               <= 32'd0;
        dc_u_valid_pending             <= 1'b0;
        dc_i_valid_pending             <= 1'b0;
        dh_order_u_valid_pending       <= 1'b0;
        dh_order_i_valid_pending       <= 1'b0;
        dh_order_u_list_pending        <= 45'd0;
        dh_order_i_list_pending        <= 45'd0;
        dh_order_u_count_pending       <= 3'd0;
        dh_order_i_count_pending       <= 3'd0;
        thd_u_raw_active               <= 32'd0;
        thd_i_raw_active               <= 32'd0;
        thd_u_valid_active             <= 1'b0;
        thd_i_valid_active             <= 1'b0;
        u1_mag_raw_active              <= 32'd0;
        i1_mag_raw_active              <= 32'd0;
        u1_mag_valid_active            <= 1'b0;
        i1_mag_valid_active            <= 1'b0;
        phase1_raw_active              <= 32'sd0;
        phase1_valid_active            <= 1'b0;
        dc_u_raw_active                <= 32'd0;
        dc_i_raw_active                <= 32'd0;
        dc_u_valid_active              <= 1'b0;
        dc_i_valid_active              <= 1'b0;
        dh_order_u_valid_active        <= 1'b0;
        dh_order_i_valid_active        <= 1'b0;
        dh_order_u_list_active         <= 45'd0;
        dh_order_i_list_active         <= 45'd0;
        dh_order_u_count_active        <= 3'd0;
        dh_order_i_count_active        <= 3'd0;
        freq_text_result_commit_toggle <= 1'b0;
        thd_u_hundreds                 <= 8'd0;
        thd_u_tens                     <= 8'd0;
        thd_u_units                    <= 8'd0;
        thd_u_decile                   <= 8'd0;
        thd_u_percentiles              <= 8'd0;
        thd_u_valid                    <= 1'b0;
        thd_i_hundreds                 <= 8'd0;
        thd_i_tens                     <= 8'd0;
        thd_i_units                    <= 8'd0;
        thd_i_decile                   <= 8'd0;
        thd_i_percentiles              <= 8'd0;
        thd_i_valid                    <= 1'b0;
        u1_mag_hundreds                <= 8'd0;
        u1_mag_tens                    <= 8'd0;
        u1_mag_units                   <= 8'd0;
        u1_mag_decile                  <= 8'd0;
        u1_mag_percentiles             <= 8'd0;
        u1_mag_valid                   <= 1'b0;
        i1_mag_hundreds                <= 8'd0;
        i1_mag_tens                    <= 8'd0;
        i1_mag_units                   <= 8'd0;
        i1_mag_decile                  <= 8'd0;
        i1_mag_percentiles             <= 8'd0;
        i1_mag_valid                   <= 1'b0;
        phase1_neg                     <= 1'b0;
        phase1_hundreds                <= 8'd0;
        phase1_tens                    <= 8'd0;
        phase1_units                   <= 8'd0;
        phase1_decile                  <= 8'd0;
        phase1_percentiles             <= 8'd0;
        phase1_valid                   <= 1'b0;
        dc_u_hundreds                  <= 8'd0;
        dc_u_tens                      <= 8'd0;
        dc_u_units                     <= 8'd0;
        dc_u_decile                    <= 8'd0;
        dc_u_percentiles               <= 8'd0;
        dc_u_valid                     <= 1'b0;
        dc_i_hundreds                  <= 8'd0;
        dc_i_tens                      <= 8'd0;
        dc_i_units                     <= 8'd0;
        dc_i_decile                    <= 8'd0;
        dc_i_percentiles               <= 8'd0;
        dc_i_valid                     <= 1'b0;
        dh_order_u_text                <= {25{8'h20}};
        dh_order_i_text                <= {25{8'h20}};
    end else begin
        frame_toggle_sync1 <= lcd_frame_done_toggle;
        frame_toggle_sync2 <= frame_toggle_sync1;
        frame_toggle_sync3 <= frame_toggle_sync2;
        swap_ack_sync1     <= lcd_swap_ack_toggle;
        swap_ack_sync2     <= swap_ack_sync1;
        swap_ack_sync3     <= swap_ack_sync2;
        raw_commit_sync1   <= raw_result_commit_toggle;
        raw_commit_sync2   <= raw_commit_sync1;
        raw_commit_sync3   <= raw_commit_sync2;
        x100_start         <= 1'b0;
        separator_start    <= 1'b0;

        if (raw_commit_edge) begin
            thd_u_raw_pending        <= thd_u_raw_x100;
            thd_i_raw_pending        <= thd_i_raw_x100;
            thd_u_valid_pending      <= thd_u_valid_in;
            thd_i_valid_pending      <= thd_i_valid_in;
            u1_mag_raw_pending       <= u1_mag_raw_x100;
            i1_mag_raw_pending       <= i1_mag_raw_x100;
            u1_mag_valid_pending     <= u1_mag_valid_in;
            i1_mag_valid_pending     <= i1_mag_valid_in;
            phase1_raw_pending       <= phase1_raw_x100;
            phase1_valid_pending     <= phase1_valid_in;
            dc_u_raw_pending         <= dc_u_raw_x100;
            dc_i_raw_pending         <= dc_i_raw_x100;
            dc_u_valid_pending       <= dc_u_valid_in;
            dc_i_valid_pending       <= dc_i_valid_in;
            dh_order_u_valid_pending <= dh_order_u_valid_in;
            dh_order_i_valid_pending <= dh_order_i_valid_in;
            dh_order_u_list_pending  <= dh_order_u_list_raw;
            dh_order_i_list_pending  <= dh_order_i_list_raw;
            dh_order_u_count_pending <= dh_order_u_count_raw;
            dh_order_i_count_pending <= dh_order_i_count_raw;
            raw_pending_valid        <= 1'b1;
        end

        case (state)
            ST_WAIT_FRAME: begin
                if (frame_edge_wave && raw_pending_valid) begin
                    thd_u_raw_active        <= thd_u_raw_pending;
                    thd_i_raw_active        <= thd_i_raw_pending;
                    thd_u_valid_active      <= thd_u_valid_pending;
                    thd_i_valid_active      <= thd_i_valid_pending;
                    u1_mag_raw_active       <= u1_mag_raw_pending;
                    i1_mag_raw_active       <= i1_mag_raw_pending;
                    u1_mag_valid_active     <= u1_mag_valid_pending;
                    i1_mag_valid_active     <= i1_mag_valid_pending;
                    phase1_raw_active       <= phase1_raw_pending;
                    phase1_valid_active     <= phase1_valid_pending;
                    dc_u_raw_active         <= dc_u_raw_pending;
                    dc_i_raw_active         <= dc_i_raw_pending;
                    dc_u_valid_active       <= dc_u_valid_pending;
                    dc_i_valid_active       <= dc_i_valid_pending;
                    dh_order_u_valid_active <= dh_order_u_valid_pending;
                    dh_order_i_valid_active <= dh_order_i_valid_pending;
                    dh_order_u_list_active  <= dh_order_u_list_pending;
                    dh_order_i_list_active  <= dh_order_i_list_pending;
                    dh_order_u_count_active <= dh_order_u_count_pending;
                    dh_order_i_count_active <= dh_order_i_count_pending;
                    raw_pending_valid       <= raw_commit_edge;
                    state <= ST_START_X100;
                end
            end

            ST_START_X100: begin
                x100_start <= 1'b1;
                state      <= ST_WAIT_X100;
            end

            ST_WAIT_X100: begin
                if (x100_done)
                    state <= ST_START_SEPARATOR;
            end

            ST_START_SEPARATOR: begin
                separator_start <= 1'b1;
                state           <= ST_WAIT_SEPARATOR;
            end

            ST_WAIT_SEPARATOR: begin
                if (separator_done)
                    state <= ST_COMMIT;
            end

            ST_COMMIT: begin
                thd_u_hundreds    <= thd_u_hundreds_sep;
                thd_u_tens        <= thd_u_tens_sep;
                thd_u_units       <= thd_u_units_sep;
                thd_u_decile      <= thd_u_decile_sep;
                thd_u_percentiles <= thd_u_percentiles_sep;
                thd_u_valid       <= thd_u_valid_sep;
                thd_i_hundreds    <= thd_i_hundreds_sep;
                thd_i_tens        <= thd_i_tens_sep;
                thd_i_units       <= thd_i_units_sep;
                thd_i_decile      <= thd_i_decile_sep;
                thd_i_percentiles <= thd_i_percentiles_sep;
                thd_i_valid       <= thd_i_valid_sep;
                u1_mag_hundreds   <= u1_mag_hundreds_sep;
                u1_mag_tens       <= u1_mag_tens_sep;
                u1_mag_units      <= u1_mag_units_sep;
                u1_mag_decile     <= u1_mag_decile_sep;
                u1_mag_percentiles<= u1_mag_percentiles_sep;
                u1_mag_valid      <= u1_mag_valid_sep;
                i1_mag_hundreds   <= i1_mag_hundreds_sep;
                i1_mag_tens       <= i1_mag_tens_sep;
                i1_mag_units      <= i1_mag_units_sep;
                i1_mag_decile     <= i1_mag_decile_sep;
                i1_mag_percentiles<= i1_mag_percentiles_sep;
                i1_mag_valid      <= i1_mag_valid_sep;
                phase1_neg        <= phase1_neg_sep;
                phase1_hundreds   <= phase1_hundreds_sep;
                phase1_tens       <= phase1_tens_sep;
                phase1_units      <= phase1_units_sep;
                phase1_decile     <= phase1_decile_sep;
                phase1_percentiles<= phase1_percentiles_sep;
                phase1_valid      <= phase1_valid_sep;
                dc_u_hundreds     <= dc_u_hundreds_sep;
                dc_u_tens         <= dc_u_tens_sep;
                dc_u_units        <= dc_u_units_sep;
                dc_u_decile       <= dc_u_decile_sep;
                dc_u_percentiles  <= dc_u_percentiles_sep;
                dc_u_valid        <= dc_u_valid_sep;
                dc_i_hundreds     <= dc_i_hundreds_sep;
                dc_i_tens         <= dc_i_tens_sep;
                dc_i_units        <= dc_i_units_sep;
                dc_i_decile       <= dc_i_decile_sep;
                dc_i_percentiles  <= dc_i_percentiles_sep;
                dc_i_valid        <= dc_i_valid_sep;
                dh_order_u_text   <= build_dh_text("U", dh_order_u_valid_active, dh_order_u_list_active, dh_order_u_count_active);
                dh_order_i_text   <= build_dh_text("I", dh_order_i_valid_active, dh_order_i_list_active, dh_order_i_count_active);
                freq_text_result_commit_toggle <= ~freq_text_result_commit_toggle;
                state <= ST_WAIT_FRAME;
            end

            default: begin
                state <= ST_WAIT_FRAME;
            end
        endcase
    end
end

endmodule
