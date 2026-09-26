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

#include "gt9271.h"
#include "touch.h"
#include "myiic.h"
#include "../APP/delay.h"
#include "string.h"
#include "../main.h"

//GT9271配置参数表
//第一个字节为版本号(0X41),必须保证新的版本号大于等于GT9271内部
//flash原有版本号,才会更新配置.
//分辨率1280*800
const u8 GT9271_CFG_TBL[]= {
    0x41,0x00,0x05,0x20,0x03,0x0A,0x3D,0x20,0x01,0x0A,
    0x28,0x0F,0x6E,0x5A,0x03,0x05,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x18,0x1A,0x1E,0x14,0x8F,0x2F,0xAA,
    0x26,0x24,0x0C,0x08,0x00,0x00,0x00,0x81,0x03,0x2D,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x1A,0x3C,0x94,0xC5,0x02,0x07,0x00,0x00,0x04,
    0x9E,0x1C,0x00,0x89,0x21,0x00,0x77,0x27,0x00,0x68,
    0x2E,0x00,0x5B,0x37,0x00,0x5B,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x19,0x18,0x17,0x16,0x15,0x14,0x11,0x10,
    0x0F,0x0E,0x0D,0x0C,0x09,0x08,0x07,0x06,0x05,0x04,
    0x01,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x02,0x04,0x06,0x07,0x08,0x0A,0x0C,
    0x0D,0x0F,0x10,0x11,0x12,0x13,0x14,0x19,0x1B,0x1C,
    0x1E,0x1F,0x20,0x21,0x22,0x23,0x24,0x25,0x26,0x27,
    0x28,0x29,0xFF,0xFF,0x00,0x00,0x00,0x00,0x00,0x00,
    0x00,0x00,0x00,0x00,0x5D,0x01
};

//发送GT9147配置参数
//mode:0,参数不保存到flash
//     1,参数保存到flash
u8 GT9271_Send_Cfg(u8 mode)
{
    u8 buf[2];
    u8 i=0;
    buf[0]=0;
    buf[1]=mode;    //是否写入到GT9271 FLASH?  即是否掉电保存
    for(i=0; i<(sizeof(GT9271_CFG_TBL)-2); i++)buf[0]+=GT9271_CFG_TBL[i];       //计算校验和
    buf[0]=(~buf[0])+1;
    GT9271_WR_Reg(GT9271_CFGS_REG,(u8*)GT9271_CFG_TBL,sizeof(GT9271_CFG_TBL));  //发送寄存器配置
    GT9271_WR_Reg(GT9271_CHECK_REG,buf,2);    //写入校验和,和配置更新标记
    return 0;
}


//向GT9271写入一次数据
//reg:起始寄存器地址
//buf:数据缓缓存区
//len:写数据长度
//返回值:0,成功;1,失败.
u8 GT9271_WR_Reg(u16 reg,u8 *buf,u8 len)
{
    u8 i;
    u8 ret=0;
    IIC_Start();
    IIC_Send_Byte(GT9271_CMD_WR);       //发送写命令
    IIC_Wait_Ack();
    IIC_Send_Byte(reg>>8);      //发送高8位地址
    IIC_Wait_Ack();
    IIC_Send_Byte(reg&0XFF);    //发送低8位地址
    IIC_Wait_Ack();
    for(i=0; i<len; i++) {
        IIC_Send_Byte(buf[i]);      //发数据
        ret=IIC_Wait_Ack();
        if(ret)break;
    }
    IIC_Stop();                 //产生一个停止条件
    return ret;
}
//从GT9271读出一次数据
//reg:起始寄存器地址
//buf:数据缓缓存区
//len:读数据长度
void GT9271_RD_Reg(u16 reg,u8 *buf,u8 len)
{
    u8 i;
    IIC_Start();
    IIC_Send_Byte(GT9271_CMD_WR);   //发送写命令
    IIC_Wait_Ack();
    IIC_Send_Byte(reg>>8);      //发送高8位地址
    IIC_Wait_Ack();
    IIC_Send_Byte(reg&0XFF);    //发送低8位地址
    IIC_Wait_Ack();
    IIC_Start();
    IIC_Send_Byte(GT9271_CMD_RD);   //发送读命令
    IIC_Wait_Ack();
    for(i=0; i<len; i++) {
        buf[i]=IIC_Read_Byte(i==(len-1)?0:1); //发数据
    }
    IIC_Stop();                 //产生一个停止条件
}
//初始化GT9271触摸屏
//返回值:0,初始化成功;1,初始化失败
u8 GT9271_Init(void)
{
    u8 temp[5];
    INT_DIR(1);
    INT(1);
    IIC_Init();         //初始化电容屏的I2C总线
    CT_RST(0);          //复位
    delay_ms(10);
    CT_RST(1);          //释放复位
    delay_ms(10);
    INT_DIR(0);
    delay_ms(100);
    GT9271_RD_Reg(GT9271_PID_REG,temp,4);       //读取产品ID
    temp[4]=0;
    xil_printf("CTP ID:%s\r\n\r\n",temp);           //打印ID
    if(strcmp((char*)temp,"9271")==0) {     //ID==9147
        temp[0]=0X02;
        GT9147_WR_Reg(GT9271_CTRL_REG,temp,1);  //软复位GT9271
        GT9147_RD_Reg(GT9271_CFGS_REG,temp,1);  //读取GT9271_CFGS_REG寄存器
        if(temp[0]<0X41) {                  //默认版本比较低,需要更新flash配置
        	xil_printf("Default Ver:%d\r\n",temp[0]);
            GT9271_Send_Cfg(1);                 //更新并保存配置
        }
        delay_ms(10);
        temp[0]=0X00;
        GT9147_WR_Reg(GT9271_CTRL_REG,temp,1);  //结束复位
        return 0;
    }
    return 1;
}

