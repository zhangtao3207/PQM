#include "pqm_video.h"

#include <stddef.h>
#include <string.h>

#include "xil_cache.h"
#include "xparameters.h"
#include "xstatus.h"

#define PQM_VIDEO_IRQ_PRIORITY 0xA8u
#define PQM_VIDEO_IRQ_TRIGGER  0x03u
#define PQM_VIDEO_IRQ_MASK     \
    (XAXIVDMA_IXR_FRMCNT_MASK | XAXIVDMA_IXR_ERROR_MASK)

static void pqm_video_notify_task(pqm_video_t *video)
{
    BaseType_t higher_priority_task_woken = pdFALSE;

    if (video->notify_task != NULL) {
        vTaskNotifyGiveFromISR(video->notify_task, &higher_priority_task_woken);
        portYIELD_FROM_ISR(higher_priority_task_woken);
    }
}

static void pqm_video_frame_done(void *reference, uint32_t interrupt_mask)
{
    pqm_video_t *video = (pqm_video_t *)reference;

    (void)interrupt_mask;
    video->frame_done_count += 1u;
    if (video->switch_pending) {
        video->front_index = video->pending_index;
        video->switch_pending = false;
        video->switch_completed = true;
    }
    pqm_video_notify_task(video);
}

static void pqm_video_error(void *reference, uint32_t interrupt_mask)
{
    pqm_video_t *video = (pqm_video_t *)reference;

    (void)interrupt_mask;
    video->error_count += 1u;
    pqm_video_notify_task(video);
}

static int pqm_video_configure_read_channel(pqm_video_t *video)
{
    XAxiVdma_DmaSetup config;
    int status;

    memset(&config, 0, sizeof(config));
    config.VertSizeInput = PQM_LCD_HEIGHT;
    config.HoriSizeInput = PQM_LCD_STRIDE;
    config.Stride = PQM_LCD_STRIDE;
    config.FrameDelay = 0;
    config.EnableCircularBuf = 1;
    config.EnableSync = 0;
    config.PointNum = 0;
    config.EnableFrameCounter = 0;
    config.FixedFrameStoreAddr = 0;
    config.FrameStoreStartAddr[0] = PQM_FB0_ADDR;
    config.FrameStoreStartAddr[1] = PQM_FB1_ADDR;

    status = XAxiVdma_DmaConfig(&video->instance, XAXIVDMA_READ, &config);
    if (status != XST_SUCCESS) {
        return status;
    }
    status = XAxiVdma_DmaSetBufferAddr(
        &video->instance, XAXIVDMA_READ, config.FrameStoreStartAddr);
    if (status != XST_SUCCESS) {
        return status;
    }
    status = XAxiVdma_DmaStart(&video->instance, XAXIVDMA_READ);
    if (status != XST_SUCCESS) {
        return status;
    }
    return XAxiVdma_StartParking(&video->instance, video->front_index,
                                 XAXIVDMA_READ);
}

int pqm_video_initialize(pqm_video_t *video, TaskHandle_t notify_task)
{
    XAxiVdma_Config *config;
    int status;

    if (video == NULL || notify_task == NULL) {
        return XST_INVALID_PARAM;
    }
    config = XAxiVdma_LookupConfig(XPAR_AXIVDMA_0_DEVICE_ID);
    if (config == NULL) {
        return XST_DEVICE_NOT_FOUND;
    }
    status = XAxiVdma_CfgInitialize(&video->instance, config,
                                    config->BaseAddress);
    if (status != XST_SUCCESS) {
        return status;
    }

    video->notify_task = notify_task;
    video->frame_done_count = 0u;
    video->error_count = 0u;
    video->front_index = 0u;
    video->pending_index = 0u;
    video->switch_pending = false;
    video->switch_completed = false;

    pqm_video_fill(0u, PQM_VIDEO_BLACK);
    pqm_video_fill(1u, PQM_VIDEO_BLUE);
    Xil_DCacheFlushRange(PQM_FB0_ADDR, PQM_FB_BYTES);
    Xil_DCacheFlushRange(PQM_FB1_ADDR, PQM_FB_BYTES);

    status = XAxiVdma_SetCallBack(
        &video->instance, XAXIVDMA_HANDLER_GENERAL,
        pqm_video_frame_done, video, XAXIVDMA_READ);
    if (status != XST_SUCCESS) {
        return status;
    }
    status = XAxiVdma_SetCallBack(
        &video->instance, XAXIVDMA_HANDLER_ERROR,
        pqm_video_error, video, XAXIVDMA_READ);
    if (status != XST_SUCCESS) {
        return status;
    }

    return pqm_video_configure_read_channel(video);
}

