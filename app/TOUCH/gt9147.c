// ****************************************Copyright (c)***********************************//
//原子哥在线教学平台：www.yuanzige.com
//技术支持：www.openedv.com
//淘宝店铺：http://openedv.taobao.com
//关注微信公众平台微信号："正点原子"，免费获取ZYNQ & FPGA & STM32 & LINUX资料。
//版权所有，盗版必究。
//Copyright(C) 正点原子 2018-2028
//All rights reserved
//----------------------------------------------------------------------------------------
// File name:           gt9147
// Last modified Date:  2019/07/26 16:04:03
// Last Version:        V1.0
// Descriptions:        4.3寸电容触摸屏-GT9147驱动代码
//----------------------------------------------------------------------------------------
// Created by:          正点原子
// Created date:        2019/07/26 16:04:07
// Version:             V1.0
// Descriptions:        The original version
//
//----------------------------------------------------------------------------------------
//****************************************************************************************//

#include "gt9147.h"
#include "touch.h"
#include "myiic.h"
#include "../APP/delay.h"
#include "string.h"
#include "../main.h"
#include "../emio_iic_cfg/emio_iic_cfg.h"

//GT9147配置参数表
//第一个字节为版本号(0X60),必须保证新的版本号大于等于GT9147内部
//flash原有版本号,才会更新配置.
const u8 GT9147_CFG_TBL[]= {
    0X60,0XE0,0X01,0X20,0X03,0X05,0X35,0X00,0X02,0X08,
    0X1E,0X08,0X50,0X3C,0X0F,0X05,0X00,0X00,0XFF,0X67,
    0X50,0X00,0X00,0X18,0X1A,0X1E,0X14,0X89,0X28,0X0A,
    0X30,0X2E,0XBB,0X0A,0X03,0X00,0X00,0X02,0X33,0X1D,
    0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X32,0X00,0X00,
    0X2A,0X1C,0X5A,0X94,0XC5,0X02,0X07,0X00,0X00,0X00,
    0XB5,0X1F,0X00,0X90,0X28,0X00,0X77,0X32,0X00,0X62,
    0X3F,0X00,0X52,0X50,0X00,0X52,0X00,0X00,0X00,0X00,
    0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
    0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X0F,
    0X0F,0X03,0X06,0X10,0X42,0XF8,0X0F,0X14,0X00,0X00,
    0X00,0X00,0X1A,0X18,0X16,0X14,0X12,0X10,0X0E,0X0C,
    0X0A,0X08,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
    0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
    0X00,0X00,0X29,0X28,0X24,0X22,0X20,0X1F,0X1E,0X1D,
    0X0E,0X0C,0X0A,0X08,0X06,0X05,0X04,0X02,0X00,0XFF,
    0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
    0X00,0XFF,0XFF,0XFF,0XFF,0XFF,0XFF,0XFF,0XFF,0XFF,
    0XFF,0XFF,0XFF,0XFF,
};
//发送GT9147配置参数
//mode:0,参数不保存到flash
//     1,参数保存到flash
u8 GT9147_Send_Cfg(u8 mode)
{
    u8 buf[2];
    u8 i=0;
    buf[0]=0;
    buf[1]=mode;    //是否写入到GT9147 FLASH?  即是否掉电保存
    for(i=0; i<sizeof(GT9147_CFG_TBL); i++)
        buf[0]+=GT9147_CFG_TBL[i]; //计算校验和
    buf[0]=(~buf[0])+1;
    GT9147_WR_Reg(GT_CFGS_REG,(u8*)GT9147_CFG_TBL,sizeof(GT9147_CFG_TBL));//发送寄存器配置
    GT9147_WR_Reg(GT_CHECK_REG,buf,2);//写入校验和,和配置更新标记
    return 0;
}
//向GT9147写入一次数据
//reg:起始寄存器地址
//buf:数据缓缓存区
//len:写数据长度
//返回值:0,成功;1,失败.
u8 GT9147_WR_Reg(u16 reg,u8 *buf,u8 len)
{
    u8 i;
    u8 ret=0;
    IIC_Start();
    IIC_Send_Byte(GT_CMD_WR);   //发送写命令
    IIC_Wait_Ack();
    IIC_Send_Byte(reg>>8);      //发送高8位地址
    IIC_Wait_Ack();
    IIC_Send_Byte(reg&0XFF);    //发送低8位地址
    IIC_Wait_Ack();
    for(i=0; i<len; i++) {
        IIC_Send_Byte(buf[i]);  //发数据
        ret=IIC_Wait_Ack();
        if(ret)
            break;
    }
    IIC_Stop();                 //产生一个停止条件
    return ret;
}
//从GT9147读出一次数据
//reg:起始寄存器地址
//buf:数据缓缓存区
//len:读数据长度
void GT9147_RD_Reg(u16 reg,u8 *buf,u8 len)
{
    u8 i;
    IIC_Start();
    IIC_Send_Byte(GT_CMD_WR);   //发送写命令
    IIC_Wait_Ack();
    IIC_Send_Byte(reg>>8);      //发送高8位地址
    IIC_Wait_Ack();
    IIC_Send_Byte(reg&0XFF);    //发送低8位地址
    IIC_Wait_Ack();
    IIC_Start();
    IIC_Send_Byte(GT_CMD_RD);   //发送读命令
    IIC_Wait_Ack();
    for(i=0; i<len; i++) {
        buf[i]=IIC_Read_Byte(i==(len-1)?0:1); //发数据
    }
    IIC_Stop();//产生一个停止条件
}
//初始化GT9147触摸屏
//返回值:0,初始化成功;1,初始化失败
u8 GT9147_Init(void)
{
    u8 temp[5];
    INT_DIR(1);      //TOUCH_INT引脚设置为输出
    INT(1);          //TOUCH_INT输出为1
    IIC_Init();      //初始化电容屏的I2C总线
    CT_RST(0);       //复位
    delay_ms(10);
    CT_RST(1);       //释放复位
    delay_ms(10);
    INT_DIR(0);
    delay_ms(100);
    GT9147_RD_Reg(GT_PID_REG,temp,4);      //读取产品ID
    temp[4]=0;
    xil_printf("CTP ID:%s\r\n",temp);      //打印ID
    if(strcmp((char*)temp,"9147")==0) {    //ID==9147
        temp[0]=0X02;
        GT9147_WR_Reg(GT_CTRL_REG,temp,1); //软复位GT9147
        GT9147_RD_Reg(GT_CFGS_REG,temp,1); //读取GT_CFGS_REG寄存器
        if(temp[0]<0X60) {                 //默认版本比较低,需要更新flash配置
            if(lcd_id==0X5510)
                GT9147_Send_Cfg(1);        //仅4.3寸MCU屏,更新并保存配置
        }
        delay_ms(10);
        temp[0]=0X00;
        GT9147_WR_Reg(GT_CTRL_REG,temp,1); //结束复位
        return 0;
    }
    return 0;
}