const u16 GT9271_TPX_TBL[10]= {
    GT9271_TP1_REG,GT9271_TP2_REG,GT9271_TP3_REG,GT9271_TP4_REG,GT9271_TP5_REG,
    GT9271_TP6_REG,GT9271_TP7_REG,GT9271_TP8_REG,GT9271_TP9_REG,GT9271_TP10_REG,
};
//扫描触摸屏(采用查询方式)
//mode:0,正常扫描.
//返回值:当前触屏状态.
//0,触屏无触摸;1,触屏有触摸
u8 GT9271_Scan(u8 mode)
{
    u8 buf[4];
    u8 i=0;
    u8 res=0;
    u16 temp;
    u16 tempsta;
    static u8 t=0;//控制查询间隔,从而降低CPU占用率
    t++;
    if((t%10)==0||t<10) { //空闲时,每进入10次CTP_Scan函数才检测1次,从而节省CPU使用率
        GT9271_RD_Reg(GT9271_GSTID_REG,&mode,1);    //读取触摸点的状态
        if((mode & 0X80) && ((mode&0XF)<11)) {
            i=0;
            GT9271_WR_Reg(GT9271_GSTID_REG,(u8*)&i,1);  //清标志
        }
        if((mode&0XF)&&((mode&0XF)<11)) {
            temp=0XFFFF<<(mode&0XF);    //将点的个数转换为1的位数,匹配tp_dev.sta定义
            tempsta=tp_dev.sta;         //保存当前的tp_dev.sta值
            tp_dev.sta=(~temp)|TP_PRES_DOWN|TP_CATH_PRES;
            tp_dev.x[9]=tp_dev.x[0];    //保存触点0的数据
            tp_dev.y[9]=tp_dev.y[0];
            for(i=0; i<10; i++) {
                if(tp_dev.sta&(1<<i)) { //触摸有效?
                    GT9271_RD_Reg(GT9271_TPX_TBL[i],buf,6); //读取XY坐标值
                    if(tp_dev.touchtype&0X01) { //横屏
                        tp_dev.y[i]=((u16)buf[3]<<8)+buf[2];
                        tp_dev.x[i]=((u16)buf[1]<<8)+buf[0];

                    } else {
                        tp_dev.x[i]=800-(((u16)buf[3]<<8)+buf[2]);
                        tp_dev.y[i]=((u16)buf[1]<<8)+buf[0];
                    }
                }
            }
            res=1;
            if( tp_dev.x[0] > vd_mode.height || tp_dev.y[0] > vd_mode.width ) { //非法数据(坐标超出了)
                if((mode&0XF)>1) {  //有其他点有数据,则复第二个触点的数据到第一个触点.
                    tp_dev.x[0]=tp_dev.x[1];
                    tp_dev.y[0]=tp_dev.y[1];
                    t=0;                //触发一次,则会最少连续监测10次,从而提高命中率
                } else {                //非法数据,则忽略此次数据(还原原来的)
                    tp_dev.x[0]=tp_dev.x[9];
                    tp_dev.y[0]=tp_dev.y[9];
                    mode=0X80;
                    tp_dev.sta=tempsta; //恢复tp_dev.sta
                }
            } else t=0;                 //触发一次,则会最少连续监测10次,从而提高命中率
        }
    }
    if((mode&0X8F)==0X80) { //无触摸点按下
        if(tp_dev.sta&TP_PRES_DOWN) {   //之前是被按下的
            tp_dev.sta&=~TP_PRES_DOWN;  //标记按键松开
        } else {                        //之前就没有被按下
            tp_dev.x[0]=0xffff;
            tp_dev.y[0]=0xffff;
            tp_dev.sta&=0XE000;         //清除点有效标记
        }
    }
    if(t>240)t=10;//重新从10开始计数
    return res;
}
