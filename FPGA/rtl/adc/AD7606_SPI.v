module AD7606_SPI  (
    input clk,
    input rst_n,
    input start,
    input data_in,

    output reg [15:0] rddata,
    output reg read_done
);

reg [4:0] cnt;
always@(posedge clk or negedge rst_n)begin
    if(!rst_n) cnt <= 5'b0;
    else if(!start) cnt <= 5'b0;
    else if(cnt < 5'd31) cnt <= cnt + 5'b1;
end

reg [15:0] rddata_r;
always@(posedge clk or negedge rst_n)begin
    if(!rst_n) begin
        rddata_r <= 16'b0;
        read_done <= 1'b0;
    end 
    else 
        case (cnt)
            5'd0: read_done <= 1'b0;
            5'd1: rddata_r[15] <= data_in;
            5'd2: rddata_r[14] <= data_in;
            5'd3: rddata_r[13] <= data_in;
            5'd4: rddata_r[12] <= data_in;
            5'd5: rddata_r[11] <= data_in;
            5'd6: rddata_r[10] <= data_in;
            5'd7: rddata_r[9] <= data_in;
            5'd8: rddata_r[8] <= data_in;
            5'd9: rddata_r[7] <= data_in;
            5'd10: rddata_r[6] <= data_in;
            5'd11: rddata_r[5] <= data_in;
            5'd12: rddata_r[4] <= data_in;
            5'd13: rddata_r[3] <= data_in;
            5'd14: rddata_r[2] <= data_in;
            5'd15: rddata_r[1] <= data_in;
            5'd16: rddata_r[0] <= data_in;
            5'd17:begin
                rddata <= rddata_r;
                read_done <= 1'd1;
            end
            default:; 
        endcase
end

endmodule