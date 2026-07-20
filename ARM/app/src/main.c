#include "FreeRTOS.h"
#include "queue.h"
#include "task.h"

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "drivers/pqm_dma/pqm_dma.h"
#include "drivers/pqm_touch/pqm_touch.h"
#include "drivers/pqm_video/pqm_video.h"
#include "platform/pqm_platform.h"
#include "services/measurement/pqm_measurement.h"
#include "services/waveform/pqm_waveform.h"
#include "ui/pqm_lvgl_port.h"
#include "ui/pqm_ui.h"
#include "xil_printf.h"
#include "xscugic.h"
#include "xstatus.h"

#define PQM_DMA_TASK_STACK_WORDS          2048u
#define PQM_TOUCH_TASK_STACK_WORDS        1024u
#define PQM_UI_TASK_STACK_WORDS           4096u
#define PQM_MEASUREMENT_TASK_STACK_WORDS  1024u
#define PQM_SYSTEM_TASK_STACK_WORDS        512u

#define PQM_DMA_TASK_PRIORITY         (tskIDLE_PRIORITY + 5u)
#define PQM_TOUCH_TASK_PRIORITY       (tskIDLE_PRIORITY + 4u)
#define PQM_UI_TASK_PRIORITY          (tskIDLE_PRIORITY + 3u)
#define PQM_MEASUREMENT_TASK_PRIORITY (tskIDLE_PRIORITY + 2u)
#define PQM_SYSTEM_TASK_PRIORITY      (tskIDLE_PRIORITY + 1u)

#define PQM_UI_PERIOD_MS           5u
#define PQM_MEASUREMENT_PERIOD_MS 50u
#define PQM_TOUCH_POLL_MS         20u
#define PQM_RANGE_COMMAND_TIMEOUT_POLLS 100000u

typedef struct {
    uint32_t generation;
    pqm_wave_column_t columns[PQM_UI_WAVE_COLUMNS];
} pqm_waveform_message_t;

typedef struct {
    bool low_range;
} pqm_range_request_t;

typedef struct {
    bool success;
    bool low_range;
} pqm_range_result_t;

extern XScuGic xInterruptController;

static pqm_dma_t dma_driver;
static pqm_touch_t touch_driver;
static pqm_video_t video_driver;
static pqm_waveform_t waveform_state;
static pqm_lvgl_port_t lvgl_port;
static pqm_ui_t ui;

static StaticTask_t dma_task_control;
static StaticTask_t touch_task_control;
static StaticTask_t ui_task_control;
static StaticTask_t measurement_task_control;
static StaticTask_t system_task_control;
static StackType_t dma_task_stack[PQM_DMA_TASK_STACK_WORDS];
static StackType_t touch_task_stack[PQM_TOUCH_TASK_STACK_WORDS];
static StackType_t ui_task_stack[PQM_UI_TASK_STACK_WORDS];
static StackType_t measurement_task_stack[PQM_MEASUREMENT_TASK_STACK_WORDS];
static StackType_t system_task_stack[PQM_SYSTEM_TASK_STACK_WORDS];
static StaticTask_t idle_task_control;
static StackType_t idle_task_stack[configMINIMAL_STACK_SIZE];
static StaticTask_t timer_task_control;
static StackType_t timer_task_stack[configTIMER_TASK_STACK_DEPTH];

static StaticQueue_t measurement_queue_control;
static StaticQueue_t waveform_queue_control;
static StaticQueue_t harmonic_queue_control;
static StaticQueue_t range_request_queue_control;
static StaticQueue_t range_result_queue_control;
static uint8_t measurement_queue_storage[sizeof(pqm_measurement_t)]
    __attribute__((aligned(8)));
static uint8_t waveform_queue_storage[sizeof(pqm_waveform_message_t)]
    __attribute__((aligned(8)));
static uint8_t harmonic_queue_storage[sizeof(pqm_harmonic_raw_snapshot_t)]
    __attribute__((aligned(8)));
static uint8_t range_request_queue_storage[sizeof(pqm_range_request_t)]
    __attribute__((aligned(8)));
static uint8_t range_result_queue_storage[sizeof(pqm_range_result_t)]
    __attribute__((aligned(8)));
static QueueHandle_t measurement_queue;
static QueueHandle_t waveform_queue;
static QueueHandle_t harmonic_queue;
static QueueHandle_t range_request_queue;
static QueueHandle_t range_result_queue;

static pqm_waveform_message_t dma_waveform_message;
static pqm_waveform_message_t ui_waveform_message;
static pqm_measurement_t measurement_message;
static pqm_measurement_t ui_measurement_message;
static pqm_harmonic_raw_snapshot_t harmonic_message;
static pqm_harmonic_raw_snapshot_t ui_harmonic_message;
static pqm_range_request_t range_request_message;
static pqm_range_result_t range_result_message;
static volatile bool touch_ready;

