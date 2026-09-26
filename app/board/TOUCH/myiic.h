//****************************************Copyright (c)***********************************//
//原子哥在线教学平台：www.yuanzige.com
//技术支持：www.openedv.com
//淘宝店铺：http://openedv.taobao.com
//关注微信公众平台微信号："正点原子"，免费获取ZYNQ & FPGA & STM32 & LINUX资料。
//版权所有，盗版必究。
//Copyright(C) 正点原子 2018-2028
//All rights reserved
//----------------------------------------------------------------------------------------
// File name:           myiic.h
// Last modified Date:  2019/07/26 16:04:03
// Last Version:        V1.0
// Descriptions:        IIC 驱动代码的头文件
//----------------------------------------------------------------------------------------
// Created by:          正点原子
// Created date:        2019/07/26 16:04:07
// Version:             V1.0
// Descriptions:        The original version
//
//----------------------------------------------------------------------------------------
//****************************************************************************************//

#ifndef __MYIIC_H
#define __MYIIC_H
#include "../APP/delay.h"


//IIC所有操作函数
void IIC_Init(void);                    //初始化IIC的IO口
void IIC_Start(void);                   //发送IIC开始信号
void IIC_Stop(void);                    //发送IIC停止信号
void IIC_Send_Byte(u8 txd);             //IIC发送一个字节
u8   IIC_Read_Byte(unsigned char ack);  //IIC读取一个字节
u8   IIC_Wait_Ack(void);                //IIC等待ACK信号
void IIC_Ack(void);                     //IIC发送ACK信号
void IIC_NAck(void);                    //IIC不发送ACK信号
#endif
