//****************************************Copyright (c)***********************************//
//原子哥在线教学平台：www.yuanzige.com
//技术支持：www.openedv.com
//淘宝店铺：http://openedv.taobao.com
//关注微信公众平台微信号："正点原子"，免费获取ZYNQ & FPGA & STM32 & LINUX资料。
//版权所有，盗版必究。
//Copyright(C) 正点原子 2018-2028
//All rights reserved
//----------------------------------------------------------------------------------------
// File name:           emio_iic_cfg.h
// Last modified Date:  2019/07/26 15:59:46
// Last Version:        V1.0
// Descriptions:        iic驱动
//----------------------------------------------------------------------------------------
// Created by:          正点原子
// Created date:        2019/07/26 15:59:52
// Version:             V1.0
// Descriptions:        The original version
//
//----------------------------------------------------------------------------------------
//****************************************************************************************//

#ifndef IIC_EMIO_CFG_
#define IIC_EMIO_CFG_


#include "xgpiops.h"


#define EMIO_SCL_NUM 54
#define EMIO_SDA_NUM 55
#define EMIO_CT_RST_NUM 56
#define EMIO_CT_INT_NUM 57

void emio_init(void);

void  SDA_IN( void );
void  SDA_OUT( void );
void  IIC_SCL( u8 x );
void  IIC_SDA( u8 x );
u8  READ_SDA ( void );

void  CT_RST( u8 x );
void  INT_DIR( u8 x );
void  INT( u8 x );
u8  INT_RD( void );


#endif /* SCCB_EMIO_CFG_ */
