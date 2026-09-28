/*
 * PQM 频域页面。
 *
 * 显示谐波幅值占比、谐波相位与五项规定参数，并支持在多个谐波窗口间切换。
 * 页面只负责 LVGL 对象创建与刷新，不读取任何硬件。
 */

#include "pqmui_internal.h"
#include "pqmui_format.h"
#include "pqmui_style.h"

#include <stdio.h>
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
/* 相位图的 y 数组。相位是有符号量，但 LVGL 一个 series 只有一种颜色，
 * 所以颜色不在 series 上定，改由 PQMUI_FreqPhaseBarDraw 在逐柱绘制时按符号改 ——
 * 这样正负柱都占满同一个块宽、x 位置一致；
 * 若像早前那样拆成「正/负两个 series」，两个 series 会各占半个块宽，
 * 同一根谐波换个符号柱子就横向跳半个块宽。 */
static lv_coord_t PhasePoints[PQMUI_HARMONIC_POINTS];
static lv_obj_t *FreqValueLabels[5];
static lv_obj_t *FreqHarmonicLabels[3];
static lv_obj_t *HarmonicWindowLabel;
/* 频域两张图共用的横坐标刻度标签：每 PQMUI_HARMONIC_TICK_STEP 根标一次。
 * 挂在左面板上而不是图表上 —— 图表自己的绘图区不放文字，挂上去会被裁掉。 */
static lv_obj_t *FreqTickLabels[PQMUI_HARMONIC_TICK_COUNT];

/* 图表在左面板里的 x 偏移，以及刻度行所在的 y（夹在幅度图与相位图之间）。 */
#define PQMUI_FREQ_CHART_X     48
#define PQMUI_FREQ_TICK_Y      247

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

/*
 * 图表绘图区里 y = 0 刻度线所在的屏幕行。与 LVGL 的两处绘制用同一套公式：
 *   draw_series_bar(): col_a.y1 = h - y_tmp + obj->coords.y1 + pad_top - scroll_top
 *   draw_div_lines():  p1.y    = h * i / (hdiv-1) + obj->coords.y1 + pad_top + border - scroll_top
 * 其中 h 是内容高度，y_tmp = (v - ymin) * h / (ymax - ymin)。
 * 相位图值域是 -18000..18000，v = 0 恰好落在 h/2。
 */
static lv_coord_t PQMUI_FreqChartZeroY(lv_obj_t *chart)
{
    lv_coord_t pad_top = lv_obj_get_style_pad_top(chart, LV_PART_MAIN);
    lv_coord_t height =
        (lv_coord_t)(((int32_t)lv_obj_get_content_height(chart) *
                      (int32_t)lv_chart_get_zoom_y(chart)) >> 8);

    return (lv_coord_t)(chart->coords.y1 + pad_top -
                        lv_obj_get_scroll_top(chart) + (height / 2));
}

/*
 * LVGL 的条形图一律从「图表对象的底边」往上长 —— draw_series_bar() 里
 * col_a.y2 恒等于 obj->coords.y2，没有零基线的概念。
 * 幅度图值域是 0..10000，底边恰好就是 0，所以看不出问题；
 * 相位图值域是 -180..+180，底边对应 -180，于是每根柱都会从自己的相位值一直拉到 -180，
 * 读出来的其实是「离 -180 还有多远」，正相位更是几乎满格 —— 整张图是错的。
 * 这里在矩形绘制前把柱子的另一端掰到 0 刻度线上，柱形才真正表示相位的大小与正负。
 */
static void PQMUI_FreqPhaseBarDraw(lv_event_t *event)
{
    lv_obj_draw_part_dsc_t *dsc = lv_event_get_draw_part_dsc(event);
    lv_coord_t zero_y;
    lv_coord_t value_y;

    if (dsc == NULL || dsc->part != LV_PART_ITEMS ||
        dsc->type != LV_CHART_DRAW_PART_BAR || dsc->draw_area == NULL) {
        return;
    }

    zero_y = PQMUI_FreqChartZeroY(lv_event_get_target(event));
    /* LVGL 交给这里的矩形两端是「数值行(y1) .. 图表对象的底边(y2)」，
     * y2 恒等于相位图的 -180 线。
     *   正相位：数值行在 0 线之上，y1 已经是对的，把 y2 收到 0 线即可；
     *   负相位：数值行在 0 线之下，得**同时**改两端 —— y1 收到 0 线、
     *           y2 从图表底边收到数值行。只改 y1 会让柱子从 0 线一路铺到底
     *           （第一版就是这么错的，红柱画成了整整半屏）。 */
    value_y = dsc->draw_area->y1;
    if (dsc->value >= 0) {
        if (dsc->draw_area->y2 > zero_y) {
            dsc->draw_area->y2 = zero_y;
        }
        if (dsc->rect_dsc != NULL) {
            dsc->rect_dsc->bg_color = lv_color_hex(PQMUI_COLOR_PHASE);
        }
    } else {
        if (value_y > zero_y) {
            dsc->draw_area->y1 = zero_y;
            dsc->draw_area->y2 = value_y;
        }
        if (dsc->rect_dsc != NULL) {
            dsc->rect_dsc->bg_color = lv_color_hex(PQMUI_COLOR_ALARM);
        }
    }
}

