/* PQM波形服务接口：定义DMA采样格式、帧连续性状态和显示列包络数据。 */
#ifndef PQM_WAVEFORM_H
#define PQM_WAVEFORM_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define PQM_WAVEFORM_SAMPLES_PER_FRAME 2048u

typedef struct {
    int16_t u;
    int16_t i;
    uint32_t sequence;
} pqm_dma_sample_t;

typedef struct {
    int16_t u_min;
    int16_t u_max;
    int16_t i_min;
    int16_t i_max;
} pqm_wave_column_t;

typedef struct {
    pqm_dma_sample_t display_frame[PQM_WAVEFORM_SAMPLES_PER_FRAME];
    uint32_t expected_sequence;
    uint32_t generation;
    bool has_display_frame;
    bool has_sequence_anchor;
} pqm_waveform_t;

/* 清空帧连续性锚点和显示状态。 */
void pqm_waveform_init(pqm_waveform_t *state);
/* 校验整帧源序号，连续时接收，否则丢弃并重新建立序号锚点。 */
bool pqm_waveform_accept_frame(
    pqm_waveform_t *state,
    const pqm_dma_sample_t samples[PQM_WAVEFORM_SAMPLES_PER_FRAME]);
/* 将最近一帧按显示列分组，计算每列电压/电流最小值和最大值。 */
void pqm_waveform_resample(const pqm_waveform_t *state,
                           pqm_wave_column_t *columns, size_t column_count);

#endif
