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
        requests.beginMenu()
        let menu = NSMenu(title: "iTools")
        let controller = FIFinderSyncController.default()
        // A blank-area click must not reuse items selected elsewhere in the window.
        let selected = menuKind == .contextualMenuForContainer ? [] : controller.selectedItemURLs() ?? []
        let target = controller.targetedURL()
        let files = selected.isEmpty ? target.map { [$0] } ?? [] : selected
        let directory = target.map { [$0] } ?? files
        let root = NSMenuItem(title: "iTools 访达工具", action: nil, keyEquivalent: "")
        root.image = toolbarItemImage
        let tools = NSMenu(title: root.title); root.submenu = tools; menu.addItem(root)
        for group in FinderActions.groups {
            let item = NSMenuItem(title: group.title, action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: group.icon, accessibilityDescription: nil)
            let submenu = NSMenu(title: group.title); item.submenu = submenu; tools.addItem(item)
            for action in group.actions {
                if action.id == "open-with" { addApplications(paths: files, to: submenu); continue }
                add(action.title, action: action.id, paths: action.directory ? directory : files, to: submenu)
            }
        }
        return menu
    }
    private func addApplications(paths: [URL], to menu: NSMenu) {
        let item = NSMenuItem(title: "打开方式", action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: item.title); item.submenu = submenu; menu.addItem(item)
        add("使用系统默认应用", action: "open-with", paths: paths, application: "system-default", to: submenu)
        let apps = FinderApplications.common(for: paths) { NSWorkspace.shared.urlsForApplications(toOpen: $0) }
        var seen = Set<String>()
        for app in apps {
            guard let bundle = Bundle(url: app), let id = bundle.bundleIdentifier,
                  !id.hasPrefix("app.itools.mac"), seen.insert(id).inserted else { continue }
            let title = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? app.deletingPathExtension().lastPathComponent
            add(title, action: "open-with", paths: paths, application: app.path, to: submenu)
            submenu.items.last?.image = NSWorkspace.shared.icon(forFile: app.path)
            submenu.items.last?.image?.size = NSSize(width: 16, height: 16)
        }
        submenu.addItem(.separator())
        add("其他应用…", action: "open-with", paths: paths, to: submenu)
    }
    private func add(_ title: String, action: String, paths: [URL], application: String? = nil, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: #selector(invoke(_:)), keyEquivalent: "")
        item.target = self
        if let url = FinderMenuRequests.makeURL(action: action, paths: paths, application: application) {
            item.tag = requests.insert(url); item.isEnabled = true
        } else { item.tag = 0; item.isEnabled = false }
        menu.addItem(item)
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
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        workspace.open([request], withApplicationAt: worker, configuration: configuration) { [weak self] app, error in
            if let error = error {
                DispatchQueue.main.async { self?.showFailure("无法执行访达操作：\(error.localizedDescription)") }
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
