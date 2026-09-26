//****************************************Copyright (c)***********************************//
//原子哥在线教学平台：www.yuanzige.com
//技术支持：http://www.openedv.com/forum.php
//淘宝店铺：https://zhengdianyuanzi.tmall.com
//关注微信公众平台微信号："正点原子"，免费获取ZYNQ & FPGA & STM32 & LINUX资料。
//版权所有，盗版必究。
//Copyright(C) 正点原子 2023-2033
//All rights reserved                                  
//----------------------------------------------------------------------------------------
// File name:           timer
// Created by:          正点原子
// Created date:        2024年4月28日14:02:48
// Version:             V1.0
// Descriptions:        定时器中断配置和处理
//
//----------------------------------------------------------------------------------------
//****************************************************************************************//

#ifndef TIMER_H_
#define TIMER_H_

#include "xparameters.h"				//包含器件的参数信息
#include "xscutimer.h"					//定时器中断的函数声明
#include "xscugic.h"					//包含中断的函数声明
#include "xil_printf.h"

int timer_init(XScuGic *intc_ptr);
void timer_intr_handler(void *CallBackRef);

#endif /* TIMER_H_ */





