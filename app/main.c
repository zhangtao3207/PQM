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
#include "lv_port_indev_template.h"
#include "lv_port_disp_template.h"
#include "lv_demo_music.h"

//宏定义
#define BYTES_PIXEL        3                          //像素字节数，RGB888占3个字节
#define CLK_WIZ_ID         XPAR_CLK_WIZ_0_DEVICE_ID   //时钟IP核器件ID
#define VDMA_ID            XPAR_AXIVDMA_0_DEVICE_ID   //VDMA器件ID
#define DISP_VTC_ID        XPAR_VTC_0_DEVICE_ID       //VTC器件ID
#define AXI_GPIO_0_ID      XPAR_AXI_GPIO_0_DEVICE_ID  //AXI GPIO 0(lcd_id)器件ID
#define AXI_GPIO_0_CHANEL  1                          //AXI GPIO(lcd_id)通道1

//函数声明
void gui_draw_hline(u16 x0, u16 y0, u16 len, u16 color); //画水平线
void gui_fill_circle(u16 x0, u16 y0, u16 r, u16 color);  //画实心圆
void ctp_test(void); //电容触摸屏测试函数
void lcd_draw_bline(u16 x1, u16 y1, u16 x2, u16 y2, u8 size, u16 color); //画线函数
void frame_data_fill(u8 *frame,  u16 sx,  u16 sy,  u16 ex,  u16 ey,  u16 color,  u32 stride);
void colorbar(u8 *frame, u32 width, u32 height, u32 stride);


//10个触控点的颜色(电容触摸屏用)
const u16 POINT_COLOR_TBL[10] = {
    MLCD_RED,  MLCD_GREEN, MLCD_BLUE,      MLCD_BROWN, MLCD_GRED,
    MLCD_BRED, MLCD_GBLUE, MLCD_LIGHTBLUE, MLCD_BRRED, MLCD_GRAY
};

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

    lv_demo_music();                   /* 官方例程测试 */
    while(1)
    {
    	lv_task_handler();
    }

    return 0;
}
