`timescale 1ns / 1ps

/*
 * 模块: p2p_measure
 * 功能:
 *   在一次采样窗口内统计输入码值的最大值和最小值，
 *   输出峰峰值码差的原始结果，供上层统一换算为显示用 x100 数据。
 * 输入:
 *   clk: 工作时钟。
 *   rst_n: 低有效复位。
 *   start: 启动一次峰峰值测量。
 *   sample_count_n: 本次测量允许处理的采样点数。
 *   sample_valid: 当前采样是否有效。
 *   sample_code: 当前采样码值。
 * 输出:
 *   busy: 当前峰峰值测量流程是否仍在进行。
 *   done: 本次测量结束时给出的完成脉冲。
 *   p2p_raw: 峰峰值原始码差，统一扩展为 32 位补码。
 *   p2p_valid: 本次原始峰峰值结果是否有效。
 */
module p2p_measure #(
    parameter integer WIDTH             = 16,
    parameter integer MAX_FRAME_SAMPLES = 4096,
    parameter integer N_WIDTH           = (MAX_FRAME_SAMPLES <= 2) ? 2 : $clog2(MAX_FRAME_SAMPLES)
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               start,
    input  wire [N_WIDTH-1:0] sample_count_n,
    input  wire               sample_valid,
    input  wire [WIDTH-1:0]   sample_code,
    output reg                busy,
    output reg                done,
    output reg  signed [31:0] p2p_raw,
    output reg                p2p_valid
);

localparam [1:0] ST_IDLE    = 2'd0;
localparam [1:0] ST_CAPTURE = 2'd1;

reg  [1:0]          state;
reg  [N_WIDTH-1:0]  sample_target;
reg  [N_WIDTH-1:0]  sample_count;
reg  [WIDTH-1:0]    min_code;
reg  [WIDTH-1:0]    max_code;
reg                 seen_sample;
wire [WIDTH:0]      p2p_diff_unsigned;

// 将窗口内最大值与最小值相减，得到无符号峰峰值码差。
assign p2p_diff_unsigned = {1'b0, max_code} - {1'b0, min_code};

// 在采样窗口内持续更新最小值和最大值，窗口结束时统一锁存原始峰峰值结果。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state         <= ST_IDLE;
        sample_target <= {N_WIDTH{1'b0}};
        sample_count  <= {N_WIDTH{1'b0}};
        min_code      <= {WIDTH{1'b1}};
        max_code      <= {WIDTH{1'b0}};
        seen_sample   <= 1'b0;
        busy          <= 1'b0;
        done          <= 1'b0;
        p2p_raw       <= 32'sd0;
        p2p_valid     <= 1'b0;
    end else begin
        done      <= 1'b0;
        p2p_valid <= 1'b0;

        case (state)
            ST_IDLE: begin
                busy <= 1'b0;

                if (start) begin
                    sample_target <= sample_count_n;
                    sample_count  <= {N_WIDTH{1'b0}};
                    min_code      <= {WIDTH{1'b1}};
                    max_code      <= {WIDTH{1'b0}};
                    seen_sample   <= 1'b0;

                    if (sample_count_n == {N_WIDTH{1'b0}}) begin
                        done  <= 1'b1;
                        state <= ST_IDLE;
                    end else begin
                        busy  <= 1'b1;
                        state <= ST_CAPTURE;
                    end
                end
            end

            ST_CAPTURE: begin
                if (sample_valid) begin
                    if (!seen_sample) begin
                        min_code    <= sample_code;
                        max_code    <= sample_code;
                        seen_sample <= 1'b1;
                    end else begin
                        if (sample_code < min_code)
                            min_code <= sample_code;
                        if (sample_code > max_code)
                            max_code <= sample_code;
                    end

                    if (sample_count == (sample_target - 1'b1)) begin
                        if (seen_sample || (sample_count_n != {N_WIDTH{1'b0}})) begin
                            p2p_raw   <= {{(31 - WIDTH){1'b0}}, p2p_diff_unsigned};
                            p2p_valid <= 1'b1;
                        end
                        busy         <= 1'b0;
                        done         <= 1'b1;
                        sample_count <= {N_WIDTH{1'b0}};
                        state        <= ST_IDLE;
                    end else begin
                        sample_count <= sample_count + {{(N_WIDTH - 1){1'b0}}, 1'b1};
                    end
                end
            end

            default: begin
                busy  <= 1'b0;
                done  <= 1'b0;
                state <= ST_IDLE;
            end
        endcase
    end
end

endmodule