const u16 GT9147_TPX_TBL[5]= {GT_TP1_REG,GT_TP2_REG,GT_TP3_REG,GT_TP4_REG,GT_TP5_REG};


//扫描触摸屏(采用查询方式)
//mode:0,正常扫描.
//返回值:当前触屏状态.
//0,触屏无触摸;1,触屏有触摸
u8 GT9147_Scan(u8 mode)
{
    u8 buf[4];
    u8 i=0;
    u8 res=0;
    u16 temp;
    u16 tempsta;
    static u8 t=0;//控制查询间隔,从而降低CPU占用率
    t++;
    if((t%10)==0||t<10)//空闲时,每进入10次CTP_Scan函数才检测1次,从而节省CPU使用率
    {
        GT9147_RD_Reg(GT_GSTID_REG,&mode,1);    //读取触摸点的状态
        if(mode&0X80&&((mode&0XF)<6))
        {
            i=0;
            GT9147_WR_Reg(GT_GSTID_REG,&i,1);//清标志
        }
        if((mode&0XF)&&((mode&0XF)<6))
        {
            temp=0XFFFF<<(mode&0XF);    //将点的个数转换为1的位数,匹配tp_dev.sta定义
            tempsta=tp_dev.sta;         //保存当前的tp_dev.sta值
            tp_dev.sta=(~temp)|TP_PRES_DOWN|TP_CATH_PRES;
            tp_dev.x[4]=tp_dev.x[0];    //保存触点0的数据
            tp_dev.y[4]=tp_dev.y[0];
            for(i=0;i<5;i++)
            {
                if(tp_dev.sta&(1<<i))   //触摸有效?
                {
                    GT9147_RD_Reg(GT9147_TPX_TBL[i],buf,4); //读取XY坐标值
                    if(lcd_id==0X4384)   //4.3寸800*480 RGB屏
                    {
                        if(tp_dev.touchtype&0X01)//横屏
                        {
                            tp_dev.x[i]=((u16)buf[1]<<8)+buf[0];
                            tp_dev.y[i]=((u16)buf[3]<<8)+buf[2];

                        }else
                        {
                            tp_dev.y[i]=((u16)buf[1]<<8)+buf[0];
                            tp_dev.x[i]=480-(((u16)buf[3]<<8)+buf[2]);
                        }
                    }else if(lcd_id==0X4342) //4.3寸480*272 RGB屏
                    {
                        if(tp_dev.touchtype&0X01)//横屏
                        {
                            tp_dev.x[i]=(((u16)buf[1]<<8)+buf[0]);
                            tp_dev.y[i]=(((u16)buf[3]<<8)+buf[2]);
                        }else
                        {
                            tp_dev.y[i]=((u16)buf[1]<<8)+buf[0];
                            tp_dev.x[i]=272-(((u16)buf[3]<<8)+buf[2]);
                        }
                    }
                }
            }
            res=1;
            if(tp_dev.x[0] > vd_mode.height || tp_dev.y[0] > vd_mode.width)  //非法数据(坐标超出了)
            {
                if((mode&0XF)>1)        //有其他点有数据,则复第二个触点的数据到第一个触点.
                {
                    tp_dev.x[0]=tp_dev.x[1];
                    tp_dev.y[0]=tp_dev.y[1];
                    t=0;                //触发一次,则会最少连续监测10次,从而提高命中率
                }else                   //非法数据,则忽略此次数据(还原原来的)
                {
                    tp_dev.x[0]=tp_dev.x[4];
                    tp_dev.y[0]=tp_dev.y[4];
                    mode=0X80;
                    tp_dev.sta=tempsta; //恢复tp_dev.sta
                }
            }else t=0;                  //触发一次,则会最少连续监测10次,从而提高命中率
        }
    }
    if((mode&0X8F)==0X80)//无触摸点按下
    {
        if(tp_dev.sta&TP_PRES_DOWN)     //之前是被按下的
        {
            tp_dev.sta&=~TP_PRES_DOWN;  //标记按键松开
        }else                           //之前就没有被按下
        {
            tp_dev.x[0]=0xffff;
            tp_dev.y[0]=0xffff;
            tp_dev.sta&=0XE000;         //清除点有效标记
        }
    }
    if(t>240)t=10;//重新从10开始计数
    return res;
}
