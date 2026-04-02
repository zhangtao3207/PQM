`timescale 1ns / 1ps


module adc_write_ctrl_tb();

    reg Clk;
    reg Reset_n;
    reg [14:0]DataNum;    //单次采集的数据个数，最大不超过FIFO的深度
    reg RestartReq;       //开始采样请求信号
    reg [7:0]ChannelSel;  //需要采样的通道选择  ，每一位对应一个通道的开关
    wire fifowrreq;       //采集到的数据写FIFO请求信号
    wire [15:0]fifowrdata; //采集到的数据
    reg fifowrfull;
    
    reg [7:0]adc_data_flag;
    reg [15:0]adc_data_mult_ch;
    
    adc_write_ctrl adc_write_ctrl(
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
    
    initial Clk = 1;
    always #10 Clk = ~Clk;
    
    integer i;
    
    initial begin
        Reset_n = 0;
        i=0;
        RestartReq = 0;
        adc_data_flag = 8'b0000_0000;;
        adc_data_mult_ch = 0;
        DataNum = 100;
        ChannelSel = 8'hf0;
        fifowrfull = 0;
        #201;
        Reset_n = 1;
        #200;
        RestartReq = 1;
        #20;
        RestartReq = 0;
        #200;
        repeat(120)begin
            for(i=0;i<8;i=i+1)begin
                adc_data_mult_ch = adc_data_mult_ch + 1;
                adc_data_flag = 1 << i;
                #20;
                adc_data_flag = 0;
                #100;
            end
        end   
        #2000;
        $stop; 
    end

endmodule
