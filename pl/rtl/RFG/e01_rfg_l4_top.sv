`timescale 1ns/1ps

// Isolated L4 RFG core with streaming residue folding.
// The common four-part multiplier remains the only variable-coefficient
// arithmetic primitive; L4-only rotations use exact sign and swap logic.
module e01_rfg_l4_top #(
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
    localparam integer C_COLUMNS = C_N/4;
    localparam integer C_COLUMN_AW = (C_COLUMNS <= 1) ? 1 : $clog2(C_COLUMNS);
    localparam integer C_LANE_AW = (C_D <= 1) ? 1 : $clog2(C_D);
    // Each L4 residue contains four signed Q15 terms.  Nineteen value bits
    // cover the full legal input range: [-4*2^16, 4*(2^16-2)].  Q15 input
    // terms are always even, so bit zero is omitted from storage without
    // losing information; the 18 stored bits are restored on read.
    localparam integer C_RESIDUE_VALUE_WIDTH = 19;
    localparam integer C_RESIDUE_STORAGE_WIDTH = 18;

    localparam [4:0] ST_IDLE        = 5'd0;
    localparam [4:0] ST_INPUT       = 5'd1;
    localparam [4:0] ST_BATCH_SETUP = 5'd2;
    localparam [4:0] ST_GO_REAL     = 5'd3;
    localparam [4:0] ST_GO_REAL_WAIT= 5'd4;
    localparam [4:0] ST_GO_IMAG     = 5'd5;
    localparam [4:0] ST_GO_IMAG_WAIT= 5'd6;
    localparam [4:0] ST_RAW_CR      = 5'd7;
    localparam [4:0] ST_RAW_CR_WAIT = 5'd8;
    localparam [4:0] ST_RAW_SI      = 5'd9;
    localparam [4:0] ST_RAW_SI_WAIT = 5'd10;
    localparam [4:0] ST_RAW_SR      = 5'd11;
    localparam [4:0] ST_RAW_SR_WAIT = 5'd12;
    localparam [4:0] ST_RAW_CI      = 5'd13;
    localparam [4:0] ST_RAW_CI_WAIT = 5'd14;
    localparam [4:0] ST_OUTPUT      = 5'd16;
    localparam [4:0] ST_INPUT_READ  = 5'd17;
    localparam [4:0] ST_INPUT_WRITE = 5'd18;
    localparam [4:0] ST_RESIDUE_READ = 5'd19;

    reg [4:0] state_current;
    reg [1:0] input_member;
    reg [C_COLUMN_AW-1:0] input_column;
    reg [1:0] input_member_hold;
    reg [C_COLUMN_AW-1:0] input_column_hold;
    reg signed [15:0] input_sample_hold;
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
    reg signed [34:0] product_hold [0:C_D-1];

    // Real-input L4 symmetry requires only R0.real, R1.real, R2.real and
    // R1.imag.  R3 is the conjugate of R1; R0/R2 imaginary parts are zero.
    wire [C_COLUMN_AW-1:0] residue_read_column;
    wire signed [C_RESIDUE_STORAGE_WIDTH*4-1:0] residue_memory_read;
    wire signed [C_RESIDUE_STORAGE_WIDTH*4-1:0] residue_word_read = residue_memory_read;
    wire [1:0] input_member_selected;
    wire [C_COLUMN_AW-1:0] input_column_selected;
    wire signed [15:0] input_sample_selected;
    wire residue_write_enable;
    wire [1:0] input_next_member =
        (input_column_hold == C_COLUMNS-1) ? input_member_hold+1'b1 : input_member_hold;
    wire [C_COLUMN_AW-1:0] input_next_column =
        (input_column_hold == C_COLUMNS-1) ? {C_COLUMN_AW{1'b0}} : input_column_hold+1'b1;
    wire input_pending_final =
        (input_member_hold == 2'd3) && (input_column_hold == C_COLUMNS-1);
    assign residue_read_column =
        (state_current == ST_INPUT) ? input_column : go_column;
    assign input_member_selected = input_member;
    assign input_column_selected = input_column;
    assign input_sample_selected = i_sample;
    assign residue_write_enable = (state_current == ST_INPUT) && i_sample_valid;
    wire signed [32:0] input_sample_q15 =
        {{16{input_sample_selected[15]}},input_sample_selected,1'b0};

    wire signed [18:0] residue_bank0_value =
        {residue_word_read[17:0],1'b0};
    wire signed [18:0] residue_bank1_value =
        {residue_word_read[35:18],1'b0};
    wire signed [18:0] residue_bank2_value =
        {residue_word_read[53:36],1'b0};
    wire signed [18:0] residue_bank3_value =
        {residue_word_read[71:54],1'b0};
    wire signed [31:0] residue_bank0 =
        {{13{residue_bank0_value[18]}},residue_bank0_value};
    wire signed [31:0] residue_bank1 =
        {{13{residue_bank1_value[18]}},residue_bank1_value};
    wire signed [31:0] residue_bank2 =
        {{13{residue_bank2_value[18]}},residue_bank2_value};
    wire signed [31:0] residue_bank3 =
        {{13{residue_bank3_value[18]}},residue_bank3_value};
    wire signed [18:0] residue_bank3_negative_value = -residue_bank3_value;
    wire signed [18:0] residue_real_value [0:3];
    wire signed [18:0] residue_imag_value [0:3];
    assign residue_real_value[0] = residue_bank0_value;
    assign residue_real_value[1] = residue_bank1_value;
    assign residue_real_value[2] = residue_bank2_value;
    assign residue_real_value[3] = residue_bank1_value;
    assign residue_imag_value[0] = 19'sd0;
    assign residue_imag_value[1] = residue_bank3_value;
    assign residue_imag_value[2] = 19'sd0;
    assign residue_imag_value[3] = residue_bank3_negative_value;

    wire signed [31:0] fold_current [0:3];
    assign fold_current[0] = residue_bank0;
    assign fold_current[1] = residue_bank1;
    assign fold_current[2] = residue_bank2;
    assign fold_current[3] = residue_bank3;
    reg signed [32:0] fold_term [0:3];
    reg signed [35:0] fold_next [0:3];
    reg fold_overflow_next;
    integer fold_index;
    always @* begin
        for (fold_index = 0; fold_index < 4; fold_index = fold_index+1) begin
            fold_term[fold_index] = 33'sd0;
        end
        case (input_member_selected)
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

        fold_overflow_next = 1'b0;
        for (fold_index = 0; fold_index < 4; fold_index = fold_index+1) begin
            if (input_member_selected == 0) begin
                fold_next[fold_index] =
                    {{3{fold_term[fold_index][32]}},fold_term[fold_index]};
            end else begin
                fold_next[fold_index] =
                    $signed({{4{fold_current[fold_index][31]}},fold_current[fold_index]})+
                    $signed({{3{fold_term[fold_index][32]}},fold_term[fold_index]});
            end
            if (fold_next[fold_index][35:32] != {4{fold_next[fold_index][31]}})
                fold_overflow_next = 1'b1;
        end
    end

    wire signed [25:0] lane_cosine [0:C_D-1];
    wire signed [25:0] lane_negative_sine [0:C_D-1];
    wire signed [34:0] lane_product [0:C_D-1];
    wire signed [31:0] lane_residue_real [0:C_D-1];
    wire signed [31:0] lane_residue_imag [0:C_D-1];
    wire signed [18:0] lane_residue_real_value [0:C_D-1];
    wire signed [18:0] lane_residue_imag_value [0:C_D-1];
    wire signed [31:0] lane_neg_raw_real [0:C_D-1];
    wire signed [31:0] lane_neg_raw_imag [0:C_D-1];

    reg [C_D-1:0] multiplier_start;
    reg signed [C_D*33-1:0] multiplier_data;
    reg signed [C_D*26-1:0] multiplier_coefficient;
    wire [C_D-1:0] multiplier_busy;
    wire [C_D-1:0] multiplier_done;
    wire signed [C_D*35-1:0] multiplier_product;

    genvar generated_lane;
    generate
        for (generated_lane = 0; generated_lane < C_D; generated_lane = generated_lane+1) begin : g_lane
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
            assign lane_product[generated_lane] =
                multiplier_product[generated_lane*35 +: 35];
            if ((C_D % 4) == 0) begin : g_fixed_l4_bank
                localparam integer C_BANK = (generated_lane+1) & 3;
                assign lane_residue_real_value[generated_lane] =
                    residue_real_value[C_BANK];
                assign lane_residue_imag_value[generated_lane] =
                    residue_imag_value[C_BANK];
            end else begin : g_dynamic_l4_bank
                assign lane_residue_real_value[generated_lane] =
                    residue_real_value[lane_bin[generated_lane][1:0]];
                assign lane_residue_imag_value[generated_lane] =
                    residue_imag_value[lane_bin[generated_lane][1:0]];
            end
            assign lane_residue_real[generated_lane] =
                {{13{lane_residue_real_value[generated_lane][18]}},
                 lane_residue_real_value[generated_lane]};
            assign lane_residue_imag[generated_lane] =
                {{13{lane_residue_imag_value[generated_lane][18]}},
                 lane_residue_imag_value[generated_lane]};
            assign lane_neg_raw_real[generated_lane] = -raw_real[generated_lane];
            assign lane_neg_raw_imag[generated_lane] = -raw_imag[generated_lane];
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

    integer lane;
    always @* begin
        multiplier_start = {C_D{1'b0}};
        multiplier_data = {(C_D*33){1'b0}};
        multiplier_coefficient = {(C_D*26){1'b0}};
        for (lane = 0; lane < C_D; lane = lane+1) begin
            if (lane_active[lane]) begin
                case (state_current)
                    ST_GO_REAL: begin
                        multiplier_start[lane] = 1'b1;
                        multiplier_data[lane*33 +: 33] =
                            {state1_real[lane][31],state1_real[lane]};
                        multiplier_coefficient[lane*26 +: 26] =
                            lane_cosine[lane] <<< 1;
                    end
                    ST_GO_IMAG: begin
                        multiplier_start[lane] = 1'b1;
                        multiplier_data[lane*33 +: 33] =
                            {state1_imag[lane][31],state1_imag[lane]};
                        multiplier_coefficient[lane*26 +: 26] =
                            lane_cosine[lane] <<< 1;
                    end
                    ST_RAW_CR: begin
                        multiplier_start[lane] = 1'b1;
                        multiplier_data[lane*33 +: 33] =
                            {state1_real[lane][31],state1_real[lane]};
                        multiplier_coefficient[lane*26 +: 26] = lane_cosine[lane];
                    end
                    ST_RAW_SI: begin
                        multiplier_start[lane] = 1'b1;
                        multiplier_data[lane*33 +: 33] =
                            {state1_imag[lane][31],state1_imag[lane]};
                        multiplier_coefficient[lane*26 +: 26] = -lane_negative_sine[lane];
                    end
                    ST_RAW_SR: begin
                        multiplier_start[lane] = 1'b1;
                        multiplier_data[lane*33 +: 33] =
                            {state1_real[lane][31],state1_real[lane]};
                        multiplier_coefficient[lane*26 +: 26] = -lane_negative_sine[lane];
                    end
                    ST_RAW_CI: begin
                        multiplier_start[lane] = 1'b1;
                        multiplier_data[lane*33 +: 33] =
                            {state1_imag[lane][31],state1_imag[lane]};
                        multiplier_coefficient[lane*26 +: 26] = lane_cosine[lane];
                    end
                    default: begin end
                endcase
            end
        end
    end

    wire active_done;
    reg [C_D-1:0] active_lane_mask;
    always @* begin
        for (lane = 0; lane < C_D; lane = lane+1)
            active_lane_mask[lane] = lane_active[lane];
    end
    assign active_done = &(multiplier_done | ~active_lane_mask);

    reg signed [35:0] lane_arithmetic [0:C_D-1];
    always @* begin
        for (lane = 0; lane < C_D; lane = lane+1) begin
            lane_arithmetic[lane] = 36'sd0;
            case (state_current)
                ST_GO_REAL_WAIT: lane_arithmetic[lane] =
                    $signed({{4{lane_residue_real[lane][31]}},lane_residue_real[lane]})+
                    $signed({lane_product[lane][34],lane_product[lane]})-
                    $signed({{4{state2_real[lane][31]}},state2_real[lane]});
                ST_GO_IMAG_WAIT: lane_arithmetic[lane] =
                    $signed({{4{lane_residue_imag[lane][31]}},lane_residue_imag[lane]})+
                    $signed({lane_product[lane][34],lane_product[lane]})-
                    $signed({{4{state2_imag[lane][31]}},state2_imag[lane]});
                ST_RAW_SI_WAIT: lane_arithmetic[lane] =
                    $signed({product_hold[lane][34],product_hold[lane]})-
                    $signed({lane_product[lane][34],lane_product[lane]})-
                    $signed({{4{state2_real[lane][31]}},state2_real[lane]});
                ST_RAW_CI_WAIT: lane_arithmetic[lane] =
                    $signed({product_hold[lane][34],product_hold[lane]})+
                    $signed({lane_product[lane][34],lane_product[lane]})-
                    $signed({{4{state2_imag[lane][31]}},state2_imag[lane]});
                default: begin end
            endcase
        end
    end

    reg active_arithmetic_overflow;
    always @* begin
        active_arithmetic_overflow = 1'b0;
        for (lane = 0; lane < C_D; lane = lane+1)
            if (lane_active[lane] &&
                lane_arithmetic[lane][35:32] != {4{lane_arithmetic[lane][31]}})
                active_arithmetic_overflow = 1'b1;
    end

    assign o_sample_ready = (state_current == ST_INPUT);
    assign o_busy = state_current != ST_IDLE;
    assign o_result_valid = state_current == ST_OUTPUT;
    assign o_bin_index = lane_bin[output_lane];
    reg signed [31:0] selected_result_real;
    reg signed [31:0] selected_result_imag;
    wire [1:0] output_rotation =
        ((C_D % 4) == 0) ? ((output_lane + 1'b1) & 2'd3) :
        lane_bin[output_lane][1:0];
    always @* begin
        selected_result_real = raw_real[output_lane];
        selected_result_imag = raw_imag[output_lane];
        case (output_rotation)
            2'd0: begin end
            2'd1: begin
                selected_result_real = raw_imag[output_lane];
                selected_result_imag = lane_neg_raw_real[output_lane];
            end
            2'd2: begin
                selected_result_real = lane_neg_raw_real[output_lane];
                selected_result_imag = lane_neg_raw_imag[output_lane];
            end
            default: begin
                selected_result_real = lane_neg_raw_imag[output_lane];
                selected_result_imag = raw_real[output_lane];
            end
        endcase
    end
    assign o_result_real = selected_result_real;
    assign o_result_imag = selected_result_imag;
    assign o_result_last = o_result_valid && (lane_bin[output_lane] == C_K);
    assign o_frame_done = o_result_last && i_result_ready;
    assign o_overflow = overflow_reg;

    // ---- 残差存储器（内联；唯一的实现，无 ram_style 属性，组合读 + 同步写）----
    reg signed [C_RESIDUE_STORAGE_WIDTH*4-1:0] memory [0:C_COLUMNS-1];
    assign residue_memory_read = memory[residue_read_column];
    always @(posedge sys_clk)
        if (residue_write_enable) memory[input_column_selected] <= {fold_next[3][C_RESIDUE_VALUE_WIDTH-1:1], fold_next[2][C_RESIDUE_VALUE_WIDTH-1:1], fold_next[1][C_RESIDUE_VALUE_WIDTH-1:1], fold_next[0][C_RESIDUE_VALUE_WIDTH-1:1]};

    // Datapath and residue memories intentionally have no reset.  Each new
    // frame overwrites the banks and each bin batch initializes its state.
    always @(posedge sys_clk) begin
        if (state_current == ST_BATCH_SETUP) begin
            for (lane = 0; lane < C_D; lane = lane+1) begin
                lane_bin[lane] <= batch_first_bin+lane;
                lane_active[lane] <= (batch_first_bin+lane) <= C_K;
                state1_real[lane] <= 32'sd0;
                state1_imag[lane] <= 32'sd0;
                state2_real[lane] <= 32'sd0;
                state2_imag[lane] <= 32'sd0;
                raw_real[lane] <= 32'sd0;
                raw_imag[lane] <= 32'sd0;
                product_hold[lane] <= 35'sd0;
            end
        end

        if (state_current == ST_GO_REAL_WAIT && active_done) begin
            for (lane = 0; lane < C_D; lane = lane+1) begin
                if (lane_active[lane]) begin
                    state2_real[lane] <= state1_real[lane];
                    state1_real[lane] <= lane_arithmetic[lane][31:0];
                end
            end
        end
        if (state_current == ST_GO_IMAG_WAIT && active_done) begin
            for (lane = 0; lane < C_D; lane = lane+1) begin
                if (lane_active[lane]) begin
                    state2_imag[lane] <= state1_imag[lane];
                    state1_imag[lane] <= lane_arithmetic[lane][31:0];
                end
            end
        end
        if ((state_current == ST_RAW_CR_WAIT || state_current == ST_RAW_SR_WAIT) && active_done) begin
            for (lane = 0; lane < C_D; lane = lane+1)
                if (lane_active[lane]) product_hold[lane] <= lane_product[lane];
        end
        if (state_current == ST_RAW_SI_WAIT && active_done) begin
            for (lane = 0; lane < C_D; lane = lane+1)
                if (lane_active[lane]) raw_real[lane] <= lane_arithmetic[lane][31:0];
        end
        if (state_current == ST_RAW_CI_WAIT && active_done) begin
            for (lane = 0; lane < C_D; lane = lane+1)
                if (lane_active[lane]) raw_imag[lane] <= lane_arithmetic[lane][31:0];
        end
    end

    always @(posedge sys_clk or negedge rst_n) begin
        if (!rst_n) begin
            state_current <= ST_IDLE;
            input_member <= 2'd0;
            input_column <= {C_COLUMN_AW{1'b0}};
            input_member_hold <= 2'd0;
            input_column_hold <= {C_COLUMN_AW{1'b0}};
            input_sample_hold <= 16'sd0;
            batch_first_bin <= 9'd1;
            batch_index <= 9'd0;
            go_column <= {C_COLUMN_AW{1'b0}};
            output_lane <= {C_LANE_AW{1'b0}};
            overflow_reg <= 1'b0;
        end else begin
            case (state_current)
                ST_IDLE: begin
                    if (i_start) begin
                        input_member <= 2'd0;
                        input_column <= {C_COLUMN_AW{1'b0}};
                        overflow_reg <= 1'b0;
                        state_current <= ST_INPUT;
                    end
                end
                ST_INPUT: begin
                    if (i_sample_valid) begin
                        input_member_hold <= input_member;
                        input_column_hold <= input_column;
                        input_sample_hold <= i_sample;
                        if (fold_overflow_next) overflow_reg <= 1'b1;
                        if (input_member == 2'd3 && input_column == C_COLUMNS-1) begin
                            batch_first_bin <= 9'd1;
                            batch_index <= 9'd0;
                            state_current <= ST_BATCH_SETUP;
                        end else if (input_column == C_COLUMNS-1) begin
                            input_column <= {C_COLUMN_AW{1'b0}};
                            input_member <= input_member+1'b1;
                        end else begin
                            input_column <= input_column+1'b1;
                        end
                    end
                end
                ST_INPUT_READ: begin
                    state_current <= ST_INPUT_WRITE;
                end
                ST_INPUT_WRITE: begin
                        if (fold_overflow_next) overflow_reg <= 1'b1;
                        if (input_pending_final) begin
                            batch_first_bin <= 9'd1;
                            batch_index <= 9'd0;
                            state_current <= ST_BATCH_SETUP;
                        end else if (i_sample_valid) begin
                            input_member_hold <= input_next_member;
                            input_column_hold <= input_next_column;
                            input_sample_hold <= i_sample;
                            input_column <= input_next_column;
                            input_member <= input_next_member;
                            state_current <= ST_INPUT_WRITE;
                        end else begin
                            input_column <= input_next_column;
                            input_member <= input_next_member;
                            state_current <= ST_INPUT;
                        end
                end
                ST_BATCH_SETUP: begin
                    go_column <= {C_COLUMN_AW{1'b0}};
                    output_lane <= {C_LANE_AW{1'b0}};
                    // The block RAM read for column zero is issued during
                    // this setup cycle; its registered output is consumed
                    // directly by ST_GO_REAL on the following cycle.
                    state_current <= ST_GO_REAL;
                end
                ST_RESIDUE_READ: state_current <= ST_GO_REAL;
                ST_GO_REAL: state_current <= ST_GO_REAL_WAIT;
                ST_GO_REAL_WAIT: begin
                    if (active_done) begin
                        if (active_arithmetic_overflow) overflow_reg <= 1'b1;
                        state_current <= ST_GO_IMAG;
                    end
                end
                ST_GO_IMAG: state_current <= ST_GO_IMAG_WAIT;
                ST_GO_IMAG_WAIT: begin
                    if (active_done) begin
                        if (active_arithmetic_overflow) overflow_reg <= 1'b1;
                        if (go_column == C_COLUMNS-1) begin
                            state_current <= ST_RAW_CR;
                        end else begin
                            go_column <= go_column+1'b1;
                            // The next residue column was prefetched while
                            // this column's imaginary recurrence completed.
                            state_current <= ST_GO_REAL;
                        end
                    end
                end
                ST_RAW_CR: state_current <= ST_RAW_CR_WAIT;
                ST_RAW_CR_WAIT: if (active_done) state_current <= ST_RAW_SI;
                ST_RAW_SI: state_current <= ST_RAW_SI_WAIT;
                ST_RAW_SI_WAIT: begin
                    if (active_done) begin
                        if (active_arithmetic_overflow) overflow_reg <= 1'b1;
                        state_current <= ST_RAW_SR;
                    end
                end
                ST_RAW_SR: state_current <= ST_RAW_SR_WAIT;
                ST_RAW_SR_WAIT: if (active_done) state_current <= ST_RAW_CI;
                ST_RAW_CI: state_current <= ST_RAW_CI_WAIT;
                ST_RAW_CI_WAIT: begin
                    if (active_done) begin
                        if (active_arithmetic_overflow) overflow_reg <= 1'b1;
                        for (lane = 0; lane < C_D; lane = lane+1) begin
                            if (lane_active[lane] &&
                                ((lane_bin[lane][1:0] == 2'd1 && raw_real[lane] == 32'sh80000000) ||
                                 (lane_bin[lane][1:0] == 2'd2 &&
                                  (raw_real[lane] == 32'sh80000000 ||
                                   lane_arithmetic[lane][31:0] == 32'sh80000000)) ||
                                 (lane_bin[lane][1:0] == 2'd3 &&
                                  lane_arithmetic[lane][31:0] == 32'sh80000000)))
                                overflow_reg <= 1'b1;
                        end
                        output_lane <= {C_LANE_AW{1'b0}};
                        state_current <= ST_OUTPUT;
                    end
                end
                ST_OUTPUT: begin
                    if (i_result_ready) begin
                        if (lane_bin[output_lane] == C_K) begin
                            state_current <= ST_IDLE;
                        end else if (output_lane == C_D-1) begin
                            batch_first_bin <= batch_first_bin+C_D;
                            batch_index <= batch_index+1'b1;
                            state_current <= ST_BATCH_SETUP;
                        end else if (!lane_active[output_lane+1'b1]) begin
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
        if (!(C_D == 1 || C_D == 2 || C_D == 4 || C_D == 8))
            $error("C_D must be 1, 2, 4, or 8");
    end
`endif
endmodule
