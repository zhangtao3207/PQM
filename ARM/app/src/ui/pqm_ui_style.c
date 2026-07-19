#include "pqm_ui_internal.h"

void pqm_ui_style_initialize(pqm_ui_styles_t *styles)
{
    lv_style_init(&styles->screen);
    lv_style_set_bg_color(&styles->screen, lv_color_hex(0x0B1524));
    lv_style_set_bg_opa(&styles->screen, LV_OPA_COVER);
    lv_style_set_text_color(&styles->screen, lv_color_hex(0xF2F6FA));
    lv_style_set_text_font(&styles->screen, &lv_font_montserrat_16);

    lv_style_init(&styles->header);
    lv_style_set_bg_color(&styles->header, lv_color_hex(0x173B63));
    lv_style_set_bg_opa(&styles->header, LV_OPA_COVER);
    lv_style_set_border_width(&styles->header, 0);
    lv_style_set_radius(&styles->header, 0);
    lv_style_set_pad_all(&styles->header, 0);

    lv_style_init(&styles->panel);
    lv_style_set_bg_color(&styles->panel, lv_color_hex(0x142235));
    lv_style_set_bg_opa(&styles->panel, LV_OPA_COVER);
    lv_style_set_border_color(&styles->panel, lv_color_hex(0x4F6D8F));
    lv_style_set_border_width(&styles->panel, 1);
    lv_style_set_radius(&styles->panel, 0);
    lv_style_set_pad_all(&styles->panel, 0);

    lv_style_init(&styles->chart);
    lv_style_set_bg_color(&styles->chart, lv_color_hex(0x020406));
    lv_style_set_bg_opa(&styles->chart, LV_OPA_COVER);
    lv_style_set_border_color(&styles->chart, lv_color_hex(0x4F6D8F));
    lv_style_set_border_width(&styles->chart, 1);
    lv_style_set_radius(&styles->chart, 0);
    lv_style_set_line_color(&styles->chart, lv_color_hex(0x243645));
    lv_style_set_line_width(&styles->chart, 1);

    lv_style_init(&styles->button);
    lv_style_set_bg_color(&styles->button, lv_color_hex(0x49617E));
    lv_style_set_bg_opa(&styles->button, LV_OPA_COVER);
    lv_style_set_border_color(&styles->button, lv_color_hex(0xDEE9F5));
    lv_style_set_border_width(&styles->button, 1);
    lv_style_set_radius(&styles->button, 4);
    lv_style_set_pad_all(&styles->button, 0);
    lv_style_set_text_color(&styles->button, lv_color_hex(0xF2F6FA));

    lv_style_init(&styles->button_pressed);
    lv_style_set_bg_color(&styles->button_pressed, lv_color_hex(0x3D536D));
    lv_style_set_bg_opa(&styles->button_pressed, LV_OPA_COVER);

    lv_style_init(&styles->title);
    lv_style_set_text_color(&styles->title, lv_color_hex(0xF2F6FA));
    lv_style_set_text_font(&styles->title, &lv_font_montserrat_20);

    lv_style_init(&styles->text);
    lv_style_set_text_color(&styles->text, lv_color_hex(0xC6D3E2));
    lv_style_set_text_font(&styles->text, &lv_font_montserrat_16);

    lv_style_init(&styles->text_dim);
    lv_style_set_text_color(&styles->text_dim, lv_color_hex(0x95A9BE));
    lv_style_set_text_font(&styles->text_dim, &lv_font_montserrat_14);

    lv_style_init(&styles->alarm);
    lv_style_set_text_color(&styles->alarm, lv_color_hex(0xFF5A5F));
    lv_style_set_text_font(&styles->alarm, &lv_font_montserrat_16);
}
