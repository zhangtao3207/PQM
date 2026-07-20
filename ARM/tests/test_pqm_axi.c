#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "pqm_axi.h"

#define MOCK_WORD_COUNT 0x1400u

typedef struct {
    uint32_t words[MOCK_WORD_COUNT];
    bool mutate_snapshot;
    bool auto_respond;
    bool corrupt_range_response;
    uint32_t scalar_reads;
} mock_memory_t;

#define EXPECTED_SET_RANGE_COMMAND 0x00000001u

extern bool pqm_axi_set_range(pqm_axi_t *axi, bool low_range,
                              uint32_t timeout_polls);

static int failures;

#define CHECK(condition)                                                        \
    do {                                                                        \
        if (!(condition)) {                                                     \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #condition);       \
            failures += 1;                                                      \
        }                                                                       \
    } while (0)

static uint32_t mock_read_word(void *context, uint32_t word_offset)
{
    mock_memory_t *memory = (mock_memory_t *)context;

    if (word_offset >= MOCK_WORD_COUNT) {
        return 0u;
    }

    if (word_offset == PQM_SHM_SCALAR_BASE_WORD) {
        memory->scalar_reads += 1u;
        if (memory->mutate_snapshot) {
            memory->words[PQM_SHM_SNAPSHOT_SEQ_WORD] += 1u;
            memory->words[PQM_SHM_SCALAR_U_RMS_WORD] = 22222u;
            memory->mutate_snapshot = false;
        }
    }

    return memory->words[word_offset];
}

static void mock_write_word(void *context, uint32_t word_offset, uint32_t value)
{
    mock_memory_t *memory = (mock_memory_t *)context;

    if (word_offset >= MOCK_WORD_COUNT) {
        return;
    }

    memory->words[word_offset] = value;
    if (memory->auto_respond && word_offset == PQM_SHM_COMMAND_SEQUENCE_WORD) {
        if (memory->words[PQM_SHM_COMMAND_REQUEST_WORD] ==
            EXPECTED_SET_RANGE_COMMAND) {
            memory->words[PQM_SHM_COMMAND_RESPONSE_WORD] =
                memory->corrupt_range_response
                    ? 2u
                    : memory->words[PQM_SHM_COMMAND_ARGUMENT_WORD];
        } else {
            memory->words[PQM_SHM_COMMAND_RESPONSE_WORD] = 0xA55A1234u;
        }
        memory->words[PQM_SHM_COMMAND_RESPONSE_SEQ_WORD] = value;
    }
}

static pqm_axi_t make_axi(mock_memory_t *memory)
{
    pqm_axi_t axi;

    pqm_axi_init(&axi, memory, mock_read_word, mock_write_word);
    return axi;
}

static void initialize_valid_memory(mock_memory_t *memory)
{
    memset(memory, 0, sizeof(*memory));
    memory->words[PQM_SHM_MAGIC_WORD] = PQM_SHM_MAGIC;
    memory->words[PQM_SHM_ABI_WORD] = PQM_SHM_ABI_VERSION;
    memory->words[PQM_SHM_CAPABILITIES_WORD] = PQM_SHM_CAPABILITIES;
    memory->words[PQM_SHM_STATUS_WORD] = PQM_SHM_STATUS_SNAPSHOT_VALID;
    memory->words[PQM_SHM_SNAPSHOT_SEQ_WORD] = 7u;
    memory->words[PQM_SHM_SCALAR_U_RMS_WORD] = 23012u;
    memory->words[PQM_SHM_SCALAR_I_RMS_WORD] = 512u;
    memory->words[PQM_SHM_SCALAR_U_P2P_WORD] = 65000u;
    memory->words[PQM_SHM_SCALAR_I_P2P_WORD] = 1400u;
    memory->words[PQM_SHM_SCALAR_FREQUENCY_WORD] = 5000u;
    memory->words[PQM_SHM_SCALAR_PHASE_WORD] = (uint32_t)(int32_t)-1234;
    memory->words[PQM_SHM_SCALAR_ACTIVE_POWER_WORD] = (uint32_t)(int32_t)-900;
    memory->words[PQM_SHM_SCALAR_REACTIVE_POWER_WORD] = (uint32_t)(int32_t)-321;
    memory->words[PQM_SHM_SCALAR_APPARENT_POWER_WORD] = 1024u;
    memory->words[PQM_SHM_SCALAR_POWER_FACTOR_WORD] = (uint32_t)(int32_t)-88;
    memory->words[PQM_SHM_SCALAR_THD_U_WORD] = 350u;
    memory->words[PQM_SHM_SCALAR_THD_I_WORD] = 725u;
    memory->words[PQM_SHM_SCALAR_DC_U_WORD] = 12u;
    memory->words[PQM_SHM_SCALAR_DC_I_WORD] = 34u;
    memory->words[PQM_SHM_SCALAR_ALARM_WORD] = 0x31u;
    memory->words[PQM_SHM_SCALAR_VALIDITY_WORD] = 0x7FFu;
}

static void test_validate_identity(void)
{
    mock_memory_t memory;
    pqm_axi_t axi;

    initialize_valid_memory(&memory);
    axi = make_axi(&memory);
    CHECK(pqm_axi_validate(&axi));

    memory.words[PQM_SHM_MAGIC_WORD] = 0u;
    CHECK(!pqm_axi_validate(&axi));

    memory.words[PQM_SHM_MAGIC_WORD] = PQM_SHM_MAGIC;
    memory.words[PQM_SHM_ABI_WORD] += 1u;
    CHECK(!pqm_axi_validate(&axi));
}

