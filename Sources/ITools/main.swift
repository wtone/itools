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
    private var initializeMenuBarOnLeft = false
    private var menuActions: [Int: () -> Void] = [:]
    private var readyForOpenRequests = false
    private var queuedOpenURLs: [URL] = []
    private var launchedAtLogin = false
    private var launchedForFinderAction = ProcessInfo.processInfo.arguments.contains(FinderLaunchEvent.hostActionArgument)
    private var queuedFinderVisibility: [UUID] = []
    private var seenFinderVisibility: [UUID] = []
    private var finderVisibilityRunning = false
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(openApplication(_:reply:)),
            forEventClass: AEEventClass(kCoreEventClass), andEventID: AEEventID(kAEOpenApplication))
    }
    @objc private func openApplication(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        if event.paramDescriptor(forKeyword: FinderLaunchEvent.requestsKey) != nil {
            guard let urls = FinderLaunchEvent.requests(in: event),
                  urls.allSatisfy({ FinderDirectRequest($0)?.action == FinderActions.visibilityActionID }) else { return }
            if !readyForOpenRequests { launchedForFinderAction = true }
            for url in urls {
                guard let request = FinderDirectRequest(url), !seenFinderVisibility.contains(request.id),
                      queuedFinderVisibility.count < 20 else { continue }
                seenFinderVisibility.append(request.id)
                if seenFinderVisibility.count > 200 { seenFinderVisibility.removeFirst() }
                queuedFinderVisibility.append(request.id)
            }
            if readyForOpenRequests { runNextFinderVisibility() }
            return
        }
        if !readyForOpenRequests { launchedAtLogin = LoginLaunch.isLoginEvent(event) }
        else if !LoginLaunch.isLoginEvent(event) { showWindow() }
        if readyForOpenRequests { writeLoginTestReceipt() }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let smoke = ProcessInfo.processInfo.arguments.contains("--smoke-test")
        if smoke { model.menuBar.setDisplaySelection(.init()) }
        if ProcessInfo.processInfo.arguments.contains("--permission-check") {
            NSApp.setActivationPolicy(.accessory)
            let status = PermissionCenter.shared; status.refresh()
            let report: [String: Any] = ["application": Bundle.main.bundleURL.path,
                "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
                "accessibility": status.accessibility, "eventPosting": status.eventPosting,
                "screen": status.screen, "microphone": status.microphone.rawValue]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]),
               let text = String(data: data, encoding: .utf8) { print(text) }
            NSApp.terminate(nil); return
        }
        // Remember the source app before showing any iTools window or requesting access.
        AppFocus.shared.captureFrontmost()
        NSApp.setActivationPolicy((launchedAtLogin || launchedForFinderAction) && !smoke ? .accessory : .regular)
        let appearance = UserDefaults.standard.string(forKey: "appearance") ?? "system"
        NSApp.appearance = appearance == "system" ? nil : NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 790), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "iTools"; window.minSize = NSSize(width: 990, height: 730)
        window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isOpaque = false; window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: RootView(model: model))
        window.center()
        if !smoke { window.setFrameAutosaveName("IToolsMainWindow") }
        model.showWindow = { [weak self] in self?.showWindow() }
        quickPanelController = QuickPanelController(model: model)
        clipboardPanelController = ClipboardPanelController(model: model)
        shortcutGuideController = ShortcutGuideController(model: model)
        PermissionCenter.shared.preparePresentation = { [weak self] in
            self?.quickPanelController?.close(); self?.clipboardPanelController?.close(); self?.shortcutGuideController?.close(returnFocus: false)
        }
        PermissionCenter.shared.relaunch = { [weak self] in self?.relaunchForPermissions() }
        model.showClipboard = { [weak self] snippets in
            self?.quickPanelController?.close(); self?.shortcutGuideController?.close()
            self?.clipboardPanelController?.toggle(snippets: snippets)
        }
        model.showGuide = { [weak self] in
            self?.quickPanelController?.close(); self?.clipboardPanelController?.close()
            self?.shortcutGuideController?.show(toggle: true)
        }
        model.clipboardSelectionAction = { [weak self] action in self?.clipboardPanelController?.performSelection(action) }
        model.showShortcutSettings = { [weak self] category in
            self?.quickPanelController?.close(); self?.clipboardPanelController?.close()
            self?.shortcutGuideController?.show(category: category)
        }
        model.showToolbox = { [weak self] in
            guard let self = self, let button = self.status.button else { return }
            self.clipboardPanelController?.close(); self.shortcutGuideController?.close()
            self.quickPanelController?.toggle(relativeTo: button, fromClick: false)
        }
        model.performQuickAction = { [weak self] in self?.quickPanelController?.perform($0) }
        model.shortcuts.run = { [weak self] id in self?.model.performCommand(id) }
        model.resetMenuBarPosition = { [weak self] in self?.restoreMenuBarPosition() }
        setupMainMenu(); setupStatusMenu()
        menuBarMonitor = MenuBarMonitor(monitor: model.monitor, preferences: model.menuBar, statusItem: status, initializeOnLeft: initializeMenuBarOnLeft, click: { [weak self] button, right in
            self?.handleStatusClick(button, right: right)
        })
        if ((!launchedAtLogin && !launchedForFinderAction) || smoke) && !ProcessInfo.processInfo.arguments.contains("--capture-editor-check") && !ProcessInfo.processInfo.arguments.contains("--menu-bar-display-check") { showWindow() }
        readyForOpenRequests = true
        runNextFinderVisibility()
        let queued = queuedOpenURLs; queuedOpenURLs.removeAll()
        if !queued.isEmpty { application(NSApp, open: queued) }
        if smoke {
            if ProcessInfo.processInfo.arguments.contains("--menu-bar-display-check") {
                let destination = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ITOOLS_SMOKE_OUTPUT"] ?? NSTemporaryDirectory() + "itools-menu-bar-test")
                try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                for metric in MenuBarMetric.allCases { model.menuBar.set(metric, enabled: true) }
                model.monitor.start()
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    do { try self.menuBarMonitor?.verifyAndExport(snapshot: self.model.monitor.snapshot, destination: destination) }
                    catch { print("FAIL: \(error.localizedDescription)"); exit(7) }
                    var remaining = 30
                    func checkLiveRefresh() {
                        do { try self.menuBarMonitor?.verifyCurrentDisplay() }
                        catch { print("FAIL: \(error.localizedDescription)"); exit(7) }
                        remaining -= 1
                        if remaining == 0 {
                            print("PASS: primary-only compositor placement and button anchor across 30 live refresh checks")
                            NSApp.terminate(nil)
                        } else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: checkLiveRefresh) }
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: checkLiveRefresh)
                }
                return
            }
            if ProcessInfo.processInfo.arguments.contains("--clipboard-focus-test") {
                // Run the panel's real responder checks after the launch transaction settles.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    ShortcutSmokeChecks.verifyClipboardSearch(model: self.model) { error in
                        if let error = error { print("FAIL: \(error.localizedDescription)"); exit(17) }
                        NSApp.terminate(nil)
                    }
                }
                return
            }
            if ProcessInfo.processInfo.arguments.contains("--quick-panel-screen-test") {
                let destination = URL(fileURLWithPath: ProcessInfo.processInfo.environment["ITOOLS_SMOKE_OUTPUT"] ?? NSTemporaryDirectory() + "itools-screen-test")
                try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                for metric in MenuBarMetric.allCases { model.menuBar.set(metric, enabled: true) }
                model.monitor.start()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    self.quickPanelController?.verifyScreenStability(destination: destination) { error in
                        if let error = error { print("FAIL: \(error.localizedDescription)"); exit(16) }
                        self.runSmokeTest()
                    }
                }
            } else { runSmokeTest() }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--login-item-test") {
            writeLoginTestReceipt()
            if ProcessInfo.processInfo.environment["ITOOLS_LOGIN_TEST_MODE"] == "registration",
               let directory = ProcessInfo.processInfo.environment["ITOOLS_LOGIN_TEST_OUTPUT"] {
                LoginItemSmokeChecks.registration(controller: model.loginItem, destination: URL(fileURLWithPath: directory))
            }
            return
        }
        if ProcessInfo.processInfo.arguments.contains("--finder-launch-test") { return }
        model.start(); registerShortcuts()
        if ProcessInfo.processInfo.arguments.contains("--permission-help") {
            PermissionCenter.shared.show(.accessibility, operation: "直接粘贴")
        }
    }
    private func runNextFinderVisibility() {
        guard readyForOpenRequests, !finderVisibilityRunning, !queuedFinderVisibility.isEmpty else { return }
        queuedFinderVisibility.removeFirst()
        guard model.filesEnabled else {
            queuedFinderVisibility.removeAll()
            NoticeCenter.shared.report(UserFacingError("访达与文件功能已停用，请在 iTools 设置中开启。"))
            showWindow(); return
        }
        finderVisibilityRunning = true
        FinderVisibilityController.toggle { [weak self] error in
            guard let self = self else { return }
            self.finderVisibilityRunning = false
            if let error = error { NoticeCenter.shared.report(error); self.showWindow() }
            else { NoticeCenter.shared.success("已向访达发送隐藏文件显示切换。") }
            DispatchQueue.main.async { self.runNextFinderVisibility() }
        }
    }
    func showWindow() {
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        if let permission = PermissionCenter.shared.windowForChecks, permission.isVisible { permission.makeKeyAndOrderFront(nil) }
    }
    private func relaunchForPermissions() {
        guard !model.recorder.isActive, !model.recorder.converting, !model.capture.busy, !model.files.working else {
            PermissionCenter.shared.report("请先结束正在进行的录制、截图或文件操作，再重新打开 iTools。"); return
        }
        let launcher = Process(); launcher.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Positional arguments carry the path; no path or user text is interpreted as shell code.
        launcher.arguments = ["-c", "i=0; while kill -0 \"$1\" 2>/dev/null; do i=$((i+1)); [ \"$i\" -lt 100 ] || exit 1; sleep 0.1; done; exec /usr/bin/open \"$2\"", "itools-relaunch", String(ProcessInfo.processInfo.processIdentifier), Bundle.main.bundleURL.path]
        do { try launcher.run(); NSApp.terminate(nil) } catch { PermissionCenter.shared.report(error.localizedDescription) }
    }
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
        edit.submenu = editMenu; main.addItem(edit)
        let viewItem = NSMenuItem(title: "显示", action: nil, keyEquivalent: "")
        let viewMenu = NSMenu(title: "显示")
        for (index, page) in ToolPage.allCases.enumerated() {
            let item = NSMenuItem(title: page.rawValue, action: #selector(navigatePage(_:)), keyEquivalent: String(index + 1))
            item.target = self; item.tag = index; viewMenu.addItem(item)
        }
        viewItem.submenu = viewMenu; main.addItem(viewItem); NSApp.mainMenu = main
    }
    @objc private func navigatePage(_ sender: NSMenuItem) {
        guard ToolPage.allCases.indices.contains(sender.tag) else { return }
        model.navigate(ToolPage.allCases[sender.tag])
    }
    private func restoreMenuBarPosition() {
        guard !ProcessInfo.processInfo.arguments.contains("--smoke-test") else { return }
        quickPanelController?.close()
        menuBarMonitor?.restoreDefaultPosition()
        NoticeCenter.shared.success("iTools 已移到状态图标区靠左的可见位置")
    }
    private func setupStatusMenu() {
        let smoke = ProcessInfo.processInfo.arguments.contains("--smoke-test")
        let name = smoke ? "iTools.smoke." + UUID().uuidString : "iTools.metrics"
        // Assign a fresh temporary slot before the first native layout in checks.
        // Normal launches preserve the position saved by the user's Cmd-drag.
        let key = "NSStatusItem Preferred Position " + name
        if smoke, ProcessInfo.processInfo.arguments.contains("--menu-bar-notch-check"),
           let right = NSScreen.screens.first?.auxiliaryTopRightArea {
            UserDefaults.standard.set(right.width + 63, forKey: key)
        }
        initializeMenuBarOnLeft = MenuBarDisplayScope.prepareAutosave(name)
        status = MenuBarDisplayScope.makeStatusItem(length: NSStatusItem.variableLength)
        status.autosaveName = name
        status.button?.image = NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: "iTools 工具箱")
        status.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        traditionalMenu.delegate = self
        status.button?.target = self; status.button?.action = #selector(statusClicked(_:))
        status.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        status.button?.toolTip = "iTools 快捷面板 · 右键打开文字菜单"
    }
    @objc private func statusClicked(_ sender: NSStatusBarButton) {
        handleStatusClick(sender, right: NSApp.currentEvent?.type == .rightMouseUp)
    }
    private func handleStatusClick(_ sender: NSStatusBarButton, right: Bool) {
        // Reject stale native events from a display removed/rearranged during a click.
        if let event = NSApp.currentEvent, [.leftMouseUp, .rightMouseUp].contains(event.type),
           !MenuBarDisplayScope.allowsMenuBar(at: NSEvent.mouseLocation, selection: model.menuBar.displaySelection) { return }
        if right {
            quickPanelController?.close()
            if let rect = MenuBarDisplayScope.buttonScreenRect(sender) {
                traditionalMenu.popUp(positioning: nil, at: NSPoint(x: rect.minX, y: rect.minY - 4), in: nil)
            } else {
                traditionalMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY - 4), in: sender)
            }
        } else { quickPanelController?.toggle(relativeTo: sender) }
    }
    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems(); menuActions.removeAll()
        add("打开 iTools", menu: menu) { self.showWindow() }
        menu.addItem(.separator())
        if model.captureEnabled { add("区域截图    " + model.shortcuts.display("quick.screenshot"), menu: menu) { self.model.takeScreenshot() }; add("屏幕文字识别    " + model.shortcuts.display("quick.ocr"), menu: menu) { self.model.takeScreenshot(ocr: true) } }
        add("剪贴板历史    " + model.shortcuts.display("quick.clipboard"), menu: menu) { self.model.showClipboard?(false) }
        add("快捷键与操作指南    " + model.shortcuts.display("app.guide"), menu: menu) { self.model.showShortcutSettings?(nil) }
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
            if let message = FinderLaunchFailure.message(in: url) {
                model.navigate(.files); NoticeCenter.shared.report(UserFacingError(message)); continue
            }
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
    private func writeLoginTestReceipt() {
        guard ProcessInfo.processInfo.arguments.contains("--login-item-test"),
              let directory = ProcessInfo.processInfo.environment["ITOOLS_LOGIN_TEST_OUTPUT"] else { return }
        let receipt: [String: Any] = ["login": launchedAtLogin, "windowVisible": window.isVisible,
            "accessory": NSApp.activationPolicy() == .accessory, "statusItem": status.button != nil,
            "pid": ProcessInfo.processInfo.processIdentifier, "bundle": Bundle.main.bundleURL.path,
            "registration": String(describing: model.loginItem.state)]
        do {
            try JSONSerialization.data(withJSONObject: receipt, options: [.sortedKeys])
                .write(to: URL(fileURLWithPath: directory).appendingPathComponent("launch.json"), options: .atomic)
        } catch { print("FAIL: login receipt: \(error)") }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow(); writeLoginTestReceipt(); return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if model.recorder.isActive {
            NoticeCenter.shared.report(UserFacingError("录制尚未保存，请先停止录制后再退出。")); showWindow(); return .terminateCancel
        }
        if model.recorder.converting {
            NoticeCenter.shared.report(UserFacingError("视频仍在导出，请等待完成后再退出。")); showWindow(); return .terminateCancel
        }
        if model.files.working {
            NoticeCenter.shared.report(UserFacingError("文件任务尚未完成，请完成任务或停止扫描后再退出。")); showWindow(); return .terminateCancel
        }
        model.capture.cancelRegionCapture(); model.capture.cancelLongCapture()
        quickPanelController?.close(); clipboardPanelController?.close(); shortcutGuideController?.close(); menuBarMonitor?.stop(); model.stop()
        if ProcessInfo.processInfo.arguments.contains("--smoke-test"), let name = status?.autosaveName {
            NSStatusBar.system.removeStatusItem(status)
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.contains(name) { UserDefaults.standard.removeObject(forKey: key) }
        }
        return .terminateNow
    }
    private func runSmokeTest() {
        let directory = ProcessInfo.processInfo.environment["ITOOLS_SMOKE_OUTPUT"] ?? NSTemporaryDirectory() + "itools-smoke"
        let destination = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let interfacePreview = ProcessInfo.processInfo.arguments.contains("--interface-preview")
        if interfacePreview {
            model.clipboard.entries = [
                ClipEntry(kind: .text, text: "单击复制，双击粘贴到之前的应用。", source: "iTools 界面样例", payload: []),
                ClipEntry(kind: .text, text: "半透明分区通过底色与留白区分层次。", source: "iTools 界面样例", payload: []),
                ClipEntry(kind: .text, text: "快捷键与操作指南：查看分组、修改快捷键。", source: "iTools 界面样例", payload: [])
            ]
        } else {
            if ProcessInfo.processInfo.arguments.contains("--capture-editor-check") { model.showWindow = nil; model.capture.onShow = nil }
            do { try SmokeChecks.run(model: model, destination: destination) }
            catch { print("FAIL: \(error.localizedDescription)"); exit(5) }
            if ProcessInfo.processInfo.arguments.contains("--capture-editor-check") { NSApp.terminate(nil); return }
        }
        for metric in MenuBarMetric.allCases { model.menuBar.set(metric, enabled: true) }
        // Read system counters only; never request permissions or read clipboard content.
        model.monitor.start()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            do { try self.menuBarMonitor?.verifyAndExport(snapshot: self.model.monitor.snapshot, destination: destination) }
            catch { print("FAIL: \(error.localizedDescription)"); exit(7) }
            do {
                if let button = self.status.button { try self.quickPanelController?.verifyAndExport(button: button, destination: destination) }
            } catch { print("FAIL: \(error.localizedDescription)"); exit(8) }
            if interfacePreview {
                do {
                    try FinderMenuSmokeChecks.run(destination: destination)
                    try ShortcutWorkspaceSmokeChecks.render(model: self.model, destination: destination)
                    try WindowGlassChecks.verifyAccessibilityFallback(destination: destination)
                } catch { print("FAIL: \(error.localizedDescription)"); exit(18) }
                self.renderPage(index: 0, destination: destination)
                return
            }
            ShortcutSmokeChecks.verifyClipboardSearch(model: self.model) { error in
                if let error = error { print("FAIL: \(error.localizedDescription)"); exit(17) }
                self.runShortcutSmokeChecks(destination: destination)
            }
        }
    }
    private func runShortcutSmokeChecks(destination: URL) {
            do { try ShortcutSmokeChecks.run(model: self.model, destination: destination) }
            catch { print("FAIL: \(error.localizedDescription)"); exit(9) }
            ShortcutSmokeChecks.verifyHotKeyDispatch { error in
                if let error = error { print("FAIL: \(error.localizedDescription)"); exit(10) }
                // Render extra settings windows after the focus-sensitive panel checks.
                do { try FinderMenuSmokeChecks.run(destination: destination) }
                catch { print("FAIL: \(error.localizedDescription)"); exit(11) }
                do { try LoginItemSmokeChecks.render(destination: destination) }
                catch { print("FAIL: \(error.localizedDescription)"); exit(12) }
                ShortcutWorkspaceSmokeChecks.run(model: self.model, destination: destination) { error in
                    if let error = error { print("FAIL: \(error.localizedDescription)"); exit(13) }
                    PermissionSmokeChecks.run(mainWindow: self.window, destination: destination) { error in
                        if let error = error { print("FAIL: \(error.localizedDescription)"); exit(15) }
                        self.renderPage(index: 0, destination: destination)
                    }
                }
            }
    }
    private func renderPage(index: Int, destination: URL) {
        let previews: [(ToolPage, Bool, NSSize)] = ToolPage.allCases.map { ($0, false, NSSize(width: 1120, height: 790)) } + [
            (.overview, true, NSSize(width: 1120, height: 790)),
            (.settings, true, NSSize(width: 1120, height: 790)),
            (.monitor, true, NSSize(width: 1120, height: 790)),
            (.overview, false, NSSize(width: 970, height: 680)),
            (.settings, false, NSSize(width: 970, height: 680)),
            (.utilities, true, NSSize(width: 1120, height: 790)),
            (.monitor, false, NSSize(width: 970, height: 680)),
            (.utilities, true, NSSize(width: 970, height: 680)),
            (.clipboard, true, NSSize(width: 1120, height: 790)),
            (.files, true, NSSize(width: 1120, height: 790)),
            (.capture, true, NSSize(width: 1120, height: 790))
        ]
        guard index < previews.count else {
            model.monitor.stop()
            guard model.monitor.snapshot.memoryTotal > 0, model.monitor.snapshot.cpu != nil else { print("FAIL: system counters unavailable"); exit(6) }
            let result = "PASS: \(ToolPage.allCases.count) pages in light/dark + minimum-width overview/settings/monitor/utilities; native interface export; OS=\(ProcessInfo.processInfo.operatingSystemVersionString); cpu=\(model.monitor.snapshot.cpu ?? -1); memory=\(model.monitor.snapshot.memoryTotal); temp=\(model.monitor.snapshot.cpuTemperature ?? -1)"
            print(result); try? result.write(to: destination.appendingPathComponent("smoke-result.txt"), atomically: true, encoding: .utf8)
            NSApp.terminate(nil); return
        }
        let preview = previews[index]
        NSApp.appearance = NSAppearance(named: preview.1 ? .darkAqua : .aqua)
        model.page = preview.0; window.setContentSize(preview.2)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            guard let view = self.window.contentView else { exit(1) }
            view.layoutSubtreeIfNeeded()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(2) }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(3) }
            do { try png.write(to: destination.appendingPathComponent("page-\(index).png")) }
            catch { print(error); exit(4) }
            if preview.0 == .overview || (preview.0 == .settings && (preview.1 || preview.2.width == 970)) {
                do { try WindowGlassChecks.verifyAndExport(self.window, destination: destination, name: "window-frame-\(index)") }
                catch { print("FAIL: \(error.localizedDescription)"); exit(14) }
            }
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
