#include "pqm_axi.h"

#include <stddef.h>

static uint32_t pqm_mmio_read_word(void *context, uint32_t word_offset)
{
    uintptr_t base_address = (uintptr_t)context;
    volatile const uint32_t *words = (volatile const uint32_t *)base_address;

    return words[word_offset];
}

static void pqm_mmio_write_word(void *context, uint32_t word_offset, uint32_t value)
{
    uintptr_t base_address = (uintptr_t)context;
    volatile uint32_t *words = (volatile uint32_t *)base_address;

    words[word_offset] = value;
}

static bool pqm_axi_can_read(const pqm_axi_t *axi)
{
    return axi != NULL && axi->read_word != NULL;
}

static bool pqm_axi_can_write(const pqm_axi_t *axi)
{
    return pqm_axi_can_read(axi) && axi->write_word != NULL;
}

static int32_t pqm_decode_signed_word(uint32_t word)
{
    if ((word & 0x80000000u) == 0u) {
        return (int32_t)word;
    }

    return -1 - (int32_t)(~word);
}

static int16_t pqm_decode_signed_halfword(uint32_t word)
{
    uint16_t value = (uint16_t)word;

    if ((value & 0x8000u) == 0u) {
        return (int16_t)value;
    }
    return (int16_t)(-1 - (int32_t)(uint16_t)(~value));
}

void pqm_axi_init(pqm_axi_t *axi, void *context,
                  pqm_read_word_fn read_word, pqm_write_word_fn write_word)
{
    if (axi == NULL) {
        return;
    }

    axi->context = context;
    axi->read_word = read_word;
    axi->write_word = write_word;
    axi->next_command_sequence = 0u;
}

void pqm_axi_init_mmio(pqm_axi_t *axi, uintptr_t base_address)
{
    pqm_axi_init(axi, (void *)base_address, pqm_mmio_read_word, pqm_mmio_write_word);
}

bool pqm_axi_validate(pqm_axi_t *axi)
{
    uint32_t capabilities;

    if (!pqm_axi_can_read(axi)) {
        return false;
    }

    if (axi->read_word(axi->context, PQM_SHM_MAGIC_WORD) != PQM_SHM_MAGIC) {
        return false;
    }

    if (axi->read_word(axi->context, PQM_SHM_ABI_WORD) != PQM_SHM_ABI_VERSION) {
        return false;
    }

    capabilities = axi->read_word(axi->context, PQM_SHM_CAPABILITIES_WORD);
    return (capabilities & PQM_SHM_CAPABILITIES) == PQM_SHM_CAPABILITIES;
}

bool pqm_axi_read_snapshot(pqm_axi_t *axi, pqm_measurement_raw_t *out)
{
    uint32_t attempt;

    if (!pqm_axi_can_read(axi) || out == NULL) {
        return false;
    }

    for (attempt = 0u; attempt < PQM_AXI_SNAPSHOT_MAX_RETRIES; ++attempt) {
        pqm_measurement_raw_t snapshot;
        uint32_t sequence_before;
        uint32_t sequence_after;
        uint32_t status;

        sequence_before = axi->read_word(axi->context, PQM_SHM_SNAPSHOT_SEQ_WORD);
        status = axi->read_word(axi->context, PQM_SHM_STATUS_WORD);
        if ((status & PQM_SHM_STATUS_SNAPSHOT_VALID) == 0u) {
            return false;
        }

        snapshot.u_rms_x100 = pqm_decode_signed_word(
            axi->read_word(axi->context, PQM_SHM_SCALAR_U_RMS_WORD));
        snapshot.i_rms_x100 = pqm_decode_signed_word(
            axi->read_word(axi->context, PQM_SHM_SCALAR_I_RMS_WORD));
        snapshot.u_p2p_x100 = pqm_decode_signed_word(
            axi->read_word(axi->context, PQM_SHM_SCALAR_U_P2P_WORD));
        snapshot.i_p2p_x100 = pqm_decode_signed_word(
            axi->read_word(axi->context, PQM_SHM_SCALAR_I_P2P_WORD));
        snapshot.frequency_x100 = pqm_decode_signed_word(
            axi->read_word(axi->context, PQM_SHM_SCALAR_FREQUENCY_WORD));
        snapshot.phase_x100 = pqm_decode_signed_word(
            axi->read_word(axi->context, PQM_SHM_SCALAR_PHASE_WORD));
        snapshot.active_power_x100 = pqm_decode_signed_word(
            axi->read_word(axi->context, PQM_SHM_SCALAR_ACTIVE_POWER_WORD));
        snapshot.reactive_power_x100 = pqm_decode_signed_word(
            axi->read_word(axi->context, PQM_SHM_SCALAR_REACTIVE_POWER_WORD));
        snapshot.apparent_power_x100 = pqm_decode_signed_word(
            axi->read_word(axi->context, PQM_SHM_SCALAR_APPARENT_POWER_WORD));
        snapshot.power_factor_x100 = pqm_decode_signed_word(
            axi->read_word(axi->context, PQM_SHM_SCALAR_POWER_FACTOR_WORD));
        snapshot.thd_u_x100 = pqm_decode_signed_word(
            axi->read_word(axi->context, PQM_SHM_SCALAR_THD_U_WORD));
        snapshot.thd_i_x100 = pqm_decode_signed_word(
            axi->read_word(axi->context, PQM_SHM_SCALAR_THD_I_WORD));
        snapshot.dc_u_x100 = pqm_decode_signed_word(
            axi->read_word(axi->context, PQM_SHM_SCALAR_DC_U_WORD));
        snapshot.dc_i_x100 = pqm_decode_signed_word(
            axi->read_word(axi->context, PQM_SHM_SCALAR_DC_I_WORD));
        snapshot.alarm = axi->read_word(axi->context, PQM_SHM_SCALAR_ALARM_WORD);
        snapshot.validity = axi->read_word(axi->context, PQM_SHM_SCALAR_VALIDITY_WORD);

        sequence_after = axi->read_word(axi->context, PQM_SHM_SNAPSHOT_SEQ_WORD);
        if (sequence_before == sequence_after) {
            snapshot.sequence = sequence_after;
            *out = snapshot;
            return true;
        }
    }

    return false;
}

