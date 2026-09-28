/*
 * PS/PL 共享内存 ABI 的 C 版定义。
 *
 * 这是 pl/rtl/PSInterface/pqm_shared_memory_map.vh 的 C 复刻，**唯一目的**是让
 * 应用侧不必把 Verilog 宏文件塞进 C 编译器。两边的取值必须逐条保持一致：
 * 任何一边改了字偏移或字宽，都要同步改另一边。
 *
 * 内存布局（基址 0x40000000，16384 字 x 32 位）：
 *   word 0x00  MAGIC          0x50514D31 ("PQM1")
 *   word 0x01  ABI 版本       0x00010000
 *   word 0x02  状态字          bit0 快照有效 / bit1 当前谐波 bank / bit2 谐波有效
 *   word 0x03  快照序号
 *   word 0x04  谐波代数
 *   word 0x05  能力位
 *   word 0x10..0x1D  标量快照（工程量 x100）
 *   word 0x1E  告警字（bit0 = alarm_active）
 *   word 0x1F  逐字段有效位
 *   word 0x80..0x84  PS 命令区 / PL 响应区
 *   word 0xA0  运行计数器（丢样本数）
 *   word 0x400 起 64 条谐波 bank0（每条 4 字：U 占比 / I 占比 / 相位 / 标志）
 *   word 0xC00 起 64 条谐波 bank1（同上，双 bank 交替发布）
 */
#ifndef __PQM_SHARED_MEMORY_MAP_H__
#define __PQM_SHARED_MEMORY_MAP_H__

/* 共享内存基址与容量 */
#define PQM_SHM_BASE_ADDR          0x40000000u
#define PQM_SHM_TOTAL_WORDS        16384u
#define PQM_SHM_TOTAL_BYTES        (PQM_SHM_TOTAL_WORDS * 4u)

/* 头部 */
#define PQM_SHM_MAGIC_WORD         0x00000000u
#define PQM_SHM_ABI_WORD           0x00000001u
#define PQM_SHM_STATUS_WORD        0x00000002u
#define PQM_SHM_SNAPSHOT_SEQ_WORD  0x00000003u
#define PQM_SHM_HARMONIC_GEN_WORD  0x00000004u
#define PQM_SHM_CAPABILITIES_WORD  0x00000005u

#define PQM_SHM_MAGIC              0x50514D31u
#define PQM_SHM_ABI_VERSION        0x00010000u
#define PQM_SHM_CAPABILITIES       0x0000000Fu

/* 状态字位 */
#define PQM_SHM_STATUS_SNAPSHOT_VALID   0x00000001u
#define PQM_SHM_STATUS_HARMONIC_BANK    0x00000002u
#define PQM_SHM_STATUS_HARMONIC_VALID   0x00000004u

/* 标量快照（word 0x10 起 16 个字，全部为工程量 x100 的 32 位有符号数） */
#define PQM_SHM_SCALAR_BASE_WORD        0x00000010u
#define PQM_SHM_SCALAR_U1_RMS_WORD      0x00000010u
#define PQM_SHM_SCALAR_U2_RMS_WORD      0x00000011u
#define PQM_SHM_SCALAR_U1_P2P_WORD      0x00000012u
#define PQM_SHM_SCALAR_U2_P2P_WORD      0x00000013u
#define PQM_SHM_SCALAR_FREQUENCY_WORD   0x00000014u
#define PQM_SHM_SCALAR_PHASE_WORD       0x00000015u
#define PQM_SHM_SCALAR_ACTIVE_POWER_WORD    0x00000016u
#define PQM_SHM_SCALAR_REACTIVE_POWER_WORD  0x00000017u
#define PQM_SHM_SCALAR_APPARENT_POWER_WORD  0x00000018u
#define PQM_SHM_SCALAR_POWER_FACTOR_WORD    0x00000019u
#define PQM_SHM_SCALAR_THD_U1_WORD      0x0000001Au
#define PQM_SHM_SCALAR_THD_U2_WORD      0x0000001Bu
#define PQM_SHM_SCALAR_DC_U1_WORD       0x0000001Cu
#define PQM_SHM_SCALAR_DC_U2_WORD       0x0000001Du
#define PQM_SHM_SCALAR_ALARM_WORD       0x0000001Eu
#define PQM_SHM_SCALAR_VALIDITY_WORD    0x0000001Fu

