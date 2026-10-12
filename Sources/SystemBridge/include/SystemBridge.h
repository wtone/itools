#ifndef ITOOLS_SYSTEM_BRIDGE_H
#define ITOOLS_SYSTEM_BRIDGE_H
#include <stdint.h>
typedef struct {
    uint32_t user_ticks, system_ticks, idle_ticks, nice_ticks;
    uint64_t memory_used, memory_total, swap_used, network_in, network_out;
    int cpu_valid, memory_valid, network_valid;
} ITSystemSample;
typedef struct { double cpu_temperature, battery_temperature, fan_rpm, second_fan_rpm; int cpu_core_max; } ITSensorSample;
ITSystemSample it_system_sample(void);
ITSensorSample it_sensor_sample(void);
double it_sensor_decode(uint32_t type, const uint8_t *bytes, uint32_t size);
// Returned status item is retained; the caller must consume the ownership.
void *it_primary_status_item_create(double length);
int it_primary_status_item_supported(void);
int it_primary_status_item_is_confined(void *object);
int it_primary_status_item_pin(void *object, const char *display_identifier);
int it_primary_status_item_reset_position(void *object);
int it_primary_status_item_set_position(void *object, double preferred);
int it_primary_status_items_set_positions(void * const *objects, const double *positions, int count);
#endif
