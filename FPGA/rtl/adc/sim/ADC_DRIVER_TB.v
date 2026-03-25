
module ADC_DRIVER_TB ();
    
reg clk;
reg rst_n;
reg data_in;
reg is_busy;
wire[3:0] state_t;

wire range;
wire os;
wire ad_rst;
wire convst_A;
wire convst_B;
wire spi_cs;
wire spi_clk_rd;
wire [15:0] rddata;


initial begin
    clk <= 1'b0;
    rst_n <= 1'b0;

    #40
    rst_n <= 1'b1;
    is_busy <= 1'b0;

    #1600
    is_busy <= 1'b1;
    data_in <= 1'd1;

    #1600
    is_busy <= 1'd0;

    #20_000
    is_busy <= 1'd1;
    data_in <= 1'd0;

    #1600
    is_busy <= 1'd0;

    #20_000
    is_busy <= 1'd1;
    data_in <= 1'd1;

    #1600
    is_busy <= 1'd0;

    


    #100_000
    $stop;
end

always #10 clk <= ~clk;

AD7606_Driver u_AD7606_Driver(
    .clk(clk),
    .rst_n(rst_n),
    .data_in(data_in),
    .is_busy(is_busy),
    .AD_ENABLE(1'b1),

    .range(range),
    .os(os),
    .ad_rst(ad_rst),
    .convst_A(convst_A),
    .convst_B(convst_B),
    .spi_cs(spi_cs),
    .spi_clk_rd(spi_clk_rd),

    .rddata(rddata),
    .state_t(state_t)
);
endmodule