import SwiftUI
import IToolsCore

final class ShortcutWorkspaceState: ObservableObject {
    @Published var category: ShortcutCategory = .general
    @Published var query = ""
    @Published var assignedOnly = false
    @Published var searchRequest = 0
    var isSearching: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

final class ShortcutEditor: ObservableObject {
    @Published private(set) var action: ShortcutAction?
    @Published private(set) var candidate: KeyChord?
    @Published private(set) var error = ""
    @Published private(set) var message = ""
    let manager: ShortcutManager
    init(manager: ShortcutManager) { self.manager = manager }
    func begin(_ action: ShortcutAction) {
        self.action = action; candidate = nil; error = ""; message = ""
        manager.isEditing = true; manager.suspend(true)
    }
    func receive(_ chord: KeyChord) {
        guard let action = action else { return }
        if chord.key == 53 { cancel(); return }
        candidate = chord; error = manager.preferences.error(for: chord, action: action.id) ?? ""
    }
    func save() {
        guard let action = action, let chord = candidate else { return }
        error = manager.preferences.error(for: chord, action: action.id) ?? ""
        guard error.isEmpty else { return }
        // Resume OS registration while keeping command dispatch suppressed until editing has ended.
        manager.suspend(false)
        if let failure = manager.set(chord, for: action.id) { error = failure; manager.suspend(true); return }
        message = "已保存「\(action.title)」的快捷键"
        cancel()
    }
    func cancel() {
        guard action != nil else { return }
        action = nil; candidate = nil; error = ""
        manager.suspend(false); manager.isEditing = false
    }
    func clear(_ action: ShortcutAction) {
        cancel()
        if let failure = manager.set(nil, for: action.id) { message = failure }
        else { message = "已清除「\(action.title)」的快捷键" }
    }
}
