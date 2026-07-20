/*
 * 触摸协议解析与故障状态机。
 *
 * 本模块不直接访问硬件，负责把FT/GT原始坐标转换为LCD坐标，并管理连续失败
 * 次数和恢复等待时间，因此可以脱离开发板进行单元测试。
 */
#include "pqm_touch_protocol.h"

#include <stddef.h>

#define PQM_TOUCH_MAX_X 799u
#define PQM_TOUCH_MAX_Y 479u

static uint16_t pqm_touch_clip(uint16_t value, uint16_t maximum)
{
    return value > maximum ? maximum : value;
}

bool pqm_touch_decode_packet(pqm_touch_controller_t controller,
                             uint8_t status, const uint8_t coordinates[4],
                             pqm_touch_point_t *point)
{
    uint8_t point_count;
    uint16_t x;
    uint16_t y;

    if (point == NULL) {
        return false;
    }
    point->pressed = false;
    if (controller == PQM_TOUCH_CONTROLLER_FT) {
        point_count = status & 0x0Fu;
    } else if (controller == PQM_TOUCH_CONTROLLER_GT) {
        if ((status & 0x80u) == 0u) {
            return true;
        }
        point_count = status & 0x0Fu;
    } else {
        return false;
    }

    if (point_count == 0u) {
        return true;
    }
    if (point_count > 5u || coordinates == NULL) {
        return false;
    }

    if (controller == PQM_TOUCH_CONTROLLER_FT) {
        uint16_t controller_x =
            ((uint16_t)(coordinates[0] & 0x0Fu) << 8) | coordinates[1];
        uint16_t controller_y =
            ((uint16_t)(coordinates[2] & 0x0Fu) << 8) | coordinates[3];

        x = controller_y;
        y = controller_x;
    } else {
        x = (uint16_t)coordinates[0] | ((uint16_t)coordinates[1] << 8);
        y = (uint16_t)coordinates[2] | ((uint16_t)coordinates[3] << 8);
    }

    point->x = pqm_touch_clip(x, PQM_TOUCH_MAX_X);
    point->y = pqm_touch_clip(y, PQM_TOUCH_MAX_Y);
    point->pressed = true;
    return true;
}

void pqm_touch_fault_init(pqm_touch_fault_t *fault)
{
    if (fault != NULL) {
        fault->consecutive_failures = 0u;
        fault->recovering = false;
        fault->retry_at_ms = 0u;
    }
}

void pqm_touch_fault_success(pqm_touch_fault_t *fault)
{
    pqm_touch_fault_init(fault);
}

void pqm_touch_fault_failure(pqm_touch_fault_t *fault, uint32_t now_ms)
{
    if (fault == NULL || fault->recovering) {
        return;
    }
    if (fault->consecutive_failures < UINT8_MAX) {
        fault->consecutive_failures += 1u;
    }
    if (fault->consecutive_failures >= PQM_TOUCH_FAILURE_LIMIT) {
        fault->recovering = true;
        fault->retry_at_ms = now_ms + PQM_TOUCH_RECOVERY_DELAY_MS;
    }
}

bool pqm_touch_fault_retry_due(const pqm_touch_fault_t *fault,
                               uint32_t now_ms)
{
    if (fault == NULL || !fault->recovering) {
        return false;
    }
    return (int32_t)(now_ms - fault->retry_at_ms) >= 0;
}
