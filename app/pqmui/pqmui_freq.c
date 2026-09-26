/*
 * PQM 频域页面。
 *
 * 显示谐波幅值占比、谐波相位与五项规定参数，并支持在多个谐波窗口间切换。
 * 页面只负责 LVGL 对象创建与刷新，不读取任何硬件。
 */

#include "pqmui_internal.h"
#include "pqmui_format.h"
#include "pqmui_style.h"

/* 频域页右面板前五行使用的字段与名称。 */
static const pqmui_field_t FreqFields[5] = {
    PQMUI_FIELD_FREQUENCY,
    PQMUI_FIELD_THD_U,
    PQMUI_FIELD_THD_I,
    PQMUI_FIELD_DC_U,
    PQMUI_FIELD_DC_I
};

static const char *const FreqNames[5] = {
    "Fundamental", "THD-U", "THD-I", "DC-U", "DC-I"
};

/* 参数行的文字颜色：按通道着色，0 表示沿用默认正文色。 */
static const u32 FreqRowColors[5] = {
    0u,                    /* Fundamental */
    PQMUI_COLOR_U_WAVE,    /* THD-U */
    PQMUI_COLOR_I_WAVE,    /* THD-I */
    PQMUI_COLOR_U_WAVE,    /* DC-U */
    PQMUI_COLOR_I_WAVE     /* DC-I */
};

/* 谐波详情三行的颜色：U 级、I 级、相位。 */
static const u32 FreqHarmonicColors[3] = {
    PQMUI_COLOR_U_WAVE,
    PQMUI_COLOR_I_WAVE,
    PQMUI_COLOR_PHASE
};

static lv_obj_t *MagnitudeChart;
static lv_obj_t *PhaseChart;
static lv_chart_series_t *MagnitudeSeries[2];
static lv_chart_series_t *PhaseSeries;
static lv_coord_t MagnitudePoints[2][PQMUI_HARMONIC_POINTS];
static lv_coord_t PhasePoints[PQMUI_HARMONIC_POINTS];
static lv_obj_t *FreqValueLabels[5];
static lv_obj_t *FreqHarmonicLabels[3];
static lv_obj_t *HarmonicWindowLabel;

static void PQMUI_PreviousWindowEvent(lv_event_t *event)
{
    (void)event;

    if (PQMUI_HarmonicWindowStart >= PQMUI_HARMONIC_STEP) {
        PQMUI_HarmonicWindowStart -= PQMUI_HARMONIC_STEP;
    } else {
        PQMUI_HarmonicWindowStart = 0u;
    }
    PQMUI_FreqRefreshHarmonics();
}

static void PQMUI_NextWindowEvent(lv_event_t *event)
{
    (void)event;

    if (PQMUI_HarmonicWindowStart < PQMUI_HARMONIC_MAX_START) {
        PQMUI_HarmonicWindowStart += PQMUI_HARMONIC_STEP;
    }
    PQMUI_FreqRefreshHarmonics();
}

