import Foundation
import Combine

public enum ClipboardLayout: String, CaseIterable {
    case horizontal = "横向卡片", vertical = "竖向列表"
    public var title: String { self == .horizontal ? "屏幕底部卡片" : rawValue }
}
public enum ClipboardQuickUse: String, CaseIterable { case paste = "直接粘贴", copy = "仅复制" }
public enum ClipboardNumberModifier: String, CaseIterable {
    case none = "数字键", command = "⌘ + 数字", option = "⌥ + 数字", control = "⌃ + 数字", shift = "⇧ + 数字"
    public var bits: UInt32 { switch self { case .none: return 0; case .command: return 1; case .option: return 4; case .control: return 8; case .shift: return 2 } }
    public var symbol: String { switch self { case .none: return ""; case .command: return "⌘"; case .option: return "⌥"; case .control: return "⌃"; case .shift: return "⇧" } }
}
public final class ClipboardPanelPreferences: ObservableObject {
    private let defaults: UserDefaults, persist: Bool
    @Published public var layout: ClipboardLayout { didSet { save() } }
    @Published public var quickUse: ClipboardQuickUse { didSet { save() } }
    @Published public var numberModifier: ClipboardNumberModifier { didSet { save() } }
    public init(defaults: UserDefaults = .standard, persist: Bool = true) {
        self.defaults = defaults; self.persist = persist
        layout = ClipboardLayout(rawValue: defaults.string(forKey: "clipboard.panel.layout") ?? "") ?? .horizontal
        quickUse = ClipboardQuickUse(rawValue: defaults.string(forKey: "clipboard.panel.quickUse") ?? "") ?? .paste
        numberModifier = ClipboardNumberModifier(rawValue: defaults.string(forKey: "clipboard.panel.numbers") ?? "") ?? .none
    }
    private func save() {
        guard persist else { return }
        defaults.set(layout.rawValue, forKey: "clipboard.panel.layout"); defaults.set(quickUse.rawValue, forKey: "clipboard.panel.quickUse")
        defaults.set(numberModifier.rawValue, forKey: "clipboard.panel.numbers")
    }
}
public enum ClipboardPanelRules {
    public static func matches(_ entry: ClipEntry, query: String, kind: ClipKind?, group: String) -> Bool {
        (kind == nil || entry.kind == kind) && (group == "全部" || (group == "收藏" && entry.pinned) || entry.group == group) &&
        (query.isEmpty || entry.text.localizedCaseInsensitiveContains(query) || entry.source.localizedCaseInsensitiveContains(query))
    }
    /// Never consume bare numbers from an editor or an active IME composition.
    public static func numberIndex(key: UInt32, modifiers: UInt32, configured: ClipboardNumberModifier, editing: Bool, composing: Bool) -> Int? {
        guard !composing, modifiers == configured.bits, !(editing && (modifiers == 0 || modifiers == KeyChord.shift)) else { return nil }
        return [18:0,19:1,20:2,21:3,23:4,22:5,26:6,28:7,25:8,83:0,84:1,85:2,86:3,87:4,88:5,89:6,91:7,92:8][Int(key)]
    }
    public static func movedIndex(_ index: Int, delta: Int, count: Int) -> Int { count == 0 ? 0 : min(max(0, index + delta), count - 1) }
    /// AppKit screen coordinates: the minimum Y is the bottom, including on displays below the main screen.
    public static func bottomPanelFrame(visible: CGRect) -> CGRect {
        let insetX = min(8, max(0, visible.width / 4)), insetY = min(8, max(0, visible.height / 4))
        let width = max(1, visible.width - insetX * 2)
        let availableHeight = max(1, visible.height - insetY * 2)
        let height = min(availableHeight, min(360, max(300, visible.height * 0.36)))
        return CGRect(x: visible.minX + insetX, y: visible.minY + insetY, width: width, height: height)
    }
    public static func panelFrame(size: CGSize, visible: CGRect, anchor: CGPoint) -> CGRect {
        let width = min(size.width, max(1, visible.width - 24)), height = min(size.height, max(1, visible.height - 24))
        return CGRect(x: min(max(visible.minX + 12, anchor.x - width / 2), visible.maxX - width - 12),
                      y: min(max(visible.minY + 12, anchor.y - height / 2), visible.maxY - height - 12), width: width, height: height)
    }
}
