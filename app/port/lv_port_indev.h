/*
 * LVGL 触摸输入接口适配。
 *
 * 基于官方 37_zynq_lvgl 例程的 lv_port_indev_template.c/.h 重写：读取逻辑
 * 保持一致，只把 include 路径与文件名改成本工程的结构。
 */

#ifndef __LV_PORT_INDEV_H__
#define __LV_PORT_INDEV_H__

#include "lvgl.h"

void lv_port_indev_init(void);

#endif /* __LV_PORT_INDEV_H__ */
