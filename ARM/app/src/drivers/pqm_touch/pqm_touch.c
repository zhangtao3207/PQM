/*
 * 800x480电容触摸硬件驱动。
 *
 * 通过PS I2C0和MIO/EMIO GPIO访问触摸控制器，自动探测FT与GT两类协议，
 * 使用GPIO下降沿中断唤醒触摸任务，并在连续通信失败后执行延时复位恢复。
 */
#include "pqm_touch.h"

#include <stddef.h>

#include "xparameters.h"
#include "xparameters_ps.h"
#include "xstatus.h"

#define PQM_TOUCH_I2C_HZ            250000u
#define PQM_TOUCH_FT_ADDRESS        0x38u
#define PQM_TOUCH_GT_ADDRESS        0x14u
#define PQM_TOUCH_FT_VERSION_REG    0x00A1u
#define PQM_TOUCH_FT_STATUS_REG     0x0002u
#define PQM_TOUCH_FT_COORD_REG      0x0003u
#define PQM_TOUCH_GT_STATUS_REG     0x814Eu
#define PQM_TOUCH_GT_COORD_REG      0x8150u
#define PQM_TOUCH_GPIO_IRQ_PRIORITY 0xB0u
#define PQM_TOUCH_GPIO_IRQ_TRIGGER  0x03u
#define PQM_TOUCH_BUS_IDLE_POLLS    100000u

static int pqm_touch_wait_bus_idle(pqm_touch_t *touch)
{
    uint32_t poll;

    for (poll = 0u; poll < PQM_TOUCH_BUS_IDLE_POLLS; ++poll) {
        if (!XIicPs_BusIsBusy(&touch->iic)) {
            return XST_SUCCESS;
        }
    }
    return XST_FAILURE;
}

static int pqm_touch_read_register(pqm_touch_t *touch, uint8_t slave_address,
                                   uint16_t register_address, bool wide_address,
                                   uint8_t *data, uint32_t length)
{
    uint8_t address[2];
    int address_length = wide_address ? 2 : 1;
    int status;

    if (wide_address) {
        address[0] = (uint8_t)(register_address >> 8);
        address[1] = (uint8_t)register_address;
    } else {
        address[0] = (uint8_t)register_address;
    }

    XIicPs_SetOptions(&touch->iic, XIICPS_REP_START_OPTION);
    status = XIicPs_MasterSendPolled(&touch->iic, address, address_length,
                                     slave_address);
    XIicPs_ClearOptions(&touch->iic, XIICPS_REP_START_OPTION);
    if (status != XST_SUCCESS) {
        return status;
    }
    status = XIicPs_MasterRecvPolled(&touch->iic, data, (int)length,
                                     slave_address);
    if (status != XST_SUCCESS) {
        return status;
    }
    return pqm_touch_wait_bus_idle(touch);
}

static int pqm_touch_write_register(pqm_touch_t *touch, uint8_t slave_address,
                                    uint16_t register_address,
                                    bool wide_address, uint8_t value)
{
    uint8_t packet[3];
    int packet_length;
    int status;

    if (wide_address) {
        packet[0] = (uint8_t)(register_address >> 8);
        packet[1] = (uint8_t)register_address;
        packet[2] = value;
        packet_length = 3;
    } else {
        packet[0] = (uint8_t)register_address;
        packet[1] = value;
        packet_length = 2;
    }
    status = XIicPs_MasterSendPolled(&touch->iic, packet, packet_length,
                                     slave_address);
    if (status != XST_SUCCESS) {
        return status;
    }
    return pqm_touch_wait_bus_idle(touch);
}

static void pqm_touch_publish(pqm_touch_t *touch,
                              const pqm_touch_point_t *point)
{
    taskENTER_CRITICAL();
    touch->latest_point = *point;
    taskEXIT_CRITICAL();
}

static void pqm_touch_publish_released(pqm_touch_t *touch)
{
    pqm_touch_point_t point = touch->latest_point;

    point.pressed = false;
    pqm_touch_publish(touch, &point);
}

static int pqm_touch_configure_ft(pqm_touch_t *touch)
{
    static const uint8_t registers[] = {0x00u, 0xA4u, 0x80u, 0x88u};
    static const uint8_t values[] = {0u, 0u, 22u, 12u};
    size_t index;

    for (index = 0u; index < sizeof(registers); ++index) {
        int status = pqm_touch_write_register(
            touch, PQM_TOUCH_FT_ADDRESS, registers[index], false,
            values[index]);
        if (status != XST_SUCCESS) {
            return status;
        }
    }
    return XST_SUCCESS;
}

