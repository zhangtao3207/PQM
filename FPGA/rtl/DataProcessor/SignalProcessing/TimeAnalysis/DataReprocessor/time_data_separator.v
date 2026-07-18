/*
 * 模块: time_data_separator
 * 功能:
 *   在所有 x100 数据稳定后，统一提取符号位并拆分出 LCD 显示所需的十进制各位。
 *   本模块串行复用一组比较/减法逻辑，避免多个并行拆位器占用大量 LUT。
 * 输入:
 *   clk: 工作时钟。
 *   rst_n: 低有效复位。
 *   start: 启动一次统一拆位。
 *   u_rms_x100: 电压 RMS 的 x100 补码数据。
 *   i_rms_x100: 电流 RMS 的 x100 补码数据。
 *   rms_valid: RMS 数据是否有效。
 *   u_pp_x100: 电压峰峰值的 x100 补码数据。
 *   i_pp_x100: 电流峰峰值的 x100 补码数据。
 *   u_pp_valid: 电压峰峰值数据是否有效。
 *   i_pp_valid: 电流峰峰值数据是否有效。
 *   phase_x100_signed: 相位差的 x100 补码数据。
 *   phase_valid: 相位差数据是否有效。
 *   freq_x100: 频率的 x100 补码数据。
 *   freq_valid: 频率数据是否有效。
 *   active_p_x100: 有功功率的 x100 补码数据。
 *   reactive_q_x100: 无功功率的 x100 补码数据。
 *   apparent_s_x100: 视在功率的 x100 补码数据。
 *   power_factor_x100: 功率因数的 x100 补码数据。
 *   power_metrics_valid: 功率相关数据是否有效。
 * 输出:
 *   done: 本次统一拆位完成脉冲。
 *   各 sign/hundreds/tens/units/decile/percentiles/valid: 提供给显示链路的数字位与符号位。
 */
module time_data_separator (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    start,

    input  wire signed [31:0]      u_rms_x100,
    input  wire signed [31:0]      i_rms_x100,
    input  wire                    rms_valid,

    input  wire signed [31:0]      u_pp_x100,
    input  wire signed [31:0]      i_pp_x100,
    input  wire                    u_pp_valid,
    input  wire                    i_pp_valid,

    input  wire signed [31:0]      phase_x100_signed,
    input  wire                    phase_valid,

    input  wire signed [31:0]      freq_x100,
    input  wire                    freq_valid,

    input  wire signed [31:0]      active_p_x100,
    input  wire signed [31:0]      reactive_q_x100,
    input  wire signed [31:0]      apparent_s_x100,
    input  wire signed [31:0]      power_factor_x100,
    input  wire                    power_metrics_valid,

    output reg                     done,

    output reg [7:0]               u_rms_hundreds,
    output reg [7:0]               u_rms_tens,
    output reg [7:0]               u_rms_units,
    output reg [7:0]               u_rms_decile,
    output reg [7:0]               u_rms_percentiles,
    output reg                     u_rms_digits_valid,
    output reg [7:0]               i_rms_hundreds,
    output reg [7:0]               i_rms_tens,
    output reg [7:0]               i_rms_units,
    output reg [7:0]               i_rms_decile,
    output reg [7:0]               i_rms_percentiles,
    output reg                     i_rms_digits_valid,

    output reg                     phase_neg,
    output reg [7:0]               phase_hundreds,
    output reg [7:0]               phase_tens,
    output reg [7:0]               phase_units,
    output reg [7:0]               phase_decile,
    output reg [7:0]               phase_percentiles,
    output reg                     phase_digits_valid,

    output reg [7:0]               freq_hundreds,
    output reg [7:0]               freq_tens,
    output reg [7:0]               freq_units,
    output reg [7:0]               freq_decile,
    output reg [7:0]               freq_percentiles,
    output reg                     freq_digits_valid,

    output reg [7:0]               u_pp_hundreds,
    output reg [7:0]               u_pp_tens,
    output reg [7:0]               u_pp_units,
    output reg [7:0]               u_pp_decile,
    output reg [7:0]               u_pp_percentiles,
    output reg                     u_pp_digits_valid,
    output reg [7:0]               i_pp_hundreds,
    output reg [7:0]               i_pp_tens,
    output reg [7:0]               i_pp_units,
    output reg [7:0]               i_pp_decile,
    output reg [7:0]               i_pp_percentiles,
    output reg                     i_pp_digits_valid,

    output reg                     active_p_neg,
    output reg [7:0]               active_p_hundreds,
    output reg [7:0]               active_p_tens,
    output reg [7:0]               active_p_units,
    output reg [7:0]               active_p_decile,
    output reg [7:0]               active_p_percentiles,
    output reg                     reactive_q_neg,
    output reg [7:0]               reactive_q_hundreds,
    output reg [7:0]               reactive_q_tens,
    output reg [7:0]               reactive_q_units,
    output reg [7:0]               reactive_q_decile,
    output reg [7:0]               reactive_q_percentiles,
    output reg [7:0]               apparent_s_hundreds,
    output reg [7:0]               apparent_s_tens,
    output reg [7:0]               apparent_s_units,
    output reg [7:0]               apparent_s_decile,
    output reg [7:0]               apparent_s_percentiles,
    output reg                     power_factor_neg,
    output reg [7:0]               power_factor_hundreds,
    output reg [7:0]               power_factor_tens,
    output reg [7:0]               power_factor_units,
    output reg [7:0]               power_factor_decile,
    output reg [7:0]               power_factor_percentiles,
    output reg                     power_metrics_digits_valid
);

