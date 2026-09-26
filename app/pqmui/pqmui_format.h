/*
 * 工程量格式化接口。
 *
 * 每个字段有固定的取值范围、单位与符号策略；超出范围的输入先按量程限幅，
 * 无效值显示为占位符。该层不访问硬件，也不创建 LVGL 对象。
 */

#ifndef __PQMUI_FORMAT_H__
#define __PQMUI_FORMAT_H__

#include "pqmui.h"

/* 按字段量程对定点值限幅。 */
s32 PQMUI_FieldClampX100(pqmui_field_t field, s32 x100);

/* 把定点测量值格式化成显示文本；无效值写成 "--" 加单位。 */
u8 PQMUI_FieldFormat(pqmui_field_t field, const pqmui_value_t *value,
                     char *buffer, u32 size);

#endif /* __PQMUI_FORMAT_H__ */