bool pqm_axi_read_harmonics(pqm_axi_t *axi,
                            pqm_harmonic_raw_snapshot_t *out)
{
    uint32_t attempt;

    if (!pqm_axi_can_read(axi) || out == NULL) {
        return false;
    }
    for (attempt = 0u; attempt < PQM_AXI_SNAPSHOT_MAX_RETRIES; ++attempt) {
        uint32_t generation_before;
        uint32_t generation_after;
        uint32_t status_before;
        uint32_t status_after;
        uint32_t bank_base;
        uint32_t index;

        status_before = axi->read_word(axi->context, PQM_SHM_STATUS_WORD);
        if ((status_before & PQM_SHM_STATUS_HARMONIC_VALID) == 0u) {
            return false;
        }
        generation_before = axi->read_word(
            axi->context, PQM_SHM_HARMONIC_GENERATION_WORD);
        bank_base = (status_before & PQM_SHM_STATUS_HARMONIC_BANK) != 0u
                        ? PQM_SHM_HARMONIC_BANK1_WORD
                        : PQM_SHM_HARMONIC_BANK0_WORD;
        for (index = 0u; index < PQM_HARMONIC_ENTRY_COUNT; ++index) {
            uint32_t entry_base = bank_base +
                (index * PQM_SHM_HARMONIC_ENTRY_WORDS);

            out->entries[index].u_ratio_x100 = (uint16_t)
                axi->read_word(axi->context, entry_base);
            out->entries[index].i_ratio_x100 = (uint16_t)
                axi->read_word(axi->context, entry_base + 1u);
            out->entries[index].phase_x100 = pqm_decode_signed_halfword(
                axi->read_word(axi->context, entry_base + 2u));
            out->entries[index].flags = (uint8_t)
                axi->read_word(axi->context, entry_base + 3u);
        }
        generation_after = axi->read_word(
            axi->context, PQM_SHM_HARMONIC_GENERATION_WORD);
        status_after = axi->read_word(axi->context, PQM_SHM_STATUS_WORD);
        if (generation_before == generation_after &&
            ((status_before ^ status_after) &
             (PQM_SHM_STATUS_HARMONIC_BANK |
              PQM_SHM_STATUS_HARMONIC_VALID)) == 0u) {
            out->generation = generation_after;
            return true;
        }
    }
    return false;
}

bool pqm_axi_send_command(pqm_axi_t *axi, uint32_t command, uint32_t argument,
                          uint32_t timeout_polls, uint32_t *response)
{
    uint32_t poll;
    uint32_t sequence;

    if (!pqm_axi_can_write(axi) || timeout_polls == 0u) {
        return false;
    }

    sequence = axi->next_command_sequence + 1u;
    if (sequence == 0u) {
        sequence = 1u;
    }
    axi->next_command_sequence = sequence;

    axi->write_word(axi->context, PQM_SHM_COMMAND_REQUEST_WORD, command);
    axi->write_word(axi->context, PQM_SHM_COMMAND_ARGUMENT_WORD, argument);
    axi->write_word(axi->context, PQM_SHM_COMMAND_SEQUENCE_WORD, sequence);

    for (poll = 0u; poll < timeout_polls; ++poll) {
        if (axi->read_word(axi->context, PQM_SHM_COMMAND_RESPONSE_SEQ_WORD) == sequence) {
            if (response != NULL) {
                *response = axi->read_word(axi->context, PQM_SHM_COMMAND_RESPONSE_WORD);
            }
            return true;
        }
    }

    return false;
}
