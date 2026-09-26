`timescale 1ns/1ps

// e01_rfg_fold_l4 —— L4 折叠前端原子件。
//
// 统一契约见 e01_rfg_fold_l2.sv 的头部说明（19 个端口逐位同形）。
// 本模块不持有残差存储器；阵列由唯一顶层内联声明（理由见 fold_l2 头部）。
//
// L4 折叠算术：一列 4 个成员（x[c], x[c+N/4], x[c+N/2], x[c+3N/4]）按成员相位
// 折叠进 4 个 bank。实输入 L4 存在共轭对称，只需要 R0.re / R1.re / R2.re / R1.im：
//   成员 0: bank0+=x, bank1+=x, bank2+=x, bank3+=0
//   成员 1: bank0+=x, bank1+=0, bank2-=x, bank3-=x
//   成员 2: bank0+=x, bank1-=x, bank2+=x, bank3+=0
//   成员 3: bank0+=x, bank1+=0, bank2-=x, bank3+=x
// 成员 0 为初始化（不累加），与 v2 一致。
//
// 展开映射（含共轭重建）：
//   real[0..3] = {b0, b1, b2, b1}      R3.re = R1.re
//   imag[0..3] = {0,  b3, 0, -b3}      R3.im = -R1.im，R0/R2.im = 0
//
// 存储压缩：每个 bank 最多累加 4 个幅值 <= 2^16 的 Q15 项，19 位有符号覆盖
// [-4*2^16, 4*(2^16-2)]；Q15 项恒为偶数，故省去 bit0 存 18 位，读回左移还原。4*18 = 72 位/列。

// H14: this front end serves the matching engine bins 1..C_K.
// Unrequested numeric residues may be zero; declared storage geometry is unchanged.
module e01_rfg_fold_l4 #(
    parameter integer C_N = 64,
    parameter integer C_K = 24,
    parameter integer C_D = 1,
    parameter integer C_L = 4,
    parameter integer C_STORE_WIDTH = 18,       // 每 bank 存储位宽（value>>1）
    parameter integer C_BANKS = 4,
    parameter integer C_COLUMN_AW = ((C_N/C_L) <= 1) ? 1 : $clog2(C_N/C_L),
    parameter integer C_MEMBER_AW = (C_L <= 1) ? 1 : $clog2(C_L),
    parameter integer C_RESIDUE_AW = (C_L <= 1) ? 1 : $clog2(C_L)
) (
    input  wire                                     sys_clk,
    input  wire                                     rst_n,
    input  wire                                     i_start,
    input  wire                                     i_engine_busy,
    input  wire                                     i_sample_valid,
    input  wire signed [15:0]                       i_sample,
    output wire [C_COLUMN_AW-1:0]                   o_write_address,
    output wire                                     o_write_enable,
    output wire signed [C_BANKS*C_STORE_WIDTH-1:0]  o_write_data,
    output wire [C_COLUMN_AW-1:0]                   o_read_address,
    input  wire signed [C_BANKS*C_STORE_WIDTH-1:0]  i_word_read,
    output wire                                     o_fold_active,
    output wire                                     o_sample_ready,
    output wire                                     o_fold_overflow_sticky,
    output wire                                     o_fold_overflow_now,
    output wire                                     o_fold_done,
    input  wire [C_D*C_RESIDUE_AW-1:0]              i_lane_residue,
    output wire signed [C_D*32-1:0]                 o_residue_real,
    output wire signed [C_D*32-1:0]                 o_residue_imag
);
    localparam integer C_COLUMNS = C_N/C_L;
    localparam integer C_VALUE_WIDTH = C_STORE_WIDTH+1;     // 还原后的 19 位视图
    localparam integer C_EXTEND_AMOUNT = 32-C_VALUE_WIDTH;  // 19 -> 32 的符号扩展位数

    // H14: physical banks 1/3 jointly serve residue 1 and its conjugate.
    function automatic integer fold_bank_needed(input integer bank);
        begin
            case (bank)
                0: fold_bank_needed = (C_K >= 4);
                2: fold_bank_needed = (C_K >= 2);
                default: fold_bank_needed = 1;
            endcase
        end
    endfunction

    reg input_active;
    reg [C_MEMBER_AW-1:0] input_member;
    reg [C_COLUMN_AW-1:0] input_column;
    reg input_pending;
    reg [C_MEMBER_AW-1:0] input_member_hold;
    reg [C_COLUMN_AW-1:0] input_column_hold;
    reg signed [15:0] input_sample_hold;
    reg fold_overflow_reg;

    wire signed [15:0] sample_selected = input_pending ? input_sample_hold : i_sample;
    wire [C_MEMBER_AW-1:0] member_selected = input_pending ? input_member_hold : input_member;
    wire [C_COLUMN_AW-1:0] column_selected = input_pending ? input_column_hold : input_column;

    wire signed [32:0] input_sample_q15 = {{16{sample_selected[15]}},sample_selected,1'b0};

    // 打包字 -> 每个 bank 的 19 位值（省去 bit0）-> 32 位累加视图。纯连线。
    wire signed [C_VALUE_WIDTH-1:0] bank_value [0:C_BANKS-1];
    wire signed [31:0] bank_extended [0:C_BANKS-1];
    genvar bank_index;
    generate
        for (bank_index = 0; bank_index < C_BANKS; bank_index = bank_index+1) begin : g_bank_read
            assign bank_value[bank_index] =
                fold_bank_needed(bank_index) ?
                {i_word_read[bank_index*C_STORE_WIDTH +: C_STORE_WIDTH],1'b0} :
                {C_VALUE_WIDTH{1'b0}};
            assign bank_extended[bank_index] =
                {{C_EXTEND_AMOUNT{bank_value[bank_index][C_VALUE_WIDTH-1]}},bank_value[bank_index]};
        end
    endgenerate

    wire signed [C_VALUE_WIDTH-1:0] bank3_negative_value = -bank_value[3];
    // 展开映射表（19 位视图，保持“先取负再扩展”的精确顺序）。
    wire signed [C_VALUE_WIDTH-1:0] residue_real_value [0:3];
    wire signed [C_VALUE_WIDTH-1:0] residue_imag_value [0:3];
    assign residue_real_value[0] = bank_value[0];
    assign residue_real_value[1] = bank_value[1];
    assign residue_real_value[2] = bank_value[2];
    assign residue_real_value[3] = bank_value[1];
    assign residue_imag_value[0] = {C_VALUE_WIDTH{1'b0}};
    assign residue_imag_value[1] = bank_value[3];
    assign residue_imag_value[2] = {C_VALUE_WIDTH{1'b0}};
    assign residue_imag_value[3] = bank3_negative_value;

    reg signed [32:0] fold_term [0:C_BANKS-1];
    // 2026-09-11 面积优化（与 fold_l8 同）：累加器只需"值宽 + 1 位溢出位"。
    // 本模块存储 C_STORE_WIDTH=18 位表示 value>>1，故值宽 C_VALUE_WIDTH=19 位；
    // 原 36 位累加器多出的高位只服务"是否超出 32 位"这个判据，在 19 位值宽下没有意义。
    // 20 位加法的低位只取决于操作数低位 ⇒ 写入存储的数据逐位不变；溢出判据改为
    // "和的第 19 位与第 18 位不一致"（装不进 19 位有符号），对合法输入与旧判据等价。
    reg signed [C_VALUE_WIDTH:0] fold_next [0:C_BANKS-1];
    integer fold_index;
    always @* begin
        for (fold_index = 0; fold_index < C_BANKS; fold_index = fold_index+1)
            fold_term[fold_index] = 33'sd0;
        case (member_selected)
            2'd0: begin
                fold_term[0] = input_sample_q15;
                fold_term[1] = input_sample_q15;
                fold_term[2] = input_sample_q15;
            end
            2'd1: begin
                fold_term[0] = input_sample_q15;
                fold_term[2] = -input_sample_q15;
                fold_term[3] = -input_sample_q15;
            end
            2'd2: begin
                fold_term[0] = input_sample_q15;
                fold_term[1] = -input_sample_q15;
                fold_term[2] = input_sample_q15;
            end
            default: begin
                fold_term[0] = input_sample_q15;
                fold_term[2] = -input_sample_q15;
                fold_term[3] = input_sample_q15;
            end
        endcase
        for (fold_index = 0; fold_index < C_BANKS; fold_index = fold_index+1) begin
            if (!fold_bank_needed(fold_index))
                fold_next[fold_index] = {(C_VALUE_WIDTH+1){1'b0}};
            else if (member_selected == {C_MEMBER_AW{1'b0}})
                fold_next[fold_index] =
                    fold_term[fold_index][C_VALUE_WIDTH:0];
            else
                fold_next[fold_index] =
                    bank_extended[fold_index][C_VALUE_WIDTH:0]+
                    fold_term[fold_index][C_VALUE_WIDTH:0];
        end
    end

    // H16: with the fixed geometry and asynchronous read, every committed
    // legal fold prefix fits the stored signed value. The matching top only
    // consumes this flag on commits / fold_done. Idle raw diagnostics may differ.
    // Keep the original arithmetic and raw comparison for traceability.
    localparam integer C_FOLD_RANGE_PROVEN =
        (C_L == 4) && (C_BANKS == 4) && (C_STORE_WIDTH == 18);
    wire fold_overflow_raw =
        (fold_next[0][C_VALUE_WIDTH] != fold_next[0][C_VALUE_WIDTH-1]) ||
        (fold_next[1][C_VALUE_WIDTH] != fold_next[1][C_VALUE_WIDTH-1]) ||
        (fold_next[2][C_VALUE_WIDTH] != fold_next[2][C_VALUE_WIDTH-1]) ||
        (fold_next[3][C_VALUE_WIDTH] != fold_next[3][C_VALUE_WIDTH-1]);
    assign o_fold_overflow_now =
        C_FOLD_RANGE_PROVEN ? 1'b0 : fold_overflow_raw;

    wire input_commit = input_active && i_sample_valid;
    wire final_sample_accept = input_commit &&
        (member_selected == C_L-1) && (column_selected == C_COLUMNS-1);

    assign o_write_enable = input_commit;
    assign o_write_address = column_selected;
    assign o_write_data = {
        fold_next[3][C_VALUE_WIDTH-1:1],fold_next[2][C_VALUE_WIDTH-1:1],
        fold_next[1][C_VALUE_WIDTH-1:1],fold_next[0][C_VALUE_WIDTH-1:1]};
    assign o_read_address = column_selected;
    assign o_fold_active = input_active;
    assign o_sample_ready = input_active;
    assign o_fold_overflow_sticky = fold_overflow_reg;
    assign o_fold_done = final_sample_accept;

    genvar generated_lane;
    generate
        for (generated_lane = 0; generated_lane < C_D; generated_lane = generated_lane+1) begin : g_residue_expand
            if ((C_D % 4) == 0) begin : g_fixed_l4_bank
                // 批起始频点恒为 1 且每批 +C_D，C_D%4==0 时 (lane_bin mod 4) 是编译期常数。
                localparam integer C_BANK = (generated_lane+1) & 3;
                assign o_residue_real[generated_lane*32 +: 32] =
                    {{C_EXTEND_AMOUNT{residue_real_value[C_BANK][C_VALUE_WIDTH-1]}},
                     residue_real_value[C_BANK]};
                assign o_residue_imag[generated_lane*32 +: 32] =
                    {{C_EXTEND_AMOUNT{residue_imag_value[C_BANK][C_VALUE_WIDTH-1]}},
                     residue_imag_value[C_BANK]};
            end else begin : g_dynamic_l4_bank
                wire [1:0] lane_bank = i_lane_residue[generated_lane*C_RESIDUE_AW +: C_RESIDUE_AW];
                assign o_residue_real[generated_lane*32 +: 32] =
                    {{C_EXTEND_AMOUNT{residue_real_value[lane_bank][C_VALUE_WIDTH-1]}},
                     residue_real_value[lane_bank]};
                assign o_residue_imag[generated_lane*32 +: 32] =
                    {{C_EXTEND_AMOUNT{residue_imag_value[lane_bank][C_VALUE_WIDTH-1]}},
                     residue_imag_value[lane_bank]};
            end
        end
    endgenerate

    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            input_active <= 1'b0;
            input_member <= {C_MEMBER_AW{1'b0}};
            input_column <= {C_COLUMN_AW{1'b0}};
            input_pending <= 1'b0;
            input_member_hold <= {C_MEMBER_AW{1'b0}};
            input_column_hold <= {C_COLUMN_AW{1'b0}};
            input_sample_hold <= 16'sd0;
            fold_overflow_reg <= 1'b0;
        end else begin
            if (!input_active && !i_engine_busy) begin
                if (i_start) begin
                    input_active <= 1'b1;
                    input_member <= {C_MEMBER_AW{1'b0}};
                    input_column <= {C_COLUMN_AW{1'b0}};
                    input_pending <= 1'b0;
                    fold_overflow_reg <= 1'b0;
                end
            end else if (input_active && i_sample_valid) begin
                if (o_fold_overflow_now)
                    fold_overflow_reg <= 1'b1;
                if (final_sample_accept) begin
                    input_active <= 1'b0;
                end else if (input_column == C_COLUMNS-1) begin
                    input_column <= {C_COLUMN_AW{1'b0}};
                    input_member <= input_member+1'b1;
                end else begin
                    input_column <= input_column+1'b1;
                end
            end
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (!(C_N == 64 || C_N == 128 || C_N == 256 || C_N == 512))
            $error("C_N must be 64, 128, 256, or 512");
        if (C_L != 4)
            $error("e01_rfg_fold_l4 requires C_L = 4");
        if (C_BANKS != 4 || C_STORE_WIDTH != 18)
            $error("e01_rfg_fold_l4 requires the proven 4 banks x 18-bit storage");
        if (!(C_D == 1 || C_D == 2 || C_D == 4 || C_D == 8))
            $error("C_D must be 1, 2, 4, or 8");

    end
`endif
endmodule
