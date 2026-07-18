`timescale 1ns / 1ps

/*
 * 模块: freq_text_data_separator
 * 功能:
 *   将频域文本指标的 x100/order 数值拆分为 LCD 字符渲染需要的十进制数字位。
 *   本模块串行复用一组比较/减法逻辑，避免每个字段并行实例化拆位器造成 LUT 超量。
 * 输入:
 *   clk: 文本预处理工作时钟。
 *   rst_n: 低有效复位信号。
 *   start: 启动一次频域文本数位拆分。
 *   thd_u_x100: 电压 THD，单位为百分比 x100。
 *   thd_i_x100: 电流 THD，单位为百分比 x100。
 *   thd_u_valid_in: 电压 THD 有效标志。
 *   thd_i_valid_in: 电流 THD 有效标志。
 *   u1_mag_x100: 电压基波幅值占比，单位为百分比 x100。
 *   i1_mag_x100: 电流基波幅值占比，单位为百分比 x100。
 *   u1_mag_valid_in: 电压基波幅值占比有效标志。
 *   i1_mag_valid_in: 电流基波幅值占比有效标志。
 *   phase1_x100: 基波 U-I 相位差，单位为度 x100。
 *   phase1_valid_in: 基波相位差有效标志。
 *   dc_u_x100: 电压直流分量占比，单位为百分比 x100。
 *   dc_i_x100: 电流直流分量占比，单位为百分比 x100。
 *   dc_u_valid_in: 电压直流分量有效标志。
 *   dc_i_valid_in: 电流直流分量有效标志。
 *   dh_order_u: 电压主导谐波次数。
 *   dh_order_i: 电流主导谐波次数。
 *   dh_order_u_valid_in: 电压主导谐波次数有效标志。
 *   dh_order_i_valid_in: 电流主导谐波次数有效标志。
 * 输出:
 *   done: 本次数位拆分完成脉冲。
 *   各 digit/valid 输出: 供 LCD 文本层直接渲染的数字位、符号位和有效位。
 */
module freq_text_data_separator (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               start,
    input  wire [31:0]        thd_u_x100,
    input  wire [31:0]        thd_i_x100,
    input  wire               thd_u_valid_in,
    input  wire               thd_i_valid_in,
    input  wire [31:0]        u1_mag_x100,
    input  wire [31:0]        i1_mag_x100,
    input  wire               u1_mag_valid_in,
    input  wire               i1_mag_valid_in,
    input  wire signed [31:0] phase1_x100,
    input  wire               phase1_valid_in,
    input  wire [31:0]        dc_u_x100,
    input  wire [31:0]        dc_i_x100,
    input  wire               dc_u_valid_in,
    input  wire               dc_i_valid_in,
    input  wire [8:0]         dh_order_u,
    input  wire [8:0]         dh_order_i,
    input  wire               dh_order_u_valid_in,
    input  wire               dh_order_i_valid_in,
    output reg                done,
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

localparam [3:0] IDX_THD_U      = 4'd0;
localparam [3:0] IDX_THD_I      = 4'd1;
localparam [3:0] IDX_U1_MAG     = 4'd2;
localparam [3:0] IDX_I1_MAG     = 4'd3;
localparam [3:0] IDX_PHASE1     = 4'd4;
localparam [3:0] IDX_DC_U       = 4'd5;
localparam [3:0] IDX_DC_I       = 4'd6;
localparam [3:0] IDX_DH_ORDER_U = 4'd7;
localparam [3:0] IDX_DH_ORDER_I = 4'd8;

reg       busy;
reg [3:0] item_index;
reg [2:0] digit_state;
reg [31:0] digit_work;
reg [7:0]  calc_hundreds;
reg [7:0]  calc_tens;
reg [7:0]  calc_units;
reg [7:0]  calc_decile;

wire [31:0] phase1_abs_x100;
wire [31:0] dh_order_u_x100;
wire [31:0] dh_order_i_x100;

localparam [2:0] DIG_LOAD     = 3'd0;
localparam [2:0] DIG_HUNDREDS = 3'd1;
localparam [2:0] DIG_TENS     = 3'd2;
localparam [2:0] DIG_UNITS    = 3'd3;
localparam [2:0] DIG_DECILE   = 3'd4;
localparam [2:0] DIG_STORE    = 3'd5;

// 将有符号相位转换为绝对值，符号位单独传给 LCD 文本层。
function [31:0] abs_value_of;
    input signed [31:0] signed_value;
    begin
        abs_value_of = signed_value[31] ? (~signed_value + 32'd1) : signed_value[31:0];
    end
endfunction

assign phase1_abs_x100 = abs_value_of(phase1_x100);

// 主导谐波次数是整数，转换成 x100 格式后复用统一拆位器。
assign dh_order_u_x100 = ({23'd0, dh_order_u} << 6) +
                         ({23'd0, dh_order_u} << 5) +
                         ({23'd0, dh_order_u} << 2);
assign dh_order_i_x100 = ({23'd0, dh_order_i} << 6) +
                         ({23'd0, dh_order_i} << 5) +
                         ({23'd0, dh_order_i} << 2);

// 根据当前字段选择要进入串行拆位流程的 x100 数值。
function [31:0] select_digit_value;
    input [3:0] index;
    begin
        select_digit_value = 32'd0;

        case (index)
            IDX_THD_U:      select_digit_value = thd_u_x100;
            IDX_THD_I:      select_digit_value = thd_i_x100;
            IDX_U1_MAG:     select_digit_value = u1_mag_x100;
            IDX_I1_MAG:     select_digit_value = i1_mag_x100;
            IDX_PHASE1:     select_digit_value = phase1_abs_x100;
            IDX_DC_U:       select_digit_value = dc_u_x100;
            IDX_DC_I:       select_digit_value = dc_i_x100;
            IDX_DH_ORDER_U: select_digit_value = dh_order_u_x100;
            IDX_DH_ORDER_I: select_digit_value = dh_order_i_x100;
            default:        select_digit_value = 32'd0;
        endcase
    end
endfunction

// 当前字段完成后跳转到下一个字段；最后一个字段完成时结束本轮拆位。
function [3:0] next_item_index;
    input [3:0] index;
    begin
        next_item_index = IDX_THD_U;

        case (index)
            IDX_THD_U:      next_item_index = IDX_THD_I;
            IDX_THD_I:      next_item_index = IDX_U1_MAG;
            IDX_U1_MAG:     next_item_index = IDX_I1_MAG;
            IDX_I1_MAG:     next_item_index = IDX_PHASE1;
            IDX_PHASE1:     next_item_index = IDX_DC_U;
            IDX_DC_U:       next_item_index = IDX_DC_I;
            IDX_DC_I:       next_item_index = IDX_DH_ORDER_U;
            IDX_DH_ORDER_U: next_item_index = IDX_DH_ORDER_I;
            default:        next_item_index = IDX_THD_U;
        endcase
    end
endfunction

// 把当前字段的拆位结果写入对应输出寄存器。
task store_digit_result;
    begin
        case (item_index)
            IDX_THD_U: begin
                thd_u_hundreds    <= calc_hundreds;
                thd_u_tens        <= calc_tens;
                thd_u_units       <= calc_units;
                thd_u_decile      <= calc_decile;
                thd_u_percentiles <= digit_work[7:0];
                thd_u_valid       <= thd_u_valid_in;
            end

            IDX_THD_I: begin
                thd_i_hundreds    <= calc_hundreds;
                thd_i_tens        <= calc_tens;
                thd_i_units       <= calc_units;
                thd_i_decile      <= calc_decile;
                thd_i_percentiles <= digit_work[7:0];
                thd_i_valid       <= thd_i_valid_in;
            end

            IDX_U1_MAG: begin
                u1_mag_hundreds    <= calc_hundreds;
                u1_mag_tens        <= calc_tens;
                u1_mag_units       <= calc_units;
                u1_mag_decile      <= calc_decile;
                u1_mag_percentiles <= digit_work[7:0];
                u1_mag_valid       <= u1_mag_valid_in;
            end

            IDX_I1_MAG: begin
                i1_mag_hundreds    <= calc_hundreds;
                i1_mag_tens        <= calc_tens;
                i1_mag_units       <= calc_units;
                i1_mag_decile      <= calc_decile;
                i1_mag_percentiles <= digit_work[7:0];
                i1_mag_valid       <= i1_mag_valid_in;
            end

            IDX_PHASE1: begin
                phase1_neg         <= phase1_x100[31] && (phase1_abs_x100 != 32'd0);
                phase1_hundreds    <= calc_hundreds;
                phase1_tens        <= calc_tens;
                phase1_units       <= calc_units;
                phase1_decile      <= calc_decile;
                phase1_percentiles <= digit_work[7:0];
                phase1_valid       <= phase1_valid_in;
            end

            IDX_DC_U: begin
                dc_u_hundreds    <= calc_hundreds;
                dc_u_tens        <= calc_tens;
                dc_u_units       <= calc_units;
                dc_u_decile      <= calc_decile;
                dc_u_percentiles <= digit_work[7:0];
                dc_u_valid       <= dc_u_valid_in;
            end

            IDX_DC_I: begin
                dc_i_hundreds    <= calc_hundreds;
                dc_i_tens        <= calc_tens;
                dc_i_units       <= calc_units;
                dc_i_decile      <= calc_decile;
                dc_i_percentiles <= digit_work[7:0];
                dc_i_valid       <= dc_i_valid_in;
            end

            IDX_DH_ORDER_U: begin
                dh_order_u_hundreds <= calc_hundreds;
                dh_order_u_tens     <= calc_tens;
                dh_order_u_units    <= calc_units;
                dh_order_u_valid    <= dh_order_u_valid_in;
            end

            IDX_DH_ORDER_I: begin
                dh_order_i_hundreds <= calc_hundreds;
                dh_order_i_tens     <= calc_tens;
                dh_order_i_units    <= calc_units;
                dh_order_i_valid    <= dh_order_i_valid_in;
            end

            default: begin
            end
        endcase
    end
endtask

// 串行锁存每个字段的拆位结果，完成后给上级一个 done 脉冲。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        busy                  <= 1'b0;
        item_index            <= IDX_THD_U;
        digit_state           <= DIG_LOAD;
        digit_work            <= 32'd0;
        calc_hundreds         <= 8'd0;
        calc_tens             <= 8'd0;
        calc_units            <= 8'd0;
        calc_decile           <= 8'd0;
        done                  <= 1'b0;
        thd_u_hundreds        <= 8'd0;
        thd_u_tens            <= 8'd0;
        thd_u_units           <= 8'd0;
        thd_u_decile          <= 8'd0;
        thd_u_percentiles     <= 8'd0;
        thd_u_valid           <= 1'b0;
        thd_i_hundreds        <= 8'd0;
        thd_i_tens            <= 8'd0;
        thd_i_units           <= 8'd0;
        thd_i_decile          <= 8'd0;
        thd_i_percentiles     <= 8'd0;
        thd_i_valid           <= 1'b0;
        u1_mag_hundreds       <= 8'd0;
        u1_mag_tens           <= 8'd0;
        u1_mag_units          <= 8'd0;
        u1_mag_decile         <= 8'd0;
        u1_mag_percentiles    <= 8'd0;
        u1_mag_valid          <= 1'b0;
        i1_mag_hundreds       <= 8'd0;
        i1_mag_tens           <= 8'd0;
        i1_mag_units          <= 8'd0;
        i1_mag_decile         <= 8'd0;
        i1_mag_percentiles    <= 8'd0;
        i1_mag_valid          <= 1'b0;
        phase1_neg            <= 1'b0;
        phase1_hundreds       <= 8'd0;
        phase1_tens           <= 8'd0;
        phase1_units          <= 8'd0;
        phase1_decile         <= 8'd0;
        phase1_percentiles    <= 8'd0;
        phase1_valid          <= 1'b0;
        dc_u_hundreds         <= 8'd0;
        dc_u_tens             <= 8'd0;
        dc_u_units            <= 8'd0;
        dc_u_decile           <= 8'd0;
        dc_u_percentiles      <= 8'd0;
        dc_u_valid            <= 1'b0;
        dc_i_hundreds         <= 8'd0;
        dc_i_tens             <= 8'd0;
        dc_i_units            <= 8'd0;
        dc_i_decile           <= 8'd0;
        dc_i_percentiles      <= 8'd0;
        dc_i_valid            <= 1'b0;
        dh_order_u_hundreds   <= 8'd0;
        dh_order_u_tens       <= 8'd0;
        dh_order_u_units      <= 8'd0;
        dh_order_u_valid      <= 1'b0;
        dh_order_i_hundreds   <= 8'd0;
        dh_order_i_tens       <= 8'd0;
        dh_order_i_units      <= 8'd0;
        dh_order_i_valid      <= 1'b0;
    end else begin
        done <= 1'b0;

        if (start && !busy) begin
            busy       <= 1'b1;
            item_index <= IDX_THD_U;
            digit_state <= DIG_LOAD;
        end else if (busy) begin
            case (digit_state)
                DIG_LOAD: begin
                    digit_work    <= select_digit_value(item_index);
                    calc_hundreds <= 8'd0;
                    calc_tens     <= 8'd0;
                    calc_units    <= 8'd0;
                    calc_decile   <= 8'd0;
                    digit_state   <= DIG_HUNDREDS;
                end

                DIG_HUNDREDS: begin
                    if ((digit_work >= 32'd10000) && (calc_hundreds < 8'd9)) begin
                        digit_work    <= digit_work - 32'd10000;
                        calc_hundreds <= calc_hundreds + 8'd1;
                    end else begin
                        digit_state <= DIG_TENS;
                    end
                end

                DIG_TENS: begin
                    if ((digit_work >= 32'd1000) && (calc_tens < 8'd9)) begin
                        digit_work <= digit_work - 32'd1000;
                        calc_tens  <= calc_tens + 8'd1;
                    end else begin
                        digit_state <= DIG_UNITS;
                    end
                end

                DIG_UNITS: begin
                    if ((digit_work >= 32'd100) && (calc_units < 8'd9)) begin
                        digit_work <= digit_work - 32'd100;
                        calc_units <= calc_units + 8'd1;
                    end else begin
                        digit_state <= DIG_DECILE;
                    end
                end

                DIG_DECILE: begin
                    if ((digit_work >= 32'd10) && (calc_decile < 8'd9)) begin
                        digit_work  <= digit_work - 32'd10;
                        calc_decile <= calc_decile + 8'd1;
                    end else begin
                        digit_state <= DIG_STORE;
                    end
                end

                DIG_STORE: begin
                    store_digit_result();

                    if (item_index == IDX_DH_ORDER_I) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                    end else begin
                        item_index  <= next_item_index(item_index);
                        digit_state <= DIG_LOAD;
                    end
                end

                default: begin
                    busy        <= 1'b0;
                    item_index  <= IDX_THD_U;
                    digit_state <= DIG_LOAD;
                end
            endcase
        end
    end
end

endmodule
