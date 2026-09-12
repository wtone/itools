import AppKit
import Combine
import IToolsCore

struct MenuBarReading {
    let top: String
    let bottom: String
    let tooltip: String
    static func make(_ metric: MenuBarMetric, snapshot s: MonitorSnapshot, running: Bool) -> MenuBarReading {
        guard running else { return .init(top: "—", bottom: metric.label, tooltip: metric.title + "：监控已暂停。点击打开 iTools 快捷面板。") }
        let value: String
        var detail = metric.detail
        switch metric {
        case .cpu: value = MetricFormatting.percent(s.cpu)
        case .memory: value = MetricFormatting.percent(s.memoryAvailable ? s.memoryPercent : nil)
        case .gpu:
            value = MetricFormatting.percent(s.gpu)
            detail = s.gpuDevices.isEmpty ? "当前显卡驱动未提供可用的使用率" : s.gpuDevices.joined(separator: "\n")
        case .disk: value = MetricFormatting.percent(MetricFormatting.diskPercent(free: s.diskFree, total: s.diskTotal))
        case .network:
            return .init(top: "↑ " + MetricFormatting.rate(s.networkAvailable ? s.upload : nil),
                         bottom: "↓ " + MetricFormatting.rate(s.networkAvailable ? s.download : nil),
                         tooltip: "网速\n上传：\(MetricFormatting.rate(s.networkAvailable ? s.upload : nil))\n下载：\(MetricFormatting.rate(s.networkAvailable ? s.download : nil))\n物理网络接口汇总；点击打开 iTools 快捷面板。")
        case .temperature: value = s.cpuTemperature.map { String(format: "%.0f°", $0) } ?? "—"
        case .fan: value = s.fan.map { String(format: "%.0f", $0) } ?? "—"
        }
        return .init(top: value, bottom: metric.label, tooltip: "\(metric.title)：\(value == "—" ? "不可用或等待采样" : value)\n\(detail)\n点击打开 iTools 快捷面板。")
    }
}

