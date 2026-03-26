module AD7606_SPI  (
    input clk,
    input rst_n,
    input start,
    input sclk_en,
    input data_in,

    output reg [15:0] rddata,
    output reg read_done,
    output reg [4:0] cnt_t
);

always@(posedge clk or negedge rst_n)begin
    if(!rst_n) cnt_t <= 5'b0;
    else if(!start) cnt_t <= 5'b0;
    else if(!sclk_en) cnt_t <= 5'b0;
    else if(cnt_t < 5'd31) cnt_t <= cnt_t + 5'b1;
end

reg [15:0] rddata_r;
always@(negedge clk or negedge rst_n)begin
    if(!rst_n) begin
        rddata_r <= 16'b0;
        read_done <= 1'b0;
        rddata <= 16'b0;
    end 
    else if(start && !sclk_en) begin
        read_done <= 1'b0;
        rddata[15] <= data_in;
    end
    else if(sclk_en)
        case (cnt_t)
            5'd0: read_done <= 1'b0;
            5'd1: rddata[14] <= data_in;
            5'd2: rddata[13] <= data_in;
            5'd3: rddata[12] <= data_in;
            5'd4: rddata[11] <= data_in;
            5'd5: rddata[10] <= data_in;
            5'd6: rddata[9] <= data_in;
            5'd7: rddata[8] <= data_in;
            5'd8: rddata[7] <= data_in;
            5'd9: rddata[6] <= data_in;
            5'd10: rddata[5] <= data_in;
            5'd11: rddata[4] <= data_in;
            5'd12: rddata[3] <= data_in;
            5'd13: rddata[2] <= data_in;
            5'd14: rddata[1] <= data_in;
            5'd15: rddata[0] <= data_in;
            5'd16:begin
                //rddata <= rddata_r;
                read_done <= 1'd1;
            end
            default:; 
        endcase
    else
        read_done <= 1'b0;
end

endmodule
