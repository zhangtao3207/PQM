//****************************************Copyright (c)***********************************//
//原子哥在线教学平台：www.yuanzige.com
//技术支持：www.openedv.com
//淘宝店铺：http://openedv.taobao.com
//关注微信公众平台微信号："正点原子"，免费获取ZYNQ & FPGA & STM32 & LINUX资料。
//版权所有，盗版必究。
//Copyright(C) 正点原子 2018-2028
//All rights reserved
//----------------------------------------------------------------------------------------
// File name:           myiic
// Last modified Date:  2019/07/26 16:04:03
// Last Version:        V1.0
// Descriptions:        IIC 驱动代码
//----------------------------------------------------------------------------------------
// Created by:          正点原子
// Created date:        2019/07/26 16:04:03
// Version:             V1.0
// Descriptions:        The original version
//
//----------------------------------------------------------------------------------------
//****************************************************************************************//

#include "myiic.h"
#include"../emio_iic_cfg/emio_iic_cfg.h"

//控制I2C速度的延时
void CT_Delay(void)
{
    delay_us(2);
}

//初始化IIC
void IIC_Init(void)
{
    IIC_SCL(1);
    IIC_SDA(1);
}

//产生IIC起始信号
void IIC_Start(void)
{
    SDA_OUT();   //sda线输出
    IIC_SDA(1);
    IIC_SCL(1);
    CT_Delay();
    IIC_SDA(0);  //START信号:SCL为高时，SDA由高变低
    CT_Delay();
    IIC_SCL(0);  //钳住I2C总线，准备发送或接收数据
    CT_Delay();
}

//产生IIC停止信号
void IIC_Stop(void)
{
    SDA_OUT();  //sda线输出
    IIC_SCL(0);
    IIC_SDA(0); //STOP信号:SCL为高时，SDA由低变高
    CT_Delay();
    IIC_SCL(1);
    CT_Delay();
    IIC_SDA(1); //发送I2C总线结束信号
    CT_Delay();
}

//等待应答信号到来
//返回值：1，接收应答失败
//0，接收应答成功
u8 IIC_Wait_Ack(void)
{
    u8 ucErrTime=0;
    SDA_IN();      //SDA设置为输入
    IIC_SDA(1);
    CT_Delay();
    IIC_SCL(1);
    CT_Delay();
    while( READ_SDA() ) {
        ucErrTime++;
        if(ucErrTime>250) {
            IIC_Stop();
            return 1;
        }
    }
    IIC_SCL(0);//时钟输出0
    CT_Delay();
    return 0;
}

//产生ACK应答
void IIC_Ack(void)
{
    IIC_SCL(0);
    SDA_OUT();
    IIC_SDA(0);
    CT_Delay();
    IIC_SCL(1);
    CT_Delay();
    IIC_SCL(0);
    CT_Delay();
}

//不产生ACK应答
void IIC_NAck(void)
{
    IIC_SCL(0);
    SDA_OUT();
    IIC_SDA(1);
    CT_Delay();
    IIC_SCL(1);
    CT_Delay();
    IIC_SCL(0);
    CT_Delay();
}

//IIC发送一个字节
//返回从机有无应答
//1，有应答
//0，无应答
void IIC_Send_Byte(u8 txd)
{
    u8 t;
    SDA_OUT();
    IIC_SCL(0);//拉低时钟开始数据传输
    for(t=0; t<8; t++) {
        IIC_SDA((txd&0x80)>>7);
        txd<<=1;
        CT_Delay();
        IIC_SCL(1);
        CT_Delay();
        IIC_SCL(0);
        CT_Delay();
    }
}

//读1个字节，ack=1时，发送ACK，ack=0，发送nACK
u8 IIC_Read_Byte(unsigned char ack)
{
    unsigned char i,receive=0;
    SDA_IN();//SDA设置为输入
    for(i=0; i<8; i++ ) {
        IIC_SCL(0);
        CT_Delay();
        IIC_SCL(1);
        receive<<=1;
        if( READ_SDA() )
            receive++;
        CT_Delay();
    }
    if (!ack)
        IIC_NAck();//发送nACK
    else
        IIC_Ack(); //发送ACK
    return receive;
}
