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

#ifndef __TOUCH_H__
#define __TOUCH_H__

#include "gt9147.h"
#include "gt9271.h"
#include "ft5206.h"
#include "xil_types.h"

#define TP_PRES_DOWN 0x8000  //触屏被按下
#define TP_CATH_PRES 0x4000  //有按键按下了
#define CT_MAX_TOUCH 10      //电容屏支持的点数,固定为10点

#define PEN   IORD_ALTERA_AVALON_PIO_DATA(TOUCH_INT_BASE)   //T_PEN

//触摸屏控制器
typedef struct
{
    u8 (*init)(void);           //初始化触摸屏控制器
	u8 (*scan)(void);           //扫描触摸屏.0,屏幕扫描;1,物理坐标;
    u16 x[CT_MAX_TOUCH];        //当前坐标
    u16 y[CT_MAX_TOUCH];        
    //电容屏最多有10组坐标,电阻屏则用x[0],y[0]代表:此次扫描时,触屏的坐标,用
                                //x[9],y[9]存储第一次按下时的坐标.
    u16 sta;                    //笔的状态
                                //b15:按下1/松开0;
                                //b14:0,没有按键按下;1,有按键按下.
                                //b13~b10:保留
                                //b9~b0:电容触摸屏按下的点数(0,表示未按下,1表示按下)
//新增的参数,当触摸屏的左右上下完全颠倒时需要用到.
//b0:0,竖屏(适合左右为X坐标,上下为Y坐标的TP)
//   1,横屏(适合左右为Y坐标,上下为X坐标的TP)
//b1~6:保留.
//b7:0,电阻屏
//   1,电容屏
    u8 touchtype;
}_m_tp_dev;

extern _m_tp_dev tp_dev;        //触屏控制器在touch.c里面定义

//电容屏 共用函数
u8 TP_Scan();                   //扫描
void TP_Init(void);             //初始化

#endif
