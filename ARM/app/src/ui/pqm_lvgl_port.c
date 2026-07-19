#include "pqm_lvgl_port.h"

#include <stddef.h>

#include "FreeRTOS.h"
#include "task.h"
#include "xstatus.h"

#define PQM_LVGL_FLUSH_TIMEOUT_TICKS pdMS_TO_TICKS(100u)

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
