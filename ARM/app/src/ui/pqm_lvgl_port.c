/*
 * LVGL到PQM硬件显示/触摸驱动的适配层。
 *
 * 将LVGL绘制目标绑定到VDMA双帧缓存，在刷新完成时请求换帧，并把触摸驱动
 * 发布的最新触点转换为LVGL输入事件。所有接口由UI任务调用。
 */
#include "pqm_lvgl_port.h"

#include <stddef.h>

#include "FreeRTOS.h"
#include "task.h"
#include "xstatus.h"

#define PQM_LVGL_FLUSH_TIMEOUT_TICKS pdMS_TO_TICKS(100u)

static void pqm_lvgl_touch_read(lv_indev_drv_t *driver, lv_indev_data_t *data)
{
    pqm_lvgl_port_t *port = (pqm_lvgl_port_t *)driver->user_data;
    pqm_touch_point_t point;

    pqm_touch_get_point(port->touch, &point);
    data->point.x = (lv_coord_t)point.x;
    data->point.y = (lv_coord_t)point.y;
    data->state = point.pressed ? LV_INDEV_STATE_PR : LV_INDEV_STATE_REL;
}

static void pqm_lvgl_flush(lv_disp_drv_t *driver, const lv_area_t *area,
                           lv_color_t *color_buffer)
{
    pqm_lvgl_port_t *port = (pqm_lvgl_port_t *)driver->user_data;
    uint8_t framebuffer_index;
    int status;

    if (color_buffer == (lv_color_t *)pqm_video_framebuffer(0u)) {
        framebuffer_index = 0u;
    } else if (color_buffer == (lv_color_t *)pqm_video_framebuffer(1u)) {
        framebuffer_index = 1u;
    } else {
        lv_disp_flush_ready(driver);
        return;
    }

    pqm_video_clean_area(framebuffer_index,
                         (uint16_t)area->x1, (uint16_t)area->y1,
                         (uint16_t)area->x2, (uint16_t)area->y2);
    status = pqm_video_request_frame(port->video, framebuffer_index);
    if (status != XST_SUCCESS) {
        lv_disp_flush_ready(driver);
        return;
    }
    port->flush_started = xTaskGetTickCount();
    port->flush_pending = true;
}

bool pqm_lvgl_port_initialize(pqm_lvgl_port_t *port, pqm_video_t *video)
{
    if (port == NULL || video == NULL || sizeof(lv_color_t) != sizeof(uint16_t)) {
        return false;
    }

    port->video = video;
    port->touch = NULL;
    port->input_device = NULL;
    port->flush_pending = false;
    port->flush_started = 0u;

    lv_init();
    lv_disp_draw_buf_init(
        &port->draw_buffer,
        (lv_color_t *)pqm_video_framebuffer(0u),
        (lv_color_t *)pqm_video_framebuffer(1u),
        PQM_LCD_WIDTH * PQM_LCD_HEIGHT);
    lv_disp_drv_init(&port->display_driver);
    port->display_driver.hor_res = PQM_LCD_WIDTH;
    port->display_driver.ver_res = PQM_LCD_HEIGHT;
    port->display_driver.full_refresh = 1u;
    port->display_driver.draw_buf = &port->draw_buffer;
    port->display_driver.flush_cb = pqm_lvgl_flush;
    port->display_driver.user_data = port;
    port->display = lv_disp_drv_register(&port->display_driver);
    return port->display != NULL;
}

bool pqm_lvgl_port_attach_touch(pqm_lvgl_port_t *port, pqm_touch_t *touch)
{
    if (port == NULL || touch == NULL) {
        return false;
    }
    port->touch = touch;
    lv_indev_drv_init(&port->input_driver);
    port->input_driver.type = LV_INDEV_TYPE_POINTER;
    port->input_driver.read_cb = pqm_lvgl_touch_read;
    port->input_driver.user_data = port;
    port->input_device = lv_indev_drv_register(&port->input_driver);
    return port->input_device != NULL;
}

void pqm_lvgl_port_process(pqm_lvgl_port_t *port)
{
    uint8_t front_index;

    if (port == NULL || !port->flush_pending) {
        return;
    }
    if (pqm_video_take_switch_complete(port->video, &front_index)) {
        (void)front_index;
        port->flush_pending = false;
        lv_disp_flush_ready(&port->display_driver);
        return;
    }
    if ((xTaskGetTickCount() - port->flush_started) >=
        PQM_LVGL_FLUSH_TIMEOUT_TICKS) {
        (void)pqm_video_restart(port->video);
        port->flush_pending = false;
        lv_disp_flush_ready(&port->display_driver);
    }
}
