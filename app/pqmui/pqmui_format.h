/*
 * 工程量格式化接口。
 *
 * 每个字段有固定的取值范围、单位与符号策略；超出范围的输入先按量程限幅，
 * 无效值显示为占位符。该层不访问硬件，也不创建 LVGL 对象。
 */

#ifndef __PQMUI_FORMAT_H__
#define __PQMUI_FORMAT_H__

#include "pqmui.h"

/* 按字段量程对定点值限幅（输入输出都在“显示域”，即已乘过缩放系数）。 */
s32 PQMUI_FieldClampX100(pqmui_field_t field, s32 x100);

/* 把 ABI 真值换算成界面显示值：大量程按模拟市电系数放大，小量程原样返回。
 * 系数按字段查表：有效值/峰峰值 × 27.50，有功/无功/视在 × 756.25，其余 × 1。
 * 定点量是 x100 的 s32，× 756.25 的中间积用 s64 承载并做饱和，不会回绕。 */
s32 PQMUI_ApplySimScale(pqmui_field_t field, s32 x100, u8 low_range);

/* 把定点测量值格式化成显示文本；无效值写成 "--" 加单位。 */
u8 PQMUI_FieldFormat(pqmui_field_t field, const pqmui_value_t *value,
                     char *buffer, u32 size);

#endif /* __PQMUI_FORMAT_H__ */
