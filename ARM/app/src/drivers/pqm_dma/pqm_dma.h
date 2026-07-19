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

int pqm_dma_initialize(pqm_dma_t *dma, TaskHandle_t notify_task);
int pqm_dma_connect_interrupt(pqm_dma_t *dma, XScuGic *interrupt_controller);
void pqm_dma_isr(void *reference);
int pqm_dma_service(pqm_dma_t *dma, pqm_waveform_t *waveform,
                    uint32_t *accepted_frames);
bool pqm_dma_error_pending(const pqm_dma_t *dma);

#endif
