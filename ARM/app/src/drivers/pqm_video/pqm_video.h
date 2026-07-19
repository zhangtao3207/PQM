#ifndef PQM_VIDEO_H
#define PQM_VIDEO_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "FreeRTOS.h"
#include "task.h"
#include "xaxivdma.h"
#include "xscugic.h"

#define PQM_LCD_WIDTH       800u
#define PQM_LCD_HEIGHT      480u
#define PQM_LCD_STRIDE      (PQM_LCD_WIDTH * sizeof(uint16_t))
#define PQM_FB_BYTES        (PQM_LCD_WIDTH * PQM_LCD_HEIGHT * sizeof(uint16_t))
#define PQM_FB0_ADDR_VALUE  0x3E000000u
#define PQM_FB1_ADDR_VALUE  (PQM_FB0_ADDR_VALUE + PQM_FB_BYTES)
#define PQM_FB0_ADDR        ((UINTPTR)PQM_FB0_ADDR_VALUE)
#define PQM_FB1_ADDR        ((UINTPTR)PQM_FB1_ADDR_VALUE)

_Static_assert(PQM_FB_BYTES == 768000u, "unexpected RGB565 framebuffer size");
_Static_assert((PQM_FB0_ADDR_VALUE & 63u) == 0u, "framebuffer 0 alignment");
_Static_assert((PQM_FB1_ADDR_VALUE & 63u) == 0u, "framebuffer 1 alignment");

typedef enum {
    PQM_VIDEO_BLACK = 0x0000u,
    PQM_VIDEO_BLUE  = 0x001Fu,
    PQM_VIDEO_GREEN = 0x07E0u,
    PQM_VIDEO_RED   = 0xF800u,
    PQM_VIDEO_WHITE = 0xFFFFu
} pqm_video_color_t;

typedef struct {
    XAxiVdma instance;
    TaskHandle_t notify_task;
    volatile uint32_t frame_done_count;
    volatile uint32_t error_count;
    volatile uint8_t front_index;
    volatile uint8_t pending_index;
    volatile bool switch_pending;
    volatile bool switch_completed;
} pqm_video_t;

int pqm_video_initialize(pqm_video_t *video, TaskHandle_t notify_task);
int pqm_video_connect_interrupt(pqm_video_t *video,
                                XScuGic *interrupt_controller);
uint16_t *pqm_video_framebuffer(uint8_t index);
void pqm_video_fill(uint8_t index, pqm_video_color_t color);
void pqm_video_clean_area(uint8_t index, uint16_t x1, uint16_t y1,
                          uint16_t x2, uint16_t y2);
int pqm_video_request_frame(pqm_video_t *video, uint8_t index);
bool pqm_video_take_switch_complete(pqm_video_t *video, uint8_t *front_index);
int pqm_video_restart(pqm_video_t *video);

#endif
