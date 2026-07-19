#ifndef LV_CONF_H
#define LV_CONF_H

#include <stdint.h>

#define LV_COLOR_DEPTH 16
#define LV_COLOR_16_SWAP 0
#define LV_COLOR_SCREEN_TRANSP 0

#define LV_MEM_CUSTOM 0
#define LV_MEM_SIZE (256u * 1024u)
#define LV_MEMCPY_MEMSET_STD 1

#define LV_DISP_DEF_REFR_PERIOD 30
#define LV_INDEV_DEF_READ_PERIOD 20
#define LV_TICK_CUSTOM 0
#define LV_DPI_DEF 120

#ifdef PQM_DEBUG
#define LV_USE_LOG 1
#define LV_LOG_LEVEL LV_LOG_LEVEL_INFO
#else
#define LV_USE_LOG 0
#endif
#define LV_LOG_PRINTF 0

#define LV_USE_ASSERT_NULL 1
#define LV_USE_ASSERT_MALLOC 1
#define LV_USE_ASSERT_STYLE 0
#define LV_USE_ASSERT_MEM_INTEGRITY 0
#define LV_USE_ASSERT_OBJ 0

#define LV_FONT_MONTSERRAT_14 1
#define LV_FONT_MONTSERRAT_16 1
#define LV_FONT_MONTSERRAT_20 1
#define LV_FONT_DEFAULT &lv_font_montserrat_14

#define LV_USE_CHART 1
#define LV_USE_LABEL 1
#define LV_USE_LINE 1
#define LV_USE_TABLE 1
#define LV_USE_TABVIEW 1

#endif