static void test_stable_snapshot_and_signed_fields(void)
{
    mock_memory_t memory;
    pqm_axi_t axi;
    pqm_measurement_raw_t snapshot;

    initialize_valid_memory(&memory);
    axi = make_axi(&memory);

    CHECK(pqm_axi_read_snapshot(&axi, &snapshot));
    CHECK(snapshot.sequence == 7u);
    CHECK(snapshot.u_rms_x100 == 23012);
    CHECK(snapshot.frequency_x100 == 5000);
    CHECK(snapshot.phase_x100 == -1234);
    CHECK(snapshot.active_power_x100 == -900);
    CHECK(snapshot.reactive_power_x100 == -321);
    CHECK(snapshot.power_factor_x100 == -88);
    CHECK(snapshot.alarm == 0x31u);
    CHECK(snapshot.validity == 0x7FFu);
}

static void test_snapshot_retries_changed_sequence(void)
{
    mock_memory_t memory;
    pqm_axi_t axi;
    pqm_measurement_raw_t snapshot;

    initialize_valid_memory(&memory);
    memory.mutate_snapshot = true;
    axi = make_axi(&memory);

    CHECK(pqm_axi_read_snapshot(&axi, &snapshot));
    CHECK(snapshot.sequence == 8u);
    CHECK(snapshot.u_rms_x100 == 22222);
    CHECK(memory.scalar_reads >= 2u);
}

static void test_command_response_and_timeout(void)
{
    mock_memory_t memory;
    pqm_axi_t axi;
    uint32_t response = 0u;

    initialize_valid_memory(&memory);
    axi = make_axi(&memory);

    CHECK(!pqm_axi_send_command(&axi, 0x12u, 0x34u, 3u, &response));
    CHECK(memory.words[PQM_SHM_COMMAND_REQUEST_WORD] == 0x12u);
    CHECK(memory.words[PQM_SHM_COMMAND_ARGUMENT_WORD] == 0x34u);
    CHECK(memory.words[PQM_SHM_COMMAND_SEQUENCE_WORD] == 1u);

    memory.auto_respond = true;
    CHECK(pqm_axi_send_command(&axi, 0x56u, 0x78u, 3u, &response));
    CHECK(memory.words[PQM_SHM_COMMAND_SEQUENCE_WORD] == 2u);
    CHECK(response == 0xA55A1234u);
}

static void test_harmonic_bank_snapshot(void)
{
    mock_memory_t memory;
    pqm_axi_t axi;
    pqm_harmonic_raw_snapshot_t harmonics;
    uint32_t entry_base;

    initialize_valid_memory(&memory);
    memory.words[PQM_SHM_STATUS_WORD] |=
        PQM_SHM_STATUS_HARMONIC_VALID | PQM_SHM_STATUS_HARMONIC_BANK;
    memory.words[PQM_SHM_HARMONIC_GENERATION_WORD] = 19u;
    entry_base = PQM_SHM_HARMONIC_BANK1_WORD +
                 (17u * PQM_SHM_HARMONIC_ENTRY_WORDS);
    memory.words[entry_base] = 8750u;
    memory.words[entry_base + 1u] = 6250u;
    memory.words[entry_base + 2u] = (uint32_t)(int32_t)-1234;
    memory.words[entry_base + 3u] = 3u;
    axi = make_axi(&memory);

    CHECK(pqm_axi_read_harmonics(&axi, &harmonics));
    CHECK(harmonics.generation == 19u);
    CHECK(harmonics.entries[17].u_ratio_x100 == 8750u);
    CHECK(harmonics.entries[17].i_ratio_x100 == 6250u);
    CHECK(harmonics.entries[17].phase_x100 == -1234);
    CHECK(harmonics.entries[17].flags == 3u);

    memory.words[PQM_SHM_STATUS_WORD] &= ~PQM_SHM_STATUS_HARMONIC_VALID;
    CHECK(!pqm_axi_read_harmonics(&axi, &harmonics));
}

static void test_set_range_requires_matching_pl_acknowledgement(void)
{
    mock_memory_t memory;
    pqm_axi_t axi;

    initialize_valid_memory(&memory);
    memory.auto_respond = true;
    axi = make_axi(&memory);

    CHECK(pqm_axi_set_range(&axi, true, 3u));
    CHECK(memory.words[PQM_SHM_COMMAND_REQUEST_WORD] ==
          EXPECTED_SET_RANGE_COMMAND);
    CHECK(memory.words[PQM_SHM_COMMAND_ARGUMENT_WORD] == 1u);

    CHECK(pqm_axi_set_range(&axi, false, 3u));
    CHECK(memory.words[PQM_SHM_COMMAND_ARGUMENT_WORD] == 0u);

    memory.corrupt_range_response = true;
    CHECK(!pqm_axi_set_range(&axi, true, 3u));
}

int main(void)
{
    test_validate_identity();
    test_stable_snapshot_and_signed_fields();
    test_snapshot_retries_changed_sequence();
    test_command_response_and_timeout();
    test_harmonic_bank_snapshot();
    test_set_range_requires_matching_pl_acknowledgement();

    if (failures != 0) {
        printf("FAIL: pqm_axi (%d failures)\n", failures);
        return 1;
    }

    printf("PASS: pqm_axi\n");
    return 0;
}
