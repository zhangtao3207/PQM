/*
 * PQM 时域页面。
 *
 * 显示电压/电流的极值包络、十项标量参数与高低量程按钮。量程按钮只发出请求，
 * 实际显示状态在结果返回后由总控模块更新。
 */

#include "pqmui_internal.h"
#include "pqmui_format.h"
#include "pqmui_style.h"

#include <limits.h>

/* 横轴时间跨度文本。真实时基由 PL 的帧采样率决定，尚未确定，沿用旧工程的显示值。 */
#define PQMUI_TIME_AXIS_SPAN_TEXT "20 ms"

static const pqmui_field_t TimeFields[10] = {
    PQMUI_FIELD_FREQUENCY,
    PQMUI_FIELD_U_RMS,
    PQMUI_FIELD_I_RMS,
    PQMUI_FIELD_U_P2P,
    PQMUI_FIELD_I_P2P,
    PQMUI_FIELD_PHASE,
    PQMUI_FIELD_ACTIVE_POWER,
    PQMUI_FIELD_REACTIVE_POWER,
    PQMUI_FIELD_APPARENT_POWER,
    PQMUI_FIELD_POWER_FACTOR
};

static const char *const TimeNames[10] = {
    "Frequency", "U RMS", "I RMS", "U P-P", "I P-P",
    "Phase", "Active P", "Reactive Q", "Apparent S", "Power factor"
};

/* 参数行的文字颜色：按通道着色，0 表示沿用默认正文色。 */
static const u32 TimeRowColors[10] = {
    0u,                    /* Frequency */
    PQMUI_COLOR_U_WAVE,    /* U RMS */
    PQMUI_COLOR_I_WAVE,    /* I RMS */
    PQMUI_COLOR_U_WAVE,    /* U P-P */
    PQMUI_COLOR_I_WAVE,    /* I P-P */
    PQMUI_COLOR_PHASE,     /* Phase */
    0u,                    /* Active P */
    0u,                    /* Reactive Q */
    0u,                    /* Apparent S */
    0u                     /* Power factor */
};

static lv_obj_t *TimeChart;
static lv_chart_series_t *TimeSeries[4];
static lv_coord_t TimePoints[4][PQMUI_WAVE_COLUMNS];
static lv_obj_t *TimeValueLabels[10];

lv_obj_t *PQMUI_RangeButtonLabel;

static void PQMUI_RangeEvent(lv_event_t *event)
{
    u8 requested_low_range;

    (void)event;

    if (PQMUI_RangePending) {
        return;
    }
    requested_low_range = PQMUI_LowRange ? 0u : 1u;
    if (PQMUI_RangeRequest != NULL && PQMUI_RangeRequest(requested_low_range)) {
        PQMUI_RangePending = 1u;
        PQMUI_RangeError = 0u;
        lv_label_set_text(PQMUI_RangeButtonLabel, "Switching...");
    } else {
        PQMUI_SetRangeResult(0u, PQMUI_LowRange);
    }
}

