`timescale 1ns/1ns

module ADC_DRIVER_TB ();

reg clk;
reg rst_n;
reg data_in;
reg is_busy;
wire [3:0] state_t;

wire range;
wire [2:0] os;
wire ad_rst;
wire convst_A;
wire convst_B;
wire spi_cs;
wire spi_clk_rd;
wire [15:0] rddata;

//
wire [4:0] cnt;
wire start;

reg [3:0] mov;
reg [3:0] num;
reg convst_a_d;
reg [15:0] busy_cycle_cnt;

localparam integer CONV_BUSY_CYCLES = 16'd40;

reg [15:0] sample_mem [0:5];
initial begin
    clk = 1'b0;
    rst_n = 1'b0;
    data_in = 1'bz;
    is_busy = 1'b0;

    sample_mem[0] = 16'b1000_0100_0010_0001;//8421
    sample_mem[1] = 16'h89AB;
    sample_mem[2] = 16'hFEDC;
    sample_mem[3] = 16'h34AB;
    sample_mem[4] = 16'hDFE2;
    sample_mem[5] = 16'h6dc0;


    mov = 4'd15;
    num = 4'd0;
    convst_a_d = 1'b0;
    busy_cycle_cnt = 16'd0;

    #80;
    rst_n = 1'b1;

    #2000000;
    $stop;
end

always #10 clk = ~clk;

// Generate a realistic BUSY pulse after each conversion start.
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        convst_a_d <= 1'b0;
        is_busy <= 1'b0;
        busy_cycle_cnt <= 16'd0;
    end
    else begin
        convst_a_d <= convst_A;

        if(!convst_a_d && convst_A && !is_busy) begin
            is_busy <= 1'b1;
            busy_cycle_cnt <= 16'd0;
        end
        else if(is_busy) begin
            if(busy_cycle_cnt >= CONV_BUSY_CYCLES - 1) begin
                is_busy <= 1'b0;
                busy_cycle_cnt <= 16'd0;
            end
            else begin
                busy_cycle_cnt <= busy_cycle_cnt + 16'd1;
            end
        end
    end
end

// CS falling edge makes DOUT leave Hi-Z and present the first MSB.
always @(negedge spi_cs or posedge spi_cs or negedge rst_n) begin
    if(!rst_n) begin
        mov <= 4'd15;
        data_in <= 1'bz;
    end
    else if(!spi_cs) begin
        mov <= 4'd15;
        data_in <= sample_mem[num][15];
    end
    else begin
        data_in <= 1'bz;
    end
end

// Subsequent SCLK rising edges shift out the remaining bits.
always @(posedge spi_clk_rd or negedge rst_n) begin
    if(!rst_n)begin
        mov <= 4'd15;
        num <= 4'd0;
        data_in <= 1'bz;
    end
    else if(!spi_cs) begin
        if(mov == 4'd15) begin
            data_in <= sample_mem[num][14];
            mov <= 4'd14;
        end
        else if(mov != 0) begin
            data_in <= sample_mem[num][mov - 1];
            mov <= mov - 4'd1;
        end
        else begin
            data_in <= sample_mem[num][0];
            mov <= 4'd15;
            if(num < 4'd5)
                num <= num + 4'd1;
        end
    end
    else begin
        mov <= 4'd15;
        data_in <= 1'bz;
    end
end


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
    .state_t(state_t),
    .cnt_t(cnt),
    .start(start)
);

endmodule
