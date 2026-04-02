`timescale 1ns/1ps
module adc_write_ctrl(
    Clk,
    Reset_n,
    DataNum,
    RestartReq,
    ChannelSel,
    fifowrreq,
    fifowrdata,
    fifowrfull,
    
    adc_data_flag,
    adc_data_mult_ch
);
    
    input Clk;
    input Reset_n;
    input [14:0]DataNum;    //单次采集的数据个数，最大不超过FIFO的深度
    input RestartReq;       //开始采样请求信号
    input [7:0]ChannelSel;  //需要采样的通道选择  ，每一位对应一个通道的开关
    output reg fifowrreq;       //采集到的数据写FIFO请求信号
    output reg[15:0]fifowrdata; //采集到的数据
    input fifowrfull;
    
    input [7:0]adc_data_flag;
    input [15:0]adc_data_mult_ch;
    
    reg sample_en;  //采样
    reg [14:0]data_cnt;
    
    //采样控制逻辑，每次采样请求信号到来开始采样，采样个数满了停止采样。
    always@(posedge Clk or negedge Reset_n)
    if(!Reset_n)
        sample_en <= #1  1'b0;
    else if(RestartReq)
        sample_en <= #1  1'b1;
    else if(data_cnt >= DataNum)
        sample_en <= #1  1'b0;
    
    //采样个数计数器，在采样使能阶段，每个flag到来的时候计数器自加1
    always@(posedge Clk or negedge Reset_n)
    if(!Reset_n)
        data_cnt <= #1  15'd0;
    else if(sample_en)begin
        if(adc_data_flag & ChannelSel)
            data_cnt <= #1  data_cnt + 1'd1;
        else
            data_cnt <= #1  data_cnt;
    end
    else
        data_cnt <= #1  15'd0;
 
    always@(posedge Clk)
        fifowrreq <= #1  (adc_data_flag & ChannelSel)  && sample_en;
        
    always@(posedge Clk)    
        fifowrdata <= #1  adc_data_mult_ch;

endmodule
