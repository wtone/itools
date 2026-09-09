import AppKit
import SwiftUI
import Combine
import Carbon
import IToolsCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let model = AppModel()
    private var window: NSWindow!
    private var status: NSStatusItem!
    private var quickPanelController: QuickPanelController?
    private var clipboardPanelController: ClipboardPanelController?
    private var shortcutGuideController: ShortcutGuideController?
    private let traditionalMenu = NSMenu()
    private var menuBarMonitor: MenuBarMonitor?
    private var menuActions: [Int: () -> Void] = [:]
    private var readyForOpenRequests = false
    private var queuedOpenURLs: [URL] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        let smoke = ProcessInfo.processInfo.arguments.contains("--smoke-test")
        NSApp.setActivationPolicy(.regular)
        let appearance = UserDefaults.standard.string(forKey: "appearance") ?? "system"
        NSApp.appearance = appearance == "system" ? nil : NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 790), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "iTools"; window.minSize = NSSize(width: 990, height: 730)
        window.titlebarAppearsTransparent = true; window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: RootView(model: model))
        window.center()
        if !smoke { window.setFrameAutosaveName("IToolsMainWindow") }
        model.showWindow = { [weak self] in self?.showWindow() }
        quickPanelController = QuickPanelController(model: model)
        clipboardPanelController = ClipboardPanelController(model: model)
        shortcutGuideController = ShortcutGuideController(model: model)
        model.showClipboard = { [weak self] snippets in
            self?.quickPanelController?.close(); self?.shortcutGuideController?.close()
            self?.clipboardPanelController?.toggle(snippets: snippets)
        }
        model.showGuide = { [weak self] in
            self?.quickPanelController?.close(); self?.clipboardPanelController?.close()
            self?.shortcutGuideController?.show()
        }
        model.clipboardSelectionAction = { [weak self] action in self?.clipboardPanelController?.performSelection(action) }
        model.showShortcutSettings = { [weak self] in
            self?.quickPanelController?.close(); self?.clipboardPanelController?.close()
            self?.shortcutGuideController?.show(settings: true)
        }
        model.showToolbox = { [weak self] in
            guard let self = self, let button = self.status.button else { return }
            self.clipboardPanelController?.close(); self.shortcutGuideController?.close()
            self.quickPanelController?.toggle(relativeTo: button)
        }
        model.performQuickAction = { [weak self] in self?.quickPanelController?.perform($0) }
        model.shortcuts.run = { [weak self] id in self?.model.performCommand(id) }
        setupMainMenu(); setupStatusMenu()
        menuBarMonitor = MenuBarMonitor(monitor: model.monitor, preferences: model.menuBar) { [weak self] button in self?.quickPanelController?.toggle(relativeTo: button) }
        showWindow()
        readyForOpenRequests = true
        let queued = queuedOpenURLs; queuedOpenURLs.removeAll()
        if !queued.isEmpty { application(NSApp, open: queued) }
        if smoke { runSmokeTest(); return }
        if ProcessInfo.processInfo.arguments.contains("--finder-launch-test") { return }
        model.start(); registerShortcuts()
    }
    func showWindow() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    private func setupMainMenu() {
        let main = NSMenu(); let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 iTools", action: #selector(about), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "设置…", action: #selector(settings), keyEquivalent: ",")
        appMenu.addItem(withTitle: "隐藏 iTools", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 iTools", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; main.addItem(appItem)
        let edit = NSMenuItem(); edit.title = "编辑"; let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.submenu = editMenu; main.addItem(edit); NSApp.mainMenu = main
    }
    private func setupStatusMenu() {
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: "iTools 工具箱")
        status.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        traditionalMenu.delegate = self
        status.button?.target = self; status.button?.action = #selector(statusClicked(_:))
        status.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        status.button?.toolTip = "iTools 快捷面板 · 右键打开文字菜单"
    }
    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            quickPanelController?.close()
            traditionalMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY - 4), in: sender)
        } else { quickPanelController?.toggle(relativeTo: sender) }
    }
    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems(); menuActions.removeAll()
        add("打开 iTools", menu: menu) { self.showWindow() }
        menu.addItem(.separator())
        if model.captureEnabled { add("区域截图    " + model.shortcuts.display("quick.screenshot"), menu: menu) { self.model.takeScreenshot() }; add("屏幕文字识别    " + model.shortcuts.display("quick.ocr"), menu: menu) { self.model.takeScreenshot(ocr: true) } }
        add("剪贴板历史    " + model.shortcuts.display("quick.clipboard"), menu: menu) { self.model.showClipboard?(false) }
        add("快捷键操作指南    " + model.shortcuts.display("app.guide"), menu: menu) { self.model.showGuide?() }
        add("快捷键设置…", menu: menu) { self.model.showShortcutSettings?() }
        add("粘贴队列下一项    " + model.shortcuts.display("clipboard.next"), menu: menu) { self.model.clipboard.pasteNext() }
        add(model.clipboard.enabled ? "暂停剪贴板记录" : "开启剪贴板记录", menu: menu) { self.model.clipboard.enabled.toggle() }
        if model.recorder.isActive {
            add("停止录制并保存", menu: menu) { self.model.recorder.stop() }
        }
        menu.addItem(.separator())
        for layout in [WindowLayout.left, .right, .maximize] { add(layout.title, menu: menu) { self.model.windows.apply(layout) } }
        add("还原窗口", menu: menu) { self.model.windows.restore() }
        add(model.awake.active ? "停止防休眠" : "保持唤醒 30 分钟", menu: menu) { if self.model.awake.active { self.model.awake.stop() } else { self.model.awake.start(minutes: 30, keepDisplay: false) } }
        menu.addItem(.separator())
        add("系统状态", menu: menu) { self.model.navigate(.monitor) }
        let metricsItem = NSMenuItem(title: "菜单栏显示", action: nil, keyEquivalent: "")
        let metricsMenu = NSMenu(title: "菜单栏显示")
        for metric in MenuBarMetric.allCases {
            add(metric.title, menu: metricsMenu) { self.model.menuBar.set(metric, enabled: !self.model.menuBar.isEnabled(metric)) }
            metricsMenu.items.last?.state = model.menuBar.isEnabled(metric) ? .on : .off
        }
        metricsItem.submenu = metricsMenu; menu.addItem(metricsItem)
        add("设置…", menu: menu) { self.model.navigate(.settings) }
        add("退出 iTools", menu: menu) { NSApp.terminate(nil) }
    }
    private func add(_ title: String, menu: NSMenu, action: @escaping () -> Void) {
        let item = NSMenuItem(title: title, action: #selector(runMenu(_:)), keyEquivalent: "")
        item.target = self; item.tag = menuActions.count; menuActions[item.tag] = action; menu.addItem(item)
    }
    @objc private func runMenu(_ sender: NSMenuItem) { menuActions[sender.tag]?() }
    @objc private func settings() { model.navigate(.settings) }
    @objc private func about() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "iTools", .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版", .credits: NSAttributedString(string: "Intel Mac 工具箱\nmacOS 12 Monterey 及以上\n独立实现 · 本机处理")])
    }
    private func registerShortcuts() { model.shortcuts.start() }
    func application(_ application: NSApplication, open urls: [URL]) {
        guard readyForOpenRequests else { queuedOpenURLs.append(contentsOf: urls.prefix(20)); return }
        for url in urls {
            if url.scheme == "itools" {
                guard model.filesEnabled else { model.navigate(.settings); continue }
                model.files.receive(url); model.navigate(.files)
                writeFinderTestReceipt()
            } else if url.isFileURL { model.capture.openImage(url) }
        }
    }
    /// Test-only receipt for LaunchServices cold/warm delivery. Normal launches never log file paths.
    private func writeFinderTestReceipt() {
        guard ProcessInfo.processInfo.arguments.contains("--finder-launch-test"),
              let directory = ProcessInfo.processInfo.environment["ITOOLS_FINDER_TEST_OUTPUT"] else { return }
        let receipt: [String: Any] = ["action": model.files.pendingFinderAction ?? "", "paths": model.files.selection.map(\.path),
                                     "page": model.page.rawValue, "windowVisible": window.isVisible,
                                     "bundle": Bundle.main.bundleURL.path, "pid": ProcessInfo.processInfo.processIdentifier]
        do {
            let data = try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys])
            try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("receipt.json"), options: .atomic)
        } catch { print("FAIL: Finder receipt: \(error)") }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showWindow(); return true }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model.recorder.isActive {
            NoticeCenter.shared.report(UserFacingError("录制尚未保存，请先停止录制后再退出。")); showWindow(); return .terminateCancel
        }
        if model.files.working {
            NoticeCenter.shared.report(UserFacingError("文件任务尚未完成，请完成任务或停止扫描后再退出。")); showWindow(); return .terminateCancel
        }
        quickPanelController?.close(); clipboardPanelController?.close(); shortcutGuideController?.close(); menuBarMonitor?.stop(); model.stop(); return .terminateNow
    }
    private func runSmokeTest() {
        let directory = ProcessInfo.processInfo.environment["ITOOLS_SMOKE_OUTPUT"] ?? NSTemporaryDirectory() + "itools-smoke"
        let destination = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        do { try SmokeChecks.run(model: model, destination: destination) }
        catch { print("FAIL: \(error.localizedDescription)"); exit(5) }
        for metric in MenuBarMetric.allCases { model.menuBar.set(metric, enabled: true) }
        // Read system counters only; never request permissions or read clipboard content.
        model.monitor.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            do { try self.menuBarMonitor?.verifyAndExport(snapshot: self.model.monitor.snapshot, destination: destination) }
            catch { print("FAIL: \(error.localizedDescription)"); exit(7) }
            do {
                if let button = self.status.button { try self.quickPanelController?.verifyAndExport(button: button, destination: destination) }
            } catch { print("FAIL: \(error.localizedDescription)"); exit(8) }
            do { try ShortcutSmokeChecks.run(model: self.model, destination: destination) }
            catch { print("FAIL: \(error.localizedDescription)"); exit(9) }
            ShortcutSmokeChecks.verifyHotKeyDispatch { error in
                if let error = error { print("FAIL: \(error.localizedDescription)"); exit(10) }
                self.renderPage(index: 0, destination: destination)
            }
        }
    }
    private func renderPage(index: Int, destination: URL) {
        guard index <= ToolPage.allCases.count else {
            model.monitor.stop()
            guard model.monitor.snapshot.memoryTotal > 0, model.monitor.snapshot.cpu != nil else { print("FAIL: system counters unavailable"); exit(6) }
            let result = "PASS: 8 pages + dark overview; pixel export/redaction/OCR/crop/Finder staging; OS=\(ProcessInfo.processInfo.operatingSystemVersionString); cpu=\(model.monitor.snapshot.cpu ?? -1); memory=\(model.monitor.snapshot.memoryTotal); temp=\(model.monitor.snapshot.cpuTemperature ?? -1)"
            print(result); try? result.write(to: destination.appendingPathComponent("smoke-result.txt"), atomically: true, encoding: .utf8)
            NSApp.terminate(nil); return
        }
        if index == ToolPage.allCases.count {
            NSApp.appearance = NSAppearance(named: .darkAqua); model.page = .overview
        } else { model.page = ToolPage.allCases[index] }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard let view = self.window.contentView else { exit(1) }
            view.layoutSubtreeIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(2) }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(3) }
            do { try png.write(to: destination.appendingPathComponent("page-\(index).png")) }
            catch { print(error); exit(4) }
            self.renderPage(index: index+1, destination: destination)
        }
    }
}
let app = NSApplication.shared
// The embedded accessory uses the same executable, but never creates AppModel,
// a main window, menu-bar monitors, clipboard recording, or global shortcuts.
let delegate: NSApplicationDelegate = Bundle.main.bundleIdentifier == FinderHostLocation.workerBundleID
    ? FinderActionDelegate() : AppDelegate()
app.delegate = delegate
app.run()
