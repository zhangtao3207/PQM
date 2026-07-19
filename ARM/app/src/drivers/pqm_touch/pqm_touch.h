#ifndef PQM_TOUCH_H
#define PQM_TOUCH_H

#include <stdbool.h>
#include <stdint.h>

#include "FreeRTOS.h"
#include "task.h"
#include "xgpiops.h"
#include "xiicps.h"
#include "xscugic.h"

#include "pqm_touch_protocol.h"

#define PQM_TOUCH_RESET_PIN 54u
#define PQM_TOUCH_INT_PIN   55u

typedef struct {
    XIicPs iic;
    XGpioPs gpio;
    TaskHandle_t notify_task;
    pqm_touch_controller_t controller;
    pqm_touch_fault_t fault;
    pqm_touch_point_t latest_point;
    volatile bool irq_pending;
    bool interrupt_enabled;
    uint8_t interrupt_bank;
    uint8_t interrupt_pin;
} pqm_touch_t;

int pqm_touch_initialize(pqm_touch_t *touch, TaskHandle_t notify_task);
int pqm_touch_connect_interrupt(pqm_touch_t *touch,
                                XScuGic *interrupt_controller);
int pqm_touch_service(pqm_touch_t *touch, uint32_t now_ms);
void pqm_touch_get_point(pqm_touch_t *touch, pqm_touch_point_t *point);

#endif
