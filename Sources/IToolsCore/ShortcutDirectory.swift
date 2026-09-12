import Foundation

public enum ShortcutCategory: String, CaseIterable, Identifiable {
    case general, clipboard, capture, recording, files, windows, system
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .general: return "面板与导航"; case .clipboard: return "剪贴板与短语"
        case .capture: return "截图与标注"; case .recording: return "录屏与录音"
        case .files: return "访达与文件"; case .windows: return "窗口与效率"
        case .system: return "系统与监控"
        }
    }
    public var icon: String {
        switch self {
        case .general: return "square.grid.2x2"; case .clipboard: return "doc.on.clipboard"
        case .capture: return "viewfinder"; case .recording: return "record.circle"
        case .files: return "folder"; case .windows: return "rectangle.3.offgrid"
        case .system: return "waveform.path.ecg"
        }
    }
    public var subtitle: String {
        switch self {
        case .general: return "快速呼出面板，跳转到需要的工具。"
        case .clipboard: return "呼出历史、使用内容，让常用回复随手可用。"
        case .capture: return "从截取画面到编辑图片，按步骤找到操作。"
        case .recording: return "开始、暂停和保存录制，再处理导出内容。"
        case .files: return "新建、整理与打开文件，按用途设置按键。"
        case .windows: return "安排窗口布局，切换桌面和专注状态。"
        case .system: return "查看系统状态，快速打开 macOS 工具。"
        }
    }
}

public struct ShortcutSection: Identifiable {
    public let category: ShortcutCategory
    public let title: String
    public let actions: [ShortcutAction]
    public var id: String { category.rawValue + "." + title }
    public var detail: String {
        if actions.contains(where: { $0.id.hasPrefix("file.") }) { return "文件处理按键执行前会先让你选择文件或目录。" }
        if title == "当前内容" { return "面板未打开时，先呼出面板供选择。" }
        if title == "标注工具" { return "切换当前图片的标注工具。" }
        return ""
    }
}

/// Organizes existing command IDs without migrating or discarding any saved bindings.
public enum ShortcutDirectory {
    public static func location(of action: ShortcutAction) -> (ShortcutCategory, String) {
        let id = action.id
        if id.hasPrefix("page.") { return (.general, "页面入口") }
        if id.hasPrefix("app.") { return (.general, "呼出常用面板") }
        if id == "quick.clipboard" || ["clipboard.snippets", "clipboard.record"].contains(id) { return (.clipboard, "呼出与记录") }
        if ["clipboard.next", "clipSelection.queue"].contains(id) { return (.clipboard, "连续粘贴") }
        if id.hasPrefix("clipSelection.") { return (.clipboard, "当前内容") }
        if id.hasPrefix("clipboard.") { return (.clipboard, "历史管理") }
        if ["quick.screenshot", "quick.ocr", "quick.colorPicker", "capture.full", "capture.delay"].contains(id) { return (.capture, "截图与识别") }
        if id.hasPrefix("mark.") || id == "capture.undo" { return (.capture, "标注工具") }
        if id.hasPrefix("capture.") { return (.capture, "图片处理") }
        if ["quick.recording", "record.full", "record.region", "record.audio"].contains(id) { return (.recording, "开始录制") }
        if ["record.pause", "record.stop"].contains(id) { return (.recording, "录制控制") }
        if id.hasPrefix("record.") { return (.recording, "导出与转换") }
        if id.hasPrefix("file.") { return (.files, action.group.replacingOccurrences(of: "文件 · ", with: "")) }
        if id == "quick.emptyTrash" || id == "files.stopScan" { return (.files, "显示、权限与清理") }
        if id.hasPrefix("files.") || id == "quick.files" { return (.files, "文件工具入口") }
        if id.hasPrefix("window.") || ["quick.leftWindow", "quick.rightWindow", "quick.maximize", "quick.restoreWindow"].contains(id) { return (.windows, "窗口布局") }
        if ["quick.awake", "quick.keepDisplay", "quick.lockScreen", "quick.screenSaver"].contains(id) { return (.windows, "专注与唤醒") }
        if id.hasPrefix("utility.") { return (.windows, "便笺与小工具") }
        if id.hasPrefix("metric.") || id == "monitor.toggle" { return (.system, "菜单栏与监控") }
        if id.hasPrefix("system.") || ["quick.displaySettings", "quick.dockSettings"].contains(id) { return (.system, "系统工具入口") }
        if id.hasPrefix("quick.") { return (.windows, "桌面与外观") }
        return (.general, "其他功能")
    }

    public static func sections(actions: [ShortcutAction], category: ShortcutCategory?, query: String = "",
                                assignedOnly: Bool = false, bindings: [String: KeyChord] = [:]) -> [ShortcutSection] {
        let words = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        var result: [ShortcutSection] = []
        for current in ShortcutCategory.allCases where category == nil || category == current {
            var order: [String] = [], grouped: [String: [ShortcutAction]] = [:]
            for action in actions {
                let (owner, section) = location(of: action)
                guard owner == current, !assignedOnly || bindings[action.id] != nil else { continue }
                let searchable = [action.title, action.group, action.detail, current.title, section,
                                  bindings[action.id]?.display ?? "未设置"].joined(separator: " ")
                guard words.allSatisfy({ searchable.localizedCaseInsensitiveContains($0) }) else { continue }
                if grouped[section] == nil { order.append(section) }
                grouped[section, default: []].append(action)
            }
            result += order.map { ShortcutSection(category: current, title: $0, actions: grouped[$0]!) }
        }
        return result
    }
}