static int pqm_touch_reset_and_probe(pqm_touch_t *touch)
{
    uint8_t probe[2];
    int status;

    XGpioPs_WritePin(&touch->gpio, PQM_TOUCH_RESET_PIN, 0u);
    vTaskDelay(pdMS_TO_TICKS(10u));
    XGpioPs_WritePin(&touch->gpio, PQM_TOUCH_RESET_PIN, 1u);
    vTaskDelay(pdMS_TO_TICKS(50u));

    status = pqm_touch_read_register(
        touch, PQM_TOUCH_FT_ADDRESS, PQM_TOUCH_FT_VERSION_REG,
        false, probe, sizeof(probe));
    if (status == XST_SUCCESS) {
        uint16_t version = ((uint16_t)probe[0] << 8) | probe[1];

        if (version == 0x3003u || version == 0x0001u ||
            version == 0x0002u || version == 0x0000u) {
            touch->controller = PQM_TOUCH_CONTROLLER_FT;
            return pqm_touch_configure_ft(touch);
        }
    }

    status = pqm_touch_read_register(
        touch, PQM_TOUCH_GT_ADDRESS, PQM_TOUCH_GT_STATUS_REG,
        true, probe, 1u);
    if (status == XST_SUCCESS) {
        touch->controller = PQM_TOUCH_CONTROLLER_GT;
        return XST_SUCCESS;
    }
    touch->controller = PQM_TOUCH_CONTROLLER_NONE;
    return XST_DEVICE_NOT_FOUND;
}

static void pqm_touch_gpio_callback(void *reference, uint32_t bank,
                                    uint32_t status)
{
    pqm_touch_t *touch = (pqm_touch_t *)reference;
    BaseType_t higher_priority_task_woken = pdFALSE;

    if (bank != touch->interrupt_bank ||
        (status & (1u << touch->interrupt_pin)) == 0u) {
        return;
    }
    touch->irq_pending = true;
    if (touch->notify_task != NULL) {
        vTaskNotifyGiveFromISR(touch->notify_task,
                               &higher_priority_task_woken);
        portYIELD_FROM_ISR(higher_priority_task_woken);
    }
}

static void pqm_touch_record_failure(pqm_touch_t *touch, uint32_t now_ms)
{
    pqm_touch_fault_failure(&touch->fault, now_ms);
    if (touch->fault.recovering && touch->interrupt_enabled) {
        XGpioPs_IntrDisablePin(&touch->gpio, PQM_TOUCH_INT_PIN);
        touch->interrupt_enabled = false;
    }
    pqm_touch_publish_released(touch);
}

int pqm_touch_initialize(pqm_touch_t *touch, TaskHandle_t notify_task)
{
    XIicPs_Config *iic_config;
    XGpioPs_Config *gpio_config;
    int status;

    if (touch == NULL || notify_task == NULL) {
        return XST_INVALID_PARAM;
    }
    iic_config = XIicPs_LookupConfig(XPAR_XIICPS_0_DEVICE_ID);
    gpio_config = XGpioPs_LookupConfig(XPAR_XGPIOPS_0_DEVICE_ID);
    if (iic_config == NULL || gpio_config == NULL) {
        return XST_DEVICE_NOT_FOUND;
    }
    status = XIicPs_CfgInitialize(&touch->iic, iic_config,
                                  iic_config->BaseAddress);
    if (status != XST_SUCCESS) {
        return status;
    }
    status = XIicPs_SetSClk(&touch->iic, PQM_TOUCH_I2C_HZ);
    if (status != XST_SUCCESS) {
        return status;
    }
    status = XGpioPs_CfgInitialize(&touch->gpio, gpio_config,
                                   gpio_config->BaseAddr);
    if (status != XST_SUCCESS) {
        return status;
    }

    touch->notify_task = notify_task;
    touch->irq_pending = true;
    touch->interrupt_enabled = false;
    touch->controller = PQM_TOUCH_CONTROLLER_NONE;
    touch->latest_point.x = 0u;
    touch->latest_point.y = 0u;
    touch->latest_point.pressed = false;
    pqm_touch_fault_init(&touch->fault);
    XGpioPs_GetBankPin((uint8_t)PQM_TOUCH_INT_PIN,
                       &touch->interrupt_bank, &touch->interrupt_pin);

    XGpioPs_SetDirectionPin(&touch->gpio, PQM_TOUCH_RESET_PIN, 1u);
    XGpioPs_SetOutputEnablePin(&touch->gpio, PQM_TOUCH_RESET_PIN, 1u);
    XGpioPs_SetDirectionPin(&touch->gpio, PQM_TOUCH_INT_PIN, 0u);
    return pqm_touch_reset_and_probe(touch);
}

