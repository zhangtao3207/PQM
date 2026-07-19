#include "pqm_dma.h"

#include <stddef.h>

#include "xil_cache.h"
#include "xparameters.h"
#include "xstatus.h"

#define PQM_DMA_IRQ_MASK (XAXIDMA_IRQ_IOC_MASK | XAXIDMA_IRQ_ERROR_MASK)
#define PQM_DMA_IRQ_PRIORITY 0xA0u
#define PQM_DMA_IRQ_TRIGGER  0x03u

static uint8_t pqm_dma_bd_space[
    XAXIDMA_BD_MINIMUM_ALIGNMENT * PQM_DMA_BUFFER_COUNT]
    __attribute__((aligned(XAXIDMA_BD_MINIMUM_ALIGNMENT),
                   section(".bss.pqm_dma_descriptors")));

static pqm_dma_sample_t
    pqm_dma_buffers[PQM_DMA_BUFFER_COUNT][PQM_WAVEFORM_SAMPLES_PER_FRAME]
    __attribute__((aligned(64), section(".bss.pqm_dma_buffers")));

static int pqm_dma_configure_descriptors(pqm_dma_t *dma,
                                         XAxiDma_Bd *first_bd,
                                         int descriptor_count,
                                         pqm_dma_sample_t **buffers)
{
    XAxiDma_Bd *descriptor = first_bd;
    int index;

    for (index = 0; index < descriptor_count; ++index) {
        UINTPTR buffer_address = (UINTPTR)buffers[index];
        int status;

        status = XAxiDma_BdSetBufAddr(descriptor, buffer_address);
        if (status != XST_SUCCESS) {
            return status;
        }
        status = XAxiDma_BdSetLength(descriptor, PQM_DMA_FRAME_BYTES,
                                     dma->rx_ring->MaxTransferLen);
        if (status != XST_SUCCESS) {
            return status;
        }
        XAxiDma_BdSetCtrl(descriptor, 0u);
        XAxiDma_BdSetId(descriptor, buffer_address);
        descriptor = (XAxiDma_Bd *)XAxiDma_BdRingNext(dma->rx_ring,
                                                       descriptor);
    }
    return XST_SUCCESS;
}

int pqm_dma_initialize(pqm_dma_t *dma, TaskHandle_t notify_task)
{
    XAxiDma_Config *config;
    XAxiDma_Bd template_bd;
    XAxiDma_Bd *descriptors;
    pqm_dma_sample_t *buffers[PQM_DMA_BUFFER_COUNT];
    int status;
    uint32_t index;

    if (dma == NULL || notify_task == NULL) {
        return XST_INVALID_PARAM;
    }

    config = XAxiDma_LookupConfig(XPAR_AXIDMA_0_DEVICE_ID);
    if (config == NULL) {
        return XST_DEVICE_NOT_FOUND;
    }
    status = XAxiDma_CfgInitialize(&dma->instance, config);
    if (status != XST_SUCCESS || !XAxiDma_HasSg(&dma->instance)) {
        return XST_FAILURE;
    }

    dma->rx_ring = XAxiDma_GetRxRing(&dma->instance);
    dma->notify_task = notify_task;
    dma->error_pending = false;
    XAxiDma_BdRingIntDisable(dma->rx_ring, XAXIDMA_IRQ_ALL_MASK);

    status = XAxiDma_BdRingCreate(
        dma->rx_ring, (UINTPTR)pqm_dma_bd_space, (UINTPTR)pqm_dma_bd_space,
        XAXIDMA_BD_MINIMUM_ALIGNMENT, PQM_DMA_BUFFER_COUNT);
    if (status != XST_SUCCESS) {
        return status;
    }

    XAxiDma_BdClear(&template_bd);
    status = XAxiDma_BdRingClone(dma->rx_ring, &template_bd);
    if (status != XST_SUCCESS) {
        return status;
    }
    status = XAxiDma_BdRingAlloc(dma->rx_ring, PQM_DMA_BUFFER_COUNT,
                                 &descriptors);
    if (status != XST_SUCCESS) {
        return status;
    }

    for (index = 0u; index < PQM_DMA_BUFFER_COUNT; ++index) {
        buffers[index] = pqm_dma_buffers[index];
        Xil_DCacheFlushRange((UINTPTR)buffers[index], PQM_DMA_FRAME_BYTES);
    }
    status = pqm_dma_configure_descriptors(
        dma, descriptors, (int)PQM_DMA_BUFFER_COUNT, buffers);
    if (status != XST_SUCCESS) {
        return status;
    }
    status = XAxiDma_BdRingSetCoalesce(dma->rx_ring, 1u, 0u);
    if (status != XST_SUCCESS) {
        return status;
    }
    status = XAxiDma_BdRingToHw(dma->rx_ring, PQM_DMA_BUFFER_COUNT,
                                descriptors);
    if (status != XST_SUCCESS) {
        return status;
    }

    XAxiDma_BdRingIntEnable(dma->rx_ring, PQM_DMA_IRQ_MASK);
    return XAxiDma_BdRingStart(dma->rx_ring);
}

