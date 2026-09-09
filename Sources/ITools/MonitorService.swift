import Foundation
import Darwin
import Combine
import IOKit.ps
import SystemBridge
import IToolsCore

struct MonitorSnapshot {
    var cpu: Double?
    var cpuUser: Double?
    var cpuSystem: Double?
    var cpuIdle: Double?
    var localAddresses: [String] = []
    var memoryUsed: UInt64 = 0
    var memoryTotal: UInt64 = 0
    var memoryAvailable = false
    var networkAvailable = false
    var gpu: Double?
    var gpuDevices: [String] = []
    var swap: UInt64 = 0
    var diskFree: UInt64 = 0
    var diskTotal: UInt64 = 0
    var download: Double = 0
    var upload: Double = 0
    var uptime: TimeInterval = 0
    var cpuTemperature: Double?
    var batteryTemperature: Double?
    var fan: Double?
    var fan2: Double?
    var battery: Double?
    var charging = false
    var batteryCycles: Int?
    var batteryHealth: Double?
    var memoryPercent: Double { memoryTotal == 0 ? 0 : Double(memoryUsed) / Double(memoryTotal) * 100 }
}
final class MonitorService: ObservableObject {
    @Published var snapshot = MonitorSnapshot()
    @Published var cpuHistory: [Double] = []
    @Published var memoryHistory: [Double] = []
    @Published var gpuHistory: [Double] = []
    @Published var enabled = true { didSet { UserDefaults.standard.set(enabled, forKey: "monitor.enabled"); configure() } }
    private let queue = DispatchQueue(label: "itools.monitor", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var previous: ITSystemSample?
    private var previousTime: TimeInterval?
    private var tick = 0
    private var sensors = ITSensorSample(cpu_temperature: .nan, battery_temperature: .nan, fan_rpm: .nan, second_fan_rpm: .nan)
    init() { enabled = UserDefaults.standard.object(forKey: "monitor.enabled") as? Bool ?? true }
    func start() { configure() }
    func stop() { timer?.cancel(); timer = nil }
    private func configure() {
        stop()
        guard enabled else { return }
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now(), repeating: 2, leeway: .milliseconds(300))
        source.setEventHandler { [weak self] in self?.sample() }
        timer = source; source.resume()
    }
    private func sample() {
        let sample = it_system_sample()
        let now = ProcessInfo.processInfo.systemUptime
        var result = MonitorSnapshot()
        if let old = previous, sample.cpu_valid == 1, old.cpu_valid == 1 {
            let user = Double(sample.user_ticks &- old.user_ticks)
            let system = Double(sample.system_ticks &- old.system_ticks)
            let nice = Double(sample.nice_ticks &- old.nice_ticks)
            let idle = Double(sample.idle_ticks &- old.idle_ticks)
            let total = user + system + nice + idle
            if total > 0 {
                result.cpu = (user + system + nice) / total * 100
                result.cpuUser = (user + nice) / total * 100
                result.cpuSystem = system / total * 100
                result.cpuIdle = idle / total * 100
            }
            if let time = previousTime, now > time, sample.network_valid == 1, old.network_valid == 1 {
                result.download = sample.network_in >= old.network_in ? Double(sample.network_in - old.network_in) / (now - time) : 0
                result.upload = sample.network_out >= old.network_out ? Double(sample.network_out - old.network_out) / (now - time) : 0
                result.networkAvailable = sample.network_in >= old.network_in && sample.network_out >= old.network_out
            }
        }
        previous = sample; previousTime = now
        result.memoryUsed = sample.memory_used; result.memoryTotal = sample.memory_total; result.swap = sample.swap_used
        result.memoryAvailable = sample.memory_valid == 1 && sample.memory_total > 0
        let graphics = GPUReader.read()
        result.gpu = graphics.map(\.value).max()
        result.gpuDevices = graphics.map { "\($0.name)：\(MetricFormatting.percent($0.value))" }
        if let disk = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()) {
            result.diskFree = (disk[.systemFreeSize] as? NSNumber)?.uint64Value ?? 0
            result.diskTotal = (disk[.systemSize] as? NSNumber)?.uint64Value ?? 0
        }
        result.uptime = now
        result.localAddresses = Self.localAddresses()
        if tick % 5 == 0 { sensors = it_sensor_sample() }
        tick += 1
        result.cpuTemperature = sensors.cpu_temperature.isFinite ? sensors.cpu_temperature : nil
        result.batteryTemperature = sensors.battery_temperature.isFinite ? sensors.battery_temperature : nil
        result.fan = sensors.fan_rpm.isFinite && sensors.fan_rpm >= 0 ? sensors.fan_rpm : nil
        result.fan2 = sensors.second_fan_rpm.isFinite && sensors.second_fan_rpm >= 0 ? sensors.second_fan_rpm : nil
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(), let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] {
            for source in list {
                guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                      description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
                if let current = description[kIOPSCurrentCapacityKey] as? Double, let max = description[kIOPSMaxCapacityKey] as? Double, max > 0 {
                    result.battery = current / max * 100
                }
                result.charging = description[kIOPSIsChargingKey] as? Bool ?? false
            }
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        if service != 0 {
            defer { IOObjectRelease(service) }
            func value(_ key: String) -> Double? { (IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber)?.doubleValue }
            if let cycles = value("CycleCount") { result.batteryCycles = Int(cycles) }
            if let maximum = value("AppleRawMaxCapacity") ?? value("MaxCapacity"), let design = value("DesignCapacity"), maximum > 100, design > 100 {
                result.batteryHealth = min(100, maximum / design * 100)
            }
        }
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.enabled else { return }
            self.snapshot = result
            if let cpu = result.cpu { self.cpuHistory.append(cpu); self.cpuHistory = Array(self.cpuHistory.suffix(60)) }
            self.memoryHistory.append(result.memoryPercent); self.memoryHistory = Array(self.memoryHistory.suffix(60))
            if let gpu = result.gpu { self.gpuHistory.append(gpu); self.gpuHistory = Array(self.gpuHistory.suffix(60)) }
        }
    }
    private static func localAddresses() -> [String] {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return [] }
        defer { freeifaddrs(list) }
        var addresses: [String] = []; var next = list
        while let item = next {
            let entry = item.pointee; next = entry.ifa_next
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  entry.ifa_flags & UInt32(IFF_UP) != 0,
                  String(cString: entry.ifa_name).hasPrefix("en") else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                addresses.append(String(cString: buffer))
            }
        }
        return Array(Set(addresses)).sorted()
    }
}

private enum GPUReader {
    struct Reading { let name: String; let value: Double }
    static func read() -> [Reading] {
        // IORegistry reads only: no Metal device creation or driver/control requests.
        // These PerformanceStatistics keys depend on the GPU driver, and may be absent.
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var readings: [Reading] = []
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            guard let stats = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? [String: Any],
                  let value = GPUStatistics.utilization(stats.compactMapValues { ($0 as? NSNumber)?.doubleValue }) else { continue }
            let driver = IORegistryEntryCreateCFProperty(entry, "IOClass" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String ?? ""
            let name = driver.localizedCaseInsensitiveContains("intel") ? "Intel GPU"
                : driver.localizedCaseInsensitiveContains("amd") ? "AMD GPU"
                : driver.localizedCaseInsensitiveContains("nv") ? "NVIDIA GPU" : "GPU"
            readings.append(Reading(name: name, value: value))
        }
        return readings
    }
}