void PQMUI_TimeCreate(void)
{
    lv_obj_t *left;
    lv_obj_t *right;
    lv_obj_t *button;
    lv_obj_t *label;
    u32 index;

    PQMUI_TimePage = lv_obj_create(lv_scr_act());
    lv_obj_remove_style_all(PQMUI_TimePage);
    lv_obj_set_pos(PQMUI_TimePage, 0, 44);
    lv_obj_set_size(PQMUI_TimePage, 800, 436);
    lv_obj_clear_flag(PQMUI_TimePage, LV_OBJ_FLAG_SCROLLABLE);

    left = lv_obj_create(PQMUI_TimePage);
    lv_obj_add_style(left, &PQMUI_StylePanel, LV_PART_MAIN);
    lv_obj_set_pos(left, 0, 20);
    lv_obj_set_size(left, 486, 396);
    lv_obj_clear_flag(left, LV_OBJ_FLAG_SCROLLABLE);
    PQMUI_CreateText(left, 18, 10, "Voltage / Current Waveform", 0u);

    label = PQMUI_CreateText(left, 302, 12, "U", 0u);
    lv_obj_set_style_text_color(label, lv_color_hex(PQMUI_COLOR_U_WAVE),
                                LV_PART_MAIN);
    label = PQMUI_CreateText(left, 340, 12, "I", 0u);
    lv_obj_set_style_text_color(label, lv_color_hex(PQMUI_COLOR_I_WAVE),
                                LV_PART_MAIN);

    TimeChart = lv_chart_create(left);
    lv_obj_add_style(TimeChart, &PQMUI_StyleChart, LV_PART_MAIN);
    lv_obj_set_pos(TimeChart, 48, 48);
    lv_obj_set_size(TimeChart, 414, 280);
    lv_obj_clear_flag(TimeChart, LV_OBJ_FLAG_SCROLLABLE);
    lv_chart_set_type(TimeChart, LV_CHART_TYPE_LINE);
    lv_chart_set_point_count(TimeChart, PQMUI_WAVE_COLUMNS);
    lv_chart_set_range(TimeChart, LV_CHART_AXIS_PRIMARY_Y,
                       -PQMUI_WAVE_FULL_SCALE, PQMUI_WAVE_FULL_SCALE);
    lv_chart_set_div_line_count(TimeChart, 7, 8);
    TimeSeries[0] = lv_chart_add_series(TimeChart,
                                        lv_color_hex(PQMUI_COLOR_U_WAVE),
                                        LV_CHART_AXIS_PRIMARY_Y);
    TimeSeries[1] = lv_chart_add_series(TimeChart,
                                        lv_color_hex(PQMUI_COLOR_U_WAVE),
                                        LV_CHART_AXIS_PRIMARY_Y);
    TimeSeries[2] = lv_chart_add_series(TimeChart,
                                        lv_color_hex(PQMUI_COLOR_I_WAVE),
                                        LV_CHART_AXIS_PRIMARY_Y);
    TimeSeries[3] = lv_chart_add_series(TimeChart,
                                        lv_color_hex(PQMUI_COLOR_I_WAVE),
                                        LV_CHART_AXIS_PRIMARY_Y);
    for (index = 0u; index < 4u; ++index) {
        lv_chart_set_ext_y_array(TimeChart, TimeSeries[index],
                                 TimePoints[index]);
    }

    PQMUI_CreateText(left, 8, 54, "+FS", 1u);
    PQMUI_CreateText(left, 14, 184, "0", 1u);
    PQMUI_CreateText(left, 8, 310, "-FS", 1u);
    PQMUI_CreateText(left, 48, 338, "0", 1u);
    PQMUI_CreateText(left, 420, 338, PQMUI_TIME_AXIS_SPAN_TEXT, 1u);

    button = PQMUI_CreateButton(left, 145, 354, 196, 32,
                                "350 V / 30 A", &PQMUI_RangeButtonLabel);
    lv_obj_add_event_cb(button, PQMUI_RangeEvent, LV_EVENT_CLICKED, NULL);

    right = lv_obj_create(PQMUI_TimePage);
    lv_obj_add_style(right, &PQMUI_StylePanel, LV_PART_MAIN);
    lv_obj_set_pos(right, 500, 20);
    lv_obj_set_size(right, 300, 396);
    lv_obj_clear_flag(right, LV_OBJ_FLAG_SCROLLABLE);
    PQMUI_CreateText(right, 18, 10, "Parameters", 0u);
    for (index = 0u; index < 10u; ++index) {
        TimeValueLabels[index] = PQMUI_CreateText(
            right, 18, (lv_coord_t)(48 + (index * 32u)), "--", 0u);
        if (TimeRowColors[index] != 0u) {
            lv_obj_set_style_text_color(TimeValueLabels[index],
                                        lv_color_hex(TimeRowColors[index]),
                                        LV_PART_MAIN);
        }
    }
}

void PQMUI_TimeRefreshMeasurement(void)
{
    u32 index;

    if (!PQMUI_MeasurementAvailable) {
        return;
    }
    for (index = 0u; index < 10u; ++index) {
        char value[32];

        (void)PQMUI_FieldFormat(TimeFields[index],
                                &PQMUI_LatestMeasurement.value[TimeFields[index]],
                                value, sizeof(value));
        lv_label_set_text_fmt(TimeValueLabels[index], "%s  %s",
                              TimeNames[index], value);
    }
}

void PQMUI_TimeRefreshWaveform(const pqmui_wave_column_t *columns)
{
    u32 index;

    for (index = 0u; index < PQMUI_WAVE_COLUMNS; ++index) {
        TimePoints[0][index] = (columns[index].u_min == INT16_MIN)
                                   ? -PQMUI_WAVE_FULL_SCALE
                                   : columns[index].u_min;
        TimePoints[1][index] = columns[index].u_max;
        TimePoints[2][index] = (columns[index].i_min == INT16_MIN)
                                   ? -PQMUI_WAVE_FULL_SCALE
                                   : columns[index].i_min;
        TimePoints[3][index] = columns[index].i_max;
    }
    lv_chart_refresh(TimeChart);
}