localparam [3:0] IDX_U_RMS       = 4'd0;
localparam [3:0] IDX_I_RMS       = 4'd1;
localparam [3:0] IDX_PHASE       = 4'd2;
localparam [3:0] IDX_FREQ        = 4'd3;
localparam [3:0] IDX_U_PP        = 4'd4;
localparam [3:0] IDX_I_PP        = 4'd5;
localparam [3:0] IDX_ACTIVE_P    = 4'd6;
localparam [3:0] IDX_REACTIVE_Q  = 4'd7;
localparam [3:0] IDX_APPARENT_S  = 4'd8;
localparam [3:0] IDX_POWER_FACT  = 4'd9;

localparam [2:0] DIG_LOAD     = 3'd0;
localparam [2:0] DIG_HUNDREDS = 3'd1;
localparam [2:0] DIG_TENS     = 3'd2;
localparam [2:0] DIG_UNITS    = 3'd3;
localparam [2:0] DIG_DECILE   = 3'd4;
localparam [2:0] DIG_STORE    = 3'd5;

reg       busy;
reg [3:0] item_index;
reg [2:0] digit_state;
reg [31:0] digit_work;
reg [7:0]  calc_hundreds;
reg [7:0]  calc_tens;
reg [7:0]  calc_units;
reg [7:0]  calc_decile;

wire [31:0] u_rms_abs_value;
wire [31:0] i_rms_abs_value;
wire [31:0] u_pp_abs_value;
wire [31:0] i_pp_abs_value;
wire [31:0] phase_abs_value;
wire [31:0] freq_abs_value;
wire [31:0] active_p_abs_value;
wire [31:0] reactive_q_abs_value;
wire [31:0] apparent_s_abs_value;
wire [31:0] power_factor_abs_value;