/* 快照有效位：与 pqm_measurement_core.v 里 ps_snapshot_words 最高字的拼接顺序一一对应 */
#define PQM_SHM_VALID_RMS          0x00000001u   /* bit0/bit1：U1/U2 RMS */
#define PQM_SHM_VALID_U1_P2P       0x00000004u
#define PQM_SHM_VALID_U2_P2P       0x00000008u
#define PQM_SHM_VALID_PHASE        0x00000010u
#define PQM_SHM_VALID_FREQUENCY    0x00000020u
#define PQM_SHM_VALID_POWER        0x00000040u   /* 有功/无功/视在/功率因数 */
#define PQM_SHM_VALID_THD_U1       0x00000080u
#define PQM_SHM_VALID_THD_U2       0x00000100u
#define PQM_SHM_VALID_DC_U1        0x00000200u
#define PQM_SHM_VALID_DC_U2        0x00000400u

/* 缺陷 3：饱和/溢出可见位（validity 字 bit15..12，粘滞位）。
 * 与 pl/rtl/PSInterface/pqm_shared_memory_map.vh 保持一致；ABI 偏移未变。
 * 这三位置 1 表示“去零点发生饱和 / RFG 溢出 / 取样 FIFO 溢出”，
 * 此时频域那几项（THD、DC）不可信，PS 侧把它们按无效处理（界面显示 --）。 */
#define PQM_SHM_VALIDITY_CENTER_SAT     0x00001000u
#define PQM_SHM_VALIDITY_RFG_OVERFLOW   0x00002000u
#define PQM_SHM_VALIDITY_FIFO_OVERFLOW  0x00004000u
#define PQM_SHM_VALIDITY_TRUST_MASK     (PQM_SHM_VALIDITY_CENTER_SAT | \
                                         PQM_SHM_VALIDITY_RFG_OVERFLOW | \
                                         PQM_SHM_VALIDITY_FIFO_OVERFLOW)
/* PS 命令区与 PL 响应区 */
#define PQM_SHM_COMMAND_BASE_WORD           0x00000080u
#define PQM_SHM_COMMAND_REQUEST_WORD        0x00000080u
#define PQM_SHM_COMMAND_ARGUMENT_WORD       0x00000081u
#define PQM_SHM_COMMAND_SEQUENCE_WORD       0x00000082u
#define PQM_SHM_COMMAND_RESPONSE_WORD       0x00000083u
#define PQM_SHM_COMMAND_RESPONSE_SEQ_WORD   0x00000084u

/* 命令码与参数（与 pqm_range_command_controller.v 一致） */
#define PQM_SHM_COMMAND_SET_RANGE   0x00000001u
#define PQM_SHM_RANGE_HIGH          0x00000000u
#define PQM_SHM_RANGE_LOW           0x00000001u
#define PQM_SHM_RESPONSE_ERROR      0xFFFFFFFFu

/* 运行计数器 */
#define PQM_SHM_COUNTER_BASE_WORD           0x000000A0u
#define PQM_SHM_COUNTER_SAMPLE_DROP_WORD    0x000000A0u

/* 双 bank 谐波窗口：每条 4 个字（U 占比 / I 占比 / 相位 / 标志） */
#define PQM_SHM_HARMONIC_BANK0_WORD     0x00000400u
#define PQM_SHM_HARMONIC_BANK1_WORD     0x00000C00u
#define PQM_SHM_HARMONIC_ENTRY_WORDS    0x00000004u
#define PQM_SHM_HARMONIC_LAST_INDEX     0x0000003Fu   /* 共 64 条：0..63 */

/* 谐波条目标志位（与 pqm_measurement_core.v 的 ps_harmonic_flags 一致） */
#define PQM_SHM_HARMONIC_FLAG_RATIO     0x00000001u
#define PQM_SHM_HARMONIC_FLAG_PHASE     0x00000002u

#endif /* __PQM_SHARED_MEMORY_MAP_H__ */
