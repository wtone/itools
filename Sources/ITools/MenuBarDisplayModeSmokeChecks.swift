import AppKit
import IToolsCore

extension MenuBarMonitor {
    /// Exercise production preference -> scope -> WindowServer, without changing
    /// system display settings or the user's persisted preferences.
    func verifyDisplayModes(preferences: MenuBarPreferences, destination: URL) throws {
        let original = preferences.displaySelection
        let originalIdentity = ObjectIdentifier(statusItem)
        let originalMetrics = preferences.enabledMetrics
        let originalLength = statusItem.length
        var lines: [String] = []
        defer {
            preferences.setDisplaySelection(original)
            for metric in MenuBarMetric.allCases { preferences.set(metric, enabled: originalMetrics.contains(metric)) }
            refreshDisplayConfiguration()
            restoreDefaultPosition()
            RunLoop.main.run(until: Date().addingTimeInterval(1))
        }
        guard let primary = NSScreen.screens.first else { throw UserFacingError("Smoke: no connected screens") }
        func visibleEntries() -> [CGRect] {
            (CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []).compactMap { record in
                guard record[kCGWindowOwnerPID as String] as? Int32 == ProcessInfo.processInfo.processIdentifier,
                      record[kCGWindowLayer as String] as? Int == NSWindow.Level.statusBar.rawValue,
                      let raw = record[kCGWindowBounds as String] as? NSDictionary,
                      let rect = CGRect(dictionaryRepresentation: raw) else { return nil }
                return rect
            }
        }
        func check(_ selection: MenuBarDisplaySelection, name: String, expectedLength: CGFloat? = nil) throws {
            preferences.setDisplaySelection(selection)
            let expected = MenuBarDisplayScope.resolvedScreens(for: selection)
            let deadline = Date().addingTimeInterval(7)
            var frames: [CGRect] = []
            var valid = false
            repeat {
                refreshDisplayConfiguration()
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                frames = visibleEntries()
                valid = statusItem.length == (expectedLength ?? originalLength) && frames.count == expected.count && expected.allSatisfy { screen in
                    let quartz = CGRect(x: screen.frame.minX, y: primary.frame.maxY - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
                    return frames.filter { quartz.contains($0) && abs($0.minY - quartz.minY) < 1 }.count == 1
                }
            } while !valid && Date() < deadline
            guard valid, ObjectIdentifier(statusItem) == originalIdentity else {
                let all = (CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []).filter {
                    $0[kCGWindowOwnerPID as String] as? Int32 == ProcessInfo.processInfo.processIdentifier && $0[kCGWindowLayer as String] as? Int == NSWindow.Level.statusBar.rawValue
                }
                throw UserFacingError("Smoke: display mode \(name) expected \(expected.count) native entries, got \(frames); all=\(all); root=\(statusItem.button?.window?.windowNumber ?? -1)")
            }
            lines.append("PASS \(name) entries=\(frames.count) frames=\(frames)")
        }
        // Repeated round trips must not leak duplicate native replicas.
        for cycle in 1...2 {
            try check(.init(mode: .all), name: "all-\(cycle)")
            NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: NSApp)
            try check(.init(mode: .all), name: "all-refresh-\(cycle)")
            for screen in MenuBarDisplayScope.availableScreens {
                try check(.init(displayID: screen.id, displayName: screen.name), name: "selected-\(screen.name)-\(cycle)")
            }
            try check(.init(displayID: "itools.disconnected.test", displayName: "Disconnected fixture"), name: "missing-target-falls-back-\(cycle)")
            guard preferences.displaySelection.displayID == "itools.disconnected.test" else { throw UserFacingError("Smoke: fallback rewrote saved target") }
            try check(.init(), name: "follow-primary-\(cycle)")
        }
        try check(.init(mode: .all), name: "all-before-disable")
        for metric in MenuBarMetric.allCases { preferences.set(metric, enabled: false) }
        try check(.init(mode: .all), name: "all-off-toolbox-on-each-display", expectedLength: 16)
        for metric in MenuBarMetric.allCases { preferences.set(metric, enabled: originalMetrics.contains(metric)) }
        try check(.init(mode: .all), name: "all-restored-without-duplicate-slots")
        try lines.joined(separator: "\n").write(to: destination.appendingPathComponent("menu-bar-display-modes.txt"), atomically: true, encoding: .utf8)
        print("PASS: all/single/selected display round trips, native replica counts, missing-target fallback and unchanged saved target")
    }
}
