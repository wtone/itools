import AppKit

/// Shared by the extension and native verification, so changing menu placement
/// cannot accidentally change selected paths or the tag-based callback route.
public final class FinderMenuBuilder {
    private let requests: FinderMenuRequests
    private let target: AnyObject
    private let selector: Selector
    private let applicationLookup: (URL) -> [URL]
    public init(requests: FinderMenuRequests, target: AnyObject, selector: Selector,
                applicationLookup: @escaping (URL) -> [URL] = { NSWorkspace.shared.urlsForApplications(toOpen: $0) }) {
        self.requests = requests; self.target = target; self.selector = selector; self.applicationLookup = applicationLookup
    }
    public func menu(layout: FinderMenuLayout, files: [URL], directory: [URL]) -> NSMenu {
        requests.beginMenu()
        let menu = NSMenu(title: "iTools")
        menu.autoenablesItems = false
        for action in layout.topLevelActions {
            add(action, files: files, directory: directory, topLevel: true, to: menu)
        }
        let remaining = layout.remainingGroups
        if !remaining.isEmpty {
            if !layout.topLevelActions.isEmpty { menu.addItem(.separator()) }
            let root = NSMenuItem(title: "iTools 访达工具", action: nil, keyEquivalent: "")
            root.image = NSImage(systemSymbolName: "folder.badge.gearshape", accessibilityDescription: "iTools")
            let submenu = NSMenu(title: root.title); root.submenu = submenu; menu.addItem(root)
            submenu.autoenablesItems = false
            for group in remaining {
                let item = NSMenuItem(title: group.title, action: nil, keyEquivalent: "")
                item.image = NSImage(systemSymbolName: group.icon, accessibilityDescription: nil)
                let children = NSMenu(title: group.title); item.submenu = children; submenu.addItem(item)
                children.autoenablesItems = false
                for action in group.actions { add(action, files: files, directory: directory, topLevel: false, to: children) }
            }
        }
        return menu
    }
    private func add(_ action: FinderAction, files: [URL], directory: [URL], topLevel: Bool, to menu: NSMenu) {
        let title = topLevel ? FinderMenuLayout.topLevelTitle(action) : action.title
        if action.id == "open-with" {
            addApplications(title: topLevel ? "iTools · 打开方式" : "打开方式", paths: files, to: menu)
        } else {
            add(title, action: action.id, paths: action.directory ? directory : files, to: menu)
        }
        if topLevel, let group = FinderActions.groups.first(where: { $0.actions.contains { $0.id == action.id } }) {
            menu.items.last?.image = NSImage(systemSymbolName: group.icon, accessibilityDescription: "iTools")
        }
    }
    private func addApplications(title: String, paths: [URL], to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu(title: item.title); item.submenu = submenu; menu.addItem(item)
        submenu.autoenablesItems = false
        add("使用系统默认应用", action: "open-with", paths: paths, application: "system-default", to: submenu)
        let apps = FinderApplications.common(for: paths, lookup: applicationLookup)
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
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = target
        if let url = FinderMenuRequests.makeURL(action: action, paths: paths, application: application) {
            item.tag = requests.insert(url); item.isEnabled = true
        } else { item.tag = 0; item.isEnabled = false }
        menu.addItem(item)
    }
}