void PQMUI_FreqCreate(void)
{
    lv_obj_t *left;
    lv_obj_t *right;
    lv_obj_t *button;
    lv_obj_t *label;
    u32 index;

    PQMUI_FrequencyPage = lv_obj_create(lv_scr_act());
    lv_obj_remove_style_all(PQMUI_FrequencyPage);
    lv_obj_set_pos(PQMUI_FrequencyPage, 0, 44);
    lv_obj_set_size(PQMUI_FrequencyPage, 800, 436);
    lv_obj_clear_flag(PQMUI_FrequencyPage, LV_OBJ_FLAG_SCROLLABLE);

    left = lv_obj_create(PQMUI_FrequencyPage);
    lv_obj_add_style(left, &PQMUI_StylePanel, LV_PART_MAIN);
    lv_obj_set_pos(left, 0, 20);
    lv_obj_set_size(left, 486, 396);
    lv_obj_clear_flag(left, LV_OBJ_FLAG_SCROLLABLE);
    PQMUI_CreateText(left, 18, 8, "Harmonic Spectrum", 0u);

    MagnitudeChart = lv_chart_create(left);
    lv_obj_add_style(MagnitudeChart, &PQMUI_StyleChart, LV_PART_MAIN);
    lv_obj_set_pos(MagnitudeChart, 48, 38);
    lv_obj_set_size(MagnitudeChart, 414, 205);
    lv_obj_clear_flag(MagnitudeChart, LV_OBJ_FLAG_SCROLLABLE);
    /* 谐波占比按“每个谐波一根”的方式展示，故用条形图；相位图仍为折线。 */
    lv_chart_set_type(MagnitudeChart, LV_CHART_TYPE_BAR);
    lv_chart_set_point_count(MagnitudeChart, PQMUI_HARMONIC_POINTS);
    lv_chart_set_range(MagnitudeChart, LV_CHART_AXIS_PRIMARY_Y, 0, 10000);
    lv_chart_set_div_line_count(MagnitudeChart, 5, 6);
    MagnitudeSeries[0] = lv_chart_add_series(MagnitudeChart,
                                             lv_color_hex(PQMUI_COLOR_U_WAVE),
                                             LV_CHART_AXIS_PRIMARY_Y);
    MagnitudeSeries[1] = lv_chart_add_series(MagnitudeChart,
                                             lv_color_hex(PQMUI_COLOR_I_WAVE),
                                             LV_CHART_AXIS_PRIMARY_Y);
    for (index = 0u; index < 2u; ++index) {
        lv_chart_set_ext_y_array(MagnitudeChart, MagnitudeSeries[index],
                                 MagnitudePoints[index]);
    }
    PQMUI_CreateText(left, 8, 40, "100%", 1u);
    PQMUI_CreateText(left, 20, 220, "0", 1u);

    PhaseChart = lv_chart_create(left);
    lv_obj_add_style(PhaseChart, &PQMUI_StyleChart, LV_PART_MAIN);
    lv_obj_set_pos(PhaseChart, 48, 266);
    lv_obj_set_size(PhaseChart, 414, 82);
    lv_obj_clear_flag(PhaseChart, LV_OBJ_FLAG_SCROLLABLE);
    lv_chart_set_type(PhaseChart, LV_CHART_TYPE_LINE);
    lv_chart_set_point_count(PhaseChart, PQMUI_HARMONIC_POINTS);
    lv_chart_set_range(PhaseChart, LV_CHART_AXIS_PRIMARY_Y, -18000, 18000);
    lv_chart_set_div_line_count(PhaseChart, 3, 6);
    PhaseSeries = lv_chart_add_series(PhaseChart,
                                      lv_color_hex(PQMUI_COLOR_PHASE),
                                      LV_CHART_AXIS_PRIMARY_Y);
    lv_chart_set_ext_y_array(PhaseChart, PhaseSeries, PhasePoints);
    PQMUI_CreateText(left, 6, 264, "+180", 1u);
    PQMUI_CreateText(left, 12, 322, "-180", 1u);

    button = PQMUI_CreateButton(left, 48, 356, 48, 30,
                                LV_SYMBOL_LEFT, &label);
    lv_obj_add_event_cb(button, PQMUI_PreviousWindowEvent, LV_EVENT_CLICKED,
                        NULL);
    HarmonicWindowLabel = PQMUI_CreateText(left, 160, 363, "H0 - H25", 0u);
    button = PQMUI_CreateButton(left, 414, 356, 48, 30,
                                LV_SYMBOL_RIGHT, &label);
    lv_obj_add_event_cb(button, PQMUI_NextWindowEvent, LV_EVENT_CLICKED, NULL);

    right = lv_obj_create(PQMUI_FrequencyPage);
    lv_obj_add_style(right, &PQMUI_StylePanel, LV_PART_MAIN);
    lv_obj_set_pos(right, 500, 20);
    lv_obj_set_size(right, 300, 396);
    lv_obj_clear_flag(right, LV_OBJ_FLAG_SCROLLABLE);
    PQMUI_CreateText(right, 18, 10, "Parameters", 0u);
    for (index = 0u; index < 5u; ++index) {
        FreqValueLabels[index] = PQMUI_CreateText(
            right, 18, (lv_coord_t)(50 + (index * 38u)), "--", 0u);
        if (FreqRowColors[index] != 0u) {
            lv_obj_set_style_text_color(FreqValueLabels[index],
                                        lv_color_hex(FreqRowColors[index]),
                                        LV_PART_MAIN);
        }
    }
    for (index = 0u; index < 3u; ++index) {
        FreqHarmonicLabels[index] = PQMUI_CreateText(
            right, 18, (lv_coord_t)(50 + ((index + 5u) * 38u)), "--", 0u);
        lv_obj_set_style_text_color(FreqHarmonicLabels[index],
                                    lv_color_hex(FreqHarmonicColors[index]),
                                    LV_PART_MAIN);
    }
}

