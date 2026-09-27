/*
 * PQM 界面总控模块。
 *
 * 创建顶层页面与公共控件，处理页面切换、冻结状态，并把测量、波形与谐波
 * 分发到时域页和频域页。具体页面布局由各自的模块实现。
 */

#include "pqmui_internal.h"
#include "pqmui_style.h"

#include <string.h>

lv_obj_t *PQMUI_TimePage;
lv_obj_t *PQMUI_FrequencyPage;
lv_obj_t *PQMUI_TitleLabel;
lv_obj_t *PQMUI_StatusLabel;
lv_obj_t *PQMUI_PageButtonLabel;
lv_obj_t *PQMUI_FreezeButtonLabel;

u8 PQMUI_FrequencyActive;
u8 PQMUI_Frozen;
u8 PQMUI_LowRange;
u8 PQMUI_RangePending;
u8 PQMUI_RangeError;
u8 PQMUI_MeasurementAvailable;
u8 PQMUI_HarmonicsAvailable;

pqmui_measurement_t PQMUI_LatestMeasurement;
pqmui_harmonic_snapshot_t PQMUI_LatestHarmonics;
u16 PQMUI_HarmonicWindowStart;

pqmui_range_request_fn PQMUI_RangeRequest;

/* 按当前页面状态切换两页的可见性，并同步标题与翻页按钮文字。 */
static void PQMUI_SetPageVisible(void)
{
    if (PQMUI_FrequencyActive) {
        lv_obj_add_flag(PQMUI_TimePage, LV_OBJ_FLAG_HIDDEN);
        lv_obj_clear_flag(PQMUI_FrequencyPage, LV_OBJ_FLAG_HIDDEN);
        lv_label_set_text(PQMUI_TitleLabel, "PQM - Frequency Domain");
        lv_label_set_text(PQMUI_PageButtonLabel, "Time");
    } else {
        lv_obj_clear_flag(PQMUI_TimePage, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(PQMUI_FrequencyPage, LV_OBJ_FLAG_HIDDEN);
        lv_label_set_text(PQMUI_TitleLabel, "PQM - Time Domain");
        lv_label_set_text(PQMUI_PageButtonLabel, "Spectrum");
    }
}

static void PQMUI_PageButtonEvent(lv_event_t *event)
{
    (void)event;

    PQMUI_FrequencyActive = PQMUI_FrequencyActive ? 0u : 1u;
    PQMUI_SetPageVisible();
}

static void PQMUI_FreezeButtonEvent(lv_event_t *event)
{
    (void)event;

    PQMUI_Frozen = PQMUI_Frozen ? 0u : 1u;
    lv_label_set_text(PQMUI_FreezeButtonLabel,
                      PQMUI_Frozen ? "Resume" : "Freeze");
    PQMUI_UpdateStatus();
}

lv_obj_t *PQMUI_CreateText(lv_obj_t *parent, lv_coord_t x, lv_coord_t y,
                           const char *text, u8 dim)
{
    lv_obj_t *label = lv_label_create(parent);

    lv_obj_add_style(label, dim ? &PQMUI_StyleTextDim : &PQMUI_StyleText,
                     LV_PART_MAIN);
    lv_label_set_text(label, text);
    lv_obj_set_pos(label, x, y);
    return label;
}

lv_obj_t *PQMUI_CreateButton(lv_obj_t *parent, lv_coord_t x, lv_coord_t y,
                             lv_coord_t width, lv_coord_t height,
                             const char *text, lv_obj_t **label)
{
    lv_obj_t *button = lv_btn_create(parent);

    lv_obj_set_pos(button, x, y);
    lv_obj_set_size(button, width, height);
    lv_obj_add_style(button, &PQMUI_StyleButton, LV_PART_MAIN);
    lv_obj_add_style(button, &PQMUI_StyleButtonPressed,
                     LV_PART_MAIN | LV_STATE_PRESSED);
    *label = lv_label_create(button);
    lv_label_set_text(*label, text);
    lv_obj_center(*label);
    return button;
}

void PQMUI_UpdateStatus(void)
{
    u32 code = (PQMUI_LatestMeasurement.alarm >> 1u) & 0x7u;
    const char *channel;
    const char *direction;

    switch (code) {
    case 1u:
        channel = "U";
        direction = "RISE";
        break;
    case 2u:
        channel = "U";
        direction = "DROP";
        break;
    case 3u:
        channel = "I";
        direction = "RISE";
        break;
    case 4u:
        channel = "I";
        direction = "DROP";
        break;
    default:
        /* PL 只定义 0~4，5~7 不会出现。这里沿用旧工程按 (code==3||4) 选通道、
         * (code==2||4) 选方向推导出的兜底取值，保证渲染结果与旧实现一致。 */
        channel = "U";
        direction = "RISE";
        break;
    }

    if (PQMUI_RangeError) {
        lv_label_set_text(PQMUI_StatusLabel, "RANGE ERROR");
        lv_obj_set_style_text_color(PQMUI_StatusLabel,
                                    lv_color_hex(PQMUI_COLOR_ALARM),
                                    LV_PART_MAIN);
    } else if ((PQMUI_LatestMeasurement.alarm & 1u) != 0u && code != 0u) {
        lv_label_set_text_fmt(PQMUI_StatusLabel, "ALARM %s %s",
                              channel, direction);
        lv_obj_set_style_text_color(PQMUI_StatusLabel,
                                    lv_color_hex(PQMUI_COLOR_ALARM),
                                    LV_PART_MAIN);
    } else {
        lv_label_set_text(PQMUI_StatusLabel, PQMUI_Frozen ? "FROZEN" : "RUN");
        lv_obj_set_style_text_color(PQMUI_StatusLabel,
                                    lv_color_hex(PQMUI_COLOR_STATUS),
                                    LV_PART_MAIN);
    }
}

void PQMUI_Init(void)
{
    lv_obj_t *screen;
    lv_obj_t *header;
    lv_obj_t *button;

    memset(&PQMUI_LatestMeasurement, 0, sizeof(PQMUI_LatestMeasurement));
    memset(&PQMUI_LatestHarmonics, 0, sizeof(PQMUI_LatestHarmonics));
    PQMUI_FrequencyActive = 0u;
    PQMUI_Frozen = 0u;
    PQMUI_LowRange = 0u;
    PQMUI_RangePending = 0u;
    PQMUI_RangeError = 0u;
    PQMUI_MeasurementAvailable = 0u;
    PQMUI_HarmonicsAvailable = 0u;
    PQMUI_RangeRequest = NULL;

    PQMUI_StyleInit();

    screen = lv_scr_act();
    lv_obj_remove_style_all(screen);
    lv_obj_add_style(screen, &PQMUI_StyleScreen, LV_PART_MAIN);

    header = lv_obj_create(screen);
    lv_obj_remove_style_all(header);
    lv_obj_add_style(header, &PQMUI_StyleHeader, LV_PART_MAIN);
    lv_obj_set_pos(header, 0, 0);
    lv_obj_set_size(header, 800, 44);
    lv_obj_clear_flag(header, LV_OBJ_FLAG_SCROLLABLE);

    PQMUI_TitleLabel = lv_label_create(header);
    lv_obj_add_style(PQMUI_TitleLabel, &PQMUI_StyleTitle, LV_PART_MAIN);
    lv_label_set_text(PQMUI_TitleLabel, "PQM - Time Domain");
    lv_obj_set_pos(PQMUI_TitleLabel, 20, 10);

    PQMUI_StatusLabel = lv_label_create(header);
    lv_obj_add_style(PQMUI_StatusLabel, &PQMUI_StyleText, LV_PART_MAIN);
    lv_label_set_text(PQMUI_StatusLabel, "STARTING");
    lv_obj_set_pos(PQMUI_StatusLabel, 430, 13);

    button = PQMUI_CreateButton(header, 560, 6, 102, 32,
                                "Spectrum", &PQMUI_PageButtonLabel);
    lv_obj_add_event_cb(button, PQMUI_PageButtonEvent, LV_EVENT_CLICKED, NULL);
    button = PQMUI_CreateButton(header, 672, 6, 108, 32,
                                "Freeze", &PQMUI_FreezeButtonLabel);
    lv_obj_add_event_cb(button, PQMUI_FreezeButtonEvent, LV_EVENT_CLICKED, NULL);

    PQMUI_TimeCreate();
    PQMUI_FreqCreate();
    PQMUI_HarmonicWindowStart = 0u;
    PQMUI_SetPageVisible();
}

void PQMUI_SetRangeRequest(pqmui_range_request_fn request)
{
    PQMUI_RangeRequest = request;
}

void PQMUI_SetRangeResult(u8 success, u8 low_range)
{
    PQMUI_RangePending = 0u;
    PQMUI_RangeError = success ? 0u : 1u;
    if (success) {
        PQMUI_LowRange = low_range;
    }
    if (PQMUI_RangeButtonLabel != NULL) {
        lv_label_set_text(PQMUI_RangeButtonLabel,
                          PQMUI_LowRange ? "10 V / 3 A" : "350 V / 30 A");
    }
    PQMUI_UpdateStatus();
}

void PQMUI_UpdateMeasurement(const pqmui_measurement_t *measurement)
{
    if (measurement == NULL || PQMUI_Frozen) {
        return;
    }
    PQMUI_LatestMeasurement = *measurement;
    PQMUI_MeasurementAvailable = 1u;
    PQMUI_TimeRefreshMeasurement();
    PQMUI_FreqRefreshMeasurement();
    PQMUI_UpdateStatus();
}

void PQMUI_UpdateWaveform(const pqmui_wave_column_t *columns)
{
    if (columns == NULL || PQMUI_Frozen) {
        return;
    }
    PQMUI_TimeRefreshWaveform(columns);
}

void PQMUI_UpdateHarmonics(const pqmui_harmonic_snapshot_t *harmonics)
{
    if (harmonics == NULL || PQMUI_Frozen) {
        return;
    }
    PQMUI_LatestHarmonics = *harmonics;
    PQMUI_HarmonicsAvailable = 1u;
    PQMUI_FreqRefreshHarmonics();
}
