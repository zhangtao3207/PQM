`timescale 1ns / 1ps

module adc_abs_voltage_calc #(
    parameter integer WIDTH         = 8,
    parameter integer FULL_SCALE_MV = 5000,
    parameter integer ZERO_CODE_DEFAULT = (1 << (WIDTH - 1)) - 1
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire [WIDTH-1:0]  avg_code,
    input  wire              avg_valid,
    input  wire              over_range_in,
    input  wire [WIDTH-1:0]  zero_code,
    input  wire              zero_code_valid,
    output reg  [31:0]       voltage_mv,
    output reg               voltage_valid,
    output reg               over_range_out,
    output reg               data_symbol
);

localparam integer ADC_CODE_SPAN = (1 << WIDTH);
localparam integer PRODUCT_WIDTH = WIDTH + 16;
localparam [WIDTH-1:0] ZERO_CODE_FALLBACK = ZERO_CODE_DEFAULT[WIDTH-1:0];

reg [WIDTH-1:0]         abs_delta_d0;
reg [WIDTH:0]           span_code_d0;
reg                     negative_d0;
reg                     avg_valid_d0;
reg                     over_range_d0;
reg [PRODUCT_WIDTH-1:0] scaled_product_d1;
reg [WIDTH:0]           span_code_d1;
reg                     negative_d1;
reg                     avg_valid_d1;
reg                     over_range_d1;

wire [WIDTH-1:0] zero_code_eff;

assign zero_code_eff = zero_code_valid ? zero_code : ZERO_CODE_FALLBACK;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        abs_delta_d0      <= {WIDTH{1'b0}};
        span_code_d0      <= {(WIDTH + 1){1'b0}};
        negative_d0       <= 1'b0;
        avg_valid_d0      <= 1'b0;
        over_range_d0     <= 1'b0;
        scaled_product_d1 <= {PRODUCT_WIDTH{1'b0}};
        span_code_d1      <= {(WIDTH + 1){1'b0}};
        negative_d1       <= 1'b0;
        avg_valid_d1      <= 1'b0;
        over_range_d1     <= 1'b0;
        voltage_mv        <= 32'd0;
        voltage_valid     <= 1'b0;
        over_range_out    <= 1'b0;
        data_symbol       <= 1'b0;
    end else begin
        avg_valid_d0  <= avg_valid;
        over_range_d0 <= over_range_in;
        if (avg_valid) begin
            if (avg_code >= zero_code_eff) begin
                abs_delta_d0 <= avg_code - zero_code_eff;
                span_code_d0 <= ADC_CODE_SPAN - zero_code_eff;
                negative_d0  <= 1'b0;
            end else begin
                abs_delta_d0 <= zero_code_eff - avg_code;
                span_code_d0 <= zero_code_eff + 1'b1;
                negative_d0  <= 1'b1;
            end
        end

        avg_valid_d1  <= avg_valid_d0;
        over_range_d1 <= over_range_d0;
        span_code_d1  <= span_code_d0;
        negative_d1   <= negative_d0;

        if (avg_valid_d0)
            scaled_product_d1 <= abs_delta_d0 * FULL_SCALE_MV;

        voltage_valid  <= avg_valid_d1;
        over_range_out <= over_range_d1;

        if (avg_valid_d1) begin
            if (over_range_d1) begin
                voltage_mv <= FULL_SCALE_MV;
                data_symbol <= 1'b0;
            end else if (span_code_d1 == {(WIDTH + 1){1'b0}}) begin
                voltage_mv <= 32'd0;
                data_symbol <= 1'b0;
            end else begin
                voltage_mv  <= (scaled_product_d1 + (span_code_d1 >> 1)) / span_code_d1;
                data_symbol <= negative_d1;
            end
        end
    end
end

endmodule
