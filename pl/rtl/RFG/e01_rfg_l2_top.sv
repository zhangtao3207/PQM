`timescale 1ns/1ps

// Direct L2 RFG top with streaming two-point residue folding.
// N, K, and D remain compile-time parameters; this file is synthesized
// directly and does not pass through a unified L selector.
module e01_rfg_l2_top #(
    parameter integer C_N = 64,
    parameter integer C_K = 24,
    parameter integer C_D = 1
) (
    input  wire                     sys_clk,        // 50 MHz system clock
    input  wire                     rst_n,          // Asynchronous active-low reset
    input  wire                     i_start,        // Starts one frame while idle
    input  wire                     i_sample_valid, // Marks i_sample valid
    input  wire signed [15:0]       i_sample,       // Signed Q2.14 real sample
    input  wire                     i_result_ready, // Accepts the current result
    output wire                     o_sample_ready, // Core can accept one input sample
    output wire                     o_busy,         // Frame processing is active
    output wire                     o_result_valid, // Current complex result is valid
    output wire [8:0]               o_bin_index,    // One-based target-bin index
    output wire signed [31:0]       o_result_real,  // Signed Q15 real component
    output wire signed [31:0]       o_result_imag,  // Signed Q15 imaginary component
    output wire                     o_result_last,  // Current result is the final bin
    output wire                     o_frame_done,   // Final-result handshake pulse
    output wire                     o_overflow      // Sticky arithmetic-wrap flag
);
    localparam integer C_COLUMNS = C_N/2;
    localparam integer C_COLUMN_AW = $clog2(C_COLUMNS);

    reg input_active;
    reg input_member;
    reg [C_COLUMN_AW-1:0] input_column;
    reg input_pending;
    reg input_member_hold;
    reg [C_COLUMN_AW-1:0] input_column_hold;
    reg signed [15:0] input_sample_hold;
    reg fold_overflow_reg;

    wire signed [32:0] input_sample_q15 =
        {{16{i_sample[15]}}, i_sample, 1'b0};
    // WIDTH-34 storage (L4 72-bit precedent): each of the 2 banks accumulates
    // at most 2 fold terms of magnitude <= 2^16 (sample min -32768 gives
    // -65536), so the signed sum lies in [-131072, 131068]; all L2 fold
    // coefficients are {0,+/-1}, every term is even, and storing value>>1 in
    // 17 signed bits covers [-65536, 65534] exactly.  2 banks * 17 = 34.
    localparam integer C_RESIDUE_STORE_WIDTH = 17;
    localparam integer C_RESIDUE_BANKS = 2;
    wire signed [C_RESIDUE_BANKS*C_RESIDUE_STORE_WIDTH-1:0] fold_residue_word;
    wire signed [31:0] fold_current0 =
        {{(32-C_RESIDUE_STORE_WIDTH){fold_residue_word[C_RESIDUE_STORE_WIDTH-1]}},
         fold_residue_word[C_RESIDUE_STORE_WIDTH-1:0],1'b0};
    wire signed [31:0] fold_current1 =
        {{(32-C_RESIDUE_STORE_WIDTH){fold_residue_word[2*C_RESIDUE_STORE_WIDTH-1]}},
         fold_residue_word[2*C_RESIDUE_STORE_WIDTH-1:C_RESIDUE_STORE_WIDTH],1'b0};
    wire signed [32:0] fold_term0 = input_sample_q15;
    wire input_member_selected = input_member;
    wire signed [32:0] fold_term1 = input_member_selected ? -input_sample_q15 : input_sample_q15;
    wire signed [35:0] fold_next0 = input_member_selected ?
        $signed({{4{fold_current0[31]}},fold_current0})+
        $signed({{3{fold_term0[32]}},fold_term0}) :
        $signed({{3{fold_term0[32]}},fold_term0});
    wire signed [35:0] fold_next1 = input_member_selected ?
        $signed({{4{fold_current1[31]}},fold_current1})+
        $signed({{3{fold_term1[32]}},fold_term1}) :
        $signed({{3{fold_term1[32]}},fold_term1});
    wire fold_overflow_next =
        (fold_next0[35:32] != {4{fold_next0[31]}}) ||
        (fold_next1[35:32] != {4{fold_next1[31]}});
    wire input_commit = input_active && i_sample_valid;
    wire final_sample_accept = input_commit && input_member_selected &&
        input_column == C_COLUMNS-1;

    wire bin_busy;
    wire bin_overflow;
    wire [C_COLUMN_AW-1:0] residue_column;
    wire [C_D-1:0] residue_index;
    wire signed [C_D*32-1:0] residue_real;
    wire signed [C_D*32-1:0] residue_imag;

    genvar generated_lane;
    generate
        for (generated_lane = 0; generated_lane < C_D; generated_lane = generated_lane+1) begin : g_residue_read
            assign residue_real[generated_lane*32 +: 32] =
                residue_index[generated_lane] ?
                fold_current1 : fold_current0;
            assign residue_imag[generated_lane*32 +: 32] = 32'sd0;
        end
    endgenerate

    e01_rfg_direct_bin_engine #(
        .C_N(C_N),
        .C_K(C_K),
        .C_L(2),
        .C_D(C_D)
    ) u_bin_engine (
        .sys_clk(sys_clk),
        .rst_n(rst_n),
        .i_start(final_sample_accept),
        .i_fold_overflow(fold_overflow_reg | fold_overflow_next),
        .i_result_ready(i_result_ready),
        .o_busy(bin_busy),
        .o_residue_column(residue_column),
        .o_residue_index(residue_index),
        .i_residue_real(residue_real),
        .i_residue_imag(residue_imag),
        .o_result_valid(o_result_valid),
        .o_bin_index(o_bin_index),
        .o_result_real(o_result_real),
        .o_result_imag(o_result_imag),
        .o_result_last(o_result_last),
        .o_frame_done(o_frame_done),
        .o_overflow(bin_overflow)
    );

    assign o_sample_ready = input_active;
    assign o_busy = input_active || bin_busy;
    assign o_overflow = input_active ? fold_overflow_reg : bin_overflow;

    // ---- 残差存储器（内联；唯一的实现，无 ram_style 属性，组合读 + 同步写）----
    reg signed [C_RESIDUE_BANKS*C_RESIDUE_STORE_WIDTH-1:0] memory [0:C_COLUMNS-1];
    assign fold_residue_word = memory[input_active ? input_column : residue_column];
    always @(posedge sys_clk)
        if (input_commit) memory[input_column] <= {fold_next1[C_RESIDUE_STORE_WIDTH:1],fold_next0[C_RESIDUE_STORE_WIDTH:1]};

    // The two residue banks are overwritten by every accepted frame and do
    // not require resettable storage.
    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            input_active <= 1'b0;
            input_member <= 1'b0;
            input_column <= {C_COLUMN_AW{1'b0}};
            input_pending <= 1'b0;
            input_member_hold <= 1'b0;
            input_column_hold <= {C_COLUMN_AW{1'b0}};
            input_sample_hold <= 16'sd0;
            fold_overflow_reg <= 1'b0;
        end else begin
            if (!input_active && !bin_busy) begin
                if (i_start) begin
                    input_active <= 1'b1;
                    input_member <= 1'b0;
                    input_column <= {C_COLUMN_AW{1'b0}};
                    input_pending <= 1'b0;
                    fold_overflow_reg <= 1'b0;
                end
            end else if (input_active && i_sample_valid) begin
                if (fold_overflow_next)
                    fold_overflow_reg <= 1'b1;
                if (final_sample_accept) begin
                    input_active <= 1'b0;
                end else if (input_column == C_COLUMNS-1) begin
                    input_column <= {C_COLUMN_AW{1'b0}};
                    input_member <= 1'b1;
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
        if (C_K < 1 || C_K >= C_N/2)
            $error("C_K must satisfy 1 <= C_K < C_N/2");
        if (!(C_D == 1 || C_D == 2 || C_D == 4 || C_D == 8))
            $error("C_D must be 1, 2, 4, or 8");
    end
`endif
endmodule
