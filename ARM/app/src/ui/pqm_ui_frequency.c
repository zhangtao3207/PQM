/*
 * PQM频域页面。
 *
 * 显示功率、功率因数、THD和谐波柱状图，并支持在多个谐波窗口间切换。
 * 页面只负责LVGL对象创建和刷新，不直接读取PL共享内存。
 */
#include "pqm_ui_internal.h"

#include <stdio.h>

static const pqm_measurement_field_t frequency_fields[5] = {
    PQM_MEAS_FREQUENCY,
    PQM_MEAS_THD_U,
    PQM_MEAS_THD_I,
    PQM_MEAS_DC_U,
    PQM_MEAS_DC_I
};

static const char *const frequency_names[5] = {
    "Fundamental", "THD-U", "THD-I", "DC-U", "DC-I"
};

static lv_obj_t *create_text(pqm_ui_t *ui, lv_obj_t *parent,
                             lv_coord_t x, lv_coord_t y,
                             const char *text, bool dim)
{
    lv_obj_t *label = lv_label_create(parent);

    lv_obj_add_style(label, dim ? &ui->styles.text_dim : &ui->styles.text,
                     LV_PART_MAIN);
    lv_label_set_text(label, text);
    lv_obj_set_pos(label, x, y);
    return label;
}

static void previous_window(lv_event_t *event)
{
    pqm_ui_t *ui = (pqm_ui_t *)lv_event_get_user_data(event);

    if (ui->harmonic_window_start >= 25u) {
        ui->harmonic_window_start -= 25u;
    } else {
        ui->harmonic_window_start = 0u;
    }
    pqm_ui_frequency_refresh_harmonics(ui);
}

static void next_window(lv_event_t *event)
{
    pqm_ui_t *ui = (pqm_ui_t *)lv_event_get_user_data(event);

    if (ui->harmonic_window_start < 475u) {
        ui->harmonic_window_start += 25u;
    }
    pqm_ui_frequency_refresh_harmonics(ui);
}

void pqm_ui_frequency_create(pqm_ui_t *ui)
{
    lv_obj_t *left;
    lv_obj_t *right;
    lv_obj_t *button;
    lv_obj_t *button_label;
    uint32_t index;

    ui->frequency_page = lv_obj_create(ui->screen);
    lv_obj_remove_style_all(ui->frequency_page);
    lv_obj_set_pos(ui->frequency_page, 0, 44);
    lv_obj_set_size(ui->frequency_page, 800, 436);
    lv_obj_clear_flag(ui->frequency_page, LV_OBJ_FLAG_SCROLLABLE);

    left = lv_obj_create(ui->frequency_page);
    lv_obj_add_style(left, &ui->styles.panel, LV_PART_MAIN);
    lv_obj_set_pos(left, 0, 20);
    lv_obj_set_size(left, 486, 396);
    lv_obj_clear_flag(left, LV_OBJ_FLAG_SCROLLABLE);
    create_text(ui, left, 18, 8, "Harmonic Spectrum", false);

    ui->magnitude_chart = lv_chart_create(left);
    lv_obj_add_style(ui->magnitude_chart, &ui->styles.chart, LV_PART_MAIN);
    lv_obj_set_pos(ui->magnitude_chart, 48, 38);
    lv_obj_set_size(ui->magnitude_chart, 414, 205);
    lv_obj_clear_flag(ui->magnitude_chart, LV_OBJ_FLAG_SCROLLABLE);
    lv_chart_set_type(ui->magnitude_chart, LV_CHART_TYPE_LINE);
    lv_chart_set_point_count(ui->magnitude_chart, PQM_UI_HARMONIC_POINTS);
    lv_chart_set_range(ui->magnitude_chart, LV_CHART_AXIS_PRIMARY_Y, 0, 10000);
    lv_chart_set_div_line_count(ui->magnitude_chart, 5, 6);
    ui->magnitude_series[0] = lv_chart_add_series(
        ui->magnitude_chart, lv_color_hex(0x39E46F), LV_CHART_AXIS_PRIMARY_Y);
    ui->magnitude_series[1] = lv_chart_add_series(
        ui->magnitude_chart, lv_color_hex(0xFFD84E), LV_CHART_AXIS_PRIMARY_Y);
    for (index = 0u; index < 2u; ++index) {
        lv_chart_set_ext_y_array(ui->magnitude_chart,
                                 ui->magnitude_series[index],
                                 ui->magnitude_points[index]);
    }
    create_text(ui, left, 8, 40, "100%", true);
    create_text(ui, left, 20, 220, "0", true);

    ui->phase_chart = lv_chart_create(left);
    lv_obj_add_style(ui->phase_chart, &ui->styles.chart, LV_PART_MAIN);
    lv_obj_set_pos(ui->phase_chart, 48, 266);
    lv_obj_set_size(ui->phase_chart, 414, 82);
    lv_obj_clear_flag(ui->phase_chart, LV_OBJ_FLAG_SCROLLABLE);
    lv_chart_set_type(ui->phase_chart, LV_CHART_TYPE_LINE);
    lv_chart_set_point_count(ui->phase_chart, PQM_UI_HARMONIC_POINTS);
    lv_chart_set_range(ui->phase_chart, LV_CHART_AXIS_PRIMARY_Y, -18000, 18000);
    lv_chart_set_div_line_count(ui->phase_chart, 3, 6);
    ui->phase_series = lv_chart_add_series(
        ui->phase_chart, lv_color_hex(0x58B6FF), LV_CHART_AXIS_PRIMARY_Y);
    lv_chart_set_ext_y_array(ui->phase_chart, ui->phase_series,
                             ui->phase_points);
    create_text(ui, left, 6, 264, "+180", true);
    create_text(ui, left, 12, 322, "-180", true);

    button = pqm_ui_create_button(ui, left, 48, 356, 48, 30,
                                  LV_SYMBOL_LEFT, &button_label);
    lv_obj_add_event_cb(button, previous_window, LV_EVENT_CLICKED, ui);
    ui->harmonic_window_label = create_text(ui, left, 160, 363,
                                             "H0 - H25", false);
    button = pqm_ui_create_button(ui, left, 414, 356, 48, 30,
                                  LV_SYMBOL_RIGHT, &button_label);
    lv_obj_add_event_cb(button, next_window, LV_EVENT_CLICKED, ui);

    right = lv_obj_create(ui->frequency_page);
    lv_obj_add_style(right, &ui->styles.panel, LV_PART_MAIN);
    lv_obj_set_pos(right, 500, 20);
    lv_obj_set_size(right, 300, 396);
    lv_obj_clear_flag(right, LV_OBJ_FLAG_SCROLLABLE);
    create_text(ui, right, 18, 10, "Parameters", false);
    for (index = 0u; index < 8u; ++index) {
        ui->frequency_value_labels[index] = create_text(
            ui, right, 18, (lv_coord_t)(50 + (index * 38u)), "--", false);
    }
}

