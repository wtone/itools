import AppKit
import ObjectiveC
import SystemBridge
import IToolsCore

enum MenuBarPlacementSmokeChecks {
    static func run(item: NSStatusItem, scope: MenuBarDisplayScope, destination: URL) throws {
        guard let screen = NSScreen.screens.first, let right = screen.auxiliaryTopRightArea else {
            print("SKIP: native notch recovery requires a notched primary display"); return
        }
        let originalName = item.autosaveName
        let name = "iTools.notch-check." + UUID().uuidString
        let key = "NSStatusItem Preferred Position " + name
        func check(_ condition: Bool, _ text: String) throws {
            if !condition { throw UserFacingError("Smoke: " + text) }
        }
        func settle(_ seconds: TimeInterval) {
            let deadline = Date().addingTimeInterval(seconds)
            while Date() < deadline {
                scope.refresh(); RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            }
        }
        func visible() -> Bool {
            guard let button = item.button, let frame = MenuBarDisplayScope.buttonScreenRect(button) else { return false }
            return MenuBarPlacement.isFrameVisible(frame, screen: screen.frame, rightArea: right)
        }
        // Set this process's native registry and window to a misplaced layout.
        // A registry preference alone does not move a WindowServer slot; the
        // actual window geometry below is what the recovery must detect.
        guard let ivar = class_getInstanceVariable(NSStatusItem.self, "_cgsItem"),
              let root = object_getIvar(item, ivar) as? NSObject,
              let method = class_getInstanceMethod(object_getClass(root), NSSelectorFromString("setPreferredPosition:")),
              let layoutMethod = class_getInstanceMethod(NSStatusItem.self, NSSelectorFromString("_updateItemForCurrentMetrics")) else {
            throw UserFacingError("Smoke: native position setter unavailable")
        }
        let selector = NSSelectorFromString("setPreferredPosition:")
        let setPosition = unsafeBitCast(method_getImplementation(method), to: (@convention(c) (AnyObject, Selector, Float) -> Void).self)
        let relayout = unsafeBitCast(method_getImplementation(layoutMethod), to: (@convention(c) (AnyObject, Selector) -> Void).self)
        func place(_ position: Float) throws {
            guard let current = object_getIvar(item, ivar) as? NSObject else { throw UserFacingError("Smoke: native item registry disappeared") }
            if let autosave = item.autosaveName {
                UserDefaults.standard.set(Double(position), forKey: "NSStatusItem Preferred Position " + autosave)
            }
            setPosition(current, selector, position)
            scope.refresh() // retain the native preferred value before relayout
            item.isVisible = false
            if let hiddenRoot = object_getIvar(item, ivar) as? NSObject { setPosition(hiddenRoot, selector, position) }
            item.isVisible = true
            relayout(item, NSSelectorFromString("_updateItemForCurrentMetrics"))
        }
        defer {
            item.autosaveName = originalName
            scope.restoreDefaultPosition(on: screen); settle(5)
            for key in UserDefaults.standard.dictionaryRepresentation().keys where key.contains(name) { UserDefaults.standard.removeObject(forKey: key) }
        }
        // Startup sanitization uses the real display's usable width, not a model
        // name or hard-coded notch coordinates.
        UserDefaults.standard.set(right.width + 63, forKey: key)
        MenuBarDisplayScope.prepareAutosave(name)
        try check(UserDefaults.standard.double(forKey: key) == 0, "hidden saved position survived startup preparation")
        item.autosaveName = name
        scope.restoreDefaultPosition(on: screen)
        settle(5); try check(visible(), "startup repair did not produce a visible item")
        let initialLeft = item.button.flatMap { MenuBarDisplayScope.buttonScreenRect($0) }
        try place(0); settle(0.4)
        let rightmost = item.button.flatMap { MenuBarDisplayScope.buttonScreenRect($0) }
        scope.restoreDefaultPosition(on: screen); settle(5)
        let leftmost = item.button.flatMap { MenuBarDisplayScope.buttonScreenRect($0) }
        try check(visible() && (leftmost?.minX ?? .infinity) < (rightmost?.minX ?? 0), "default did not move left of the old rightmost slot; initial=\(initialLeft as Any) right=\(rightmost as Any) left=\(leftmost as Any)")
        let badPosition = Float(right.width + 63)
        try place(badPosition); UserDefaults.standard.set(Double(badPosition), forKey: key)
        if let window = item.button?.window {
            var frame = window.frame
            frame.origin.x = right.minX - frame.width / 2
            frame.origin.y = screen.frame.maxY - frame.height
            window.setFrame(frame, display: true)
        }
        settle(0.15)
        let misplacedFrame = item.button.flatMap { MenuBarDisplayScope.buttonScreenRect($0) }
        try check(!visible(), "native misplaced-item regression did not reproduce the notch collision; frame=\(misplacedFrame as Any)")
        settle(5); try check(visible(), "live notch collision was not automatically repaired")
        let recoveredFrame = item.button.flatMap { MenuBarDisplayScope.buttonScreenRect($0) }
        try scope.verifyCurrentDisplay()
        try check(MenuBarPlacement.isSavedPositionUsable(UserDefaults.standard.double(forKey: key), screen: screen.frame, rightArea: right), "repair left a hidden position saved")
        try place(60); UserDefaults.standard.set(60, forKey: key)
        settle(1.2); try check(visible(), "ordinary position lost visibility")
        try check(UserDefaults.standard.double(forKey: key) == 60, "recovery overwrote a valid user position")
        // A new saved position can become invalid even while the native entry is
        // uninstalled. Reinstallation must repair the live cached value as well.
        item.isVisible = false
        UserDefaults.standard.set(Double(badPosition), forKey: key)
        item.isVisible = true; try place(badPosition); settle(5)
        try check(visible(), "hidden/reinstalled item retained a notch-obscured position")
        try scope.verifyCurrentDisplay()
        try "PASS: left default, saved out-of-range position, live notch collision, valid position preserved, hidden/reinstalled recovery; primary only\ninitialLeft=\(initialLeft as Any) rightmost=\(rightmost as Any) leftmost=\(leftmost as Any)\nmisplaced=\(misplacedFrame as Any) recovered=\(recoveredFrame as Any) notchRight=\(right)\n"
            .write(to: destination.appendingPathComponent("menu-bar-notch-check.txt"), atomically: true, encoding: .utf8)
        print("PASS: left default replaces rightmost slot; notch startup/live/reinstallation recovery; valid Cmd-drag position preserved; primary-only native item")
    }
}
