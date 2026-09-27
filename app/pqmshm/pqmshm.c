/*
 * PQM 界面层的真实数据源：读 PS/PL 共享内存。
 *
 * 数据通路：
 *   PL（50 MHz，pqm_pl_top）
 *     pqm_measurement_core 每 MEASUREMENT_INTERVAL_CYCLES(16e6) 拍产出一次
 *     标量快照 + 一帧 64 条谐波，经 pqm_shared_memory_bridge 写进
 *     blk_mem_gen_shared 的端口 B；
 *   PS（ARM，本文件）
 *     经 axi_bram_ctrl_0 在 0x40000000 读同一个双口 BRAM 的端口 A 侧镜像。
 *     两侧共用同一块 BRAM，没有第二条数据通路，所以这里读到的就是 PL 实测值。
 *
 * 一致性处理：
 *   1) BRAM 是两端异步访问的，PL 可能在读的过程中改写。ABI 提供两个单调计数器
 *      （快照序号 word0x03、谐波代数 word0x04）与状态字 word0x02；本模块读完
 *      数据后重读计数器，不一致就整轮丢弃重来（最多 3 次）。谐波用双 bank
 *      交替发布，状态字 bit1 指示当前有效 bank，读数期间该位变化同样判为撕裂。
 *   2) BSP 把 0x40000000 段映射成 Strongly Ordered（未开 cache），读写直达 BRAM；
 *      读之前仍显式 invalidate、写命令字后 dsb + flush，作为将来改成 cacheable 的兜底。
 *
 * 界面映射（未改任何界面代码）：
 *   标量快照 -> pqmui_measurement_t（14 个字段，工程量 x100，逐位取 ABI 有效位）
 *   谐波条目 -> pqmui_harmonic_snapshot_t（64 条：U 占比 / I 占比 / 相位 / 标志）
 *   时域波形 -> pqmui_wave_column_t[400]
 *
 * 时域波形的来源必须说清楚（**不是**原始采样）：
 *   ABI 里没有原始采样帧区（PL 不向 PS 发布逐点样本），可用的真实数据只有
 *   标量 RMS/峰峰值与 64 条谐波的"占比 + U-I 相位差"。所以这里做的是一屏
 *   **由实测频谱重建**的波形：
 *     基波峰值（AD 码）= U_RMS(V) * sqrt(2) / 全量程 * 32767
 *     A_k = 基波峰值 * 占比_k / 10000
 *     u(t) = Σ A_k^u * sin(k*theta)                 （U 作为相位参考）
 *     i(t) = Σ A_k^i * sin(k*theta + φ_k)           （φ_k = ABI 里的 U-I 相位差）
 *   全量程随当前量程取值：大量程 U 350.00 V / I 30.00 A，小量程 U 10.00 V / I 3.00 A
 *   （与 pqm_measurement_core.v 的 U/I_FULL_SCALE_*_X100 一致）。ABI 里没有量程字，
 *   所以 PS 侧自己维护「已被 PL 受理的当前量程」，见 PqmshmPollRange。
 *   最后把 AD 码换算成「占本通道满量程的百分比 x100」，两路共用 ±100.00% 的归一化纵轴。
 *   谐波占比是"占本帧该通道总幅值的百分比"，纯正弦下基波占比≈100%，所以
 *   ΣA_k ≈ 基波峰值，幅度尺度与 RMS 读数自洽。
 *   结论：波形幅度/相位来自实测，形状受 64 次谐波带限；它不是原始采样点。
 */

#include "pqmshm.h"

#include "pqmui/pqmui.h"
#include "pqmui/pqmui_format.h"
#include "pqmshm/pqm_shared_memory_map.h"

#include "xtime_l.h"
#include "xil_cache.h"
#include "xpseudo_asm.h"

/* ---------------- 共享内存窗口 ---------------- */
/* 直接按字索引访问 0x40000000：AXI BRAM 控制器给出的是一段线性可寻址窗口。 */
#define PQMSHM_W(word_index) (((volatile u32 *)PQM_SHM_BASE_ADDR)[(word_index)])

/* ---------------- 刷新节奏 ---------------- */
#define PQMSHM_POLL_PERIOD_MS      50u    /* 两次读共享内存之间的最小间隔 */
#define PQMSHM_RANGE_TIMEOUT_MS    2000u  /* 量程命令应答超时 */

