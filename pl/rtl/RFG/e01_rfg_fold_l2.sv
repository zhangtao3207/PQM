`timescale 1ns/1ps

// e01_rfg_fold_l2 —— L2 折叠前端原子件。
//
// 统一契约（与 e01_rfg_fold_l4 / l8 / l16 逐位相同的端口形态）：
//   写侧：把输入样本流式折叠成打包字，交给顶层持有的残差存储器；
//   读侧：把存储器当前列的打包字，组合展开成引擎需要的每 lane 复残差；
//   握手：o_sample_ready / o_fold_active / o_fold_done / 两个溢出输出。
//
// 本模块**不持有残差存储器**。存储器由唯一顶层**内联**声明（不是包装模块）：
// v2 的 e01_rfg_l4/l8/l16_top 都记录了实测证据——把存储阵列放进独立模块会使
// Vivado 的 RAM 推断显著劣化（L8 几何 8x512：u_residue_memory 1348 LUT vs
// 内联 ~429 LUT；L4 16x72 同样有 360 logic LUT 膨胀）。因此本模块只做组合与
// 寄存器逻辑，阵列留在顶层。
//
// L2 折叠算术：输入按列切成 N/2 个二元组，两个 bank 分别累加
//   bank0 = x[c] + x[c+N/2]   （和序列，供偶频点）
//   bank1 = x[c] - x[c+N/2]   （差序列，供奇频点）
// 展开映射：real 残差按 lane 的频点奇偶二选一；imag 残差恒 0。
//
// 存储压缩（沿用 v2 已验证的宽度证明）：每 bank 最多累加 2 个幅值 <= 2^16 的折叠项，
// 有符号和落在 [-131072, 131068]；L2 折叠系数只有 {0,+/-1}，每项必为偶数，
// 故存 value>>1 于 17 位有符号即可精确覆盖 [-65536, 65534]。2 bank * 17 = 34 位/列。

// H14: this front end serves the matching engine bins 1..C_K.
// Unrequested numeric residues may be zero; declared storage geometry is unchanged.
module e01_rfg_fold_l2 #(
    parameter integer C_N = 64,                 // 帧长（编译期）
    parameter integer C_K = 24,                 // 目标频点数（编译期；K=1 不生成和序列）
    parameter integer C_D = 1,                  // 并行 lane 数 / 物理 DSP 预算（编译期）
    parameter integer C_L = 2,                  // 折叠长度（编译期）
    parameter integer C_STORE_WIDTH = 17,       // 每 bank 存储位宽
    parameter integer C_BANKS = 2,              // 本 L 的 bank 数
    // 派生宽度以参数形式给出，才能在端口声明里直接使用（localparam 声明在端口之后）。
    parameter integer C_COLUMN_AW = ((C_N/C_L) <= 1) ? 1 : $clog2(C_N/C_L),
    parameter integer C_MEMBER_AW = (C_L <= 1) ? 1 : $clog2(C_L),
    parameter integer C_RESIDUE_AW = (C_L <= 1) ? 1 : $clog2(C_L)
) (
    input  wire                                     sys_clk,        // 50 MHz 系统时钟
    input  wire                                     rst_n,          // 低有效异步复位
    input  wire                                     i_start,        // 空闲时启动一帧
    input  wire                                     i_engine_busy,  // 后折叠引擎忙
    input  wire                                     i_sample_valid, // 输入样本有效
    input  wire signed [15:0]                       i_sample,       // 有符号 Q2.14 输入样本
    output wire [C_COLUMN_AW-1:0]                   o_write_address, // 折叠写列地址
    output wire                                     o_write_enable,  // 折叠写使能
    output wire signed [C_BANKS*C_STORE_WIDTH-1:0]  o_write_data,    // 折叠写打包字
    output wire [C_COLUMN_AW-1:0]                   o_read_address,  // 折叠侧读列地址
    input  wire signed [C_BANKS*C_STORE_WIDTH-1:0]  i_word_read,     // 存储器当前列打包字
    output wire                                     o_fold_active,   // 折叠进行中（顶层据此复用地址）
    output wire                                     o_sample_ready,  // 可再收一个输入样本
    output wire                                     o_fold_overflow_sticky, // 本帧累计折叠溢出
    output wire                                     o_fold_overflow_now,    // 本拍折叠溢出（未寄存）
    output wire                                     o_fold_done,     // 折叠收尾脉冲（引擎启动）
    input  wire [C_D*C_RESIDUE_AW-1:0]              i_lane_residue,  // 引擎给出的每 lane 残差序号
    output wire signed [C_D*32-1:0]                 o_residue_real,  // 每 lane Q15 实残差
    output wire signed [C_D*32-1:0]                 o_residue_imag   // 每 lane Q15 虚残差
);
    localparam integer C_COLUMNS = C_N/C_L;
    localparam integer C_SHIFT_AMOUNT = 32-C_STORE_WIDTH;

    reg input_active;
    reg [C_MEMBER_AW-1:0] input_member;
    reg [C_COLUMN_AW-1:0] input_column;
    reg input_pending;
    reg [C_MEMBER_AW-1:0] input_member_hold;
    reg [C_COLUMN_AW-1:0] input_column_hold;
    reg signed [15:0] input_sample_hold;
    reg fold_overflow_reg;

    // 寄存器读模式下本拍消费的是上一拍锁存的样本/成员/列。
    wire signed [15:0] sample_selected = input_pending ? input_sample_hold : i_sample;
    wire [C_MEMBER_AW-1:0] member_selected = input_pending ? input_member_hold : input_member;
    wire [C_COLUMN_AW-1:0] column_selected = input_pending ? input_column_hold : input_column;

    wire signed [32:0] input_sample_q15 = {{16{sample_selected[15]}},sample_selected,1'b0};

    // 打包字 -> 32 位累加视图（纯连线，零 LUT）。存的是 value>>1，读回左移还原。
    wire signed [32:0] bank0_extended =
        (C_K < 2) ? 33'sd0 :
        {{C_SHIFT_AMOUNT{i_word_read[C_STORE_WIDTH-1]}},
         i_word_read[C_STORE_WIDTH-1:0],1'b0};
    wire signed [32:0] bank1_extended =
        {{C_SHIFT_AMOUNT{i_word_read[2*C_STORE_WIDTH-1]}},
         i_word_read[2*C_STORE_WIDTH-1:C_STORE_WIDTH],1'b0};
    wire signed [31:0] fold_current0 = bank0_extended[31:0];
    wire signed [31:0] fold_current1 = bank1_extended[31:0];

    wire signed [32:0] fold_term0 = input_sample_q15;
    wire signed [32:0] fold_term1 = (member_selected != {C_MEMBER_AW{1'b0}}) ?
        -input_sample_q15 : input_sample_q15;

    // ---- Handover GPT 第 3 轮 H2-L2（round3_l2_bounded_sum.svh）以下 19 行原样嵌入 ----
    // 存储值先恢复被省略的 bit0，值宽为 C_STORE_WIDTH+1；再留一位覆盖任意读回值的加法。
    // C_STORE_WIDTH=17 时为 19 位，覆盖 [-196608,196606]，不依赖合法帧内的存储可达性。
    localparam integer C_FOLD_SUM_WIDTH = C_STORE_WIDTH+2;
    wire signed [C_FOLD_SUM_WIDTH-1:0] fold_sum0 =
        (C_K < 2) ? {C_FOLD_SUM_WIDTH{1'b0}} :
        (member_selected != {C_MEMBER_AW{1'b0}}) ?
        $signed(fold_current0[C_FOLD_SUM_WIDTH-1:0])+
        $signed(fold_term0[C_FOLD_SUM_WIDTH-1:0]) :
        $signed(fold_term0[C_FOLD_SUM_WIDTH-1:0]);
    wire signed [C_FOLD_SUM_WIDTH-1:0] fold_sum1 =
        (member_selected != {C_MEMBER_AW{1'b0}}) ?
        $signed(fold_current1[C_FOLD_SUM_WIDTH-1:0])+
        $signed(fold_term1[C_FOLD_SUM_WIDTH-1:0]) :
        $signed(fold_term1[C_FOLD_SUM_WIDTH-1:0]);

    // 保留原 36 位观察信号和原 signed32 溢出判据；高位只是已精确求和结果的符号扩展。
    wire signed [35:0] fold_next0 =
        {{(36-C_FOLD_SUM_WIDTH){fold_sum0[C_FOLD_SUM_WIDTH-1]}},fold_sum0};
    wire signed [35:0] fold_next1 =
        {{(36-C_FOLD_SUM_WIDTH){fold_sum1[C_FOLD_SUM_WIDTH-1]}},fold_sum1};

    assign o_fold_overflow_now =
        (fold_next0[35:32] != {4{fold_next0[31]}}) ||
        (fold_next1[35:32] != {4{fold_next1[31]}});

    wire input_commit = input_active && i_sample_valid;
    wire final_sample_accept = input_commit &&
        (member_selected == C_L-1) && (column_selected == C_COLUMNS-1);

    assign o_write_enable = input_commit;
    assign o_write_address = column_selected;
    assign o_write_data = {fold_next1[C_STORE_WIDTH:1],fold_next0[C_STORE_WIDTH:1]};
    assign o_read_address = column_selected;
    assign o_fold_active = input_active;
    assign o_sample_ready = input_active;
    assign o_fold_overflow_sticky = fold_overflow_reg;
    assign o_fold_done = final_sample_accept;

    // 展开映射：索引 0 -> bank0（和序列），否则 bank1（差序列）；虚残差恒 0。
    genvar generated_lane;
    generate
        for (generated_lane = 0; generated_lane < C_D; generated_lane = generated_lane+1) begin : g_residue_expand
            assign o_residue_real[generated_lane*32 +: 32] =
                (i_lane_residue[generated_lane*C_RESIDUE_AW +: C_RESIDUE_AW] ==
                 {C_RESIDUE_AW{1'b0}}) ? fold_current0 : fold_current1;
            assign o_residue_imag[generated_lane*32 +: 32] = 32'sd0;
        end
    endgenerate

    // 两个 bank 每帧都被完整覆写，不需要可复位存储。
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
        if (C_L != 2)
            $error("e01_rfg_fold_l2 requires C_L = 2");
        if (C_BANKS != 2 || C_STORE_WIDTH != 17)
            $error("e01_rfg_fold_l2 requires the proven 2 banks x 17-bit storage");
        if (!(C_D == 1 || C_D == 2 || C_D == 4 || C_D == 8))
            $error("C_D must be 1, 2, 4, or 8");
    end
`endif
endmodule
