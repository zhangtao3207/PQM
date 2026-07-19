#include <stdint.h>
#include <stdio.h>

#include "pqm_touch_protocol.h"

static int failures;

#define CHECK(condition)                                                        \
    do {                                                                        \
        if (!(condition)) {                                                     \
            printf("FAIL %s:%d: %s\n", __FILE__, __LINE__, #condition);       \
            failures += 1;                                                      \
        }                                                                       \
    } while (0)

static void test_ft_packets_and_orientation(void)
{
    pqm_touch_point_t point = {1u, 1u, true};
    const uint8_t no_touch[4] = {0u, 0u, 0u, 0u};
    const uint8_t press[4] = {0x00u, 100u, 0x00u, 200u};
    const uint8_t move[4] = {0x01u, 0x2Cu, 0x02u, 0x58u};

    CHECK(pqm_touch_decode_packet(PQM_TOUCH_CONTROLLER_FT, 0u,
                                  no_touch, &point));
    CHECK(!point.pressed);
    CHECK(pqm_touch_decode_packet(PQM_TOUCH_CONTROLLER_FT, 1u,
                                  press, &point));
    CHECK(point.pressed);
    CHECK(point.x == 200u);
    CHECK(point.y == 100u);
    CHECK(pqm_touch_decode_packet(PQM_TOUCH_CONTROLLER_FT, 1u,
                                  move, &point));
    CHECK(point.x == 600u);
    CHECK(point.y == 300u);
}

static void test_gt_packets_and_malformed_count(void)
{
    pqm_touch_point_t point;
    const uint8_t coordinates[4] = {0x20u, 0x03u, 0xE0u, 0x01u};

    CHECK(pqm_touch_decode_packet(PQM_TOUCH_CONTROLLER_GT, 0x81u,
                                  coordinates, &point));
    CHECK(point.pressed);
    CHECK(point.x == 799u);
    CHECK(point.y == 479u);
    CHECK(!pqm_touch_decode_packet(PQM_TOUCH_CONTROLLER_GT, 0x86u,
                                   coordinates, &point));
    CHECK(!point.pressed);
    CHECK(!pqm_touch_decode_packet(PQM_TOUCH_CONTROLLER_NONE, 1u,
                                   coordinates, &point));
}

static void test_panel_edges_are_clipped(void)
{
    pqm_touch_point_t point;
    const uint8_t origin[4] = {0u, 0u, 0u, 0u};
    const uint8_t beyond_ft[4] = {0x0Fu, 0xFFu, 0x0Fu, 0xFFu};

    CHECK(pqm_touch_decode_packet(PQM_TOUCH_CONTROLLER_GT, 0x81u,
                                  origin, &point));
    CHECK(point.x == 0u && point.y == 0u);
    CHECK(pqm_touch_decode_packet(PQM_TOUCH_CONTROLLER_FT, 1u,
                                  beyond_ft, &point));
    CHECK(point.x == 799u && point.y == 479u);
}

static void test_i2c_timeout_recovery(void)
{
    pqm_touch_fault_t fault;

    pqm_touch_fault_init(&fault);
    pqm_touch_fault_failure(&fault, 100u);
    pqm_touch_fault_failure(&fault, 110u);
    CHECK(!fault.recovering);
    pqm_touch_fault_failure(&fault, 120u);
    CHECK(fault.recovering);
    CHECK(fault.retry_at_ms == 620u);
    CHECK(!pqm_touch_fault_retry_due(&fault, 619u));
    CHECK(pqm_touch_fault_retry_due(&fault, 620u));
    pqm_touch_fault_success(&fault);
    CHECK(!fault.recovering);
    CHECK(fault.consecutive_failures == 0u);
}

int main(void)
{
    test_ft_packets_and_orientation();
    test_gt_packets_and_malformed_count();
    test_panel_edges_are_clipped();
    test_i2c_timeout_recovery();

    if (failures != 0) {
        printf("FAIL: pqm_touch (%d failures)\n", failures);
        return 1;
    }
    printf("PASS: pqm_touch\n");
    return 0;
}
