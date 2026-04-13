/*
 * 模块: binary2bcd
 * 功能:
 *   将 16 位二进制数转换为 4 位 BCD 显示码。
 *
 * 输入:
 *   sys_clk: 系统时钟。
 *   sys_rst_n: 低有效系统复位信号。
 *   data: 待转换的 16 位二进制输入。
 *
 * 输出:
 *   bcd_data: BCD 编码结果。
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


// 记录当前进行到第几轮移位/修正操作。
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

// double-dabble 主体：先修正，再移位。
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


// 在“修正”和“移位”两个子阶段之间交替切换。
always@(posedge sys_clk or negedge sys_rst_n)begin
    if(!sys_rst_n)
        shift_flag <= 1'b0;
    else
        shift_flag <= ~shift_flag;
end


// 所有轮次结束后，把最终 BCD 结果锁存到输出。
always@(posedge sys_clk or negedge sys_rst_n)begin
    if(!sys_rst_n)
        bcd_data <= 16'd0;
    else if(cnt_shift == CNT_SHIFT_NUM + 5'b1)
        bcd_data <= data_shift[31:16];
    else
        bcd_data <= bcd_data;
end

endmodule
