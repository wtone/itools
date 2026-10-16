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

/// One native slot per selected display, sharing the same monitor and preferences.
final class MenuBarMonitor {
    static let metricGap: CGFloat = 4
    private var subscription: AnyCancellable?
    let statusItem: NSStatusItem
    private let preferences: MenuBarPreferences
    private let toolboxImage: NSImage?
    private var displayScope: MenuBarDisplayScope!
    private var interaction: MenuBarMetricsView!
    private var modeSubscription: AnyCancellable?
    private let pinnedDisplayID: String?
    private var replicas: [String: MenuBarMonitor] = [:]
    private var screenObserver: NSObjectProtocol?
    private let monitor: MonitorService
    private let clickHandler: (NSStatusBarButton, Bool) -> Void
    private var checkingDisplayScope = false
    private(set) var activeMetrics: Set<MenuBarMetric> = []
    private var readings: [MenuBarMetric: MenuBarReading] = [:]
    init(monitor: MonitorService, preferences: MenuBarPreferences, statusItem: NSStatusItem, initializeOnLeft: Bool,
         pinnedDisplayID: String? = nil, click: @escaping (NSStatusBarButton, Bool) -> Void) {
        self.statusItem = statusItem; self.preferences = preferences
        self.monitor = monitor; self.clickHandler = click; self.pinnedDisplayID = pinnedDisplayID
        toolboxImage = statusItem.button?.image
        installInteraction()
        subscription = Publishers.CombineLatest4(monitor.$snapshot, monitor.$enabled, preferences.$enabledMetrics, preferences.$metricOrder)
            .debounce(for: .milliseconds(100), scheduler: DispatchQueue.main)
            .sink { [weak self] snapshot, running, selected, order in
                self?.update(metrics: order.filter { selected.contains($0) }, snapshot: snapshot, running: running)
            }
        update(metrics: preferences.visibleMetrics, snapshot: monitor.snapshot, running: monitor.enabled)
        displayScope = MenuBarDisplayScope(item: statusItem, initializeOnLeft: initializeOnLeft, preferences: preferences, pinnedDisplayID: pinnedDisplayID)
        if pinnedDisplayID == nil {
            modeSubscription = preferences.$displaySelection.dropFirst()
                .receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refreshDisplayConfiguration() }
            screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                object: nil, queue: .main) { [weak self] _ in self?.refreshDisplayConfiguration() }
            refreshDisplayConfiguration()
        }
    }
    private func installInteraction() {
        interaction = MenuBarMetricsView(button: statusItem.button!)
        statusItem.button?.addSubview(interaction)
        interaction.move = { [weak preferences] metric, target in preferences?.move(metric, to: target) }
        interaction.click = { [weak self] right in
            guard let self, let button = self.statusItem.button else { return }
            self.clickHandler(button, right)
        }
    }
    func refreshDisplayConfiguration() {
        guard pinnedDisplayID == nil else { displayScope.refresh(); return }
        let targets = preferences.displaySelection.mode == .all && MenuBarDisplayScope.isSupported ? Array(MenuBarDisplayScope.availableScreens.dropFirst()) : []
        let wanted = Set(targets.map(\.id))
        for id in Array(replicas.keys) where !wanted.contains(id) {
            if let replica = replicas.removeValue(forKey: id) {
                replica.stop()
                Self.removeReplicaItem(replica.statusItem)
            }
        }
        for screen in targets where replicas[screen.id] == nil {
            let name = (statusItem.autosaveName ?? "iTools.metrics") + ".display." + screen.id
            let initializeOnLeft = MenuBarDisplayScope.prepareAutosave(name)
            let item = MenuBarDisplayScope.makeStatusItem(length: statusItem.length)
            item.autosaveName = name
            item.button?.image = toolboxImage
            item.button?.target = statusItem.button?.target; item.button?.action = statusItem.button?.action
            item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
            replicas[screen.id] = MenuBarMonitor(monitor: monitor, preferences: preferences, statusItem: item,
                initializeOnLeft: initializeOnLeft, pinnedDisplayID: screen.id, click: clickHandler)
        }
        // Apply the current shared selection before pinning the new topology.
        // Do not wait for a queued sampling delivery to size a newly shown item.
        update(metrics: preferences.visibleMetrics, snapshot: monitor.snapshot, running: monitor.enabled)
        displayScope.refresh()
        for replica in replicas.values {
            replica.update(metrics: preferences.visibleMetrics, snapshot: monitor.snapshot, running: monitor.enabled)
            replica.displayScope.refresh()
        }
    }
    private static func removeReplicaItem(_ item: NSStatusItem) {
        let key = item.autosaveName.map { "NSStatusItem Preferred Position " + $0 }
        let saved = key.flatMap { UserDefaults.standard.object(forKey: $0) }
        NSStatusBar.system.removeStatusItem(item)
        if let key, let saved { UserDefaults.standard.set(saved, forKey: key) }
    }
    private func update(metrics: [MenuBarMetric], snapshot: MonitorSnapshot, running: Bool) {
        guard !checkingDisplayScope else { return }
        activeMetrics = Set(metrics)
        readings = Dictionary(uniqueKeysWithValues: metrics.map { ($0, MenuBarReading.make($0, snapshot: snapshot, running: running)) })
        let images = metrics.map { Self.image(for: readings[$0]!, width: Self.imageWidth(for: $0), metric: $0) }
        let width = metrics.isEmpty ? 16 : images.reduce(CGFloat(0)) { $0 + $1.size.width } + CGFloat(max(0, metrics.count - 1)) * Self.metricGap
        let combined = NSImage(size: NSSize(width: width, height: 22), flipped: false) { [toolboxImage] _ in
            if images.isEmpty { toolboxImage?.draw(in: NSRect(x: 0, y: 3, width: 16, height: 16)) }
            var x: CGFloat = 0
            for image in images {
                image.draw(in: NSRect(x: x, y: 0, width: image.size.width, height: 22)); x += image.size.width + Self.metricGap
            }
            return true
        }
        combined.isTemplate = true
        // Keep the same native slot and its insertion point when switches change.
        // Only the contiguous content changes width; other apps cannot interleave.
        let changedWidth = statusItem.length != width
        let position = statusItem.autosaveName.map { UserDefaults.standard.double(forKey: "NSStatusItem Preferred Position " + $0) } ?? 0
        if changedWidth { statusItem.length = width }
        statusItem.button?.image = combined; statusItem.button?.title = ""
        statusItem.button?.imagePosition = .imageOnly; statusItem.button?.toolTip = nil
        statusItem.button?.setAccessibilityLabel(metrics.isEmpty ? "iTools 工具箱" : "iTools 系统指标")
        statusItem.button?.setAccessibilityValue(metrics.map { "\($0.title)：\(readings[$0]!.top) \(readings[$0]!.bottom)" }.joined(separator: "，"))
        var x: CGFloat = 0
        var columns = metrics.map { metric -> MenuBarMetricsView.Column in
            let width = Self.imageWidth(for: metric)
            defer { x += width + Self.metricGap }
            return .init(metric: metric, x: x, width: width, tooltip: readings[metric]!.tooltip + "\n拖动或按住 ⌘ 拖动，调整区域内顺序。")
        }
        if metrics.isEmpty { columns = [.init(metric: nil, x: 0, width: 16, tooltip: "iTools 快捷面板 · 右键打开文字菜单")] }
        interaction.update(columns)
        if changedWidth {
            // Rapid zero/nonzero transitions can leave the existing compositor
            // window uninstalled although its registry remains visible. Reuse
            // the same native insertion point and object after resizing.
            _ = it_primary_status_item_set_position(Unmanaged.passUnretained(statusItem).toOpaque(), position)
        }
        displayScope?.refresh()
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
        subscription?.cancel(); subscription = nil; modeSubscription?.cancel(); modeSubscription = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }; screenObserver = nil
        interaction.stop(); displayScope.stop()
        for replica in replicas.values { replica.stop(); Self.removeReplicaItem(replica.statusItem) }
        replicas.removeAll()
    }
    func restoreDefaultPosition() {
        if let screen = displayScope.placementScreen { displayScope.restoreDefaultPosition(on: screen) }
        for replica in replicas.values { replica.restoreDefaultPosition() }
    }
    private func settlePlacement() {
        let deadline = Date().addingTimeInterval(6)
        while Date() < deadline { displayScope.refresh(); RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    }
    func verifyCurrentDisplay() throws { try displayScope.verifyCurrentDisplay() }
    func verifyAndExport(snapshot: MonitorSnapshot, destination: URL) throws {
        checkingDisplayScope = true
        // Preserve the application's configured group after isolated native checks.
        defer {
            checkingDisplayScope = false
            update(metrics: preferences.visibleMetrics, snapshot: snapshot, running: true)
        }
        checkingDisplayScope = false
        let all = MenuBarMetric.allCases
        update(metrics: all, snapshot: snapshot, running: true)
        restoreDefaultPosition(); settlePlacement()
        try verifyCurrentDisplay()
        let identity = ObjectIdentifier(statusItem)
        let length = statusItem.length
        for value in [0.0, 9, 99, 100, 9_999, 999_999_999] {
            var changing = snapshot; changing.cpu = min(value, 100); changing.upload = value; changing.download = value
            update(metrics: all, snapshot: changing, running: true)
            guard ObjectIdentifier(statusItem) == identity, statusItem.length == length else { throw UserFacingError("Smoke: sampling recreated or resized the metric group") }
        }
        update(metrics: all, snapshot: snapshot, running: true)
        try readings.values.map(\.tooltip).joined(separator: "\n\n").write(to: destination.appendingPathComponent("menu-bar-live.txt"), atomically: true, encoding: .utf8)
        checkingDisplayScope = true
        try displayScope.verifyAndExport(destination: destination)
        if ProcessInfo.processInfo.arguments.contains("--menu-bar-notch-check") {
            try MenuBarPlacementSmokeChecks.run(item: statusItem, scope: displayScope, destination: destination)
        }
        checkingDisplayScope = false
        update(metrics: all, snapshot: snapshot, running: true)
        try verifyInternalInteraction(snapshot: snapshot)
        try verifyNeighborOrder(snapshot: snapshot)
        if ProcessInfo.processInfo.arguments.contains("--menu-bar-display-mode-check") {
            try verifyDisplayModes(preferences: preferences, destination: destination)
        }
        restoreDefaultPosition(); settlePlacement()
        try MenuBarRenderingSmokeChecks.run(destination: destination)
        try verifyCurrentDisplay()
        print("PASS: one contiguous native metric group; toolbox only when all off; internal mouse/Cmd reorder; stable order across toggles; no app interleaving; fixed reading widths")
    }
    private func verifyInternalInteraction(snapshot: MonitorSnapshot) throws {
        guard let button = statusItem.button, let window = button.window else { throw UserFacingError("Smoke: metric interaction window missing") }
        let click = interaction.click
        var clicks: [Bool] = []; interaction.click = { clicks.append($0) }
        defer { interaction.click = click }
        func event(_ type: NSEvent.EventType, metric: MenuBarMetric, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
            guard let column = interaction.columns.first(where: { $0.metric == metric }) else { throw UserFacingError("Smoke: drag column missing") }
            let origin = button.cell?.imageRect(forBounds: button.bounds).minX ?? 0
            let location = interaction.convert(NSPoint(x: origin + column.x + column.width / 2, y: interaction.bounds.midY), to: nil)
            guard let event = NSEvent.mouseEvent(with: type, location: location, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1) else { throw UserFacingError("Smoke: own-window drag event missing") }
            return event
        }
        // Feed the exact handler used by the local event monitor, in this own
        // status window; do not synthesize global mouse/keyboard input.
        let beforeCommandDrag = preferences.visibleMetrics
        guard let cpuTarget = beforeCommandDrag.firstIndex(of: .cpu) else { throw UserFacingError("Smoke: CPU target missing") }
        interaction.handle(try event(.leftMouseDown, metric: .network, flags: .command), showCursor: false)
        interaction.handle(try event(.leftMouseDragged, metric: .cpu, flags: .command), showCursor: false)
        interaction.handle(try event(.leftMouseUp, metric: .cpu, flags: .command), showCursor: false)
        update(metrics: preferences.visibleMetrics, snapshot: snapshot, running: true)
        guard preferences.visibleMetrics[cpuTarget] == .network,
              preferences.visibleMetrics.filter({ $0 != .network }) == beforeCommandDrag.filter({ $0 != .network }),
              interaction.visibleMetrics == preferences.visibleMetrics, clicks.isEmpty else { throw UserFacingError("Smoke: Cmd drag failed internal reorder or opened the panel") }
        let beforeDirectDrag = preferences.visibleMetrics
        guard let memoryTarget = beforeDirectDrag.firstIndex(of: .memory) else { throw UserFacingError("Smoke: memory target missing") }
        interaction.handle(try event(.leftMouseDown, metric: .fan), showCursor: false)
        interaction.handle(try event(.leftMouseDragged, metric: .memory), showCursor: false)
        interaction.handle(try event(.leftMouseUp, metric: .memory), showCursor: false)
        interaction.handle(try event(.rightMouseDown, metric: .memory), showCursor: false)
        update(metrics: preferences.visibleMetrics, snapshot: snapshot, running: true)
        guard preferences.visibleMetrics[memoryTarget] == .fan,
              preferences.visibleMetrics.filter({ $0 != .fan }) == beforeDirectDrag.filter({ $0 != .fan }),
              interaction.visibleMetrics == preferences.visibleMetrics, clicks.isEmpty else { throw UserFacingError("Smoke: direct drag failed internal reorder") }
        let wanted = preferences.visibleMetrics
        for metric in [MenuBarMetric.memory, .cpu, .network] {
            preferences.set(metric, enabled: false)
            update(metrics: preferences.visibleMetrics, snapshot: snapshot, running: true)
            preferences.set(metric, enabled: true)
            update(metrics: preferences.visibleMetrics, snapshot: snapshot, running: true)
            guard interaction.visibleMetrics == wanted else { throw UserFacingError("Smoke: metric toggle scrambled internal order") }
        }
        interaction.handle(try event(.leftMouseDown, metric: .memory), showCursor: false)
        interaction.handle(try event(.leftMouseUp, metric: .memory), showCursor: false)
        interaction.handle(try event(.rightMouseUp, metric: .memory), showCursor: false)
        guard clicks == [false, true] else { throw UserFacingError("Smoke: group left/right clicks failed") }
        update(metrics: [], snapshot: snapshot, running: true)
        guard interaction.visibleMetrics.isEmpty, interaction.columns.count == 1, interaction.columns.first?.metric == nil, statusItem.length == 16 else { throw UserFacingError("Smoke: all-off toolbox failed") }
        update(metrics: wanted, snapshot: snapshot, running: true)
        guard interaction.columns.allSatisfy({ $0.metric != nil }) else { throw UserFacingError("Smoke: toolbox still visible with metrics") }
    }
    private func verifyNeighborOrder(snapshot: MonitorSnapshot) throws {
        checkingDisplayScope = true
        let name = "iTools.group-neighbors." + UUID().uuidString
        UserDefaults.standard.set(0, forKey: "NSStatusItem Preferred Position " + name + ".a")
        UserDefaults.standard.set(40, forKey: "NSStatusItem Preferred Position " + name + ".b")
        let a = MenuBarDisplayScope.makeStatusItem(length: 20), b = MenuBarDisplayScope.makeStatusItem(length: 20)
        a.autosaveName = name + ".a"; b.autosaveName = name + ".b"; a.button?.title = "•"; b.button?.title = "•"
        _ = it_primary_status_item_set_position(Unmanaged.passUnretained(a).toOpaque(), 0)
        _ = it_primary_status_item_set_position(Unmanaged.passUnretained(b).toOpaque(), 40)
        let scopeA = MenuBarDisplayScope(item: a, initializeOnLeft: false), scopeB = MenuBarDisplayScope(item: b, initializeOnLeft: false)
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.4)) }
        defer {
            scopeA.stop(); scopeB.stop()
            a.isVisible = false; b.isVisible = false
            NSStatusBar.system.removeStatusItem(a); NSStatusBar.system.removeStatusItem(b)
            settle()
            checkingDisplayScope = false
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.contains(name) { UserDefaults.standard.removeObject(forKey: key) }
        }
        settle()
        func orderedNeighbors() -> [Int] {
            [a, b].compactMap { item -> (Int, CGFloat)? in
                guard let button = item.button, let window = button.window, let frame = MenuBarDisplayScope.buttonScreenRect(button) else { return nil }
                return (window.windowNumber, frame.minX)
            }.sorted { $0.1 < $1.1 }.map { $0.0 }
        }
        let wanted = orderedNeighbors()
        let slot = ObjectIdentifier(statusItem), autosave = statusItem.autosaveName
        let order = preferences.visibleMetrics
        for metrics in [order, [.cpu], [.memory, .network], [], order] {
            checkingDisplayScope = false; update(metrics: metrics, snapshot: snapshot, running: true); checkingDisplayScope = true; settle()
            guard orderedNeighbors() == wanted, ObjectIdentifier(statusItem) == slot, statusItem.autosaveName == autosave else { throw UserFacingError("Smoke: toggles changed the native slot or neighbor order") }
            guard interaction.columns.filter({ $0.metric != nil }).count == metrics.count else { throw UserFacingError("Smoke: noncontiguous metric content") }
        }
        print("PASS: metrics toggle inside the same native slot; neighboring application-item order unchanged while group width contracts/expands")
    }
    deinit { stop() }
}
