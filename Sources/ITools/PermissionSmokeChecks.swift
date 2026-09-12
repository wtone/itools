import AppKit
import AVFoundation
import IToolsCore

enum PermissionSmokeChecks {
    static func run(mainWindow: NSWindow, destination: URL, completion: @escaping (Error?) -> Void) {
        let center = PermissionCenter.shared
        let original = center.readStatus
        let clipboardCount = NSPasteboard.general.changeCount
        func finish(_ error: Error?) {
            center.close(); center.readStatus = original; center.refresh(); completion(error)
        }
        func require(_ value: Bool, _ message: String) throws {
            if !value { throw UserFacingError("Permission smoke: " + message) }
        }
        do {
            center.readStatus = { (false, false, false, .denied) }
            let service = ClipboardService()
            let entry = ClipEntry(kind: .text, text: "iTools permission test; do not paste", source: "Own smoke fixture", payload: [])
            try require(!service.copy(entry, paste: true), "denied paste accepted")
            let firstWindow = center.windowForChecks
            try require(firstWindow?.isVisible == true, "guidance window hidden")
            service.enqueue(entry); service.pasteNext()
            try require(service.stackCount == 1, "denied paste consumed queue head")
            try require(center.windowForChecks === firstWindow, "duplicate permission window created")
            try require(NSPasteboard.general.changeCount == clipboardCount, "denied paste changed user's clipboard")
            guard let window = firstWindow, let view = window.contentView else { throw UserFacingError("Permission smoke: no window") }
            // Let the main dispatch queue process application activation notifications. A nested
            // RunLoop inside the previous test's main-queue block cannot drain that queue.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                NSApp.activate(ignoringOtherApps: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    do {
                        mainWindow.orderFront(nil); window.makeKeyAndOrderFront(nil)
                        print("Permission presentation: visible=\(window.isVisible), key=\(window.isKeyWindow), canBecomeKey=\(window.canBecomeKey), appActive=\(NSApp.isActive), levels=\(window.level.rawValue)/\(mainWindow.level.rawValue)")
                        try require(window.level.rawValue > mainWindow.level.rawValue && window.isKeyWindow, "guidance can be covered by main window")
                        try require(window.hidesOnDeactivate, "guidance would stay in front of System Settings")
                        view.layoutSubtreeIfNeeded()
                        if let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                            view.cacheDisplay(in: view.bounds, to: bitmap)
                            try bitmap.representation(using: .png, properties: [:])?.write(to: destination.appendingPathComponent("permission-guide.png"))
                        }
                        // Refresh checks do not replay the denied operation, emit keystrokes or consume the queue.
                        center.readStatus = { (true, false, true, .authorized) }; center.refresh()
                        try require(!center.allowed, "AX authorization incorrectly implies event posting")
                        center.readStatus = { (true, true, true, .authorized) }; center.refresh()
                        try require(center.allowed && service.stackCount == 1, "grant did not refresh or replayed a paste")
                        try require(NSPasteboard.general.changeCount == clipboardCount, "refresh posted/changed clipboard")
                        print("PASS: single frontmost permission guide; separate AX/event-posting checks; live refresh without replay; denied paste preserves clipboard and queue; no actual permission requests or keystrokes")
                        finish(nil)
                    } catch { finish(error) }
                }
            }
        } catch { finish(error) }
    }
}
