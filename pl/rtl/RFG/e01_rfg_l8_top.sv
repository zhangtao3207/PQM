`timescale 1ns/1ps

// Direct L8 RFG top with streaming real-input residue folding.
// One LUT constant product supplies the sqrt(1/2) fold terms; all variable
// Goertzel and output-phase products retain the frozen four-phase multiplier.
module e01_rfg_l8_top #(
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
    localparam integer C_COLUMNS = C_N/8;
    localparam integer C_COLUMN_AW = $clog2(C_COLUMNS);
    // WIDTH-320 storage (L4 72-bit precedent): each bank accumulates at most
    // 8 fold terms of magnitude <= 2^16-2, so the signed sum fits 20 bits
    // (worst pure +/-1 bank 8*(2^16-2) = 524272 < 2^19, positive side
    // 8*65534 = 524272 <= 2^19-1).  L8 sqrt(1/2) fold terms have no evenness
    // guarantee after >>24 truncation, so all 20 bits are stored: 16*20=320.
    localparam integer C_RESIDUE_STORE_WIDTH = 20;
    localparam integer C_RESIDUE_BANKS = 16;

    reg input_active;
    reg [2:0] input_member;
    reg [C_COLUMN_AW-1:0] input_column;
    reg input_pending;
    reg [2:0] input_member_hold;
    reg [C_COLUMN_AW-1:0] input_column_hold;
    reg signed [15:0] input_sample_hold;
    reg fold_overflow_reg;

    // Bank mapping: real R0..R7, followed by imaginary R0..R7.  Both halves
    // are retained because Q24 truncation makes a negative-coefficient product
    // differ by one LSB from simply negating its positive counterpart.
    wire signed [32:0] input_sample_q15 =
        {{16{i_sample[15]}}, i_sample, 1'b0};
    wire signed [34:0] fold_one_positive =
        {{2{input_sample_q15[32]}},input_sample_q15};
    wire signed [34:0] fold_one_negative = -fold_one_positive;

    function automatic signed [58:0] half_shift_add(
        input signed [32:0] value
    );
        reg signed [58:0] extended_value;
        begin
            extended_value = {{26{value[32]}},value};
            half_shift_add =
                (extended_value <<< 24) - (extended_value <<< 22) -
                (extended_value <<< 20) + (extended_value <<< 18) +
                (extended_value <<< 16) + (extended_value <<< 10) +
                (extended_value <<< 8)  - (extended_value <<< 4)  +
                (extended_value <<< 2)  - extended_value;
        end
    endfunction

    wire signed [58:0] fold_half_product_full =
        half_shift_add(input_sample_q15);
    wire signed [58:0] fold_half_product_negative_full = -fold_half_product_full;
    wire signed [34:0] fold_half_positive = fold_half_product_full[58:24];
    wire signed [34:0] fold_half_negative = fold_half_product_negative_full[58:24];

    function automatic signed [34:0] select_fold_term(
        input integer component,
        input [2:0] member,
        input signed [34:0] one_positive,
        input signed [34:0] one_negative,
        input signed [34:0] half_positive,
        input signed [34:0] half_negative
    );
        integer residue;
        integer phase;
        reg imaginary_component;
        begin
            if (component < 8) begin
                residue = component;
                imaginary_component = 1'b0;
            end else begin
                residue = component-8;
                imaginary_component = 1'b1;
            end
            phase = (residue*member) & 7;
            if (!imaginary_component) begin
                case (phase)
                    0: select_fold_term = one_positive;
                    1,7: select_fold_term = half_positive;
                    2,6: select_fold_term = 35'sd0;
                    3,5: select_fold_term = half_negative;
                    default: select_fold_term = one_negative;
                endcase
            end else begin
                case (phase)
                    0,4: select_fold_term = 35'sd0;
                    1,3: select_fold_term = half_negative;
                    2: select_fold_term = one_negative;
                    5,7: select_fold_term = half_positive;
                    default: select_fold_term = one_positive;
                endcase
            end
        end
    endfunction

    wire signed [31:0] fold_current [0:15];
    reg signed [34:0] fold_term [0:15];
    reg signed [35:0] fold_next [0:15];
    reg fold_overflow_next;
    wire [C_COLUMN_AW-1:0] residue_column;
    wire [C_COLUMN_AW-1:0] residue_word_address =
        input_active ? input_column :
            residue_column;
    wire signed [C_RESIDUE_BANKS*C_RESIDUE_STORE_WIDTH-1:0] residue_word_read;
    wire signed [C_RESIDUE_BANKS*C_RESIDUE_STORE_WIDTH-1:0] fold_next_word;
    // Reconstruct the 32-bit accumulate view by sign-extending the stored
    // 20-bit value.  Pure wiring, zero LUT cost.
    wire signed [31:0] bank_value [0:C_RESIDUE_BANKS-1];
    genvar bank_index;
    generate
        for (bank_index = 0; bank_index < C_RESIDUE_BANKS; bank_index = bank_index+1) begin : g_fold_read
            wire signed [C_RESIDUE_STORE_WIDTH-1:0] stored =
                residue_word_read[bank_index*C_RESIDUE_STORE_WIDTH +: C_RESIDUE_STORE_WIDTH];
            assign bank_value[bank_index] =
                {{(32-C_RESIDUE_STORE_WIDTH){stored[C_RESIDUE_STORE_WIDTH-1]}},stored};
            assign fold_current[bank_index] = bank_value[bank_index];
            assign fold_next_word[bank_index*C_RESIDUE_STORE_WIDTH +: C_RESIDUE_STORE_WIDTH] =
                fold_next[bank_index][C_RESIDUE_STORE_WIDTH-1:0];
        end
    endgenerate

    integer fold_index;
    always @* begin
        fold_overflow_next = 1'b0;
        for (fold_index = 0; fold_index < 16; fold_index = fold_index+1) begin
            fold_term[fold_index] = select_fold_term(
                fold_index,input_member,
                fold_one_positive,fold_one_negative,
                fold_half_positive,fold_half_negative);
            if (input_member == 0)
                fold_next[fold_index] =
                    $signed({fold_term[fold_index][34],fold_term[fold_index]});
            else
                fold_next[fold_index] =
                    $signed({{4{fold_current[fold_index][31]}},fold_current[fold_index]})+
                    $signed({fold_term[fold_index][34],fold_term[fold_index]});
            if (fold_next[fold_index][35:32] != {4{fold_next[fold_index][31]}})
                fold_overflow_next = 1'b1;
        end
    end

    wire [2:0] input_member_selected = input_member;
    wire [C_COLUMN_AW-1:0] input_column_selected = input_column;
    wire input_commit = input_active && i_sample_valid;
    wire final_sample_accept = input_commit && input_member_selected == 3'd7 &&
        input_column_selected == C_COLUMNS-1;
    wire bin_busy;
    wire bin_overflow;
    wire [C_D*3-1:0] residue_index;
    reg signed [C_D*32-1:0] residue_real;
    reg signed [C_D*32-1:0] residue_imag;

    genvar read_lane;
    generate if (C_D == 8) begin : g_fixed_bank_read
        // FIXED-BANK SPECIALIZATION (L4 C_D%4==0 precedent): batch_first_bin
        // starts at 1 and advances by C_D per batch, so for C_D==8 it stays
        // congruent to 1 (mod 8) and lane_bin[lane] mod 8 == (lane+1) mod 8
        // is a compile-time constant.  The per-lane 8:1 residue read mux
        // collapses to wiring.  Other D values keep the dynamic mux.
        for (read_lane = 0; read_lane < C_D; read_lane = read_lane+1) begin : g_lane_fixed
            wire [2:0] fixed_bank = read_lane + 1;
            assign residue_real[read_lane*32 +: 32] = bank_value[fixed_bank];
            assign residue_imag[read_lane*32 +: 32] = bank_value[8+fixed_bank];
        end
    end else begin : g_dynamic_bank_read
        for (read_lane = 0; read_lane < C_D; read_lane = read_lane+1) begin : g_lane_dyn
            assign residue_real[read_lane*32 +: 32] =
                bank_value[residue_index[read_lane*3 +: 3]];
            assign residue_imag[read_lane*32 +: 32] =
                bank_value[8+residue_index[read_lane*3 +: 3]];
        end
    end endgenerate

    e01_rfg_direct_bin_engine #(
        .C_N(C_N),
        .C_K(C_K),
        .C_L(8),
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
    assign residue_word_read = memory[residue_word_address];
    always @(posedge sys_clk)
        if (input_commit) memory[input_column_selected] <= fold_next_word;

    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            input_active <= 1'b0;
            input_member <= 3'd0;
            input_column <= {C_COLUMN_AW{1'b0}};
            input_pending <= 1'b0;
            input_member_hold <= 3'd0;
            input_column_hold <= {C_COLUMN_AW{1'b0}};
            input_sample_hold <= 16'sd0;
            fold_overflow_reg <= 1'b0;
        end else begin
            if (!input_active && !bin_busy) begin
                if (i_start) begin
                    input_active <= 1'b1;
                    input_member <= 3'd0;
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
        if (C_K < 1 || C_K >= C_N/2)
            $error("C_K must satisfy 1 <= C_K < C_N/2");
        if (!(C_D == 1 || C_D == 2 || C_D == 4 || C_D == 8))
            $error("C_D must be 1, 2, 4, or 8");
    end
`endif
endmodule
