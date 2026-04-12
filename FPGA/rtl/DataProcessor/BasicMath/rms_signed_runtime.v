`timescale 1ns / 1ps

/*
 * 模块: rms_signed_runtime
 * 功能:
 *   对运行时指定数量 N 的 16bit 补码离散样本执行 RMS 计算，
 *   即先累加每个样本的平方，再除以 N 得到均方值，最后开平方得到 RMS。
 *
 * 使用约定:
 *   - start 仅在空闲状态下拉高 1 拍，用于启动一次新的 RMS 计算
 *   - start 后应送入恰好 N 个 sample_valid 有效样本
 *   - N 由输入端口给定，不使用参数固定
 *   - rms_valid 在结果就绪时拉高 1 拍
 *
 * 输入:
 *   clk: 模块工作时钟
 *   rst_n: 低有效复位
 *   start: 启动一次新的 RMS 计算
 *   sample_count_n: 本次参与 RMS 计算的样本数 N
 *   sample_valid: 输入样本有效标志
 *   sample_in: 输入的 16bit 补码样本
 *
 * 输出:
 *   busy: 模块忙标志，高电平表示正在接收样本或执行除法/开方
 *   rms_valid: RMS 结果有效脉冲
 *   rms_out: 计算得到的 16bit 补码 RMS 值
 */
module rms_signed_runtime #(
    parameter integer DATA_WIDTH = 16,
    parameter integer N_WIDTH    = 16,
    parameter integer SQ_WIDTH   = DATA_WIDTH * 2,
    parameter integer ACC_WIDTH  = SQ_WIDTH + N_WIDTH
)(
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         start,
    input  wire [N_WIDTH-1:0]           sample_count_n,
    input  wire                         sample_valid,
    input  wire signed [DATA_WIDTH-1:0] sample_in,
    output reg                          busy,
    output reg                          rms_valid,
    output reg  signed [DATA_WIDTH-1:0] rms_out
);

localparam integer SQRT_ROOT_WIDTH = (ACC_WIDTH + 1) / 2;
localparam [SQRT_ROOT_WIDTH-1:0] RMS_OUT_MAX = {{(SQRT_ROOT_WIDTH - DATA_WIDTH){1'b0}}, 16'h7FFF};

localparam [2:0] ST_IDLE       = 3'd0;
localparam [2:0] ST_ACCUM      = 3'd1;
localparam [2:0] ST_DIV_START  = 3'd2;
localparam [2:0] ST_DIV_WAIT   = 3'd3;
localparam [2:0] ST_SQRT_START = 3'd4;
localparam [2:0] ST_SQRT_WAIT  = 3'd5;

// 对 -32768 这类补码样本直接平方，结果为非负无符号值
wire signed [SQ_WIDTH-1:0] sample_square_signed;
wire [SQ_WIDTH-1:0]        sample_square;

reg  [2:0]                 state;
reg  [N_WIDTH-1:0]         sample_target;
reg  [N_WIDTH-1:0]         sample_count;
reg  [ACC_WIDTH-1:0]       sum_square_acc;
reg  [ACC_WIDTH-1:0]       mean_dividend_reg;
reg  [ACC_WIDTH-1:0]       mean_divisor_reg;
reg  [ACC_WIDTH-1:0]       mean_square_reg;
reg                        div_start;
reg                        sqrt_start;

wire                       div_busy;
wire                       div_done;
wire                       div_zero;
wire [ACC_WIDTH-1:0]       div_quotient;
wire                       sqrt_busy;
wire                       sqrt_done;
wire [SQRT_ROOT_WIDTH-1:0] sqrt_root;

assign sample_square_signed = sample_in * sample_in;
assign sample_square        = sample_square_signed[SQ_WIDTH-1:0];

divider_unsigned #(
    .WIDTH(ACC_WIDTH)
) u_rms_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (div_start),
    .dividend      (mean_dividend_reg),
    .divisor       (mean_divisor_reg),
    .busy          (div_busy),
    .done          (div_done),
    .divide_by_zero(div_zero),
    .quotient      (div_quotient)
);

sqrt_unsigned #(
    .RADICAND_WIDTH(ACC_WIDTH),
    .ROOT_WIDTH    (SQRT_ROOT_WIDTH)
) u_rms_sqrt (
    .clk     (clk),
    .rst_n   (rst_n),
    .start   (sqrt_start),
    .radicand(mean_square_reg),
    .busy    (sqrt_busy),
    .done    (sqrt_done),
    .root    (sqrt_root)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state            <= ST_IDLE;
        busy             <= 1'b0;
        rms_valid        <= 1'b0;
        rms_out          <= {DATA_WIDTH{1'b0}};
        sample_target    <= {N_WIDTH{1'b0}};
        sample_count     <= {N_WIDTH{1'b0}};
        sum_square_acc   <= {ACC_WIDTH{1'b0}};
        mean_dividend_reg<= {ACC_WIDTH{1'b0}};
        mean_divisor_reg <= {ACC_WIDTH{1'b0}};
        mean_square_reg  <= {ACC_WIDTH{1'b0}};
        div_start        <= 1'b0;
        sqrt_start       <= 1'b0;
    end else begin
        // 有效脉冲和启动脉冲默认先拉低
        rms_valid  <= 1'b0;
        div_start  <= 1'b0;
        sqrt_start <= 1'b0;

        case (state)
            ST_IDLE: begin
                busy <= 1'b0;

                if (start) begin
                    sample_target   <= sample_count_n;
                    sample_count    <= {N_WIDTH{1'b0}};
                    sum_square_acc  <= {ACC_WIDTH{1'b0}};
                    mean_square_reg <= {ACC_WIDTH{1'b0}};

                    if (sample_count_n == {N_WIDTH{1'b0}}) begin
                        // N=0 时直接返回 0，避免除零
                        rms_out   <= {DATA_WIDTH{1'b0}};
                        rms_valid <= 1'b1;
                    end else begin
                        busy  <= 1'b1;
                        state <= ST_ACCUM;
                    end
                end
            end

            ST_ACCUM: begin
                if (sample_valid) begin
                    if (sample_count == (sample_target - 1'b1)) begin
                        // 收到第 N 个样本后锁存平方和，并准备进入均值除法
                        mean_dividend_reg <= sum_square_acc + {{(ACC_WIDTH - SQ_WIDTH){1'b0}}, sample_square};
                        mean_divisor_reg  <= {{(ACC_WIDTH - N_WIDTH){1'b0}}, sample_target};
                        sample_count      <= {N_WIDTH{1'b0}};
                        state             <= ST_DIV_START;
                    end else begin
                        sample_count    <= sample_count + 1'b1;
                        sum_square_acc  <= sum_square_acc + {{(ACC_WIDTH - SQ_WIDTH){1'b0}}, sample_square};
                    end
                end
            end

            ST_DIV_START: begin
                div_start <= 1'b1;
                state     <= ST_DIV_WAIT;
            end

            ST_DIV_WAIT: begin
                if (div_done) begin
                    mean_square_reg <= div_zero ? {ACC_WIDTH{1'b0}} : div_quotient;
                    state           <= ST_SQRT_START;
                end
            end

            ST_SQRT_START: begin
                sqrt_start <= 1'b1;
                state      <= ST_SQRT_WAIT;
            end

            ST_SQRT_WAIT: begin
                if (sqrt_done) begin
                    // RMS 始终为非负值，超出 16bit 补码正数范围时饱和到 16'sh7FFF
                    if (sqrt_root > RMS_OUT_MAX)
                        rms_out <= 16'sh7FFF;
                    else
                        rms_out <= sqrt_root[DATA_WIDTH-1:0];

                    busy      <= 1'b0;
                    rms_valid <= 1'b1;
                    state     <= ST_IDLE;
                end
            end

            default: begin
                busy  <= 1'b0;
                state <= ST_IDLE;
            end
        endcase
    end
end

endmodule
