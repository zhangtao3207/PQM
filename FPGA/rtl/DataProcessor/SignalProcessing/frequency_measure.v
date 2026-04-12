`timescale 1ns / 1ps

module frequency_measure #(
    parameter integer WIDTH             = 16,
    parameter integer MAX_FRAME_SAMPLES = 4096,
    parameter integer N_WIDTH           = (MAX_FRAME_SAMPLES <= 2) ? 2 : $clog2(MAX_FRAME_SAMPLES),
    parameter [39:0]  CLK_FREQ_X100     = 40'd5000000000
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire             start,
    input  wire [N_WIDTH-1:0] sample_count_n,
    input  wire             sample_valid,
    input  wire [WIDTH-1:0] sample_code,
    input  wire [WIDTH-1:0] zero_code,
    input  wire             zero_valid,

    output reg              busy,
    output reg              done,
    output reg  [7:0]       freq_hundreds,
    output reg  [7:0]       freq_tens,
    output reg  [7:0]       freq_units,
    output reg  [7:0]       freq_decile,
    output reg  [7:0]       freq_percentiles,
    output reg              freq_valid
);

localparam [2:0] ST_IDLE      = 3'd0;
localparam [2:0] ST_CAPTURE   = 3'd1;
localparam [2:0] ST_DIV_START = 3'd2;
localparam [2:0] ST_DIV_WAIT  = 3'd3;
localparam [2:0] ST_COMMIT    = 3'd4;

localparam [WIDTH-1:0] CENTER_DEFAULT = {1'b1, {(WIDTH - 1){1'b0}}};
localparam integer     FREQ_HYST_INT  = (WIDTH >= 8) ? (2 << (WIDTH - 8)) : 2;
localparam [WIDTH-1:0] FREQ_HYST      = FREQ_HYST_INT;
localparam [31:0]      VALUE_CLIP_X100 = 32'd99999;

reg  [2:0]            state;
reg  [N_WIDTH-1:0]    sample_target;
reg  [N_WIDTH-1:0]    sample_count;
reg  [31:0]           period_clk_cnt;
reg  [31:0]           period_clk_latched;
reg                   trigger_armed;
reg                   first_cross_seen;
reg                   freq_div_start;
reg                   freq_valid_next;
reg  [31:0]           freq_x100_reg;
reg  [31:0]           freq_digit_value;
reg  [7:0]            freq_hundreds_calc;
reg                   cross_now;
integer               digit_idx;

wire [WIDTH-1:0]      ref_code;
wire [WIDTH-1:0]      code_low;
wire [WIDTH-1:0]      code_high;
wire                  freq_div_done;
wire                  freq_div_zero;
wire [63:0]           freq_div_quotient;
wire [7:0]            freq_tens_calc;
wire [7:0]            freq_units_calc;
wire [7:0]            freq_decile_calc;
wire [7:0]            freq_percentiles_calc;

assign ref_code = zero_valid ? zero_code : CENTER_DEFAULT;
assign code_low  = (ref_code > FREQ_HYST) ? (ref_code - FREQ_HYST) : {WIDTH{1'b0}};
assign code_high = (ref_code < ({WIDTH{1'b1}} - FREQ_HYST)) ? (ref_code + FREQ_HYST) : {WIDTH{1'b1}};

divider_unsigned #(
    .WIDTH(64)
) u_frequency_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (freq_div_start),
    .dividend      ({24'd0, CLK_FREQ_X100} + {32'd0, period_clk_latched[31:1]}),
    .divisor       ({32'd0, period_clk_latched}),
    .busy          (),
    .done          (freq_div_done),
    .divide_by_zero(freq_div_zero),
    .quotient      (freq_div_quotient)
);

always @(*) begin
    freq_digit_value   = freq_x100_reg;
    freq_hundreds_calc = 8'd0;

    for (digit_idx = 0; digit_idx < 10; digit_idx = digit_idx + 1) begin
        if (freq_digit_value >= 32'd10000) begin
            freq_digit_value   = freq_digit_value - 32'd10000;
            freq_hundreds_calc = freq_hundreds_calc + 8'd1;
        end
    end
end

value_x100_to_digits u_frequency_digits (
    .value_x100  (freq_digit_value),
    .tens        (freq_tens_calc),
    .units       (freq_units_calc),
    .decile      (freq_decile_calc),
    .percentiles (freq_percentiles_calc)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state            <= ST_IDLE;
        sample_target    <= {N_WIDTH{1'b0}};
        sample_count     <= {N_WIDTH{1'b0}};
        period_clk_cnt   <= 32'd0;
        period_clk_latched<= 32'd0;
        trigger_armed    <= 1'b0;
        first_cross_seen <= 1'b0;
        freq_div_start   <= 1'b0;
        freq_valid_next  <= 1'b0;
        freq_x100_reg    <= 32'd0;
        busy             <= 1'b0;
        done             <= 1'b0;
        freq_hundreds    <= 8'd0;
        freq_tens        <= 8'd0;
        freq_units       <= 8'd0;
        freq_decile      <= 8'd0;
        freq_percentiles <= 8'd0;
        freq_valid       <= 1'b0;
    end else begin
        done           <= 1'b0;
        freq_div_start <= 1'b0;

        case (state)
            ST_IDLE: begin
                busy <= 1'b0;

                if (start) begin
                    sample_target     <= sample_count_n;
                    sample_count      <= {N_WIDTH{1'b0}};
                    period_clk_cnt    <= 32'd0;
                    period_clk_latched<= 32'd0;
                    trigger_armed     <= 1'b0;
                    first_cross_seen  <= 1'b0;
                    freq_valid_next   <= 1'b0;
                    freq_x100_reg     <= 32'd0;
                    freq_valid        <= 1'b0;

                    if (sample_count_n == {N_WIDTH{1'b0}}) begin
                        done  <= 1'b1;
                        state <= ST_IDLE;
                    end else begin
                        busy  <= 1'b1;
                        state <= ST_CAPTURE;
                    end
                end
            end

            ST_CAPTURE: begin
                if (period_clk_cnt != 32'hFFFF_FFFF)
                    period_clk_cnt <= period_clk_cnt + 32'd1;

                if (sample_valid) begin
                    cross_now = 1'b0;

                    if (sample_code <= code_low)
                        trigger_armed <= 1'b1;
                    else if (trigger_armed && (sample_code >= code_high)) begin
                        cross_now     = 1'b1;
                        trigger_armed <= 1'b0;
                    end

                    if (cross_now) begin
                        if (!first_cross_seen) begin
                            first_cross_seen <= 1'b1;
                            period_clk_cnt   <= 32'd0;
                        end else begin
                            period_clk_latched <= period_clk_cnt;
                            state             <= ST_DIV_START;
                        end
                    end

                    if (sample_count == (sample_target - 1'b1)) begin
                        if (!cross_now || !first_cross_seen) begin
                            busy       <= 1'b0;
                            done       <= 1'b1;
                            freq_valid <= 1'b0;
                            state      <= ST_IDLE;
                        end
                        sample_count <= {N_WIDTH{1'b0}};
                    end else begin
                        sample_count <= sample_count + {{(N_WIDTH - 1){1'b0}}, 1'b1};
                    end
                end
            end

            ST_DIV_START: begin
                freq_div_start <= 1'b1;
                state          <= ST_DIV_WAIT;
            end

            ST_DIV_WAIT: begin
                if (freq_div_done) begin
                    if (freq_div_zero) begin
                        freq_x100_reg   <= 32'd0;
                        freq_valid_next <= 1'b0;
                    end else if ((freq_div_quotient[63:32] != 32'd0) ||
                                 (freq_div_quotient[31:0] > VALUE_CLIP_X100)) begin
                        freq_x100_reg   <= VALUE_CLIP_X100;
                        freq_valid_next <= 1'b1;
                    end else begin
                        freq_x100_reg   <= freq_div_quotient[31:0];
                        freq_valid_next <= 1'b1;
                    end
                    state <= ST_COMMIT;
                end
            end

            ST_COMMIT: begin
                freq_hundreds    <= freq_hundreds_calc;
                freq_tens        <= freq_tens_calc;
                freq_units       <= freq_units_calc;
                freq_decile      <= freq_decile_calc;
                freq_percentiles <= freq_percentiles_calc;
                freq_valid       <= freq_valid_next;
                busy             <= 1'b0;
                done             <= 1'b1;
                state            <= ST_IDLE;
            end

            default: begin
                busy  <= 1'b0;
                done  <= 1'b0;
                state <= ST_IDLE;
            end
        endcase
    end
end

endmodule
