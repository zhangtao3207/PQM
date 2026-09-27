/*
 * PQM 界面层的真实数据源：从 PS/PL 共享内存读测量结果。
 *
 * 共享内存由 PL 的 pqm_measurement_core + pqm_shared_memory_bridge 周期发布，
 * PS 侧经 axi_bram_ctrl_0 映射在 0x40000000（64K）。本模块只读那个窗口，
 * 把 ABI 里的标量快照与谐波条目翻译成 pqmui 层的结构体，再驱动界面刷新。
 *
 * 与阶段 1 的假数据源（app/demo/pqmui_demo.c）接口等价：main 循环里一次
 * PQMUI_ShmPoll() 即可，界面层代码零改动。
 */
#ifndef __PQMSHM_H__
#define __PQMSHM_H__

#include "xil_types.h"

/* 在 LVGL 主循环里周期调用：读共享内存并刷新界面（分频见实现）。 */
void PQMUI_ShmPoll(void);

/* 诊断用：最近一次读到的共享内存头部字段，未读到时为 0。 */
extern u32 PQMUI_ShmMagic;
extern u32 PQMUI_ShmAbiVersion;
extern u32 PQMUI_ShmStatus;
extern u32 PQMUI_ShmSnapshotSequence;
extern u32 PQMUI_ShmHarmonicGeneration;
extern u32 PQMUI_ShmSampleDropCount;

#endif /* __PQMSHM_H__ */
