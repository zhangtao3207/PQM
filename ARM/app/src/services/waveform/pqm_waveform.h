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

void pqm_waveform_init(pqm_waveform_t *state);
bool pqm_waveform_accept_frame(
    pqm_waveform_t *state,
    const pqm_dma_sample_t samples[PQM_WAVEFORM_SAMPLES_PER_FRAME]);
void pqm_waveform_resample(const pqm_waveform_t *state,
                           pqm_wave_column_t *columns, size_t column_count);

#endif
