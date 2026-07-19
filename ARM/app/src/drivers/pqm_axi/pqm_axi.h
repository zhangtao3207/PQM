#ifndef PQM_AXI_H
#define PQM_AXI_H

#include <stdbool.h>
#include <stdint.h>

#include "pqm_shared_memory_map.h"

#ifdef __cplusplus
extern "C" {
#endif

#define PQM_AXI_SNAPSHOT_MAX_RETRIES 4u

typedef uint32_t (*pqm_read_word_fn)(void *context, uint32_t word_offset);
typedef void (*pqm_write_word_fn)(void *context, uint32_t word_offset, uint32_t value);

typedef struct {
    void *context;
    pqm_read_word_fn read_word;
    pqm_write_word_fn write_word;
    uint32_t next_command_sequence;
} pqm_axi_t;

typedef struct {
    uint32_t sequence;
    int32_t u_rms_x100;
    int32_t i_rms_x100;
    int32_t u_p2p_x100;
    int32_t i_p2p_x100;
    int32_t frequency_x100;
    int32_t phase_x100;
    int32_t active_power_x100;
    int32_t reactive_power_x100;
    int32_t apparent_power_x100;
    int32_t power_factor_x100;
    int32_t thd_u_x100;
    int32_t thd_i_x100;
    int32_t dc_u_x100;
    int32_t dc_i_x100;
    uint32_t alarm;
    uint32_t validity;
} pqm_measurement_raw_t;

void pqm_axi_init(pqm_axi_t *axi, void *context,
                  pqm_read_word_fn read_word, pqm_write_word_fn write_word);
void pqm_axi_init_mmio(pqm_axi_t *axi, uintptr_t base_address);
bool pqm_axi_validate(pqm_axi_t *axi);
bool pqm_axi_read_snapshot(pqm_axi_t *axi, pqm_measurement_raw_t *out);
bool pqm_axi_send_command(pqm_axi_t *axi, uint32_t command, uint32_t argument,
                          uint32_t timeout_polls, uint32_t *response);

#ifdef __cplusplus
}
#endif

#endif
