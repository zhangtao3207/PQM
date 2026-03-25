
module ADC_CLK_DIV (
    input clk,
    input rst_n,
    input [11:0] div,
    output wire clk_out
);

reg [11:0] cnt;
reg clk_out_reg;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        cnt <= 12'd0;
        clk_out_reg <= 1'b0;
    end
    else begin
        if(div <= 12'd1) begin
            clk_out_reg <= 1'b0;
        end
        else begin
            if(cnt >= div/2 - 12'd1) begin
                cnt <= 12'd0;
                clk_out_reg <= ~ clk_out_reg;
                cnt <= 12'd0;
            end
            else begin
                cnt <= cnt + 12'd1;
            end
        end
    end
end

assign clk_out = clk_out_reg;

endmodule