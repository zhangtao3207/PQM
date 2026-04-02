//****************************************Copyright (c)***********************************//
//原子哥在线教学平台：www.yuanzige.com
//技术支持：http://www.openedv.com/forum.php
//淘宝店铺：https://zhengdianyuanzi.tmall.com
//关注微信公众平台微信号："正点原子"，免费获取ZYNQ & FPGA & STM32 & LINUX资料。
//版权所有，盗版必究。
//Copyright(C) 正点原子 2023-2033
//All rights reserved                                  
//----------------------------------------------------------------------------------------
// File name:           tb_top_dvm
// Created by:          正点原子
// Created date:        2025年10月10日10:47:00
// Version:             V1.0
// Descriptions:        电压表实验仿真激励文件
//
//----------------------------------------------------------------------------------------
//****************************************************************************************//

`timescale 1ns / 1ns

module tb_top_dvm();

//reg define
reg           sys_clk;
reg           sys_rst_n;     
reg [7:0]     test_data;
reg [11:0]    initial_cnt;

//wire define
wire          lcd_de ;
wire          lcd_hs ;
wire          lcd_vs ;
wire          lcd_bl ;
wire          lcd_clk;
wire  [23:0]  lcd_rgb;
wire          lcd_rst;

wire          ad_clk ;
wire          da_clk ;
wire  [7:0]   da_data;
        
always #10 sys_clk = ~sys_clk;
assign lcd_rgb = lcd_de ?  {24{1'bz}} : 24'h80;

initial begin
    sys_clk = 1'b0;
    sys_rst_n = 1'b0;
    #200
    sys_rst_n = 1'b1;
end

always @(posedge ad_clk or negedge sys_rst_n )begin
    if(!sys_rst_n) 
        initial_cnt <= 12'd0;
    else if(initial_cnt < 12'd2048)
        initial_cnt <= initial_cnt+12'd1;
    else;
end

always@(posedge ad_clk or negedge sys_rst_n )begin
    if(!sys_rst_n)
        test_data <= 8'd0;
    else if(initial_cnt<12'd2048)
        test_data <= 8'd127;
    else
        test_data <= da_data;
end

top_dvm u_top_dvm(
    .sys_clk  (sys_clk),
    .sys_rst_n(sys_rst_n),
    .ad_data  (test_data),
    .ad_otr   (1'b0),
    .ad_clk   (ad_clk),
    .da_clk   (da_clk),
    .da_data  (da_data),
    .lcd_de   (lcd_de ),
    .lcd_hs   (lcd_hs ),
    .lcd_vs   (lcd_vs ),
    .lcd_clk  (lcd_clk),
    .lcd_rgb  (lcd_rgb),
    .lcd_rst  (lcd_rst),
    .lcd_bl   (lcd_bl ) 
    );

endmodule