static bool queue_range_request(void *context, bool low_range)
{
    pqm_range_request_t request;

    (void)context;
    request.low_range = low_range;
    return xQueueOverwrite(range_request_queue, &request) == pdPASS;
}

static void dma_rx_task(void *argument)
{
    (void)argument;
    pqm_waveform_init(&waveform_state);
    if (pqm_dma_initialize(&dma_driver, xTaskGetCurrentTaskHandle()) !=
            XST_SUCCESS ||
        pqm_dma_connect_interrupt(&dma_driver, &xInterruptController) !=
            XST_SUCCESS) {
        pqm_platform_fatal("AXI DMA initialization failed");
    }

    for (;;) {
        uint32_t accepted_frames = 0u;

        (void)ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
        if (pqm_dma_service(&dma_driver, &waveform_state,
                            &accepted_frames) != XST_SUCCESS) {
            pqm_platform_fatal("AXI DMA receive failed");
        }
        if (accepted_frames != 0u && waveform_state.has_display_frame) {
            dma_waveform_message.generation = waveform_state.generation;
            pqm_waveform_resample(&waveform_state,
                                  dma_waveform_message.columns,
                                  PQM_UI_WAVE_COLUMNS);
            (void)xQueueOverwrite(waveform_queue, &dma_waveform_message);
        }
    }
}

static void touch_task(void *argument)
{
    (void)argument;
    if (pqm_touch_initialize(&touch_driver, xTaskGetCurrentTaskHandle()) !=
            XST_SUCCESS ||
        pqm_touch_connect_interrupt(&touch_driver, &xInterruptController) !=
            XST_SUCCESS) {
        pqm_platform_fatal("touch initialization failed");
    }
    touch_ready = true;

    for (;;) {
        uint32_t now_ms;

        (void)ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(PQM_TOUCH_POLL_MS));
        now_ms = (uint32_t)(xTaskGetTickCount() * portTICK_PERIOD_MS);
        (void)pqm_touch_service(&touch_driver, now_ms);
    }
}

static void measurement_task(void *argument)
{
    pqm_axi_t *axi = pqm_platform_axi();
    TickType_t last_wake = xTaskGetTickCount();
    uint32_t last_harmonic_generation = UINT32_MAX;

    (void)argument;
    for (;;) {
        pqm_measurement_raw_t raw;
        uint32_t harmonic_generation;
        uint32_t harmonic_status;

        if (xQueueReceive(range_request_queue, &range_request_message, 0u) ==
            pdPASS) {
            range_result_message.low_range = range_request_message.low_range;
            range_result_message.success = pqm_axi_set_range(
                axi, range_request_message.low_range,
                PQM_RANGE_COMMAND_TIMEOUT_POLLS);
            (void)xQueueOverwrite(range_result_queue, &range_result_message);
        }

        if (pqm_axi_read_snapshot(axi, &raw)) {
            pqm_measurement_from_raw(&measurement_message, &raw);
            (void)xQueueOverwrite(measurement_queue, &measurement_message);
        }
        harmonic_status = axi->read_word(axi->context, PQM_SHM_STATUS_WORD);
        harmonic_generation = axi->read_word(
            axi->context, PQM_SHM_HARMONIC_GENERATION_WORD);
        if ((harmonic_status & PQM_SHM_STATUS_HARMONIC_VALID) != 0u &&
            harmonic_generation != last_harmonic_generation &&
            pqm_axi_read_harmonics(axi, &harmonic_message)) {
            last_harmonic_generation = harmonic_message.generation;
            (void)xQueueOverwrite(harmonic_queue, &harmonic_message);
        }
        vTaskDelayUntil(&last_wake,
                        pdMS_TO_TICKS(PQM_MEASUREMENT_PERIOD_MS));
    }
}

static void ui_task(void *argument)
{
    TickType_t last_wake = xTaskGetTickCount();
    bool touch_attached = false;

    (void)argument;
    if (pqm_video_initialize(&video_driver, xTaskGetCurrentTaskHandle()) !=
            XST_SUCCESS ||
        pqm_video_connect_interrupt(&video_driver, &xInterruptController) !=
            XST_SUCCESS ||
        !pqm_lvgl_port_initialize(&lvgl_port, &video_driver) ||
        !pqm_ui_initialize(&ui, queue_range_request, NULL)) {
        pqm_platform_fatal("LVGL/video initialization failed");
    }

    for (;;) {
        (void)ulTaskNotifyTake(pdTRUE, 0u);
        pqm_lvgl_port_process(&lvgl_port);
        if (!touch_attached && touch_ready) {
            touch_attached = pqm_lvgl_port_attach_touch(
                &lvgl_port, &touch_driver);
        }
        if (xQueueReceive(measurement_queue, &ui_measurement_message, 0u) ==
            pdPASS) {
            pqm_ui_update_measurement(&ui, &ui_measurement_message);
        }
        if (xQueueReceive(waveform_queue, &ui_waveform_message, 0u) == pdPASS) {
            pqm_ui_update_waveform(&ui, ui_waveform_message.columns);
        }
        if (xQueueReceive(harmonic_queue, &ui_harmonic_message, 0u) == pdPASS) {
            pqm_ui_update_harmonics(&ui, &ui_harmonic_message);
        }
        if (xQueueReceive(range_result_queue, &range_result_message, 0u) ==
            pdPASS) {
            pqm_ui_set_range_result(&ui, range_result_message.success,
                                    range_result_message.low_range);
        }
        lv_tick_inc(PQM_UI_PERIOD_MS);
        (void)lv_timer_handler();
        vTaskDelayUntil(&last_wake, pdMS_TO_TICKS(PQM_UI_PERIOD_MS));
    }
}

