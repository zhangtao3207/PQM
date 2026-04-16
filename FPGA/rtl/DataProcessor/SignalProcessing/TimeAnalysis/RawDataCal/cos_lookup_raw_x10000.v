`timescale 1ns / 1ps

/*
 * 模块: cos_lookup_raw_x10000
 * 功能:
 *   接收相位差原始偏移计数和周期计数，直接换算为 cos(phi) 的 x10000 补码结果。
 *   本模块不对外输出 phase_x100，只为功率原始量计算提供 cos(phi) 和相位正负号。
 * 输入:
 *   clk: 工作时钟。
 *   rst_n: 低有效复位。
 *   start: 启动一次 raw phase 到 cos(phi) 的换算。
 *   phase_offset_raw: 相位差原始偏移计数。
 *   phase_period_raw: 相位差原始周期计数。
 * 输出:
 *   busy: 当前换算流程是否仍在进行。
 *   valid: 本次 cos(phi) 结果有效脉冲。
 *   phase_neg: 相位折算到 [-180,180] 后是否为负。
 *   cos_x10000_signed: cos(phi) 的 x10000 补码结果。
 */
module cos_lookup_raw_x10000 (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               start,
    input  wire signed [31:0] phase_offset_raw,
    input  wire signed [31:0] phase_period_raw,
    output reg                busy,
    output reg                valid,
    output reg                phase_neg,
    output reg  signed [15:0] cos_x10000_signed
);

localparam [15:0] FULL_CIRCLE_ADDR_MAX = 16'd1800;
localparam [15:0] HALF_CIRCLE_ADDR_MAX = 16'd900;
localparam [15:0] QUADRANT_ADDR_MAX    = 16'd450;
localparam [15:0] RAW_TO_ADDR_SCALE    = 16'd1800;

localparam [2:0] ST_IDLE      = 3'd0;
localparam [2:0] ST_DIV_START = 3'd1;
localparam [2:0] ST_DIV_WAIT  = 3'd2;
localparam [2:0] ST_ROM_EN    = 3'd3;
localparam [2:0] ST_ROM_WAIT  = 3'd4;

reg  [2:0]               state;
reg  signed [31:0]       work_phase_offset_raw;
reg  signed [31:0]       work_phase_period_raw;
reg                      div_start;
reg  [47:0]              div_dividend;
reg  [47:0]              div_divisor;
reg  [8:0]               rom_addr;
reg                      rom_en;
reg                      cos_neg_pending;
reg                      phase_neg_pending;
reg  [15:0]              full_circle_addr;

wire [31:0]              phase_offset_abs;
wire signed [47:0]       raw_to_addr_product_signed;
wire [47:0]              raw_to_addr_product_unsigned;
wire                     div_done;
wire                     div_zero;
wire [47:0]              div_quotient;
wire [15:0]              rom_dout;

// 对相位偏移原始计数取绝对值，供后续换算完整相位地址使用。
assign phase_offset_abs = work_phase_offset_raw[31] ?
                          (~work_phase_offset_raw + 32'd1) :
                          work_phase_offset_raw[31:0];

// 将相位偏移计数乘以 1800，得到 0.2° 地址换算所需的分子。
multiplier_signed #(
    .A_WIDTH(32),
    .B_WIDTH(16)
) u_raw_to_addr_multiplier (
    .multiplicand({1'b0, phase_offset_abs[30:0]}),
    .multiplier  (RAW_TO_ADDR_SCALE),
    .product     (raw_to_addr_product_signed)
);

// 将乘积转换为无符号除法输入，负值统一按 0 处理。
assign raw_to_addr_product_unsigned = raw_to_addr_product_signed[47] ?
                                      48'd0 : raw_to_addr_product_signed[47:0];

// 对 raw 偏移与周期做比例归一，得到一圈 1800 个 0.2° 地址中的位置。
divider_unsigned #(
    .WIDTH(48)
) u_raw_phase_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (div_start),
    .dividend      (div_dividend),
    .divisor       (div_divisor),
    .busy          (),
    .done          (div_done),
    .divide_by_zero(div_zero),
    .quotient      (div_quotient)
);

// 复用现有余弦 ROM，只查 0°~90° 的正值幅度。
ROM_COS_0p2deg u_cos_rom (
    .clka  (clk),
    .ena   (rom_en),
    .addra (rom_addr),
    .douta (rom_dout)
);

// 顺序完成 raw phase 比例换算、象限折叠和余弦查表。
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state             <= ST_IDLE;
        busy              <= 1'b0;
        valid             <= 1'b0;
        phase_neg         <= 1'b0;
        cos_x10000_signed <= 16'sd0;
        work_phase_offset_raw <= 32'sd0;
        work_phase_period_raw <= 32'sd0;
        div_start         <= 1'b0;
        div_dividend      <= 48'd0;
        div_divisor       <= 48'd1;
        rom_addr          <= 9'd0;
        rom_en            <= 1'b0;
        cos_neg_pending   <= 1'b0;
        phase_neg_pending <= 1'b0;
        full_circle_addr  <= 16'd0;
    end else begin
        valid     <= 1'b0;
        div_start <= 1'b0;
        rom_en    <= 1'b0;

        case (state)
            ST_IDLE: begin
                busy <= 1'b0;

                if (start) begin
                    work_phase_offset_raw <= phase_offset_raw;
                    work_phase_period_raw <= phase_period_raw;

                    if (phase_period_raw[31] || (phase_period_raw == 32'sd0)) begin
                        phase_neg         <= 1'b0;
                        cos_x10000_signed <= 16'sd0;
                        valid             <= 1'b1;
                        state             <= ST_IDLE;
                    end else begin
                        busy  <= 1'b1;
                        state <= ST_DIV_START;
                    end
                end
            end

            ST_DIV_START: begin
                div_dividend <= raw_to_addr_product_unsigned + {16'd0, work_phase_period_raw[31:1]};
                div_divisor  <= {16'd0, work_phase_period_raw[31:0]};
                div_start    <= 1'b1;
                state        <= ST_DIV_WAIT;
            end

            ST_DIV_WAIT: begin
                if (div_done) begin
                    if (div_zero) begin
                        full_circle_addr  <= 16'd0;
                        phase_neg_pending <= 1'b0;
                        cos_neg_pending   <= 1'b0;
                        rom_addr          <= 9'd0;
                    end else begin
                        if ((div_quotient[47:16] != 32'd0) || (div_quotient[15:0] > FULL_CIRCLE_ADDR_MAX))
                            full_circle_addr <= FULL_CIRCLE_ADDR_MAX;
                        else
                            full_circle_addr <= div_quotient[15:0];

                        if ((div_quotient[47:16] != 32'd0) || (div_quotient[15:0] > FULL_CIRCLE_ADDR_MAX)) begin
                            phase_neg_pending <= 1'b0;
                            cos_neg_pending   <= 1'b0;
                            rom_addr          <= 9'd0;
                        end else if (div_quotient[15:0] > (HALF_CIRCLE_ADDR_MAX + QUADRANT_ADDR_MAX)) begin
                            phase_neg_pending <= 1'b1;
                            cos_neg_pending   <= 1'b0;
                            rom_addr          <= FULL_CIRCLE_ADDR_MAX - div_quotient[15:0];
                        end else if (div_quotient[15:0] > HALF_CIRCLE_ADDR_MAX) begin
                            phase_neg_pending <= 1'b1;
                            cos_neg_pending   <= 1'b1;
                            rom_addr          <= div_quotient[15:0] - HALF_CIRCLE_ADDR_MAX;
                        end else if (div_quotient[15:0] > QUADRANT_ADDR_MAX) begin
                            phase_neg_pending <= 1'b0;
                            cos_neg_pending   <= 1'b1;
                            rom_addr          <= HALF_CIRCLE_ADDR_MAX - div_quotient[15:0];
                        end else begin
                            phase_neg_pending <= 1'b0;
                            cos_neg_pending   <= 1'b0;
                            rom_addr          <= div_quotient[15:0];
                        end
                    end

                    state <= ST_ROM_EN;
                end
            end

            ST_ROM_EN: begin
                rom_en <= 1'b1;
                state  <= ST_ROM_WAIT;
            end

            ST_ROM_WAIT: begin
                phase_neg <= phase_neg_pending && (full_circle_addr != FULL_CIRCLE_ADDR_MAX);

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
