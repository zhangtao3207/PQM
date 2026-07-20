/* PQM平台层公开接口：负责PS硬件初始化、共享内存访问和致命错误复位。 */
#ifndef PQM_PLATFORM_H
#define PQM_PLATFORM_H

#include <stdbool.h>

#include "../drivers/pqm_axi/pqm_axi.h"

/* 开启缓存、绑定共享内存并校验PS/PL接口。 */
bool pqm_platform_initialize(void);
/* 返回全局共享内存驱动实例。 */
pqm_axi_t *pqm_platform_axi(void);
/* 输出PL魔数、ABI版本和能力位，便于启动诊断。 */
void pqm_platform_print_identity(void);
/* 输出错误并启动看门狗复位；此函数不会返回。 */
void pqm_platform_fatal(const char *reason) __attribute__((noreturn));

#endif
