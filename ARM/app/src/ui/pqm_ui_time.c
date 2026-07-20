#include "pqm_ui_internal.h"

#include <limits.h>
#include <stdio.h>

static const pqm_measurement_field_t time_fields[10] = {
    PQM_MEAS_FREQUENCY,
    PQM_MEAS_U_RMS,
    PQM_MEAS_I_RMS,
    PQM_MEAS_U_P2P,
    PQM_MEAS_I_P2P,
    PQM_MEAS_PHASE,
    PQM_MEAS_ACTIVE_POWER,
    PQM_MEAS_REACTIVE_POWER,
    PQM_MEAS_APPARENT_POWER,
    PQM_MEAS_POWER_FACTOR
};

static const char *const time_names[10] = {
    "Frequency", "U RMS", "I RMS", "U P-P", "I P-P",
    "Phase", "Active P", "Reactive Q", "Apparent S", "Power factor"
};

static void range_event(lv_event_t *event)
{
    pqm_ui_t *ui = (pqm_ui_t *)lv_event_get_user_data(event);
    bool requested_low_range;

    if (ui->range_pending) {
        return;
    }
    requested_low_range = !ui->low_range;
    if (ui->range_request != NULL &&
        ui->range_request(ui->range_request_context, requested_low_range)) {
        ui->range_pending = true;
        ui->range_error = false;
        lv_label_set_text(ui->range_button_label, "Switching...");
    } else {
        pqm_ui_set_range_result(ui, false, ui->low_range);
    }
}

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

void pqm_ui_time_create(pqm_ui_t *ui)
{
    lv_obj_t *left;
    lv_obj_t *right;
    lv_obj_t *button;
    uint32_t index;

    ui->time_page = lv_obj_create(ui->screen);
    lv_obj_remove_style_all(ui->time_page);
    lv_obj_set_pos(ui->time_page, 0, 44);
    lv_obj_set_size(ui->time_page, 800, 436);
    lv_obj_clear_flag(ui->time_page, LV_OBJ_FLAG_SCROLLABLE);

    left = lv_obj_create(ui->time_page);
    lv_obj_add_style(left, &ui->styles.panel, LV_PART_MAIN);
    lv_obj_set_pos(left, 0, 20);
    lv_obj_set_size(left, 486, 396);
    lv_obj_clear_flag(left, LV_OBJ_FLAG_SCROLLABLE);
    create_text(ui, left, 18, 10, "Voltage / Current Waveform", false);
    create_text(ui, left, 302, 12, "U", false);
    lv_obj_set_style_text_color(lv_obj_get_child(left, -1),
                                lv_color_hex(0x39E46F), LV_PART_MAIN);
    create_text(ui, left, 340, 12, "I", false);
    lv_obj_set_style_text_color(lv_obj_get_child(left, -1),
                                lv_color_hex(0xFFD84E), LV_PART_MAIN);

    ui->time_chart = lv_chart_create(left);
    lv_obj_add_style(ui->time_chart, &ui->styles.chart, LV_PART_MAIN);
    lv_obj_set_pos(ui->time_chart, 48, 48);
    lv_obj_set_size(ui->time_chart, 414, 280);
    lv_obj_clear_flag(ui->time_chart, LV_OBJ_FLAG_SCROLLABLE);
    lv_chart_set_type(ui->time_chart, LV_CHART_TYPE_LINE);
    lv_chart_set_point_count(ui->time_chart, PQM_UI_WAVE_COLUMNS);
    lv_chart_set_range(ui->time_chart, LV_CHART_AXIS_PRIMARY_Y,
                       -32767, 32767);
    lv_chart_set_div_line_count(ui->time_chart, 7, 8);
    ui->time_series[0] = lv_chart_add_series(
        ui->time_chart, lv_color_hex(0x39E46F), LV_CHART_AXIS_PRIMARY_Y);
    ui->time_series[1] = lv_chart_add_series(
        ui->time_chart, lv_color_hex(0x39E46F), LV_CHART_AXIS_PRIMARY_Y);
    ui->time_series[2] = lv_chart_add_series(
        ui->time_chart, lv_color_hex(0xFFD84E), LV_CHART_AXIS_PRIMARY_Y);
    ui->time_series[3] = lv_chart_add_series(
        ui->time_chart, lv_color_hex(0xFFD84E), LV_CHART_AXIS_PRIMARY_Y);
    for (index = 0u; index < 4u; ++index) {
        lv_chart_set_ext_y_array(ui->time_chart, ui->time_series[index],
                                 ui->time_points[index]);
    }
    create_text(ui, left, 8, 54, "+FS", true);
    create_text(ui, left, 14, 184, "0", true);
    create_text(ui, left, 8, 310, "-FS", true);
    create_text(ui, left, 48, 338, "0", true);
    create_text(ui, left, 420, 338, "20 ms", true);
    button = pqm_ui_create_button(ui, left, 145, 354, 196, 32,
                                  "350 V / 30 A", &ui->range_button_label);
    lv_obj_add_event_cb(button, range_event, LV_EVENT_CLICKED, ui);

    right = lv_obj_create(ui->time_page);
    lv_obj_add_style(right, &ui->styles.panel, LV_PART_MAIN);
    lv_obj_set_pos(right, 500, 20);
    lv_obj_set_size(right, 300, 396);
    lv_obj_clear_flag(right, LV_OBJ_FLAG_SCROLLABLE);
    create_text(ui, right, 18, 10, "Parameters", false);
    for (index = 0u; index < 10u; ++index) {
        ui->time_value_labels[index] = create_text(
            ui, right, 18, (lv_coord_t)(48 + (index * 32u)), "--", false);
    }
}

void pqm_ui_time_refresh_measurement(pqm_ui_t *ui)
{
    uint32_t index;

    if (!ui->measurement_available) {
        return;
    }
    for (index = 0u; index < 10u; ++index) {
        char value[32];

        (void)pqm_measurement_format(&ui->latest_measurement,
                                     time_fields[index], value, sizeof(value));
        lv_label_set_text_fmt(ui->time_value_labels[index], "%s  %s",
                              time_names[index], value);
    }
}

void pqm_ui_time_refresh_waveform(
    pqm_ui_t *ui, const pqm_wave_column_t columns[PQM_UI_WAVE_COLUMNS])
{
    uint32_t index;

    for (index = 0u; index < PQM_UI_WAVE_COLUMNS; ++index) {
        ui->time_points[0][index] = columns[index].u_min == INT16_MIN
                                         ? -32767 : columns[index].u_min;
        ui->time_points[1][index] = columns[index].u_max;
        ui->time_points[2][index] = columns[index].i_min == INT16_MIN
                                         ? -32767 : columns[index].i_min;
        ui->time_points[3][index] = columns[index].i_max;
    }
    lv_chart_refresh(ui->time_chart);
}
