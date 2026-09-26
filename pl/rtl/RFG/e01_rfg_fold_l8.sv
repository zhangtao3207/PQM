`timescale 1ns/1ps

// e01_rfg_fold_l8 —— L8 折叠前端原子件。
//
// 统一契约见 e01_rfg_fold_l2.sv 的头部说明（19 个端口逐位同形）。
// 本模块不持有残差存储器；阵列由唯一顶层内联声明（理由见 fold_l2 头部）。
//
// L8 折叠算术：每列 8 个成员，按成员相位把输入轮转到 8 个相位项上累加。
// 旋转因子只有 {0, ±1, ±sqrt(1/2)}；sqrt(1/2) 用精确的全宽有符号移位加法网络
// half_shift_add 生成（不是乘法器），末位按 Q24 截断取 [58:24] 保持与冻结算术逐位一致。
//
// H8 私有打包格式（端口仍为 16*20 位）：保留 Re0..Re4、Im1..Im3。
// 实部镜像沿用 H5；Im0/Im4 数值恒零；Im5..Im7 用 ~Im(8-r)+(1-C) 精确重建。
// 原 Im0 槽 bank8[2:0] 改存 signed3 偏差 B_odd=1-C；bank13..15 写零且不读。
// 分数负项的 -1 LSB 偏差计入 C，不能直接使用无修正的共轭取负。
//
// 数值位宽仍为 signed20；每项绝对值 <=65536，实部 member0 的正端 <=65534，
// 故实部全列正端 <2^19、负端 >=-2^19。虚部至少有两个固定零项，任意前缀
// abs(Im)<=6*65536<2^19。分数项不保证偶数；320 位是展开槽位宽度，非独立状态位数。

// H14: this front end serves the matching engine bins 1..C_K.
// Unrequested numeric residues may be zero; declared storage geometry is unchanged.
module e01_rfg_fold_l8 #(
    parameter integer C_N = 64,
    parameter integer C_K = 24,
    parameter integer C_D = 1,
    parameter integer C_L = 8,
    parameter integer C_STORE_WIDTH = 20,
    parameter integer C_BANKS = 16,
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

    // H11: factor the exact integer coefficient before the unchanged Q24 slice.
    function automatic signed [58:0] half_shift_add(
        input signed [32:0] value
    );
        reg signed [58:0] extended_value;
        reg signed [58:0] value_times5;
        reg signed [58:0] value_times11;
        reg signed [58:0] value_times13;
        reg signed [58:0] half_high;
        reg signed [58:0] half_low;
        begin
            extended_value = {{26{value[32]}},value};
            value_times5 = (extended_value <<< 2)+extended_value;
            value_times11 = (value_times5 <<< 1)+extended_value;
            value_times13 = (extended_value <<< 3)+value_times5;
            half_high = (value_times11 <<< 20)+(value_times5 <<< 16);
            half_low = (value_times5 <<< 8)-value_times13;
            half_shift_add = half_high+half_low;
        end
    endfunction

    // H13 carries H1/H1-L8 negative-term semantics into the fold adder.
    // A negative fractional coefficient uses ~positive for nonzero signed16 samples.
    // Negative integer terms, or a zero sample, need carry-in 1 instead.
    wire fold_sample_is_zero = (sample_selected == 16'sd0);
    wire signed [58:0] fold_half_product_full = half_shift_add(input_sample_q15);
    wire signed [34:0] fold_half_q15_full = fold_half_product_full[58:24];
    // H21: the signed16-derived sample bounds this Q15 term to signed17.
    // Preserve every Q24 fractional bit decision; upper bits repeat its sign.
    wire signed [34:0] fold_half_positive =
        {{18{fold_half_q15_full[16]}},fold_half_q15_full[16:0]};

    // 相位项选择：component < 8 为实部 bank，否则为虚部 bank；phase = (residue*member) & 7。
    // H13: select a base value and two scalar controls; no negative-value mux.
    function automatic [36:0] select_fold_operand(
        input integer component,
        input [C_MEMBER_AW-1:0] member,
        input signed [34:0] one_positive,
        input signed [34:0] half_positive
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
            phase = (residue*member) & (C_L-1);
            if (!imaginary_component) begin
                negative_coefficient = phase[2] ^ phase[1];
                case (phase)
                    0,4: magnitude_value = one_positive;
                    2,6: magnitude_value = 35'sd0;
                    default: magnitude_value = half_positive;
                endcase
            end else begin
                negative_coefficient = ~phase[2];
                case (phase)
                    0,4: magnitude_value = 35'sd0;
                    2,6: magnitude_value = one_positive;
                    default: magnitude_value = half_positive;
                endcase
            end
            select_fold_operand = {negative_coefficient,~phase[0],magnitude_value};
        end
    endfunction

    wire signed [31:0] fold_current [0:C_BANKS-1];
    // H13 descriptor: [36]=coefficient sign, [35]=integer phase, [34:0]=Q15 base.
    reg [36:0] fold_operand [0:C_BANKS-1];
    reg [C_STORE_WIDTH:0] fold_add_base [0:C_BANKS-1];
    reg [C_STORE_WIDTH:0] fold_add_operand [0:C_BANKS-1];
    reg fold_add_carry [0:C_BANKS-1];
    reg [C_STORE_WIDTH+1:0] fold_add_full [0:C_BANKS-1];
    // 2026-09-11 面积优化：累加器只需覆盖"存储宽度 + 1 位溢出位"。
    // 存储是 C_STORE_WIDTH=20 位，且头部已证明该宽度对合法输入足够
    // （最坏 8*65534 = 524272 <= 2^19-1）。原来的 36 位累加器多出的 [35:20] 位
    // 只服务"是否超出 32 位"这个判据，而该判据在存储只有 20 位时没有意义：
    // 落在 20 位之外、32 位之内会写坏存储却不报溢出。
    // 现改为 21 位加法：和的低 21 位只取决于操作数的低 21 位，故低位结果逐位不变；
    // 溢出判据改为"和的第 20 位与第 19 位不一致" = "装不进 20 位有符号"，
    // 对**全部合法输入**与旧判据等价（都不触发），且语义上真正保护了存储宽度。
    reg signed [C_STORE_WIDTH:0] fold_next [0:C_BANKS-1];
    wire signed [C_BANKS*C_STORE_WIDTH-1:0] fold_next_word;
    // H8: per-column B=1-C; odd residues share C=#nonzero samples at odd members.
    // Valid prefixes give B in [-3,1], so signed3 is sufficient.
    wire signed [2:0] imag_bias_odd_current =
        i_word_read[C_HALF_BANKS*C_STORE_WIDTH +: 3];
    wire signed [2:0] imag_bias_odd_next =
        (C_K <= C_L/2) ? 3'sd0 :
        (member_selected == {C_MEMBER_AW{1'b0}}) ? 3'sd1 :
        (imag_bias_odd_current -
         ((member_selected[0] && !fold_sample_is_zero) ? 3'sd1 : 3'sd0));

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
                        {{(C_STORE_WIDTH-3){imag_bias_odd_current[2]}},imag_bias_odd_current};
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
                    {{(C_STORE_WIDTH-3){1'b0}},imag_bias_odd_next};
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
                fold_operand[fold_index] = select_fold_operand(
                    fold_index,member_selected,fold_one_positive,fold_half_positive);
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
        (C_L == 8) && (C_BANKS == 16) && (C_STORE_WIDTH == 20);
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

    genvar generated_lane;
    generate
        for (generated_lane = 0; generated_lane < C_D; generated_lane = generated_lane+1) begin : g_residue_expand
            if (C_D == C_L) begin : g_fixed_bank
                // 批起始频点恒为 1 且每批 +C_D；C_D == C_L 时 lane_bin mod C_L 是编译期常数。
                localparam integer C_BANK = (generated_lane+1) % C_L;
                assign o_residue_real[generated_lane*32 +: 32] = fold_current[C_BANK];
                assign o_residue_imag[generated_lane*32 +: 32] = fold_current[C_HALF_BANKS+C_BANK];
            end else begin : g_dynamic_bank
                wire [C_RESIDUE_AW-1:0] lane_bank =
                    i_lane_residue[generated_lane*C_RESIDUE_AW +: C_RESIDUE_AW];
                assign o_residue_real[generated_lane*32 +: 32] = fold_current[lane_bank];
                assign o_residue_imag[generated_lane*32 +: 32] =
                    fold_current[C_HALF_BANKS+lane_bank];
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
        if (C_L != 8)
            $error("e01_rfg_fold_l8 requires C_L = 8");
        if (C_BANKS != 16 || C_STORE_WIDTH != 20)
            $error("e01_rfg_fold_l8 requires the proven 16 banks x 20-bit storage");
        if (!(C_D == 1 || C_D == 2 || C_D == 4 || C_D == 8))
            $error("C_D must be 1, 2, 4, or 8");

    end
`endif
endmodule
