//****************************************Copyright (c)***********************************//
//原子哥在线教学平台：www.yuanzige.com
//技术支持：www.openedv.com
//淘宝店铺：http://openedv.taobao.com
//关注微信公众平台微信号："正点原子"，免费获取ZYNQ & FPGA & STM32 & LINUX资料。
//版权所有，盗版必究。
//Copyright(C) 正点原子 2018-2028
//All rights reserved
//----------------------------------------------------------------------------------------
// File name:           gt9271
// Last modified Date:  2019/07/26 16:04:03
// Last Version:        V1.0
// Descriptions:        10.1寸电容触摸屏-GT9271 驱动代码
//----------------------------------------------------------------------------------------
// Created by:          正点原子
// Created date:        2019/07/26 16:04:07
// Version:             V1.0
// Descriptions:        The original version
//
//----------------------------------------------------------------------------------------
//****************************************************************************************//

#ifndef __GT9271_H
#define __GT9271_H
#include "xil_types.h"

//IO操作函数
#define GT9271_RST(x)   	IOWR_ALTERA_AVALON_PIO_DATA(TOUCH_TCS_BASE,x) 		//GT9147复位引脚
#define GT9271_INT(x)   	IOWR_ALTERA_AVALON_PIO_DATA(TOUCH_INT_BASE,x)     	//GT9147中断引脚
#define GT9271_INT_DIR(x)	IOWR_ALTERA_AVALON_PIO_DIRECTION(TOUCH_INT_BASE,x)  // 设置PIO的方向

//I2C读写命令
#define GT9271_CMD_WR       0X28        //写命令
#define GT9271_CMD_RD       0X29        //读命令

//GT9271 部分寄存器定义
#define GT9271_CTRL_REG     0X8040      //GT9271控制寄存器
#define GT9271_CFGS_REG     0X8047      //GT9271配置起始地址寄存器
#define GT9271_CHECK_REG    0X80FF      //GT9271校验和寄存器
#define GT9271_PID_REG      0X8140      //GT9271产品ID寄存器

#define GT9271_GSTID_REG    0X814E      //GT9271当前检测到的触摸情况
#define GT9271_TP1_REG      0X8150      //第一个触摸点数据地址
#define GT9271_TP2_REG      0X8158      //第二个触摸点数据地址
#define GT9271_TP3_REG      0X8160      //第三个触摸点数据地址
#define GT9271_TP4_REG      0X8168      //第四个触摸点数据地址
#define GT9271_TP5_REG      0X8170      //第五个触摸点数据地址
#define GT9271_TP6_REG      0X8178      //第六个触摸点数据地址
#define GT9271_TP7_REG      0X8180      //第七个触摸点数据地址
#define GT9271_TP8_REG      0X8188      //第八个触摸点数据地址
#define GT9271_TP9_REG      0X8190      //第九个触摸点数据地址
#define GT9271_TP10_REG     0X8198      //第十个触摸点数据地址


u8 GT9271_Send_Cfg(u8 mode);
u8 GT9271_WR_Reg(u16 reg,u8 *buf,u8 len);
void GT9271_RD_Reg(u16 reg,u8 *buf,u8 len);
u8 GT9271_Init(void);
u8 GT9271_Scan(u8 mode);
#endif
