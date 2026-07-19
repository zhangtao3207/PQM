#include "pqm_waveform.h"

#include <string.h>

void pqm_waveform_init(pqm_waveform_t *state)
{
    if (state != NULL) {
        memset(state, 0, sizeof(*state));
    }
}

bool pqm_waveform_accept_frame(
    pqm_waveform_t *state,
    const pqm_dma_sample_t samples[PQM_WAVEFORM_SAMPLES_PER_FRAME])
{
    bool contiguous;
    size_t index;

    if (state == NULL || samples == NULL) {
        return false;
    }

    contiguous = !state->has_sequence_anchor ||
                 samples[0].sequence == state->expected_sequence;
    for (index = 1u; index < PQM_WAVEFORM_SAMPLES_PER_FRAME; ++index) {
        if (samples[index].sequence != samples[index - 1u].sequence + 1u) {
            contiguous = false;
        }
    }

    state->expected_sequence =
        samples[PQM_WAVEFORM_SAMPLES_PER_FRAME - 1u].sequence + 1u;
    state->has_sequence_anchor = true;
    if (!contiguous) {
        return false;
    }

    memcpy(state->display_frame, samples, sizeof(state->display_frame));
    state->has_display_frame = true;
    state->generation += 1u;
    return true;
}

void pqm_waveform_resample(const pqm_waveform_t *state,
                           pqm_wave_column_t *columns, size_t column_count)
{
    size_t column;

    if (columns == NULL || column_count == 0u) {
        return;
    }
    if (state == NULL || !state->has_display_frame) {
        memset(columns, 0, column_count * sizeof(*columns));
        return;
    }

    for (column = 0u; column < column_count; ++column) {
        size_t begin =
            (column * PQM_WAVEFORM_SAMPLES_PER_FRAME) / column_count;
        size_t end =
            ((column + 1u) * PQM_WAVEFORM_SAMPLES_PER_FRAME) / column_count;
        size_t index;
        pqm_wave_column_t result;

        if (begin >= PQM_WAVEFORM_SAMPLES_PER_FRAME) {
            begin = PQM_WAVEFORM_SAMPLES_PER_FRAME - 1u;
        }
        if (end <= begin) {
            end = begin + 1u;
        }
        if (end > PQM_WAVEFORM_SAMPLES_PER_FRAME) {
            end = PQM_WAVEFORM_SAMPLES_PER_FRAME;
        }

        result.u_min = state->display_frame[begin].u;
        result.u_max = state->display_frame[begin].u;
        result.i_min = state->display_frame[begin].i;
        result.i_max = state->display_frame[begin].i;
        for (index = begin + 1u; index < end; ++index) {
            int16_t u = state->display_frame[index].u;
            int16_t i = state->display_frame[index].i;

            if (u < result.u_min) {
                result.u_min = u;
            }
            if (u > result.u_max) {
                result.u_max = u;
            }
            if (i < result.i_min) {
                result.i_min = i;
            }
            if (i > result.i_max) {
                result.i_max = i;
            }
        }
        columns[column] = result;
    }
}
