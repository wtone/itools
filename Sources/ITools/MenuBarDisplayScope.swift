import AppKit
import ObjectiveC
import SystemBridge
import IToolsCore

/// A native status item confined to the system primary display. AppKit has no public
/// per-display replication switch. A checked compatibility callback keeps the
/// public factory, AppKit observation, and native status-bar layout intact.
final class MenuBarDisplayScope {
    private let item: NSStatusItem
    private let confined: Bool
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var timer: Timer?
    private var scheduled = false
    private var active = true
    private var validating = false
    private var invalidPlacementSince: Date?
    private var repairedInvalidPlacement = false
    private var defaultPlacementPending: Bool
    private let placementRecovery: (() -> Bool)?
    private struct LeftPlacement {
        var low: Double = 0
        var high: Double
        var candidate: Double
        var checkedZero = false
        var attempts = 0
        var changedAt = Date()
        let screenID: UInt32?
        let length: CGFloat
    }
    private var leftPlacement: LeftPlacement?

    static var isSupported: Bool { it_primary_status_item_supported() != 0 }
    static func makeStatusItem(length: CGFloat) -> NSStatusItem {
        if let pointer = it_primary_status_item_create(length) {
            return Unmanaged<NSStatusItem>.fromOpaque(pointer).takeRetainedValue()
        }
        return NSStatusBar.system.statusItem(withLength: length)
    }
    @discardableResult static func prepareAutosave(_ name: String) -> Bool {
        let key = "NSStatusItem Preferred Position " + name
        guard let screen = NSScreen.screens.first else { return true }
        if let saved = UserDefaults.standard.object(forKey: key) as? NSNumber,
           MenuBarPlacement.isSavedPositionUsable(saved.doubleValue, screen: screen.frame, rightArea: screen.auxiliaryTopRightArea) { return false }
        UserDefaults.standard.set(0, forKey: key)
        return true
    }

