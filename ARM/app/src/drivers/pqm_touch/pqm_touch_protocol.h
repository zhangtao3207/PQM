/* PQM触摸协议接口：定义控制器类型、触点数据以及可测试的故障恢复状态。 */
#ifndef PQM_TOUCH_PROTOCOL_H
#define PQM_TOUCH_PROTOCOL_H

#include <stdbool.h>
#include <stdint.h>

#define PQM_TOUCH_RECOVERY_DELAY_MS 500u
#define PQM_TOUCH_FAILURE_LIMIT     3u

typedef enum {
    PQM_TOUCH_CONTROLLER_NONE = 0,
    PQM_TOUCH_CONTROLLER_FT,
    PQM_TOUCH_CONTROLLER_GT
} pqm_touch_controller_t;

typedef struct {
    uint16_t x;
    uint16_t y;
    bool pressed;
} pqm_touch_point_t;

typedef struct {
    uint8_t consecutive_failures;
    bool recovering;
    uint32_t retry_at_ms;
} pqm_touch_fault_t;

/* 将FT或GT控制器原始数据包解析为800x480屏幕坐标。 */
bool pqm_touch_decode_packet(pqm_touch_controller_t controller,
                             uint8_t status, const uint8_t coordinates[4],
                             pqm_touch_point_t *point);
/* 初始化、清除或累计触摸通信故障状态。 */
void pqm_touch_fault_init(pqm_touch_fault_t *fault);
void pqm_touch_fault_success(pqm_touch_fault_t *fault);
void pqm_touch_fault_failure(pqm_touch_fault_t *fault, uint32_t now_ms);
/* 判断恢复等待时间是否已经到达。 */
bool pqm_touch_fault_retry_due(const pqm_touch_fault_t *fault,
                               uint32_t now_ms);

#endif
