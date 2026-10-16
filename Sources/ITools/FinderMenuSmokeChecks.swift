import AppKit
import SwiftUI
import IToolsCore

enum FinderMenuSmokeChecks {
    final class Callback: NSObject { @objc func invoke(_ sender: NSMenuItem) {} }
    static func run(destination: URL) throws {
        func check(_ value: Bool, _ message: String) throws { if !value { throw UserFacingError("Finder menu smoke: " + message) } }
        let store = FinderMenuRequests(), callback = Callback()
        let builder = FinderMenuBuilder(requests: store, target: callback, selector: #selector(Callback.invoke(_:)), applicationLookup: { _ in [] })
        let selected = [URL(fileURLWithPath: "/tmp/所选 & # 文件.txt")]
        let directory = [URL(fileURLWithPath: "/tmp/实际目录", isDirectory: true)]
        func leaves(_ menu: NSMenu) -> [NSMenuItem] {
            menu.items.flatMap { $0.submenu.map(leaves) ?? ($0.isSeparatorItem ? [] : [$0]) }
        }
        for layout in [FinderMenuLayout(), .common, FinderMenuLayout(topLevelIDs: ["open-with"]),
                       FinderMenuLayout(topLevelIDs: Set(FinderActions.all.map(\.id)))] {
            let menu = builder.menu(layout: layout, files: selected, directory: directory)
            let root = menu.items.first { $0.title == "iTools 访达工具" }
            let top = menu.items.filter { !$0.isSeparatorItem && $0 !== root }
            try check(top.count == layout.topLevelActions.count, "wrong top-level count")
            try check((root == nil) == layout.remainingGroups.isEmpty, "empty root or missing submenu")
            var seen: [String] = []
            for item in leaves(menu) {
                guard let url = store.request(tag: item.tag), let encoded = FinderDirectRequest.makeURL(from: url),
                      let request = FinderDirectRequest(encoded), let action = FinderActions.action(request.action) else {
                    throw UserFacingError("Finder menu smoke: missing tag route")
                }
                try check(item.representedObject == nil && item.target === callback, "callback target changed")
                try check(request.paths.map(\.path) == (action.directory ? directory : selected).map(\.path), "incorrect files/directory for " + action.id)
                seen.append(action.id)
            }
            try check(Set(seen) == Set(FinderActions.all.map(\.id)), "an action disappeared")
            try check(seen.count == FinderActions.all.count + 1, "duplicate action outside open-with choices")
            if let root = root?.submenu {
                for item in leaves(root) {
                    let url = store.request(tag: item.tag)!
                    let request = FinderDirectRequest(FinderDirectRequest.makeURL(from: url)!)!
                    try check(!layout.topLevelIDs.contains(request.action), "promoted action still nested")
                }
            }
            if layout.topLevelIDs.contains("open-with") {
                let apps = top.first { $0.title == "iTools · 打开方式" }?.submenu
                try check(apps?.items.first?.title == "使用系统默认应用" && apps?.items.last?.title == "其他应用…", "open-with lost native choices")
            }
        }
        let empty = builder.menu(layout: .common, files: [], directory: [])
        for item in leaves(empty) {
            if let url = store.request(tag: item.tag), let encoded = FinderDirectRequest.makeURL(from: url),
               let request = FinderDirectRequest(encoded) {
                try check(FinderActions.action(request.action)?.requiresPaths == false && item.isEnabled && request.paths.isEmpty,
                          "empty selection enabled a file command")
            } else { try check(!item.isEnabled && item.tag == 0, "empty selection lost disabled file command") }
        }
        do {
            let visibilityBuilder = FinderMenuBuilder(requests: store, target: callback, selector: #selector(Callback.invoke(_:)),
                applicationLookup: { _ in [] })
            for layout in [FinderMenuLayout(), FinderMenuLayout(topLevelIDs: [FinderActions.visibilityActionID])] {
                let menu = visibilityBuilder.menu(layout: layout, files: [], directory: [])
                for id in [FinderActions.visibilityActionID] {
                    let item = leaves(menu).first { item in
                        guard let url = store.request(tag: item.tag), let encoded = FinderDirectRequest.makeURL(from: url) else { return false }
                        return FinderDirectRequest(encoded)?.action == id
                    }
                    try check(item?.isEnabled == true && item?.state == .off,
                              "hidden-files toggle must be neutral and enabled without selection")
                }
            }
        }
        let preferences = FinderMenuPreferences(persist: false)
        let saved = FinderMenuLayout.load()
        preferences.apply(.common)
        for (name, appearance) in [("finder-menu-settings", NSAppearance.Name.aqua), ("finder-menu-settings-dark", .darkAqua)] {
            let host = NSHostingView(rootView: FinderMenuSettingsView(preferences: preferences)
                .environment(\.colorScheme, appearance == .darkAqua ? .dark : .light))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 660),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: appearance); window.contentView = host
            defer { window.close() }
            host.frame = NSRect(x: 0, y: 0, width: 780, height: 660)
            host.appearance = NSAppearance(named: appearance)
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
            try WindowGlassChecks.verifyMaterial(window, material: .hudWindow)
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw UserFacingError("Finder settings bitmap failed") }
            host.cacheDisplay(in: host.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name + ".png"))
        }
        preferences.set("terminal", enabled: false)
        try check(!preferences.layout.topLevelIDs.contains("terminal"), "toggle did not update selection")
        try check(FinderMenuLayout.load() == saved, "smoke changed the user's layout")
        print("PASS: actual Finder NSMenu none/mixed/all placement; \(FinderActions.all.count) actions preserved; hidden-file state and selection-free routes; no duplicate promoted actions; tag-only paths; native open-with choices; settings light/dark; user layout untouched")
    }
}