void PQMUI_FreqRefreshMeasurement(void)
{
    u32 index;

    if (!PQMUI_MeasurementAvailable) {
        return;
    }
    for (index = 0u; index < 5u; ++index) {
        char value[32];

        (void)PQMUI_FieldFormat(FreqFields[index],
                                &PQMUI_LatestMeasurement.value[FreqFields[index]],
                                value, sizeof(value));
        lv_label_set_text_fmt(FreqValueLabels[index], "%s  %s",
                              FreqNames[index], value);
    }
}

void PQMUI_FreqRefreshHarmonics(void)
{
    u32 point;
    u32 selected;

    if (!PQMUI_HarmonicsAvailable) {
        return;
    }
    for (point = 0u; point < PQMUI_HARMONIC_POINTS; ++point) {
        u32 harmonic = (u32)PQMUI_HarmonicWindowStart + point;

        if (harmonic < PQMUI_HARMONIC_ENTRIES &&
            (PQMUI_LatestHarmonics.entries[harmonic].flags &
             PQMUI_HARMONIC_FLAG_RATIO) != 0u) {
            MagnitudePoints[0][point] =
                PQMUI_LatestHarmonics.entries[harmonic].u_ratio_x100;
            MagnitudePoints[1][point] =
                PQMUI_LatestHarmonics.entries[harmonic].i_ratio_x100;
            PhasePoints[point] =
                (PQMUI_LatestHarmonics.entries[harmonic].flags &
                 PQMUI_HARMONIC_FLAG_PHASE) != 0u
                    ? PQMUI_LatestHarmonics.entries[harmonic].phase_x100
                    : LV_CHART_POINT_NONE;
        } else {
            MagnitudePoints[0][point] = LV_CHART_POINT_NONE;
            MagnitudePoints[1][point] = LV_CHART_POINT_NONE;
            PhasePoints[point] = LV_CHART_POINT_NONE;
        }
    }
    lv_chart_refresh(MagnitudeChart);
    lv_chart_refresh(PhaseChart);
    lv_label_set_text_fmt(HarmonicWindowLabel, "H%u - H%u",
                          (unsigned int)PQMUI_HarmonicWindowStart,
                          (unsigned int)(PQMUI_HarmonicWindowStart +
                                         PQMUI_HARMONIC_STEP));

    /* 谐波详情显示窗口内的第一个非直流谐波：H0 为直流，没有占比含义。 */
    selected = PQMUI_HarmonicWindowStart == 0u
                   ? 1u : PQMUI_HarmonicWindowStart;
    if ((PQMUI_LatestHarmonics.entries[selected].flags &
         PQMUI_HARMONIC_FLAG_RATIO) != 0u) {
        const pqmui_harmonic_t *entry = &PQMUI_LatestHarmonics.entries[selected];
        s32 phase = entry->phase_x100;
        u32 phase_magnitude = (u32)(phase < 0 ? -phase : phase);

        lv_label_set_text_fmt(FreqHarmonicLabels[0], "H%u U  %u.%02u %%",
                              (unsigned int)selected,
                              (unsigned int)(entry->u_ratio_x100 / 100u),
                              (unsigned int)(entry->u_ratio_x100 % 100u));
        lv_label_set_text_fmt(FreqHarmonicLabels[1], "H%u I  %u.%02u %%",
                              (unsigned int)selected,
                              (unsigned int)(entry->i_ratio_x100 / 100u),
                              (unsigned int)(entry->i_ratio_x100 % 100u));
        if ((entry->flags & PQMUI_HARMONIC_FLAG_PHASE) != 0u) {
            lv_label_set_text_fmt(FreqHarmonicLabels[2],
                                  "H%u Phase  %c%u.%02u deg",
                                  (unsigned int)selected,
                                  phase < 0 ? '-' : '+',
                                  (unsigned int)(phase_magnitude / 100u),
                                  (unsigned int)(phase_magnitude % 100u));
        } else {
            lv_label_set_text_fmt(FreqHarmonicLabels[2],
                                  "H%u Phase  -- deg",
                                  (unsigned int)selected);
        }
    } else {
        lv_label_set_text_fmt(FreqHarmonicLabels[0], "H%u U  -- %%",
                              (unsigned int)selected);
        lv_label_set_text_fmt(FreqHarmonicLabels[1], "H%u I  -- %%",
                              (unsigned int)selected);
        lv_label_set_text_fmt(FreqHarmonicLabels[2], "H%u Phase  -- deg",
                              (unsigned int)selected);
    }
}