int pqm_dma_connect_interrupt(pqm_dma_t *dma, XScuGic *interrupt_controller)
{
    int status;

    if (dma == NULL || interrupt_controller == NULL) {
        return XST_INVALID_PARAM;
    }
    XScuGic_SetPriorityTriggerType(
        interrupt_controller, XPAR_FABRIC_AXIDMA_0_VEC_ID,
        PQM_DMA_IRQ_PRIORITY, PQM_DMA_IRQ_TRIGGER);
    status = XScuGic_Connect(
        interrupt_controller, XPAR_FABRIC_AXIDMA_0_VEC_ID,
        (Xil_InterruptHandler)pqm_dma_isr, dma);
    if (status == XST_SUCCESS) {
        XScuGic_Enable(interrupt_controller, XPAR_FABRIC_AXIDMA_0_VEC_ID);
    }
    return status;
}

void pqm_dma_isr(void *reference)
{
    pqm_dma_t *dma = (pqm_dma_t *)reference;
    BaseType_t higher_priority_task_woken = pdFALSE;
    uint32_t interrupt_status;

    if (dma == NULL || dma->rx_ring == NULL) {
        return;
    }
    interrupt_status = XAxiDma_BdRingGetIrq(dma->rx_ring) & PQM_DMA_IRQ_MASK;
    XAxiDma_BdRingAckIrq(dma->rx_ring, interrupt_status);
    if ((interrupt_status & XAXIDMA_IRQ_ERROR_MASK) != 0u) {
        dma->error_pending = true;
    }
    if (interrupt_status != 0u && dma->notify_task != NULL) {
        vTaskNotifyGiveFromISR(dma->notify_task, &higher_priority_task_woken);
        portYIELD_FROM_ISR(higher_priority_task_woken);
    }
}

int pqm_dma_service(pqm_dma_t *dma, pqm_waveform_t *waveform,
                    uint32_t *accepted_frames)
{
    XAxiDma_Bd *first_descriptor;
    XAxiDma_Bd *descriptor;
    pqm_dma_sample_t *completed_buffers[PQM_DMA_BUFFER_COUNT];
    uint32_t accepted = 0u;
    int descriptor_count;
    int index;
    int status;

    if (dma == NULL || waveform == NULL || dma->rx_ring == NULL) {
        return XST_INVALID_PARAM;
    }
    if (dma->error_pending) {
        return XST_FAILURE;
    }

    descriptor_count = XAxiDma_BdRingFromHw(
        dma->rx_ring, PQM_DMA_BUFFER_COUNT, &first_descriptor);
    if (descriptor_count == 0) {
        if (accepted_frames != NULL) {
            *accepted_frames = 0u;
        }
        return XST_SUCCESS;
    }

    descriptor = first_descriptor;
    for (index = 0; index < descriptor_count; ++index) {
        uint32_t descriptor_status = XAxiDma_BdGetSts(descriptor);
        uint32_t actual_length = XAxiDma_BdGetActualLength(
            descriptor, dma->rx_ring->MaxTransferLen);
        pqm_dma_sample_t *buffer =
            (pqm_dma_sample_t *)(UINTPTR)XAxiDma_BdGetId(descriptor);

        completed_buffers[index] = buffer;
        Xil_DCacheInvalidateRange((UINTPTR)buffer, PQM_DMA_FRAME_BYTES);
        if ((descriptor_status & XAXIDMA_BD_STS_ALL_ERR_MASK) != 0u ||
            (descriptor_status & XAXIDMA_BD_STS_COMPLETE_MASK) == 0u) {
            dma->error_pending = true;
        } else if (actual_length == PQM_DMA_FRAME_BYTES &&
                   pqm_waveform_accept_frame(waveform, buffer)) {
            accepted += 1u;
        }
        descriptor = (XAxiDma_Bd *)XAxiDma_BdRingNext(dma->rx_ring,
                                                       descriptor);
    }

    status = XAxiDma_BdRingFree(dma->rx_ring, descriptor_count,
                                first_descriptor);
    if (status != XST_SUCCESS) {
        dma->error_pending = true;
        return status;
    }
    status = XAxiDma_BdRingAlloc(dma->rx_ring, descriptor_count,
                                 &first_descriptor);
    if (status != XST_SUCCESS) {
        dma->error_pending = true;
        return status;
    }
    status = pqm_dma_configure_descriptors(
        dma, first_descriptor, descriptor_count, completed_buffers);
    if (status != XST_SUCCESS) {
        dma->error_pending = true;
        return status;
    }
    status = XAxiDma_BdRingToHw(dma->rx_ring, descriptor_count,
                                first_descriptor);
    if (status != XST_SUCCESS) {
        dma->error_pending = true;
        return status;
    }

    if (accepted_frames != NULL) {
        *accepted_frames = accepted;
    }
    return dma->error_pending ? XST_FAILURE : XST_SUCCESS;
}

bool pqm_dma_error_pending(const pqm_dma_t *dma)
{
    return dma == NULL || dma->error_pending;
}