static void system_task(void *argument)
{
    (void)argument;
    for (;;) {
        xil_printf("PQM runtime: dma=%u vdma=%u errors=%u touch=%u\r\n",
                   waveform_state.generation,
                   video_driver.frame_done_count,
                   video_driver.error_count,
                   touch_ready ? 1u : 0u);
        vTaskDelay(pdMS_TO_TICKS(1000u));
    }
}

static void create_queues(void)
{
    measurement_queue = xQueueCreateStatic(
        1u, sizeof(pqm_measurement_t), measurement_queue_storage,
        &measurement_queue_control);
    waveform_queue = xQueueCreateStatic(
        1u, sizeof(pqm_waveform_message_t), waveform_queue_storage,
        &waveform_queue_control);
    harmonic_queue = xQueueCreateStatic(
        1u, sizeof(pqm_harmonic_raw_snapshot_t), harmonic_queue_storage,
        &harmonic_queue_control);
    range_request_queue = xQueueCreateStatic(
        1u, sizeof(pqm_range_request_t), range_request_queue_storage,
        &range_request_queue_control);
    range_result_queue = xQueueCreateStatic(
        1u, sizeof(pqm_range_result_t), range_result_queue_storage,
        &range_result_queue_control);
    if (measurement_queue == NULL || waveform_queue == NULL ||
        harmonic_queue == NULL || range_request_queue == NULL ||
        range_result_queue == NULL) {
        pqm_platform_fatal("static queue creation failed");
    }
}

static void create_tasks(void)
{
    if (xTaskCreateStatic(dma_rx_task, "dma_rx", PQM_DMA_TASK_STACK_WORDS,
                          NULL, PQM_DMA_TASK_PRIORITY, dma_task_stack,
                          &dma_task_control) == NULL ||
        xTaskCreateStatic(touch_task, "touch", PQM_TOUCH_TASK_STACK_WORDS,
                          NULL, PQM_TOUCH_TASK_PRIORITY, touch_task_stack,
                          &touch_task_control) == NULL ||
        xTaskCreateStatic(ui_task, "ui", PQM_UI_TASK_STACK_WORDS,
                          NULL, PQM_UI_TASK_PRIORITY, ui_task_stack,
                          &ui_task_control) == NULL ||
        xTaskCreateStatic(measurement_task, "measurement",
                          PQM_MEASUREMENT_TASK_STACK_WORDS, NULL,
                          PQM_MEASUREMENT_TASK_PRIORITY,
                          measurement_task_stack,
                          &measurement_task_control) == NULL ||
        xTaskCreateStatic(system_task, "system", PQM_SYSTEM_TASK_STACK_WORDS,
                          NULL, PQM_SYSTEM_TASK_PRIORITY, system_task_stack,
                          &system_task_control) == NULL) {
        pqm_platform_fatal("static task creation failed");
    }
}

int main(void)
{
    if (!pqm_platform_initialize()) {
        pqm_platform_print_identity();
        pqm_platform_fatal("PS/PL shared-memory ABI mismatch");
    }
    pqm_platform_print_identity();
    create_queues();
    create_tasks();

    xil_printf("PQM FreeRTOS scheduler start\r\n");
    vTaskStartScheduler();
    pqm_platform_fatal("scheduler returned");
}

void vApplicationMallocFailedHook(void)
{
    pqm_platform_fatal("FreeRTOS allocation failed");
}

void vApplicationStackOverflowHook(TaskHandle_t task, char *task_name)
{
    (void)task;
    xil_printf("PQM stack overflow: %s\r\n",
               task_name != NULL ? task_name : "unknown");
    pqm_platform_fatal("FreeRTOS stack overflow");
}

void vApplicationGetIdleTaskMemory(StaticTask_t **task_control,
                                   StackType_t **task_stack,
                                   uint32_t *stack_words)
{
    *task_control = &idle_task_control;
    *task_stack = idle_task_stack;
    *stack_words = configMINIMAL_STACK_SIZE;
}

void vApplicationGetTimerTaskMemory(StaticTask_t **task_control,
                                    StackType_t **task_stack,
                                    uint32_t *stack_words)
{
    *task_control = &timer_task_control;
    *task_stack = timer_task_stack;
    *stack_words = configTIMER_TASK_STACK_DEPTH;
}
