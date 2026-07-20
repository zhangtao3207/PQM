/*
 * 波形服务主机测试。
 * 验证2048点帧序号连续性、丢帧后的重新同步以及400列包络重采样。
 */
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "pqm_waveform.h"

static int failures;

#define CHECK(condition)                                                        \
    do {                                                                        \
        if (!(condition)) {                                                     \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #condition);       \
            failures += 1;                                                      \
        }                                                                       \
    } while (0)

static void fill_frame(pqm_dma_sample_t *samples, uint32_t first_sequence)
{
    size_t index;

    for (index = 0u; index < PQM_WAVEFORM_SAMPLES_PER_FRAME; ++index) {
        samples[index].u = (int16_t)index;
        samples[index].i = (int16_t)-(int32_t)index;
        samples[index].sequence = first_sequence + (uint32_t)index;
    }
}

static void test_contiguous_frames_and_wraparound(void)
{
    pqm_waveform_t state;
    pqm_dma_sample_t samples[PQM_WAVEFORM_SAMPLES_PER_FRAME];

    CHECK(sizeof(pqm_dma_sample_t) == 8u);
    pqm_waveform_init(&state);
    fill_frame(samples, 0xFFFFFC00u);
    CHECK(pqm_waveform_accept_frame(&state, samples));
    CHECK(state.generation == 1u);
    CHECK(state.expected_sequence == 0x00000400u);

    fill_frame(samples, 0x00000400u);
    CHECK(pqm_waveform_accept_frame(&state, samples));
    CHECK(state.generation == 2u);
}

static void test_dropped_regions_preserve_previous_frame(void)
{
    pqm_waveform_t state;
    pqm_dma_sample_t samples[PQM_WAVEFORM_SAMPLES_PER_FRAME];
    pqm_wave_column_t before;
    pqm_wave_column_t after;
    size_t index;

    pqm_waveform_init(&state);
    fill_frame(samples, 0u);
    CHECK(pqm_waveform_accept_frame(&state, samples));
    pqm_waveform_resample(&state, &before, 1u);

    fill_frame(samples, 2048u);
    for (index = 700u; index < PQM_WAVEFORM_SAMPLES_PER_FRAME; ++index) {
        samples[index].sequence += 1u;
        samples[index].u = 12000;
    }
    CHECK(!pqm_waveform_accept_frame(&state, samples));
    CHECK(state.generation == 1u);
    pqm_waveform_resample(&state, &after, 1u);
    CHECK(memcmp(&before, &after, sizeof(before)) == 0);

    fill_frame(samples, 4097u);
    samples[300u].sequence += 2u;
    samples[1200u].sequence += 5u;
    CHECK(!pqm_waveform_accept_frame(&state, samples));
    CHECK(state.generation == 1u);

    fill_frame(samples, 6145u);
    CHECK(pqm_waveform_accept_frame(&state, samples));
    CHECK(state.generation == 2u);
}

static void test_resample_2048_to_400_columns(void)
{
    pqm_waveform_t state;
    pqm_dma_sample_t samples[PQM_WAVEFORM_SAMPLES_PER_FRAME];
    pqm_wave_column_t columns[400];
    size_t column;

    pqm_waveform_init(&state);
    fill_frame(samples, 0u);
    samples[0].u = INT16_MIN;
    samples[PQM_WAVEFORM_SAMPLES_PER_FRAME - 1u].u = INT16_MAX;
    CHECK(pqm_waveform_accept_frame(&state, samples));
    pqm_waveform_resample(&state, columns, 400u);

    CHECK(columns[0].u_min == INT16_MIN);
    CHECK(columns[399].u_max == INT16_MAX);
    for (column = 1u; column < 399u; ++column) {
        size_t begin = (column * PQM_WAVEFORM_SAMPLES_PER_FRAME) / 400u;
        size_t end = ((column + 1u) * PQM_WAVEFORM_SAMPLES_PER_FRAME) / 400u;

        CHECK(columns[column].u_min == (int16_t)begin);
        CHECK(columns[column].u_max == (int16_t)(end - 1u));
        CHECK(columns[column].i_min == (int16_t)-(int32_t)(end - 1u));
        CHECK(columns[column].i_max == (int16_t)-(int32_t)begin);
    }
}

static void test_constant_signed_signal(void)
{
    pqm_waveform_t state;
    pqm_dma_sample_t samples[PQM_WAVEFORM_SAMPLES_PER_FRAME];
    pqm_wave_column_t columns[17];
    size_t index;

    pqm_waveform_init(&state);
    fill_frame(samples, 100u);
    for (index = 0u; index < PQM_WAVEFORM_SAMPLES_PER_FRAME; ++index) {
        samples[index].u = -1234;
        samples[index].i = 32700;
    }
    CHECK(pqm_waveform_accept_frame(&state, samples));
    pqm_waveform_resample(&state, columns, 17u);
    for (index = 0u; index < 17u; ++index) {
        CHECK(columns[index].u_min == -1234);
        CHECK(columns[index].u_max == -1234);
        CHECK(columns[index].i_min == 32700);
        CHECK(columns[index].i_max == 32700);
    }
}

int main(void)
{
    test_contiguous_frames_and_wraparound();
    test_dropped_regions_preserve_previous_frame();
    test_resample_2048_to_400_columns();
    test_constant_signed_signal();

    if (failures != 0) {
        printf("FAIL: pqm_waveform (%d failures)\n", failures);
        return 1;
    }
    printf("PASS: pqm_waveform\n");
    return 0;
}
