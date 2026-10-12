import AppKit
import Combine
import SystemBridge
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
        case .temperature:
            value = s.cpuTemperature.map { String(format: "%.0f°", $0) } ?? "—"
            detail = s.cpuTemperatureIsCoreMaximum ? "已读取的 CPU 核心最高温度 · SMC 只读" : "CPU 温度 · SMC 只读"
        case .fan:
            value = s.fan.map { String(format: "%.0f", $0) } ?? "—"
            detail = "转速，单位 RPM" + (s.fan2.map { String(format: "；第二风扇 %.0f RPM", $0) } ?? "")
            if s.fan == 0 { detail += "；当前风扇停转" }
        }
        return .init(top: value, bottom: metric.label, tooltip: "\(metric.title)：\(value == "—" ? "不可用或等待采样" : value)\n\(detail)\n点击打开 iTools 快捷面板。")
    }
}

/// Each reading is a real native status item, with its own Cmd-drag and autosave slot.
final class MenuBarMonitor {
    static let metricGap: CGFloat = 16
    private struct Entry {
        let item: NSStatusItem
        let scope: MenuBarDisplayScope
    }
    private var items: [MenuBarMetric: Entry] = [:]
    private var subscription: AnyCancellable?
    private let statusItem: NSStatusItem
    private var displayScope: MenuBarDisplayScope!
    private let placement = MenuBarItemPlacement()
    private var checkingDisplayScope = false
    private var initializeOnLeft: Bool
    private var smokeNames: Set<String> = []
    var activeMetrics: Set<MenuBarMetric> { Set(items.keys) }
    private var nativeItems: [NSStatusItem] { [statusItem] + MenuBarMetric.allCases.compactMap { items[$0]?.item } }
    init(monitor: MonitorService, preferences: MenuBarPreferences, statusItem: NSStatusItem, initializeOnLeft: Bool) {
        self.statusItem = statusItem
        self.initializeOnLeft = initializeOnLeft
        statusItem.length = 16
        statusItem.button?.imagePosition = .imageOnly
        displayScope = makeScope(for: statusItem)
        subscription = Publishers.CombineLatest3(monitor.$snapshot, monitor.$enabled, preferences.$enabledMetrics)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] snapshot, running, selected in
                self?.update(selected: selected, snapshot: snapshot, running: running)
            }
        update(selected: preferences.enabledMetrics, snapshot: monitor.snapshot, running: monitor.enabled)
    }
    private func makeScope(for item: NSStatusItem) -> MenuBarDisplayScope {
        MenuBarDisplayScope(item: item, initializeOnLeft: false, placementRecovery: { [weak self] in
            guard let self, !self.checkingDisplayScope, !self.placement.isPlacing else { return false }
            self.restoreDefaultPosition(); return self.placement.isPlacing
        })
    }
    private func update(selected: Set<MenuBarMetric>, snapshot: MonitorSnapshot, running: Bool) {
        guard !checkingDisplayScope else { return }
        var needsPlacement = initializeOnLeft
        if selected != activeMetrics {
            needsPlacement = needsPlacement || placement.isPlacing
            placement.stop()
        }
        for metric in MenuBarMetric.allCases where !selected.contains(metric) {
            if let entry = items.removeValue(forKey: metric) {
                // Removal lets AppKit save this item's position for later re-enabling.
                remove(entry)
            }
        }
        for metric in MenuBarMetric.allCases where selected.contains(metric) {
            if items[metric] == nil {
                let name = (statusItem.autosaveName ?? "iTools.metrics") + "." + metric.rawValue
                let key = "NSStatusItem Preferred Position " + name
                let saved = UserDefaults.standard.object(forKey: key) as? NSNumber
                let valid = NSScreen.screens.first.map { screen in
                    saved.map { value in MenuBarPlacement.isSavedPositionUsable(value.doubleValue, screen: screen.frame, rightArea: screen.auxiliaryTopRightArea) } ?? false
                } ?? false
                if !valid { UserDefaults.standard.set(0, forKey: key); needsPlacement = true }
                let item = MenuBarDisplayScope.makeStatusItem(length: Self.imageWidth(for: metric))
                item.autosaveName = name
                item.button?.target = statusItem.button?.target; item.button?.action = statusItem.button?.action
                item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
                item.button?.imagePosition = .imageOnly
                if valid, let saved {
                    // Autosave assignment can update the registry without moving
                    // the newly created compositor slot. Reinstall at that slot.
                    _ = it_primary_status_item_set_position(Unmanaged.passUnretained(item).toOpaque(), saved.doubleValue)
                }
                items[metric] = Entry(item: item, scope: makeScope(for: item))
                if ProcessInfo.processInfo.arguments.contains("--smoke-test") { smokeNames.insert(name) }
            }
            guard let entry = items[metric] else { continue }
            let reading = MenuBarReading.make(metric, snapshot: snapshot, running: running)
            entry.item.button?.image = Self.image(for: reading, width: Self.imageWidth(for: metric), metric: metric)
            entry.item.button?.title = ""
            entry.item.button?.toolTip = reading.tooltip
            entry.item.button?.setAccessibilityLabel(metric.title)
            entry.item.button?.setAccessibilityValue(reading.top + ", " + reading.bottom)
            entry.scope.refresh()
        }
        initializeOnLeft = false
        displayScope.refresh()
        if needsPlacement { restoreDefaultPosition() }
    }
    /// Keep the menu bar's geometry stable across percentage digits and network unit changes.
    static func imageWidth(for metric: MenuBarMetric) -> CGFloat { metric == .network ? 58 : 28 }
    static func image(for reading: MenuBarReading, width fixedWidth: CGFloat? = nil, metric: MenuBarMetric? = nil, leftAligned: Bool? = nil) -> NSImage {
        // Upload and download are both values; keep their sizes equal.
        let numericPair = metric == .network && reading.bottom != MenuBarMetric.network.label
        let valueFont = NSFont.monospacedDigitSystemFont(ofSize: numericPair ? 10 : 11, weight: numericPair ? .medium : .semibold)
        let labelFont = numericPair ? valueFont : NSFont.systemFont(ofSize: 7.5, weight: .medium)
        let topAttributes: [NSAttributedString.Key: Any] = [.font: valueFont, .foregroundColor: NSColor.black]
        let bottomAttributes: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: NSColor.black]
        let alignLeft = leftAligned ?? (metric == .network)
        let top = reading.top as NSString, bottom = reading.bottom as NSString
        let width = fixedWidth ?? ceil(max(30, max(top.size(withAttributes: topAttributes).width, bottom.size(withAttributes: bottomAttributes).width)))
        let image = NSImage(size: NSSize(width: width, height: 22), flipped: false) { rect in
            for (text, y, attributes) in [(top, CGFloat(numericPair ? 10 : 9), topAttributes), (bottom, CGFloat(0), bottomAttributes)] {
                let naturalWidth = text.size(withAttributes: attributes).width
                let scale = min(1, rect.width / max(1, naturalWidth))
                // Unusually long driver readings shrink in place instead of moving every other status item.
                NSGraphicsContext.saveGraphicsState()
                let transform = NSAffineTransform(); transform.translateX(by: alignLeft ? 0 : (rect.width - naturalWidth * scale) / 2, yBy: y)
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
        subscription?.cancel(); subscription = nil; placement.stop()
        for entry in items.values { remove(entry) }
        items.removeAll(); displayScope.stop()
        for name in smokeNames {
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.contains(name) { UserDefaults.standard.removeObject(forKey: key) }
        }
    }
    private func remove(_ entry: Entry) {
        let name = entry.item.autosaveName
        let position = MenuBarItemPlacement.savedPosition(of: entry.item)
        entry.scope.stop(); NSStatusBar.system.removeStatusItem(entry.item)
        // AppKit can discard a removed item's autosave position. Preserve the
        // native key itself, so toggles and normal shutdown retain the user's slot.
        if let name, let position { UserDefaults.standard.set(position, forKey: "NSStatusItem Preferred Position " + name) }
    }
    func restoreDefaultPosition() {
        if let screen = NSScreen.screens.first {
            placement.restore(MenuBarItemPlacement.savedOrder(nativeItems), on: screen)
        }
    }
    private func settlePlacement() throws {
        let deadline = Date().addingTimeInterval(8)
        while placement.isPlacing && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        guard !placement.isPlacing else { throw UserFacingError("Smoke: independent status-item placement did not settle") }
    }
    func verifyCurrentDisplay() throws {
        try displayScope.verifyCurrentDisplay(expectedItemCount: nativeItems.count)
        for entry in items.values { try entry.scope.verifyCurrentDisplay(expectedItemCount: nativeItems.count) }
        let frames = nativeItems.compactMap { $0.button.flatMap { MenuBarDisplayScope.buttonScreenRect($0, includeWindowFrame: true) } }.sorted { $0.minX < $1.minX }
        guard zip(frames, frames.dropFirst()).allSatisfy({ $0.maxX <= $1.minX + 0.5 }) else { throw UserFacingError("Smoke: independent status items overlap") }
    }
    func verifyAndExport(snapshot: MonitorSnapshot, destination: URL) throws {
        let all = Set(MenuBarMetric.allCases)
        try settlePlacement()
        guard activeMetrics == all, Set(nativeItems.compactMap(\.autosaveName)).count == all.count + 1,
              items.allSatisfy({ metric, entry in entry.item.button?.image?.isTemplate == true && entry.item.button?.toolTip?.contains(metric.title) == true }),
              nativeItems.allSatisfy({ $0.button?.target === statusItem.button?.target && $0.button?.action == statusItem.button?.action }) else {
            throw UserFacingError("Smoke: independent native items, autosave names or click actions missing")
        }
        try verifyCurrentDisplay()
        try verifyGroupDisplayScope()
        try settlePlacement()
        try items.values.compactMap { $0.item.button?.toolTip }.joined(separator: "\n\n").write(to: destination.appendingPathComponent("menu-bar-live.txt"), atomically: true, encoding: .utf8)
        let identities = items.mapValues { ObjectIdentifier($0.item) }
        let lengths = items.mapValues { $0.item.length }
        for value in [0.0, 9, 99, 100, 999, 9_999, 999_999, 999_999_999, 1_000_000_000] {
            var changing = snapshot; changing.cpu = min(value, 100)
            changing.upload = value; changing.download = value; changing.fan = value
            update(selected: all, snapshot: changing, running: true)
            guard items.mapValues({ ObjectIdentifier($0.item) }) == identities, items.mapValues({ $0.item.length }) == lengths else {
                throw UserFacingError("Smoke: sampling recreated or resized an independently draggable item")
            }
        }
        update(selected: all, snapshot: snapshot, running: true)
        try MenuBarRenderingSmokeChecks.run(destination: destination)
        // Exercise the original confinement / notch fixtures with one isolated item.
        update(selected: [], snapshot: snapshot, running: true)
        guard items.isEmpty, statusItem.length == 16 else { throw UserFacingError("Smoke: disabled metrics retained a native slot") }
        placement.stop(); displayScope.stop()
        let isolated = MenuBarDisplayScope(item: statusItem, initializeOnLeft: false)
        checkingDisplayScope = true
        do {
            try isolated.verifyAndExport(destination: destination)
            if ProcessInfo.processInfo.arguments.contains("--menu-bar-notch-check") {
                // Keep the broad-window collision fixture comparable with the
                // original consolidated item; production toolbox width stays 16.
                statusItem.length = 278
                try MenuBarPlacementSmokeChecks.run(item: statusItem, scope: isolated, destination: destination)
                statusItem.length = 16
            }
        } catch { isolated.stop(); throw error }
        isolated.stop(); checkingDisplayScope = false; displayScope = makeScope(for: statusItem)
        update(selected: all, snapshot: snapshot, running: true); restoreDefaultPosition(); try settlePlacement()
        // Reorder native slots, including the toolbox, then remove/re-enable a metric.
        // Read back compositor order; writing defaults alone is not proof of movement.
        let wanted = [items[.network]!.item, items[.cpu]!.item, statusItem] + MenuBarMetric.allCases.filter { $0 != .network && $0 != .cpu }.compactMap { items[$0]?.item }
        placement.restore(wanted, on: NSScreen.screens.first!); try settlePlacement()
        let names = wanted.compactMap(\.autosaveName)
        func actualOrder() -> [String] {
            nativeItems.sorted {
                ($0.button.flatMap { MenuBarDisplayScope.buttonScreenRect($0) }?.minX ?? 0) < ($1.button.flatMap { MenuBarDisplayScope.buttonScreenRect($0) }?.minX ?? 0)
            }.compactMap(\.autosaveName)
        }
        guard actualOrder() == names else { throw UserFacingError("Smoke: native status item reorder did not move the toolbox and network independently; wanted=\(names), actual=\(actualOrder())") }
        update(selected: all.subtracting([.memory]), snapshot: snapshot, running: true)
        update(selected: all, snapshot: snapshot, running: true); try settlePlacement()
        guard actualOrder() == names else { throw UserFacingError("Smoke: re-enabling a metric lost its saved native position; wanted=\(names), actual=\(actualOrder())") }
        try verifyCurrentDisplay()
        for metric in MenuBarMetric.allCases {
            guard MenuBarReading.make(metric, snapshot: snapshot, running: false).top == "—" else { throw UserFacingError("Smoke: paused metric shows stale data") }
        }
        let lines = nativeItems.map { "\($0.autosaveName ?? ""): length=\($0.length) position=\(MenuBarItemPlacement.savedPosition(of: $0) as Any) frame=\($0.button.flatMap { MenuBarDisplayScope.buttonScreenRect($0, includeWindowFrame: true) } as Any)" }
        try lines.joined(separator: "\n").write(to: destination.appendingPathComponent("menu-bar-independent-items.txt"), atomically: true, encoding: .utf8)
        print("PASS: 8 independently draggable native status items; unique autosave positions; toolbox/network reordering; metric removal/re-enabling preserves order; unchanged objects and widths during sampling")
    }
    private func verifyGroupDisplayScope() throws {
        let entries = [displayScope!] + MenuBarMetric.allCases.compactMap { items[$0]?.scope }
        let name = "iTools.group-display-check." + UUID().uuidString
        let key = "NSStatusItem Preferred Position " + name
        UserDefaults.standard.set(nativeItems.reduce(CGFloat(0)) { $0 + $1.length + 16 }, forKey: key)
        let existing = Set(NSApp.windows.map(\.windowNumber))
        let witness = NSStatusBar.system.statusItem(withLength: 20)
        witness.autosaveName = name; witness.button?.title = "•"
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.3)) }
        checkingDisplayScope = true
        defer {
            NSStatusBar.system.removeStatusItem(witness)
            for entry in entries { entry.finishVisibilityCheck() }
            checkingDisplayScope = false
            restoreDefaultPosition()
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.contains(name) { UserDefaults.standard.removeObject(forKey: key) }
        }
        settle()
        let windows = NSApp.windows.filter { !existing.contains($0.windowNumber) && $0.level == .statusBar }
        guard windows.count == NSScreen.screens.count else { throw UserFacingError("Smoke: independent-group layout witness missing a display") }
        for entry in entries { entry.setVisibilityForCheck(false) }; settle()
        let absent = Dictionary(uniqueKeysWithValues: windows.map { ($0.windowNumber, $0.frame) })
        for entry in entries { entry.setVisibilityForCheck(true) }; settle()
        for window in windows where window.screen !== NSScreen.screens.first {
            guard window.frame == absent[window.windowNumber] else { throw UserFacingError("Smoke: independent metrics reserve secondary menu-bar space") }
        }
        print("PASS: all independent menu items retain zero secondary native layout width as a group")
    }
    deinit { stop() }
}
