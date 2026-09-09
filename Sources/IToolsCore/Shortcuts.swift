import Foundation
import Combine

/// Hardware key positions; modifier bits are independent of Carbon/AppKit encodings.
public struct KeyChord: Codable, Hashable {
    public let key: UInt32
    public let modifiers: UInt32
    public init(_ key: UInt32, _ modifiers: UInt32) { self.key = key; self.modifiers = modifiers }
    public static let command: UInt32 = 1, shift: UInt32 = 2, option: UInt32 = 4, control: UInt32 = 8
    public static let names: [UInt32: String] = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"−",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",36:"↩",37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",48:"⇥",49:"Space",50:"`",51:"⌫",53:"Esc",65:"Num .",67:"Num *",69:"Num +",75:"Num /",76:"Num ↩",78:"Num −",82:"Num 0",83:"Num 1",84:"Num 2",85:"Num 3",86:"Num 4",87:"Num 5",88:"Num 6",89:"Num 7",91:"Num 8",92:"Num 9",96:"F5",97:"F6",98:"F7",99:"F3",100:"F8",101:"F9",103:"F11",109:"F10",111:"F12",115:"Home",116:"Page ↑",117:"⌦",118:"F4",119:"End",120:"F2",121:"Page ↓",122:"F1",123:"←",124:"→",125:"↓",126:"↑"]
    public var display: String {
        [(8,"⌃"),(4,"⌥"),(2,"⇧"),(1,"⌘")].filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined() + (Self.names[key] ?? "Key \(key)")
    }
    public var validationError: String? {
        guard Self.names[key] != nil, modifiers & ~15 == 0 else { return "暂不支持这组按键。" }
        guard modifiers & (Self.command | Self.option | Self.control) != 0 else { return "全局快捷键需包含 ⌘、⌥ 或 ⌃，以免影响正常输入。" }
        if modifiers == Self.command && [0,6,7,8,9,12,13,46,48,49,43].contains(key) { return "这组按键用于常见编辑或系统操作，请增加修饰键。" }
        if key == 53 || key == 48 || (key == 49 && (modifiers == Self.command || modifiers == Self.control)) { return "请避开 Esc、Tab 和系统切换快捷键。" }
        return nil
    }
}
public struct ShortcutAction: Identifiable {
    public let id: String, title: String, group: String, detail: String
    public let initial: KeyChord?
    public init(_ id: String, _ title: String, _ group: String, _ detail: String = "", _ initial: KeyChord? = nil) {
        self.id = id; self.title = title; self.group = group; self.detail = detail; self.initial = initial
    }
}
private struct ShortcutOverride: Codable { let chord: KeyChord? }
public final class ShortcutPreferences: ObservableObject {
    @Published public private(set) var bindings: [String: KeyChord] = [:]
    public let actions: [ShortcutAction]
    private let defaults: UserDefaults, persist: Bool
    private var overrides: [String: ShortcutOverride] = [:]
    public init(actions: [ShortcutAction], defaults: UserDefaults = .standard, persist: Bool = true) {
        self.actions = actions; self.defaults = defaults; self.persist = persist
        if let data = defaults.data(forKey: "shortcuts.v1"), let saved = try? JSONDecoder().decode([String: ShortcutOverride].self, from: data) { overrides = saved }
        rebuild()
    }
    private func rebuild() {
        var next: [String: KeyChord] = [:], used = Set<KeyChord>()
        // Explicit assignments take priority over defaults introduced in a later release.
        for action in actions where overrides[action.id] != nil {
            if let chord = overrides[action.id]?.chord, chord.validationError == nil, used.insert(chord).inserted { next[action.id] = chord }
        }
        for action in actions where overrides[action.id] == nil {
            if let chord = action.initial, chord.validationError == nil, used.insert(chord).inserted { next[action.id] = chord }
        }
        bindings = next
    }
    public func error(for chord: KeyChord, action: String) -> String? {
        if let error = chord.validationError { return error }
        if let other = actions.first(where: { $0.id != action && bindings[$0.id] == chord }) { return "已用于「\(other.title)」，请先清除原分配或使用其他按键。" }
        return nil
    }
    public func set(_ chord: KeyChord?, for action: String) {
        guard actions.contains(where: { $0.id == action }), chord.map({ error(for: $0, action: action) == nil }) ?? true else { return }
        overrides[action] = ShortcutOverride(chord: chord); rebuild(); save()
    }
    public func reset() { overrides = [:]; rebuild(); save() }
    private func save() { if persist, let data = try? JSONEncoder().encode(overrides) { defaults.set(data, forKey: "shortcuts.v1") } }
}
