`timescale 1ns / 1ps

/*
 * Module: signal_rms_calc
 * Function:
 *   Calculate the RMS value of the raw ADC waveform over a fixed window.
 *   The module uses an externally tracked waveform center code to remove
 *   the DC offset, accumulates the squared magnitude, divides by the
 *   window length and finally converts the RMS code into XX.XX-style
 *   display digits.
 */
module signal_rms_calc #(
    parameter integer WIDTH             = 8,
    parameter integer FULL_SCALE_MV     = 5000,
    parameter integer WINDOW_SAMPLES    = 1_000_000
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire [WIDTH-1:0] sample_code,
    input  wire [WIDTH-1:0] center_code,
    output wire [7:0]       rms_tens,
    output wire [7:0]       rms_units,
    output wire [7:0]       rms_decile,
    output wire [7:0]       rms_percentiles,
    output wire             rms_digits_valid
);

localparam integer COUNT_W = (WINDOW_SAMPLES <= 2) ? 2 : $clog2(WINDOW_SAMPLES);
localparam integer SUM_W   = 40;
localparam [SUM_W-1:0] WINDOW_SAMPLES_EXT = WINDOW_SAMPLES;

reg  [COUNT_W-1:0] sample_cnt;
reg  [SUM_W-1:0]   sum_sq_acc;
reg  [SUM_W-1:0]   sum_sq_latched;
reg                mean_div_start;
reg                mean_div_pending;
reg                mean_div_active;
reg  [31:0]        rms_mv;
reg                rms_mv_valid;

wire [WIDTH-1:0] abs_delta;
wire [15:0]      delta_square;
wire [SUM_W-1:0] sum_sq_next;
wire             mean_div_busy;
wire             mean_div_done;
wire             mean_div_zero;
wire [SUM_W-1:0] mean_square_q;
wire [7:0]       rms_code_calc;
wire [31:0]      rms_mv_next;
wire             rms_symbol_unused;

assign abs_delta     = (sample_code >= center_code) ? (sample_code - center_code) :
                                                    (center_code - sample_code);
assign delta_square  = abs_delta * abs_delta;
assign sum_sq_next   = sum_sq_acc + {{(SUM_W - 16){1'b0}}, delta_square};
assign rms_code_calc = isqrt16(mean_square_q[15:0]);
assign rms_mv_next   = (({24'd0, rms_code_calc} * FULL_SCALE_MV) + 32'd64) >> 7;

divider_unsigned #(
    .WIDTH(SUM_W)
) u_mean_square_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (mean_div_start),
    .dividend      (sum_sq_latched),
    .divisor       (WINDOW_SAMPLES_EXT),
    .busy          (mean_div_busy),
    .done          (mean_div_done),
    .divide_by_zero(mean_div_zero),
    .quotient      (mean_square_q)
);

adc_voltage_digits u_rms_digits (
    .clk             (clk),
    .rst_n           (rst_n),
    .voltage_mv      (rms_mv),
    .voltage_valid   (rms_mv_valid),
    .over_range      (1'b0),
    .data_symbol_in  (1'b0),
    .data_symbol     (rms_symbol_unused),
    .data_tens       (rms_tens),
    .data_units      (rms_units),
    .data_decile     (rms_decile),
    .data_percentiles(rms_percentiles),
    .digits_valid    (rms_digits_valid)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sample_cnt        <= {COUNT_W{1'b0}};
        sum_sq_acc        <= {SUM_W{1'b0}};
        sum_sq_latched    <= {SUM_W{1'b0}};
        mean_div_start    <= 1'b0;
        mean_div_pending  <= 1'b0;
        mean_div_active   <= 1'b0;
        rms_mv            <= 32'd0;
        rms_mv_valid      <= 1'b0;
    end else begin
        mean_div_start <= 1'b0;
        rms_mv_valid   <= 1'b0;

        if (mean_div_pending) begin
            mean_div_start   <= 1'b1;
            mean_div_pending <= 1'b0;
        end else if (!mean_div_active) begin
            if (sample_cnt == WINDOW_SAMPLES - 1) begin
                sample_cnt       <= {COUNT_W{1'b0}};
                sum_sq_acc       <= {SUM_W{1'b0}};
                sum_sq_latched   <= sum_sq_next;
                mean_div_pending <= 1'b1;
                mean_div_active  <= 1'b1;
            end else begin
                sample_cnt <= sample_cnt + {{(COUNT_W - 1){1'b0}}, 1'b1};
                sum_sq_acc <= sum_sq_next;
            end
        end else if (mean_div_done) begin
            mean_div_active <= 1'b0;
            rms_mv          <= mean_div_zero ? 32'd0 : rms_mv_next;
            rms_mv_valid    <= 1'b1;
        end
    end
end

function [7:0] isqrt16;
    input [15:0] radicand;
    integer bit_idx;
    reg [7:0] candidate;
    reg [15:0] candidate_sq;
    begin
        isqrt16 = 8'd0;
        for (bit_idx = 7; bit_idx >= 0; bit_idx = bit_idx - 1) begin
            candidate    = isqrt16 | (8'd1 << bit_idx);
            candidate_sq = candidate * candidate;
            if (candidate_sq <= radicand)
                isqrt16 = candidate;
        end
    end
endfunction

endmodule
