import AppKit
import SwiftUI
import Carbon
import IToolsCore

enum ShortcutWorkspaceSmokeChecks {
    static func run(model: AppModel, destination: URL, completion: @escaping (Error?) -> Void) {
        let manager = model.shortcuts, catalog = model.shortcuts.preferences.actions
        let original = manager.preferences.bindings
        let savedData = UserDefaults.standard.data(forKey: "shortcuts.v1")
        let originalRun = manager.run
        let guide = ShortcutGuideController(model: model)
        let action = catalog.first { $0.id == "clipboard.record" }!
        var blocker: EventHotKeyRef?
        func require(_ condition: Bool, _ message: String) throws {
            if !condition { throw UserFacingError("Shortcut workspace: " + message) }
        }
        func finish(_ error: Error?) {
            if let blocker = blocker { UnregisterEventHotKey(blocker) }
            guide.close(); manager.stop(); manager.run = originalRun
            _ = manager.set(original[action.id], for: action.id)
            completion(error)
        }
        do {
            let organized = ShortcutDirectory.sections(actions: catalog, category: nil)
            let ids = organized.flatMap(\.actions).map(\.id)
            try require(Set(ids) == Set(catalog.map(\.id)) && ids.count == catalog.count, "catalog lost or duplicated actions")
            try require(ShortcutCategory.allCases.allSatisfy { category in organized.contains { $0.category == category } }, "empty top-level category")
            let searched = ShortcutDirectory.sections(actions: catalog, category: nil, query: "菜单栏", bindings: original)
            try require(Set(searched.map(\.category)).count >= 2, "global search did not cross categories")
        } catch { finish(error); return }
        // No real command executes even if a queued event reaches this diagnostic instance.
        manager.run = { _ in }; manager.start()
        guide.show(category: .clipboard)
        // Finish the first layout/search-focus transaction before simulating a user's click to record.
        // Starting before the first frame can race TextField's initial focus and cancel the synthetic edit.
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        guide.editor.begin(action)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            do {
                try require(guide.panel.isKeyWindow && manager.isEditing, "inline editor not active")
                try require(guide.panel.firstResponder.map { String(describing: type(of: $0)).contains("RecorderView") } == true,
                            "inline field did not receive keyboard focus")
                let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                    windowNumber: guide.panel.windowNumber, context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)!
                guide.panel.firstResponder?.keyDown(with: event)
                try require(!guide.editor.error.isEmpty, "bare typing was accepted as a global chord")
                let conflict = original.first { $0.key != action.id }!.value
                guide.editor.receive(conflict); guide.editor.save()
                try require(!guide.editor.error.isEmpty && manager.preferences.bindings == original, "duplicate chord changed a binding")
                let candidate = [103, 111, 100, 101].map { KeyChord(UInt32($0), 15) }.first { !original.values.contains($0) }!
                let modifiers = UInt32(cmdKey | optionKey | controlKey | shiftKey)
                let code = RegisterEventHotKey(candidate.key, modifiers, EventHotKeyID(signature: 0x4954534D, id: 9910), GetApplicationEventTarget(), 0, &blocker)
                try require(code == noErr, "could not reserve the OS conflict fixture")
                guide.editor.receive(candidate); guide.editor.save()
                try require(!guide.editor.error.isEmpty && manager.preferences.bindings == original && manager.isEditing,
                            "OS conflict did not preserve the previous binding and editor")
                if let item = blocker { UnregisterEventHotKey(item); blocker = nil }
                guide.editor.receive(candidate); guide.editor.save()
                try require(manager.preferences.bindings[action.id] == candidate && guide.editor.action == nil && !manager.isEditing,
                            "inline save did not commit and restore dispatch")
                guide.editor.clear(action)
                try require(manager.preferences.bindings[action.id] == nil, "clear did not remove binding")
                guide.editor.begin(action); guide.editor.receive(KeyChord(53, 0))
                try require(guide.editor.action == nil && !manager.isEditing && guide.panel.isVisible, "Esc did not cancel only the edit")
                guide.editor.begin(action); guide.state.query = "新建"
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    do {
                        try require(guide.editor.action == nil && !manager.isEditing, "search left global shortcuts suspended")
                        guide.state.query = ""; guide.show(category: .windows)
                        try require(guide.state.category == .windows && guide.panel.isVisible, "context entry did not open the same workspace")
                        guide.editor.begin(action); guide.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: guide.panel))
                        try require(!manager.isEditing && guide.editor.action == nil, "focus loss did not end recording")
                        guide.show(toggle: true)
                        try require(!guide.panel.isVisible, "global toggle failed to close workspace")
                        manager.stop(); _ = manager.set(original[action.id], for: action.id)
                        try require(manager.preferences.bindings == original, "diagnostic did not restore bindings")
                        try render(model: model, destination: destination)
                        try require(UserDefaults.standard.data(forKey: "shortcuts.v1") == savedData, "diagnostic wrote user's shortcut preferences")
                        print("PASS: unified shortcut workspace; all \(catalog.count) commands classified exactly once; cross-category search; real inline responder; duplicate/OS conflict preservation; save/clear/Esc/search/focus cleanup; category entry and toggle; original bindings retained")
                        finish(nil)
                    } catch { finish(error) }
                }
            } catch { finish(error) }
        }
    }
    private static func render(model: AppModel, destination: URL) throws {
        let previews: [(String, ShortcutCategory, String, Bool, Bool, NSSize)] = [
            ("shortcut-guide", .general, "", false, false, NSSize(width: 1080, height: 760)),
            ("shortcut-clipboard", .clipboard, "", false, false, NSSize(width: 1080, height: 760)),
            ("shortcut-guide-dark", .clipboard, "", false, true, NSSize(width: 1080, height: 760)),
            ("shortcut-narrow", .capture, "", false, false, NSSize(width: 810, height: 640)),
            ("shortcut-files", .files, "", false, false, NSSize(width: 1080, height: 760)),
            ("shortcut-search", .general, "菜单栏", false, false, NSSize(width: 1080, height: 760)),
            ("shortcut-empty", .general, "no-such-feature", true, false, NSSize(width: 1080, height: 760)),
            ("shortcut-assigned", .capture, "", true, false, NSSize(width: 1080, height: 760)),
            ("shortcut-editing", .clipboard, "", false, false, NSSize(width: 1080, height: 760))
        ]
        for (name, category, query, assigned, dark, size) in previews {
            let state = ShortcutWorkspaceState(); state.category = category; state.query = query; state.assignedOnly = assigned
            let editor = ShortcutEditor(manager: model.shortcuts)
            if name == "shortcut-editing" {
                editor.begin(model.shortcuts.preferences.actions.first { $0.id == "clipboard.record" }!)
                editor.receive(model.shortcuts.preferences.bindings["app.guide"] ?? KeyChord(44, 5))
            }
            defer { editor.cancel() }
            let content = ShortcutGuideView(manager: model.shortcuts, state: state, editor: editor, clipboard: model.clipboardPanel, close: {}, run: { _ in })
            try ShortcutSmokeChecks.export(content, size: size, name: name, destination: destination, dark: dark)
        }
        print("PASS: shortcut workspace light/dark, clipboard controls, narrow single-column layout, file groups, global search, empty/assigned filters and inline conflict rendering")
    }
}
