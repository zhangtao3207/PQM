`timescale 1ns/1ps

// e01_rfg_nkld_top —— RFG 唯一顶层（原子化模型收口点）。
//
// 定位：N / K / L / D 全部是编译期参数。没有任何 L 输入端口、L 寄存器或运行时
// 选择网络——L 的四条折叠通路在精化期由 generate 分离，综合器只会看到所选那一条。
//
// 分层（引擎与存储器在 generate 之外，只存在一份）：
//   本顶层
//     ├─ 残差存储器（内联声明，单数组单读口，地址 2:1 复用）
//     ├─ e01_rfg_direct_bin_engine   ← 唯一一份，C_L 泛化到 {2,4,8,16}
//     └─ generate if/else-if (C_L) → e01_rfg_fold_l{2,4,8,16}（**折叠算术**按 L 分离的唯一处）
//
// ⚠ 更正（2026-09-11）：本行原先写作"L 差异唯一存在处"，**与代码不符**——
//   引擎 e01_rfg_direct_bin_engine 自身也有 6 处 C_L 分支：
//   相位常数表 85/87、123/125；输出去旋转 298/306；溢出守卫 457/461/475。
//   若要真正做到"L 只存在于 fold"，需要把引擎的 L 相位表抽成独立原子件（见
//   docs/E01/rfg_systematic_analysis_20260911.md §2.4 候选 C2）。
//
// 存储器为什么内联而不走包装模块：v2 的 e01_rfg_l4/l8/l16_top 都记录了实测证据——
// 把阵列放进独立模块会让 Vivado 的 RAM 推断显著劣化（L8 几何 8x512：包装件
// 1348 LUT vs 内联 ~429 LUT；L4 16x72 同样有 360 logic LUT 膨胀）。因此这里保持
// v2 已验证的内联形态，只让折叠算术与展开映射进模块边界。
//
// 每 L 的存储位宽（bank 数 x 位宽）：L2 = 2x17 = 34；L4 = 4x18 = 72；
// L8 = 16x20 = 320；L16 = 32x21 = 672（L16 的 21 位是相对 v2 的有意修正，见
// e01_rfg_fold_l16.sv 头部说明）。
//
// C_BACKEND 为预留给 v3 宽乘后端（e01_wide_mul_backend）的参数位，当前恒为 0 且未接
// 实现，刻意不并入本次结构归一化，避免同时改多处而无法归因。

module e01_rfg_nkld_top #(
    parameter integer C_N = 64,                  // 帧长（编译期）
    parameter integer C_K = 24,                  // 目标频点数 1..K（编译期）
    parameter integer C_L = 2,                   // 折叠长度（编译期，2/4/8/16）
    parameter integer C_D = 1,                   // 并行 lane 数 / 物理 DSP 预算（编译期）
    parameter integer C_BACKEND = 0              // 预留：乘法后端选择，当前仅 0 有效
) (
    input  wire                     sys_clk,        // 50 MHz 系统时钟
    input  wire                     rst_n,          // 低有效异步复位
    input  wire                     i_start,        // 空闲时启动一帧
    input  wire                     i_sample_valid, // 输入样本有效
    input  wire signed [15:0]       i_sample,       // 有符号 Q2.14 输入样本
    input  wire                     i_result_ready, // 下游接收当前结果
    output wire                     o_sample_ready, // 可再收一个输入样本
    output wire                     o_busy,         // 帧处理进行中
    output wire                     o_result_valid, // 当前复结果有效
    output wire [8:0]               o_bin_index,    // 从 1 开始的目标频点编号
    output wire signed [31:0]       o_result_real,  // 有符号 Q15 实部
    output wire signed [31:0]       o_result_imag,  // 有符号 Q15 虚部
    output wire                     o_result_last,  // 当前为最后一个频点
    output wire                     o_frame_done,   // 末结果握手完成脉冲
    output wire                     o_overflow      // 本帧算术溢出粘滞标志
);
    // ---- 由 C_L 导出的编译期几何 ----
    localparam integer C_BANKS = (C_L == 2) ? 2 : (C_L == 4) ? 4 : (C_L == 8) ? 16 : 32;
    localparam integer C_STORE_WIDTH =
        (C_L == 2) ? 17 : (C_L == 4) ? 18 : (C_L == 8) ? 20 : 21;
    localparam integer C_WORD_WIDTH = C_BANKS*C_STORE_WIDTH;
    localparam integer C_COLUMNS = C_N/C_L;
    localparam integer C_COLUMN_AW = (C_COLUMNS <= 1) ? 1 : $clog2(C_COLUMNS);
    localparam integer C_RESIDUE_AW = (C_L <= 1) ? 1 : $clog2(C_L);

    // ---- 折叠前端 <-> 顶层 的共享连线 ----
    wire [C_COLUMN_AW-1:0]          fold_write_address;
    wire                            fold_write_enable;
    wire signed [C_WORD_WIDTH-1:0]  fold_write_data;
    wire [C_COLUMN_AW-1:0]          fold_read_address;
    wire signed [C_WORD_WIDTH-1:0]  residue_word_read;
    wire                            fold_active;
    wire                            fold_sample_ready;
    wire                            fold_overflow_sticky;
    wire                            fold_overflow_now;
    wire                            fold_done;
    wire signed [C_D*32-1:0]        residue_real;
    wire signed [C_D*32-1:0]        residue_imag;
    wire [C_D*C_RESIDUE_AW-1:0]     residue_index;
    wire [C_COLUMN_AW-1:0]          engine_column;
    wire                            engine_busy;
    wire                            engine_overflow;

    // 单数组、单异步读口：折叠期读折叠列，引擎期读引擎列。
    wire [C_COLUMN_AW-1:0] memory_read_address =
        fold_active ? fold_read_address : engine_column;

    // ---- 残差存储器（内联；唯一的实现，无 ram_style 属性，组合读 + 同步写）----
    reg signed [C_WORD_WIDTH-1:0] memory [0:C_COLUMNS-1];
    assign residue_word_read = memory[memory_read_address];
    always @(posedge sys_clk)
        if (fold_write_enable)
            memory[fold_write_address] <= fold_write_data;

    // ---- 唯一一份后折叠引擎（L 泛化，位于 generate 之外）----
    e01_rfg_direct_bin_engine #(
        .C_N(C_N),
        .C_K(C_K),
        .C_L(C_L),
        .C_D(C_D)
    ) u_bin_engine (
        .sys_clk(sys_clk),
        .rst_n(rst_n),
        .i_start(fold_done),
        .i_fold_overflow(fold_overflow_sticky || fold_overflow_now),
        .i_result_ready(i_result_ready),
        .o_busy(engine_busy),
        .o_residue_column(engine_column),
        .o_residue_index(residue_index),
        .i_residue_real(residue_real),
        .i_residue_imag(residue_imag),
        .o_result_valid(o_result_valid),
        .o_bin_index(o_bin_index),
        .o_result_real(o_result_real),
        .o_result_imag(o_result_imag),
        .o_result_last(o_result_last),
        .o_frame_done(o_frame_done),
        .o_overflow(engine_overflow)
    );

    // ---- 按 C_L 在精化期分离折叠前端（只有一条被实例化）----
    generate
        if (C_L == 2) begin : g_l2
            e01_rfg_fold_l2 #(
                .C_N(C_N),.C_K(C_K),.C_D(C_D),.C_L(2),
                .C_STORE_WIDTH(17),.C_BANKS(2)
            ) u_fold (
                .sys_clk(sys_clk),.rst_n(rst_n),.i_start(i_start),
                .i_engine_busy(engine_busy),
                .i_sample_valid(i_sample_valid),.i_sample(i_sample),
                .o_write_address(fold_write_address),
                .o_write_enable(fold_write_enable),
                .o_write_data(fold_write_data),
                .o_read_address(fold_read_address),
                .i_word_read(residue_word_read),
                .o_fold_active(fold_active),
                .o_sample_ready(fold_sample_ready),
                .o_fold_overflow_sticky(fold_overflow_sticky),
                .o_fold_overflow_now(fold_overflow_now),
                .o_fold_done(fold_done),
                .i_lane_residue(residue_index),
                .o_residue_real(residue_real),
                .o_residue_imag(residue_imag));
        end else if (C_L == 4) begin : g_l4
            e01_rfg_fold_l4 #(
                .C_N(C_N),.C_K(C_K),.C_D(C_D),.C_L(4),
                .C_STORE_WIDTH(18),.C_BANKS(4)
            ) u_fold (
                .sys_clk(sys_clk),.rst_n(rst_n),.i_start(i_start),
                .i_engine_busy(engine_busy),
                .i_sample_valid(i_sample_valid),.i_sample(i_sample),
                .o_write_address(fold_write_address),
                .o_write_enable(fold_write_enable),
                .o_write_data(fold_write_data),
                .o_read_address(fold_read_address),
                .i_word_read(residue_word_read),
                .o_fold_active(fold_active),
                .o_sample_ready(fold_sample_ready),
                .o_fold_overflow_sticky(fold_overflow_sticky),
                .o_fold_overflow_now(fold_overflow_now),
                .o_fold_done(fold_done),
                .i_lane_residue(residue_index),
                .o_residue_real(residue_real),
                .o_residue_imag(residue_imag));
        end else if (C_L == 8) begin : g_l8
            e01_rfg_fold_l8 #(
                .C_N(C_N),.C_K(C_K),.C_D(C_D),.C_L(8),
                .C_STORE_WIDTH(20),.C_BANKS(16)
            ) u_fold (
                .sys_clk(sys_clk),.rst_n(rst_n),.i_start(i_start),
                .i_engine_busy(engine_busy),
                .i_sample_valid(i_sample_valid),.i_sample(i_sample),
                .o_write_address(fold_write_address),
                .o_write_enable(fold_write_enable),
                .o_write_data(fold_write_data),
                .o_read_address(fold_read_address),
                .i_word_read(residue_word_read),
                .o_fold_active(fold_active),
                .o_sample_ready(fold_sample_ready),
                .o_fold_overflow_sticky(fold_overflow_sticky),
                .o_fold_overflow_now(fold_overflow_now),
                .o_fold_done(fold_done),
                .i_lane_residue(residue_index),
                .o_residue_real(residue_real),
                .o_residue_imag(residue_imag));
        end else if (C_L == 16) begin : g_l16
            e01_rfg_fold_l16 #(
                .C_N(C_N),.C_K(C_K),.C_D(C_D),.C_L(16),
                .C_STORE_WIDTH(21),.C_BANKS(32)
            ) u_fold (
                .sys_clk(sys_clk),.rst_n(rst_n),.i_start(i_start),
                .i_engine_busy(engine_busy),
                .i_sample_valid(i_sample_valid),.i_sample(i_sample),
                .o_write_address(fold_write_address),
                .o_write_enable(fold_write_enable),
                .o_write_data(fold_write_data),
                .o_read_address(fold_read_address),
                .i_word_read(residue_word_read),
                .o_fold_active(fold_active),
                .o_sample_ready(fold_sample_ready),
                .o_fold_overflow_sticky(fold_overflow_sticky),
                .o_fold_overflow_now(fold_overflow_now),
                .o_fold_done(fold_done),
                .i_lane_residue(residue_index),
                .o_residue_real(residue_real),
                .o_residue_imag(residue_imag));
        end else begin : g_unsupported_l
            initial begin
                $error("e01_rfg_nkld_top: C_L must be 2, 4, 8, or 16 (got %0d)", C_L);
            end
            assign fold_write_address = {C_COLUMN_AW{1'b0}};
            assign fold_write_enable = 1'b0;
            assign fold_write_data = {C_WORD_WIDTH{1'b0}};
            assign fold_read_address = {C_COLUMN_AW{1'b0}};
            assign fold_active = 1'b0;
            assign fold_sample_ready = 1'b0;
            assign fold_overflow_sticky = 1'b0;
            assign fold_overflow_now = 1'b0;
            assign fold_done = 1'b0;
            assign residue_real = {C_D*32{1'b0}};
            assign residue_imag = {C_D*32{1'b0}};
        end
    endgenerate

    assign o_sample_ready = fold_sample_ready;
    assign o_busy = fold_active || engine_busy;
    assign o_overflow = fold_active ? fold_overflow_sticky : engine_overflow;

`ifndef SYNTHESIS
    // L 契约的唯一权威：原先分散在四条 L 顶层里的检查全部收敛到此处。
    initial begin
        if (!(C_N == 64 || C_N == 128 || C_N == 256 || C_N == 512))
            $error("C_N must be 64, 128, 256, or 512");
        if (C_K < 1 || C_K >= C_N/2)
            $error("C_K must satisfy 1 <= C_K < C_N/2");
        if (!(C_L == 2 || C_L == 4 || C_L == 8 || C_L == 16))
            $error("C_L must be 2, 4, 8, or 16");
        if ((C_N % C_L) != 0 || C_COLUMNS < 4)
            $error("C_L must divide C_N and leave at least four columns");
        if (!(C_D == 1 || C_D == 2 || C_D == 4 || C_D == 8))
            $error("C_D must be 1, 2, 4, or 8");
        if (C_BACKEND != 0)
            $error("C_BACKEND is a reserved parameter; only 0 is implemented");
    end
`endif
endmodule