int pqm_touch_connect_interrupt(pqm_touch_t *touch,
                                XScuGic *interrupt_controller)
{
    int status;

    if (touch == NULL || interrupt_controller == NULL) {
        return XST_INVALID_PARAM;
    }
    XGpioPs_SetCallbackHandler(&touch->gpio, touch,
                               pqm_touch_gpio_callback);
    XGpioPs_SetIntrTypePin(&touch->gpio, PQM_TOUCH_INT_PIN,
                           XGPIOPS_IRQ_TYPE_EDGE_FALLING);
    XScuGic_SetPriorityTriggerType(interrupt_controller, XPS_GPIO_INT_ID,
                                   PQM_TOUCH_GPIO_IRQ_PRIORITY,
                                   PQM_TOUCH_GPIO_IRQ_TRIGGER);
    status = XScuGic_Connect(interrupt_controller, XPS_GPIO_INT_ID,
                             (Xil_InterruptHandler)XGpioPs_IntrHandler,
                             &touch->gpio);
    if (status == XST_SUCCESS) {
        XGpioPs_IntrEnablePin(&touch->gpio, PQM_TOUCH_INT_PIN);
        XScuGic_Enable(interrupt_controller, XPS_GPIO_INT_ID);
        touch->interrupt_enabled = true;
    }
    return status;
}

int pqm_touch_service(pqm_touch_t *touch, uint32_t now_ms)
{
    uint8_t status_byte;
    uint8_t coordinates[4] = {0u, 0u, 0u, 0u};
    uint8_t slave_address;
    uint16_t status_register;
    uint16_t coordinate_register;
    bool wide_address;
    bool has_point;
    pqm_touch_point_t point;
    int status;

    if (touch == NULL) {
        return XST_INVALID_PARAM;
    }
    if (touch->fault.recovering) {
        pqm_touch_publish_released(touch);
        if (!pqm_touch_fault_retry_due(&touch->fault, now_ms)) {
            return XST_SUCCESS;
        }
        status = pqm_touch_reset_and_probe(touch);
        if (status != XST_SUCCESS) {
            touch->fault.retry_at_ms = now_ms + PQM_TOUCH_RECOVERY_DELAY_MS;
            return status;
        }
        pqm_touch_fault_success(&touch->fault);
        if (!touch->interrupt_enabled) {
            XGpioPs_IntrEnablePin(&touch->gpio, PQM_TOUCH_INT_PIN);
            touch->interrupt_enabled = true;
        }
        touch->irq_pending = true;
    }
    if (!touch->irq_pending) {
        return XST_SUCCESS;
    }
    touch->irq_pending = false;

    if (touch->controller == PQM_TOUCH_CONTROLLER_FT) {
        slave_address = PQM_TOUCH_FT_ADDRESS;
        status_register = PQM_TOUCH_FT_STATUS_REG;
        coordinate_register = PQM_TOUCH_FT_COORD_REG;
        wide_address = false;
    } else if (touch->controller == PQM_TOUCH_CONTROLLER_GT) {
        slave_address = PQM_TOUCH_GT_ADDRESS;
        status_register = PQM_TOUCH_GT_STATUS_REG;
        coordinate_register = PQM_TOUCH_GT_COORD_REG;
        wide_address = true;
    } else {
        return XST_DEVICE_NOT_FOUND;
    }

    status = pqm_touch_read_register(touch, slave_address, status_register,
                                     wide_address, &status_byte, 1u);
    if (status != XST_SUCCESS) {
        pqm_touch_record_failure(touch, now_ms);
        return status;
    }
    has_point = (status_byte & 0x0Fu) != 0u;
    if (touch->controller == PQM_TOUCH_CONTROLLER_GT) {
        has_point = has_point && (status_byte & 0x80u) != 0u;
    }
    status = XST_SUCCESS;
    if (has_point) {
        status = pqm_touch_read_register(
            touch, slave_address, coordinate_register, wide_address,
            coordinates, sizeof(coordinates));
    }
    if (pqm_touch_write_register(touch, slave_address, status_register,
                                 wide_address, 0u) != XST_SUCCESS ||
        status != XST_SUCCESS) {
        pqm_touch_record_failure(touch, now_ms);
        return XST_FAILURE;
    }
    if (!pqm_touch_decode_packet(touch->controller, status_byte,
                                 coordinates, &point)) {
        pqm_touch_record_failure(touch, now_ms);
        return XST_FAILURE;
    }

    pqm_touch_fault_success(&touch->fault);
    pqm_touch_publish(touch, &point);
    return XST_SUCCESS;
}

void pqm_touch_get_point(pqm_touch_t *touch, pqm_touch_point_t *point)
{
    if (touch == NULL || point == NULL) {
        return;
    }
    taskENTER_CRITICAL();
    *point = touch->latest_point;
    taskEXIT_CRITICAL();
}
