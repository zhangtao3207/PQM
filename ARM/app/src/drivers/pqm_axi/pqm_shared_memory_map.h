/*
 * PQM共享内存ABI定义。
 *
 * 这里的字偏移、状态位、能力位和数据结构必须与PL端
 * pqm_shared_memory_bridge保持一致；修改后需要同时更新接口文档和RTL。
 */
#ifndef PQM_SHARED_MEMORY_MAP_H
#define PQM_SHARED_MEMORY_MAP_H

/* 共享内存头部与协议身份标识。 */
#define PQM_SHM_MAGIC_WORD                   0x00000000u
#define PQM_SHM_ABI_WORD                     0x00000001u
#define PQM_SHM_STATUS_WORD                  0x00000002u
#define PQM_SHM_SNAPSHOT_SEQ_WORD            0x00000003u
#define PQM_SHM_HARMONIC_GENERATION_WORD     0x00000004u
#define PQM_SHM_CAPABILITIES_WORD            0x00000005u
#define PQM_SHM_MAGIC                        0x50514D31u
#define PQM_SHM_ABI_VERSION                  0x00010000u
#define PQM_SHM_CAPABILITIES                 0x0000000Fu

/* 状态字：标识标量快照、谐波快照和命令通道是否有效。 */
#define PQM_SHM_STATUS_SNAPSHOT_VALID        0x00000001u
#define PQM_SHM_STATUS_HARMONIC_BANK         0x00000002u
#define PQM_SHM_STATUS_HARMONIC_VALID        0x00000004u

/* 标量测量快照的字偏移。 */
#define PQM_SHM_SCALAR_BASE_WORD             0x00000010u
#define PQM_SHM_SCALAR_U_RMS_WORD            0x00000010u
#define PQM_SHM_SCALAR_I_RMS_WORD            0x00000011u
#define PQM_SHM_SCALAR_U_P2P_WORD            0x00000012u
#define PQM_SHM_SCALAR_I_P2P_WORD            0x00000013u
#define PQM_SHM_SCALAR_FREQUENCY_WORD        0x00000014u
#define PQM_SHM_SCALAR_PHASE_WORD            0x00000015u
#define PQM_SHM_SCALAR_ACTIVE_POWER_WORD     0x00000016u
#define PQM_SHM_SCALAR_REACTIVE_POWER_WORD   0x00000017u
#define PQM_SHM_SCALAR_APPARENT_POWER_WORD   0x00000018u
#define PQM_SHM_SCALAR_POWER_FACTOR_WORD     0x00000019u
#define PQM_SHM_SCALAR_THD_U_WORD            0x0000001Au
#define PQM_SHM_SCALAR_THD_I_WORD            0x0000001Bu
#define PQM_SHM_SCALAR_DC_U_WORD              0x0000001Cu
#define PQM_SHM_SCALAR_DC_I_WORD              0x0000001Du
#define PQM_SHM_SCALAR_ALARM_WORD             0x0000001Eu
#define PQM_SHM_SCALAR_VALIDITY_WORD          0x0000001Fu

/* PS命令与PL响应区域的字偏移。 */
#define PQM_SHM_COMMAND_BASE_WORD            0x00000080u
#define PQM_SHM_COMMAND_REQUEST_WORD         0x00000080u
#define PQM_SHM_COMMAND_ARGUMENT_WORD        0x00000081u
#define PQM_SHM_COMMAND_SEQUENCE_WORD        0x00000082u
#define PQM_SHM_COMMAND_RESPONSE_WORD        0x00000083u
#define PQM_SHM_COMMAND_RESPONSE_SEQ_WORD    0x00000084u

/* 命令码及参数定义。 */
#define PQM_SHM_COMMAND_SET_RANGE            0x00000001u
#define PQM_SHM_RANGE_HIGH                   0x00000000u
#define PQM_SHM_RANGE_LOW                    0x00000001u

/* 运行时统计计数器的字偏移。 */
#define PQM_SHM_COUNTER_BASE_WORD            0x000000A0u
#define PQM_SHM_COUNTER_SAMPLE_DROP_WORD     0x000000A0u

/* 双缓冲谐波窗口；每项依次为电压、电流、相位和标志四个字。 */
#define PQM_SHM_HARMONIC_BANK0_WORD          0x00000400u
#define PQM_SHM_HARMONIC_BANK1_WORD          0x00000C00u
#define PQM_SHM_HARMONIC_ENTRY_WORDS         0x00000004u
#define PQM_SHM_HARMONIC_LAST_INDEX          0x000001F4u

#endif
