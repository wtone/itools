#ifndef ITOOLS_SYSTEM_BRIDGE_H
#define ITOOLS_SYSTEM_BRIDGE_H
#include <stdint.h>
typedef struct {
    uint32_t user_ticks, system_ticks, idle_ticks, nice_ticks;
    uint64_t memory_used, memory_total, swap_used, network_in, network_out;
    int cpu_valid, memory_valid, network_valid;
} ITSystemSample;
typedef struct { double cpu_temperature, battery_temperature, fan_rpm, second_fan_rpm; } ITSensorSample;
ITSystemSample it_system_sample(void);
ITSensorSample it_sensor_sample(void);
#endif