    static func isPrimaryScreen(_ point: NSPoint) -> Bool { NSScreen.screens.first?.frame.contains(point) == true }
    static func buttonScreenRect(_ button: NSStatusBarButton, includeWindowFrame: Bool = false) -> NSRect? {
        guard let window = button.window else { return nil }
        // Confinement can leave AppKit's cached frame on the formerly active bar.
        // Anchor menus to this app's actual compositor window, using screen points.
        let info = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(window.windowNumber)) as? [[String: Any]]
        if let entry = info?.first(where: { $0[kCGWindowNumber as String] as? Int == window.windowNumber }),
           let dictionary = entry[kCGWindowBounds as String] as? NSDictionary,
           let bounds = CGRect(dictionaryRepresentation: dictionary), let primary = NSScreen.screens.first {
            if includeWindowFrame {
                return NSRect(x: bounds.minX, y: primary.frame.maxY - bounds.maxY, width: bounds.width, height: bounds.height)
            }
            let local = button.convert(button.bounds, to: nil)
            return NSRect(x: bounds.minX + local.minX, y: primary.frame.maxY - bounds.maxY + local.minY,
                          width: local.width, height: local.height)
        }
        return includeWindowFrame ? window.frame : window.convertToScreen(button.convert(button.bounds, to: nil))
    }
    static func isWindowOnScreen(_ button: NSStatusBarButton) -> Bool {
        guard let window = button.window else { return false }
        let records = CGWindowListCopyWindowInfo(.optionIncludingWindow, CGWindowID(window.windowNumber)) as? [[String: Any]]
        return records?.first(where: { $0[kCGWindowNumber as String] as? Int == window.windowNumber })?[kCGWindowIsOnscreen as String] as? Bool == true
    }
    private static func screenID(_ screen: NSScreen?) -> UInt32? {
        (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
    private static func identifier(_ screen: NSScreen) -> String? {
        guard let id = screenID(screen), let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid) else { return nil }
        return string as String
    }

    init(item: NSStatusItem, initializeOnLeft: Bool, placementRecovery: (() -> Bool)? = nil) {
        self.item = item
        self.placementRecovery = placementRecovery
        defaultPlacementPending = initializeOnLeft
        confined = it_primary_status_item_is_confined(Unmanaged.passUnretained(item).toOpaque()) != 0
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.refresh() })
        observers.append(center.addObserver(forName: NSWindow.didChangeScreenNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self = self, let window = notification.object as? NSWindow, window === self.item.button?.window else { return }
            self.scheduleRefresh()
        })
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            workspaceObservers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.scheduleRefresh() })
        }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 0.2; self.timer = timer; RunLoop.main.add(timer, forMode: .common)
        refresh()
    }

    func refresh() {
        guard active, !validating else { return }
        // NSScreen.main follows keyboard focus; screens.first identifies the system primary.
        apply(screen: NSScreen.screens.first)
    }

    private func apply(screen: NSScreen?) {
        guard let screen = screen else { item.isVisible = false; return }
        guard confined, let identifier = Self.identifier(screen) else {
            // Fail closed on unsupported macOS versions: no invisible secondary slots.
            // Single-screen machines can still use the ordinary public status item.
            item.isVisible = NSScreen.screens.count == 1
            return
        }
        // Visibility installs the native entry; confine it after installation.
        if !item.isVisible { item.isVisible = true }
        let pinned = identifier.withCString { it_primary_status_item_pin(Unmanaged.passUnretained(item).toOpaque(), $0) != 0 }
        guard pinned else { item.isVisible = false; return }
        // AppKit can retain visible=true while a rapid resize has ordered the
        // backing window out of the compositor. Recover only this original
        // primary window, after its real bounds are safe and the bar is shown.
        if NSMenu.menuBarVisible(), NSEvent.pressedMouseButtons == 0,
           let button = item.button, let window = button.window,
           let frame = Self.buttonScreenRect(button, includeWindowFrame: true),
           MenuBarPlacement.isFrameVisible(frame, screen: screen.frame, rightArea: screen.auxiliaryTopRightArea),
           !Self.isWindowOnScreen(button) {
            window.orderOut(nil); window.orderFrontRegardless()
        }
        // Wait for MenuBarMonitor to apply the final reading width. Keep valid
        // Cmd-drag positions; the old rightmost default (0) initializes on the left.
        if defaultPlacementPending, item.length != NSStatusItem.variableLength,
           item.button?.image != nil {
            defaultPlacementPending = false
            restoreDefaultPosition(on: screen)
        }
        if leftPlacement != nil { advanceLeftPlacement(on: screen); return }
        recoverPlacementIfNeeded(on: screen)
    }

    private func recoverPlacementIfNeeded(on screen: NSScreen) {
        guard !validating else { return }
        guard NSMenu.menuBarVisible() else { invalidPlacementSince = nil; return }
        // Never fight a Cmd-drag in progress. Wait for a stable invalid placement
        // so asynchronous native screen/width changes have time to settle.
        guard NSEvent.pressedMouseButtons == 0 else {
            invalidPlacementSince = nil; repairedInvalidPlacement = false; return
        }
        guard let button = item.button, let frame = Self.buttonScreenRect(button, includeWindowFrame: true) else { return }
        if MenuBarPlacement.isFrameVisible(frame, screen: screen.frame, rightArea: screen.auxiliaryTopRightArea), Self.isWindowOnScreen(button) {
            invalidPlacementSince = nil; repairedInvalidPlacement = false; return
        }
        guard !repairedInvalidPlacement else { return }
        let now = Date()
        guard let since = invalidPlacementSince else { invalidPlacementSince = now; return }
        guard now.timeIntervalSince(since) >= 0.8 else { return }
        repairedInvalidPlacement = true
        if let placementRecovery {
            if !placementRecovery() { repairedInvalidPlacement = false; invalidPlacementSince = nil }
        } else { restoreDefaultPosition(on: screen) }
    }

    private func installPosition(_ position: Double) -> Bool {
        let installed = it_primary_status_item_set_position(Unmanaged.passUnretained(item).toOpaque(), position) != 0
        if installed {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in self?.refresh() }
        }
        return installed
    }
    /// Preferred positions are native insertion points, not exact x coordinates.
    /// Let each relayout finish before measuring this item's compositor window.
    func restoreDefaultPosition(on screen: NSScreen) {
        guard NSMenu.menuBarVisible() else { defaultPlacementPending = true; leftPlacement = nil; return }
        let high = max(0, Double((screen.auxiliaryTopRightArea ?? screen.frame).width) - 1)
        leftPlacement = LeftPlacement(high: high, candidate: high, screenID: Self.screenID(screen), length: item.length)
        if !installPosition(high) { leftPlacement = nil }
    }
    private func advanceLeftPlacement(on screen: NSScreen) {
        guard var search = leftPlacement else { return }
        guard NSMenu.menuBarVisible() else { defaultPlacementPending = true; leftPlacement = nil; return }
        // Ordinary clicks elsewhere must not cancel calibration at an invisible
        // intermediate slot. Only a Cmd-drag on this status item takes control.
        if NSEvent.pressedMouseButtons != 0, NSEvent.modifierFlags.contains(.command),
           let button = item.button, let frame = Self.buttonScreenRect(button, includeWindowFrame: true),
           frame.contains(NSEvent.mouseLocation) {
            leftPlacement = nil; return
        }
        if search.screenID != Self.screenID(screen) || search.length != item.length {
            restoreDefaultPosition(on: screen); return
        }
        guard Date().timeIntervalSince(search.changedAt) >= 0.3,
              let frame = item.button.flatMap({ Self.buttonScreenRect($0, includeWindowFrame: true) }) else { return }
        let visible = MenuBarPlacement.isFrameVisible(frame, screen: screen.frame, rightArea: screen.auxiliaryTopRightArea) && item.button.map(Self.isWindowOnScreen) == true
        if ProcessInfo.processInfo.arguments.contains("--smoke-test") {
            print("PLACEMENT candidate=\(search.candidate) low=\(search.low) high=\(search.high) frame=\(frame) visible=\(visible)")
        }
        if visible { search.low = search.candidate }
        else { search.high = search.candidate }
        search.attempts += 1
        if (visible && search.candidate == search.high) || search.high - search.low < 2 || search.attempts >= 11 {
            leftPlacement = nil
            if !visible { _ = installPosition(search.low) }
            invalidPlacementSince = nil; repairedInvalidPlacement = false
            return
        }
        if !visible && !search.checkedZero {
            search.checkedZero = true; search.candidate = 0
        } else {
            search.candidate = (search.low + search.high) / 2
        }
        search.changedAt = Date(); leftPlacement = search
        if !installPosition(search.candidate) {
            if ProcessInfo.processInfo.arguments.contains("--smoke-test") { print("PLACEMENT installation rejected at \(search.candidate)") }
            leftPlacement = nil
        }
    }

    private func scheduleRefresh() {
        guard active, !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.scheduled = false; self.refresh()
        }
    }

    func stop() {
        guard active else { return }
        active = false; timer?.invalidate(); timer = nil; leftPlacement = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }; observers.removeAll()
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }; workspaceObservers.removeAll()
        // The owner removes the item or exits. Do not persist a hidden-item
        // preference merely because monitoring/observation is being torn down.
    }

    func setVisibilityForCheck(_ visible: Bool) {
        validating = true
        apply(screen: visible ? NSScreen.screens.first : nil)
        if visible {
            let saved = item.autosaveName.map { UserDefaults.standard.double(forKey: "NSStatusItem Preferred Position " + $0) } ?? 0
            _ = installPosition(saved)
        }
    }
    func finishVisibilityCheck() { validating = false; refresh() }

    func verifyCurrentDisplay(expectedItemCount: Int = 1) throws {
        guard let primary = NSScreen.screens.first, let button = item.button, let window = button.window,
              item.isVisible, window.alphaValue == 1, !window.ignoresMouseEvents else {
            throw UserFacingError("Smoke: primary status item is unavailable during live refresh")
        }
        let info = (CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? [])
            .filter { $0[kCGWindowOwnerPID as String] as? Int32 == ProcessInfo.processInfo.processIdentifier &&
                $0[kCGWindowLayer as String] as? Int == NSWindow.Level.statusBar.rawValue }
        let own = info.first { $0[kCGWindowNumber as String] as? Int == window.windowNumber }
        guard info.count == expectedItemCount, let own,
              (own[kCGWindowAlpha as String] as? NSNumber)?.doubleValue == 1,
              let dictionary = own[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: dictionary), bounds.minY == 0,
              primary.frame.maxX >= bounds.maxX, bounds.minX >= primary.frame.minX,
              MenuBarPlacement.isFrameVisible(bounds, screen: primary.frame, rightArea: primary.auxiliaryTopRightArea),
              let anchor = Self.buttonScreenRect(button), primary.frame.contains(anchor) else {
            let allOwn = (CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []).filter {
                $0[kCGWindowOwnerPID as String] as? Int32 == ProcessInfo.processInfo.processIdentifier &&
                $0[kCGWindowLayer as String] as? Int == NSWindow.Level.statusBar.rawValue
            }
            var registry = "unavailable"
            if let ivar = class_getInstanceVariable(NSStatusItem.self, "_cgsItem"), let root = object_getIvar(item, ivar) as? NSObject {
                registry = "class=\(type(of: root)) installed=\(root.value(forKey: "installed") as Any) preferred=\(root.value(forKey: "preferredPosition") as Any) display=\(root.value(forKey: "confiningDisplayID") as Any)"
            }
            throw UserFacingError("Smoke: live refresh lost primary placement or recreated a secondary menu-bar target; onScreen=\(info), allOwn=\(allOwn), registry=\(registry), windowVisible=\(window.isVisible) appHidden=\(NSApp.isHidden), button=\(Self.buttonScreenRect(button) as Any)")
        }
        guard let frame = Self.buttonScreenRect(button),
              MenuBarPlacement.isFrameVisible(frame, screen: primary.frame, rightArea: primary.auxiliaryTopRightArea) else {
            throw UserFacingError("Smoke: menu bar readings overlap the notch or extend outside the primary display")
        }
    }

    func verifyAndExport(destination: URL) throws {
        guard confined, let primary = NSScreen.screens.first, let primaryID = Self.screenID(primary),
              let root = item.button?.window else { throw UserFacingError("Smoke: native primary-only status item is unavailable (ABI=\(Self.isSupported), class=\(type(of: item)), window=\(item.button?.window != nil))") }
        validating = true
        let originalLength = item.length
        let originalAutosave = item.autosaveName
        let testName = "iTools.display-check." + UUID().uuidString
        let witnessName = testName + ".neighbor"
        UserDefaults.standard.set(0, forKey: "NSStatusItem Preferred Position " + testName)
        UserDefaults.standard.set(originalLength + 16, forKey: "NSStatusItem Preferred Position " + witnessName)
        item.autosaveName = testName
        item.length = 80
        // A normal neighboring status item is a layout witness on every real display.
        // Compare with iTools absent: secondary slots must neither move nor reserve width.
        let existing = Set(NSApp.windows.map(\.windowNumber))
        let witness = NSStatusBar.system.statusItem(withLength: 20)
        witness.autosaveName = witnessName
        witness.button?.title = "•"
        func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.4)) }
        func placeForCheck(on screen: NSScreen) {
            apply(screen: screen)
            // A new autosave name can change a registry value without moving
            // its existing compositor slot. Explicitly install the test slot.
            _ = installPosition(0)
            settle()
        }
        defer {
            NSStatusBar.system.removeStatusItem(witness); item.length = originalLength
            item.autosaveName = originalAutosave
            apply(screen: primary)
            validating = false
            restoreDefaultPosition(on: primary)
            let deadline = Date().addingTimeInterval(6)
            while Date() < deadline && leftPlacement != nil {
                refresh(); RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.contains(testName) { UserDefaults.standard.removeObject(forKey: key) }
        }
        settle()
        let witnessWindows = NSApp.windows.filter { !existing.contains($0.windowNumber) && $0.level == .statusBar }
        guard witnessWindows.count == NSScreen.screens.count else { throw UserFacingError("Smoke: native layout witness missing a display") }
        let witnessIDs = Set(witnessWindows.map(\.windowNumber))
        apply(screen: nil); settle()
        let baseline = Dictionary(uniqueKeysWithValues: witnessWindows.map { ($0.windowNumber, $0.frame) })
        placeForCheck(on: primary)
        func activeItemInfo() -> [[String: Any]] {
            (CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? [])
                .filter { $0[kCGWindowOwnerPID as String] as? Int32 == ProcessInfo.processInfo.processIdentifier &&
                    $0[kCGWindowLayer as String] as? Int == NSWindow.Level.statusBar.rawValue &&
                    !witnessIDs.contains($0[kCGWindowNumber as String] as? Int ?? -1) }
        }
        @discardableResult func check(screen: NSScreen) throws -> CGRect {
            guard root.alphaValue == 1, !root.ignoresMouseEvents else { throw UserFacingError("Smoke: primary status item lost rendering or mouse input") }
            for window in witnessWindows where Self.screenID(window.screen) != Self.screenID(screen) {
                guard window.frame == baseline[window.windowNumber] else { throw UserFacingError("Smoke: iTools still reserves secondary menu-bar layout space") }
            }
            let info = activeItemInfo()
            guard info.count == 1, info.first?[kCGWindowNumber as String] as? Int == root.windowNumber,
                  (info.first?[kCGWindowAlpha as String] as? NSNumber)?.doubleValue == 1,
                  let dictionary = info.first?[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dictionary) else {
                throw UserFacingError("Smoke: expected one visible original status item on selected display; root=\(root.frame), own=\(info)")
            }
            // NSWindow.screen can retain AppKit's active-display ID after confinement.
            // The WindowServer bounds are the actual display and clickable position.
            let quartzScreen = CGRect(x: screen.frame.minX, y: primary.frame.maxY - screen.frame.maxY,
                                      width: screen.frame.width, height: screen.frame.height)
            guard quartzScreen.contains(bounds), abs(bounds.minY - quartzScreen.minY) < 1,
                  let nativeHeight = witnessWindows.first(where: { Self.screenID($0.screen) == Self.screenID(screen) })?.frame.height,
                  abs(bounds.height - nativeHeight) < 1 else { throw UserFacingError("Smoke: primary status item has the wrong display or native menu-bar height") }
            return bounds
        }
        let before = try check(screen: primary)
        item.length = 128; placeForCheck(on: primary)
        let after = try check(screen: primary)
        // A wider item grows to the left from its native right anchor. A neighbor
        // to its right legitimately stays still; it is not a width witness here.
        guard abs(after.width - before.width - 48) < 1, abs(after.maxX - before.maxX) < 1 else {
            throw UserFacingError("Smoke: primary status item lost native width/position layout: before=\(before), after=\(after)")
        }
        item.length = 80; placeForCheck(on: primary)
        // Exercise the real display setter and native relayout without modifying macOS
        // preferences. Every nonselected display must return to the absent-item baseline.
        for screen in NSScreen.screens { placeForCheck(on: screen); try check(screen: screen) }
        apply(screen: nil); settle()
        guard activeItemInfo().isEmpty, witnessWindows.allSatisfy({ $0.frame == baseline[$0.windowNumber] }) else { throw UserFacingError("Smoke: missing-display fallback retained status item slots") }
        placeForCheck(on: primary); try check(screen: primary)
        let lines = NSScreen.screens.map { screen in
            "display=\(Self.screenID(screen) ?? 0) primary=\(primaryID) installedItems=\(Self.screenID(screen) == primaryID ? 1 : 0) secondaryReservedWidth=0 secondaryClickTargets=0"
        }
        try lines.joined(separator: "\n").write(to: destination.appendingPathComponent("menu-bar-displays.txt"), atomically: true, encoding: .utf8)
        print("PASS: one native status item on primary; no secondary WindowServer item, tooltip/click target or reserved layout width; native primary layout, resizing, display switch and missing-display recovery")
    }

    deinit { stop() }
}