/* ---------------- 量程换算常数（与 pqm_measurement_core.v 一致） ----------------
 * PL 内部按 full_scale_low_range_active 在这两组常数之间切换，但**不往共享内存
 * 发布满量程**（ABI 里没有这个字段），所以 PS 侧必须自己维护当前量程，否则小量程下
 * 波形换算会继续用大量程常数，幅度被压到 1/35。
 */
#define PQMSHM_U_FULL_SCALE_HIGH_X100   35000  /* 350.00 V 对应 AD 满量程 */
#define PQMSHM_I_FULL_SCALE_HIGH_X100   3000   /* 30.00 A 对应 AD 满量程 */
#define PQMSHM_U_FULL_SCALE_LOW_X100    1000   /* 10.00 V 对应 AD 满量程 */
#define PQMSHM_I_FULL_SCALE_LOW_X100    300    /* 3.00 A 对应 AD 满量程 */
#define PQMSHM_SQRT2_X1E5               141421 /* sqrt(2) x 1e5 */

/* ---------------- 诊断量 ---------------- */
u32 PQMUI_ShmMagic;
u32 PQMUI_ShmAbiVersion;
u32 PQMUI_ShmStatus;
u32 PQMUI_ShmSnapshotSequence;
u32 PQMUI_ShmHarmonicGeneration;
u32 PQMUI_ShmSampleDropCount;

/* ---------------- 内部状态 ---------------- */
static pqmui_measurement_t ShmMeasurement;
static pqmui_harmonic_snapshot_t ShmHarmonics;
static pqmui_wave_column_t ShmColumns[PQMUI_WAVE_COLUMNS];


static u8  ShmStarted;
static u32 ShmLastSnapshotSeq;
static u32 ShmLastHarmonicGen;
static XTime ShmLastPollTime;

static u8  ShmRangePending;
static u8  ShmRangeRequested;
static u32 ShmRangeSequence;
static XTime ShmRangeStartTime;

/* 已被 PL 受理的当前量程：0 = 大量程，1 = 小量程。PL 复位后是大量程。 */
static u8  ShmLowRange;

/* 当前量程下 U/I 的满量程（工程量 x100）。 */
static u32 PqmshmUFullScaleX100(void)
{
    return ShmLowRange ? (u32)PQMSHM_U_FULL_SCALE_LOW_X100
                       : (u32)PQMSHM_U_FULL_SCALE_HIGH_X100;
}

static u32 PqmshmIFullScaleX100(void)
{
    return ShmLowRange ? (u32)PQMSHM_I_FULL_SCALE_LOW_X100
                       : (u32)PQMSHM_I_FULL_SCALE_HIGH_X100;
}

/* 把满量程下发给界面层：时域页的纵轴双刻度文字要用。 */
static void PqmshmPublishFullScale(void)
{
    PQMUI_SetFullScale(PqmshmUFullScaleX100(), PqmshmIFullScaleX100());
}

/* 标量快照的字段级映射表：pqmui_field_t 顺序 -> ABI word / ABI 有效位。 */
static const u32 ShmFieldWord[PQMUI_FIELD_COUNT] = {
    PQM_SHM_SCALAR_FREQUENCY_WORD,
    PQM_SHM_SCALAR_U1_RMS_WORD,
    PQM_SHM_SCALAR_U2_RMS_WORD,
    PQM_SHM_SCALAR_U1_P2P_WORD,
    PQM_SHM_SCALAR_U2_P2P_WORD,
    PQM_SHM_SCALAR_PHASE_WORD,
    PQM_SHM_SCALAR_ACTIVE_POWER_WORD,
    PQM_SHM_SCALAR_REACTIVE_POWER_WORD,
    PQM_SHM_SCALAR_APPARENT_POWER_WORD,
    PQM_SHM_SCALAR_POWER_FACTOR_WORD,
    PQM_SHM_SCALAR_THD_U1_WORD,
    PQM_SHM_SCALAR_THD_U2_WORD,
    PQM_SHM_SCALAR_DC_U1_WORD,
    PQM_SHM_SCALAR_DC_U2_WORD
};

