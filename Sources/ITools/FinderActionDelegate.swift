import AppKit
import IToolsCore

/// An accessory process for Finder commands. It deliberately has no main-app
/// delegate, AppModel, URL-scheme registration, or general document association.
final class FinderActionDelegate: NSObject, NSApplicationDelegate {
    private let files = FileService()
    private var ready = false
    private var incoming: [URL] = []
    private var queued: [FinderDirectRequest] = []
    private var seen: [UUID] = []
    private var active: FinderDirectRequest?
    private var executing = false
    private var timer: Timer?
    private var idleTimer: Timer?
    private var progress: NSPanel?
    private var progressLabel: NSTextField?
    private var errors: [String] = []
    private var dialogs: [String] = []
    private var started = Date()
    private var isTest: Bool { ProcessInfo.processInfo.arguments.contains("--finder-direct-test") }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // AppKit installs its standard event handlers before this notification.
        // Registering in init would be overwritten and lose the first request.
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(receiveLaunch(_:reply:)),
            forEventClass: FinderLaunchEvent.eventClass, andEventID: FinderLaunchEvent.eventID)
    }

    @objc private func receiveLaunch(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let urls = FinderLaunchEvent.requests(in: event) else {
            present(title: "无法识别访达操作", text: "请求无效，请重新打开 Finder 右键菜单。"); return
        }
        application(NSApp, open: urls)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        files.finderDirect = true
        NoticeCenter.shared.errorPresenter = { [weak self] message in
            guard let self = self else { return }
            self.errors.append(message)
            self.present(title: "访达操作未完成", text: message)
        }
        if isTest {
            files.terminalOpener = { _, _, done in done(nil) }
            files.applicationOpener = { _, _, done in done(nil) }
            let name = ProcessInfo.processInfo.environment["ITOOLS_FINDER_TEST_OUTPUT"] ?? UUID().uuidString
            files.fileClipboard = NativeFileClipboard(NSPasteboard(name: .init("itools-finder-test-" + name)))
            files.recycleHandler = { sources, completion in
                NativeFileSmokeChecks.recycleFixtures(sources, in: URL(fileURLWithPath: name), completion: completion)
            }
        }
        ready = true
        let urls = incoming; incoming.removeAll()
        application(NSApp, open: urls)
        scheduleIdleExit()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard ready else { incoming.append(contentsOf: urls.prefix(20)); return }
        for url in urls {
            guard let request = FinderDirectRequest(url) else {
                present(title: "无法识别访达操作", text: "请求无效，请重新打开 Finder 右键菜单。"); continue
            }
            guard !seen.contains(request.id) else { continue }
            guard queued.count < 20 else {
                present(title: "访达操作排队中", text: "当前操作较多，请等待已提交的操作完成后重试。"); continue
            }
            seen.append(request.id); if seen.count > 200 { seen.removeFirst() }
            queued.append(request)
        }
        // Never re-enter FileService while a modal panel pumps the event loop.
        DispatchQueue.main.async { self.startNext() }
    }

    private func startNext() {
        guard active == nil, !executing, NSApp.modalWindow == nil, !queued.isEmpty else { return }
        idleTimer?.invalidate()
        let request = queued.removeFirst(); active = request; started = Date()
        errors = []; dialogs = []
        files.selection = request.paths; files.pendingFinderAction = nil; files.result = ""
        files.scanSummary = ""; files.scanEntries = []; files.operationIssues = []
        files.revealedFiles = []; files.openedDirectory = nil
        files.finderApplication = request.application
        files.openedApplications = []; files.recycledFiles = [:]
        files.refreshTemplates()
        files.favorites = Storage.load([URL].self, "folders.json", fallback: [])
        executing = true
        let enabled = UserDefaults(suiteName: FinderHostLocation.bundleID)?.object(forKey: "files.enabled") as? Bool ?? true
        if !enabled && !isTest {
            NoticeCenter.shared.report(UserFacingError("访达与文件功能已停用，请在 iTools 设置中开启。"))
        } else if request.paths.contains(where: { !AdvancedFiles.exists($0) }) {
            NoticeCenter.shared.report(UserFacingError("所选项目已移动、删除或无法访问。请重新选择后重试。"))
        } else {
            files.performAction(request.action)
        }
        executing = false
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in self?.tick() }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }

    private func tick() {
        guard let request = active, !executing, NSApp.modalWindow == nil else { return }
        if files.working {
            if files.systemOperationInProgress { progress?.close(); progress = nil; progressLabel = nil }
            else if Date().timeIntervalSince(started) > 0.6 && !isTest { showProgress(request) }
            return
        }
        executing = true
        progress?.close(); progress = nil; progressLabel = nil
        if errors.isEmpty {
            if request.action == "scan" {
                let rows = files.scanEntries.prefix(100).map { "\(bytes($0.bytes))\t\($0.url.lastPathComponent)" }.joined(separator: "\n")
                present(title: "扫描结果", text: files.scanSummary + "\n\n" + rows)
            } else if !files.operationIssues.isEmpty {
                present(title: "操作结果", text: files.result)
            } else if ["hash", "archive-test", "favorites", "new-template"].contains(request.action),
                      !files.result.isEmpty {
                present(title: FinderActions.action(request.action)?.title ?? "操作结果", text: files.result)
            }
        }
        writeTestReceipt(request)
        active = nil; executing = false; timer?.invalidate(); timer = nil
        scheduleIdleExit()
        DispatchQueue.main.async { self.startNext() }
    }

    private func showProgress(_ request: FinderDirectRequest) {
        if progress == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 390, height: 106),
                                styleMask: [.titled, .nonactivatingPanel, .utilityWindow], backing: .buffered, defer: false)
            panel.title = "iTools · " + (FinderActions.action(request.action)?.title ?? "访达操作")
            panel.isReleasedWhenClosed = false; panel.level = .floating
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            let spinner = NSProgressIndicator(frame: NSRect(x: 18, y: 63, width: 20, height: 20))
            spinner.style = .spinning; spinner.startAnimation(nil); panel.contentView?.addSubview(spinner)
            let label = NSTextField(wrappingLabelWithString: "正在处理…")
            label.frame = NSRect(x: 50, y: 40, width: 320, height: 46); panel.contentView?.addSubview(label)
            progressLabel = label
            if request.action == "scan" {
                let cancel = NSButton(title: "停止扫描", target: self, action: #selector(cancelScan))
                cancel.frame = NSRect(x: 275, y: 8, width: 95, height: 28); panel.contentView?.addSubview(cancel)
            }
            panel.center(); panel.orderFrontRegardless(); progress = panel
        }
        progressLabel?.stringValue = request.action == "scan" ? files.scanSummary : (files.result.isEmpty ? "正在处理所选文件…" : files.result)
    }
    @objc private func cancelScan() { files.scanCancellation?.cancel() }

    private func present(title: String, text: String) {
        dialogs.append(title)
        guard !isTest else { return }
        progress?.orderOut(nil)
        Panels.activateIfNeeded()
        let alert = NSAlert(); alert.messageText = title
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: text.count > 200 ? 280 : 100))
        scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        let view = NSTextView(frame: scroll.bounds); view.isEditable = false; view.isSelectable = true
        view.font = .systemFont(ofSize: 13); view.string = text
        view.textContainerInset = NSSize(width: 10, height: 10)
        view.isVerticallyResizable = true; view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true; scroll.documentView = view
        alert.accessoryView = scroll; alert.addButton(withTitle: "完成"); alert.addButton(withTitle: "复制结果")
        if alert.runModal() == .alertSecondButtonReturn { copyText(text) }
    }

    private func scheduleIdleExit() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: false) { [weak self] _ in
            guard let self = self, self.active == nil, self.queued.isEmpty else { return }
            self.files.archivePassword = nil; self.files.cutFiles = []
            NSApp.terminate(nil)
        }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if files.working || executing || active != nil || !queued.isEmpty { return .terminateCancel }
        files.archivePassword = nil; return .terminateNow
    }

    private func writeTestReceipt(_ request: FinderDirectRequest) {
        guard isTest, let path = ProcessInfo.processInfo.environment["ITOOLS_FINDER_TEST_OUTPUT"] else { return }
        let receipt: [String: Any] = ["action": request.action, "paths": request.paths.map(\.path),
            "selection": files.selection.map(\.path), "revealed": files.revealedFiles.map(\.path),
            "terminalDirectory": files.openedDirectory?.path ?? "", "cut": files.cutFiles.map(\.path),
            "fileClipboard": files.fileClipboard.files.map(\.path), "applications": files.openedApplications.map(\.path),
            "recycled": Dictionary(uniqueKeysWithValues: files.recycledFiles.map { ($0.key.path, $0.value.path) }),
            "result": files.result, "errors": errors, "dialogs": dialogs,
            "visibleWindows": NSApp.windows.filter(\.isVisible).count,
            "policy": NSApp.activationPolicy().rawValue, "pid": ProcessInfo.processInfo.processIdentifier]
        do {
            let data = try JSONSerialization.data(withJSONObject: receipt, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: URL(fileURLWithPath: path).appendingPathComponent(request.id.uuidString + ".json"), options: .atomic)
        } catch { NSLog("iTools Finder test receipt: %@", error.localizedDescription) }
    }
}
