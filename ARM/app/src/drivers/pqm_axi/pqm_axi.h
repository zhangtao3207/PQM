/* PQM AXI驱动接口：封装共享内存快照读取、接口校验和PS到PL命令发送。 */
#ifndef PQM_AXI_H
#define PQM_AXI_H

#include <stdbool.h>
#include <stdint.h>

#include "pqm_shared_memory_map.h"

#ifdef __cplusplus
extern "C" {
#endif

#define PQM_AXI_SNAPSHOT_MAX_RETRIES 4u
#define PQM_HARMONIC_ENTRY_COUNT (PQM_SHM_HARMONIC_LAST_INDEX + 1u)

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

typedef struct {
    uint16_t u_ratio_x100;
    uint16_t i_ratio_x100;
    int16_t phase_x100;
    uint8_t flags;
} pqm_harmonic_raw_t;

typedef struct {
    uint32_t generation;
    pqm_harmonic_raw_t entries[PQM_HARMONIC_ENTRY_COUNT];
} pqm_harmonic_raw_snapshot_t;

/* 使用可替换的字读写回调初始化驱动，主机测试使用此接口注入模拟内存。 */
void pqm_axi_init(pqm_axi_t *axi, void *context,
                  pqm_read_word_fn read_word, pqm_write_word_fn write_word);
/* 使用物理基地址初始化真实MMIO访问。 */
void pqm_axi_init_mmio(pqm_axi_t *axi, uintptr_t base_address);
/* 校验魔数、ABI版本和PL能力位。 */
bool pqm_axi_validate(pqm_axi_t *axi);
/* 一致性读取最新标量快照，序号变化时自动重试。 */
bool pqm_axi_read_snapshot(pqm_axi_t *axi, pqm_measurement_raw_t *out);
/* 从PL当前有效缓冲区读取完整谐波快照。 */
bool pqm_axi_read_harmonics(pqm_axi_t *axi,
                            pqm_harmonic_raw_snapshot_t *out);
/* 发送通用PS命令并轮询PL应答。 */
bool pqm_axi_send_command(pqm_axi_t *axi, uint32_t command, uint32_t argument,
                          uint32_t timeout_polls, uint32_t *response);
/* 请求切换高低量程，只有PL确认后才返回成功。 */
bool pqm_axi_set_range(pqm_axi_t *axi, bool low_range,
                       uint32_t timeout_polls);

#ifdef __cplusplus
}
#endif

#endif
