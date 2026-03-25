`timescale 1ps/1ps

module ADC_CLK_DIV_TB(); 

reg clk;
reg rst_n;
reg [11:0] div;
wire clk_out;


initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    div = 12'd8;
    #100;
    rst_n = 1'b1;
    #10_000;
    $finish;
end

always #10 clk = ~clk; 

ADC_CLK_DIV u_ADC_CLK_DIV(
    .clk(clk),
    .rst_n(rst_n),
    .div(div),
    .clk_out(clk_out)
);

endmodule