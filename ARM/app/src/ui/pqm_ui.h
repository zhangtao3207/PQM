#ifndef PQM_UI_H
#define PQM_UI_H

#include <stdbool.h>
#include <stdint.h>

#include "lvgl.h"

#include "../drivers/pqm_axi/pqm_axi.h"
#include "../services/measurement/pqm_measurement.h"
#include "../services/waveform/pqm_waveform.h"

#define PQM_UI_WAVE_COLUMNS 400u
#define PQM_UI_HARMONIC_POINTS 26u

typedef struct {
    lv_style_t screen;
    lv_style_t header;
    lv_style_t panel;
    lv_style_t chart;
    lv_style_t button;
    lv_style_t button_pressed;
    lv_style_t title;
    lv_style_t text;
    lv_style_t text_dim;
    lv_style_t alarm;
} pqm_ui_styles_t;

typedef struct pqm_ui {
    pqm_ui_styles_t styles;
    lv_obj_t *screen;
    lv_obj_t *time_page;
    lv_obj_t *frequency_page;
    lv_obj_t *title_label;
    lv_obj_t *status_label;
    lv_obj_t *page_button_label;
    lv_obj_t *freeze_button_label;
    lv_obj_t *time_chart;
    lv_chart_series_t *time_series[4];
    lv_coord_t time_points[4][PQM_UI_WAVE_COLUMNS];
    lv_obj_t *time_value_labels[10];
    lv_obj_t *range_button_label;
    lv_obj_t *magnitude_chart;
    lv_obj_t *phase_chart;
    lv_chart_series_t *magnitude_series[2];
    lv_chart_series_t *phase_series;
    lv_coord_t magnitude_points[2][PQM_UI_HARMONIC_POINTS];
    lv_coord_t phase_points[PQM_UI_HARMONIC_POINTS];
    lv_obj_t *frequency_value_labels[8];
    lv_obj_t *harmonic_window_label;
    pqm_measurement_t latest_measurement;
    pqm_harmonic_raw_snapshot_t latest_harmonics;
    uint16_t harmonic_window_start;
    bool measurement_available;
    bool harmonics_available;
    bool frequency_active;
    bool frozen;
    bool low_range;
} pqm_ui_t;

bool pqm_ui_initialize(pqm_ui_t *ui);
void pqm_ui_update_measurement(pqm_ui_t *ui,
                               const pqm_measurement_t *measurement);
void pqm_ui_update_waveform(pqm_ui_t *ui,
                            const pqm_wave_column_t columns[PQM_UI_WAVE_COLUMNS]);
void pqm_ui_update_harmonics(pqm_ui_t *ui,
                             const pqm_harmonic_raw_snapshot_t *harmonics);

#endif
