#ifndef PQM_LVGL_PORT_H
#define PQM_LVGL_PORT_H

#include <stdbool.h>

#include "lvgl.h"

#include "../drivers/pqm_video/pqm_video.h"

typedef struct {
    pqm_video_t *video;
    lv_disp_draw_buf_t draw_buffer;
    lv_disp_drv_t display_driver;
    lv_disp_t *display;
    TickType_t flush_started;
    bool flush_pending;
} pqm_lvgl_port_t;

bool pqm_lvgl_port_initialize(pqm_lvgl_port_t *port, pqm_video_t *video);
void pqm_lvgl_port_process(pqm_lvgl_port_t *port);

#endif
