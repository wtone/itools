import AppKit
import SwiftUI
import Combine
import IToolsCore

final class QuickPanelController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let panel = StatusQuickPanel()
    private var presentation: MenuPanelPlacement?
    private var localEvents: Any?
    private var outsideEvents: Any?
    private var trackingMenus = 0
    private var notifications = Set<AnyCancellable>()
    private var errorSubscription: AnyCancellable?
    init(model: AppModel) {
        self.model = model
        super.init(); panel.delegate = self
        errorSubscription = NoticeCenter.shared.$error.dropFirst().compactMap { $0 }
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.close(); self?.model.showWindow?() }
        // A changed display arrangement or Space invalidates the snapshot. Close once; never chase screens.
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.close() }.store(in: &notifications)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.close() }.store(in: &notifications)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.close() }.store(in: &notifications)
        NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)
            .sink { [weak self] _ in self?.trackingMenus += 1 }.store(in: &notifications)
        NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.trackingMenus = max(0, self.trackingMenus - 1)
                self.closeIfFocusLeft()
            }.store(in: &notifications)
    }
    var isShown: Bool { panel.isVisible }
    func toggle(relativeTo button: NSStatusBarButton, fromClick: Bool = true) {
        if isShown { close(); return }
        // Capture the pointer before refresh/focus changes. A mirrored status item's window.screen is not reliable.
        let pointer = NSEvent.mouseLocation
        let buttonRect = fromClick ? MenuBarDisplayScope.buttonScreenRect(button) : nil
        guard let placement = MenuPanelPlacement.resolve(pointer: pointer, screens: Self.screens, buttonRect: buttonRect) else { return }
        show(at: placement)
    }
    private static var screens: [MenuPanelScreen] {
        NSScreen.screens.map { screen in
            MenuPanelScreen(id: (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0,
                            frame: screen.frame, visibleFrame: screen.visibleFrame)
        }
    }
    private func show(at placement: MenuPanelPlacement) {
        presentation = placement
        model.quickSystem.refresh()
        panel.contentView = NSHostingView(rootView: StatusPanelChrome(placement: placement, content: view(includesBackground: false)))
        panel.setFrame(placement.frame, display: false)
        panel.makeKeyAndOrderFront(nil)
        installEventMonitors()
    }
    func close() {
        if let localEvents = localEvents { NSEvent.removeMonitor(localEvents) }; localEvents = nil
        if let outsideEvents = outsideEvents { NSEvent.removeMonitor(outsideEvents) }; outsideEvents = nil
        presentation = nil; panel.orderOut(nil)
    }
    private func installEventMonitors() {
        guard localEvents == nil else { return }
        localEvents = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            guard let self = self, self.isShown else { return event }
            if event.type == .keyDown {
                if event.keyCode == 53 && self.panel.isKeyWindow { self.close(); return nil }
            } else if let window = event.window, window != self.panel, window.level.rawValue < NSWindow.Level.statusBar.rawValue {
                self.close()
            }
            // Let status buttons toggle the panel themselves, and let native popup menus finish their actions.
            return event
        }
        outsideEvents = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in self?.close() }
    }
    func windowDidResignKey(_ notification: Notification) {
        closeIfFocusLeft()
    }
    private func closeIfFocusLeft() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isShown, !self.panel.isKeyWindow, self.trackingMenus == 0 else { return }
            self.close()
        }
    }
    private func afterClosing(_ action: @escaping () -> Void) {
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: action)
    }
    private func navigate(_ page: ToolPage) { close(); model.navigate(page) }
    private func view(includesBackground: Bool = true) -> QuickPanelView {
        QuickPanelView(model: model, monitor: model.monitor, preferences: model.quickPanel, system: model.quickSystem,
                       awake: model.awake, recorder: model.recorder, clipboard: model.clipboard,
                       run: { [weak self] in self?.perform($0) },
                       openSystem: { [weak self] shortcut in self?.afterClosing { self?.model.quickSystem.open(shortcut) } },
                       navigate: { [weak self] in self?.navigate($0) }, close: { [weak self] in self?.close() },
                       quit: { [weak self] in self?.close(); NSApp.terminate(nil) },
                       stopRecording: { [weak self] in self?.afterClosing { self?.model.recorder.stop() } },
                       includesBackground: includesBackground)
    }
    func perform(_ action: QuickAction) {
        if action == .awake {
            if model.awake.active { model.awake.stop() } else { model.awake.start(minutes: 30, keepDisplay: false) }; return
        }
        if action == .keepDisplay {
            if model.awake.active && model.awake.keepsDisplay { model.awake.stop() } else { model.awake.start(minutes: 30, keepDisplay: true) }; return
        }
        if action == .desktopCover { model.quickSystem.toggleDesktopCover(); return }
        afterClosing { [weak self] in
            guard let self = self else { return }
            let model = self.model
            switch action {
            case .darkMode: model.quickSystem.toggleDark()
            case .lockScreen: model.quickSystem.lockScreen()
            case .screenSaver: model.quickSystem.screenSaver()
            case .cleanScreen: model.cleaning.start(keyboardOnly: false)
            case .cleanKeyboard: model.cleaning.start(keyboardOnly: true)
            case .dockAutoHide: model.quickSystem.toggleDock()
            case .menuBarAutoHide: model.quickSystem.toggleMenuBar()
            case .screenshot: model.takeScreenshot()
            case .ocr: model.takeScreenshot(ocr: true)
            case .clipboard: model.showClipboard?(false)
            case .files: model.navigate(.files)
            case .displaySettings: model.quickSystem.openPreferences("com.apple.preference.displays")
            case .leftWindow: model.windows.apply(.left)
            case .rightWindow: model.windows.apply(.right)
            case .maximize: model.windows.apply(.maximize)
            case .restoreWindow: model.windows.restore()
            case .colorPicker: if model.captureEnabled { model.capture.pickColor() }
            case .recording: model.navigate(.capture)
            case .emptyTrash: model.quickSystem.emptyTrash()
            case .dockSettings: model.quickSystem.openPreferences("com.apple.preference.dock")
            case .awake, .keepDisplay, .desktopCover: break
            }
        }
    }
    /// Render only our own views; never executes a quick action or modifies system preferences.
    func verifyScreenStability(destination: URL, completion: @escaping (Error?) -> Void) {
        let screens = Self.screens
        guard !screens.isEmpty else { completion(UserFacingError("Smoke: no connected display")); return }
        let mainFrames = NSApp.windows.filter { $0.canBecomeMain }.map { ($0, $0.frame) }
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let initialSnapshot = model.monitor.snapshot
        var screenIndex = 0
        func nextScreen() {
            guard screenIndex < screens.count else {
                self.model.monitor.snapshot = initialSnapshot
                print("PASS: stable native panel on all \(screens.count) connected displays during repeated live content refreshes; no main-window movement or app activation")
                completion(nil); return
            }
            let screen = screens[screenIndex]
            // Use a deliberately stale primary-screen anchor for secondary displays.
            let primary = screens[0]
            let replica = CGRect(x: primary.frame.maxX - 200, y: primary.frame.maxY - 24, width: 40, height: 24)
            guard let placement = MenuPanelPlacement.resolve(pointer: CGPoint(x: screen.frame.midX, y: screen.frame.maxY - 8),
                                                            screens: screens, buttonRect: replica) else {
                completion(UserFacingError("Smoke: display placement failed")); return
            }
            self.show(at: placement)
            var ticks = 0
            func check() {
                do {
                    let screenID = (self.panel.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
                    guard self.isShown, self.panel.frame == placement.frame, screenID == screen.id,
                          self.presentation == placement, self.panel.isKeyWindow else {
                        throw UserFacingError("Smoke: quick panel moved/closed on display \(screen.id); frame=\(self.panel.frame), expected=\(placement.frame), key=\(self.panel.isKeyWindow)")
                    }
                    guard self.panel.styleMask.contains(.nonactivatingPanel), !self.panel.canBecomeMain,
                          NSWorkspace.shared.frontmostApplication?.processIdentifier == frontmost,
                          mainFrames.allSatisfy({ $0.0.frame == $0.1 }) else {
                        throw UserFacingError("Smoke: quick panel changed application/display focus")
                    }
                    if ticks == 35 {
                        if let content = self.panel.contentView, let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) {
                            content.cacheDisplay(in: content.bounds, to: bitmap)
                            try bitmap.representation(using: .png, properties: [:])?.write(to: destination.appendingPathComponent("quick-panel-display-\(screenIndex).png"))
                        }
                        print("PASS: display \(screen.id) \(screen.frame) pinned at \(placement.frame) for 36 refresh checks")
                        self.close(); screenIndex += 1
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: nextScreen)
                        return
                    }
                    var snapshot = self.model.monitor.snapshot
                    snapshot.cpu = Double(ticks % 101); snapshot.upload = pow(10, Double(ticks % 10)); snapshot.download = snapshot.upload
                    self.model.monitor.snapshot = snapshot
                    ticks += 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: check)
                } catch { self.close(); self.model.monitor.snapshot = initialSnapshot; completion(error) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: check)
        }
        nextScreen()
    }
    func verifyAndExport(button: NSStatusBarButton, destination: URL) throws {
        model.quickPanel.reset()
        toggle(relativeTo: button)
        guard isShown else { throw UserFacingError("Smoke: quick panel did not open") }
        close()
        guard !isShown else { throw UserFacingError("Smoke: quick panel did not close") }
        let previousAppearance = NSApp.appearance
        defer { NSApp.appearance = previousAppearance }
        for (name, appearance) in [("quick-panel", NSAppearance.Name.aqua), ("quick-panel-dark", NSAppearance.Name.darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            let host = NSHostingView(rootView: view().frame(width: 540, height: 760).environment(\.colorScheme, appearance == .darkAqua ? .dark : .light))
            try export(host, size: NSSize(width: 540, height: 760), appearance: appearance, name: name, destination: destination)
        }
        NSApp.appearance = NSAppearance(named: .aqua)
        let compact = NSHostingView(rootView: view().frame(width: 540, height: 500).environment(\.colorScheme, .light))
        try export(compact, size: NSSize(width: 540, height: 500), appearance: .aqua, name: "quick-panel-compact", destination: destination)
        let settings = NSHostingView(rootView: GlassScrollView(softIndicators: true) { QuickPanelSettingsView(preferences: model.quickPanel).padding(20) }.frame(width: 540, height: 920).background(Color(NSColor.windowBackgroundColor)).environment(\.colorScheme, .light))
        try export(settings, size: NSSize(width: 540, height: 920), appearance: .aqua, name: "quick-panel-settings", destination: destination)
        let cleaning = NSHostingView(rootView: CleaningView(service: model.cleaning).frame(width: 800, height: 500))
        try export(cleaning, size: NSSize(width: 800, height: 500), appearance: .darkAqua, name: "cleaning-preview", destination: destination)
        for source in [QuickSystemService.darkScript, QuickSystemService.dockScript, QuickSystemService.menuScript, "tell application \"Finder\" to empty the trash"] {
            var error: NSDictionary?
            guard NSAppleScript(source: source)?.compileAndReturnError(&error) == true else { throw UserFacingError("Smoke: system action script does not compile: \(error?.description ?? "")") }
        }
        let assertion = AwakeService()
        defer { assertion.stop() }
        assertion.start(minutes: 1, keepDisplay: true)
        guard assertion.active, assertion.keepsDisplay else { throw UserFacingError("Smoke: display awake assertion failed") }
        assertion.stop()
        guard !assertion.active, !assertion.keepsDisplay, assertion.until == nil else { throw UserFacingError("Smoke: awake assertion cleanup failed") }
        for shortcut in SystemShortcut.allCases {
            guard shortcut.url != nil else { throw UserFacingError("Smoke: system application unavailable: " + shortcut.title) }
        }
        print("PASS: awake/display assertion creation and release; system application targets resolve")
        print("PASS: quick panel open/close; light/dark/customization/cleaning views; system scripts compile without execution")
    }
    private func export(_ view: NSView, size: NSSize, appearance: NSAppearance.Name, name: String, destination: URL) throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: appearance)
        window.contentView = view; view.frame = NSRect(origin: .zero, size: size)
        // Give SwiftUI an explicit proposal and allow its appearance/layout transaction to settle.
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
        guard view.bounds.width >= size.width - 1, view.bounds.height >= size.height - 1 else { throw UserFacingError("Smoke: panel collapsed") }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw UserFacingError("Smoke: panel bitmap failed") }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw UserFacingError("Smoke: panel export failed") }
        try data.write(to: destination.appendingPathComponent(name + ".png")); window.close()
    }
    deinit {
        if let localEvents = localEvents { NSEvent.removeMonitor(localEvents) }
        if let outsideEvents = outsideEvents { NSEvent.removeMonitor(outsideEvents) }
    }
}
