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

bool pqm_touch_decode_packet(pqm_touch_controller_t controller,
                             uint8_t status, const uint8_t coordinates[4],
                             pqm_touch_point_t *point);
void pqm_touch_fault_init(pqm_touch_fault_t *fault);
void pqm_touch_fault_success(pqm_touch_fault_t *fault);
void pqm_touch_fault_failure(pqm_touch_fault_t *fault, uint32_t now_ms);
bool pqm_touch_fault_retry_due(const pqm_touch_fault_t *fault,
                               uint32_t now_ms);

#endif