static const u32 ShmFieldValid[PQMUI_FIELD_COUNT] = {
    PQM_SHM_VALID_FREQUENCY,
    PQM_SHM_VALID_RMS,
    PQM_SHM_VALID_RMS,
    PQM_SHM_VALID_U1_P2P,
    PQM_SHM_VALID_U2_P2P,
    PQM_SHM_VALID_PHASE,
    PQM_SHM_VALID_POWER,
    PQM_SHM_VALID_POWER,
    PQM_SHM_VALID_POWER,
    PQM_SHM_VALID_POWER,
    PQM_SHM_VALID_THD_U1,
    PQM_SHM_VALID_THD_U2,
    PQM_SHM_VALID_DC_U1,
    PQM_SHM_VALID_DC_U2
};

/* 64 点正弦表，幅值 32767，按 1/64 周期取样。重建成波形时做表间线性插值。 */
static const s16 ShmSineTable[64] = {
        0,   3212,   6393,   9512,  12539,  15446,  18204,  20787,
    23170,  25329,  27245,  28898,  30273,  31356,  32137,  32609,
    32767,  32609,  32137,  31356,  30273,  28898,  27245,  25329,
    23170,  20787,  18204,  15446,  12539,   9512,   6393,   3212,
        0,  -3212,  -6393,  -9512, -12539, -15446, -18204, -20787,
   -23170, -25329, -27245, -28898, -30273, -31356, -32137, -32609,
   -32767, -32609, -32137, -31356, -30273, -28898, -27245, -25329,
   -23170, -20787, -18204, -15446, -12539,  -9512,  -6393,  -3212
};

/* XTime 差值换算成毫秒。 */
static u32 PqmshmElapsedMs(XTime now, XTime then)
{
    return (u32)(((now - then) * 1000u) / (u32)COUNTS_PER_SECOND);
}

/* 取 1/256 周期为单位、幅值 32767 的正弦值（表间线性插值）。 */
static s32 PqmshmSine(u32 phase256)
{
    u32 index = (phase256 >> 2) & 63u;
    u32 fraction = phase256 & 3u;
    s32 first = ShmSineTable[index];
    s32 second = ShmSineTable[(index + 1u) & 63u];

    return first + (((second - first) * (s32)fraction) / 4);
}

/* 由 RMS 读数换算出基波峰值（AD 码，满量程 +-32767）。 */
static s32 PqmshmPeakCodes(s32 rms_x100, s32 full_scale_x100)
{
    s64 numerator;
    s64 denominator;

    if (rms_x100 < 0) {
        rms_x100 = -rms_x100;
    }
    if (full_scale_x100 <= 0) {
        return 0;
    }
    numerator = (s64)rms_x100 * (s64)PQMSHM_SQRT2_X1E5 * 32767LL;
    denominator = (s64)full_scale_x100 * 100000LL;

    return (s32)(numerator / denominator);
}

/* 只读一次共享内存窗口的头部：返回 0 表示接口不正常（magic/abi 不符）。 */
static u32 PqmshmReadHeader(void)
{
    Xil_DCacheInvalidateRange((INTPTR)PQM_SHM_BASE_ADDR,
                              (u32)PQM_SHM_TOTAL_BYTES);

    PQMUI_ShmMagic = PQMSHM_W(PQM_SHM_MAGIC_WORD);
    PQMUI_ShmAbiVersion = PQMSHM_W(PQM_SHM_ABI_WORD);
    PQMUI_ShmStatus = PQMSHM_W(PQM_SHM_STATUS_WORD);
    PQMUI_ShmSnapshotSequence = PQMSHM_W(PQM_SHM_SNAPSHOT_SEQ_WORD);
    PQMUI_ShmHarmonicGeneration = PQMSHM_W(PQM_SHM_HARMONIC_GEN_WORD);
    PQMUI_ShmSampleDropCount = PQMSHM_W(PQM_SHM_COUNTER_SAMPLE_DROP_WORD);

    if (PQMUI_ShmMagic != PQM_SHM_MAGIC) {
        return 0u;
    }
    if ((PQMUI_ShmAbiVersion & 0xFFFF0000u) !=
        (PQM_SHM_ABI_VERSION & 0xFFFF0000u)) {
        return 0u;
    }
    return 1u;
}

