#include "pqm_measurement.h"

#include <stdio.h>

typedef struct {
    uint32_t valid_mask;
    int32_t minimum_x100;
    int32_t maximum_x100;
    const char *unit;
    bool force_sign;
} pqm_measurement_spec_t;

/* All shared scalar values are engineering units scaled by 100. */
static const pqm_measurement_spec_t field_specs[PQM_MEAS_FIELD_COUNT] = {
    {PQM_VALID_U_RMS,         0,       99999, "V",   false},
    {PQM_VALID_I_RMS,         0,       99999, "A",   false},
    {PQM_VALID_U_P2P,         0,       99999, "V",   false},
    {PQM_VALID_I_P2P,         0,       99999, "A",   false},
    {PQM_VALID_FREQUENCY,     0,       99999, "Hz",  false},
    {PQM_VALID_PHASE,    -99999,       99999, "deg", true},
    {PQM_VALID_POWER_METRICS, -99999,  99999, "W",   false},
    {PQM_VALID_POWER_METRICS, -99999,  99999, "var", true},
    {PQM_VALID_POWER_METRICS,      0,  99999, "VA",  false},
    {PQM_VALID_POWER_METRICS,   -999,    999, "",    false},
    {PQM_VALID_THD_U,             0,   99999, "%",   false},
    {PQM_VALID_THD_I,             0,   99999, "%",   false},
    {PQM_VALID_DC_U,              0,   99999, "%",   false},
    {PQM_VALID_DC_I,              0,   99999, "%",   false}
};

static int32_t clamp_x100(int32_t value, const pqm_measurement_spec_t *spec)
{
    if (value < spec->minimum_x100) {
        return spec->minimum_x100;
    }
    if (value > spec->maximum_x100) {
        return spec->maximum_x100;
    }
    return value;
}

void pqm_measurement_from_raw(pqm_measurement_t *measurement,
                              const pqm_measurement_raw_t *raw)
{
    int32_t raw_values[PQM_MEAS_FIELD_COUNT];
    size_t field;

    if (measurement == NULL || raw == NULL) {
        return;
    }
    raw_values[PQM_MEAS_U_RMS] = raw->u_rms_x100;
    raw_values[PQM_MEAS_I_RMS] = raw->i_rms_x100;
    raw_values[PQM_MEAS_U_P2P] = raw->u_p2p_x100;
    raw_values[PQM_MEAS_I_P2P] = raw->i_p2p_x100;
    raw_values[PQM_MEAS_FREQUENCY] = raw->frequency_x100;
    raw_values[PQM_MEAS_PHASE] = raw->phase_x100;
    raw_values[PQM_MEAS_ACTIVE_POWER] = raw->active_power_x100;
    raw_values[PQM_MEAS_REACTIVE_POWER] = raw->reactive_power_x100;
    raw_values[PQM_MEAS_APPARENT_POWER] = raw->apparent_power_x100;
    raw_values[PQM_MEAS_POWER_FACTOR] = raw->power_factor_x100;
    raw_values[PQM_MEAS_THD_U] = raw->thd_u_x100;
    raw_values[PQM_MEAS_THD_I] = raw->thd_i_x100;
    raw_values[PQM_MEAS_DC_U] = raw->dc_u_x100;
    raw_values[PQM_MEAS_DC_I] = raw->dc_i_x100;
    measurement->sequence = raw->sequence;
    measurement->alarm = raw->alarm;
    for (field = 0u; field < PQM_MEAS_FIELD_COUNT; ++field) {
        measurement->values[field].x100 =
            clamp_x100(raw_values[field], &field_specs[field]);
        measurement->values[field].valid =
            (raw->validity & field_specs[field].valid_mask) != 0u;
    }
}

const pqm_measurement_value_t *pqm_measurement_get(
    const pqm_measurement_t *measurement, pqm_measurement_field_t field)
{
    if (measurement == NULL || field < PQM_MEAS_U_RMS ||
        field >= PQM_MEAS_FIELD_COUNT) {
        return NULL;
    }
    return &measurement->values[field];
}

bool pqm_measurement_format(const pqm_measurement_t *measurement,
                            pqm_measurement_field_t field,
                            char *buffer, size_t buffer_size)
{
    const pqm_measurement_spec_t *spec;
    const pqm_measurement_value_t *value;
    int64_t magnitude;
    unsigned long whole;
    unsigned long fraction;
    int result;
    char sign;

    if (buffer == NULL || buffer_size == 0u) {
        return false;
    }
    buffer[0] = '\0';
    value = pqm_measurement_get(measurement, field);
    if (value == NULL) {
        return false;
    }
    spec = &field_specs[field];
    if (!value->valid) {
        result = spec->unit[0] != '\0'
                     ? snprintf(buffer, buffer_size, "-- %s", spec->unit)
                     : snprintf(buffer, buffer_size, "--");
    } else {
        magnitude = value->x100;
        sign = '\0';
        if (magnitude < 0) {
            sign = '-';
            magnitude = -magnitude;
        } else if (spec->force_sign) {
            sign = '+';
        }
        whole = (unsigned long)(magnitude / 100);
        fraction = (unsigned long)(magnitude % 100);
        if (spec->unit[0] != '\0') {
            result = sign != '\0'
                         ? snprintf(buffer, buffer_size, "%c%lu.%02lu %s",
                                    sign, whole, fraction, spec->unit)
                         : snprintf(buffer, buffer_size, "%lu.%02lu %s",
                                    whole, fraction, spec->unit);
        } else {
            result = sign != '\0'
                         ? snprintf(buffer, buffer_size, "%c%lu.%02lu",
                                    sign, whole, fraction)
                         : snprintf(buffer, buffer_size, "%lu.%02lu",
                                    whole, fraction);
        }
    }
    if (result < 0 || (size_t)result >= buffer_size) {
        buffer[buffer_size - 1u] = '\0';
        return false;
    }
    return true;
}
