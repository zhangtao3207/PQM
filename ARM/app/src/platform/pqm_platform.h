#ifndef PQM_PLATFORM_H
#define PQM_PLATFORM_H

#include <stdbool.h>

#include "../drivers/pqm_axi/pqm_axi.h"

bool pqm_platform_initialize(void);
pqm_axi_t *pqm_platform_axi(void);
void pqm_platform_print_identity(void);
void pqm_platform_fatal(const char *reason) __attribute__((noreturn));

#endif
