import AppKit
import SwiftUI
import Combine
import Carbon
import IToolsCore

enum SystemShortcut: String, CaseIterable, Identifiable {
    case settings, diskUtility, systemInformation, console, activityMonitor
    var id: String { rawValue }
    var title: String {
        switch self { case .settings: return "系统设置"; case .diskUtility: return "磁盘工具"
        case .systemInformation: return "系统信息"; case .console: return "控制台"; case .activityMonitor: return "活动监视器" }
    }
    var bundleID: String {
        switch self { case .settings: return "com.apple.systempreferences"; case .diskUtility: return "com.apple.DiskUtility"
        case .systemInformation: return "com.apple.SystemProfiler"; case .console: return "com.apple.Console"; case .activityMonitor: return "com.apple.ActivityMonitor" }
    }
    var url: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
}

final class QuickSystemService: ObservableObject {
    @Published private(set) var dark = false
    @Published private(set) var dockHidden = false
    @Published private(set) var menuHidden = false
    @Published private(set) var desktopCovered = false
    private var desktopWindows: [NSWindow] = []
    private var observers: [NSObjectProtocol] = []
    init() {
        refresh()
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.removeDesktopCover() })
    }
    func refresh() {
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        CFPreferencesAppSynchronize("com.apple.dock" as CFString)
        dark = (CFPreferencesCopyValue("AppleInterfaceStyle" as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? String) == "Dark"
        dockHidden = (CFPreferencesCopyAppValue("autohide" as CFString, "com.apple.dock" as CFString) as? Bool) ?? false
        menuHidden = (CFPreferencesCopyValue("_HIHideMenuBar" as CFString, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? Bool) ?? false
    }
    static let darkScript = """
    tell application "System Events"
        tell appearance preferences
            set dark mode to not dark mode
            return dark mode
        end tell
    end tell
    """
    static let dockScript = """
    tell application "System Events"
        tell dock preferences
            set autohide to not autohide
            return autohide
        end tell
    end tell
    """
    static let menuScript = """
    tell application "System Events"
        tell dock preferences
            set autohide menu bar to not autohide menu bar
            return autohide menu bar
        end tell
    end tell
    """
    @discardableResult func script(_ source: String) -> NSAppleEventDescriptor? {
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        if let error = error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            let detail = error[NSAppleScript.errorMessage] as? String ?? "系统未完成操作。"
            NoticeCenter.shared.report(UserFacingError(code == -1743 ? "系统未允许自动化控制。请在「隐私与安全性 → 自动化」允许 iTools 控制 System Events / Finder 后再试。" : detail))
            return nil
        }
        return result
    }
    func toggleDark() { if let value = script(Self.darkScript) { dark = value.booleanValue } }
    func toggleDock() { if let value = script(Self.dockScript) { dockHidden = value.booleanValue } }
    func toggleMenuBar() { if let value = script(Self.menuScript) { menuHidden = value.booleanValue } }
    func open(_ shortcut: SystemShortcut) {
        guard let url = shortcut.url else { NoticeCenter.shared.report(UserFacingError("未找到" + shortcut.title)); return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in if let error = error { NoticeCenter.shared.report(error) } }
    }
    func openPreferences(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:" + pane), NSWorkspace.shared.open(url) { return }
        open(.settings)
    }
    func lockScreen() {
        guard Permissions.requireAccessibility() else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_Q), keyDown: down)
            event?.flags = [.maskCommand, .maskControl]; event?.post(tap: .cghidEventTap)
        }
    }
    func screenSaver() {
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
        NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in if let error = error { NoticeCenter.shared.report(error) } }
    }
    func emptyTrash() {
        guard Panels.confirm("清空废纸篓？", detail: "Finder 将永久删除废纸篓中的项目，此操作无法撤销。", action: "清空废纸篓") else { return }
        if script("tell application \"Finder\" to empty the trash") != nil { NoticeCenter.shared.success("Finder 已处理清空废纸篓请求") }
    }
    func toggleDesktopCover() {
        if desktopCovered { removeDesktopCover(); return }
        for screen in NSScreen.screens {
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false; panel.canHide = false; panel.hasShadow = false
            let view = NSImageView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.imageScaling = .scaleProportionallyUpOrDown; view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            if let imageURL = NSWorkspace.shared.desktopImageURL(for: screen) { view.image = NSImage(contentsOf: imageURL) }
            panel.contentView = view; panel.orderFrontRegardless(); desktopWindows.append(panel)
        }
        desktopCovered = !desktopWindows.isEmpty
    }
    func removeDesktopCover() { let owned = desktopWindows; desktopWindows.removeAll(); desktopCovered = false; owned.forEach { $0.close() } }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
}

