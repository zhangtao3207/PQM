/*
 * PQM 界面公共样式。
 *
 * 集中初始化页面背景、信息面板、图表、按钮与文字样式，保证时域页和频域页
 * 使用一致的颜色、边框和字号。颜色与尺寸取自旧工程 PQM 的界面规格。
 */

#include "pqmui_internal.h"
#include "pqmui_style.h"

lv_style_t PQMUI_StyleScreen;
lv_style_t PQMUI_StyleHeader;
lv_style_t PQMUI_StylePanel;
lv_style_t PQMUI_StyleChart;
lv_style_t PQMUI_StyleButton;
lv_style_t PQMUI_StyleButtonPressed;
lv_style_t PQMUI_StyleTitle;
lv_style_t PQMUI_StyleText;
lv_style_t PQMUI_StyleTextDim;
lv_style_t PQMUI_StyleAlarm;

void PQMUI_StyleInit(void)
{
    lv_style_init(&PQMUI_StyleScreen);
    lv_style_set_bg_color(&PQMUI_StyleScreen, lv_color_hex(0x0B1524));
    lv_style_set_bg_opa(&PQMUI_StyleScreen, LV_OPA_COVER);
    lv_style_set_text_color(&PQMUI_StyleScreen, lv_color_hex(0xF2F6FA));
    lv_style_set_text_font(&PQMUI_StyleScreen, &lv_font_montserrat_16);

    lv_style_init(&PQMUI_StyleHeader);
    lv_style_set_bg_color(&PQMUI_StyleHeader, lv_color_hex(0x173B63));
    lv_style_set_bg_opa(&PQMUI_StyleHeader, LV_OPA_COVER);
    lv_style_set_border_width(&PQMUI_StyleHeader, 0);
    lv_style_set_radius(&PQMUI_StyleHeader, 0);
    lv_style_set_pad_all(&PQMUI_StyleHeader, 0);

    lv_style_init(&PQMUI_StylePanel);
    lv_style_set_bg_color(&PQMUI_StylePanel, lv_color_hex(0x142235));
    lv_style_set_bg_opa(&PQMUI_StylePanel, LV_OPA_COVER);
    lv_style_set_border_color(&PQMUI_StylePanel, lv_color_hex(0x4F6D8F));
    lv_style_set_border_width(&PQMUI_StylePanel, 1);
    lv_style_set_radius(&PQMUI_StylePanel, 0);
    lv_style_set_pad_all(&PQMUI_StylePanel, 0);

    lv_style_init(&PQMUI_StyleChart);
    lv_style_set_bg_color(&PQMUI_StyleChart, lv_color_hex(0x020406));
    lv_style_set_bg_opa(&PQMUI_StyleChart, LV_OPA_COVER);
    lv_style_set_border_color(&PQMUI_StyleChart, lv_color_hex(0x4F6D8F));
    lv_style_set_border_width(&PQMUI_StyleChart, 1);
    lv_style_set_radius(&PQMUI_StyleChart, 0);
    lv_style_set_line_color(&PQMUI_StyleChart, lv_color_hex(0x243645));
    lv_style_set_line_width(&PQMUI_StyleChart, 1);

    lv_style_init(&PQMUI_StyleButton);
    lv_style_set_bg_color(&PQMUI_StyleButton, lv_color_hex(0x49617E));
    lv_style_set_bg_opa(&PQMUI_StyleButton, LV_OPA_COVER);
    lv_style_set_border_color(&PQMUI_StyleButton, lv_color_hex(0xDEE9F5));
    lv_style_set_border_width(&PQMUI_StyleButton, 1);
    lv_style_set_radius(&PQMUI_StyleButton, 4);
    lv_style_set_pad_all(&PQMUI_StyleButton, 0);
    lv_style_set_text_color(&PQMUI_StyleButton, lv_color_hex(0xF2F6FA));

    lv_style_init(&PQMUI_StyleButtonPressed);
    lv_style_set_bg_color(&PQMUI_StyleButtonPressed, lv_color_hex(0x3D536D));
    lv_style_set_bg_opa(&PQMUI_StyleButtonPressed, LV_OPA_COVER);

    lv_style_init(&PQMUI_StyleTitle);
    lv_style_set_text_color(&PQMUI_StyleTitle, lv_color_hex(0xF2F6FA));
    lv_style_set_text_font(&PQMUI_StyleTitle, &lv_font_montserrat_20);

    lv_style_init(&PQMUI_StyleText);
    lv_style_set_text_color(&PQMUI_StyleText, lv_color_hex(PQMUI_COLOR_STATUS));
    lv_style_set_text_font(&PQMUI_StyleText, &lv_font_montserrat_16);

    lv_style_init(&PQMUI_StyleTextDim);
    lv_style_set_text_color(&PQMUI_StyleTextDim, lv_color_hex(0x95A9BE));
    lv_style_set_text_font(&PQMUI_StyleTextDim, &lv_font_montserrat_14);

    lv_style_init(&PQMUI_StyleAlarm);
    lv_style_set_text_color(&PQMUI_StyleAlarm, lv_color_hex(PQMUI_COLOR_ALARM));
    lv_style_set_text_font(&PQMUI_StyleAlarm, &lv_font_montserrat_16);
}
