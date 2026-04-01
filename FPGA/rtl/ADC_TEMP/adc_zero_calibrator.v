`timescale 1ns / 1ps

module adc_zero_calibrator #(
    parameter integer WIDTH             = 8,
    parameter integer CAL_SHIFT         = 10,
    parameter integer ZERO_CODE_DEFAULT = (1 << (WIDTH - 1)) - 1,
    parameter integer ACCEPT_TOLERANCE  = (1 << (WIDTH - 3))
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire [WIDTH-1:0] ad_data,
    output reg              zero_code_valid,
    output reg [WIDTH-1:0]  zero_code
);

localparam integer CAL_SAMPLE_COUNT = (1 << CAL_SHIFT);
localparam integer CAL_COUNT_MAX    = (CAL_SAMPLE_COUNT << 1) - 1;
localparam integer ROUND_BIAS       = (CAL_SHIFT > 0) ? (1 << (CAL_SHIFT - 1)) : 0;
localparam integer SUM_WIDTH        = WIDTH + CAL_SHIFT + 1;
localparam integer AVG_MSB          = CAL_SHIFT + WIDTH - 1;
localparam integer ZERO_MIN_CODE    = (ZERO_CODE_DEFAULT > ACCEPT_TOLERANCE) ?
                                      (ZERO_CODE_DEFAULT - ACCEPT_TOLERANCE) : 0;
localparam integer ZERO_MAX_CODE    = ZERO_CODE_DEFAULT + ACCEPT_TOLERANCE;

reg [CAL_SHIFT:0]   cal_cnt;
reg [SUM_WIDTH-1:0] sum_acc;

wire [SUM_WIDTH-1:0] sample_ext;
wire [SUM_WIDTH-1:0] window_sum;
wire [SUM_WIDTH-1:0] rounded_sum;

assign sample_ext  = {{(SUM_WIDTH - WIDTH){1'b0}}, ad_data};
assign window_sum  = sum_acc + sample_ext;
assign rounded_sum = window_sum + ROUND_BIAS;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        cal_cnt          <= {(CAL_SHIFT + 1){1'b0}};
        sum_acc          <= {SUM_WIDTH{1'b0}};
        zero_code_valid  <= 1'b0;
        zero_code        <= ZERO_CODE_DEFAULT[WIDTH-1:0];
    end else if (!zero_code_valid) begin
        if (cal_cnt == CAL_COUNT_MAX[CAL_SHIFT:0]) begin
            if ((rounded_sum[AVG_MSB:CAL_SHIFT] >= ZERO_MIN_CODE[WIDTH-1:0]) &&
                (rounded_sum[AVG_MSB:CAL_SHIFT] <= ZERO_MAX_CODE[WIDTH-1:0]))
                zero_code <= rounded_sum[AVG_MSB:CAL_SHIFT];
            else
                zero_code <= ZERO_CODE_DEFAULT[WIDTH-1:0];
            zero_code_valid <= 1'b1;
        end else begin
            cal_cnt <= cal_cnt + 1'b1;
            if (cal_cnt >= CAL_SAMPLE_COUNT - 1)
                sum_acc <= window_sum;
        end
    end
end

endmodule
