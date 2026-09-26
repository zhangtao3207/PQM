//****************************************Copyright (c)***********************************//
//原子哥在线教学平台：www.yuanzige.com
//技术支持：www.openedv.com
//淘宝店铺：http://openedv.taobao.com
//关注微信公众平台微信号："正点原子"，免费获取ZYNQ & FPGA & STM32 & LINUX资料。
//版权所有，盗版必究。
//Copyright(C) 正点原子 2018-2028
//All rights reserved
//----------------------------------------------------------------------------------------
// File name:           emio_iic_cfg.c
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

#include"emio_iic_cfg.h"

#define  GPIOPS_ID  XPAR_XGPIOPS_0_DEVICE_ID  //PS 端 GPIO 器件 ID

static  XGpioPs  gpiops_inst; //PS 端 GPIO 驱动实例

//EMIO初始化
void emio_init(void)
{
	XGpioPs_Config *gpiops_cfg_ptr; //PS 端 GPIO 配置信息

	//根据器件 ID 查找配置信息
	gpiops_cfg_ptr = XGpioPs_LookupConfig(GPIOPS_ID);

	//初始化器件驱动
	XGpioPs_CfgInitialize(&gpiops_inst, gpiops_cfg_ptr, gpiops_cfg_ptr->BaseAddr);

	//设置 iic端口 为输出
	XGpioPs_SetDirectionPin(&gpiops_inst, EMIO_SCL_NUM, 1);
	XGpioPs_SetDirectionPin(&gpiops_inst, EMIO_SDA_NUM, 1);
	XGpioPs_SetDirectionPin(&gpiops_inst, EMIO_CT_RST_NUM, 1);

	//使能iic端口 输出
	XGpioPs_SetOutputEnablePin(&gpiops_inst, EMIO_SCL_NUM, 1);
	XGpioPs_SetOutputEnablePin(&gpiops_inst, EMIO_SDA_NUM, 1);
	XGpioPs_SetOutputEnablePin(&gpiops_inst, EMIO_CT_RST_NUM, 1);

	//将iic的SCLK和SDA都拉高
	XGpioPs_WritePin(&gpiops_inst, EMIO_SCL_NUM, 1);
	XGpioPs_WritePin(&gpiops_inst, EMIO_SDA_NUM, 1);
}

//设置 iic的SDA端口为输入
void  SDA_IN( void )
{
	XGpioPs_SetOutputEnablePin (&gpiops_inst, EMIO_SDA_NUM, 0);
	XGpioPs_SetDirectionPin    (&gpiops_inst, EMIO_SDA_NUM, 0);
}

//设置 iic的SDA端口为输出
void  SDA_OUT( void )
{
	XGpioPs_SetDirectionPin    (&gpiops_inst, EMIO_SDA_NUM, 1);  //SDA设置为输出
	XGpioPs_SetOutputEnablePin (&gpiops_inst, EMIO_SDA_NUM, 1);
}

//赋值 iic的SCL端口
void  IIC_SCL( u8 x )
{
	XGpioPs_WritePin(&gpiops_inst, EMIO_SCL_NUM, x);
}

//赋值 iic的SDA端口
void  IIC_SDA( u8 x )
{
	XGpioPs_WritePin(&gpiops_inst, EMIO_SDA_NUM, x);
}

//读取 iic的SDA端口
u8  READ_SDA ( void )
{
	return  XGpioPs_ReadPin(&gpiops_inst, EMIO_SDA_NUM) ;
} 

//赋值 触摸芯片的RST端口
void  CT_RST( u8 x )
{
	XGpioPs_WritePin(&gpiops_inst, EMIO_CT_RST_NUM, x);
}

//设置触摸芯片的INT端口的方向
void  INT_DIR( u8 x )
{

	XGpioPs_SetDirectionPin(&gpiops_inst, EMIO_CT_INT_NUM, x);
	XGpioPs_SetOutputEnablePin(&gpiops_inst, EMIO_CT_INT_NUM, x);
}

//赋值触摸芯片的INT端口
void  INT( u8 x )
{
	XGpioPs_WritePin(&gpiops_inst, EMIO_CT_INT_NUM, x);
}

//读取触摸芯片的INT端口
u8  INT_RD( void )
{
	return  XGpioPs_ReadPin(&gpiops_inst, EMIO_CT_INT_NUM) ;
}

