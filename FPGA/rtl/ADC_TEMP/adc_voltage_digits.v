`timescale 1ns / 1ps

module adc_voltage_digits(
    input  wire         clk,
    input  wire         rst_n,
    input  wire [31:0]  voltage_mv,
    input  wire         voltage_valid,
    input  wire         over_range,
    input  wire         data_symbol_in,
    output reg          data_symbol,
    output reg  [7:0]   data_tens,
    output reg  [7:0]   data_units,
    output reg  [7:0]   data_decile,
    output reg  [7:0]   data_percentiles,
    output reg          digits_valid
);

reg        valid_d0;
reg        valid_d1;
reg        valid_d2;
reg        over_range_d0;
reg        over_range_d1;
reg        symbol_d0;
reg        symbol_d1;
reg [31:0] display_mv_d0;
reg [31:0] display_mv_d1;
reg [15:0] whole_v_d1;
reg [15:0] frac_mv_d1;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        valid_d0          <= 1'b0;
        valid_d1          <= 1'b0;
        valid_d2          <= 1'b0;
        over_range_d0     <= 1'b0;
        over_range_d1     <= 1'b0;
        symbol_d0         <= 1'b0;
        symbol_d1         <= 1'b0;
        display_mv_d0     <= 32'd0;
        display_mv_d1     <= 32'd0;
        whole_v_d1        <= 16'd0;
        frac_mv_d1        <= 16'd0;
        data_symbol       <= 1'b0;
        data_tens         <= 8'd0;
        data_units        <= 8'd0;
        data_decile       <= 8'd0;
        data_percentiles  <= 8'd0;
        digits_valid      <= 1'b0;
    end else begin
        valid_d0      <= voltage_valid;
        over_range_d0 <= over_range;
        symbol_d0     <= data_symbol_in;
        if (voltage_valid)
            display_mv_d0 <= voltage_mv + 32'd5;

        valid_d1      <= valid_d0;
        over_range_d1 <= over_range_d0;
        symbol_d1     <= symbol_d0;
        display_mv_d1 <= display_mv_d0;
        if (valid_d0) begin
            whole_v_d1 <= display_mv_d0 / 1000;
            frac_mv_d1 <= display_mv_d0 % 1000;
        end

        valid_d2      <= valid_d1;
        digits_valid  <= valid_d2;

        if (valid_d1) begin
            if (over_range_d1 || (display_mv_d1 > 32'd99990)) begin
                data_symbol      <= 1'b0;
                data_tens        <= 8'd9;
                data_units       <= 8'd9;
                data_decile      <= 8'd9;
                data_percentiles <= 8'd9;
            end else begin
                data_symbol      <= symbol_d1;
                data_tens        <= whole_v_d1 / 10;
                data_units       <= whole_v_d1 % 10;
                data_decile      <= frac_mv_d1 / 100;
                data_percentiles <= (frac_mv_d1 % 100) / 10;
            end
        end
    end
end

endmodule
