/*
 * 阶段 1 的内置假数据源。
 *
 * 官方比特流里没有 AD7606 采集链和 PS/PL 共享内存，界面拿不到真实测量值；
 * 这里用一组缓慢摆动的模拟量把参数、波形包络和谐波填满，用来验证界面通路
 * 与刷新是否真的在跑。阶段 3 接入真实数据后整个文件删除。
 */

#include "pqmui_demo.h"

#include "pqmui.h"
#include "pqmui_format.h"

#include "xtime_l.h"

/* 各数据源的刷新周期（毫秒） */
#define PQMUI_DEMO_MEASUREMENT_PERIOD_MS 50u
#define PQMUI_DEMO_WAVEFORM_PERIOD_MS    100u
#define PQMUI_DEMO_HARMONIC_PERIOD_MS    500u

/* 量程命令的模拟应答延迟（毫秒） */
#define PQMUI_DEMO_RANGE_DELAY_MS        400u

/* 测量值慢摆的周期（毫秒）与幅度（万分之一） */
#define PQMUI_DEMO_SWING_PERIOD_MS       2000u
#define PQMUI_DEMO_SWING_AMPLITUDE       200

/* 波形：一个显示周期对应一个工频周期，电压取满量程的 63%，电流滞后 30 度。 */
#define PQMUI_DEMO_U_PEAK                20643
#define PQMUI_DEMO_I_PEAK                5600
#define PQMUI_DEMO_CURRENT_LAG_PHASE     ((30u * 256u) / 360u)

/* 64 点正弦表，幅值 32767，按 1/64 周期取样。 */
static const s16 DemoSineTable[64] = {
        0,   3212,   6393,   9512,  12539,  15446,  18204,  20787,
    23170,  25329,  27245,  28898,  30273,  31356,  32137,  32609,
    32767,  32609,  32137,  31356,  30273,  28898,  27245,  25329,
    23170,  20787,  18204,  15446,  12539,   9512,   6393,   3212,
        0,  -3212,  -6393,  -9512, -12539, -15446, -18204, -20787,
   -23170, -25329, -27245, -28898, -30273, -31356, -32137, -32609,
   -32767, -32609, -32137, -31356, -30273, -28898, -27245, -25329,
   -23170, -20787, -18204, -15446, -12539,  -9512,  -6393,  -3212
};

/* 十四个字段的基准值（工程量乘以 100）。 */
static const s32 DemoBaseValue[PQMUI_FIELD_COUNT] = {
    5000,   /* PQMUI_FIELD_FREQUENCY     50.00 Hz */
    22005,  /* PQMUI_FIELD_U_RMS        220.05 V */
    512,    /* PQMUI_FIELD_I_RMS          5.12 A */
    62230,  /* PQMUI_FIELD_U_P2P        622.30 V */
    1448,   /* PQMUI_FIELD_I_P2P         14.48 A */
    3000,   /* PQMUI_FIELD_PHASE        +30.00 deg */
    97642,  /* PQMUI_FIELD_ACTIVE_POWER 976.42 W */
    56382,  /* PQMUI_FIELD_REACTIVE_POWER +563.82 var */
    112666, /* PQMUI_FIELD_APPARENT_POWER 1126.66 VA */
    87,     /* PQMUI_FIELD_POWER_FACTOR   0.87 */
    235,    /* PQMUI_FIELD_THD_U          2.35 % */
    310,    /* PQMUI_FIELD_THD_I          3.10 % */
    5,      /* PQMUI_FIELD_DC_U           0.05 % */
    2       /* PQMUI_FIELD_DC_I           0.02 % */
};

static pqmui_measurement_t DemoMeasurement;
static pqmui_harmonic_snapshot_t DemoHarmonics;
static pqmui_wave_column_t DemoColumns[PQMUI_WAVE_COLUMNS];

static u8 DemoStarted;
static u8 DemoRangePending;
static u8 DemoRangeRequested;
static XTime DemoLastMeasurement;
static XTime DemoLastWaveform;
static XTime DemoLastHarmonic;
static XTime DemoRangeRequestTime;

/* 把 XTime 的差值换算成毫秒。 */
static u32 PQMUI_DemoElapsedMs(XTime now, XTime then)
{
    return (u32)(((now - then) * 1000u) / (u32)COUNTS_PER_SECOND);
}

/* 取 1/256 周期为单位、幅值 32767 的正弦值，表间线性插值。 */
static s32 PQMUI_DemoSine(u32 phase)
{
    u32 index = (phase >> 2) & 63u;
    u32 fraction = phase & 3u;
    s32 first = DemoSineTable[index];
    s32 second = DemoSineTable[(index + 1u) & 63u];

    return first + (((second - first) * (s32)fraction) / 4);
}

/* 缓慢摆动的系数，返回值是万分之一单位的比例（10000 表示原值）。 */
static s32 PQMUI_DemoSwing(u32 elapsed_ms)
{
    s32 phase = (s32)(((elapsed_ms % PQMUI_DEMO_SWING_PERIOD_MS) * 256u) /
                      PQMUI_DEMO_SWING_PERIOD_MS);

    return 10000 + ((s32)PQMUI_DEMO_SWING_AMPLITUDE * PQMUI_DemoSine((u32)phase)) /
                       32767;
}

