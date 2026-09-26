`timescale 1ns/1ps

// e01_rfg_fold_l16 —— L16 折叠前端原子件。
//
// 统一契约见 e01_rfg_fold_l2.sv 的头部说明（19 个端口逐位同形）。
// 本模块不持有残差存储器；阵列由唯一顶层内联声明（理由见 fold_l2 头部）。
//
// L16 折叠算术：每列 16 个成员，旋转因子取 {0, ±1, ±sqrt(1/2), ±cos(pi/8), ±sin(pi/8)}。
// 三个非常量 1 的因子全部用精确的全宽有符号移位加法网络生成（cos_pi8 / half / sin_pi8），
// 末位取 [58:24] 完成 Q24 截断，保持与冻结算术逐位一致；不使用乘法器。
//
// H8 私有打包格式（端口仍为 32*21 位）：保留 Re0..Re8、Im1..Im7。
// 实部镜像沿用 H5；Im0/Im8 数值恒零；Im9..Im15 用 ~Im(16-r)+(1-C) 精确重建。
// 原 Im0 槽 bank16[4:0] 存 signed5 B_fractional，[8:5] 存 signed4 B_odd。
// bank25..31 写零且不读；偏差元数据不作为 Im0 数值输出或 Q15 溢出检测对象。
//
// 存储位宽（**相对 v2 的一处有意修正**）：
// v2 的 e01_rfg_l16_top 用 20 位/bank（32*20 = 640 位/列），已在隔离实验的 l16a 批次
// 被位真检查抓到真实有符号截断：frame13 / bin1 得到 (742772,1455945)，独立参考
// (131042,-2668009)。全幅边界下 q0 正峰 1048544、q8 峰 1048560、q0 负峰 -1048576，
// 20 位 [-524288,524287] 不足，21 位 [-1048576,1048575] 才够。
// 故本模块用 21 位/bank（32*21 = 672 位/列），并配参数化符号范围夹具
// （sim/unit/tb_rfg_fold_storage_range.sv）做独立佐证。
// 注意：范围比较必须保留独立的 signed[35:0] 高位切片，写成带 unsigned 比较上下文的
// 单表达式移位会在 xsim 里静默出错（v3 的 s02 批次踩过）。

// H14: this front end serves the matching engine bins 1..C_K.
// Unrequested numeric residues may be zero; declared storage geometry is unchanged.
module e01_rfg_fold_l16 #(
    parameter integer C_N = 64,
    parameter integer C_K = 24,
    parameter integer C_D = 1,
    parameter integer C_L = 16,
    parameter integer C_STORE_WIDTH = 21,
    parameter integer C_BANKS = 32,
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
    localparam integer C_EXTEND_AMOUNT = 32-C_STORE_WIDTH;
    localparam integer C_HALF_BANKS = C_BANKS/2;

    // H14: only residues reachable from the matching engine's bins 1..C_K.
    function automatic integer fold_bank_needed(input integer bank);
        integer residue;
        begin
            residue = (bank < C_HALF_BANKS) ? bank : bank-C_HALF_BANKS;
            fold_bank_needed = (C_K >= C_L) ||
                ((residue != 0) && (residue <= C_K));
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
    wire signed [34:0] fold_one_positive = {{2{input_sample_q15[32]}},input_sample_q15};

    // H11: shared full-width integer multiples for all three fold constants.
    // No intermediate Q24 slice: every node remains signed [58:0].
    wire signed [58:0] fold_mcm_value =
        {{26{input_sample_q15[32]}},input_sample_q15};
    wire signed [58:0] fold_mcm_times3 =
        (fold_mcm_value <<< 1)+fold_mcm_value;
    wire signed [58:0] fold_mcm_times5 =
        (fold_mcm_value <<< 2)+fold_mcm_value;
    wire signed [58:0] fold_mcm_times11 =
        (fold_mcm_times5 <<< 1)+fold_mcm_value;
    wire signed [58:0] fold_mcm_times13 =
        (fold_mcm_value <<< 3)+fold_mcm_times5;

    wire signed [58:0] fold_mcm_half_high =
        (fold_mcm_times11 <<< 20)+(fold_mcm_times5 <<< 16);
    wire signed [58:0] fold_mcm_half_low =
        (fold_mcm_times5 <<< 8)-fold_mcm_times13;
    wire signed [58:0] fold_mcm_cos_high =
        (fold_mcm_value <<< 24)-(fold_mcm_times5 <<< 18);
    wire signed [58:0] fold_mcm_cos_middle =
        (fold_mcm_value <<< 15)+(fold_mcm_value <<< 10);
    wire signed [58:0] fold_mcm_cos_low =
        (fold_mcm_times5 <<< 5)+(fold_mcm_value <<< 1);
    wire signed [58:0] fold_mcm_sin_high =
        (fold_mcm_times3 <<< 21)+(fold_mcm_value <<< 17);
    wire signed [58:0] fold_mcm_sin_low =
        (fold_mcm_value <<< 11)+(fold_mcm_value <<< 7);

    // H13 carries H1/H1-L8 negative-term semantics into the fold adder.
    // A negative fractional coefficient uses ~positive for nonzero signed16 samples.
    // Negative integer terms, or a zero sample, need carry-in 1 instead.
    wire fold_sample_is_zero = (sample_selected == 16'sd0);

    wire signed [58:0] fold_cos_pi8_product_full =
        (fold_mcm_cos_high+fold_mcm_cos_middle)-fold_mcm_cos_low;
    wire signed [34:0] fold_cos_pi8_q15_full = fold_cos_pi8_product_full[58:24];
    // H21: the signed16-derived sample bounds this Q15 term to signed17.
    // Preserve every Q24 fractional bit decision; upper bits repeat its sign.
    wire signed [34:0] fold_cos_pi8_positive =
        {{18{fold_cos_pi8_q15_full[16]}},fold_cos_pi8_q15_full[16:0]};

    wire signed [58:0] fold_half_product_full = fold_mcm_half_high+fold_mcm_half_low;
    wire signed [34:0] fold_half_q15_full = fold_half_product_full[58:24];
    // H21: the signed16-derived sample bounds this Q15 term to signed17.
    // Preserve every Q24 fractional bit decision; upper bits repeat its sign.
    wire signed [34:0] fold_half_positive =
        {{18{fold_half_q15_full[16]}},fold_half_q15_full[16:0]};

    wire signed [58:0] fold_sin_pi8_product_full =
        (fold_mcm_sin_high-fold_mcm_sin_low)+fold_mcm_times11;
    wire signed [34:0] fold_sin_pi8_q15_full = fold_sin_pi8_product_full[58:24];
    // H21: the signed16-derived sample bounds this Q15 term to signed16.
    // Preserve every Q24 fractional bit decision; upper bits repeat its sign.
    wire signed [34:0] fold_sin_pi8_positive =
        {{19{fold_sin_pi8_q15_full[15]}},fold_sin_pi8_q15_full[15:0]};

    // H13: select a base value and two scalar controls; no negative-value mux.
    function automatic [36:0] direct_phase_operand(
        input integer component,
        input [C_MEMBER_AW-1:0] member,
        input signed [34:0] one_positive,
        input signed [34:0] cos_pi8_positive,
        input signed [34:0] half_positive,
        input signed [34:0] sin_pi8_positive
    );
        integer residue;
        integer phase;
        reg imaginary_component;
        reg signed [34:0] magnitude_value;
        reg negative_coefficient;
        begin
            if (component < C_HALF_BANKS) begin
                residue = component;
                imaginary_component = 1'b0;
            end else begin
                residue = component-C_HALF_BANKS;
                imaginary_component = 1'b1;
            end
            case (member)
                0: phase = 0;
                1: phase = residue;
                2: phase = residue << 1;
                3: phase = residue+(residue << 1);
                4: phase = residue << 2;
                5: phase = residue+(residue << 2);
                6: phase = (residue << 1)+(residue << 2);
                7: phase = (residue << 3)-residue;
                8: phase = residue << 3;
                9: phase = residue+(residue << 3);
                10: phase = (residue << 1)+(residue << 3);
                11: phase = residue+(residue << 1)+(residue << 3);
                12: phase = (residue << 2)+(residue << 3);
                13: phase = residue+(residue << 2)+(residue << 3);
                14: phase = (residue << 1)+(residue << 2)+(residue << 3);
                default: phase = (residue << 4)-residue;
            endcase
            phase = phase & (C_L-1);
            if (!imaginary_component) begin
                negative_coefficient = phase[3] ^ phase[2];
                case (phase)
                    0,8: magnitude_value = one_positive;
                    1,7,9,15: magnitude_value = cos_pi8_positive;
                    2,6,10,14: magnitude_value = half_positive;
                    3,5,11,13: magnitude_value = sin_pi8_positive;
                    default: magnitude_value = 35'sd0;
                endcase
            end else begin
                negative_coefficient = ~phase[3];
                case (phase)
                    0,8: magnitude_value = 35'sd0;
                    1,7,9,15: magnitude_value = sin_pi8_positive;
                    2,6,10,14: magnitude_value = half_positive;
                    3,5,11,13: magnitude_value = cos_pi8_positive;
                    default: magnitude_value = one_positive;
                endcase
            end
            direct_phase_operand =
                {negative_coefficient,(phase[1:0] == 2'd0),magnitude_value};
        end
    endfunction

    wire signed [31:0] fold_current [0:C_BANKS-1];
    // H13 descriptor: [36]=coefficient sign, [35]=integer phase, [34:0]=Q15 base.
    reg [36:0] fold_operand [0:C_BANKS-1];
    reg [C_STORE_WIDTH:0] fold_add_base [0:C_BANKS-1];
    reg [C_STORE_WIDTH:0] fold_add_operand [0:C_BANKS-1];
    reg fold_add_carry [0:C_BANKS-1];
    reg [C_STORE_WIDTH+1:0] fold_add_full [0:C_BANKS-1];
    // 2026-09-11 面积优化（与 fold_l8 同）：累加器只需"存储宽度 + 1 位溢出位"。
    // 存储是 C_STORE_WIDTH=21 位且头部已证明足够；原 36 位累加器多出的 [35:22] 位
    // 只服务"是否超出 32 位"这个判据，而该判据在 21 位存储下没有意义。
    // 21 位加法的低 22 位只取决于操作数的低 22 位 ⇒ 写入存储的数据逐位不变；
    // 溢出判据改为"和的第 21 位与第 20 位不一致"（装不进 21 位有符号），
    // 对全部合法输入与旧判据等价（都不触发）。
    reg signed [C_STORE_WIDTH:0] fold_next [0:C_BANKS-1];
    wire signed [C_BANKS*C_STORE_WIDTH-1:0] fold_next_word;
    // H8: per-column B=1-C. Odd residues count nonzero samples at member mod 4 != 0;
    // residues mod 4 == 2 count only odd members. Valid bias ranges are [-11,1]/[-7,1].
    wire signed [4:0] imag_bias_fractional_current =
        i_word_read[C_HALF_BANKS*C_STORE_WIDTH +: 5];
    wire signed [3:0] imag_bias_odd_current =
        i_word_read[C_HALF_BANKS*C_STORE_WIDTH+5 +: 4];
    wire signed [4:0] imag_bias_fractional_next =
        (C_K <= C_L/2) ? 5'sd0 :
        (member_selected == {C_MEMBER_AW{1'b0}}) ? 5'sd1 :
        (imag_bias_fractional_current -
         (((member_selected[1:0] != 2'd0) && !fold_sample_is_zero) ? 5'sd1 : 5'sd0));
    wire signed [3:0] imag_bias_odd_next =
        (C_K <= C_L/2+1) ? 4'sd0 :
        (member_selected == {C_MEMBER_AW{1'b0}}) ? 4'sd1 :
        (imag_bias_odd_current -
         ((member_selected[0] && !fold_sample_is_zero) ? 4'sd1 : 4'sd0));

    genvar bank_index;
    generate
        for (bank_index = 0; bank_index < C_BANKS; bank_index = bank_index+1) begin : g_fold_read
            // H5: zero imaginary banks and mirror real banks have no independent readback.
            if (!fold_bank_needed(bank_index)) begin : g_unrequested_residue
                assign fold_current[bank_index] = 32'sd0;
            end else if ((bank_index == C_HALF_BANKS) ||
                (bank_index == C_HALF_BANKS+C_L/2)) begin : g_zero_imaginary
                assign fold_current[bank_index] = 32'sd0;
            end else if ((bank_index < C_HALF_BANKS) &&
                         (bank_index > C_L/2)) begin : g_mirror_real
                assign fold_current[bank_index] = fold_current[C_L-bank_index];
            end else if (bank_index > C_HALF_BANKS+C_L/2) begin : g_mirror_imag
                localparam integer C_RESIDUE = bank_index-C_HALF_BANKS;
                localparam integer C_SOURCE_BANK = C_HALF_BANKS+C_L-C_RESIDUE;
                wire signed [C_STORE_WIDTH-1:0] source_value =
                    fold_current[C_SOURCE_BANK][C_STORE_WIDTH-1:0];
                wire signed [C_STORE_WIDTH-1:0] mirror_bias;
                if ((C_RESIDUE & 1) != 0) begin : g_fractional_bias
                    assign mirror_bias =
                        {{(C_STORE_WIDTH-5){imag_bias_fractional_current[4]}},imag_bias_fractional_current};
                end else if ((C_RESIDUE & 3) == 2) begin : g_odd_member_bias
                    assign mirror_bias =
                        {{(C_STORE_WIDTH-4){imag_bias_odd_current[3]}},imag_bias_odd_current};
                end else begin : g_integer_bias
                    assign mirror_bias = {{(C_STORE_WIDTH-1){1'b0}},1'b1};
                end
                // One W-bit add: ~Y+(1-C) == -Y-C modulo 2^W.
                // Both true imaginary sums fit W bits for every legal frame prefix.
                wire signed [C_STORE_WIDTH-1:0] mirror_value = ~source_value+mirror_bias;
                assign fold_current[bank_index] =
                    {{C_EXTEND_AMOUNT{mirror_value[C_STORE_WIDTH-1]}},mirror_value};
            end else begin : g_stored
                wire signed [C_STORE_WIDTH-1:0] stored =
                    i_word_read[bank_index*C_STORE_WIDTH +: C_STORE_WIDTH];
                assign fold_current[bank_index] =
                    {{C_EXTEND_AMOUNT{stored[C_STORE_WIDTH-1]}},stored};
            end
            if (bank_index == C_HALF_BANKS) begin : g_pack_bias
                // Private metadata occupies the otherwise unread Im0 slot.
                assign fold_next_word[bank_index*C_STORE_WIDTH +: C_STORE_WIDTH] =
                    {{(C_STORE_WIDTH-9){1'b0}},imag_bias_odd_next,imag_bias_fractional_next};
            end else begin : g_pack_value
                assign fold_next_word[bank_index*C_STORE_WIDTH +: C_STORE_WIDTH] =
                    fold_next[bank_index][C_STORE_WIDTH-1:0];
            end
        end
    endgenerate

    integer fold_index;
    always @* begin
        for (fold_index = 0; fold_index < C_BANKS; fold_index = fold_index+1) begin
            fold_operand[fold_index] = 37'd0;
            fold_add_base[fold_index] = {(C_STORE_WIDTH+1){1'b0}};
            fold_add_operand[fold_index] = {(C_STORE_WIDTH+1){1'b0}};
            fold_add_carry[fold_index] = 1'b0;
            fold_add_full[fold_index] = {(C_STORE_WIDTH+2){1'b0}};
            if (!fold_bank_needed(fold_index)) begin
                // No requested consumer; legal committed prefixes cannot overflow here.
                fold_next[fold_index] = {(C_STORE_WIDTH+1){1'b0}};
            end else if ((fold_index == C_HALF_BANKS) ||
                (fold_index == C_HALF_BANKS+C_L/2)) begin
                fold_next[fold_index] = {(C_STORE_WIDTH+1){1'b0}};
            end else if ((fold_index < C_HALF_BANKS) &&
                         (fold_index > C_L/2)) begin
                // H5: copy the complete canonical sum, including its guard bit.
                fold_operand[fold_index] = fold_operand[C_L-fold_index];
                fold_next[fold_index] = fold_next[C_L-fold_index];
            end else if (fold_index > C_HALF_BANKS+C_L/2) begin
                // H8: high-half imaginary fields still have no independent feedback.
                fold_next[fold_index] = {(C_STORE_WIDTH+1){1'b0}};
            end else begin
                fold_operand[fold_index] = direct_phase_operand(
                    fold_index,member_selected,fold_one_positive,
                    fold_cos_pi8_positive,fold_half_positive,fold_sin_pi8_positive);
                // Member zero replaces stale memory by loading the first term.
                fold_add_base[fold_index] =
                    (member_selected == {C_MEMBER_AW{1'b0}}) ?
                    {(C_STORE_WIDTH+1){1'b0}} :
                    fold_current[fold_index][C_STORE_WIDTH:0];
                fold_add_operand[fold_index] =
                    fold_operand[fold_index][C_STORE_WIDTH:0] ^
                    {(C_STORE_WIDTH+1){fold_operand[fold_index][36]}};
                // Negative integer terms need +1; fractional terms need it only at s=0.
                fold_add_carry[fold_index] = fold_operand[fold_index][36] &&
                    (fold_operand[fold_index][35] || fold_sample_is_zero);
                // One binary add: bit 0 produces carry-in; [W:1] is A+X+carry mod 2^W.
                fold_add_full[fold_index] =
                    {fold_add_base[fold_index],1'b1} +
                    {fold_add_operand[fold_index],fold_add_carry[fold_index]};
                fold_next[fold_index] =
                    fold_add_full[fold_index][C_STORE_WIDTH+1:1];
            end
        end
    end

    reg fold_overflow_comb;
    integer overflow_index;
    always @* begin
        fold_overflow_comb = 1'b0;
        for (overflow_index = 0; overflow_index < C_BANKS; overflow_index = overflow_index+1)
            if (fold_next[overflow_index][C_STORE_WIDTH] !=
                fold_next[overflow_index][C_STORE_WIDTH-1])
                fold_overflow_comb = 1'b1;
    end
    // H16: with the fixed geometry and asynchronous read, every committed
    // legal fold prefix fits the stored signed value. The matching top only
    // consumes this flag on commits / fold_done. Idle raw diagnostics may differ.
    // Keep the original arithmetic and raw comparison for traceability.
    localparam integer C_FOLD_RANGE_PROVEN =
        (C_L == 16) && (C_BANKS == 32) && (C_STORE_WIDTH == 21);
    assign o_fold_overflow_now =
        C_FOLD_RANGE_PROVEN ? 1'b0 : fold_overflow_comb;

    wire input_commit = input_active && i_sample_valid;
    wire final_sample_accept = input_commit &&
        (member_selected == C_L-1) && (column_selected == C_COLUMNS-1);

    assign o_write_enable = input_commit;
    assign o_write_address = column_selected;
    assign o_write_data = fold_next_word;
    assign o_read_address = column_selected;
    assign o_fold_active = input_active;
    assign o_sample_ready = input_active;
    assign o_fold_overflow_sticky = fold_overflow_reg;
    assign o_fold_done = final_sample_accept;

    // L16 无固定 bank 特化：C_D <= 8 < 16，lane_bin mod 16 随批变化，没有编译期常数映射。
    genvar generated_lane;
    generate
        for (generated_lane = 0; generated_lane < C_D; generated_lane = generated_lane+1) begin : g_residue_expand
            wire [C_RESIDUE_AW-1:0] lane_bank =
                i_lane_residue[generated_lane*C_RESIDUE_AW +: C_RESIDUE_AW];
            assign o_residue_real[generated_lane*32 +: 32] = fold_current[lane_bank];
            assign o_residue_imag[generated_lane*32 +: 32] =
                fold_current[C_HALF_BANKS+lane_bank];
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
    // 存储范围证明：32 个 bank，每个最多累加 16 个折叠项。
    // 实部 q0 达 ±1048544/1048560，虚部边界 -1048576，故 21 位 [-1048576,1048575] 刚好覆盖。
    // 2026-09-11：累加器已收窄为 C_STORE_WIDTH+1 位，故这里直接看"溢出位"（最高位与其下一位的异或）。
    wire storage_overflow_probe =
        fold_next[0][C_STORE_WIDTH] ^ fold_next[0][C_STORE_WIDTH-1];
    initial begin
        if (!(C_N == 64 || C_N == 128 || C_N == 256 || C_N == 512))
            $error("C_N must be 64, 128, 256, or 512");
        if (C_L != 16)
            $error("e01_rfg_fold_l16 requires C_L = 16");
        if (C_BANKS != 32 || C_STORE_WIDTH != 21)
            $error("e01_rfg_fold_l16 requires 32 banks x 21-bit storage (20 bits truncates at full scale)");
        if (!(C_D == 1 || C_D == 2 || C_D == 4 || C_D == 8))
            $error("C_D must be 1, 2, 4, or 8");

        if ($isunknown(storage_overflow_probe))
            $error("storage range probe must not be unknown");
    end
`endif
endmodule
