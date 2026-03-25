
module AD7606_Driver (
    input clk,
    input rst_n,
    input data_in,
    input is_busy,
    input AD_ENABLE,

    output range,
    output [2:0] os,
    output ad_rst,
    output reg convst_A,
    output reg convst_B,
    output reg spi_cs,
    output spi_clk_rd,

    output [15:0] rddata,

    //
    output wire [3:0] state_t
);



assign range = 1'b0; // 0: ±5V, 1: ±10V
assign os = 3'b000;  //过采�?
assign ad_rst = ~rst_n;
assign spi_clk_rd = spi_cs;


wire clk_25;
ADC_CLK_DIV clk_div (
    .clk(clk),
    .rst_n(rst_n),
    .div(12'd20),
    .clk_out(clk_25)
);



reg [1:0] is_busy_r;
wire is_busy_neg;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        is_busy_r <= 2'd0;
    else is_busy_r <= {is_busy_r[0],is_busy};
end

assign is_busy_neg = ~is_busy&is_busy_r[0];



wire read_done;
wire read_done_pos;
reg [1:0] read_done_r;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        read_done_r <= 2'd0;
    else read_done_r <= {read_done_r[0],read_done};
end

assign read_done_pos = (!is_busy_r[0]) & read_done;




reg [3:0] state;
parameter IDLE = 4'b0001,CONVST = 4'b0010,CONVSTING = 4'b0100,READDATA = 4'b1000;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        state <= IDLE;
    else begin
        case(state)
            IDLE:   if(AD_ENABLE)  state <= CONVST;
            CONVST:     state <= CONVSTING;
            CONVSTING: if(is_busy_neg) state <= READDATA;
            READDATA:  if(is_busy|read_done_pos) state <= IDLE;
        endcase
    end
end


reg [15:0] cnt;
reg start;
always @(posedge clk or negedge rst_n) begin 
    if(!rst_n)  begin
        spi_cs <= 1'b1;
        convst_A <= 1'b1;
        convst_B <= 1'b1;
        cnt <= 16'd0;
        start <= 1'b0;
    end
    else begin 
        case(state)
            IDLE: begin
                spi_cs <= 1'b1;
                convst_A <= 1'b0;
                convst_B <= 1'b0;
                cnt <= 16'd0;
                start <= 1'b0;
            end
            CONVST: begin
                spi_cs <= 1'b1;
                convst_A <= 1'b1;
                convst_B <= 1'b1;
                cnt <= 16'd0;
                start <= 1'b1;
            end
            CONVSTING: begin
                spi_cs <= 1'b1;
                convst_A <= 1'b1;
                convst_B <= 1'b1;
                cnt <= 16'd0;
                start <= 1'b0;
            end
            READDATA: begin
                if(cnt < 16'd40)begin
                    cnt <= cnt + 1;
                    start <= 1;
                    if(cnt[0] == 0) spi_cs <= 1'b0;
                    else if (cnt[0] == 1'b1) spi_cs <= 1'b1;
                end
                else begin
                    start <= 1'b0;
                end
            end
        endcase
    end
end

wire clk_spi;
assign clk_spi = (state == READDATA) ? spi_cs : clk_25;

assign state_t = state;
AD7606_SPI u_AD7606_SPI (
    .clk(clk_spi),
    .rst_n(rst_n),
    .start(start),
    .data_in(data_in),

    .rddata(rddata),
    .read_done(read_done)
);

endmodule
