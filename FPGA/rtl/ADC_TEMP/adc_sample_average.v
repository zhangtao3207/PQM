`timescale 1ns / 1ps

module adc_sample_average #(
    parameter integer WIDTH         = 8,
    parameter integer AVERAGE_SHIFT = 6
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire [WIDTH-1:0]  ad_data,
    input  wire              ad_otr,
    output reg  [WIDTH-1:0]  avg_code,
    output reg               avg_valid,
    output reg               over_range
);

localparam integer SAMPLE_COUNT = (1 << AVERAGE_SHIFT);
localparam integer ROUND_BIAS   = (AVERAGE_SHIFT > 0) ? (1 << (AVERAGE_SHIFT - 1)) : 0;
localparam integer SUM_WIDTH    = WIDTH + AVERAGE_SHIFT + 1;
localparam integer AVG_MSB      = AVERAGE_SHIFT + WIDTH - 1;

reg [SUM_WIDTH-1:0] sum_acc;
reg [AVERAGE_SHIFT:0] sample_cnt;
reg                  otr_acc;

wire [SUM_WIDTH-1:0] sample_ext;
wire [SUM_WIDTH-1:0] window_sum;
wire [SUM_WIDTH-1:0] rounded_sum;

assign sample_ext  = {{(SUM_WIDTH - WIDTH){1'b0}}, ad_data};
assign window_sum  = sum_acc + sample_ext;
assign rounded_sum = window_sum + ROUND_BIAS;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sum_acc     <= {SUM_WIDTH{1'b0}};
        sample_cnt  <= {(AVERAGE_SHIFT + 1){1'b0}};
        otr_acc     <= 1'b0;
        avg_code    <= {WIDTH{1'b0}};
        avg_valid   <= 1'b0;
        over_range  <= 1'b0;
    end else begin
        avg_valid <= 1'b0;

        if (sample_cnt == SAMPLE_COUNT - 1) begin
            avg_code   <= rounded_sum[AVG_MSB:AVERAGE_SHIFT];
            avg_valid  <= 1'b1;
            over_range <= otr_acc | ad_otr;
            sum_acc    <= {SUM_WIDTH{1'b0}};
            sample_cnt <= {(AVERAGE_SHIFT + 1){1'b0}};
            otr_acc    <= 1'b0;
        end else begin
            sum_acc    <= window_sum;
            sample_cnt <= sample_cnt + 1'b1;
            otr_acc    <= otr_acc | ad_otr;
        end
    end
end

endmodule