/* 读一次标量快照。返回 1 表示本轮数据未被 PL 改写、可以采信。 */
static u32 PqmshmReadMeasurement(void)
{
    u32 validity;
    u32 index;

    validity = PQMSHM_W(PQM_SHM_SCALAR_VALIDITY_WORD);
    for (index = 0u; index < (u32)PQMUI_FIELD_COUNT; ++index) {
        s32 raw = (s32)PQMSHM_W(ShmFieldWord[index]);

        ShmMeasurement.value[index].x100 =
            PQMUI_FieldClampX100((pqmui_field_t)index, raw);
        ShmMeasurement.value[index].valid =
            ((validity & ShmFieldValid[index]) != 0u) ? 1u : 0u;
    }
    ShmMeasurement.sequence = PQMUI_ShmSnapshotSequence;
    ShmMeasurement.alarm =
        (PQMSHM_W(PQM_SHM_SCALAR_ALARM_WORD) & 0x1u);

    /* 撕裂检查：读完数据后序号必须没变。 */
    Xil_DCacheInvalidateRange((INTPTR)PQM_SHM_BASE_ADDR,
                              (u32)PQM_SHM_TOTAL_BYTES);
    return (PQMSHM_W(PQM_SHM_SNAPSHOT_SEQ_WORD) == PQMUI_ShmSnapshotSequence)
               ? 1u : 0u;
}

/* 读一整帧谐波（当前有效 bank）。返回 1 表示本轮未被 PL 改写。 */
static u32 PqmshmReadHarmonics(void)
{
    u32 bank = (PQMUI_ShmStatus & PQM_SHM_STATUS_HARMONIC_BANK) ? 1u : 0u;
    u32 base = bank ? PQM_SHM_HARMONIC_BANK1_WORD : PQM_SHM_HARMONIC_BANK0_WORD;
    u32 index;

    for (index = 0u; index < (u32)PQMUI_HARMONIC_ENTRIES; ++index) {
        u32 entry = base + (index * PQM_SHM_HARMONIC_ENTRY_WORDS);
        s32 phase = (s32)PQMSHM_W(entry + 2u);

        ShmHarmonics.entries[index].u_ratio_x100 =
            (u16)(PQMSHM_W(entry + 0u) & 0xFFFFu);
        ShmHarmonics.entries[index].i_ratio_x100 =
            (u16)(PQMSHM_W(entry + 1u) & 0xFFFFu);
        if (phase > 32767) {
            phase = 32767;
        } else if (phase < -32768) {
            phase = -32768;
        }
        ShmHarmonics.entries[index].phase_x100 = (s16)phase;
        ShmHarmonics.entries[index].flags =
            (u8)(PQMSHM_W(entry + 3u) & 0xFFu);
    }
    ShmHarmonics.generation = PQMUI_ShmHarmonicGeneration;

    /* 撕裂检查：代数与当前 bank 位都必须没变。 */
    Xil_DCacheInvalidateRange((INTPTR)PQM_SHM_BASE_ADDR,
                              (u32)PQM_SHM_TOTAL_BYTES);
    if (PQMSHM_W(PQM_SHM_HARMONIC_GEN_WORD) != PQMUI_ShmHarmonicGeneration) {
        return 0u;
    }
    if (((PQMSHM_W(PQM_SHM_STATUS_WORD) & PQM_SHM_STATUS_HARMONIC_BANK) ? 1u : 0u)
        != bank) {
        return 0u;
    }
    return 1u;
}

/*
 * 用实测频谱重建一屏时域波形（400 列，覆盖一个基波周期），
 * 并按「占本通道满量程的百分比」归一化，两路共用 ±100.00% 的纵轴。
 *
 *   theta = 2*pi*column/400
 *   u(t)  = Sigma A_k^u * sin(k*theta)            （U 作相位参考）
 *   i(t)  = Sigma A_k^i * sin(k*theta + phi_k)    （phi_k = ABI 里的 U-I 相位差）
 *
 * 关键：phi_k 只加到电流的自变量上。原先 u/i 共用同一个 sine，等于把同一个相位
 * 偏移同时加到两路上，图上自然看不出 30 度相差（实测两条线峰谷同 x）。
 *
 * A_k 由 RMS 读数换算：基波峰值（AD 码）= U_RMS * sqrt(2) / 满量程 * 32767；
 * 满量程随量程切换，与 PL 的 time_x100_normalizer 用同一组常数。
 */
