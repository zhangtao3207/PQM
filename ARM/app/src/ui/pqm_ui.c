#include "pqm_ui_internal.h"

#include <stddef.h>
#include <string.h>

static void update_alarm(pqm_ui_t *ui);

static void set_page_visible(pqm_ui_t *ui)
{
    if (ui->frequency_active) {
        lv_obj_add_flag(ui->time_page, LV_OBJ_FLAG_HIDDEN);
        lv_obj_clear_flag(ui->frequency_page, LV_OBJ_FLAG_HIDDEN);
        lv_label_set_text(ui->title_label, "PQM - Frequency Domain");
        lv_label_set_text(ui->page_button_label, "Time");
    } else {
        lv_obj_clear_flag(ui->time_page, LV_OBJ_FLAG_HIDDEN);
        lv_obj_add_flag(ui->frequency_page, LV_OBJ_FLAG_HIDDEN);
        lv_label_set_text(ui->title_label, "PQM - Time Domain");
        lv_label_set_text(ui->page_button_label, "Spectrum");
    }
}

static void page_event(lv_event_t *event)
{
    pqm_ui_t *ui = (pqm_ui_t *)lv_event_get_user_data(event);

    ui->frequency_active = !ui->frequency_active;
    set_page_visible(ui);
}

static void freeze_event(lv_event_t *event)
{
    pqm_ui_t *ui = (pqm_ui_t *)lv_event_get_user_data(event);

    ui->frozen = !ui->frozen;
    lv_label_set_text(ui->freeze_button_label, ui->frozen ? "Resume" : "Freeze");
    update_alarm(ui);
}

lv_obj_t *pqm_ui_create_button(pqm_ui_t *ui, lv_obj_t *parent,
                               lv_coord_t x, lv_coord_t y,
                               lv_coord_t width, lv_coord_t height,
                               const char *text, lv_obj_t **label)
{
    lv_obj_t *button = lv_btn_create(parent);

    lv_obj_set_pos(button, x, y);
    lv_obj_set_size(button, width, height);
    lv_obj_add_style(button, &ui->styles.button, LV_PART_MAIN);
    lv_obj_add_style(button, &ui->styles.button_pressed,
                     LV_PART_MAIN | LV_STATE_PRESSED);
    *label = lv_label_create(button);
    lv_label_set_text(*label, text);
    lv_obj_center(*label);
    return button;
}

static void update_alarm(pqm_ui_t *ui)
{
    uint32_t code = (ui->latest_measurement.alarm >> 1u) & 0x7u;
    const char *channel = (code == 3u || code == 4u) ? "I" : "U";
    const char *direction = (code == 2u || code == 4u) ? "DROP" : "RISE";

    if ((ui->latest_measurement.alarm & 1u) != 0u && code != 0u) {
        lv_label_set_text_fmt(ui->status_label, "ALARM %s %s",
                              channel, direction);
        lv_obj_set_style_text_color(ui->status_label,
                                    lv_color_hex(0xFF5A5F), LV_PART_MAIN);
    } else {
        lv_label_set_text(ui->status_label, ui->frozen ? "FROZEN" : "RUN");
        lv_obj_set_style_text_color(ui->status_label,
                                    lv_color_hex(0xC6D3E2), LV_PART_MAIN);
    }
}

bool pqm_ui_initialize(pqm_ui_t *ui)
{
    lv_obj_t *header;
    lv_obj_t *button;

    if (ui == NULL) {
        return false;
    }
    memset(ui, 0, sizeof(*ui));
    pqm_ui_style_initialize(&ui->styles);
    ui->screen = lv_scr_act();
    if (ui->screen == NULL) {
        return false;
    }
    lv_obj_remove_style_all(ui->screen);
    lv_obj_add_style(ui->screen, &ui->styles.screen, LV_PART_MAIN);

    header = lv_obj_create(ui->screen);
    lv_obj_remove_style_all(header);
    lv_obj_add_style(header, &ui->styles.header, LV_PART_MAIN);
    lv_obj_set_pos(header, 0, 0);
    lv_obj_set_size(header, 800, 44);
    lv_obj_clear_flag(header, LV_OBJ_FLAG_SCROLLABLE);

    ui->title_label = lv_label_create(header);
    lv_obj_add_style(ui->title_label, &ui->styles.title, LV_PART_MAIN);
    lv_label_set_text(ui->title_label, "PQM - Time Domain");
    lv_obj_set_pos(ui->title_label, 20, 10);

    ui->status_label = lv_label_create(header);
    lv_obj_add_style(ui->status_label, &ui->styles.text, LV_PART_MAIN);
    lv_label_set_text(ui->status_label, "STARTING");
    lv_obj_set_pos(ui->status_label, 430, 13);

    button = pqm_ui_create_button(ui, header, 560, 6, 102, 32,
                                  "Spectrum", &ui->page_button_label);
    lv_obj_add_event_cb(button, page_event, LV_EVENT_CLICKED, ui);
    button = pqm_ui_create_button(ui, header, 672, 6, 108, 32,
                                  "Freeze", &ui->freeze_button_label);
    lv_obj_add_event_cb(button, freeze_event, LV_EVENT_CLICKED, ui);

    pqm_ui_time_create(ui);
    pqm_ui_frequency_create(ui);
    ui->harmonic_window_start = 1u;
    set_page_visible(ui);
    return true;
}

void pqm_ui_update_measurement(pqm_ui_t *ui,
                               const pqm_measurement_t *measurement)
{
    if (ui == NULL || measurement == NULL || ui->frozen) {
        return;
    }
    ui->latest_measurement = *measurement;
    ui->measurement_available = true;
    pqm_ui_time_refresh_measurement(ui);
    pqm_ui_frequency_refresh_measurement(ui);
    update_alarm(ui);
}

void pqm_ui_update_waveform(pqm_ui_t *ui,
                            const pqm_wave_column_t columns[PQM_UI_WAVE_COLUMNS])
{
    if (ui == NULL || columns == NULL || ui->frozen) {
        return;
    }
    pqm_ui_time_refresh_waveform(ui, columns);
}

void pqm_ui_update_harmonics(pqm_ui_t *ui,
                             const pqm_harmonic_raw_snapshot_t *harmonics)
{
    if (ui == NULL || harmonics == NULL || ui->frozen) {
        return;
    }
    ui->latest_harmonics = *harmonics;
    ui->harmonics_available = true;
    pqm_ui_frequency_refresh_harmonics(ui);
}
