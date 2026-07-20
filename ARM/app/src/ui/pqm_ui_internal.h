/* PQM界面内部接口：连接公共样式、时域页面和频域页面实现。 */
#ifndef PQM_UI_INTERNAL_H
#define PQM_UI_INTERNAL_H

#include "pqm_ui.h"

void pqm_ui_style_initialize(pqm_ui_styles_t *styles);
void pqm_ui_time_create(pqm_ui_t *ui);
void pqm_ui_time_refresh_measurement(pqm_ui_t *ui);
void pqm_ui_time_refresh_waveform(
    pqm_ui_t *ui, const pqm_wave_column_t columns[PQM_UI_WAVE_COLUMNS]);
void pqm_ui_frequency_create(pqm_ui_t *ui);
void pqm_ui_frequency_refresh_measurement(pqm_ui_t *ui);
void pqm_ui_frequency_refresh_harmonics(pqm_ui_t *ui);

lv_obj_t *pqm_ui_create_button(pqm_ui_t *ui, lv_obj_t *parent,
                               lv_coord_t x, lv_coord_t y,
                               lv_coord_t width, lv_coord_t height,
                               const char *text, lv_obj_t **label);

#endif
