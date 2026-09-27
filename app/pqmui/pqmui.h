/*
 * PQM 界面层对外接口。
 *
 * 页面尺寸、元素坐标、配色与交互行为按旧工程 PQM 的界面规格复现；
 * 代码组织与命名按本工程（官方例程）的风格重写。
 */

#ifndef __PQMUI_H__
#define __PQMUI_H__

#include "xil_types.h"
#include "lvgl.h"

/*********************
 *      DEFINES
 *********************/

/* 时域波形列数，对应图表横轴点数 */
#define PQMUI_WAVE_COLUMNS      400

/* 谐波表规模与频域页窗口：ABI 共 64 条（H0..H63），UI 分 4 页、每页 16 条。
 * 第 1 页 = H0-H15，之后 H16-H31 / H32-H47 / H48-H63。
 * 窗口起点就是本页首条：本页绘制 H(起点) .. H(起点+STEP-1)，4 页无重复、无空洞。 */
#define PQMUI_HARMONIC_ENTRIES  64
#define PQMUI_HARMONIC_POINTS   16
#define PQMUI_HARMONIC_STEP     16
#define PQMUI_HARMONIC_MAX_START 48

/* 时域图表纵轴满刻度：波形按“占本通道满量程的百分比”绘制。
 * 电压与电流共用同一条归一化纵轴（±100.00%，10000 = 100%），
 * 两路各自的满量程由纵轴两侧的静态刻度文字分别标注：左电压、右电流。 */
#define PQMUI_WAVE_SCALE_X100   10000

/* 谐波条目标志位 */
#define PQMUI_HARMONIC_FLAG_RATIO 0x01u
#define PQMUI_HARMONIC_FLAG_PHASE 0x02u

/**********************
 *      TYPEDEFS
 **********************/

/* 标量测量字段。前十项是时域页的参数行顺序，后四项供频域页使用。 */
typedef enum {
    PQMUI_FIELD_FREQUENCY = 0,
    PQMUI_FIELD_U_RMS,
    PQMUI_FIELD_I_RMS,
    PQMUI_FIELD_U_P2P,
    PQMUI_FIELD_I_P2P,
    PQMUI_FIELD_PHASE,
    PQMUI_FIELD_ACTIVE_POWER,
    PQMUI_FIELD_REACTIVE_POWER,
    PQMUI_FIELD_APPARENT_POWER,
    PQMUI_FIELD_POWER_FACTOR,
    PQMUI_FIELD_THD_U,
    PQMUI_FIELD_THD_I,
    PQMUI_FIELD_DC_U,
    PQMUI_FIELD_DC_I,
    PQMUI_FIELD_COUNT
} pqmui_field_t;

/* 工程量的定点表示：数值为工程量乘以 100。 */
typedef struct {
    s32 x100;
    u8 valid;
} pqmui_value_t;

typedef struct {
    u32 sequence;
    u32 alarm;
    pqmui_value_t value[PQMUI_FIELD_COUNT];
} pqmui_measurement_t;

/* 一列波形的电压/电流极值，由采样帧按列压缩得到。 */
typedef struct {
    s16 u_min;
    s16 u_max;
    s16 i_min;
    s16 i_max;
} pqmui_wave_column_t;

/* 单个谐波：占比与相位均为乘以 100 的定点值。 */
typedef struct {
    u16 u_ratio_x100;
    u16 i_ratio_x100;
    s16 phase_x100;
    u8 flags;
} pqmui_harmonic_t;

typedef struct {
    u32 generation;
    pqmui_harmonic_t entries[PQMUI_HARMONIC_ENTRIES];
} pqmui_harmonic_snapshot_t;

/* 量程切换请求回调：返回 1 表示已受理，结果稍后由 PQMUI_SetRangeResult 通知。 */
typedef u8 (*pqmui_range_request_fn)(u8 low_range);

/**********************
 *   GLOBAL VARIABLES
 **********************/

/* 页面对象与共享状态。同官方例程的做法，用文件级全局量而不是上下文结构体。 */
extern lv_obj_t *PQMUI_TimePage;
extern lv_obj_t *PQMUI_FrequencyPage;
extern lv_obj_t *PQMUI_TitleLabel;
extern lv_obj_t *PQMUI_StatusLabel;
extern lv_obj_t *PQMUI_PageButtonLabel;
extern lv_obj_t *PQMUI_FreezeButtonLabel;

extern u8 PQMUI_FrequencyActive;
extern u8 PQMUI_Frozen;
extern u8 PQMUI_LowRange;
extern u8 PQMUI_RangePending;
extern u8 PQMUI_RangeError;
extern u8 PQMUI_MeasurementAvailable;
extern u8 PQMUI_HarmonicsAvailable;

extern pqmui_measurement_t PQMUI_LatestMeasurement;
extern pqmui_harmonic_snapshot_t PQMUI_LatestHarmonics;
extern u16 PQMUI_HarmonicWindowStart;

/**********************
 * GLOBAL PROTOTYPES
 **********************/

/* 创建整棵界面：页头、公共按钮、时域页与频域页。 */
void PQMUI_Init(void);
/* 注册量程请求回调。 */
void PQMUI_SetRangeRequest(pqmui_range_request_fn request);
/* 接收量程命令结果并更新按钮文字或错误状态。 */
void PQMUI_SetRangeResult(u8 success, u8 low_range);
/* 下发当前量程下 U/I 的满量程（工程量 x100），时域页据此刷新纵轴刻度。 */
void PQMUI_SetFullScale(u32 u_full_scale_x100, u32 i_full_scale_x100);
/* 更新最新测量值，未冻结时刷新当前页面。 */
void PQMUI_UpdateMeasurement(const pqmui_measurement_t *measurement);
/* 更新时域波形包络。 */
void PQMUI_UpdateWaveform(const pqmui_wave_column_t *columns);
/* 更新谐波快照。 */
void PQMUI_UpdateHarmonics(const pqmui_harmonic_snapshot_t *harmonics);

#endif /* __PQMUI_H__ */
