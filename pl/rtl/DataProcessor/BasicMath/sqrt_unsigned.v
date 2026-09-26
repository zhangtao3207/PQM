`timescale 1ns / 1ps

/*
 * 模块: sqrt_unsigned
 * 功能:
 *   参数化无符号平方根单元。该模块在 ROOT_WIDTH 个时钟周期内逐位搜索结果，
 *   避免了之前本地 isqrt 函数的大规模组合逻辑扩展。
 */
module sqrt_unsigned #(
    parameter integer RADICAND_WIDTH = 32,
    parameter integer ROOT_WIDTH     = (RADICAND_WIDTH + 1) / 2
)(
    input  wire                          clk,
    input  wire                          rst_n,
    input  wire                          start,
    input  wire [RADICAND_WIDTH-1:0]     radicand,
    output reg                           busy,
    output reg                           done,
    output reg  [ROOT_WIDTH-1:0]         root
);

localparam integer BIT_IDX_W = (ROOT_WIDTH <= 2) ? 2 : $clog2(ROOT_WIDTH);

reg [RADICAND_WIDTH-1:0] radicand_reg;
reg [ROOT_WIDTH-1:0]     root_reg;
reg [BIT_IDX_W-1:0]      bit_idx;

wire [ROOT_WIDTH-1:0] candidate_mask;
wire [ROOT_WIDTH-1:0] candidate;
wire [(2 * ROOT_WIDTH) - 1:0] candidate_sq;
wire [(2 * ROOT_WIDTH) - 1:0] radicand_ext;
wire                          candidate_accept;
wire [ROOT_WIDTH-1:0]         root_next;

assign candidate_mask   = {{(ROOT_WIDTH - 1){1'b0}}, 1'b1} << bit_idx;
assign candidate        = root_reg | candidate_mask;
assign candidate_sq     = candidate * candidate;
assign radicand_ext     = {{((2 * ROOT_WIDTH) - RADICAND_WIDTH){1'b0}}, radicand_reg};
assign candidate_accept = (candidate_sq <= radicand_ext);
assign root_next        = candidate_accept ? candidate : root_reg;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        busy        <= 1'b0;
        done        <= 1'b0;
        root        <= {ROOT_WIDTH{1'b0}};
        root_reg    <= {ROOT_WIDTH{1'b0}};
        radicand_reg<= {RADICAND_WIDTH{1'b0}};
        bit_idx     <= {BIT_IDX_W{1'b0}};
    end else begin
        done <= 1'b0;

        if (start && !busy) begin
            busy         <= 1'b1;
            root_reg     <= {ROOT_WIDTH{1'b0}};
            radicand_reg <= radicand;
            bit_idx      <= ROOT_WIDTH - 1;
        end else if (busy) begin
            root_reg <= root_next;

            if (bit_idx == {BIT_IDX_W{1'b0}}) begin
                busy <= 1'b0;
                done <= 1'b1;
                root <= root_next;
            end else begin
                bit_idx <= bit_idx - {{(BIT_IDX_W-1){1'b0}}, 1'b1};
            end
        end
    end
end

endmodule
