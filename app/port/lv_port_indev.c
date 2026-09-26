/*
 * LVGL 触摸输入接口适配。
 *
 * LVGL 周期调用 touchpad_read，这里每次都让触摸驱动扫一次屏，把按下的坐标
 * 交给图形库。
 */

#if 1

#include "lv_port_indev.h"

#include "TOUCH/touch.h"

static void touchpad_init(void);
static void touchpad_read(lv_indev_drv_t * indev_drv, lv_indev_data_t * data);
static bool touchpad_is_pressed(void);
static void touchpad_get_xy(lv_coord_t * x, lv_coord_t * y);

lv_indev_t * indev_touchpad;

void lv_port_indev_init(void)
{

    static lv_indev_drv_t indev_drv;

    /* 初始化触摸控制器 */
    touchpad_init();

    /* 注册触摸输入设备 */
    lv_indev_drv_init(&indev_drv);
    indev_drv.type = LV_INDEV_TYPE_POINTER;
    indev_drv.read_cb = touchpad_read;
    indev_touchpad = lv_indev_drv_register(&indev_drv);
}

/*Initialize your touchpad*/
static void touchpad_init(void)
{
    /* 触摸控制器初始化 */
	tp_dev.init();
}

/*Will be called by the library to read the touchpad*/
static void touchpad_read(lv_indev_drv_t * indev_drv, lv_indev_data_t * data)
{
    static lv_coord_t last_x = 0;
    static lv_coord_t last_y = 0;

    /* 只在按下时更新坐标，松开时沿用最后一次的坐标 */
    if(touchpad_is_pressed()) {
        touchpad_get_xy(&last_x, &last_y);
        data->state = LV_INDEV_STATE_PR;
    } else {
        data->state = LV_INDEV_STATE_REL;
    }

    /*Set the last pressed coordinates*/
    data->point.x = last_x;
    data->point.y = last_y;
}

/*Return true is the touchpad is pressed*/
static bool touchpad_is_pressed(void)
{
    /* 扫描当前触摸屏状态 */
	tp_dev.scan();

	if (tp_dev.sta & TP_PRES_DOWN)
	{
		return true;
	}

    return false;
}

/*Get the x and y coordinates if the touchpad is pressed*/
static void touchpad_get_xy(lv_coord_t * x, lv_coord_t * y)
{
    (*x) = tp_dev.x[0];
    (*y) = tp_dev.y[0];
}

#else /*Enable this file at the top*/

/*This dummy typedef exists purely to silence -Wpedantic.*/
typedef int keep_pedantic_happy;
#endif