static void PQMUI_DemoFillMeasurement(u32 elapsed_ms)
{
    s32 swing = PQMUI_DemoSwing(elapsed_ms);
    u32 field;

    for (field = 0u; field < (u32)PQMUI_FIELD_COUNT; ++field) {
        s32 value = (s32)(((s64)DemoBaseValue[field] * swing) / 10000);

        DemoMeasurement.value[field].x100 = PQMUI_FieldClampX100(
            (pqmui_field_t)field, value);
        DemoMeasurement.value[field].valid = 1u;
    }
    DemoMeasurement.sequence += 1u;
    DemoMeasurement.alarm = 0u;
}

static void PQMUI_DemoFillWaveform(void)
{
    u32 column;

    for (column = 0u; column < PQMUI_WAVE_COLUMNS; ++column) {
        u32 phase = (column * 256u) / PQMUI_WAVE_COLUMNS;
        s32 u = (PQMUI_DemoSine(phase) * PQMUI_DEMO_U_PEAK) / 32767;
        s32 i = (PQMUI_DemoSine((phase + 256u - PQMUI_DEMO_CURRENT_LAG_PHASE) & 255u)
                 * PQMUI_DEMO_I_PEAK) / 32767;

        DemoColumns[column].u_min = (s16)u;
        DemoColumns[column].u_max = (s16)u;
        DemoColumns[column].i_min = (s16)i;
        DemoColumns[column].i_max = (s16)i;
    }
}

static void PQMUI_DemoFillHarmonics(void)
{
    u32 harmonic;

    for (harmonic = 0u; harmonic < PQMUI_HARMONIC_ENTRIES; ++harmonic) {
        pqmui_harmonic_t *entry = &DemoHarmonics.entries[harmonic];
        u32 odd = (harmonic % 2u) != 0u;
        s32 phase;

        if (harmonic == 0u) {
            entry->u_ratio_x100 = 50u;
            entry->i_ratio_x100 = 40u;
        } else if (odd) {
            entry->u_ratio_x100 = (u16)(10000u / harmonic);
            entry->i_ratio_x100 = (u16)(8000u / harmonic);
        } else {
            entry->u_ratio_x100 = (u16)(200u / harmonic);
            entry->i_ratio_x100 = (u16)(150u / harmonic);
        }
        phase = (s32)(((harmonic * 37u) % 31u) * 1000u) - 15000;
        entry->phase_x100 = (s16)phase;
        entry->flags = PQMUI_HARMONIC_FLAG_RATIO | PQMUI_HARMONIC_FLAG_PHASE;
    }
    DemoHarmonics.generation += 1u;
}

static u8 PQMUI_DemoRangeRequest(u8 low_range)
{
    DemoRangeRequested = low_range;
    XTime_GetTime(&DemoRangeRequestTime);
    DemoRangePending = 1u;
    return 1u;
}

void PQMUI_DemoPoll(void)
{
    XTime now;

    if (!DemoStarted) {
        /* 首次轮询时完成自举，避免在 main 里多加一处初始化调用。 */
        DemoStarted = 1u;
        DemoMeasurement.sequence = 0u;
        DemoMeasurement.alarm = 0u;
        DemoHarmonics.generation = 0u;
        PQMUI_DemoFillHarmonics();
        PQMUI_SetRangeRequest(PQMUI_DemoRangeRequest);
        XTime_GetTime(&DemoLastMeasurement);
        DemoLastWaveform = DemoLastMeasurement;
        DemoLastHarmonic = DemoLastMeasurement;
    }

    XTime_GetTime(&now);

    if (PQMUI_DemoElapsedMs(now, DemoLastMeasurement) >=
        PQMUI_DEMO_MEASUREMENT_PERIOD_MS) {
        DemoLastMeasurement = now;
        PQMUI_DemoFillMeasurement(
            (u32)((now / (COUNTS_PER_SECOND / 1000u)) % 1000000u));
        PQMUI_UpdateMeasurement(&DemoMeasurement);
    }
    if (PQMUI_DemoElapsedMs(now, DemoLastWaveform) >=
        PQMUI_DEMO_WAVEFORM_PERIOD_MS) {
        DemoLastWaveform = now;
        PQMUI_DemoFillWaveform();
        PQMUI_UpdateWaveform(DemoColumns);
    }
    if (PQMUI_DemoElapsedMs(now, DemoLastHarmonic) >=
        PQMUI_DEMO_HARMONIC_PERIOD_MS) {
        DemoLastHarmonic = now;
        PQMUI_DemoFillHarmonics();
        PQMUI_UpdateHarmonics(&DemoHarmonics);
    }
    if (DemoRangePending &&
        PQMUI_DemoElapsedMs(now, DemoRangeRequestTime) >=
            PQMUI_DEMO_RANGE_DELAY_MS) {
        DemoRangePending = 0u;
        PQMUI_SetRangeResult(1u, DemoRangeRequested);
    }
}
