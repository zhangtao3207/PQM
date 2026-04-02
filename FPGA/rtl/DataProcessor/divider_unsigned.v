`timescale 1ns / 1ps

/*
 * Module: divider_unsigned
 * Function:
 *   Parameterized unsigned divider based on the restoring-division algorithm.
 *   The module avoids the "/" operator and returns the quotient after WIDTH
 *   clock cycles. "done" is a one-cycle pulse.
 */
module divider_unsigned #(
    parameter integer WIDTH = 16
)(
    input  wire                 clk,
    input  wire                 rst_n,
    input  wire                 start,
    input  wire [WIDTH-1:0]     dividend,
    input  wire [WIDTH-1:0]     divisor,
    output reg                  busy,
    output reg                  done,
    output reg                  divide_by_zero,
    output reg  [WIDTH-1:0]     quotient
);

localparam integer COUNT_W = (WIDTH <= 2) ? 2 : $clog2(WIDTH + 1);

reg [WIDTH-1:0] divisor_reg;
reg [WIDTH-1:0] quotient_reg;
reg [WIDTH:0]   remainder_reg;
reg [COUNT_W-1:0] bit_count;

reg [WIDTH:0]   remainder_shift;
reg [WIDTH:0]   remainder_next;
reg [WIDTH-1:0] quotient_next;

always @(*) begin
    remainder_shift = {remainder_reg[WIDTH-1:0], quotient_reg[WIDTH-1]};

    if (remainder_shift >= {1'b0, divisor_reg}) begin
        remainder_next = remainder_shift - {1'b0, divisor_reg};
        quotient_next  = {quotient_reg[WIDTH-2:0], 1'b1};
    end else begin
        remainder_next = remainder_shift;
        quotient_next  = {quotient_reg[WIDTH-2:0], 1'b0};
    end
end

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        busy           <= 1'b0;
        done           <= 1'b0;
        divide_by_zero <= 1'b0;
        quotient       <= {WIDTH{1'b0}};
        divisor_reg    <= {WIDTH{1'b0}};
        quotient_reg   <= {WIDTH{1'b0}};
        remainder_reg  <= {(WIDTH + 1){1'b0}};
        bit_count      <= {COUNT_W{1'b0}};
    end else begin
        done <= 1'b0;

        if (start && !busy) begin
            if (divisor == {WIDTH{1'b0}}) begin
                busy           <= 1'b0;
                done           <= 1'b1;
                divide_by_zero <= 1'b1;
                quotient       <= {WIDTH{1'b0}};
            end else begin
                busy           <= 1'b1;
                divide_by_zero <= 1'b0;
                divisor_reg    <= divisor;
                quotient_reg   <= dividend;
                remainder_reg  <= {(WIDTH + 1){1'b0}};
                bit_count      <= WIDTH;
            end
        end else if (busy) begin
            quotient_reg  <= quotient_next;
            remainder_reg <= remainder_next;

            if (bit_count == {{(COUNT_W-1){1'b0}}, 1'b1}) begin
                busy     <= 1'b0;
                done     <= 1'b1;
                quotient <= quotient_next;
                bit_count <= {COUNT_W{1'b0}};
            end else begin
                bit_count <= bit_count - {{(COUNT_W-1){1'b0}}, 1'b1};
            end
        end
    end
end

endmodule
