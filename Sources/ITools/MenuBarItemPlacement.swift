import AppKit
import SystemBridge
import IToolsCore

/// Native autosave positions remain authoritative. This only places a new group,
/// or brings an obscured group back into the primary display's usable area.
final class MenuBarItemPlacement {
    private struct Search {
        let items: [NSStatusItem] // left to right
        let screen: NSScreen
        var low: Double = 0
        var high: Double
        var candidate: Double
        var checkedZero = false
        var attempts = 0
        var changedAt = Date()
    }
    private var search: Search?
    private var timer: Timer?
    var isPlacing: Bool { search != nil }

    static func savedPosition(of item: NSStatusItem) -> Double? {
        guard let name = item.autosaveName,
              let number = UserDefaults.standard.object(forKey: "NSStatusItem Preferred Position " + name) as? NSNumber,
              number.doubleValue.isFinite, number.doubleValue >= 0 else { return nil }
        return number.doubleValue
    }
    static func savedOrder(_ items: [NSStatusItem]) -> [NSStatusItem] {
        items.enumerated().sorted { a, b in
            let left = savedPosition(of: a.element) ?? 0, right = savedPosition(of: b.element) ?? 0
            return left == right ? a.offset < b.offset : left > right
        }.map(\.element)
    }
    func restore(_ items: [NSStatusItem], on screen: NSScreen) {
        guard MenuBarDisplayScope.isSupported, NSMenu.menuBarVisible(), !items.isEmpty else { return }
        stop()
        let high = max(0, Double((screen.auxiliaryTopRightArea ?? screen.frame).width) - 1)
        search = Search(items: items, screen: screen, high: high, candidate: high)
        guard install() else { stop(); return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in self?.advance() }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func install() -> Bool {
        guard var state = search else { return false }
        // A native status window includes 8 points of padding on each side.
        // Each reading uses its content width without additional custom padding.
        var position = state.candidate
        var objects: [UnsafeMutableRawPointer?] = []
        var positions: [Double] = []
        for item in state.items.reversed() {
            objects.append(Unmanaged.passUnretained(item).toOpaque()); positions.append(position)
            position += Double(item.length + 16)
        }
        guard it_primary_status_items_set_positions(&objects, &positions, Int32(objects.count)) != 0 else { return false }
        state.changedAt = Date(); search = state
        return true
    }
    private func advance() {
        guard var state = search else { return }
        guard NSMenu.menuBarVisible() else { stop(); return }
        // Native Cmd-drag takes over immediately, including a drag off this group.
        if NSEvent.pressedMouseButtons != 0 && NSEvent.modifierFlags.contains(.command) { stop(); return }
        guard Date().timeIntervalSince(state.changedAt) >= 0.45 else { return }
        guard NSScreen.screens.first?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber == state.screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { stop(); return }
        let visible = state.items.allSatisfy { item in
            guard let button = item.button, let frame = MenuBarDisplayScope.buttonScreenRect(button, includeWindowFrame: true) else { return false }
            return MenuBarPlacement.isFrameVisible(frame, screen: state.screen.frame, rightArea: state.screen.auxiliaryTopRightArea)
                && MenuBarDisplayScope.isWindowOnScreen(button)
        }
        if ProcessInfo.processInfo.arguments.contains("--smoke-test") {
            print("GROUP PLACEMENT candidate=\(state.candidate) visible=\(visible) items=\(state.items.count)")
            if !visible {
                for item in state.items {
                    print("GROUP ITEM \(item.autosaveName ?? "") frame=\(item.button.flatMap { MenuBarDisplayScope.buttonScreenRect($0, includeWindowFrame: true) } as Any) onscreen=\(item.button.map(MenuBarDisplayScope.isWindowOnScreen) as Any)")
                }
            }
        }
        if visible { state.low = state.candidate } else { state.high = state.candidate }
        state.attempts += 1
        if (visible && state.candidate == state.high) || state.high - state.low < 2 || state.attempts >= 11 {
            if !visible { state.candidate = state.low; search = state; _ = install() }
            stop(); return
        }
        if !visible && !state.checkedZero { state.checkedZero = true; state.candidate = 0 }
        else { state.candidate = (state.low + state.high) / 2 }
        search = state
        if !install() { stop() }
    }
    func stop() { timer?.invalidate(); timer = nil; search = nil }
    deinit { stop() }
}
