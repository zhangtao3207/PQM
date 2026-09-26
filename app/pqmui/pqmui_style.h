/*
 * PQM 界面公共样式接口。
 */

#ifndef __PQMUI_STYLE_H__
#define __PQMUI_STYLE_H__

#include "xil_types.h"
#include "lvgl.h"

extern lv_style_t PQMUI_StyleScreen;
extern lv_style_t PQMUI_StyleHeader;
extern lv_style_t PQMUI_StylePanel;
extern lv_style_t PQMUI_StyleChart;
extern lv_style_t PQMUI_StyleButton;
extern lv_style_t PQMUI_StyleButtonPressed;
extern lv_style_t PQMUI_StyleTitle;
extern lv_style_t PQMUI_StyleText;
extern lv_style_t PQMUI_StyleTextDim;
extern lv_style_t PQMUI_StyleAlarm;

/* 界面用到的固定颜色，供页面直接引用。 */
#define PQMUI_COLOR_U_WAVE    0x39E46Fu
#define PQMUI_COLOR_I_WAVE    0xFFD84Eu
#define PQMUI_COLOR_PHASE     0x58B6FFu
#define PQMUI_COLOR_ALARM     0xFF5A5Fu
#define PQMUI_COLOR_STATUS    0xC6D3E2u

void PQMUI_StyleInit(void);

#endif /* __PQMUI_STYLE_H__ */
