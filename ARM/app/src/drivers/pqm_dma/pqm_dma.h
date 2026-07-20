/* PQM DMA驱动接口：管理SG接收环、中断通知及已完成采样帧的任务级处理。 */
#ifndef PQM_DMA_H
#define PQM_DMA_H

#include <stdbool.h>
#include <stdint.h>

#include "FreeRTOS.h"
#include "task.h"
#include "xaxidma.h"
#include "xscugic.h"

#include "../../services/waveform/pqm_waveform.h"

#define PQM_DMA_BUFFER_COUNT 4u
#define PQM_DMA_FRAME_BYTES  \
    (PQM_WAVEFORM_SAMPLES_PER_FRAME * sizeof(pqm_dma_sample_t))

typedef struct {
    XAxiDma instance;
    XAxiDma_BdRing *rx_ring;
    TaskHandle_t notify_task;
    volatile bool error_pending;
} pqm_dma_t;

/* 初始化DMA接收通道、SG描述符环和四个采样缓冲区。 */
int pqm_dma_initialize(pqm_dma_t *dma, TaskHandle_t notify_task);
/* 将DMA接收中断连接到GIC。 */
int pqm_dma_connect_interrupt(pqm_dma_t *dma, XScuGic *interrupt_controller);
/* DMA中断入口：确认中断、记录错误并通知接收任务。 */
void pqm_dma_isr(void *reference);
/* 回收完成描述符、提交有效帧，并把缓冲区重新挂回硬件。 */
int pqm_dma_service(pqm_dma_t *dma, pqm_waveform_t *waveform,
                    uint32_t *accepted_frames);
/* 查询DMA是否已进入错误状态。 */
bool pqm_dma_error_pending(const pqm_dma_t *dma);

#endif
