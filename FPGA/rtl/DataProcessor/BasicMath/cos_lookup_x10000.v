`timescale 1ns / 1ps

/*
 * 模块: cos_lookup_x10000
 * 功能:
 *   将相位补码值转换为余弦补码值，输出采用 x10000 定点格式。
 *   例如:
 *   - phase_x100_signed = 17'sd1234 表示 +12.34°
 *   - cos_x10000_signed = 16'sd9781 表示 +0.9781
 *
 * 输入:
 *   clk: 系统时钟
 *   rst_n: 低有效复位
 *   start: 启动一次余弦查表
 *   phase_x100_signed: 输入相位，单位为 0.01°，采用 17bit 补码
 *
 * 输出:
 *   busy: 模块忙标志
 *   valid: 本次查表结果有效脉冲
 *   cos_x10000_signed: 余弦结果，采用 x10000 定点格式和 16bit 补码
 *
 * 说明:
 *   - 内部复用 divider_unsigned 计算 0.2° 地址，不直接使用 "/"。
 *   - 余弦 ROM 仅存储 0.0°~90.0° 的正值幅度，其他象限通过对称关系折叠并补符号。
 *   - 输入相位若超出 ±180.00°，会先钳位到该范围再参与查表。
 */
module cos_lookup_x10000 (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               start,
    input  wire signed [16:0] phase_x100_signed,
    output reg                busy,
    output reg                valid,
    output reg  signed [15:0] cos_x10000_signed
);

localparam [16:0] PHASE_ABS_MAX      = 17'd18000;
localparam [16:0] PHASE_QUADRANT_MAX = 17'd9000;
localparam [16:0] ADDR_STEP_X100     = 17'd20;
localparam [16:0] ADDR_ROUND_BIAS    = 17'd10;

localparam [2:0] ST_IDLE      = 3'd0;
localparam [2:0] ST_DIV_START = 3'd1;
localparam [2:0] ST_DIV_WAIT  = 3'd2;
localparam [2:0] ST_ROM_EN    = 3'd3;
localparam [2:0] ST_ROM_WAIT  = 3'd4;

reg  [2:0]        state;
reg  [16:0]       phase_abs_work;
reg  [16:0]       phase_folded_work;
reg               cos_neg_work;
reg               div_start;
reg  [16:0]       div_dividend;
reg  [8:0]        rom_addr;
reg               rom_en;
reg               cos_neg_pending;

wire              div_done;
wire              div_zero;
wire [16:0]       div_quotient;
wire [15:0]       rom_dout;

divider_unsigned #(
    .WIDTH(17)
) u_addr_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (div_start),
    .dividend      (div_dividend),
    .divisor       (ADDR_STEP_X100),
    .busy          (),
    .done          (div_done),
    .divide_by_zero(div_zero),
    .quotient      (div_quotient)
);

ROM_COS_0p2deg u_cos_rom (
    .clka  (clk),
    .ena   (rom_en),
    .addra (rom_addr),
    .douta (rom_dout)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state             <= ST_IDLE;
        busy              <= 1'b0;
        valid             <= 1'b0;
        cos_x10000_signed <= 16'sd0;
        phase_abs_work    <= 17'd0;
        phase_folded_work <= 17'd0;
        cos_neg_work      <= 1'b0;
        div_start         <= 1'b0;
        div_dividend      <= 17'd0;
        rom_addr          <= 9'd0;
        rom_en            <= 1'b0;
        cos_neg_pending   <= 1'b0;
    end else begin
        valid    <= 1'b0;
        div_start <= 1'b0;
        rom_en   <= 1'b0;

        case (state)
            ST_IDLE: begin
                busy <= 1'b0;

                if (start) begin
                    busy <= 1'b1;

                    // 先取绝对值，再限制到 180.00° 范围。
                    if (phase_x100_signed[16]) begin
                        phase_abs_work <= ((~phase_x100_signed) + 17'd1 > PHASE_ABS_MAX) ?
                                          PHASE_ABS_MAX : ((~phase_x100_signed) + 17'd1);
                    end else begin
                        phase_abs_work <= (phase_x100_signed > PHASE_ABS_MAX) ?
                                          PHASE_ABS_MAX : phase_x100_signed[16:0];
                    end

                    state <= ST_DIV_START;
                end
            end

            ST_DIV_START: begin
                // 利用余弦偶函数和 180° 对称性，将输入折叠到 0°~90° 的 ROM 地址范围。
                if (phase_abs_work > PHASE_QUADRANT_MAX) begin
                    phase_folded_work <= PHASE_ABS_MAX - phase_abs_work;
                    cos_neg_work      <= 1'b1;
                    div_dividend      <= (PHASE_ABS_MAX - phase_abs_work) + ADDR_ROUND_BIAS;
                end else begin
                    phase_folded_work <= phase_abs_work;
                    cos_neg_work      <= 1'b0;
                    div_dividend      <= phase_abs_work + ADDR_ROUND_BIAS;
                end

                div_start <= 1'b1;
                state     <= ST_DIV_WAIT;
            end

            ST_DIV_WAIT: begin
                if (div_done) begin
                    if (div_zero) begin
                        rom_addr        <= 9'd0;
                        cos_neg_pending <= 1'b0;
                    end else begin
                        if (div_quotient[8:0] > 9'd450)
                            rom_addr <= 9'd450;
                        else
                            rom_addr <= div_quotient[8:0];

                        cos_neg_pending <= cos_neg_work;
                    end

                    state <= ST_ROM_EN;
                end
            end

            ST_ROM_EN: begin
                rom_en <= 1'b1;
                state  <= ST_ROM_WAIT;
            end

            ST_ROM_WAIT: begin
                if (cos_neg_pending)
                    cos_x10000_signed <= ~rom_dout + 16'd1;
                else
                    cos_x10000_signed <= rom_dout;

                busy  <= 1'b0;
                valid <= 1'b1;
                state <= ST_IDLE;
            end

            default: begin
                state <= ST_IDLE;
                busy  <= 1'b0;
            end
        endcase
    end
end

endmodule
