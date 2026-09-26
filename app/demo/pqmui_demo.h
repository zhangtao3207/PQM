/*
 * 阶段 1 内置假数据源接口。阶段 3 接入真实测量数据后删除本模块。
 */

#ifndef __PQMUI_DEMO_H__
#define __PQMUI_DEMO_H__

#include "xil_types.h"

/* 在主循环里调用；内部按各自周期限流。首次调用完成回调注册。 */
void PQMUI_DemoPoll(void);

#endif /* __PQMUI_DEMO_H__ */