/*
 * 第 point 根柱子的水平中心（左面板坐标系）。公式与 draw_series_bar() 一致：
 *   x(i) = (w + gap) * i / point_cnt + pad_left，再加半个块宽即中心。
 */
static lv_coord_t PQMUI_FreqTickCenterX(u32 point)
{
    lv_coord_t content_w = lv_obj_get_content_width(MagnitudeChart);
    lv_coord_t gap = lv_obj_get_style_pad_column(MagnitudeChart, LV_PART_MAIN);
    lv_coord_t pad_left = lv_obj_get_style_pad_left(MagnitudeChart, LV_PART_MAIN);
    lv_coord_t block_w =
        (lv_coord_t)((content_w - ((lv_coord_t)(PQMUI_HARMONIC_POINTS - 1) * gap)) /
                     (lv_coord_t)PQMUI_HARMONIC_POINTS);
    lv_coord_t start =
        (lv_coord_t)(((content_w + gap) * (lv_coord_t)point) /
                     (lv_coord_t)PQMUI_HARMONIC_POINTS);

    return (lv_coord_t)(PQMUI_FREQ_CHART_X + pad_left + start + (block_w / 2));
}

/*
 * 按本页起点重排横坐标刻度：数字是绝对谐波号（第 1 页 0/4/8/12，第 2 页 16/20/24/28…），
 * 位置每次按文字实际宽度重新居中，否则 "0" 和 "16" 会偏。
 */
