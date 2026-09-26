`timescale 1ns / 1ps

// One-DSP time-multiplexed 33x26 product.
// The four HH/HL/LH/LL partial products use one DSP transaction each.
// C_DATA_WIDTH=32 is sign-extended to the same 33-bit arithmetic contract.
//
// 2026-09-11 面积优化（等价重构，o_product_q15 逐位不变）：
//   原实现用 99 位累加器 + 变量移位 {{56{p[42]}},p} << {32,24,8,0} 来放置四个部分积，
//   综合后在 D=1 上占 194 LUT，其中 92 LUT 是"放置网络"。改法是把切分点从
//   data bit24 移到 data bit16（系数仍切 bit8），使四个权重组成为 24/16/8/0 —— **等差 8**：
//       data  = Da*2^16 + Db,   Da = data[32:16](有符号 17b), Db = data[15:0](无符号 16b)
//       coeff = Ch*2^8  + Cl,   Ch = coeff[25:8](有符号 18b), Cl = coeff[7:0] (无符号 8b)
//       prod  = DaCh*2^24 + DaCl*2^16 + DbCh*2^8 + DbCl
//   于是四拍阶梯只需"累加器常量左移 8 位"（纯连线），4 路移位 mux 整体消失：
//       ST_HH: acc <= DaCh                       (acc 源置 0，等价于装载)
//       ST_HL: acc <= (acc<<8) + DaCl
//       ST_LH: acc <= (acc<<8) + DbCh
//       ST_LL: o_product_q15 = (acc<<8) + DbCl   (组合输出，与原件同拍)
//   四拍时序、o_busy/o_done 语义、相位含义均不变；累加器收窄到 [58:0] 只影响被丢弃的高位。
//   等价性已用逐位模拟核对 400072 组（含极值），并在 XSim 冻结向量上回归（见 docs/E01）。
module e01_four_part_mul_dsp1 #(
    parameter integer C_DATA_WIDTH = 33
) (
    input  wire sys_clk,                                  // 50 MHz multiplier clock
    input  wire rst_n,                                    // Asynchronous active-low reset
    input  wire i_start,                                  // Starts one product transaction
    input  wire signed [C_DATA_WIDTH-1:0] i_data,         // Q15 state/residue operand
    input  wire signed [25:0] i_coefficient,              // Q2.24 coefficient
    output wire o_busy,                                   // Four-partial-product sequence active
    output wire o_done,                                   // Product is valid in this cycle
    output wire signed [34:0] o_product_q15               // Product after arithmetic Q24 removal
);
    localparam [2:0] ST_IDLE = 3'd0;
    localparam [2:0] ST_HH   = 3'd1;
    localparam [2:0] ST_HL   = 3'd2;
    localparam [2:0] ST_LH   = 3'd3;
    localparam [2:0] ST_LL   = 3'd4;

    reg [2:0] state_current;
    reg signed [32:0] data_reg;
    reg signed [25:0] coefficient_reg;
    reg signed [58:0] accumulated_product;   // 只需 [58:0]：输出只取 [58:24]

    wire signed [32:0] data_extended = i_data;
    wire signed [16:0] data_a = data_reg[32:16];   // Da：data[32:16]，有符号
    wire        [15:0] data_b = data_reg[15:0];    // Db：data[15:0]，无符号
    wire signed [17:0] coefficient_high = coefficient_reg[25:8];
    wire        [7:0]  coefficient_low = coefficient_reg[7:0];

    reg signed [24:0] dsp_data;
    reg signed [17:0] dsp_coefficient;
    (* use_dsp = "yes" *) wire signed [42:0] dsp_product;
    wire signed [58:0] product_term;
    wire signed [58:0] acc_src;
    wire signed [58:0] accumulated_next;

    assign dsp_product = dsp_data*dsp_coefficient;
    assign product_term = dsp_product;
    // ST_HH 是装载拍：把累加器源置 0，(0<<8)+DaCh 即等于装载
    assign acc_src = (state_current == ST_HH) ? 59'sd0 : accumulated_product;
    assign accumulated_next = (acc_src <<< 8)+product_term;
    assign o_busy = state_current != ST_IDLE;
    assign o_done = state_current == ST_LL;
    assign o_product_q15 = accumulated_next[58:24];

    always @(*) begin
        dsp_data = 25'sd0;
        dsp_coefficient = 18'sd0;
        case (state_current)
            ST_HH: begin
                dsp_data = data_a;
                dsp_coefficient = coefficient_high;
            end
            ST_HL: begin
                dsp_data = data_a;
                dsp_coefficient = {10'd0, coefficient_low};
            end
            ST_LH: begin
                dsp_data = {9'd0, data_b};
                dsp_coefficient = coefficient_high;
            end
            ST_LL: begin
                dsp_data = {9'd0, data_b};
                dsp_coefficient = {10'd0, coefficient_low};
            end
            default: begin end
        endcase
    end

    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            state_current <= ST_IDLE;
            data_reg <= 33'sd0;
            coefficient_reg <= 26'sd0;
            accumulated_product <= 59'sd0;
        end else begin
            case (state_current)
                ST_IDLE: begin
                    if (i_start) begin
                        data_reg <= data_extended;
                        coefficient_reg <= i_coefficient;
                        accumulated_product <= 59'sd0;
                        state_current <= ST_HH;
                    end
                end
                ST_HH: begin
                    accumulated_product <= accumulated_next;
                    state_current <= ST_HL;
                end
                ST_HL: begin
                    accumulated_product <= accumulated_next;
                    state_current <= ST_LH;
                end
                ST_LH: begin
                    accumulated_product <= accumulated_next;
                    state_current <= ST_LL;
                end
                ST_LL: begin
                    state_current <= ST_IDLE;
                end
                default: state_current <= ST_IDLE;
            endcase
        end
    end
endmodule

// Common D-lane scheduler for the E01 algorithm implementations.
// Each lane accepts one independent 33x26 transaction and maps directly to
// one four-partial-product arithmetic atom.  D therefore means the number of
// concurrently available multiplier lanes, not an algorithm-specific P/L
// parameter.  Every accepted transaction has the same HH/HL/LH/LL schedule
// and the same Q24 removal as the D=1 reference path.
module e01_four_part_mul_scheduler #(
    parameter integer C_D = 1,
    parameter integer C_DATA_WIDTH = 33
) (
    input  wire sys_clk,                                      // 50 MHz clock
    input  wire rst_n,                                        // Active-low asynchronous reset
    input  wire [C_D-1:0] i_start,                            // Per-lane transaction start
    input  wire signed [C_D*C_DATA_WIDTH-1:0] i_data,         // Packed per-lane Q15 operands
    input  wire signed [C_D*26-1:0] i_coefficient,            // Packed per-lane Q2.24 coefficients
    output wire [C_D-1:0] o_busy,                             // Per-lane four-part schedule active
    output wire [C_D-1:0] o_done,                             // Per-lane product-valid pulse
    output wire signed [C_D*35-1:0] o_product_q15            // Packed per-lane Q15 products
);
    genvar lane;
    generate
        for (lane = 0; lane < C_D; lane = lane + 1) begin : g_lane
            e01_four_part_mul_dsp1 #(
                .C_DATA_WIDTH(C_DATA_WIDTH)
            ) u_mul (
                .sys_clk(sys_clk),
                .rst_n(rst_n),
                .i_start(i_start[lane]),
                .i_data(i_data[lane*C_DATA_WIDTH +: C_DATA_WIDTH]),
                .i_coefficient(i_coefficient[lane*26 +: 26]),
                .o_busy(o_busy[lane]),
                .o_done(o_done[lane]),
                .o_product_q15(o_product_q15[lane*35 +: 35])
            );
        end
    endgenerate
endmodule