int pqm_video_connect_interrupt(pqm_video_t *video,
                                XScuGic *interrupt_controller)
{
    int status;

    if (video == NULL || interrupt_controller == NULL) {
        return XST_INVALID_PARAM;
    }
    XScuGic_SetPriorityTriggerType(
        interrupt_controller, XPAR_FABRIC_AXIVDMA_0_VEC_ID,
        PQM_VIDEO_IRQ_PRIORITY, PQM_VIDEO_IRQ_TRIGGER);
    status = XScuGic_Connect(
        interrupt_controller, XPAR_FABRIC_AXIVDMA_0_VEC_ID,
        (Xil_InterruptHandler)XAxiVdma_ReadIntrHandler, &video->instance);
    if (status == XST_SUCCESS) {
        XAxiVdma_IntrEnable(&video->instance, PQM_VIDEO_IRQ_MASK,
                            XAXIVDMA_READ);
        XScuGic_Enable(interrupt_controller, XPAR_FABRIC_AXIVDMA_0_VEC_ID);
    }
    return status;
}

uint16_t *pqm_video_framebuffer(uint8_t index)
{
    if (index == 0u) {
        return (uint16_t *)PQM_FB0_ADDR;
    }
    if (index == 1u) {
        return (uint16_t *)PQM_FB1_ADDR;
    }
    return NULL;
}

void pqm_video_fill(uint8_t index, pqm_video_color_t color)
{
    uint16_t *framebuffer = pqm_video_framebuffer(index);
    size_t pixel;

    if (framebuffer == NULL) {
        return;
    }
    for (pixel = 0u; pixel < PQM_LCD_WIDTH * PQM_LCD_HEIGHT; ++pixel) {
        framebuffer[pixel] = (uint16_t)color;
    }
}

void pqm_video_clean_area(uint8_t index, uint16_t x1, uint16_t y1,
                          uint16_t x2, uint16_t y2)
{
    uint16_t *framebuffer = pqm_video_framebuffer(index);
    uint16_t row;

    if (framebuffer == NULL || x1 > x2 || y1 > y2 ||
        x2 >= PQM_LCD_WIDTH || y2 >= PQM_LCD_HEIGHT) {
        return;
    }
    for (row = y1; row <= y2; ++row) {
        UINTPTR row_address = (UINTPTR)&framebuffer[
            (size_t)row * PQM_LCD_WIDTH + x1];
        uint32_t row_bytes = ((uint32_t)x2 - x1 + 1u) * sizeof(uint16_t);

        Xil_DCacheFlushRange(row_address, row_bytes);
    }
}

int pqm_video_request_frame(pqm_video_t *video, uint8_t index)
{
    int status;

    if (video == NULL || index > 1u || video->switch_pending) {
        return XST_INVALID_PARAM;
    }
    if (index == video->front_index) {
        video->switch_completed = true;
        return XST_SUCCESS;
    }

    video->pending_index = index;
    video->switch_pending = true;
    status = XAxiVdma_StartParking(&video->instance, index, XAXIVDMA_READ);
    if (status != XST_SUCCESS) {
        video->switch_pending = false;
    }
    return status;
}

bool pqm_video_take_switch_complete(pqm_video_t *video, uint8_t *front_index)
{
    if (video == NULL || !video->switch_completed) {
        return false;
    }
    taskENTER_CRITICAL();
    if (!video->switch_completed) {
        taskEXIT_CRITICAL();
        return false;
    }
    video->switch_completed = false;
    if (front_index != NULL) {
        *front_index = video->front_index;
    }
    taskEXIT_CRITICAL();
    return true;
}

int pqm_video_restart(pqm_video_t *video)
{
    if (video == NULL) {
        return XST_INVALID_PARAM;
    }
    XAxiVdma_DmaStop(&video->instance, XAXIVDMA_READ);
    video->switch_pending = false;
    video->switch_completed = false;
    return pqm_video_configure_read_channel(video);
}
