`timescale 1ns/1ps

// Shared post-fold engine for the direct L-specific RFG tops.
// This is not a selectable RFG top: an L-specific top supplies already folded
// residues, while this engine schedules bins 1 through C_K on C_D frozen
// four-phase multiplier lanes.
module e01_rfg_direct_bin_engine #(
    parameter integer C_N = 64,
    parameter integer C_K = 24,
    parameter integer C_L = 8,
    parameter integer C_D = 1
) (
    input  wire                         sys_clk,           // 50 MHz system clock
    input  wire                         rst_n,             // Asynchronous active-low reset
    input  wire                         i_start,           // Starts bin processing after the final fold write
    input  wire                         i_fold_overflow,   // Sticky fold overflow captured at start
    input  wire                         i_result_ready,    // Accepts the current result
    output wire                         o_busy,            // Bin engine is active
    output wire [$clog2(C_N/C_L)-1:0]   o_residue_column,  // Current folded-sequence column
    output wire [C_D*$clog2(C_L)-1:0]   o_residue_index,   // Per-lane residue request
    input  wire signed [C_D*32-1:0]     i_residue_real,    // Per-lane Q15 folded real samples
    input  wire signed [C_D*32-1:0]     i_residue_imag,    // Per-lane Q15 folded imaginary samples
    output wire                         o_result_valid,    // Current complex result is valid
    output wire [8:0]                   o_bin_index,       // One-based target-bin index
    output wire signed [31:0]           o_result_real,     // Signed Q15 real component
    output wire signed [31:0]           o_result_imag,     // Signed Q15 imaginary component
    output wire                         o_result_last,     // Current result is the final bin
    output wire                         o_frame_done,      // Final-result handshake pulse
    output wire                         o_overflow         // Sticky arithmetic-wrap flag
);
    localparam integer C_COLUMNS = C_N/C_L;
    localparam integer C_COLUMN_AW = $clog2(C_COLUMNS);
    localparam integer C_RESIDUE_AW = $clog2(C_L);
    localparam integer C_LANE_AW = (C_D <= 1) ? 1 : $clog2(C_D);

    // H9: finite-horizon magnitude bounds, evaluated only at elaboration.
    // Return a narrower width only when the bound fits its positive signed range.
    // Width 32 is a fallback preserving the existing 32-bit wrap/check semantics.
    function automatic integer rfg_signed_width_capped32(input [63:0] magnitude_bound);
        integer width_candidate;
        begin
            rfg_signed_width_capped32 = 32;
            for (width_candidate = 31; width_candidate >= 1; width_candidate = width_candidate-1)
                if (magnitude_bound < (64'd1 << (width_candidate-1)))
                    rfg_signed_width_capped32 = width_candidate;
        end
    endfunction

    localparam [63:0] C_FOLD_INPUT_BOUND = 64'd65536*C_L;
    localparam [63:0] C_GO_BOUND =
        (C_FOLD_INPUT_BOUND+64'd1)*C_COLUMNS*(C_COLUMNS+64'd1)/64'd2;
    localparam [63:0] C_PREVIOUS_GO_BOUND =
        (C_FOLD_INPUT_BOUND+64'd1)*C_COLUMNS*(C_COLUMNS-64'd1)/64'd2;
    // H10: terminal cancellation bound for the current frozen Q24 tables.
    // Keep H9's triangle bounds when GO can wrap at 32 bits.
    localparam [63:0] C_RAW_TRIANGLE_BOUND =
        64'd2*C_GO_BOUND+C_PREVIOUS_GO_BOUND;
    localparam [63:0] C_RESULT_TRIANGLE_BOUND =
        ((C_L == 2) || (C_L == 4)) ?
        C_RAW_TRIANGLE_BOUND : 64'd2*C_RAW_TRIANGLE_BOUND;
    // H18: real input, non-DC/non-Nyquist bins, and the frozen-Q24 error
    // certificate give |RAW|, |RESULT| < 65536*N when GO cannot wrap.
    // Retain H9's original no-wrap gate; do not widen H10/H15 eligibility.
    // A 32-bit GO width alone does not imply wrap: test its magnitude bound.
    localparam integer C_TERMINAL_BOUND_VALID =
        (C_COLUMNS <= 256) && (C_GO_BOUND < (64'd1 << 31));
    localparam [63:0] C_TERMINAL_BOUND = 64'd65536*C_N-64'd1;
    localparam [63:0] C_RAW_BOUND =
        (C_TERMINAL_BOUND_VALID && (C_TERMINAL_BOUND < C_RAW_TRIANGLE_BOUND)) ?
        C_TERMINAL_BOUND : C_RAW_TRIANGLE_BOUND;
    localparam [63:0] C_RESULT_BOUND =
        (C_TERMINAL_BOUND_VALID && (C_TERMINAL_BOUND < C_RESULT_TRIANGLE_BOUND)) ?
        C_TERMINAL_BOUND : C_RESULT_TRIANGLE_BOUND;
    // H17: joint residue/coefficient bound for all legal bins of the
    // matching frozen front end. Axis residues have bounded impulse gain;
    // non-axis residues have a smaller folded-input magnitude.
    // Ceil((B+1)*M*(M+1)/3) bounds every committed GO prefix.
    // Keep C_GO_BOUND unchanged for RAW/RESULT bounds and H10/H15 gating.
    localparam [63:0] C_COUPLED_GO_BOUND =
        ((C_FOLD_INPUT_BOUND+64'd1)*C_COLUMNS*(C_COLUMNS+64'd1)+64'd2)/64'd3;
    localparam [63:0] C_GO_STATE_BOUND =
        (C_COUPLED_GO_BOUND < C_GO_BOUND) ? C_COUPLED_GO_BOUND : C_GO_BOUND;
    localparam integer C_GO_WIDTH = rfg_signed_width_capped32(C_GO_STATE_BOUND);
    localparam integer C_RAW_WIDTH = rfg_signed_width_capped32(C_RAW_BOUND);
    localparam integer C_RESULT_WIDTH = rfg_signed_width_capped32(C_RESULT_BOUND);

    // H15: H9/H10/H17/H18 prove every committed GO/RAW/RESULT value fits its
    // selected signed width when the existing terminal proof is valid.
    // Only the matching top/front-end legal input contract is assumed.
    // Keep all original checks when that proof is unavailable (N512 L2/L4).
    // Fold-overflow capture, reset, arithmetic and writebacks stay unchanged.
    localparam integer C_ARITHMETIC_GUARDS_REQUIRED = !C_TERMINAL_BOUND_VALID;

    // H6: imaginary residues are zero when bin mod (C_L/2) == 0.
    localparam integer C_ZERO_IMAG_RESIDUE_MASK = (C_L/2)-1;
    // H7: only L8/L16 lanes whose bins always land on quarter-turn phases.
    localparam integer C_QUARTER_PHASE_MASK = (C_L >= 8) ? (C_L/4)-1 : 0;
    localparam integer C_PHASE_QUADRANT_LSB = (C_L == 16) ? 2 : 1;

    localparam [4:0] ST_IDLE         = 5'd0;
    localparam [4:0] ST_BATCH_SETUP  = 5'd1;
    localparam [4:0] ST_GO_REAL      = 5'd2;
    localparam [4:0] ST_GO_REAL_WAIT = 5'd3;
    localparam [4:0] ST_GO_IMAG      = 5'd4;
    localparam [4:0] ST_GO_IMAG_WAIT = 5'd5;
    localparam [4:0] ST_RAW_CR       = 5'd6;
    localparam [4:0] ST_RAW_CR_WAIT  = 5'd7;
    localparam [4:0] ST_RAW_SI       = 5'd8;
    localparam [4:0] ST_RAW_SI_WAIT  = 5'd9;
    localparam [4:0] ST_RAW_SR       = 5'd10;
    localparam [4:0] ST_RAW_SR_WAIT  = 5'd11;
    localparam [4:0] ST_RAW_CI       = 5'd12;
    localparam [4:0] ST_RAW_CI_WAIT  = 5'd13;
    localparam [4:0] ST_PHASE_RR     = 5'd14;
    localparam [4:0] ST_PHASE_RR_WAIT= 5'd15;
    localparam [4:0] ST_PHASE_II     = 5'd16;
    localparam [4:0] ST_PHASE_II_WAIT= 5'd17;
    localparam [4:0] ST_PHASE_RI     = 5'd18;
    localparam [4:0] ST_PHASE_RI_WAIT= 5'd19;
    localparam [4:0] ST_PHASE_IR     = 5'd20;
    localparam [4:0] ST_PHASE_IR_WAIT= 5'd21;
    localparam [4:0] ST_OUTPUT       = 5'd22;
    localparam [4:0] ST_RESIDUE_READ = 5'd23;

    reg [4:0] state_current;
    reg [8:0] batch_first_bin;
    reg [8:0] batch_index;
    reg [C_COLUMN_AW-1:0] go_column;
    reg [C_LANE_AW-1:0] output_lane;
    reg overflow_reg;

    reg [8:0] lane_bin [0:C_D-1];
    reg lane_active [0:C_D-1];
    reg signed [31:0] state1_real [0:C_D-1];
    reg signed [31:0] state1_imag [0:C_D-1];
    reg signed [31:0] state2_real [0:C_D-1];
    reg signed [31:0] state2_imag [0:C_D-1];
    reg signed [31:0] raw_real [0:C_D-1];
    reg signed [31:0] raw_imag [0:C_D-1];
    reg signed [31:0] result_real [0:C_D-1];
    reg signed [31:0] result_imag [0:C_D-1];
    reg signed [34:0] product_hold0 [0:C_D-1];
    reg signed [34:0] product_hold1 [0:C_D-1];
    reg signed [34:0] product_hold2 [0:C_D-1];

    function automatic signed [25:0] phase_cosine_q24(input [3:0] residue);
        begin
            if (C_L == 2) begin
                phase_cosine_q24 = residue[0] ? -26'sd16777216 : 26'sd16777216;
            end else if (C_L == 8) begin
                case (residue[2:0])
                    3'd0: phase_cosine_q24 =  26'sd16777216;
                    3'd1: phase_cosine_q24 =  26'sd11863283;
                    3'd2: phase_cosine_q24 =  26'sd0;
                    3'd3: phase_cosine_q24 = -26'sd11863283;
                    3'd4: phase_cosine_q24 = -26'sd16777216;
                    3'd5: phase_cosine_q24 = -26'sd11863283;
                    3'd6: phase_cosine_q24 =  26'sd0;
                    default: phase_cosine_q24 = 26'sd11863283;
                endcase
            end else begin
                case (residue)
                    4'd0:  phase_cosine_q24 =  26'sd16777216;
                    4'd1:  phase_cosine_q24 =  26'sd15500126;
                    4'd2:  phase_cosine_q24 =  26'sd11863283;
                    4'd3:  phase_cosine_q24 =  26'sd6420363;
                    4'd4:  phase_cosine_q24 =  26'sd0;
                    4'd5:  phase_cosine_q24 = -26'sd6420363;
                    4'd6:  phase_cosine_q24 = -26'sd11863283;
                    4'd7:  phase_cosine_q24 = -26'sd15500126;
                    4'd8:  phase_cosine_q24 = -26'sd16777216;
                    4'd9:  phase_cosine_q24 = -26'sd15500126;
                    4'd10: phase_cosine_q24 = -26'sd11863283;
                    4'd11: phase_cosine_q24 = -26'sd6420363;
                    4'd12: phase_cosine_q24 =  26'sd0;
                    4'd13: phase_cosine_q24 =  26'sd6420363;
                    4'd14: phase_cosine_q24 =  26'sd11863283;
                    default: phase_cosine_q24 = 26'sd15500126;
                endcase
            end
        end
    endfunction

    function automatic signed [25:0] phase_negative_sine_q24(input [3:0] residue);
        begin
            if (C_L == 2) begin
                phase_negative_sine_q24 = 26'sd0;
            end else if (C_L == 8) begin
                case (residue[2:0])
                    3'd0: phase_negative_sine_q24 =  26'sd0;
                    3'd1: phase_negative_sine_q24 = -26'sd11863283;
                    3'd2: phase_negative_sine_q24 = -26'sd16777216;
                    3'd3: phase_negative_sine_q24 = -26'sd11863283;
                    3'd4: phase_negative_sine_q24 =  26'sd0;
                    3'd5: phase_negative_sine_q24 =  26'sd11863283;
                    3'd6: phase_negative_sine_q24 =  26'sd16777216;
                    default: phase_negative_sine_q24 = 26'sd11863283;
                endcase
            end else begin
                case (residue)
                    4'd0:  phase_negative_sine_q24 =  26'sd0;
                    4'd1:  phase_negative_sine_q24 = -26'sd6420363;
                    4'd2:  phase_negative_sine_q24 = -26'sd11863283;
                    4'd3:  phase_negative_sine_q24 = -26'sd15500126;
                    4'd4:  phase_negative_sine_q24 = -26'sd16777216;
                    4'd5:  phase_negative_sine_q24 = -26'sd15500126;
                    4'd6:  phase_negative_sine_q24 = -26'sd11863283;
                    4'd7:  phase_negative_sine_q24 = -26'sd6420363;
                    4'd8:  phase_negative_sine_q24 =  26'sd0;
                    4'd9:  phase_negative_sine_q24 =  26'sd6420363;
                    4'd10: phase_negative_sine_q24 =  26'sd11863283;
                    4'd11: phase_negative_sine_q24 =  26'sd15500126;
                    4'd12: phase_negative_sine_q24 =  26'sd16777216;
                    4'd13: phase_negative_sine_q24 =  26'sd15500126;
                    4'd14: phase_negative_sine_q24 =  26'sd11863283;
                    default: phase_negative_sine_q24 = 26'sd6420363;
                endcase
            end
        end
    endfunction

    wire signed [25:0] lane_cosine [0:C_D-1];
    wire signed [25:0] lane_negative_sine [0:C_D-1];
    wire signed [25:0] lane_phase_cosine [0:C_D-1];
    wire signed [25:0] lane_phase_negative_sine [0:C_D-1];
    wire signed [31:0] lane_residue_real [0:C_D-1];
    wire signed [31:0] lane_residue_imag [0:C_D-1];
    wire signed [34:0] lane_product [0:C_D-1];
    wire [C_D-1:0] lane_static_zero_imag;
    wire [C_D-1:0] lane_static_quarter_phase;
    wire [1:0] lane_phase_quadrant [0:C_D-1];

    // H19: GO/RAW imaginary updates use (A + current_product) - state2.
    // PHASE uses the same first sum, without the state2 subtraction.
    // Keep the post-stage operand at its existing observable width so sharing
    // does not make product_hold2 retain otherwise unconsumed high bits.
    localparam integer C_IMAG_POST_OPERAND_WIDTH =
        C_ARITHMETIC_GUARDS_REQUIRED ? 33 :
        ((C_RAW_WIDTH > C_RESULT_WIDTH) ? C_RAW_WIDTH : C_RESULT_WIDTH);
    wire imag_shared_use_residue = (state_current == ST_GO_IMAG_WAIT);
    wire signed [32:0] lane_imag_shared_sum [0:C_D-1];
    wire signed [32:0] lane_imag_shared_difference [0:C_D-1];

    // H20: share real GO/RAW arithmetic, and expose the first operation
    // to ordinary PHASE consumers. Preserve the existing H6/H7 special cases.
    // Limit post-stage inputs to their observable bits, as in H19.
    localparam integer C_REAL_POST_OPERAND_WIDTH =
        C_ARITHMETIC_GUARDS_REQUIRED ? 33 :
        ((C_RAW_WIDTH > C_RESULT_WIDTH) ? C_RAW_WIDTH : C_RESULT_WIDTH);
    wire real_shared_use_residue = (state_current == ST_GO_REAL_WAIT);
    wire signed [32:0] lane_real_shared_first [0:C_D-1];
    wire signed [32:0] lane_real_shared_difference [0:C_D-1];

    reg [C_D-1:0] multiplier_start;
    reg signed [C_D*33-1:0] multiplier_data;
    reg signed [C_D*26-1:0] multiplier_coefficient;
    wire [C_D-1:0] multiplier_busy;
    wire [C_D-1:0] multiplier_done;
    wire signed [C_D*35-1:0] multiplier_product;

    genvar generated_lane;
    generate
        for (generated_lane = 0; generated_lane < C_D; generated_lane = generated_lane+1) begin : g_lane
            // All operands below are elaboration constants, including generated_lane.
            // Active bins on this physical lane are 1+generated_lane+batch*C_D.
            assign lane_static_zero_imag[generated_lane] =
                ((C_D & C_ZERO_IMAG_RESIDUE_MASK) == 0) &&
                (((generated_lane+1) & C_ZERO_IMAG_RESIDUE_MASK) == 0);
            assign lane_static_quarter_phase[generated_lane] =
                ((C_L == 8) || (C_L == 16)) &&
                ((C_D & C_QUARTER_PHASE_MASK) == 0) &&
                (((generated_lane+1) & C_QUARTER_PHASE_MASK) == 0);
            assign lane_phase_quadrant[generated_lane] =
                lane_bin[generated_lane][C_PHASE_QUADRANT_LSB +: 2];
            e01_rfg_bin_twiddle_q24 #(
                .C_N(C_N),
                .C_K(C_K),
                .C_D(C_D),
                .C_LANE(generated_lane)
            ) u_bin_twiddle (
                .i_batch_index(batch_index),
                .o_cosine(lane_cosine[generated_lane]),
                .o_negative_sine(lane_negative_sine[generated_lane])
            );
            assign o_residue_index[generated_lane*C_RESIDUE_AW +: C_RESIDUE_AW] =
                lane_bin[generated_lane][C_RESIDUE_AW-1:0];
            assign lane_residue_real[generated_lane] =
                i_residue_real[generated_lane*32 +: 32];
            assign lane_residue_imag[generated_lane] =
                i_residue_imag[generated_lane*32 +: 32];
            if ((C_L == 8) || (C_L == 16)) begin : g_phase_by_batch
                // H24: k=1+lane+batch*D during every issued PHASE transaction.
                // Evaluate the unchanged phase functions at elaboration.
                // Cap the table at the residue period, even for large K.
                localparam integer C_PHASE_BATCHES = (C_K+C_D-1)/C_D;
                localparam integer C_PHASE_PERIOD = (C_D < C_L) ? C_L/C_D : 1;
                localparam integer C_PHASE_OPTIONS =
                    (C_PHASE_BATCHES < C_PHASE_PERIOD) ? C_PHASE_BATCHES : C_PHASE_PERIOD;
                localparam integer C_PHASE_SELECT_AW =
                    (C_PHASE_OPTIONS <= 1) ? 1 : $clog2(C_PHASE_OPTIONS);
                wire signed [25:0] phase_cosine_options [0:C_PHASE_OPTIONS-1];
                wire signed [25:0] phase_negative_sine_options [0:C_PHASE_OPTIONS-1];
                genvar phase_option;
                for (phase_option = 0; phase_option < C_PHASE_OPTIONS;
                     phase_option = phase_option+1) begin : g_option
                    localparam [3:0] C_PHASE_BIN =
                        phase_option*C_D+generated_lane+1;
                    assign phase_cosine_options[phase_option] =
                        phase_cosine_q24(C_PHASE_BIN);
                    assign phase_negative_sine_options[phase_option] =
                        phase_negative_sine_q24(C_PHASE_BIN);
                end
                if (C_PHASE_OPTIONS == 1) begin : g_constant
                    assign lane_phase_cosine[generated_lane] = phase_cosine_options[0];
                    assign lane_phase_negative_sine[generated_lane] =
                        phase_negative_sine_options[0];
                end else begin : g_lookup
                    assign lane_phase_cosine[generated_lane] =
                        phase_cosine_options[batch_index[C_PHASE_SELECT_AW-1:0]];
                    assign lane_phase_negative_sine[generated_lane] =
                        phase_negative_sine_options[batch_index[C_PHASE_SELECT_AW-1:0]];
                end
            end else begin : g_phase_legacy
                // L2/L4 do not issue PHASE transactions; retain their old wiring.
                assign lane_phase_cosine[generated_lane] =
                    phase_cosine_q24(lane_bin[generated_lane][3:0]);
                assign lane_phase_negative_sine[generated_lane] =
                    phase_negative_sine_q24(lane_bin[generated_lane][3:0]);
            end
            assign lane_product[generated_lane] =
                multiplier_product[generated_lane*35 +: 35];

            // H19: one selected addend, one sum, and one difference per lane.
            // GO observes all 33 low bits. Post stages observe only their
            // writeback bits, or all 33 bits when arithmetic guards are kept.
            wire signed [32:0] imag_shared_addend =
                imag_shared_use_residue ?
                $signed({lane_residue_imag[generated_lane][31],
                         lane_residue_imag[generated_lane]}) :
                $signed({{(33-C_IMAG_POST_OPERAND_WIDTH){
                             product_hold2[generated_lane][C_IMAG_POST_OPERAND_WIDTH-1]}},
                         product_hold2[generated_lane][C_IMAG_POST_OPERAND_WIDTH-1:0]});
            assign lane_imag_shared_sum[generated_lane] =
                imag_shared_addend + $signed(lane_product[generated_lane][32:0]);
            assign lane_imag_shared_difference[generated_lane] =
                lane_imag_shared_sum[generated_lane] -
                $signed({state2_imag[generated_lane][31],state2_imag[generated_lane]});

            // H20: only low post-stage bits can reach a writeback or guard.
            wire signed [32:0] real_post_hold0 =
                $signed({{(33-C_REAL_POST_OPERAND_WIDTH){
                             product_hold0[generated_lane][C_REAL_POST_OPERAND_WIDTH-1]}},
                         product_hold0[generated_lane][C_REAL_POST_OPERAND_WIDTH-1:0]});
            if (((C_D & C_ZERO_IMAG_RESIDUE_MASK) == 0) &&
                (((generated_lane+1) & C_ZERO_IMAG_RESIDUE_MASK) == 0)) begin : g_real_zero_imag
                // Same elaboration predicate as H6. RAW is H0-S here:
                // share only the last subtract; do not recreate an H1 path.
                wire signed [32:0] real_go_sum =
                    $signed({lane_residue_real[generated_lane][31],
                             lane_residue_real[generated_lane]}) +
                    $signed(lane_product[generated_lane][32:0]);
                assign lane_real_shared_first[generated_lane] =
                    real_shared_use_residue ? real_go_sum : real_post_hold0;
            end else begin : g_real_complex
                wire signed [32:0] real_post_hold1 =
                    $signed({{(33-C_REAL_POST_OPERAND_WIDTH){
                                 product_hold1[generated_lane][C_REAL_POST_OPERAND_WIDTH-1]}},
                             product_hold1[generated_lane][C_REAL_POST_OPERAND_WIDTH-1:0]});
                wire signed [32:0] real_shared_left =
                    real_shared_use_residue ?
                    $signed({lane_residue_real[generated_lane][31],
                             lane_residue_real[generated_lane]}) : real_post_hold0;
                wire signed [32:0] real_shared_right =
                    real_shared_use_residue ?
                    $signed(lane_product[generated_lane][32:0]) : ~real_post_hold1;
                // One binary adder. The appended low bit injects carry-in:
                // GO: Y+P; RAW/ordinary PHASE: H0+(~H1)+1 == H0-H1.
                wire [33:0] real_shared_add_full =
                    {real_shared_left,1'b1} +
                    {real_shared_right,(!real_shared_use_residue)};
                assign lane_real_shared_first[generated_lane] =
                    real_shared_add_full[33:1];
            end
            assign lane_real_shared_difference[generated_lane] =
                lane_real_shared_first[generated_lane] -
                $signed({state2_real[generated_lane][31],state2_real[generated_lane]});
        end
    endgenerate

    e01_four_part_mul_scheduler #(
        .C_D(C_D),
        .C_DATA_WIDTH(33)
    ) u_multiplier_scheduler (
        .sys_clk(sys_clk),
        .rst_n(rst_n),
        .i_start(multiplier_start),
        .i_data(multiplier_data),
        .i_coefficient(multiplier_coefficient),
        .o_busy(multiplier_busy),
        .o_done(multiplier_done),
        .o_product_q15(multiplier_product)
    );

    // ---- Handover GPT 第 4 轮 H3A（round4a_engine_data_mux.svh）以下 63 行原样嵌入 ----
    // 数据来源只由发射操作决定；未发射拍的总线值不被共享乘法器锁存。
    wire multiplier_use_raw_data =
        (state_current == ST_PHASE_RR) || (state_current == ST_PHASE_RI) ||
        (state_current == ST_PHASE_II) || (state_current == ST_PHASE_IR);
    wire multiplier_use_imag_data =
        (state_current == ST_GO_IMAG) || (state_current == ST_RAW_SI) ||
        (state_current == ST_RAW_CI) || (state_current == ST_PHASE_II) ||
        (state_current == ST_PHASE_IR);

    // ---- Handover GPT 第 5 轮 H3B（round5_engine_coefficient_mux.svh）以下 58 行原样嵌入 ----
    integer lane;
    always @* begin
        multiplier_start = {C_D{1'b0}};
        for (lane = 0; lane < C_D; lane = lane+1) begin
            multiplier_data[lane*33 +: 33] =
                multiplier_use_raw_data ?
                // Quarter-turn RR/IR select the complete output component.
                ((multiplier_use_imag_data ^
                  (lane_static_quarter_phase[lane] && lane_phase_quadrant[lane][0])) ?
                    {raw_imag[lane][31],raw_imag[lane]} :
                    {raw_real[lane][31],raw_real[lane]}) :
                (multiplier_use_imag_data ?
                    {state1_imag[lane][31],state1_imag[lane]} :
                    {state1_real[lane][31],state1_real[lane]});
            // 按系数来源分组；每个 lane 每次组合求值都有完整赋值。
            // 默认 cosine 同时覆盖 RAW_CR/RAW_CI；其余默认拍不会发射事务。
            case (state_current)
                ST_GO_REAL, ST_GO_IMAG:
                    multiplier_coefficient[lane*26 +: 26] =
                        lane_cosine[lane] <<< 1;
                ST_RAW_SI, ST_RAW_SR:
                    multiplier_coefficient[lane*26 +: 26] =
                        -lane_negative_sine[lane];
                ST_PHASE_RR:
                    multiplier_coefficient[lane*26 +: 26] =
                        lane_static_quarter_phase[lane] ?
                        {lane_phase_quadrant[lane][1],1'b1,24'd0} :
                        lane_phase_cosine[lane];
                ST_PHASE_IR:
                    multiplier_coefficient[lane*26 +: 26] =
                        lane_static_quarter_phase[lane] ?
                        {(lane_phase_quadrant[lane][1] ^ lane_phase_quadrant[lane][0]),1'b1,24'd0} :
                        lane_phase_cosine[lane];
                ST_PHASE_II, ST_PHASE_RI:
                    // These products are unconsumed only on quarter-turn lanes.
                    multiplier_coefficient[lane*26 +: 26] =
                        lane_static_quarter_phase[lane] ?
                        lane_cosine[lane] : lane_phase_negative_sine[lane];
                default:
                    multiplier_coefficient[lane*26 +: 26] =
                        lane_cosine[lane];
            endcase

            // 发射条件保持原状态分组与 lane_active 门控。
            if (lane_active[lane]) begin
                case (state_current)
                    ST_GO_REAL: begin
                        multiplier_start[lane] = 1'b1;
                    end
                    ST_GO_IMAG: begin
                        multiplier_start[lane] = 1'b1;
                    end
                    ST_RAW_CR, ST_RAW_SR: begin
                        multiplier_start[lane] = 1'b1;
                    end
                    ST_RAW_SI, ST_RAW_CI: begin
                        multiplier_start[lane] = 1'b1;
                    end
                    ST_PHASE_RR, ST_PHASE_RI: begin
                        multiplier_start[lane] = 1'b1;
                    end
                    ST_PHASE_II, ST_PHASE_IR: begin
                        multiplier_start[lane] = 1'b1;
                    end
                    default: begin end
                endcase
            end
        end
    end

    reg [C_D-1:0] active_lane_mask;
    wire active_done = &(multiplier_done | ~active_lane_mask);
    always @* begin
        for (lane = 0; lane < C_D; lane = lane+1)
            active_lane_mask[lane] = lane_active[lane];
    end

    assign o_busy = state_current != ST_IDLE;
    assign o_residue_column = go_column;
    assign o_result_valid = state_current == ST_OUTPUT;
    assign o_bin_index = lane_bin[output_lane];

    // Post-fold output de-rotation.  Constant-folded on C_L: only the selected
    // branch survives elaboration, so no runtime L mux is created.
    //   C_L==2 : raw pair is rotated by the bin parity (sign only)
    //   C_L==4 : raw pair is rotated by the bin residue mod 4 (sign/swap only)
    //   C_L==8/16 : PHASE transactions produced the final pair (H7 specializes quarter turns)
    reg signed [31:0] selected_result_real;
    reg signed [31:0] selected_result_imag;
    wire [1:0] l4_output_rotation =
        ((C_D % 4) == 0) ? ((output_lane + 1'b1) & 2'd3) : lane_bin[output_lane][1:0];
    always @* begin
        if (C_L == 2) begin
            if (lane_bin[output_lane][0]) begin
                selected_result_real = -raw_real[output_lane];
                selected_result_imag = -raw_imag[output_lane];
            end else begin
                selected_result_real = raw_real[output_lane];
                selected_result_imag = raw_imag[output_lane];
            end
        end else if (C_L == 4) begin
            selected_result_real = raw_real[output_lane];
            selected_result_imag = raw_imag[output_lane];
            case (l4_output_rotation)
                2'd0: begin end
                2'd1: begin
                    selected_result_real = raw_imag[output_lane];
                    selected_result_imag = -raw_real[output_lane];
                end
                2'd2: begin
                    selected_result_real = -raw_real[output_lane];
                    selected_result_imag = -raw_imag[output_lane];
                end
                default: begin
                    selected_result_real = -raw_imag[output_lane];
                    selected_result_imag = raw_real[output_lane];
                end
            endcase
        end else begin
            selected_result_real = result_real[output_lane];
            selected_result_imag = result_imag[output_lane];
        end
    end
    assign o_result_real = selected_result_real;
    assign o_result_imag = selected_result_imag;
    assign o_result_last = o_result_valid && (lane_bin[output_lane] == C_K);
    assign o_frame_done = o_result_last && i_result_ready;
    assign o_overflow = overflow_reg;

    // 2026-09-11 面积优化：算术临时量只需"输出宽度 + 1 位溢出位"。
    // 落盘/输出的都是 [31:0]（32 位有符号），原来 36 位里多出的 [35:32] 只服务
    // "是否超出 32 位"这个判据。收窄到 33 位后，判据 "bit32 != bit31" 与原来的
    // "[35:32] != {{4{bit31}}}" **完全等价**（33 位和的 bit32 即 32 位的符号溢出位），
    // 且和的低 32 位只取决于操作数低 32 位 ⇒ 写入的结果逐位不变。纯等价收窄，不改语义。
    // H9: signed33 arithmetic views remain; writebacks/checks use the proven stage width.
    reg signed [32:0] arithmetic_real;
    reg signed [32:0] arithmetic_imag;
    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            state_current <= ST_IDLE;
            batch_first_bin <= 9'd1;
            batch_index <= 9'd0;
            go_column <= {C_COLUMN_AW{1'b0}};
            output_lane <= {C_LANE_AW{1'b0}};
            overflow_reg <= 1'b0;
        end else begin
            case (state_current)
                ST_IDLE: begin
                    if (i_start) begin
                        batch_first_bin <= 9'd1;
                        batch_index <= 9'd0;
                        overflow_reg <= i_fold_overflow;
                        state_current <= ST_BATCH_SETUP;
                    end
                end
                ST_BATCH_SETUP: begin
                    go_column <= {C_COLUMN_AW{1'b0}};
                    output_lane <= {C_LANE_AW{1'b0}};
                    for (lane = 0; lane < C_D; lane = lane+1) begin
                        lane_bin[lane] <= batch_first_bin+lane;
                        lane_active[lane] <= (batch_first_bin+lane) <= C_K;
                        state1_real[lane] <= 32'sd0;
                        state1_imag[lane] <= 32'sd0;
                        state2_real[lane] <= 32'sd0;
                        state2_imag[lane] <= 32'sd0;
                        raw_real[lane] <= 32'sd0;
                        raw_imag[lane] <= 32'sd0;
                        result_real[lane] <= 32'sd0;
                        result_imag[lane] <= 32'sd0;
                        product_hold0[lane] <= 35'sd0;
                        product_hold1[lane] <= 35'sd0;
                        product_hold2[lane] <= 35'sd0;
                    end
                    state_current <= ST_GO_REAL;
                end
                ST_RESIDUE_READ: state_current <= ST_GO_REAL;
                ST_GO_REAL: state_current <= ST_GO_REAL_WAIT;
                ST_GO_REAL_WAIT: begin
                    if (active_done) begin
                        for (lane = 0; lane < C_D; lane = lane+1) begin
                            if (lane_active[lane]) begin
                                arithmetic_real = lane_real_shared_difference[lane];
                                state2_real[lane] <= state1_real[lane];
                                state1_real[lane] <=
                                    {{(32-C_GO_WIDTH){arithmetic_real[C_GO_WIDTH-1]}},
                                     arithmetic_real[C_GO_WIDTH-1:0]};
                                if (C_ARITHMETIC_GUARDS_REQUIRED &&
                                    (arithmetic_real[C_GO_WIDTH] != arithmetic_real[C_GO_WIDTH-1]))
                                    overflow_reg <= 1'b1;
                            end
                        end
                        state_current <= ST_GO_IMAG;
                    end
                end
                ST_GO_IMAG: state_current <= ST_GO_IMAG_WAIT;
                ST_GO_IMAG_WAIT: begin
                    if (active_done) begin
                        for (lane = 0; lane < C_D; lane = lane+1) begin
                            if (lane_active[lane]) begin
                                if (lane_static_zero_imag[lane]) begin
                                    // Batch setup initializes both states; zero input keeps them zero.
                                    // Keep the original transaction and active_done wait.
                                    arithmetic_imag = 33'sd0;
                                    state2_imag[lane] <= 32'sd0;
                                    state1_imag[lane] <= 32'sd0;
                                end else begin
                                    arithmetic_imag = lane_imag_shared_difference[lane];
                                    state2_imag[lane] <= state1_imag[lane];
                                    state1_imag[lane] <=
                                        {{(32-C_GO_WIDTH){arithmetic_imag[C_GO_WIDTH-1]}},
                                         arithmetic_imag[C_GO_WIDTH-1:0]};
                                end
                                if (C_ARITHMETIC_GUARDS_REQUIRED &&
                                    (arithmetic_imag[C_GO_WIDTH] != arithmetic_imag[C_GO_WIDTH-1]))
                                    overflow_reg <= 1'b1;
                            end
                        end
                        if (go_column == C_COLUMNS-1)
                            state_current <= ST_RAW_CR;
                        else begin
                            go_column <= go_column+1'b1;
                            state_current <= ST_GO_REAL;
                        end
                    end
                end
                ST_RAW_CR: state_current <= ST_RAW_CR_WAIT;
                ST_RAW_CR_WAIT: if (active_done) begin
                    for (lane = 0; lane < C_D; lane = lane+1)
                        if (lane_active[lane]) product_hold0[lane] <= lane_product[lane];
                    state_current <= ST_RAW_SI;
                end
                ST_RAW_SI: state_current <= ST_RAW_SI_WAIT;
                ST_RAW_SI_WAIT: if (active_done) begin
                    for (lane = 0; lane < C_D; lane = lane+1)
                        if (lane_active[lane]) product_hold1[lane] <= lane_product[lane];
                    state_current <= ST_RAW_SR;
                end
                ST_RAW_SR: state_current <= ST_RAW_SR_WAIT;
                ST_RAW_SR_WAIT: if (active_done) begin
                    for (lane = 0; lane < C_D; lane = lane+1)
                        if (lane_active[lane]) product_hold2[lane] <= lane_product[lane];
                    state_current <= ST_RAW_CI;
                end
                ST_RAW_CI: state_current <= ST_RAW_CI_WAIT;
                ST_RAW_CI_WAIT: if (active_done) begin
                    for (lane = 0; lane < C_D; lane = lane+1) begin
                        if (lane_active[lane]) begin
                            if (lane_static_zero_imag[lane]) begin
                                // RAW_SI and RAW_CI multiply the invariant-zero state1_imag.
                                // raw_imag itself is generally nonzero and must be retained.
                                arithmetic_real = lane_real_shared_difference[lane];
                                arithmetic_imag =
                                    $signed({product_hold2[lane][34],product_hold2[lane]});
                            end else begin
                                arithmetic_real = lane_real_shared_difference[lane];
                                arithmetic_imag = lane_imag_shared_difference[lane];
                            end
                            raw_real[lane] <=
                                {{(32-C_RAW_WIDTH){arithmetic_real[C_RAW_WIDTH-1]}},
                                 arithmetic_real[C_RAW_WIDTH-1:0]};
                            raw_imag[lane] <=
                                {{(32-C_RAW_WIDTH){arithmetic_imag[C_RAW_WIDTH-1]}},
                                 arithmetic_imag[C_RAW_WIDTH-1:0]};
                            if (C_ARITHMETIC_GUARDS_REQUIRED &&
                                (arithmetic_real[C_RAW_WIDTH] != arithmetic_real[C_RAW_WIDTH-1] ||
                                 arithmetic_imag[C_RAW_WIDTH] != arithmetic_imag[C_RAW_WIDTH-1]))
                                overflow_reg <= 1'b1;
                            // Negation-overflow guard for the sign-only de-rotations.
                            // C_L==2: only the parity bit can negate raw_imag.
                            // C_L==4: the mod-4 rotation negates raw_real, or both,
                            //         or the freshly computed raw_imag (see the case
                            //         table in the output selection above).
                            if (C_ARITHMETIC_GUARDS_REQUIRED &&
                                C_L == 2 && lane_bin[lane][0] &&
                                (arithmetic_real[31:0] == 32'sh80000000 ||
                                 arithmetic_imag[31:0] == 32'sh80000000))
                                overflow_reg <= 1'b1;
                            if (C_ARITHMETIC_GUARDS_REQUIRED && C_L == 4 &&
                                ((lane_bin[lane][1:0] == 2'd1 &&
                                  raw_real[lane] == 32'sh80000000) ||
                                 (lane_bin[lane][1:0] == 2'd2 &&
                                  (raw_real[lane] == 32'sh80000000 ||
                                   arithmetic_imag[31:0] == 32'sh80000000)) ||
                                 (lane_bin[lane][1:0] == 2'd3 &&
                                  arithmetic_imag[31:0] == 32'sh80000000)))
                                overflow_reg <= 1'b1;
                        end
                    end
                    output_lane <= {C_LANE_AW{1'b0}};
                    // L2/L4 need no four-phase phase rotation: the raw pair is already
                    // the final pair up to a constant sign/swap.
                    if (C_L == 2 || C_L == 4)
                        state_current <= ST_OUTPUT;
                    else
                        state_current <= ST_PHASE_RR;
                end
                ST_PHASE_RR: state_current <= ST_PHASE_RR_WAIT;
                ST_PHASE_RR_WAIT: if (active_done) begin
                    for (lane = 0; lane < C_D; lane = lane+1)
                        if (lane_active[lane]) product_hold0[lane] <= lane_product[lane];
                    state_current <= ST_PHASE_II;
                end
                ST_PHASE_II: state_current <= ST_PHASE_II_WAIT;
                ST_PHASE_II_WAIT: if (active_done) begin
                    for (lane = 0; lane < C_D; lane = lane+1)
                        if (lane_active[lane] && !lane_static_quarter_phase[lane])
                            product_hold1[lane] <= lane_product[lane];
                    state_current <= ST_PHASE_RI;
                end
                ST_PHASE_RI: state_current <= ST_PHASE_RI_WAIT;
                ST_PHASE_RI_WAIT: if (active_done) begin
                    for (lane = 0; lane < C_D; lane = lane+1)
                        if (lane_active[lane] && !lane_static_quarter_phase[lane])
                            product_hold2[lane] <= lane_product[lane];
                    state_current <= ST_PHASE_IR;
                end
                ST_PHASE_IR: state_current <= ST_PHASE_IR_WAIT;
                ST_PHASE_IR_WAIT: if (active_done) begin
                    for (lane = 0; lane < C_D; lane = lane+1) begin
                        if (lane_active[lane]) begin
                            if (lane_static_quarter_phase[lane]) begin
                                // RR and IR already contain the complete signed results.
                                // Preserve +2^31 in arithmetic_* for the original overflow check.
                                arithmetic_real =
                                    $signed({product_hold0[lane][34],product_hold0[lane]});
                                arithmetic_imag =
                                    $signed({lane_product[lane][34],lane_product[lane]});
                            end else begin
                                arithmetic_real = lane_real_shared_first[lane];
                                arithmetic_imag = lane_imag_shared_sum[lane];
                            end
                            result_real[lane] <=
                                {{(32-C_RESULT_WIDTH){arithmetic_real[C_RESULT_WIDTH-1]}},
                                 arithmetic_real[C_RESULT_WIDTH-1:0]};
                            result_imag[lane] <=
                                {{(32-C_RESULT_WIDTH){arithmetic_imag[C_RESULT_WIDTH-1]}},
                                 arithmetic_imag[C_RESULT_WIDTH-1:0]};
                            if (C_ARITHMETIC_GUARDS_REQUIRED &&
                                (arithmetic_real[C_RESULT_WIDTH] != arithmetic_real[C_RESULT_WIDTH-1] ||
                                 arithmetic_imag[C_RESULT_WIDTH] != arithmetic_imag[C_RESULT_WIDTH-1]))
                                overflow_reg <= 1'b1;
                        end
                    end
                    output_lane <= {C_LANE_AW{1'b0}};
                    state_current <= ST_OUTPUT;
                end
                ST_OUTPUT: begin
                    if (i_result_ready) begin
                        if (lane_bin[output_lane] == C_K) begin
                            state_current <= ST_IDLE;
                        end else if (output_lane == C_D-1 ||
                                     !lane_active[output_lane+1'b1]) begin
                            batch_first_bin <= batch_first_bin+C_D;
                            batch_index <= batch_index+1'b1;
                            state_current <= ST_BATCH_SETUP;
                        end else begin
                            output_lane <= output_lane+1'b1;
                        end
                    end
                end
                default: state_current <= ST_IDLE;
            endcase
        end
    end

`ifndef SYNTHESIS
    initial begin
        if (!(C_N == 64 || C_N == 128 || C_N == 256 || C_N == 512))
            $error("C_N must be 64, 128, 256, or 512");
        if (C_K < 1 || C_K >= C_N/2)
            $error("C_K must satisfy 1 <= C_K < C_N/2");
        if (!(C_L == 2 || C_L == 4 || C_L == 8 || C_L == 16))
            $error("The direct bin engine supports C_L = 2, 4, 8, or 16");
        if ((C_N % C_L) != 0 || C_COLUMNS < 4)
            $error("C_L must divide C_N and leave at least four columns");
        if (!(C_D == 1 || C_D == 2 || C_D == 4 || C_D == 8))
            $error("C_D must be 1, 2, 4, or 8");
    end
`endif
endmodule