static void PQMUI_FreqRefreshTicks(void)
{
    u32 tick;

    for (tick = 0u; tick < (u32)PQMUI_HARMONIC_TICK_COUNT; ++tick) {
        char text[8];
        lv_point_t size;
        u32 offset = tick * (u32)PQMUI_HARMONIC_TICK_STEP;
        u32 order = (u32)PQMUI_HarmonicWindowStart + offset;
        const lv_font_t *font =
            lv_obj_get_style_text_font(FreqTickLabels[tick], LV_PART_MAIN);

        (void)snprintf(text, sizeof(text), "%u", (unsigned int)order);
        lv_label_set_text(FreqTickLabels[tick], text);
        lv_txt_get_size(&size, text, font, 0, 0, LV_COORD_MAX, LV_TEXT_FLAG_NONE);
        lv_obj_set_pos(FreqTickLabels[tick],
                       (lv_coord_t)(PQMUI_FreqTickCenterX(offset) - (size.x / 2)),
                       PQMUI_FREQ_TICK_Y);
    }
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
    /* 与时域页同宽（494，旧规格 486）：让两页切换时左面板右边界对齐。 */
    lv_obj_set_size(left, 494, 396);
    lv_obj_clear_flag(left, LV_OBJ_FLAG_SCROLLABLE);
    PQMUI_CreateText(left, 18, 8, "Harmonic Spectrum", 0u);

    MagnitudeChart = lv_chart_create(left);
    lv_obj_add_style(MagnitudeChart, &PQMUI_StyleChart, LV_PART_MAIN);
    lv_obj_set_pos(MagnitudeChart, 48, 38);
    lv_obj_set_size(MagnitudeChart, 414, 205);
    lv_obj_clear_flag(MagnitudeChart, LV_OBJ_FLAG_SCROLLABLE);
    /* 零掉上下内边距。LVGL 主题给 chart 的默认内边距让绘图区比边框小一圈，于是
     * 「0 刻度线」和「下边框」成了相隔约 10 px 的两条线；而条形图又恒从对象底边起画，
     * 柱子会穿过 0 线扎到边框上（实测 U 的 H1 柱画到 y=306，0 线却在 y=296）。
     * 置 0 后由 LVGL 自己合掉重复的那条：border 与 pad 重合时不再画那条 div 线。
     * 半径也置 0，否则柱子还会往下多溢出 col_dsc.radius 个像素。
     * 只改频域这两张图，时域页的波形图保持原样。 */
    lv_obj_set_style_pad_top(MagnitudeChart, 0, LV_PART_MAIN);
    lv_obj_set_style_pad_bottom(MagnitudeChart, 0, LV_PART_MAIN);
    lv_obj_set_style_radius(MagnitudeChart, 0, LV_PART_ITEMS);
    /* 谐波占比按“每个谐波一根”的方式展示，故用条形图；相位图同样是条形图。 */
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
    /* 纵轴刻度文字与绘图区上下边对齐：边距置 0 后，上边框就是 100% 线、下边框就是 0 线。 */
    PQMUI_CreateText(left, 8, 30, "100%", 1u);
    PQMUI_CreateText(left, 20, 234, "0", 1u);
    /* 横坐标刻度行：夹在两张图之间，数字由 PQMUI_FreqRefreshTicks() 按当前页填。 */
    for (index = 0u; index < (u32)PQMUI_HARMONIC_TICK_COUNT; ++index) {
        FreqTickLabels[index] = PQMUI_CreateText(left, 0, PQMUI_FREQ_TICK_Y, "", 1u);
    }

    PhaseChart = lv_chart_create(left);
    lv_obj_add_style(PhaseChart, &PQMUI_StyleChart, LV_PART_MAIN);
    lv_obj_set_pos(PhaseChart, 48, 266);
    lv_obj_set_size(PhaseChart, 414, 82);
    lv_obj_clear_flag(PhaseChart, LV_OBJ_FLAG_SCROLLABLE);
    /* 相位图与上方幅度图同宽同 x 位置：同样用条形图，缺相谐波不画柱，
     * 不再像折线图那样只剩零星散点。
     * 只用一个 series：颜色（正蓝 / 非正红）在 PQMUI_FreqPhaseBarDraw 里逐柱改，
     * 这样正负柱都占满同一个块宽，x 位置不会随符号变化。 */
    lv_chart_set_type(PhaseChart, LV_CHART_TYPE_BAR);
    lv_chart_set_point_count(PhaseChart, PQMUI_HARMONIC_POINTS);
    lv_chart_set_range(PhaseChart, LV_CHART_AXIS_PRIMARY_Y, -18000, 18000);
    lv_chart_set_div_line_count(PhaseChart, 3, 6);
    PhaseSeries = lv_chart_add_series(PhaseChart,
                                      lv_color_hex(PQMUI_COLOR_PHASE),
                                      LV_CHART_AXIS_PRIMARY_Y);
    lv_chart_set_ext_y_array(PhaseChart, PhaseSeries, PhasePoints);
    /* 上下边距同样置 0：上边框 = +180 线、下边框 = -180 线、中间那条 = 0 线。 */
    lv_obj_set_style_pad_top(PhaseChart, 0, LV_PART_MAIN);
    lv_obj_set_style_pad_bottom(PhaseChart, 0, LV_PART_MAIN);
    lv_obj_set_style_radius(PhaseChart, 0, LV_PART_ITEMS);
    /* 见 PQMUI_FreqPhaseBarDraw：把每根柱的另一端掰到 0 刻度线上。 */
    lv_obj_add_event_cb(PhaseChart, PQMUI_FreqPhaseBarDraw,
                        LV_EVENT_DRAW_PART_BEGIN, NULL);
    PQMUI_CreateText(left, 6, 258, "+180", 1u);
    PQMUI_CreateText(left, 12, 339, "-180", 1u);

    button = PQMUI_CreateButton(left, 48, 356, 48, 30,
                                LV_SYMBOL_LEFT, &label);
    lv_obj_add_event_cb(button, PQMUI_PreviousWindowEvent, LV_EVENT_CLICKED,
                        NULL);
    HarmonicWindowLabel = PQMUI_CreateText(left, 160, 363, "H0 - H15", 0u);
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
    u32 probe;

    if (!PQMUI_HarmonicsAvailable) {
        return;
    }
    for (point = 0u; point < PQMUI_HARMONIC_POINTS; ++point) {
        /* 窗口起点就是本页首条：本页绘制 H(起点) .. H(起点+POINTS-1)，
         * 4 页 = H0-H15 / H16-H31 / H32-H47 / H48-H63，H0 也在第 1 页的图里。*/
        u32 harmonic = (u32)PQMUI_HarmonicWindowStart + point;

        if (harmonic < PQMUI_HARMONIC_ENTRIES &&
            (PQMUI_LatestHarmonics.entries[harmonic].flags &
             PQMUI_HARMONIC_FLAG_RATIO) != 0u) {
            const pqmui_harmonic_t *harm_entry =
                &PQMUI_LatestHarmonics.entries[harmonic];
            u8 phase_meaningful =
                (harm_entry->u_ratio_x100 >= PQMUI_HARMONIC_PHASE_MIN_RATIO_X100) &&
                (harm_entry->i_ratio_x100 >= PQMUI_HARMONIC_PHASE_MIN_RATIO_X100);

            /* 占比为 0 的空槽（flags 里有 RATIO 位、占比却是 0，例如 H2/H4/H6）不画
             * 0 高度小柱，否则幅度图底部会排出一行“梳齿”；与 H0「空槽不画」的口径一致。
             * 两个通道各自判：某通道占比为 0 就只隐掉该通道那根柱。 */
            MagnitudePoints[0][point] =
                (harm_entry->u_ratio_x100 != 0u)
                    ? (lv_coord_t)harm_entry->u_ratio_x100
                    : LV_CHART_POINT_NONE;
            MagnitudePoints[1][point] =
                (harm_entry->i_ratio_x100 != 0u)
                    ? (lv_coord_t)harm_entry->i_ratio_x100
                    : LV_CHART_POINT_NONE;

            /* 相位柱只在两路幅值都有意义时才画。零幅值谐波的相位是 atan2(≈0,≈0) 的噪声，
             * 画出来就是“蹦来蹦去”，而 PL 的 PHASE 标志并不代表幅值有意义（详见
             * PQMUI_HARMONIC_PHASE_MIN_RATIO_X100 的说明）。判据与幅度柱保持一致。
             * 颜色不在这里定：符号在 PQMUI_FreqPhaseBarDraw 里逐柱判断。 */
            PhasePoints[point] =
                ((harm_entry->flags & PQMUI_HARMONIC_FLAG_PHASE) != 0u &&
                 phase_meaningful)
                    ? (lv_coord_t)harm_entry->phase_x100
                    : LV_CHART_POINT_NONE;
        } else {
            MagnitudePoints[0][point] = LV_CHART_POINT_NONE;
            MagnitudePoints[1][point] = LV_CHART_POINT_NONE;
            PhasePoints[point] = LV_CHART_POINT_NONE;
        }
    }
    lv_chart_refresh(MagnitudeChart);
    lv_chart_refresh(PhaseChart);
    /* 标签显示本页覆盖的谐波范围：左端 = 本页首条（窗口起点），右端 = 起点 + STEP - 1。 */
    lv_label_set_text_fmt(HarmonicWindowLabel, "H%u - H%u",
                          (unsigned int)PQMUI_HarmonicWindowStart,
                          (unsigned int)(PQMUI_HarmonicWindowStart +
                                         (PQMUI_HARMONIC_STEP - 1u)));
    /* 横坐标刻度跟着翻页重排：本页每 4 根标一次，写绝对谐波号。 */
    PQMUI_FreqRefreshTicks();

    /* 谐波详情块显示「本页第一条 present 的谐波」，而不是窗口起点本身：
     * H0 是直流槽，本轮 PL 修好 DC 后它也会 present（flags 0x00 -> 0x01）。
     * 详情块要的是谐波，所以扫描时跳过 order 0（直流），优先落到基波 H1。
     * 扫描范围是 [窗口起点, 窗口起点 + 本页条数)，上界同时夹住
     * PQMUI_HARMONIC_ENTRIES，避免越界读。整页都无 present 时
     * 退回窗口起点并沿用 -- 兜底。 */
    selected = (u32)PQMUI_HarmonicWindowStart;
    for (probe = selected;
         (probe < (u32)PQMUI_HARMONIC_ENTRIES) &&
         (probe < (selected + (u32)PQMUI_HARMONIC_POINTS));
         ++probe) {
        if (probe == 0u) {
            continue;   /* 跳过 H0（直流），基波 H1 起算 */
        }
        if ((PQMUI_LatestHarmonics.entries[probe].flags &
             PQMUI_HARMONIC_FLAG_RATIO) != 0u) {
            selected = probe;
            break;
        }
    }

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
        /* 相位文本与相位柱同一条判据：零幅值谐波的相位是噪声，宁可不显示。 */
        if ((entry->flags & PQMUI_HARMONIC_FLAG_PHASE) != 0u &&
            entry->u_ratio_x100 >= PQMUI_HARMONIC_PHASE_MIN_RATIO_X100 &&
            entry->i_ratio_x100 >= PQMUI_HARMONIC_PHASE_MIN_RATIO_X100) {
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
