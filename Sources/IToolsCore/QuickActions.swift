import Foundation
import Combine

public enum QuickAction: String, CaseIterable, Identifiable {
    case awake, darkMode, lockScreen, keepDisplay, screenSaver
    case cleanScreen, cleanKeyboard, desktopCover, dockAutoHide, menuBarAutoHide
    case screenshot, ocr, clipboard, files, displaySettings
    case leftWindow, rightWindow, maximize, restoreWindow, colorPicker
    case recording, emptyTrash, dockSettings
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .awake: return "防止自动休眠"; case .darkMode: return "系统深色模式"; case .lockScreen: return "锁屏"
        case .keepDisplay: return "保持亮屏"; case .screenSaver: return "进入屏保"
        case .cleanScreen: return "清洁屏幕"; case .cleanKeyboard: return "清洁键盘"
        case .desktopCover: return "桌面遮罩"; case .dockAutoHide: return "自动隐藏 Dock"
        case .menuBarAutoHide: return "自动隐藏菜单栏"; case .screenshot: return "区域截图"
        case .ocr: return "屏幕文字识别"; case .clipboard: return "剪贴板与短语"
        case .files: return "访达工具"; case .displaySettings: return "显示器设置"
        case .leftWindow: return "左半屏"; case .rightWindow: return "右半屏"; case .maximize: return "最大化窗口"
        case .restoreWindow: return "还原窗口"; case .colorPicker: return "屏幕取色"
        case .recording: return "录屏与录音"; case .emptyTrash: return "清空废纸篓"; case .dockSettings: return "Dock 设置"
        }
    }
    public var icon: String {
        switch self {
        case .awake: return "cup.and.saucer"; case .darkMode: return "circle.lefthalf.filled"; case .lockScreen: return "lock"
        case .keepDisplay: return "display"; case .screenSaver: return "play.rectangle"
        case .cleanScreen: return "sparkles"; case .cleanKeyboard: return "keyboard"
        case .desktopCover: return "eye.slash"; case .dockAutoHide: return "dock.rectangle"
        case .menuBarAutoHide: return "menubar.rectangle"; case .screenshot: return "viewfinder"
        case .ocr: return "text.viewfinder"; case .clipboard: return "doc.on.clipboard"; case .files: return "folder"
        case .displaySettings: return "display.2"; case .leftWindow: return "rectangle.lefthalf.inset.filled"
        case .rightWindow: return "rectangle.righthalf.inset.filled"; case .maximize: return "arrow.up.left.and.arrow.down.right"
        case .restoreWindow: return "arrow.uturn.backward"; case .colorPicker: return "eyedropper"
        case .recording: return "record.circle"; case .emptyTrash: return "trash"; case .dockSettings: return "gearshape"
        }
    }
    public var detail: String {
        switch self {
        case .awake: return "防止开盖状态下的自动休眠，30 分钟后停止；不覆盖合盖休眠"
        case .keepDisplay: return "保持系统和屏幕唤醒 30 分钟；与防止自动休眠共用会话"
        case .darkMode: return "切换整个系统的深色外观，首次操作可能需要自动化授权"
        case .cleanScreen, .cleanKeyboard: return "阻止普通按键；按住 Esc 两秒或点击结束退出，一分钟后自动结束。电源及媒体键仍由系统处理"
        case .desktopCover: return "临时覆盖桌面图标，文件不会移动；退出 iTools 后恢复"
        case .dockAutoHide, .menuBarAutoHide: return "切换系统的自动隐藏设置，首次操作可能需要自动化授权"
        case .emptyTrash: return "由 Finder 清空废纸篓，执行前需确认，无法撤销"
        default: return title
        }
    }
    public static let defaults: [QuickAction] = [.awake,.darkMode,.lockScreen,.keepDisplay,.screenSaver,.cleanScreen,.cleanKeyboard,.desktopCover,.dockAutoHide,.menuBarAutoHide,.screenshot,.ocr,.clipboard,.files,.displaySettings]
}
public final class QuickPanelPreferences: ObservableObject {
    public static let key = "quickPanel.actions"
    @Published public private(set) var actions: [QuickAction]
    @Published public var showMetrics: Bool { didSet { if persist { defaults.set(showMetrics, forKey: "quickPanel.showMetrics") } } }
    private let defaults: UserDefaults
    private let persist: Bool
    public init(defaults: UserDefaults = .standard, persist: Bool = true) {
        self.defaults = defaults; self.persist = persist
        if let values = defaults.stringArray(forKey: Self.key) {
            var seen = Set<QuickAction>()
            actions = values.compactMap(QuickAction.init(rawValue:)).filter { seen.insert($0).inserted }
        } else { actions = QuickAction.defaults }
        showMetrics = defaults.object(forKey: "quickPanel.showMetrics") as? Bool ?? true
    }
    public func set(_ action: QuickAction, enabled: Bool) {
        if enabled { if !actions.contains(action) { actions.append(action) } }
        else { actions.removeAll { $0 == action } }
        save()
    }
    public func move(_ action: QuickAction, by offset: Int) {
        guard let index = actions.firstIndex(of: action), actions.indices.contains(index+offset) else { return }
        actions.swapAt(index, index+offset); save()
    }
    public func reset() { actions = QuickAction.defaults; showMetrics = true; save() }
    private func save() { if persist { defaults.set(actions.map(\.rawValue), forKey: Self.key) } }
}
public struct CleaningEscapePolicy {
    public private(set) var escapeDownAt: TimeInterval?
    public let expiresAt: TimeInterval
    public init(now: TimeInterval, duration: TimeInterval = 60) { expiresAt = now + duration }
    public mutating func key(code: Int64, down: Bool, now: TimeInterval) {
        guard code == 53 else { return }
        if down { if escapeDownAt == nil { escapeDownAt = now } }
        else { escapeDownAt = nil }
    }
    public func shouldExit(now: TimeInterval) -> Bool { now >= expiresAt || escapeDownAt.map { now - $0 >= 2 } == true }
}
