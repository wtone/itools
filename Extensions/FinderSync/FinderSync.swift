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
        let workspace = NSWorkspace.shared
        let fallbacks = [URL(fileURLWithPath: "/Applications/iTools.app"),
                         FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/iTools.app")] +
                        (workspace.urlForApplication(withBundleIdentifier: FinderHostLocation.bundleID).map { [$0] } ?? [])
        guard let host = FinderHostLocation.resolve(extensionURL: Bundle(for: IToolsFinderSync.self).bundleURL,
                                                    fallbacks: fallbacks, valid: FinderHostLocation.isHost) else {
            showFailure("找不到 iTools 主程序。请从「应用程序」打开 iTools 一次，然后重试。"); return
        }
        let worker = FinderHostLocation.worker(in: host)
        guard FinderHostLocation.isWorker(worker), let request = FinderDirectRequest.makeURL(from: url) else {
            showFailure("访达操作组件缺失，请重新安装完整的 iTools.app。"); return
        }
        guard let configuration = FinderLaunchEvent.configuration(for: [request]) else {
            showFailure("访达请求无效，请重新打开右键菜单后重试。"); return
        }
        workspace.openApplication(at: worker, configuration: configuration) { [weak self] app, error in
            if let error = error {
                let error = error as NSError
                let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError ?? error
                NSLog("iTools Finder launch failed: %@ (%ld), underlying %@ (%ld)", error.domain, error.code, underlying.domain, underlying.code)
                DispatchQueue.main.async { self?.showFailure("无法启动访达操作组件：\(error.localizedDescription)\n错误代码：\(underlying.domain) \(underlying.code)") }
            } else if app == nil { DispatchQueue.main.async { self?.showFailure("系统没有返回 iTools 启动结果，请手动打开应用后重试。") } }
        }
    }
    private func showFailure(_ message: String) {
        NSLog("iTools Finder: %@", message)
        let alert = NSAlert(); alert.messageText = "iTools 访达操作未能打开"; alert.informativeText = message
        alert.addButton(withTitle: "知道了"); alert.window.level = .floating
        NSApp.activate(ignoringOtherApps: true); alert.runModal()
    }
}
