/*
 * 工程量格式化实现。
 *
 * 字段顺序与 pqmui_field_t 一致：取值范围、单位与是否强制显示正号都在
 * FieldSpec 表里，格式化时先把输入按量程限幅再输出文本。
 *
 * 本层还提供 ABI 真值 → 显示值的换算：大量程下把真值按模拟市电系数放大
 * （见 PQMUI_ApplySimScale），小量程系数为 1。因此 FieldSpec 的上下限是
 * “显示域”的限幅，已包含缩放后的量程。
 */

#include "pqmui_format.h"

#include <limits.h>
#include <stdio.h>

typedef struct {
    s32 minimum_x100;
    s32 maximum_x100;
    const char *unit;
    u8 force_sign;
} pqmui_field_spec_t;

/* 显示域的取值上限：真值上限 × 模拟市电系数。
 * ABI/PL 把真值统一限幅在 99999（999.99）以内，但大量程要按 K=38.89、K²=1512.43 放大，
 * 所以显示域上限取“大量程满量程”这一物理上限：
 *   U/I 有效值 388.90 = 10.00 × 38.89；峰峰值 777.80 = 20.00 × 38.89；
 *   有功/无功/视在 151243.00 = 388.90 × 388.90。
 * 注意：若这里沿用真值域的 99999，大量程下 P=1.48 W（×1512.43 = 2238.40 W）会被
 * 截成 999.99 W，数值就与纵轴不同倍了。小量程真值远小于这些上限，不受影响。 */
#define PQMUI_FIELD_MAX_RMS_X100    ((s32)(1000u * PQMUI_SIM_SCALE_X100 / 100u))         /* 38890 = 388.90 */
#define PQMUI_FIELD_MAX_P2P_X100    ((s32)(2000u * PQMUI_SIM_SCALE_X100 / 100u))         /* 77780 = 777.80 */
#define PQMUI_FIELD_MAX_POWER_X100  ((s32)(10000u * PQMUI_SIM_POWER_SCALE_X100 / 100u))  /* 15124300 = 151243.00 */

static const pqmui_field_spec_t FieldSpec[PQMUI_FIELD_COUNT] = {
    {0, 99999, "Hz", 0},                        /* PQMUI_FIELD_FREQUENCY（不缩放） */
    {0, PQMUI_FIELD_MAX_RMS_X100, "V", 0},      /* PQMUI_FIELD_U_RMS（×38.89） */
    {0, PQMUI_FIELD_MAX_RMS_X100, "A", 0},      /* PQMUI_FIELD_I_RMS（×38.89，U2 当电流） */
    {0, PQMUI_FIELD_MAX_P2P_X100, "V", 0},      /* PQMUI_FIELD_U_P2P（×38.89） */
    {0, PQMUI_FIELD_MAX_P2P_X100, "A", 0},      /* PQMUI_FIELD_I_P2P（×38.89） */
    {-99999, 99999, "deg", 1},                  /* PQMUI_FIELD_PHASE（不缩放） */
    {-PQMUI_FIELD_MAX_POWER_X100, PQMUI_FIELD_MAX_POWER_X100, "W", 0},   /* PQMUI_FIELD_ACTIVE_POWER（×1512.43） */
    {-PQMUI_FIELD_MAX_POWER_X100, PQMUI_FIELD_MAX_POWER_X100, "var", 1}, /* PQMUI_FIELD_REACTIVE_POWER（×1512.43） */
    {0, PQMUI_FIELD_MAX_POWER_X100, "VA", 0},   /* PQMUI_FIELD_APPARENT_POWER（×1512.43） */
    {-999, 999, "", 0},                         /* PQMUI_FIELD_POWER_FACTOR（不缩放） */
    {0, 99999, "%", 0},                         /* PQMUI_FIELD_THD_U（百分比不缩放） */
    {0, 99999, "%", 0},                         /* PQMUI_FIELD_THD_I（百分比不缩放） */
    {0, 99999, "%", 0},                         /* PQMUI_FIELD_DC_U（百分比不缩放） */
    {0, 99999, "%", 0}                          /* PQMUI_FIELD_DC_I（百分比不缩放） */
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

/* 每个字段的「真值 → 模拟市电显示值」缩放系数，x100 定点：
 *   100    = ×1.00（频率、相位、功率因数、THD、DC 都是比例或角度，不缩放）
 *   3889   = ×38.89（有效值、峰峰值）
 *   151243 = ×1512.43（有功/无功/视在，P = U × I 的量纲是 K 的平方） */
static const u32 SimScaleX100[PQMUI_FIELD_COUNT] = {
    100u,                              /* PQMUI_FIELD_FREQUENCY */
    PQMUI_SIM_SCALE_X100,              /* PQMUI_FIELD_U_RMS */
    PQMUI_SIM_SCALE_X100,              /* PQMUI_FIELD_I_RMS */
    PQMUI_SIM_SCALE_X100,              /* PQMUI_FIELD_U_P2P */
    PQMUI_SIM_SCALE_X100,              /* PQMUI_FIELD_I_P2P */
    100u,                              /* PQMUI_FIELD_PHASE */
    PQMUI_SIM_POWER_SCALE_X100,        /* PQMUI_FIELD_ACTIVE_POWER */
    PQMUI_SIM_POWER_SCALE_X100,        /* PQMUI_FIELD_REACTIVE_POWER */
    PQMUI_SIM_POWER_SCALE_X100,        /* PQMUI_FIELD_APPARENT_POWER */
    100u,                              /* PQMUI_FIELD_POWER_FACTOR */
    100u,                              /* PQMUI_FIELD_THD_U */
    100u,                              /* PQMUI_FIELD_THD_I */
    100u,                              /* PQMUI_FIELD_DC_U */
    100u                               /* PQMUI_FIELD_DC_I */
};

s32 PQMUI_ApplySimScale(pqmui_field_t field, s32 x100, u8 low_range)
{
    s64 scaled;

    /* 小量程显示真值；字段越界时不做任何换算。 */
    if (low_range || field < 0 || field >= PQMUI_FIELD_COUNT) {
        return x100;
    }

    /* 先乘后除，中间积用 s64：s32 上限 2.1e9，而 99999 × 151243 已经到 1.5e10，
     * 用 s32 承载会回绕。结果本身不会超 s32（÷100 后最大 1.5e8），下面的饱和是兜底。 */
    scaled = (((s64)x100) * ((s64)SimScaleX100[field])) / 100LL;
    if (scaled > (s64)INT32_MAX) {
        return INT32_MAX;
    }
    if (scaled < (s64)INT32_MIN) {
        return INT32_MIN;
    }
    return (s32)scaled;
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
