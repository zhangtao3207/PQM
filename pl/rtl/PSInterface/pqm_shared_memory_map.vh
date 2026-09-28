`ifndef PQM_SHARED_MEMORY_MAP_VH
`define PQM_SHARED_MEMORY_MAP_VH

// 共享内存头部和协议标识。
`define PQM_SHM_MAGIC_WORD                   32'h00000000
`define PQM_SHM_ABI_WORD                     32'h00000001
`define PQM_SHM_STATUS_WORD                  32'h00000002
`define PQM_SHM_SNAPSHOT_SEQ_WORD            32'h00000003
`define PQM_SHM_HARMONIC_GENERATION_WORD     32'h00000004
`define PQM_SHM_CAPABILITIES_WORD            32'h00000005
`define PQM_SHM_MAGIC                        32'h50514D31
`define PQM_SHM_ABI_VERSION                  32'h00010000
`define PQM_SHM_CAPABILITIES                 32'h0000000F

// 状态字位定义。
`define PQM_SHM_STATUS_SNAPSHOT_VALID        32'h00000001
`define PQM_SHM_STATUS_HARMONIC_BANK         32'h00000002
`define PQM_SHM_STATUS_HARMONIC_VALID        32'h00000004

// 标量快照固定 word 偏移。
`define PQM_SHM_SCALAR_BASE_WORD             32'h00000010
`define PQM_SHM_SCALAR_U1_RMS_WORD            32'h00000010
`define PQM_SHM_SCALAR_U2_RMS_WORD            32'h00000011
`define PQM_SHM_SCALAR_U1_P2P_WORD            32'h00000012
`define PQM_SHM_SCALAR_U2_P2P_WORD            32'h00000013
`define PQM_SHM_SCALAR_FREQUENCY_WORD        32'h00000014
`define PQM_SHM_SCALAR_PHASE_WORD            32'h00000015
`define PQM_SHM_SCALAR_ACTIVE_POWER_WORD     32'h00000016
`define PQM_SHM_SCALAR_REACTIVE_POWER_WORD   32'h00000017
`define PQM_SHM_SCALAR_APPARENT_POWER_WORD   32'h00000018
`define PQM_SHM_SCALAR_POWER_FACTOR_WORD     32'h00000019
`define PQM_SHM_SCALAR_THD_U1_WORD            32'h0000001A
`define PQM_SHM_SCALAR_THD_U2_WORD            32'h0000001B
`define PQM_SHM_SCALAR_DC_U1_WORD              32'h0000001C
`define PQM_SHM_SCALAR_DC_U2_WORD              32'h0000001D
`define PQM_SHM_SCALAR_ALARM_WORD             32'h0000001E
`define PQM_SHM_SCALAR_VALIDITY_WORD          32'h0000001F

// validity 字（word 0x1F）里新增的“数据可信度”粘滞位（缺陷 3：饱和/溢出必须可见）。
// 原有 bit11..0 的逐字段有效位一个都没动，ABI 偏移也没有任何变化。
//   bit12 = 去零点 17→16 位发生饱和（pqm_measurement_core 的 freq_center_sat_sticky）
//   bit13 = RFG 引擎内部溢出（pqm_rfg_frontend.o_overflow 粘滞）
//   bit14 = 频域取样 FIFO 溢出（pqm_sample_fifo.o_overflow 粘滞）
//   bit15 = 保留 0
`define PQM_SHM_VALIDITY_CENTER_SAT          32'h00001000
`define PQM_SHM_VALIDITY_RFG_OVERFLOW        32'h00002000
`define PQM_SHM_VALIDITY_FIFO_OVERFLOW       32'h00004000

// PS 命令和 PL 响应固定 word 偏移。
`define PQM_SHM_COMMAND_BASE_WORD            32'h00000080
`define PQM_SHM_COMMAND_REQUEST_WORD         32'h00000080
`define PQM_SHM_COMMAND_ARGUMENT_WORD        32'h00000081
`define PQM_SHM_COMMAND_SEQUENCE_WORD        32'h00000082
`define PQM_SHM_COMMAND_RESPONSE_WORD        32'h00000083
`define PQM_SHM_COMMAND_RESPONSE_SEQ_WORD    32'h00000084

// 运行计数器固定 word 偏移。
`define PQM_SHM_COUNTER_BASE_WORD            32'h000000A0
`define PQM_SHM_COUNTER_SAMPLE_DROP_WORD     32'h000000A0

// 双 bank 谐波窗口，每项依次为 U1、U2、相位和标志四个 word。
// ABI 条目数为 64 条（0..63）：帧尾 index = PQM_SHM_HARMONIC_LAST_INDEX = 63，
// 与 harmonic_stats 的 MAX_ORDER、RFG 取点 C_K=64 一致。
`define PQM_SHM_HARMONIC_BANK0_WORD          32'h00000400
`define PQM_SHM_HARMONIC_BANK1_WORD          32'h00000C00
`define PQM_SHM_HARMONIC_ENTRY_WORDS         32'h00000004
`define PQM_SHM_HARMONIC_LAST_INDEX          32'h0000003F

`endif