/// One native menu bar item per metric. Disabled items are removed rather than left blank.
final class MenuBarMonitor {
    private var items: [MenuBarMetric: NSStatusItem] = [:]
    private var subscription: AnyCancellable?
    private let target: MetricClickTarget
    var activeMetrics: Set<MenuBarMetric> { Set(items.keys) }
    init(monitor: MonitorService, preferences: MenuBarPreferences, onClick: @escaping (NSStatusBarButton) -> Void) {
        target = MetricClickTarget(action: onClick)
        subscription = Publishers.CombineLatest3(monitor.$snapshot, monitor.$enabled, preferences.$enabledMetrics)
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot, running, selected in
                self?.update(selected: selected, snapshot: snapshot, running: running)
            }
    }
    private func update(selected: Set<MenuBarMetric>, snapshot: MonitorSnapshot, running: Bool) {
        for metric in Array(items.keys) where !selected.contains(metric) {
            if let item = items.removeValue(forKey: metric) { NSStatusBar.system.removeStatusItem(item) }
        }
        for metric in MenuBarMetric.allCases where selected.contains(metric) {
            let item: NSStatusItem
            if let existing = items[metric] { item = existing }
            else {
                item = NSStatusBar.system.statusItem(withLength: Self.imageWidth(for: metric) + 8)
                item.autosaveName = "iTools.metric." + metric.rawValue
                item.button?.target = target; item.button?.action = #selector(MetricClickTarget.clicked(_:))
                items[metric] = item
            }
            let reading = MenuBarReading.make(metric, snapshot: snapshot, running: running)
            let icon = Self.image(for: reading, width: Self.imageWidth(for: metric))
            item.button?.image = icon
            item.button?.imagePosition = .imageOnly
            item.button?.toolTip = reading.tooltip
            item.button?.setAccessibilityLabel(reading.tooltip)
        }
    }
    /// Keep the menu bar's geometry stable across percentage digits and network unit changes.
    private static func imageWidth(for metric: MenuBarMetric) -> CGFloat { metric == .network ? 70 : 32 }
    static func image(for reading: MenuBarReading, width fixedWidth: CGFloat? = nil) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let top = reading.top as NSString, bottom = reading.bottom as NSString
        let width = fixedWidth ?? ceil(max(30, max(top.size(withAttributes: attributes).width, bottom.size(withAttributes: attributes).width)))
        let image = NSImage(size: NSSize(width: width, height: 22), flipped: false) { rect in
            for (text, y) in [(top, CGFloat(10.5)), (bottom, CGFloat(0))] {
                let naturalWidth = text.size(withAttributes: attributes).width
                let scale = min(1, rect.width / max(1, naturalWidth))
                // Unusually long driver readings shrink in place instead of moving every other status item.
                NSGraphicsContext.saveGraphicsState()
                let transform = NSAffineTransform(); transform.translateX(by: (rect.width - naturalWidth * scale) / 2, yBy: y)
                transform.scaleX(by: scale, yBy: 1); transform.concat()
                text.draw(at: .zero, withAttributes: attributes)
                NSGraphicsContext.restoreGraphicsState()
            }
            return true
        }
        image.isTemplate = true  // macOS adapts the ink to light/dark menu bars and selection.
        return image
    }
    func stop() {
        subscription?.cancel(); subscription = nil
        items.values.forEach { NSStatusBar.system.removeStatusItem($0) }; items.removeAll()
    }
    func verifyAndExport(snapshot: MonitorSnapshot, destination: URL) throws {
        let all = Set(MenuBarMetric.allCases)
        update(selected: all, snapshot: snapshot, running: true)
        let initialLengths = items.mapValues(\.length)
        for value in [0.0, 9, 99, 100, 999, 9_999, 999_999, 999_999_999, 1_000_000_000] {
            var changing = snapshot; changing.cpu = min(value, 100)
            changing.upload = value; changing.download = value; changing.fan = value
            update(selected: all, snapshot: changing, running: true)
            guard items.mapValues(\.length) == initialLengths else { throw UserFacingError("Smoke: metric refresh moved menu bar items") }
        }
        update(selected: all, snapshot: snapshot, running: true)
        guard activeMetrics == all else { throw UserFacingError("Smoke: metric creation failed") }
        update(selected: [.memory, .network], snapshot: snapshot, running: true)
        guard activeMetrics == [.memory, .network] else { throw UserFacingError("Smoke: independent switches failed") }
        update(selected: [], snapshot: snapshot, running: true)
        guard items.isEmpty else { throw UserFacingError("Smoke: disabled items were not removed") }
        for metric in MenuBarMetric.allCases {
            guard MenuBarReading.make(metric, snapshot: snapshot, running: false).top == "—" else {
                throw UserFacingError("Smoke: paused metric shows stale data")
            }
        }
        update(selected: all, snapshot: snapshot, running: true)
        let images = MenuBarMetric.allCases.compactMap { items[$0]?.button?.image }
        let width = images.reduce(CGFloat(16)) { $0 + $1.size.width + 12 }
        let preview = NSImage(size: NSSize(width: width, height: 34))
        preview.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: width, height: 34).fill()
        var x: CGFloat = 8
        for image in images { image.draw(in: NSRect(x: x,y: 6,width: image.size.width,height: 22)); x += image.size.width+12 }
        preview.unlockFocus()
        guard let data = preview.png else { throw UserFacingError("Smoke: menu bar image failed") }
        try data.write(to: destination.appendingPathComponent("menu-bar.png"))
        print("PASS: real status item creation/removal, independent switches, paused readings, fixed widths across metric/unit changes; GPU \(snapshot.gpuDevices)")
    }
    deinit { stop() }
}
private final class MetricClickTarget: NSObject {
    let action: (NSStatusBarButton) -> Void
    init(action: @escaping (NSStatusBarButton) -> Void) { self.action = action }
    @objc func clicked(_ sender: NSStatusBarButton) { action(sender) }
}