static void PqmshmRebuildWaveform(void)
{
    s32 u_peak = PqmshmPeakCodes(ShmMeasurement.value[PQMUI_FIELD_U_RMS].x100,
                                 (s32)PqmshmUFullScaleX100());
    s32 i_peak = PqmshmPeakCodes(ShmMeasurement.value[PQMUI_FIELD_I_RMS].x100,
                                 (s32)PqmshmIFullScaleX100());
    u32 column;

    for (column = 0u; column < (u32)PQMUI_WAVE_COLUMNS; ++column) {
        s32 u = 0;
        s32 i = 0;
        u32 order;

        for (order = 1u; order < (u32)PQMUI_HARMONIC_ENTRIES; ++order) {
            const pqmui_harmonic_t *entry = &ShmHarmonics.entries[order];
            s32 base_phase;
            s32 phase_offset;
            s32 sine_u;
            s32 sine_i;
            s32 au;
            s32 ai;

            if ((entry->flags & PQMUI_HARMONIC_FLAG_RATIO) == 0u) {
                continue;
            }

            /* 相位以 1/256 周期为单位：k*theta，加上 ABI 的 phi_k（x100 度）。 */
            base_phase = (s32)((column * 256u * order) /
                               (u32)PQMUI_WAVE_COLUMNS);
            phase_offset = ((entry->flags & PQMUI_HARMONIC_FLAG_PHASE) != 0u)
                               ? (s32)(((s32)entry->phase_x100 * 256) / 36000)
                               : 0;

            sine_u = PqmshmSine((u32)base_phase & 255u);
            sine_i = PqmshmSine((u32)(base_phase + phase_offset) & 255u);

            au = (s32)(((s64)u_peak * (s32)entry->u_ratio_x100) / 10000);
            ai = (s32)(((s64)i_peak * (s32)entry->i_ratio_x100) / 10000);

            u += (s32)(((s64)au * (s64)sine_u) / 32767);
            i += (s32)(((s64)ai * (s64)sine_i) / 32767);
        }

        /* AD 码 -> 占本通道满量程的百分比 x100（32767 码 = 100.00%）。 */
        if (u > 32767) {
            u = 32767;
        } else if (u < -32767) {
            u = -32767;
        }
        if (i > 32767) {
            i = 32767;
        } else if (i < -32767) {
            i = -32767;
        }
        u = (s32)(((s64)u * (s64)PQMUI_WAVE_SCALE_X100) / 32767);
        i = (s32)(((s64)i * (s64)PQMUI_WAVE_SCALE_X100) / 32767);

        ShmColumns[column].u_min = (s16)u;
        ShmColumns[column].u_max = (s16)u;
        ShmColumns[column].i_min = (s16)i;
        ShmColumns[column].i_max = (s16)i;
    }
}

/*
 * 量程请求回调：把命令写进 PS 命令区，等 PL 把响应序号写回来。
 * 协议见 pl/rtl/PSInterface/pqm_shm_command_capture.v：PS 依次写
 * REQUEST / ARGUMENT / SEQUENCE，序号非 0 且与上次不同；PL 两遍读一致后受理，
 * 受理结果由 pqm_range_command_controller 产生、桥写进 RESPONSE / RESPONSE_SEQ。
 */
static u8 PqmshmRangeRequest(u8 low_range)
{
    if (ShmRangePending) {
        return 0u;
    }
    ShmRangeSequence += 1u;
    if (ShmRangeSequence == 0u) {
        ShmRangeSequence = 1u;
    }
    PQMSHM_W(PQM_SHM_COMMAND_REQUEST_WORD) = PQM_SHM_COMMAND_SET_RANGE;
    PQMSHM_W(PQM_SHM_COMMAND_ARGUMENT_WORD) =
        low_range ? PQM_SHM_RANGE_LOW : PQM_SHM_RANGE_HIGH;
    PQMSHM_W(PQM_SHM_COMMAND_SEQUENCE_WORD) = ShmRangeSequence;

    /* 写完命令字后必须保证三个字真的落到内存再"响门铃"：写入顺序固定为
     * REQUEST -> ARGUMENT -> SEQUENCE（序号最后写），PL 才能读到自洽的三元组。
     * （当前 BSP 把 0x40000000 段映射成 Strongly Ordered、未开 cache，这两步属于
     *  冗余兜底；一旦该窗口改成 cacheable，这里就是必需的。） */
    dsb();
    Xil_DCacheFlushRange(
        (INTPTR)(PQM_SHM_BASE_ADDR + (PQM_SHM_COMMAND_REQUEST_WORD * 4u)),
        (u32)(3u * sizeof(u32)));
    dsb();

    ShmRangeRequested = low_range;
    ShmRangePending = 1u;
    XTime_GetTime(&ShmRangeStartTime);

    return 1u;
}

