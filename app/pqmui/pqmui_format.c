/*
 * 工程量格式化实现。
 *
 * 字段顺序与 pqmui_field_t 一致：取值范围、单位与是否强制显示正号都在
 * FieldSpec 表里，格式化时先把输入按量程限幅再输出文本。
 */

#include "pqmui_format.h"

#include <stdio.h>

typedef struct {
    s32 minimum_x100;
    s32 maximum_x100;
    const char *unit;
    u8 force_sign;
} pqmui_field_spec_t;

static const pqmui_field_spec_t FieldSpec[PQMUI_FIELD_COUNT] = {
    {0, 99999, "Hz", 0},        /* PQMUI_FIELD_FREQUENCY */
    {0, 99999, "V", 0},         /* PQMUI_FIELD_U_RMS */
    {0, 99999, "A", 0},         /* PQMUI_FIELD_I_RMS */
    {0, 99999, "V", 0},         /* PQMUI_FIELD_U_P2P */
    {0, 99999, "A", 0},         /* PQMUI_FIELD_I_P2P */
    {-99999, 99999, "deg", 1},  /* PQMUI_FIELD_PHASE */
    {-99999, 99999, "W", 0},    /* PQMUI_FIELD_ACTIVE_POWER */
    {-99999, 99999, "var", 1},  /* PQMUI_FIELD_REACTIVE_POWER */
    {0, 99999, "VA", 0},        /* PQMUI_FIELD_APPARENT_POWER */
    {-999, 999, "", 0},         /* PQMUI_FIELD_POWER_FACTOR */
    {0, 99999, "%", 0},         /* PQMUI_FIELD_THD_U */
    {0, 99999, "%", 0},         /* PQMUI_FIELD_THD_I */
    {0, 99999, "%", 0},         /* PQMUI_FIELD_DC_U */
    {0, 99999, "%", 0}          /* PQMUI_FIELD_DC_I */
};

s32 PQMUI_FieldClampX100(pqmui_field_t field, s32 x100)
{
    const pqmui_field_spec_t *spec;

    if (field < 0 || field >= PQMUI_FIELD_COUNT) {
        return x100;
    }
    spec = &FieldSpec[field];
    if (x100 < spec->minimum_x100) {
        return spec->minimum_x100;
    }
    if (x100 > spec->maximum_x100) {
        return spec->maximum_x100;
    }
    return x100;
}

u8 PQMUI_FieldFormat(pqmui_field_t field, const pqmui_value_t *value,
                     char *buffer, u32 size)
{
    const pqmui_field_spec_t *spec;
    s32 magnitude;
    u32 whole;
    u32 fraction;
    char sign;
    int result;

    if (buffer == NULL || size == 0u) {
        return 0u;
    }
    buffer[0] = '\0';
    if (value == NULL || field < 0 || field >= PQMUI_FIELD_COUNT) {
        return 0u;
    }

    spec = &FieldSpec[field];
    if (!value->valid) {
        if (spec->unit[0] != '\0') {
            result = snprintf(buffer, size, "-- %s", spec->unit);
        } else {
            result = snprintf(buffer, size, "--");
        }
    } else {
        magnitude = PQMUI_FieldClampX100(field, value->x100);
        sign = '\0';
        if (magnitude < 0) {
            sign = '-';
            magnitude = -magnitude;
        } else if (spec->force_sign) {
            sign = '+';
        }
        whole = (u32)(magnitude / 100);
        fraction = (u32)(magnitude % 100);
        if (spec->unit[0] != '\0') {
            if (sign != '\0') {
                result = snprintf(buffer, size, "%c%u.%02u %s", sign,
                                  (unsigned int)whole, (unsigned int)fraction,
                                  spec->unit);
            } else {
                result = snprintf(buffer, size, "%u.%02u %s",
                                  (unsigned int)whole, (unsigned int)fraction,
                                  spec->unit);
            }
        } else {
            if (sign != '\0') {
                result = snprintf(buffer, size, "%c%u.%02u", sign,
                                  (unsigned int)whole, (unsigned int)fraction);
            } else {
                result = snprintf(buffer, size, "%u.%02u",
                                  (unsigned int)whole, (unsigned int)fraction);
            }
        }
    }

    if (result < 0 || (u32)result >= size) {
        buffer[size - 1u] = '\0';
        return 0u;
    }
    return 1u;
}
