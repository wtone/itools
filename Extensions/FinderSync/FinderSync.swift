import AppKit
import FinderSync

@objc(IToolsFinderSync)
final class IToolsFinderSync: FIFinderSync {
    private let requests = FinderMenuRequests()
    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/Users"), URL(fileURLWithPath: "/Volumes")]
    }
    override var toolbarItemName: String { "iTools" }
    override var toolbarItemToolTip: String { "iTools 访达工具" }
    override var toolbarItemImage: NSImage {
        NSImage(systemSymbolName: "folder.badge.gearshape", accessibilityDescription: "iTools") ?? NSImage()
    }
    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        let controller = FIFinderSyncController.default()
        // A blank-area click must not reuse another selection in the window.
        let selected = menuKind == .contextualMenuForContainer ? [] : controller.selectedItemURLs() ?? []
        let target = controller.targetedURL()
        let files = selected.isEmpty ? target.map { [$0] } ?? [] : selected
        let directory = target.map { [$0] } ?? files
        return FinderMenuBuilder(requests: requests, target: self, selector: #selector(invoke(_:)))
            .menu(layout: FinderMenuLayout.load(), files: files, directory: directory)
    }
    @objc private func invoke(_ sender: NSMenuItem) {
        guard let url = requests.request(tag: sender.tag) else {
            showFailure("访达菜单已更新，请关闭右键菜单后重新打开，再选择操作。"); return
        }
        let hosts = FinderHostLocation.launchCandidates(extensionURL: Bundle(for: IToolsFinderSync.self).bundleURL,
            registeredHost: NSWorkspace.shared.urlForApplication(withBundleIdentifier: FinderHostLocation.bundleID))
        guard !hosts.isEmpty else {
            showFailure("找不到 iTools 主程序。请从「应用程序」打开 iTools 一次，然后重试。"); return
        }
        guard let request = FinderDirectRequest.makeURL(from: url),
              let configuration = FinderLaunchEvent.configuration(for: [request]) else {
            showFailure("访达请求无效，请重新打开右键菜单后重试。"); return
        }
        launch(hosts, configuration: configuration)
    }
    private func launch(_ hosts: [URL], configuration: NSWorkspace.OpenConfiguration) {
        NSWorkspace.shared.openApplication(at: FinderHostLocation.worker(in: hosts[0]), configuration: configuration) { [weak self] app, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard let error = error as NSError? else {
                    if app == nil { self.showFailure("系统没有返回 iTools 启动结果，请手动打开应用后重试。") }
                    return
                }
                let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError ?? error
                NSLog("iTools Finder launch failed: %@ (%ld), underlying %@ (%ld)", error.domain, error.code, underlying.domain, underlying.code)
                // Only retry an explicit pre-launch missing-app failure. A
                // timeout/unknown result must not replay a destructive action.
                let missing = [error, underlying].contains {
                    ($0.domain == NSOSStatusErrorDomain && [-43, -10811, -10814, -10827].contains($0.code)) ||
                    ($0.domain == NSCocoaErrorDomain && [NSFileNoSuchFileError, NSFileReadNoSuchFileError].contains($0.code))
                }
                if hosts.count > 1 && app == nil && missing { self.launch(Array(hosts.dropFirst()), configuration: configuration) }
                else { self.showFailure("无法启动访达操作组件：\(error.localizedDescription)\n请重新打开完整的 iTools.app 后重试。\n错误代码：\(underlying.domain) \(underlying.code)") }
            }
        }
    }
    private func showFailure(_ message: String) {
        NSLog("iTools Finder: %@", message)
        guard let url = FinderLaunchFailure.makeURL(message) else { return }
        let hosts = FinderHostLocation.launchCandidates(extensionURL: Bundle(for: IToolsFinderSync.self).bundleURL,
            registeredHost: NSWorkspace.shared.urlForApplication(withBundleIdentifier: FinderHostLocation.bundleID))
        presentFailure(url, hosts: hosts)
    }
    private func presentFailure(_ url: URL, hosts: [URL]) {
        guard let host = hosts.first else { NSWorkspace.shared.open(url); return }
        let config = NSWorkspace.OpenConfiguration(); config.activates = true
        config.addsToRecentItems = false; config.promptsUserIfNeeded = false
        config.allowsRunningApplicationSubstitution = false
        NSWorkspace.shared.open([url], withApplicationAt: host, configuration: config) { [weak self] app, error in
            // Retrying a display-only message cannot repeat a file operation.
            if (error != nil || app == nil) && hosts.count > 1 {
                DispatchQueue.main.async { self?.presentFailure(url, hosts: Array(hosts.dropFirst())) }
            } else if let error = error { NSLog("iTools Finder error presentation failed: %@", error.localizedDescription) }
        }
    }
}
