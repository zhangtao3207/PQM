/* PQM测量服务接口：定义UI测量模型、显示规格以及PL原始量到显示量的转换。 */
#ifndef PQM_MEASUREMENT_H
#define PQM_MEASUREMENT_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "../../drivers/pqm_axi/pqm_axi.h"

#ifdef __cplusplus
extern "C" {
#endif

#define PQM_VALID_U_RMS          (1u << 0)
#define PQM_VALID_I_RMS          (1u << 1)
#define PQM_VALID_U_P2P          (1u << 2)
#define PQM_VALID_I_P2P          (1u << 3)
#define PQM_VALID_PHASE          (1u << 4)
#define PQM_VALID_FREQUENCY      (1u << 5)
#define PQM_VALID_POWER_METRICS  (1u << 6)
#define PQM_VALID_THD_U          (1u << 7)
#define PQM_VALID_THD_I          (1u << 8)
#define PQM_VALID_DC_U           (1u << 9)
#define PQM_VALID_DC_I           (1u << 10)
#define PQM_VALID_FREQ_METRICS   (1u << 11)
#define PQM_VALID_ALL_FIELDS     ((1u << 12) - 1u)

typedef enum {
    PQM_MEAS_U_RMS = 0,
    PQM_MEAS_I_RMS,
    PQM_MEAS_U_P2P,
    PQM_MEAS_I_P2P,
    PQM_MEAS_FREQUENCY,
    PQM_MEAS_PHASE,
    PQM_MEAS_ACTIVE_POWER,
    PQM_MEAS_REACTIVE_POWER,
    PQM_MEAS_APPARENT_POWER,
    PQM_MEAS_POWER_FACTOR,
    PQM_MEAS_THD_U,
    PQM_MEAS_THD_I,
    PQM_MEAS_DC_U,
    PQM_MEAS_DC_I,
    PQM_MEAS_FIELD_COUNT
} pqm_measurement_field_t;

typedef struct {
    int32_t x100;
    bool valid;
} pqm_measurement_value_t;

typedef struct {
    uint32_t sequence;
    uint32_t alarm;
    pqm_measurement_value_t values[PQM_MEAS_FIELD_COUNT];
} pqm_measurement_t;

/* 将PL定点原始快照转换为带有效标志的UI测量模型。 */
void pqm_measurement_from_raw(pqm_measurement_t *measurement,
                              const pqm_measurement_raw_t *raw);
/* 按字段编号读取一个测量值。 */
const pqm_measurement_value_t *pqm_measurement_get(
    const pqm_measurement_t *measurement, pqm_measurement_field_t field);
/* 按字段单位和小数位格式化显示字符串；无效值显示为占位符。 */
bool pqm_measurement_format(const pqm_measurement_t *measurement,
                            pqm_measurement_field_t field,
                            char *buffer, size_t buffer_size);

#ifdef __cplusplus
}
#endif

#endif