/* 轮询量程命令的应答。 */
static void PqmshmPollRange(void)
{
    XTime now;

    if (!ShmRangePending) {
        return;
    }
    XTime_GetTime(&now);
    Xil_DCacheInvalidateRange((INTPTR)PQM_SHM_BASE_ADDR,
                              (u32)PQM_SHM_TOTAL_BYTES);

    if (PQMSHM_W(PQM_SHM_COMMAND_RESPONSE_SEQ_WORD) == ShmRangeSequence) {
        u32 response = PQMSHM_W(PQM_SHM_COMMAND_RESPONSE_WORD);

        ShmRangePending = 0u;
        if (response == PQM_SHM_RESPONSE_ERROR) {
            PQMUI_SetRangeResult(0u, ShmRangeRequested);
        } else {
            /* 响应回显的就是 PL 实际生效的量程，以它为准更新满量程。 */
            ShmLowRange = (u8)(response & 0x1u);
            PQMUI_SetRangeResult(1u, ShmRangeRequested);
            PqmshmPublishFullScale();
        }
    } else if (PqmshmElapsedMs(now, ShmRangeStartTime) >=
               PQMSHM_RANGE_TIMEOUT_MS) {
        ShmRangePending = 0u;
        PQMUI_SetRangeResult(0u, ShmRangeRequested);
    }
}

void PQMUI_ShmPoll(void)
{
    XTime now;
    u32 attempt;

    if (!ShmStarted) {
        ShmStarted = 1u;
        ShmLowRange = 0u;              /* PL 复位后是大量程 */
        PqmshmPublishFullScale();
        ShmMeasurement.sequence = 0u;
        ShmMeasurement.alarm = 0u;
        ShmHarmonics.generation = 0u;
        ShmLastSnapshotSeq = 0u;
        ShmLastHarmonicGen = 0u;
        PQMUI_SetRangeRequest(PqmshmRangeRequest);
        XTime_GetTime(&ShmLastPollTime);
    }

    PqmshmPollRange();

    XTime_GetTime(&now);
    if (PqmshmElapsedMs(now, ShmLastPollTime) < PQMSHM_POLL_PERIOD_MS) {
        return;
    }
    ShmLastPollTime = now;

    if (!PqmshmReadHeader()) {
        return;   /* magic/ABI 不符：PL 还没起来或比特流不对 */
    }

    /* 标量快照：序号变了才读，读数期间变化就重来。 */
    if ((PQMUI_ShmStatus & PQM_SHM_STATUS_SNAPSHOT_VALID) != 0u &&
        PQMUI_ShmSnapshotSequence != ShmLastSnapshotSeq) {
        for (attempt = 0u; attempt < 3u; ++attempt) {
            if (PqmshmReadMeasurement()) {
                ShmLastSnapshotSeq = PQMUI_ShmSnapshotSequence;
                PQMUI_UpdateMeasurement(&ShmMeasurement);
                break;
            }
            (void)PqmshmReadHeader();
        }
    }

    /* 谐波：代数变了才读，读出后重建波形。 */
    if ((PQMUI_ShmStatus & PQM_SHM_STATUS_HARMONIC_VALID) != 0u &&
        PQMUI_ShmHarmonicGeneration != ShmLastHarmonicGen) {
        for (attempt = 0u; attempt < 3u; ++attempt) {
            if (PqmshmReadHarmonics()) {
                ShmLastHarmonicGen = PQMUI_ShmHarmonicGeneration;
                PQMUI_UpdateHarmonics(&ShmHarmonics);
                PqmshmRebuildWaveform();
                PQMUI_UpdateWaveform(ShmColumns);
                break;
            }
            (void)PqmshmReadHeader();
        }
    }
}
