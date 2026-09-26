//****************************************Copyright (c)***********************************//
//原子哥在线教学平台：www.yuanzige.com
//技术支持：www.openedv.com
//淘宝店铺：http://openedv.taobao.com
//关注微信公众平台微信号："正点原子"，免费获取ZYNQ & FPGA & STM32 & LINUX资料。
//版权所有，盗版必究。
//Copyright(C) 正点原子 2018-2028
//All rights reserved
//----------------------------------------------------------------------------------------
// File name:           touch
// Last modified Date:  2019/07/26 16:04:03
// Last Version:        V1.0
// Descriptions:        触摸屏驱动代码
//----------------------------------------------------------------------------------------
// Created by:          正点原子
// Created date:        2019/07/26 16:04:07
// Version:             V1.0
// Descriptions:        The original version
//
//----------------------------------------------------------------------------------------
//****************************************************************************************//

#ifndef __MAIN_H__
#define __MAIN_H__

#include "display_ctrl/display_ctrl.h"


//*************************************************
//画笔颜色
#define MLCD_WHITE        0XFFFF
#define MLCD_BLACK        0X0000
#define MLCD_BLUE         0X001F
#define MLCD_BRED         0XF81F
#define MLCD_GRED         0XFFE0
#define MLCD_GBLUE        0X07FF
#define MLCD_RED          0XF800
#define MLCD_MAGENTA      0XF81F
#define MLCD_GREEN        0X07E0
#define MLCD_CYAN         0X7FFF
#define MLCD_YELLOW       0XFFE0
#define MLCD_BROWN        0XBC40 //棕色
#define MLCD_BRRED        0XFC07 //棕红色
#define MLCD_GRAY         0X8430 //灰色

#define MLCD_DARKBLUE     0X01CF //深蓝色
#define MLCD_LIGHTBLUE    0X7D7C //浅蓝色
#define MLCD_GRAYBLUE     0X5458 //灰蓝色

#define MLCD_LIGHTGREEN   0X841F //浅绿色
#define MLCD_LGRAY        0XC618 //浅灰色

#define MLCD_LGRAYBLUE    0XA651 //浅灰蓝色
#define MLCD_LBBLUE       0X2B12 //浅棕蓝色


extern  VideoMode  vd_mode ;

extern  unsigned int lcd_id;        //LCD ID

#endif

