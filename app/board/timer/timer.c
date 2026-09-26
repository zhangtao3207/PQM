#include "timer.h"
#include "lvgl.h"
#include "xil_cache.h"

#define TIMER_DEVICE_ID     XPAR_XSCUTIMER_0_DEVICE_ID   //定时器ID
#define INTC_DEVICE_ID      XPAR_SCUGIC_SINGLE_DEVICE_ID //中断ID
#define TIMER_IRPT_INTR     XPAR_SCUTIMER_INTR           //定时器中断ID

//私有定时器的时钟频率 = CPU时钟频率/2 = 333MHz
//0.001s(1ms)   0.001*1000_000_000/(1000/333) - 1 = 0x514c7
#define TIMER_LOAD_VALUE    0x514c7                      //定时器装载值

XScuTimer Timer;            //定时器驱动程序实例

//定时器初始化程序 
int timer_init(XScuGic *intc_ptr)  //,XScuTimer *timer_ptr
{
	int status;
    //私有定时器初始化
    XScuTimer_Config *timer_cfg_ptr;
    timer_cfg_ptr = XScuTimer_LookupConfig(TIMER_DEVICE_ID);
    if (NULL == timer_cfg_ptr)
        return XST_FAILURE;
    status = XScuTimer_CfgInitialize(&Timer, timer_cfg_ptr,timer_cfg_ptr->BaseAddr);
        if (status != XST_SUCCESS) {
        xil_printf("Timer Initial Failed\r\n");
        return XST_FAILURE;
    }
    XScuTimer_LoadTimer(&Timer, TIMER_LOAD_VALUE); // 加载计数周期
    XScuTimer_EnableAutoReload(&Timer);            // 设置自动装载模式

    
    //初始化中断控制器
    XScuGic_Config *intc_cfg_ptr;
    intc_cfg_ptr = XScuGic_LookupConfig(INTC_DEVICE_ID);
    XScuGic_CfgInitialize(intc_ptr, intc_cfg_ptr,intc_cfg_ptr->CpuBaseAddress);
    //设置并打开中断异常处理功能
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT,
            (Xil_ExceptionHandler)XScuGic_InterruptHandler, intc_ptr);
    Xil_ExceptionEnable();

    //设置定时器中断
    XScuGic_Connect(intc_ptr, TIMER_IRPT_INTR,
          (Xil_ExceptionHandler)timer_intr_handler, (void *)(&Timer));

    XScuGic_Enable(intc_ptr, TIMER_IRPT_INTR); //使能GIC中的定时器中断
    XScuTimer_EnableInterrupt(&Timer);      //使能定时器中断
    
    XScuTimer_Start(&Timer);         //启动定时器
    return XST_SUCCESS;
}

//定时器中断处理程序
void timer_intr_handler(void *CallBackRef)
{
	static int ms_cnt = 0;
	XScuTimer *timer_ptr = (XScuTimer *) CallBackRef;

    lv_tick_inc(1); /* lvgl 的 1ms 心跳 */
    ms_cnt++;
    if(ms_cnt == 5)
    {
    	ms_cnt = 0;
    	Xil_DCacheFlush();     //刷新Cache，数据更新至内存
    }
    //清除定时器中断标志
    XScuTimer_ClearInterruptStatus(timer_ptr);
}
