`timescale 1ns / 1ps

module p2p_measure #(
    parameter integer WIDTH             = 16,
    parameter integer MAX_FRAME_SAMPLES = 4096,
    parameter integer N_WIDTH           = (MAX_FRAME_SAMPLES <= 2) ? 2 : $clog2(MAX_FRAME_SAMPLES),
    parameter integer FULL_SCALE_X100   = 1000
)(
    input  wire               clk,
    input  wire               rst_n,
    input  wire               start,
    input  wire [N_WIDTH-1:0] sample_count_n,
    input  wire               sample_valid,
    input  wire [WIDTH-1:0]   sample_code,
    output reg                busy,
    output reg                done,
    output reg  [7:0]         p2p_tens,
    output reg  [7:0]         p2p_units,
    output reg  [7:0]         p2p_decile,
    output reg  [7:0]         p2p_percentiles,
    output reg                p2p_digits_valid
);

localparam [2:0] ST_IDLE      = 3'd0;
localparam [2:0] ST_CAPTURE   = 3'd1;
localparam [2:0] ST_DIV_START = 3'd2;
localparam [2:0] ST_DIV_WAIT  = 3'd3;
localparam [2:0] ST_COMMIT    = 3'd4;

localparam [31:0] HALF_SCALE_CODE = 32'd1 << (WIDTH - 1);
localparam [31:0] ROUND_BIAS      = HALF_SCALE_CODE >> 1;
localparam [31:0] VALUE_CLIP_X100 = 32'd9999;

reg  [2:0]          state;
reg  [N_WIDTH-1:0]  sample_target;
reg  [N_WIDTH-1:0]  sample_count;
reg  [WIDTH-1:0]    min_code;
reg  [WIDTH-1:0]    max_code;
reg                 seen_sample;
reg                 p2p_div_start;
reg                 p2p_valid_next;
reg  [31:0]         p2p_x100_reg;

wire [WIDTH:0]      p2p_diff_unsigned;
wire signed [63:0]  p2p_scale_product_signed;
wire [63:0]         p2p_scale_product_unsigned;
wire                p2p_div_done;
wire                p2p_div_zero;
wire [63:0]         p2p_div_quotient;
wire [7:0]          p2p_tens_wire;
wire [7:0]          p2p_units_wire;
wire [7:0]          p2p_decile_wire;
wire [7:0]          p2p_percentiles_wire;

assign p2p_diff_unsigned = {1'b0, max_code} - {1'b0, min_code};
assign p2p_scale_product_unsigned = p2p_scale_product_signed[63] ? 64'd0 : p2p_scale_product_signed[63:0];

multiplier_signed #(
    .A_WIDTH(32),
    .B_WIDTH(32)
) u_p2p_scale_multiplier (
    .multiplicand({{(32 - (WIDTH + 1)){1'b0}}, p2p_diff_unsigned}),
    .multiplier  (FULL_SCALE_X100),
    .product     (p2p_scale_product_signed)
);

divider_unsigned #(
    .WIDTH(64)
) u_p2p_divider (
    .clk           (clk),
    .rst_n         (rst_n),
    .start         (p2p_div_start),
    .dividend      (p2p_scale_product_unsigned + {32'd0, ROUND_BIAS}),
    .divisor       ({32'd0, HALF_SCALE_CODE}),
    .busy          (),
    .done          (p2p_div_done),
    .divide_by_zero(p2p_div_zero),
    .quotient      (p2p_div_quotient)
);

value_x100_to_digits u_p2p_digits (
    .value_x100  (p2p_x100_reg),
    .tens        (p2p_tens_wire),
    .units       (p2p_units_wire),
    .decile      (p2p_decile_wire),
    .percentiles (p2p_percentiles_wire)
);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state            <= ST_IDLE;
        sample_target    <= {N_WIDTH{1'b0}};
        sample_count     <= {N_WIDTH{1'b0}};
        min_code         <= {WIDTH{1'b1}};
        max_code         <= {WIDTH{1'b0}};
        seen_sample      <= 1'b0;
        p2p_div_start    <= 1'b0;
        p2p_valid_next   <= 1'b0;
        p2p_x100_reg     <= 32'd0;
        busy             <= 1'b0;
        done             <= 1'b0;
        p2p_tens         <= 8'd0;
        p2p_units        <= 8'd0;
        p2p_decile       <= 8'd0;
        p2p_percentiles  <= 8'd0;
        p2p_digits_valid <= 1'b0;
    end else begin
        done          <= 1'b0;
        p2p_div_start <= 1'b0;

        case (state)
            ST_IDLE: begin
                busy <= 1'b0;

                if (start) begin
                    sample_target    <= sample_count_n;
                    sample_count     <= {N_WIDTH{1'b0}};
                    min_code         <= {WIDTH{1'b1}};
                    max_code         <= {WIDTH{1'b0}};
                    seen_sample      <= 1'b0;
                    p2p_valid_next   <= 1'b0;
                    p2p_x100_reg     <= 32'd0;
                    p2p_digits_valid <= 1'b0;

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
                if (sample_valid) begin
                    if (!seen_sample) begin
                        min_code    <= sample_code;
                        max_code    <= sample_code;
                        seen_sample <= 1'b1;
                    end else begin
                        if (sample_code < min_code)
                            min_code <= sample_code;
                        if (sample_code > max_code)
                            max_code <= sample_code;
                    end

                    if (sample_count == (sample_target - 1'b1)) begin
                        if (seen_sample || (sample_count_n != {N_WIDTH{1'b0}}))
                            state <= ST_DIV_START;
                        else begin
                            busy             <= 1'b0;
                            done             <= 1'b1;
                            p2p_digits_valid <= 1'b0;
                            state            <= ST_IDLE;
                        end
                        sample_count <= {N_WIDTH{1'b0}};
                    end else begin
                        sample_count <= sample_count + {{(N_WIDTH - 1){1'b0}}, 1'b1};
                    end
                end
            end

            ST_DIV_START: begin
                p2p_div_start <= 1'b1;
                state         <= ST_DIV_WAIT;
            end

            ST_DIV_WAIT: begin
                if (p2p_div_done) begin
                    if (p2p_div_zero) begin
                        p2p_x100_reg   <= 32'd0;
                        p2p_valid_next <= 1'b0;
                    end else if ((p2p_div_quotient[63:32] != 32'd0) ||
                                 (p2p_div_quotient[31:0] > VALUE_CLIP_X100)) begin
                        p2p_x100_reg   <= VALUE_CLIP_X100;
                        p2p_valid_next <= 1'b1;
                    end else begin
                        p2p_x100_reg   <= p2p_div_quotient[31:0];
                        p2p_valid_next <= 1'b1;
                    end
                    state <= ST_COMMIT;
                end
            end

            ST_COMMIT: begin
                p2p_tens         <= p2p_tens_wire;
                p2p_units        <= p2p_units_wire;
                p2p_decile       <= p2p_decile_wire;
                p2p_percentiles  <= p2p_percentiles_wire;
                p2p_digits_valid <= p2p_valid_next;
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
