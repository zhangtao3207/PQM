`timescale 1ns / 1ps

/*
 * 模块: freq_text_display_preprocess
 * 功能:
 *   接收频域 raw 指标完成事件，依次调度 x100 规整和十进制数位拆分，
 *   最终输出可直接写入 LCD 文本双缓冲包的频域参数数字位。
 * 输入:
 *   clk: 文本预处理工作时钟。
 *   rst_n: 低有效复位信号。
 *   raw_result_commit_toggle: 频域 raw 指标完成后翻转一次的事件信号。
 *   thd_u_raw_x100: 电压 THD raw 值。
 *   thd_i_raw_x100: 电流 THD raw 值。
 *   u1_mag_raw_x100: 电压基波幅值占比 raw 值。
 *   i1_mag_raw_x100: 电流基波幅值占比 raw 值。
 *   phase1_raw_x100: 基波相位差 raw 值。
 *   dc_u_raw_x100: 电压直流分量占比 raw 值。
 *   dc_i_raw_x100: 电流直流分量占比 raw 值。
 *   dh_order_u_raw: 电压主导谐波次数 raw 值。
 *   dh_order_i_raw: 电流主导谐波次数 raw 值。
 *   各 valid 输入: 对应 raw 指标是否有效。
 * 输出:
 *   freq_text_result_commit_toggle: 一批频域文本数字位完成后翻转一次。
 *   各 digit/valid 输出: 频域右侧文本区使用的显示数字位、符号位和有效位。
 */
module freq_text_display_preprocess (
    input  wire               clk,
    input  wire               rst_n,
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
    input  wire [8:0]         dh_order_u_raw,
    input  wire [8:0]         dh_order_i_raw,
    input  wire               dh_order_u_valid_in,
    input  wire               dh_order_i_valid_in,
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
    output reg  [7:0]         dh_order_u_hundreds,
    output reg  [7:0]         dh_order_u_tens,
    output reg  [7:0]         dh_order_u_units,
    output reg                dh_order_u_valid,
    output reg  [7:0]         dh_order_i_hundreds,
    output reg  [7:0]         dh_order_i_tens,
    output reg  [7:0]         dh_order_i_units,
    output reg                dh_order_i_valid
);

localparam [2:0] ST_WAIT_RAW        = 3'd0;
localparam [2:0] ST_START_X100      = 3'd1;
localparam [2:0] ST_WAIT_X100       = 3'd2;
localparam [2:0] ST_START_SEPARATOR = 3'd3;
localparam [2:0] ST_WAIT_SEPARATOR  = 3'd4;
localparam [2:0] ST_COMMIT          = 3'd5;

reg [2:0] state;
reg       raw_commit_sync1;
reg       raw_commit_sync2;
reg       raw_commit_sync3;
reg       x100_start;
reg       separator_start;

wire      raw_commit_edge;
wire      x100_done;
wire      separator_done;
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
wire [8:0]  dh_order_u_wire;
wire [8:0]  dh_order_i_wire;
wire        dh_order_u_valid_x100;
wire        dh_order_i_valid_x100;
wire [7:0]  thd_u_hundreds_sep, thd_u_tens_sep, thd_u_units_sep, thd_u_decile_sep, thd_u_percentiles_sep;
wire        thd_u_valid_sep;
wire [7:0]  thd_i_hundreds_sep, thd_i_tens_sep, thd_i_units_sep, thd_i_decile_sep, thd_i_percentiles_sep;
wire        thd_i_valid_sep;
wire [7:0]  u1_mag_hundreds_sep, u1_mag_tens_sep, u1_mag_units_sep, u1_mag_decile_sep, u1_mag_percentiles_sep;
wire        u1_mag_valid_sep;
wire [7:0]  i1_mag_hundreds_sep, i1_mag_tens_sep, i1_mag_units_sep, i1_mag_decile_sep, i1_mag_percentiles_sep;
wire        i1_mag_valid_sep;
wire        phase1_neg_sep;
wire [7:0]  phase1_hundreds_sep, phase1_tens_sep, phase1_units_sep, phase1_decile_sep, phase1_percentiles_sep;
wire        phase1_valid_sep;
wire [7:0]  dc_u_hundreds_sep, dc_u_tens_sep, dc_u_units_sep, dc_u_decile_sep, dc_u_percentiles_sep;
wire        dc_u_valid_sep;
wire [7:0]  dc_i_hundreds_sep, dc_i_tens_sep, dc_i_units_sep, dc_i_decile_sep, dc_i_percentiles_sep;
wire        dc_i_valid_sep;
wire [7:0]  dh_order_u_hundreds_sep, dh_order_u_tens_sep, dh_order_u_units_sep;
wire        dh_order_u_valid_sep;
wire [7:0]  dh_order_i_hundreds_sep, dh_order_i_tens_sep, dh_order_i_units_sep;
wire        dh_order_i_valid_sep;

assign raw_commit_edge = raw_commit_sync2 ^ raw_commit_sync3;

// x100 规整阶段只负责截幅和有效位传递，不做数位拆分。
freq_text_x100_normalizer u_freq_text_x100_normalizer (
    .clk                    (clk),
    .rst_n                  (rst_n),
    .start                  (x100_start),
    .thd_u_raw_x100         (thd_u_raw_x100),
    .thd_i_raw_x100         (thd_i_raw_x100),
    .thd_u_valid_in         (thd_u_valid_in),
    .thd_i_valid_in         (thd_i_valid_in),
    .u1_mag_raw_x100        (u1_mag_raw_x100),
    .i1_mag_raw_x100        (i1_mag_raw_x100),
    .u1_mag_valid_in        (u1_mag_valid_in),
    .i1_mag_valid_in        (i1_mag_valid_in),
    .phase1_raw_x100        (phase1_raw_x100),
    .phase1_valid_in        (phase1_valid_in),
    .dc_u_raw_x100          (dc_u_raw_x100),
    .dc_i_raw_x100          (dc_i_raw_x100),
    .dc_u_valid_in          (dc_u_valid_in),
    .dc_i_valid_in          (dc_i_valid_in),
    .dh_order_u_raw         (dh_order_u_raw),
    .dh_order_i_raw         (dh_order_i_raw),
    .dh_order_u_valid_in    (dh_order_u_valid_in),
    .dh_order_i_valid_in    (dh_order_i_valid_in),
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
    .dh_order_u             (dh_order_u_wire),
    .dh_order_i             (dh_order_i_wire),
    .dh_order_u_valid       (dh_order_u_valid_x100),
    .dh_order_i_valid       (dh_order_i_valid_x100)
);

// 数位拆分阶段生成 LCD 文本层直接消费的 digit/valid 字段。
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
    .dh_order_u             (dh_order_u_wire),
    .dh_order_i             (dh_order_i_wire),
    .dh_order_u_valid_in    (dh_order_u_valid_x100),
    .dh_order_i_valid_in    (dh_order_i_valid_x100),
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
    .dh_order_u_hundreds    (dh_order_u_hundreds_sep),
    .dh_order_u_tens        (dh_order_u_tens_sep),
    .dh_order_u_units       (dh_order_u_units_sep),
    .dh_order_u_valid       (dh_order_u_valid_sep),
    .dh_order_i_hundreds    (dh_order_i_hundreds_sep),
    .dh_order_i_tens        (dh_order_i_tens_sep),
    .dh_order_i_units       (dh_order_i_units_sep),
    .dh_order_i_valid       (dh_order_i_valid_sep)
);

// 以 raw 提交事件为触发，顺序完成 x100 规整、数位拆分和文本包提交。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state                          <= ST_WAIT_RAW;
        raw_commit_sync1               <= 1'b0;
        raw_commit_sync2               <= 1'b0;
        raw_commit_sync3               <= 1'b0;
        x100_start                     <= 1'b0;
        separator_start                <= 1'b0;
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
        dh_order_u_hundreds            <= 8'd0;
        dh_order_u_tens                <= 8'd0;
        dh_order_u_units               <= 8'd0;
        dh_order_u_valid               <= 1'b0;
        dh_order_i_hundreds            <= 8'd0;
        dh_order_i_tens                <= 8'd0;
        dh_order_i_units               <= 8'd0;
        dh_order_i_valid               <= 1'b0;
    end else begin
        raw_commit_sync1 <= raw_result_commit_toggle;
        raw_commit_sync2 <= raw_commit_sync1;
        raw_commit_sync3 <= raw_commit_sync2;
        x100_start       <= 1'b0;
        separator_start  <= 1'b0;

        case (state)
            ST_WAIT_RAW: begin
                if (raw_commit_edge)
                    state <= ST_START_X100;
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
                thd_u_hundreds       <= thd_u_hundreds_sep;
                thd_u_tens           <= thd_u_tens_sep;
                thd_u_units          <= thd_u_units_sep;
                thd_u_decile         <= thd_u_decile_sep;
                thd_u_percentiles    <= thd_u_percentiles_sep;
                thd_u_valid          <= thd_u_valid_sep;
                thd_i_hundreds       <= thd_i_hundreds_sep;
                thd_i_tens           <= thd_i_tens_sep;
                thd_i_units          <= thd_i_units_sep;
                thd_i_decile         <= thd_i_decile_sep;
                thd_i_percentiles    <= thd_i_percentiles_sep;
                thd_i_valid          <= thd_i_valid_sep;
                u1_mag_hundreds      <= u1_mag_hundreds_sep;
                u1_mag_tens          <= u1_mag_tens_sep;
                u1_mag_units         <= u1_mag_units_sep;
                u1_mag_decile        <= u1_mag_decile_sep;
                u1_mag_percentiles   <= u1_mag_percentiles_sep;
                u1_mag_valid         <= u1_mag_valid_sep;
                i1_mag_hundreds      <= i1_mag_hundreds_sep;
                i1_mag_tens          <= i1_mag_tens_sep;
                i1_mag_units         <= i1_mag_units_sep;
                i1_mag_decile        <= i1_mag_decile_sep;
                i1_mag_percentiles   <= i1_mag_percentiles_sep;
                i1_mag_valid         <= i1_mag_valid_sep;
                phase1_neg           <= phase1_neg_sep;
                phase1_hundreds      <= phase1_hundreds_sep;
                phase1_tens          <= phase1_tens_sep;
                phase1_units         <= phase1_units_sep;
                phase1_decile        <= phase1_decile_sep;
                phase1_percentiles   <= phase1_percentiles_sep;
                phase1_valid         <= phase1_valid_sep;
                dc_u_hundreds        <= dc_u_hundreds_sep;
                dc_u_tens            <= dc_u_tens_sep;
                dc_u_units           <= dc_u_units_sep;
                dc_u_decile          <= dc_u_decile_sep;
                dc_u_percentiles     <= dc_u_percentiles_sep;
                dc_u_valid           <= dc_u_valid_sep;
                dc_i_hundreds        <= dc_i_hundreds_sep;
                dc_i_tens            <= dc_i_tens_sep;
                dc_i_units           <= dc_i_units_sep;
                dc_i_decile          <= dc_i_decile_sep;
                dc_i_percentiles     <= dc_i_percentiles_sep;
                dc_i_valid           <= dc_i_valid_sep;
                dh_order_u_hundreds  <= dh_order_u_hundreds_sep;
                dh_order_u_tens      <= dh_order_u_tens_sep;
                dh_order_u_units     <= dh_order_u_units_sep;
                dh_order_u_valid     <= dh_order_u_valid_sep;
                dh_order_i_hundreds  <= dh_order_i_hundreds_sep;
                dh_order_i_tens      <= dh_order_i_tens_sep;
                dh_order_i_units     <= dh_order_i_units_sep;
                dh_order_i_valid     <= dh_order_i_valid_sep;
                freq_text_result_commit_toggle <= ~freq_text_result_commit_toggle;
                state <= ST_WAIT_RAW;
            end

            default: begin
                state <= ST_WAIT_RAW;
            end
        endcase
    end
end

endmodule
