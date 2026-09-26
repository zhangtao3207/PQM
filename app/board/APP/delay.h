//****************************************Copyright (c)***********************************//
//原子哥在线教学平台：www.yuanzige.com
//技术支持：www.openedv.com
//淘宝店铺：http://openedv.taobao.com 
//关注微信公众平台微信号："正点原子"，免费获取ZYNQ & FPGA & STM32 & LINUX资料。
//版权所有，盗版必究。
//Copyright(C) 正点原子 2018-2028
//All rights reserved
//----------------------------------------------------------------------------------------
// File name:           delay.h
// Last modified Date:  2019/07/26 9:53:48
// Last Version:        V1.0
// Descriptions:        延时函数头文件
//----------------------------------------------------------------------------------------
// Created by:          正点原子
// Created date:        2019/07/26 9:53:52
// Version:             V1.0
// Descriptions:        The original version
//
//----------------------------------------------------------------------------------------
//****************************************************************************************//

#ifndef DELAY_H_
#define DELAY_H_
#include "xil_types.h"
#include "sleep.h"

void delay_ms(u32 n);       //毫秒延时
void delay_us(u32 n);       //微秒延时

#endif /* DELAY_H_ */
