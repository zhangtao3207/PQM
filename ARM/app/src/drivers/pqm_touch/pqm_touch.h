/* PQM触摸硬件接口：初始化I2C/GPIO、中断服务、周期读取及最新触点发布。 */
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

/* 初始化I2C、GPIO，复位并探测触摸控制器。 */
int pqm_touch_initialize(pqm_touch_t *touch, TaskHandle_t notify_task);
/* 将触摸GPIO中断连接到GIC。 */
int pqm_touch_connect_interrupt(pqm_touch_t *touch,
                                XScuGic *interrupt_controller);
/* 在触摸任务中读取坐标，并在需要时执行故障恢复。 */
int pqm_touch_service(pqm_touch_t *touch, uint32_t now_ms);
/* 在临界区内复制最近一次触点状态。 */
void pqm_touch_get_point(pqm_touch_t *touch, pqm_touch_point_t *point);

#endif
