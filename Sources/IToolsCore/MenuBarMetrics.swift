import Foundation
import Combine

public enum MenuBarMetric: String, CaseIterable, Identifiable {
    case cpu, memory, gpu, disk, network, temperature, fan
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .cpu: return "CPU"; case .memory: return "内存"; case .gpu: return "GPU"
        case .disk: return "磁盘"; case .network: return "网速"; case .temperature: return "CPU 温度"; case .fan: return "风扇"
        }
    }
    public var label: String {
        switch self {
        case .cpu: return "CPU"; case .memory: return "MEM"; case .gpu: return "GPU"
        case .disk: return "DISK"; case .network: return "NET"; case .temperature: return "TEMP"; case .fan: return "FAN"
        }
    }
    public var detail: String {
        switch self {
        case .cpu: return "所有核心的平均使用率"
        case .memory: return "已用内存百分比"
        case .gpu: return "显卡使用率；多显卡显示最高值"
        case .disk: return "用户所在磁盘的已用空间百分比"
        case .network: return "上传 ↑ 与下载 ↓ 速度"
        case .temperature: return "CPU 温度，单位 °C"
        case .fan: return "风扇转速，单位 RPM"
        }
    }
}
public final class MenuBarPreferences: ObservableObject {
    public static let key = "menuBar.enabledMetrics"
    public static let orderKey = "menuBar.metricOrder"
    @Published public private(set) var enabledMetrics: Set<MenuBarMetric>
    @Published public private(set) var metricOrder: [MenuBarMetric]
    public var visibleMetrics: [MenuBarMetric] { metricOrder.filter { enabledMetrics.contains($0) } }
    private let defaults: UserDefaults
    private let persistChanges: Bool
    public init(defaults: UserDefaults = .standard, persistChanges: Bool = true) {
        self.defaults = defaults
        self.persistChanges = persistChanges
        let storedOrder = defaults.stringArray(forKey: Self.orderKey) ?? []
        var seen: Set<MenuBarMetric> = []
        let known = storedOrder.compactMap(MenuBarMetric.init(rawValue:)).filter { seen.insert($0).inserted }
        metricOrder = known + MenuBarMetric.allCases.filter { !seen.contains($0) }
        // Keep the previous CPU-only default. An explicitly empty selection must stay empty.
        if let stored = defaults.stringArray(forKey: Self.key) {
            enabledMetrics = Set(stored.compactMap(MenuBarMetric.init(rawValue:)))
        } else { enabledMetrics = [.cpu] }
    }
    public func move(_ metric: MenuBarMetric, to target: MenuBarMetric) {
        guard metric != target, let from = metricOrder.firstIndex(of: metric),
              let to = metricOrder.firstIndex(of: target) else { return }
        var next = metricOrder
        next.remove(at: from); next.insert(metric, at: to)
        metricOrder = next
        if persistChanges { defaults.set(next.map(\.rawValue), forKey: Self.orderKey) }
    }
    public func isEnabled(_ metric: MenuBarMetric) -> Bool { enabledMetrics.contains(metric) }
    public func set(_ metric: MenuBarMetric, enabled: Bool) {
        var next = enabledMetrics
        if enabled { next.insert(metric) } else { next.remove(metric) }
        guard next != enabledMetrics else { return }
        enabledMetrics = next
        if persistChanges { defaults.set(MenuBarMetric.allCases.filter { next.contains($0) }.map(\.rawValue), forKey: Self.key) }
    }
}
public enum MetricFormatting {
    public static func percent(_ value: Double?) -> String {
        guard let value = value, value.isFinite, (0...100).contains(value) else { return "—" }
        return String(format: "%.0f%%", value)
    }
    public static func diskPercent(free: UInt64, total: UInt64) -> Double? {
        guard total > 0, free <= total else { return nil }
        return Double(total-free)/Double(total)*100
    }
    public static func rate(_ value: Double?) -> String {
        guard let value = value, value.isFinite, value >= 0 else { return "—" }
        let units = ["B/s", "KB/s", "MB/s", "GB/s", "TB/s"]
        var amount = value, index = 0
        while amount >= 1000 && index < units.count-1 { amount /= 1000; index += 1 }
        // Fixed units and one decimal below 10 keep menu bar text compact.
        return String(format: amount < 10 && index > 0 ? "%.1f %@" : "%.0f %@", amount, units[index])
    }
}
public enum GPUStatistics {
    /// Driver-provided percentages, not cumulative counters. Missing values are unknown, not zero.
    public static func utilization(_ values: [String: Double]) -> Double? {
        for key in ["Device Utilization %", "GPU Activity(%)", "Device Utilization % at cur p-state"] {
            if let value = values[key], value.isFinite, (0...100).contains(value) { return value }
        }
        return nil
    }
}
