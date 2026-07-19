#include "pqm_platform.h"

#include <stddef.h>

#include "xil_cache.h"
#include "xparameters.h"
#include "xscuwdt.h"
#include "xstatus.h"
#include "xil_printf.h"

#define PQM_FATAL_WATCHDOG_LOAD 0x00010000u

static pqm_axi_t pqm_axi;

bool pqm_platform_initialize(void)
{
    Xil_ICacheEnable();
    Xil_DCacheEnable();
    pqm_axi_init_mmio(&pqm_axi, XPAR_AXI_BRAM_CTRL_0_S_AXI_BASEADDR);
    return pqm_axi_validate(&pqm_axi);
}

pqm_axi_t *pqm_platform_axi(void)
{
    return &pqm_axi;
}

void pqm_platform_print_identity(void)
{
    uint32_t magic = pqm_axi.read_word(pqm_axi.context, PQM_SHM_MAGIC_WORD);
    uint32_t abi = pqm_axi.read_word(pqm_axi.context, PQM_SHM_ABI_WORD);
    uint32_t capabilities = pqm_axi.read_word(
        pqm_axi.context, PQM_SHM_CAPABILITIES_WORD);

    xil_printf("PQM PS boot: magic=%08x abi=%08x capabilities=%08x\r\n",
               magic, abi, capabilities);
}

void pqm_platform_fatal(const char *reason)
{
    XScuWdt watchdog;
    XScuWdt_Config *config;

    xil_printf("PQM fatal: %s\r\n", reason != NULL ? reason : "unknown");
    config = XScuWdt_LookupConfig(XPAR_SCUWDT_0_DEVICE_ID);
    if (config != NULL &&
        XScuWdt_CfgInitialize(&watchdog, config, config->BaseAddr) == XST_SUCCESS) {
        XScuWdt_Stop(&watchdog);
        XScuWdt_LoadWdt(&watchdog, PQM_FATAL_WATCHDOG_LOAD);
        XScuWdt_SetWdMode(&watchdog);
        XScuWdt_Start(&watchdog);
    }

    for (;;) {
    }
}
