#include "SystemBridge.h"
#include <mach/mach.h>
#include <sys/sysctl.h>
#include <sys/types.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <net/if_dl.h>
#include <IOKit/IOKitLib.h>
#include <math.h>
#include <string.h>

ITSystemSample it_system_sample(void) {
    ITSystemSample sample = {0};
    mach_port_t host = mach_host_self();
    host_cpu_load_info_data_t cpu;
    mach_msg_type_number_t count = HOST_CPU_LOAD_INFO_COUNT;
    if (host_statistics(host, HOST_CPU_LOAD_INFO, (host_info_t)&cpu, &count) == KERN_SUCCESS) {
        sample.user_ticks = cpu.cpu_ticks[CPU_STATE_USER];
        sample.system_ticks = cpu.cpu_ticks[CPU_STATE_SYSTEM];
        sample.idle_ticks = cpu.cpu_ticks[CPU_STATE_IDLE];
        sample.nice_ticks = cpu.cpu_ticks[CPU_STATE_NICE]; sample.cpu_valid = 1;
    }
    size_t size = sizeof(sample.memory_total);
    sysctlbyname("hw.memsize", &sample.memory_total, &size, NULL, 0);
    vm_statistics64_data_t vm; count = HOST_VM_INFO64_COUNT;
    vm_size_t page = 0; host_page_size(host, &page);
    if (host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&vm, &count) == KERN_SUCCESS) {
        // Activity Monitor-like used memory: active + wired + compressed, excluding purgeable pages.
        uint64_t pages = (uint64_t)vm.active_count + vm.wire_count + vm.compressor_page_count;
        sample.memory_used = (pages > vm.purgeable_count ? pages - vm.purgeable_count : 0) * page;
        sample.memory_valid = 1;
    }
    mach_port_deallocate(mach_task_self(), host);
    struct xsw_usage swap = {0}; size = sizeof(swap);
    if (!sysctlbyname("vm.swapusage", &swap, &size, NULL, 0)) sample.swap_used = swap.xsu_used;
    struct ifaddrs *interfaces = NULL;
    if (!getifaddrs(&interfaces)) {
        sample.network_valid = 1;
        for (struct ifaddrs *p = interfaces; p; p = p->ifa_next) {
            if (!p->ifa_addr || !p->ifa_data || p->ifa_addr->sa_family != AF_LINK || !(p->ifa_flags & IFF_UP)) continue;
            // Count physical interfaces once; avoid VPN, loopback and peer-to-peer double counting.
            if (strncmp(p->ifa_name, "en", 2) != 0) continue;
            const struct if_data *data = p->ifa_data;
            sample.network_in += data->ifi_ibytes; sample.network_out += data->ifi_obytes;
        }
        freeifaddrs(interfaces);
    }
    return sample;
}

// AppleSMC's user-client ABI is not a supported public sensor API.
// Only key-info (9) and read-bytes (5) commands are used. No writes/fan control.
typedef struct { uint8_t major, minor, build, reserved; uint16_t release; } ITSMCVersion;
typedef struct { uint16_t version, length; uint32_t cpu, gpu, memory; } ITSMCLimits;
typedef struct { uint32_t size, type; uint8_t attributes; } ITSMCKeyInfo;
typedef struct {
    uint32_t key; ITSMCVersion version; ITSMCLimits limits; ITSMCKeyInfo info;
    uint8_t result, status, command; uint32_t data; uint8_t bytes[32];
} ITSMCMessage;
_Static_assert(sizeof(ITSMCMessage) == 80, "AppleSMC ABI must be 80 bytes");
static uint32_t fourcc(const char *s) {
    return ((uint32_t)(uint8_t)s[0] << 24) | ((uint32_t)(uint8_t)s[1] << 16) | ((uint32_t)(uint8_t)s[2] << 8) | (uint8_t)s[3];
}
double it_sensor_decode(uint32_t type, const uint8_t *bytes, uint32_t size) {
    if (!bytes) return NAN;
    if (type == fourcc("sp78") && size == 2) return (double)(int16_t)((bytes[0] << 8) | bytes[1]) / 256.0;
    if (type == fourcc("fpe2") && size == 2) return (double)((bytes[0] << 8) | bytes[1]) / 4.0;
    if (type == fourcc("flt ") && size == 4) { float value; memcpy(&value, bytes, 4); return isfinite(value) ? value : NAN; }
    return NAN;
}
static double read_value(io_connect_t connection, const char *key) {
    ITSMCMessage in = {0}, out = {0}; size_t length = sizeof(out);
    in.key = fourcc(key); in.command = 9;
    if (IOConnectCallStructMethod(connection, 2, &in, sizeof(in), &out, &length) != KERN_SUCCESS || length != sizeof(out) || out.result) return NAN;
    if (out.info.size == 0 || out.info.size > 32) return NAN;
    in.info = out.info; uint32_t type = out.info.type; in.command = 5;
    memset(&out, 0, sizeof(out)); length = sizeof(out);
    if (IOConnectCallStructMethod(connection, 2, &in, sizeof(in), &out, &length) != KERN_SUCCESS || length != sizeof(out) || out.result) return NAN;
    return it_sensor_decode(type, out.bytes, in.info.size);
}
ITSensorSample it_sensor_sample(void) {
    ITSensorSample result = {NAN, NAN, NAN, NAN, 0};
    io_service_t service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"));
    if (!service) return result;
    io_connect_t connection = IO_OBJECT_NULL;
    kern_return_t status = IOServiceOpen(service, mach_task_self(), 0, &connection); IOObjectRelease(service);
    if (status != KERN_SUCCESS) return result;
    const char *keys[] = {"TC0P", "TC0D", "TC0E", "TC0F"};
    for (int i = 0; i < 4; i++) {
        double value = read_value(connection, keys[i]);
        if (value > 0 && value < 130) { result.cpu_temperature = value; break; }
    }
#if defined(__arm64__) || defined(__aarch64__)
    char brand[128] = {0}; size_t brand_size = sizeof(brand) - 1;
    if (!sysctlbyname("machdep.cpu.brand_string", brand, &brand_size, NULL, 0) && strstr(brand, "Apple M2")) {
        // M2-family CPU core key addresses, validated on M2 Pro. Read only this
        // CPU group: GPU/board/power keys must not be labelled as CPU temperature.
        const char *core_keys[] = {"Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j", "Tp1h", "Tp1t", "Tp1p", "Tp1l"};
        double hottest = NAN;
        for (unsigned i = 0; i < sizeof(core_keys) / sizeof(core_keys[0]); i++) {
            double value = read_value(connection, core_keys[i]);
            if (value > 0 && value < 130 && (!isfinite(hottest) || value > hottest)) hottest = value;
        }
        if (isfinite(hottest)) { result.cpu_temperature = hottest; result.cpu_core_max = 1; }
    }
#endif
    double battery = read_value(connection, "TB0T");
    if (!isfinite(battery) || battery <= 0 || battery >= 100) battery = read_value(connection, "TB1T");
    if (battery > 0 && battery < 100) result.battery_temperature = battery;
    double fan = read_value(connection, "F0Ac"), fan2 = read_value(connection, "F1Ac");
    if (isfinite(fan) && fan >= 0 && fan < 30000) result.fan_rpm = fan;
    if (isfinite(fan2) && fan2 >= 0 && fan2 < 30000) result.second_fan_rpm = fan2;
    IOServiceClose(connection);
    return result;
}