// 将补码输入统一转换为绝对值，供后续十进制拆位流程使用。
function [31:0] abs_value_of;
    input signed [31:0] signed_value;
    begin
        abs_value_of = signed_value[31] ? (~signed_value + 32'd1) : signed_value[31:0];
    end
endfunction

assign u_rms_abs_value        = abs_value_of(u_rms_x100);
assign i_rms_abs_value        = abs_value_of(i_rms_x100);
assign u_pp_abs_value         = abs_value_of(u_pp_x100);
assign i_pp_abs_value         = abs_value_of(i_pp_x100);
assign phase_abs_value        = abs_value_of(phase_x100_signed);
assign freq_abs_value         = abs_value_of(freq_x100);
assign active_p_abs_value     = abs_value_of(active_p_x100);
assign reactive_q_abs_value   = abs_value_of(reactive_q_x100);
assign apparent_s_abs_value   = abs_value_of(apparent_s_x100);
assign power_factor_abs_value = abs_value_of(power_factor_x100);

// 根据当前字段选择要进入串行拆位流程的 x100 绝对值。
function [31:0] select_digit_value;
    input [3:0] index;
    begin
        select_digit_value = 32'd0;

        case (index)
            IDX_U_RMS:      select_digit_value = u_rms_abs_value;
            IDX_I_RMS:      select_digit_value = i_rms_abs_value;
            IDX_PHASE:      select_digit_value = phase_abs_value;
            IDX_FREQ:       select_digit_value = freq_abs_value;
            IDX_U_PP:       select_digit_value = u_pp_abs_value;
            IDX_I_PP:       select_digit_value = i_pp_abs_value;
            IDX_ACTIVE_P:   select_digit_value = active_p_abs_value;
            IDX_REACTIVE_Q: select_digit_value = reactive_q_abs_value;
            IDX_APPARENT_S: select_digit_value = apparent_s_abs_value;
            IDX_POWER_FACT: select_digit_value = power_factor_abs_value;
            default:        select_digit_value = 32'd0;
        endcase
    end
endfunction

// 当前字段完成后跳转到下一个字段。
function [3:0] next_item_index;
    input [3:0] index;
    begin
        next_item_index = IDX_U_RMS;

        case (index)
            IDX_U_RMS:      next_item_index = IDX_I_RMS;
            IDX_I_RMS:      next_item_index = IDX_PHASE;
            IDX_PHASE:      next_item_index = IDX_FREQ;
            IDX_FREQ:       next_item_index = IDX_U_PP;
            IDX_U_PP:       next_item_index = IDX_I_PP;
            IDX_I_PP:       next_item_index = IDX_ACTIVE_P;
            IDX_ACTIVE_P:   next_item_index = IDX_REACTIVE_Q;
            IDX_REACTIVE_Q: next_item_index = IDX_APPARENT_S;
            IDX_APPARENT_S: next_item_index = IDX_POWER_FACT;
            default:        next_item_index = IDX_U_RMS;
        endcase
    end
endfunction

// 把当前字段的拆位结果写入对应输出寄存器。
task store_digit_result;
    begin
        case (item_index)
            IDX_U_RMS: begin
                u_rms_hundreds     <= calc_hundreds;
                u_rms_tens         <= calc_tens;
                u_rms_units        <= calc_units;
                u_rms_decile       <= calc_decile;
                u_rms_percentiles  <= digit_work[7:0];
                u_rms_digits_valid <= rms_valid;
            end

            IDX_I_RMS: begin
                i_rms_hundreds     <= calc_hundreds;
                i_rms_tens         <= calc_tens;
                i_rms_units        <= calc_units;
                i_rms_decile       <= calc_decile;
                i_rms_percentiles  <= digit_work[7:0];
                i_rms_digits_valid <= rms_valid;
            end

            IDX_PHASE: begin
                phase_neg          <= phase_x100_signed[31] && (phase_abs_value != 32'd0);
                phase_hundreds     <= calc_hundreds;
                phase_tens         <= calc_tens;
                phase_units        <= calc_units;
                phase_decile       <= calc_decile;
                phase_percentiles  <= digit_work[7:0];
                phase_digits_valid <= phase_valid;
            end

            IDX_FREQ: begin
                freq_hundreds     <= calc_hundreds;
                freq_tens         <= calc_tens;
                freq_units        <= calc_units;
                freq_decile       <= calc_decile;
                freq_percentiles  <= digit_work[7:0];
                freq_digits_valid <= freq_valid;
            end

            IDX_U_PP: begin
                u_pp_hundreds     <= calc_hundreds;
                u_pp_tens         <= calc_tens;
                u_pp_units        <= calc_units;
                u_pp_decile       <= calc_decile;
                u_pp_percentiles  <= digit_work[7:0];
                u_pp_digits_valid <= u_pp_valid;
            end

            IDX_I_PP: begin
                i_pp_hundreds     <= calc_hundreds;
                i_pp_tens         <= calc_tens;
                i_pp_units        <= calc_units;
                i_pp_decile       <= calc_decile;
                i_pp_percentiles  <= digit_work[7:0];
                i_pp_digits_valid <= i_pp_valid;
            end

            IDX_ACTIVE_P: begin
                active_p_neg         <= active_p_x100[31] && (active_p_abs_value != 32'd0);
                active_p_hundreds    <= calc_hundreds;
                active_p_tens        <= calc_tens;
                active_p_units       <= calc_units;
                active_p_decile      <= calc_decile;
                active_p_percentiles <= digit_work[7:0];
            end

            IDX_REACTIVE_Q: begin
                reactive_q_neg         <= reactive_q_x100[31] && (reactive_q_abs_value != 32'd0);
                reactive_q_hundreds    <= calc_hundreds;
                reactive_q_tens        <= calc_tens;
                reactive_q_units       <= calc_units;
                reactive_q_decile      <= calc_decile;
                reactive_q_percentiles <= digit_work[7:0];
            end

            IDX_APPARENT_S: begin
                apparent_s_hundreds    <= calc_hundreds;
                apparent_s_tens        <= calc_tens;
                apparent_s_units       <= calc_units;
                apparent_s_decile      <= calc_decile;
                apparent_s_percentiles <= digit_work[7:0];
            end

            IDX_POWER_FACT: begin
                power_factor_neg         <= power_factor_x100[31] && (power_factor_abs_value != 32'd0);
                power_factor_hundreds    <= calc_hundreds;
                power_factor_tens        <= calc_tens;
                power_factor_units       <= calc_units;
                power_factor_decile      <= calc_decile;
                power_factor_percentiles <= digit_work[7:0];
                power_metrics_digits_valid <= power_metrics_valid;
            end

            default: begin
            end
        endcase
    end
endtask

// 串行完成所有时域文本字段的拆位，完成后给上级 done 脉冲。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        busy                       <= 1'b0;
        item_index                 <= IDX_U_RMS;
        digit_state                <= DIG_LOAD;
        digit_work                 <= 32'd0;
        calc_hundreds              <= 8'd0;
        calc_tens                  <= 8'd0;
        calc_units                 <= 8'd0;
        calc_decile                <= 8'd0;
        done                       <= 1'b0;
        u_rms_hundreds             <= 8'd0;
        u_rms_tens                 <= 8'd0;
        u_rms_units                <= 8'd0;
        u_rms_decile               <= 8'd0;
        u_rms_percentiles          <= 8'd0;
        u_rms_digits_valid         <= 1'b0;
        i_rms_hundreds             <= 8'd0;
        i_rms_tens                 <= 8'd0;
        i_rms_units                <= 8'd0;
        i_rms_decile               <= 8'd0;
        i_rms_percentiles          <= 8'd0;
        i_rms_digits_valid         <= 1'b0;
        phase_neg                  <= 1'b0;
        phase_hundreds             <= 8'd0;
        phase_tens                 <= 8'd0;
        phase_units                <= 8'd0;
        phase_decile               <= 8'd0;
        phase_percentiles          <= 8'd0;
        phase_digits_valid         <= 1'b0;
        freq_hundreds              <= 8'd0;
        freq_tens                  <= 8'd0;
        freq_units                 <= 8'd0;
        freq_decile                <= 8'd0;
        freq_percentiles           <= 8'd0;
        freq_digits_valid          <= 1'b0;
        u_pp_hundreds              <= 8'd0;
        u_pp_tens                  <= 8'd0;
        u_pp_units                 <= 8'd0;
        u_pp_decile                <= 8'd0;
        u_pp_percentiles           <= 8'd0;
        u_pp_digits_valid          <= 1'b0;
        i_pp_hundreds              <= 8'd0;
        i_pp_tens                  <= 8'd0;
        i_pp_units                 <= 8'd0;
        i_pp_decile                <= 8'd0;
        i_pp_percentiles           <= 8'd0;
        i_pp_digits_valid          <= 1'b0;
        active_p_neg               <= 1'b0;
        active_p_hundreds          <= 8'd0;
        active_p_tens              <= 8'd0;
        active_p_units             <= 8'd0;
        active_p_decile            <= 8'd0;
        active_p_percentiles       <= 8'd0;
        reactive_q_neg             <= 1'b0;
        reactive_q_hundreds        <= 8'd0;
        reactive_q_tens            <= 8'd0;
        reactive_q_units           <= 8'd0;
        reactive_q_decile          <= 8'd0;
        reactive_q_percentiles     <= 8'd0;
        apparent_s_hundreds        <= 8'd0;
        apparent_s_tens            <= 8'd0;
        apparent_s_units           <= 8'd0;
        apparent_s_decile          <= 8'd0;
        apparent_s_percentiles     <= 8'd0;
        power_factor_neg           <= 1'b0;
        power_factor_hundreds      <= 8'd0;
        power_factor_tens          <= 8'd0;
        power_factor_units         <= 8'd0;
        power_factor_decile        <= 8'd0;
        power_factor_percentiles   <= 8'd0;
        power_metrics_digits_valid <= 1'b0;
    end else begin
        done <= 1'b0;

        if (start && !busy) begin
            busy        <= 1'b1;
            item_index  <= IDX_U_RMS;
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

                    if (item_index == IDX_POWER_FACT) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                    end else begin
                        item_index  <= next_item_index(item_index);
                        digit_state <= DIG_LOAD;
                    end
                end

                default: begin
                    busy        <= 1'b0;
                    item_index  <= IDX_U_RMS;
                    digit_state <= DIG_LOAD;
                end
            endcase
        end
    end
end

endmodule
