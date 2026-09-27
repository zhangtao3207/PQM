/*
 * PQM 界面层内部接口：连接公共样式、时域页与频域页的实现。
 */

#ifndef __PQMUI_INTERNAL_H__
#define __PQMUI_INTERNAL_H__

#include "pqmui.h"

/**********************
 *   GLOBAL VARIABLES
 **********************/

/* 时域页的量程按钮文字标签，量程结果回来时由总控模块更新。 */
extern lv_obj_t *PQMUI_RangeButtonLabel;

/* 量程请求回调，由外部注册。 */
extern pqmui_range_request_fn PQMUI_RangeRequest;

/* 当前量程下 U/I 的满量程（工程量 x100），由数据源在量程变化时下发。 */
extern u32 PQMUI_UMaxX100;
extern u32 PQMUI_IMaxX100;

/**********************
 * GLOBAL PROTOTYPES
 **********************/

/* 样式：初始化页面、面板、图表、按钮与文字样式。 */
void PQMUI_StyleInit(void);

/* 顶部状态文字：按告警位、量程错误与冻结状态刷新。 */
void PQMUI_UpdateStatus(void);

/* 时域页 */
void PQMUI_TimeCreate(void);
void PQMUI_TimeRefreshMeasurement(void);
void PQMUI_TimeRefreshWaveform(const pqmui_wave_column_t *columns);
void PQMUI_TimeRefreshScale(void);

/* 频域页 */
void PQMUI_FreqCreate(void);
void PQMUI_FreqRefreshMeasurement(void);
void PQMUI_FreqRefreshHarmonics(void);

/* 公共控件构造：在 parent 的 (x, y) 处创建 width×height 的按钮，返回按钮并回传文字标签。 */
lv_obj_t *PQMUI_CreateButton(lv_obj_t *parent, lv_coord_t x, lv_coord_t y,
                             lv_coord_t width, lv_coord_t height,
                             const char *text, lv_obj_t **label);

/* 公共控件构造：创建文本标签并定位。dim 为 1 时使用暗色小字样式。 */
lv_obj_t *PQMUI_CreateText(lv_obj_t *parent, lv_coord_t x, lv_coord_t y,
                           const char *text, u8 dim);

#endif /* __PQMUI_INTERNAL_H__ */
