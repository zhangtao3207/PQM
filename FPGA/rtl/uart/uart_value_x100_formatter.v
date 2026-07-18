`timescale 1ns / 1ps

/*
 * 模块: uart_value_x100_formatter
 * 功能:
 *   以串行减法方式把一个 `x100` 无符号定点数拆成百位、十位、个位、十分位和百分位。
 *   该模块面向 UART ASCII 发送链路，使用一个共享减法器逐位工作，避免并行组合拆位带来的 LUT 开销。
 *
 * 输入:
 *   clk: 模块工作时钟。
 *   rst_n: 低有效复位信号。
 *   start: 单周期启动脉冲；仅在空闲时采样。
 *   value_x100: 待拆分的 `x100` 定点值，例如 `16'd1234` 表示 `12.34`。
 *
 * 输出:
 *   busy: 当前正在执行拆位流程。
 *   done: 本次拆位完成的单周期脉冲。
 *   hundreds: 拆出的百位数字。
 *   tens: 拆出的十位数字。
 *   units: 拆出的个位数字。
 *   decile: 拆出的十分位数字。
 *   percentiles: 拆出的百分位数字。
 */
module uart_value_x100_formatter (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       start,
    input  wire [15:0] value_x100,
    output reg        busy,
    output reg        done,
    output reg  [3:0] hundreds,
    output reg  [3:0] tens,
    output reg  [3:0] units,
    output reg  [3:0] decile,
    output reg  [3:0] percentiles
);

localparam [2:0] ST_IDLE     = 3'd0;
localparam [2:0] ST_HUNDREDS = 3'd1;
localparam [2:0] ST_TENS     = 3'd2;
localparam [2:0] ST_UNITS    = 3'd3;
localparam [2:0] ST_DECILE   = 3'd4;

reg [2:0]  state;
reg [15:0] work_value;

// 顺序执行 10000/1000/100/10 的重复减法，复用一条窄算术路径完成 `x100` 数值拆位。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state       <= ST_IDLE;
        work_value  <= 16'd0;
        busy        <= 1'b0;
        done        <= 1'b0;
        hundreds    <= 4'd0;
        tens        <= 4'd0;
        units       <= 4'd0;
        decile      <= 4'd0;
        percentiles <= 4'd0;
    end else begin
        done <= 1'b0;

        case (state)
            ST_IDLE: begin
                if (start) begin
                    work_value  <= value_x100;
                    busy        <= 1'b1;
                    hundreds    <= 4'd0;
                    tens        <= 4'd0;
                    units       <= 4'd0;
                    decile      <= 4'd0;
                    percentiles <= 4'd0;
                    state       <= ST_HUNDREDS;
                end
            end

            ST_HUNDREDS: begin
                if ((work_value >= 16'd10000) && (hundreds != 4'd9)) begin
                    work_value <= work_value - 16'd10000;
                    hundreds   <= hundreds + 4'd1;
                end else begin
                    state <= ST_TENS;
                end
            end

            ST_TENS: begin
                if ((work_value >= 16'd1000) && (tens != 4'd9)) begin
                    work_value <= work_value - 16'd1000;
                    tens       <= tens + 4'd1;
                end else begin
                    state <= ST_UNITS;
                end
            end

            ST_UNITS: begin
                if ((work_value >= 16'd100) && (units != 4'd9)) begin
                    work_value <= work_value - 16'd100;
                    units      <= units + 4'd1;
                end else begin
                    state <= ST_DECILE;
                end
            end

            ST_DECILE: begin
                if ((work_value >= 16'd10) && (decile != 4'd9)) begin
                    work_value <= work_value - 16'd10;
                    decile     <= decile + 4'd1;
                end else begin
                    percentiles <= work_value[3:0];
                    busy        <= 1'b0;
                    done        <= 1'b1;
                    state       <= ST_IDLE;
                end
            end

            default: begin
                state <= ST_IDLE;
                busy  <= 1'b0;
            end
        endcase
    end
end

endmodule
