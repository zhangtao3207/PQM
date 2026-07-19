#include "FreeRTOS.h"
#include "task.h"

#include <stddef.h>

#include "platform/pqm_platform.h"
#include "xil_printf.h"

#define PQM_SYSTEM_TASK_STACK_WORDS 1024u
#define PQM_SYSTEM_TASK_PRIORITY    (tskIDLE_PRIORITY + 1u)

static void system_task(void *argument)
{
    pqm_axi_t *axi = pqm_platform_axi();

    (void)argument;
    for (;;) {
        pqm_measurement_raw_t measurement;

        if (pqm_axi_read_snapshot(axi, &measurement)) {
            xil_printf("PQM snapshot %u: U=%d I=%d F=%d valid=%08x\r\n",
                       measurement.sequence,
                       measurement.u_rms_x100,
                       measurement.i_rms_x100,
                       measurement.frequency_x100,
                       measurement.validity);
        } else {
            xil_printf("PQM snapshot unavailable\r\n");
        }
        vTaskDelay(pdMS_TO_TICKS(1000u));
    }
}

int main(void)
{
    BaseType_t task_created;

    if (!pqm_platform_initialize()) {
        pqm_platform_print_identity();
        pqm_platform_fatal("PS/PL shared-memory ABI mismatch");
    }
    pqm_platform_print_identity();

    task_created = xTaskCreate(system_task, "system",
                               PQM_SYSTEM_TASK_STACK_WORDS, NULL,
                               PQM_SYSTEM_TASK_PRIORITY, NULL);
    if (task_created != pdPASS) {
        pqm_platform_fatal("system task creation failed");
    }

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