final class CleaningService: ObservableObject {
    @Published private(set) var active = false
    @Published private(set) var seconds = 60
    @Published private(set) var keyboardOnly = false
    private var windows: [NSWindow] = []
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var timer: Timer?
    private var policy: CleaningEscapePolicy?
    private var sleepObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var resignObserver: NSObjectProtocol?
    private var sessionObserver: NSObjectProtocol?
    init() {
        resignObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.stop() }
        sessionObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.stop() }
        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in self?.stop() }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.stop() }
    }
    func start(keyboardOnly: Bool) {
        guard !active, Permissions.requireAccessibility() else { return }
        let mask = [CGEventType.keyDown, .keyUp, .flagsChanged].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let eventTap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, info in
            guard let info = info else { return Unmanaged.passUnretained(event) }
            let service = Unmanaged<CleaningService>.fromOpaque(info).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                DispatchQueue.main.async { service.stop() }; return Unmanaged.passUnretained(event)
            }
            guard service.active else { return Unmanaged.passUnretained(event) }
            if type == .keyDown || type == .keyUp {
                service.policy?.key(code: event.getIntegerValueField(.keyboardEventKeycode), down: type == .keyDown, now: ProcessInfo.processInfo.systemUptime)
            }
            return nil // Consume only ordinary keyboard events, never retain or log typed content.
        }, userInfo: pointer) else {
            NoticeCenter.shared.report(UserFacingError("无法启动按键拦截。请检查辅助功能权限；清洁模式尚未开启。")); return
        }
        tap = eventTap; source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        guard let source = source else { CFMachPortInvalidate(eventTap); tap = nil; return }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        self.keyboardOnly = keyboardOnly; seconds = 60
        policy = CleaningEscapePolicy(now: ProcessInfo.processInfo.systemUptime); active = true
        for screen in NSScreen.screens {
            let window = CleaningWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver; window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: CleaningView(service: self))
            window.backgroundColor = .black; window.makeKeyAndOrderFront(nil); windows.append(window)
        }
        NSApp.activate(ignoringOtherApps: true)
        timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let policy = self.policy else { return }
            let now = ProcessInfo.processInfo.systemUptime
            if policy.shouldExit(now: now) { self.stop(); return }
            let value = max(0, Int(ceil(policy.expiresAt - now)))
            if value != self.seconds { self.seconds = value }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    func stop() {
        timer?.invalidate(); timer = nil
        if let tap = tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; active = false; policy = nil
        let owned = windows; windows.removeAll(); owned.forEach { $0.close() }
    }
    deinit {
        if let token = sleepObserver { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        if let token = screenObserver { NotificationCenter.default.removeObserver(token) }
        if let token = resignObserver { NotificationCenter.default.removeObserver(token) }
        if let token = sessionObserver { NSWorkspace.shared.notificationCenter.removeObserver(token) }
    }
}
private final class CleaningWindow: NSWindow { override var canBecomeKey: Bool { true } }
struct CleaningView: View {
    @ObservedObject var service: CleaningService
    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 18) {
                Image(systemName: service.keyboardOnly ? "keyboard" : "sparkles").font(.system(size: 36))
                Text(service.keyboardOnly ? "可以清洁键盘了" : "可以清洁屏幕了").font(.system(size: 25, weight: .medium))
                Text("按住 Esc 两秒，或点击下方按钮结束").font(.system(size: 15))
                Text("\(service.seconds) 秒后自动结束").monospacedDigit().foregroundColor(.gray)
                Button("结束清洁") { service.stop() }.buttonStyle(.plain).padding(12).background(Color.white.opacity(0.18)).cornerRadius(8)
                Text("普通按键已拦截；电源、媒体键与系统保留快捷键仍可能生效").font(.system(size: 11)).foregroundColor(.gray)
            }.foregroundColor(.white)
        }.ignoresSafeArea()
    }
}
