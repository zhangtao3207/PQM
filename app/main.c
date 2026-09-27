/*
 * PQM2 应用入口。
 *
 * 初始化顺序与官方 37_zynq_lvgl 例程保持一致：配置时钟与显示控制器、启动
 * VDMA、初始化 LVGL 的显示与触摸接口，然后把界面交给 PQM 界面层。相对官方
 * 例程只改了两处：界面入口由示例的 lv_demo_music() 换成 PQMUI_Init()，主循环
 * 里追加一次共享内存轮询——界面上的测量值全部由 PL 实测、经 0x40000000 的
 * PS/PL 共享内存读回，不再有假数据源。示例中未被引用的绘图辅助函数声明与配色表已删除。
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "xil_types.h"
#include "xil_cache.h"
#include "xparameters.h"
#include "xgpio.h"
#include "xaxivdma.h"
#include "xaxivdma_i.h"
#include "display_ctrl/display_ctrl.h"
#include "emio_iic_cfg/emio_iic_cfg.h"
#include "vdma_api/vdma_api.h"
#include "APP/delay.h"
#include "TOUCH/touch.h"
#include "main.h"
#include "clk_wiz/clk_wiz.h"
#include "timer/timer.h"
#include "sleep.h"

/* LVGL */
#include "lvgl.h"
#include "port/lv_port_indev.h"
#include "port/lv_port_disp.h"

/* PQM 界面 */
#include "pqmui/pqmui.h"
#include "pqmshm/pqmshm.h"

//宏定义
#define BYTES_PIXEL        3                          //像素字节数，RGB888占3个字节
#define CLK_WIZ_ID         XPAR_CLK_WIZ_0_DEVICE_ID   //时钟IP核器件ID
#define VDMA_ID            XPAR_AXIVDMA_0_DEVICE_ID   //VDMA器件ID
#define DISP_VTC_ID        XPAR_VTC_0_DEVICE_ID       //VTC器件ID
#define AXI_GPIO_0_ID      XPAR_AXI_GPIO_0_DEVICE_ID  //AXI GPIO 0(lcd_id)器件ID
#define AXI_GPIO_0_CHANEL  1                          //AXI GPIO(lcd_id)通道1

//全局变量
XAxiVdma     vdma;
DisplayCtrl  dispCtrl;
XGpio        axi_gpio_inst;   //PL端 AXI GPIO 驱动实例
VideoMode    vd_mode;
XScuGic      Intc;            //中断控制器驱动程序实例
//frame buffer的起始地址
unsigned int const frame_buffer_addr = (XPAR_PS7_DDR_0_S_AXI_BASEADDR + 0x1000000);
unsigned int lcd_id=0;        //LCD ID

int main(void)
{
	timer_init(&Intc);
    //获取LCD的ID
    XGpio_Initialize(&axi_gpio_inst,AXI_GPIO_0_ID);
    XGpio_SetDataDirection(&axi_gpio_inst,AXI_GPIO_0_CHANEL,0x07); //设置AXI GPIO为输入
    lcd_id = lcd_id_read(&axi_gpio_inst,AXI_GPIO_0_CHANEL);
    XGpio_SetDataDirection(&axi_gpio_inst,AXI_GPIO_0_CHANEL,0x00); //设置AXI GPIO为输出
    xil_printf("LCD ID: %x\r\n",lcd_id);

    //根据获取的LCD的ID号来进行video参数的选择
    switch(lcd_id){
        case 0x4342 : vd_mode = VMODE_480x272; break;  //4.3寸屏,480*272分辨率
        case 0x4384 : vd_mode = VMODE_800x480; break;  //4.3寸屏,800*480分辨率
        case 0x7084 : vd_mode = VMODE_800x480; break;  //7寸屏,800*480分辨率
        case 0x7016 : vd_mode = VMODE_1024x600; break; //7寸屏,1024*600分辨率
        case 0x1018 : vd_mode = VMODE_1280x800; break; //10.1寸屏,1280*800分辨率
        default : vd_mode = VMODE_800x480; break;
    }

    emio_init();

    //配置VDMA
    run_vdma_frame_buffer(&vdma, VDMA_ID, vd_mode.width, vd_mode.height,
                            frame_buffer_addr,0, 0,ONLY_READ);

    //设置时钟IP核输出的时钟频率
    clk_wiz_cfg(CLK_WIZ_ID,vd_mode.freq);
    //初始化Display controller
    DisplayInitialize(&dispCtrl, DISP_VTC_ID);
    //设置VideoMode
    DisplaySetMode(&dispCtrl, &vd_mode);
    DisplayStart(&dispCtrl);

    lv_init();                          /* lvgl系统初始化 */
    lv_port_disp_init();                /* lvgl显示接口初始化,放在lv_init()的后面 */
    lv_port_indev_init();               /* lvgl输入接口初始化,放在lv_init()的后面 */

    PQMUI_Init();                       /* PQM界面初始化 */
    while(1)
    {
    	lv_task_handler();
        PQMUI_ShmPoll();                /* 读 PL 实测结果：PS/PL 共享内存 0x40000000 */
    }

    return 0;
}
