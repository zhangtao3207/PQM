/* PQM LVGL端口接口：连接LVGL、VDMA双帧缓存与触摸输入设备。 */
#ifndef PQM_LVGL_PORT_H
#define PQM_LVGL_PORT_H

#include <stdbool.h>

#include "lvgl.h"

#include "../drivers/pqm_video/pqm_video.h"
#include "../drivers/pqm_touch/pqm_touch.h"

typedef struct {
    pqm_video_t *video;
    lv_disp_draw_buf_t draw_buffer;
    lv_disp_drv_t display_driver;
    lv_disp_t *display;
    pqm_touch_t *touch;
    lv_indev_drv_t input_driver;
    lv_indev_t *input_device;
    TickType_t flush_started;
    bool flush_pending;
} pqm_lvgl_port_t;

/* 注册LVGL显示驱动并绑定VDMA双帧缓存。 */
bool pqm_lvgl_port_initialize(pqm_lvgl_port_t *port, pqm_video_t *video);
/* 注册LVGL指针输入设备并绑定触摸驱动。 */
bool pqm_lvgl_port_attach_touch(pqm_lvgl_port_t *port, pqm_touch_t *touch);
/* 处理换帧确认和刷新超时恢复，应由UI任务周期调用。 */
void pqm_lvgl_port_process(pqm_lvgl_port_t *port);

#endif
