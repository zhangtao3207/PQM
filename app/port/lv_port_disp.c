#if 1

#include "lv_port_disp_template.h"
#include "../../lvgl.h"
#include "../../../../../src/display_ctrl/display_ctrl.h"


#define MY_DISP_HOR_RES (800)   /* ÆÁÄ»¿í¶È */
#define MY_DISP_VER_RES (480)   /* ÆÁÄ»¸ß¶È */


extern VideoMode    vd_mode;
extern unsigned int const frame_buffer_addr;

static void disp_init(void);

static void disp_flush(lv_disp_drv_t * disp_drv, const lv_area_t * area, lv_color_t * color_p);

void lv_port_disp_init(void)
{
    disp_init();

    /* Example for 1) */
    static lv_disp_draw_buf_t draw_buf_dsc_1;
    static lv_color_t buf_1[MY_DISP_HOR_RES * MY_DISP_VER_RES];                          /*A buffer for 10 rows*/
    lv_disp_draw_buf_init(&draw_buf_dsc_1, buf_1, NULL, MY_DISP_HOR_RES * MY_DISP_VER_RES);   /*Initialize the display buffer*/

    static lv_disp_drv_t disp_drv;                         /*Descriptor of a display driver*/
    lv_disp_drv_init(&disp_drv);                    /*Basic initialization*/

    /*Set up the functions to access to your display*/

    /*Set the resolution of the display*/
    disp_drv.hor_res = vd_mode.width;
    disp_drv.ver_res = vd_mode.height;

    /*Used to copy the buffer's content to the display*/
    disp_drv.flush_cb = disp_flush;

    /*Set a display buffer*/
    disp_drv.draw_buf = &draw_buf_dsc_1;

    /*Finally register the driver*/
    lv_disp_drv_register(&disp_drv);
}

/*Initialize your display and the required peripherals.*/
static void disp_init(void)
{
    /*You code here*/
}

static void disp_flush(lv_disp_drv_t * disp_drv, const lv_area_t * area, lv_color_t * color_p)
{
    /*The most simple case (but also the slowest) to put all pixels to the screen one-by-one*/


    uint16_t x;
    uint16_t y;
    uint32_t color_index = 0;
    uint8_t * lcd_base_addr = (uint8_t *)frame_buffer_addr;
    uint8_t * color_p_t = (uint8_t *)color_p;

    for(y = area->y1; y <= area->y2; y++)
    {
        for(x = area->x1; x <= area->x2; x++)
         {
            /*Put a pixel to the display. For example:*/
        	/*put_px(x, y, *color_p)*/
            lcd_base_addr[y*vd_mode.width*3+x*3] = color_p_t[color_index+0];
            lcd_base_addr[y*vd_mode.width*3+x*3+1] = color_p_t[color_index+1];
            lcd_base_addr[y*vd_mode.width*3+x*3+2] = color_p_t[color_index+2];
            color_index = color_index + 4;
         }
     }

    /*IMPORTANT!!!
     *Inform the graphics library that you are ready with the flushing*/
    lv_disp_flush_ready(disp_drv);
}

#else /*Enable this file at the top*/

/*This dummy typedef exists purely to silence -Wpedantic.*/
typedef int keep_pedantic_happy;
#endif