void pqm_ui_frequency_refresh_measurement(pqm_ui_t *ui)
{
    uint32_t index;

    if (!ui->measurement_available) {
        return;
    }
    for (index = 0u; index < 5u; ++index) {
        char value[32];

        (void)pqm_measurement_format(&ui->latest_measurement,
                                     frequency_fields[index],
                                     value, sizeof(value));
        lv_label_set_text_fmt(ui->frequency_value_labels[index], "%s  %s",
                              frequency_names[index], value);
    }
}

void pqm_ui_frequency_refresh_harmonics(pqm_ui_t *ui)
{
    uint32_t point;
    uint32_t selected;

    if (!ui->harmonics_available) {
        return;
    }
    for (point = 0u; point < PQM_UI_HARMONIC_POINTS; ++point) {
        uint32_t harmonic = ui->harmonic_window_start + point;

        if (harmonic <= PQM_SHM_HARMONIC_LAST_INDEX &&
            (ui->latest_harmonics.entries[harmonic].flags & 1u) != 0u) {
            ui->magnitude_points[0][point] =
                ui->latest_harmonics.entries[harmonic].u_ratio_x100;
            ui->magnitude_points[1][point] =
                ui->latest_harmonics.entries[harmonic].i_ratio_x100;
            ui->phase_points[point] =
                (ui->latest_harmonics.entries[harmonic].flags & 2u) != 0u
                    ? ui->latest_harmonics.entries[harmonic].phase_x100
                    : LV_CHART_POINT_NONE;
        } else {
            ui->magnitude_points[0][point] = LV_CHART_POINT_NONE;
            ui->magnitude_points[1][point] = LV_CHART_POINT_NONE;
            ui->phase_points[point] = LV_CHART_POINT_NONE;
        }
    }
    lv_chart_refresh(ui->magnitude_chart);
    lv_chart_refresh(ui->phase_chart);
    lv_label_set_text_fmt(ui->harmonic_window_label, "H%u - H%u",
                          (unsigned int)ui->harmonic_window_start,
                          (unsigned int)(ui->harmonic_window_start + 25u));

    selected = ui->harmonic_window_start == 0u
                   ? 1u : ui->harmonic_window_start;
    if ((ui->latest_harmonics.entries[selected].flags & 1u) != 0u) {
        const pqm_harmonic_raw_t *entry = &ui->latest_harmonics.entries[selected];
        int32_t phase = entry->phase_x100;
        uint32_t phase_magnitude = (uint32_t)(phase < 0 ? -phase : phase);

        lv_label_set_text_fmt(ui->frequency_value_labels[5],
                              "H%u U  %u.%02u %%", (unsigned int)selected,
                              (unsigned int)(entry->u_ratio_x100 / 100u),
                              (unsigned int)(entry->u_ratio_x100 % 100u));
        lv_label_set_text_fmt(ui->frequency_value_labels[6],
                              "H%u I  %u.%02u %%", (unsigned int)selected,
                              (unsigned int)(entry->i_ratio_x100 / 100u),
                              (unsigned int)(entry->i_ratio_x100 % 100u));
        if ((entry->flags & 2u) != 0u) {
            lv_label_set_text_fmt(ui->frequency_value_labels[7],
                                  "H%u Phase  %c%u.%02u deg",
                                  (unsigned int)selected,
                                  phase < 0 ? '-' : '+',
                                  (unsigned int)(phase_magnitude / 100u),
                                  (unsigned int)(phase_magnitude % 100u));
        } else {
            lv_label_set_text_fmt(ui->frequency_value_labels[7],
                                  "H%u Phase  -- deg", (unsigned int)selected);
        }
    } else {
        lv_label_set_text_fmt(ui->frequency_value_labels[5],
                              "H%u U  -- %%", (unsigned int)selected);
        lv_label_set_text_fmt(ui->frequency_value_labels[6],
                              "H%u I  -- %%", (unsigned int)selected);
        lv_label_set_text_fmt(ui->frequency_value_labels[7],
                              "H%u Phase  -- deg", (unsigned int)selected);
    }
}
