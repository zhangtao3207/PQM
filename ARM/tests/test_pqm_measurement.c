/*
 * 测量转换服务主机测试。
 * 验证定点原始值、字段有效位、范围约束和界面字符串格式化。
 */
#include <limits.h>
#include <stdio.h>
#include <string.h>

#include "pqm_measurement.h"

static int failures;

#define CHECK(condition)                                                        \
    do {                                                                        \
        if (!(condition)) {                                                     \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #condition);       \
            failures += 1;                                                      \
        }                                                                       \
    } while (0)

static pqm_measurement_raw_t complete_raw(void)
{
    pqm_measurement_raw_t raw = {0};

    raw.validity = PQM_VALID_ALL_FIELDS;
    return raw;
}

static void check_text(const pqm_measurement_t *measurement,
                       pqm_measurement_field_t field,
                       const char *expected)
{
    char text[32];

    memset(text, 'X', sizeof(text));
    CHECK(pqm_measurement_format(measurement, field, text, sizeof(text)));
    CHECK(strcmp(text, expected) == 0);
    CHECK(text[sizeof(text) - 1u] == 'X');
}

static void test_conversion_and_units(void)
{
    pqm_measurement_raw_t raw = complete_raw();
    pqm_measurement_t measurement;

    raw.sequence = 77u;
    raw.u_rms_x100 = 23012;
    raw.i_rms_x100 = 512;
    raw.u_p2p_x100 = 65025;
    raw.i_p2p_x100 = 1440;
    raw.frequency_x100 = 5000;
    raw.phase_x100 = 1234;
    raw.active_power_x100 = -12345;
    raw.reactive_power_x100 = 6789;
    raw.apparent_power_x100 = 14034;
    raw.power_factor_x100 = -88;
    raw.thd_u_x100 = 350;
    raw.thd_i_x100 = 725;
    raw.dc_u_x100 = 125;
    raw.dc_i_x100 = -250;
    raw.alarm = 0x13u;

    pqm_measurement_from_raw(&measurement, &raw);
    CHECK(measurement.sequence == 77u);
    CHECK(measurement.alarm == 0x13u);
    check_text(&measurement, PQM_MEAS_U_RMS, "230.12 V");
    check_text(&measurement, PQM_MEAS_I_RMS, "5.12 A");
    check_text(&measurement, PQM_MEAS_U_P2P, "650.25 V");
    check_text(&measurement, PQM_MEAS_I_P2P, "14.40 A");
    check_text(&measurement, PQM_MEAS_FREQUENCY, "50.00 Hz");
    check_text(&measurement, PQM_MEAS_PHASE, "+12.34 deg");
    check_text(&measurement, PQM_MEAS_ACTIVE_POWER, "-123.45 W");
    check_text(&measurement, PQM_MEAS_REACTIVE_POWER, "+67.89 var");
    check_text(&measurement, PQM_MEAS_APPARENT_POWER, "140.34 VA");
    check_text(&measurement, PQM_MEAS_POWER_FACTOR, "-0.88");
    check_text(&measurement, PQM_MEAS_THD_U, "3.50 %");
    check_text(&measurement, PQM_MEAS_THD_I, "7.25 %");
    check_text(&measurement, PQM_MEAS_DC_U, "1.25 %");
    check_text(&measurement, PQM_MEAS_DC_I, "0.00 %");
}

static void test_zero_sign_and_invalid_fields(void)
{
    pqm_measurement_raw_t raw = complete_raw();
    pqm_measurement_t measurement;

    pqm_measurement_from_raw(&measurement, &raw);
    check_text(&measurement, PQM_MEAS_U_RMS, "0.00 V");
    check_text(&measurement, PQM_MEAS_PHASE, "+0.00 deg");
    check_text(&measurement, PQM_MEAS_REACTIVE_POWER, "+0.00 var");
    check_text(&measurement, PQM_MEAS_ACTIVE_POWER, "0.00 W");

    raw.validity &= ~(PQM_VALID_U_RMS | PQM_VALID_PHASE |
                      PQM_VALID_POWER_METRICS | PQM_VALID_THD_U);
    pqm_measurement_from_raw(&measurement, &raw);
    check_text(&measurement, PQM_MEAS_U_RMS, "-- V");
    check_text(&measurement, PQM_MEAS_PHASE, "-- deg");
    check_text(&measurement, PQM_MEAS_ACTIVE_POWER, "-- W");
    check_text(&measurement, PQM_MEAS_POWER_FACTOR, "--");
    check_text(&measurement, PQM_MEAS_THD_U, "-- %");
}

static void test_saturation_and_integer_extremes(void)
{
    pqm_measurement_raw_t raw = complete_raw();
    pqm_measurement_t measurement;

    raw.u_rms_x100 = INT_MAX;
    raw.active_power_x100 = INT_MIN;
    raw.phase_x100 = INT_MAX;
    raw.reactive_power_x100 = INT_MIN;
    raw.power_factor_x100 = INT_MAX;
    raw.thd_u_x100 = INT_MAX;
    raw.frequency_x100 = INT_MIN;
    pqm_measurement_from_raw(&measurement, &raw);

    check_text(&measurement, PQM_MEAS_U_RMS, "999.99 V");
    check_text(&measurement, PQM_MEAS_ACTIVE_POWER, "-999.99 W");
    check_text(&measurement, PQM_MEAS_PHASE, "+999.99 deg");
    check_text(&measurement, PQM_MEAS_REACTIVE_POWER, "-999.99 var");
    check_text(&measurement, PQM_MEAS_POWER_FACTOR, "9.99");
    check_text(&measurement, PQM_MEAS_THD_U, "999.99 %");
    check_text(&measurement, PQM_MEAS_FREQUENCY, "0.00 Hz");
}

static void test_small_buffer_is_terminated(void)
{
    pqm_measurement_raw_t raw = complete_raw();
    pqm_measurement_t measurement;
    char text[5] = {'X', 'X', 'X', 'X', 'X'};

    raw.u_rms_x100 = 12345;
    pqm_measurement_from_raw(&measurement, &raw);
    CHECK(!pqm_measurement_format(&measurement, PQM_MEAS_U_RMS,
                                  text, sizeof(text)));
    CHECK(text[sizeof(text) - 1u] == '\0');
    CHECK(!pqm_measurement_format(&measurement, PQM_MEAS_U_RMS, NULL, 0u));
}

int main(void)
{
    test_conversion_and_units();
    test_zero_sign_and_invalid_fields();
    test_saturation_and_integer_extremes();
    test_small_buffer_is_terminated();

    if (failures != 0) {
        printf("pqm_measurement: %d failure(s)\n", failures);
        return 1;
    }
    printf("pqm_measurement: all tests passed\n");
    return 0;
}
