/*
 * Module: binary2bcd
 * 功能:
 *   将 16 位二进制数转换为 4 位 BCD 数据。
 */

module binary2bcd(
    input   wire           sys_clk,
    input   wire           sys_rst_n,
    input   wire  [15:0]   data,

    output  reg   [15:0]   bcd_data 
);


parameter   CNT_SHIFT_NUM = 5'd16;  


reg [4:0]   cnt_shift ;             
reg [31:0]  data_shift;             
reg         shift_flag;             


// Shift round counter.
always@(posedge sys_clk or negedge sys_rst_n)begin
    if(!sys_rst_n)
        cnt_shift <= 5'd0;
    else if((cnt_shift == CNT_SHIFT_NUM + 5'd1) && (shift_flag))
        cnt_shift <= 5'd0;
    else if(shift_flag)
        cnt_shift <= cnt_shift + 5'b1;
    else
        cnt_shift <= cnt_shift;
end

// Double-dabble core: adjust then shift.
always@(posedge sys_clk or negedge sys_rst_n)begin
    if(!sys_rst_n)
        data_shift <= 32'd0;
    else if(cnt_shift == 5'd0)
        data_shift <= {16'b0,data};
    else if((cnt_shift <= CNT_SHIFT_NUM) && (!shift_flag))begin
        data_shift[19:16] <= (data_shift[19:16] > 4) ? (data_shift[19:16] + 4'd3):(data_shift[19:16]);
        data_shift[23:20] <= (data_shift[23:20] > 4) ? (data_shift[23:20] + 4'd3):(data_shift[23:20]);
        data_shift[27:24] <= (data_shift[27:24] > 4) ? (data_shift[27:24] + 4'd3):(data_shift[27:24]);
        data_shift[31:28] <= (data_shift[31:28] > 4) ? (data_shift[31:28] + 4'd3):(data_shift[31:28]);
        end
    else if((cnt_shift <= CNT_SHIFT_NUM) && (shift_flag))
        data_shift <= data_shift << 1;
    else
        data_shift <= data_shift;
end


// Toggle adjust/shift sub-phase.
always@(posedge sys_clk or negedge sys_rst_n)begin
    if(!sys_rst_n)
        shift_flag <= 1'b0;
    else
        shift_flag <= ~shift_flag;
end


// Latch final BCD result after all shift rounds.
always@(posedge sys_clk or negedge sys_rst_n)begin
    if(!sys_rst_n)
        bcd_data <= 16'd0;
    else if(cnt_shift == CNT_SHIFT_NUM + 5'b1)
        bcd_data <= data_shift[31:16];
    else
        bcd_data <= bcd_data;
end

endmodule
