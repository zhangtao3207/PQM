/*
 * LVGL 显示接口适配。
 *
 * 在内存里开一块 800×480 的绘制缓冲交给 LVGL，刷屏时把每个像素的前三个字节
 * 按 RGB888 写进 VDMA 正在扫描的帧缓存。帧缓存的地址与行宽来自显示控制器
 * 驱动，本文件不自行假设。
 */

#if 1

#include "lv_port_disp.h"

#include "display_ctrl/display_ctrl.h"

#define MY_DISP_HOR_RES (800)   /* 屏幕宽度 */
#define MY_DISP_VER_RES (480)   /* 屏幕高度 */

extern VideoMode    vd_mode;
extern unsigned int const frame_buffer_addr;

static void disp_init(void);

static void disp_flush(lv_disp_drv_t * disp_drv, const lv_area_t * area, lv_color_t * color_p);

void lv_port_disp_init(void)
{
    disp_init();

    static lv_disp_draw_buf_t draw_buf_dsc_1;
    static lv_color_t buf_1[MY_DISP_HOR_RES * MY_DISP_VER_RES];
    lv_disp_draw_buf_init(&draw_buf_dsc_1, buf_1, NULL, MY_DISP_HOR_RES * MY_DISP_VER_RES);

    static lv_disp_drv_t disp_drv;
    lv_disp_drv_init(&disp_drv);

    /* 屏幕分辨率取自当前显示模式 */
    disp_drv.hor_res = vd_mode.width;
    disp_drv.ver_res = vd_mode.height;

    /* 把绘制缓冲的内容送到屏幕 */
    disp_drv.flush_cb = disp_flush;

    disp_drv.draw_buf = &draw_buf_dsc_1;

    lv_disp_drv_register(&disp_drv);
}

/* 显示外设已经由 main 里的显示控制器初始化完成，这里不需要额外动作。 */
static void disp_init(void)
{
}

static void disp_flush(lv_disp_drv_t * disp_drv, const lv_area_t * area, lv_color_t * color_p)
{
    /* 逐像素拷贝：LVGL 的 32 位颜色每个像素占 4 字节，帧缓存是每像素 3 字节。 */

    uint16_t x;
    uint16_t y;
    uint32_t color_index = 0;
    uint8_t * lcd_base_addr = (uint8_t *)frame_buffer_addr;
    uint8_t * color_p_t = (uint8_t *)color_p;

    for(y = area->y1; y <= area->y2; y++)
    {
        for(x = area->x1; x <= area->x2; x++)
         {
            lcd_base_addr[y*vd_mode.width*3+x*3] = color_p_t[color_index+0];
            lcd_base_addr[y*vd_mode.width*3+x*3+1] = color_p_t[color_index+1];
            lcd_base_addr[y*vd_mode.width*3+x*3+2] = color_p_t[color_index+2];
            color_index = color_index + 4;
         }
     }

    /* 告知图形库本次刷屏已经完成 */
    lv_disp_flush_ready(disp_drv);
}

#else /*Enable this file at the top*/

/*This dummy typedef exists purely to silence -Wpedantic.*/
typedef int keep_pedantic_happy;
#endif
