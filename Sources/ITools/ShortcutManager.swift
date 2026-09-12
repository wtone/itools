import AppKit
import Carbon
import Combine
import IToolsCore

extension KeyChord {
    init(event: NSEvent) {
        let f = event.modifierFlags
        self.init(UInt32(event.keyCode), (f.contains(.command) ? 1 : 0) | (f.contains(.shift) ? 2 : 0) | (f.contains(.option) ? 4 : 0) | (f.contains(.control) ? 8 : 0))
    }
    var carbonModifiers: UInt32 {
        (modifiers & 1 != 0 ? UInt32(cmdKey) : 0) | (modifiers & 2 != 0 ? UInt32(shiftKey) : 0) |
        (modifiers & 4 != 0 ? UInt32(optionKey) : 0) | (modifiers & 8 != 0 ? UInt32(controlKey) : 0)
    }
}
final class ShortcutManager: ObservableObject {
    let preferences = ShortcutPreferences(actions: AppCommands.catalog, persist: !ProcessInfo.processInfo.arguments.contains("--smoke-test"))
    @Published private(set) var failures: [String: String] = [:]
    var run: ((String) -> Void)?
    private var started = false
    private var suspended = false
    var isEditing = false
    private var observer: AnyCancellable?
    init() { observer = preferences.objectWillChange.sink { [weak self] in self?.objectWillChange.send() } }
    func display(_ id: String) -> String { preferences.bindings[id]?.display ?? "未设置" }
    func start() { started = true; rebuild() }
    func stop() { started = false; HotKeyCenter.shared.stop() }
    func suspend(_ value: Bool) { suspended = value; rebuild() }
    private func number(_ id: String) -> UInt32 { UInt32((preferences.actions.firstIndex { $0.id == id } ?? 0) + 100) }
    private func register(_ chord: KeyChord, for id: String) -> OSStatus {
        HotKeyCenter.shared.register(number(id), key: chord.key, modifiers: chord.carbonModifiers) { [weak self] in
            guard let self = self, !self.suspended, !self.isEditing,
                  NSApp.modalWindow == nil, NSApp.keyWindow?.attachedSheet == nil else { return }
            self.run?(id)
        }
    }
    func rebuild() {
        HotKeyCenter.shared.stop(); failures = [:]
        guard started, !suspended else { return }
        for action in preferences.actions {
            if let chord = preferences.bindings[action.id] {
                let result = register(chord, for: action.id)
                if result != noErr { failures[action.id] = "无法注册，可能被系统或其他应用占用（\(result)）" }
            }
        }
    }
    func set(_ chord: KeyChord?, for id: String) -> String? {
        if let chord = chord {
            if let error = preferences.error(for: chord, action: id) { return error }
            if started && !suspended {
                let result = register(chord, for: id)
                guard result == noErr else { return "无法注册这组按键（\(result)），请检查系统或其他应用的快捷键。原设置已保留。" }
            }
        } else { HotKeyCenter.shared.unregister(number(id)) }
        preferences.set(chord, for: id); failures.removeValue(forKey: id); return nil
    }
    func reset() { preferences.reset(); rebuild() }
}

enum AppCommands {
    static let catalog: [ShortcutAction] = {
        var actions: [ShortcutAction] = [
            .init("app.guide", "快捷键与操作指南", "常用面板", "随时查看、修改 iTools 按键和操作说明", .init(44, 5)),
            .init("app.toolbox", "顶部工具面板", "常用面板", "打开或收起状态和快捷操作", .init(49, 12)),
            .init("app.shortcuts", "快捷键面板（备用）", "常用面板", "可为同一面板设置另一组按键"),
            .init("clipboard.snippets", "快捷短语面板", "剪贴板", "独立面板中选择常用回复", .init(9, 7)),
            .init("clipboard.next", "粘贴队列下一项", "剪贴板", "粘贴到之前的应用", .init(11, 5)),
            .init("clipboard.record", "开启 / 暂停剪贴板记录", "剪贴板"),
            .init("clipboard.import", "导入剪贴板历史", "剪贴板"), .init("clipboard.export", "导出剪贴板历史", "剪贴板"),
            .init("clipboard.clear", "清空剪贴板历史…", "剪贴板", "需要确认，会同时删除收藏"),
            .init("capture.full", "全屏截图", "截图与标注", "主显示器", .init(20, 6)),
            .init("capture.delay", "延迟 5 秒截图", "截图与标注"), .init("capture.open", "打开图片", "截图与标注"),
            .init("capture.copy", "复制当前图片", "截图与标注"), .init("capture.export", "导出当前图片", "截图与标注"),
            .init("capture.pin", "当前图片贴图置顶", "截图与标注"), .init("capture.ocr", "识别当前图片文字 / 二维码", "截图与标注"),
            .init("capture.stitch", "纵向拼接多张图片", "截图与标注"), .init("capture.undo", "撤销上次标注", "截图与标注"),
            .init("record.full", "开始全屏录制", "录屏与录音", "先选择保存位置，使用当前录制设置"),
            .init("record.region", "开始区域录制", "录屏与录音"), .init("record.audio", "开始录音", "录屏与录音"),
            .init("record.pause", "暂停 / 继续录制", "录屏与录音"), .init("record.stop", "停止并保存录制", "录屏与录音", "", .init(1, 12)),
            .init("record.gif", "将录制转换为 GIF", "录屏与录音"), .init("record.trim", "裁剪录制视频", "录屏与录音"),
            .init("record.compress", "压缩录制视频", "录屏与录音"), .init("monitor.toggle", "开启 / 暂停系统监控", "系统监控"),
            .init("files.choose", "选择要处理的文件", "访达工具"), .init("files.template", "导入新建文件模板", "访达工具"),
            .init("files.stopScan", "停止磁盘扫描", "访达工具"),
            .init("utility.note", "打开临时便笺", "效率工具", "打开对应工具并滚动定位"),
            .init("utility.link", "打开链接清理", "效率工具", "打开对应工具并滚动定位"),
            .init("utility.qr", "打开二维码生成", "效率工具", "打开对应工具并滚动定位")
        ]
        let initial: [QuickAction: KeyChord] = [.screenshot:.init(21,6), .ocr:.init(17,6), .clipboard:.init(9,5), .leftWindow:.init(123,12), .rightWindow:.init(124,12), .maximize:.init(126,12), .restoreWindow:.init(125,12)]
        actions += QuickAction.allCases.map { .init("quick." + $0.rawValue, $0 == .clipboard ? "剪贴板历史面板" : $0.title, "快捷操作", $0 == .clipboard ? "独立浮动面板；再次按下可收起" : $0.detail, initial[$0]) }
        actions += ToolPage.allCases.map { .init("page." + $0.rawValue, "打开" + $0.rawValue, "功能页面") }
        actions += WindowLayout.allCases.filter { ![.left,.right,.maximize].contains($0) }.map { .init("window." + $0.rawValue, $0.title, "窗口布局") }
        actions += MarkTool.allCases.map { .init("mark." + $0.rawValue, "标注 · " + $0.rawValue, "截图与标注", "打开当前图片并切换工具") }
        actions += MenuBarMetric.allCases.map { .init("metric." + $0.rawValue, "菜单栏显示 / 隐藏 " + $0.title, "系统监控") }
        actions += SystemShortcut.allCases.map { .init("system." + $0.rawValue, "打开" + $0.title, "系统应用") }
        actions += FinderActions.groups.flatMap { group in group.actions.map { .init("file." + $0.id, $0.title, "文件 · " + group.title, "先选择本次处理的文件或目录；保留原有确认步骤") } }
        actions += [("copy","复制当前历史项"),("paste","粘贴当前历史项"),("plainCopy","纯文本复制当前历史项"),("plainPaste","纯文本粘贴当前历史项"),("pin","收藏 / 取消收藏当前历史项"),("queue","当前历史项加入粘贴队列"),("delete","删除当前历史项"),("group","设置当前历史项的分组")].map { .init("clipSelection." + $0.0, $0.1, "剪贴板", "面板打开时操作当前选中项；否则仅打开面板供选择") }
        let priority = ["app.guide", "quick.clipboard", "clipboard.snippets", "app.toolbox", "app.shortcuts", "quick.screenshot", "quick.ocr", "clipboard.next"]
        return priority.compactMap { id in actions.first { $0.id == id } } + actions.filter { !priority.contains($0.id) }
    }()
}

extension AppModel {
    func performCommand(_ id: String) {
        if id == "app.guide" { showGuide?(); return }
        if id == "app.toolbox" { showToolbox?(); return }
        if id == "app.shortcuts" { showShortcutSettings?(nil); return }
        if id.hasPrefix("clipSelection.") { clipboardSelectionAction?(String(id.dropFirst(14))); return }
        if id.hasPrefix("quick."), let action = QuickAction(rawValue: String(id.dropFirst(6))) { performQuickAction?(action); return }
        if id.hasPrefix("page."), let page = ToolPage(rawValue: String(id.dropFirst(5))) { navigate(page); return }
        if id.hasPrefix("window."), let layout = WindowLayout(rawValue: String(id.dropFirst(7))) { windows.apply(layout); return }
        if id.hasPrefix("metric."), let metric = MenuBarMetric(rawValue: String(id.dropFirst(7))) { menuBar.set(metric, enabled: !menuBar.isEnabled(metric)); return }
        if id.hasPrefix("system."), let system = SystemShortcut(rawValue: String(id.dropFirst(7))) { quickSystem.open(system); return }
        if id.hasPrefix("utility.") { utilityAnchor = id; navigate(.utilities); return }
        if id.hasPrefix("file."), let action = FinderActions.action(String(id.dropFirst(5))) {
            guard filesEnabled, !files.working else { navigate(.files); return }
            navigate(.files)
            if !["password","favorites"].contains(action.id) {
                // A global invocation never reuses a stale file selection from an earlier task.
                files.selection = []; files.choose(); guard !files.selection.isEmpty else { return }
            }
            files.performAction(action.id); return
        }
        if id.hasPrefix("capture.") || id.hasPrefix("record.") || id.hasPrefix("mark.") {
            guard captureEnabled else { navigate(.settings); NoticeCenter.shared.success("请先启用截图与录制模块"); return }
            if id.hasPrefix("mark."), let tool = MarkTool(rawValue: String(id.dropFirst(5))) { navigate(.capture); capture.document.tool = tool; return }
            if !["capture.full","capture.delay"].contains(id) { navigate(.capture) }
            switch id {
            case "capture.full": capture.capture(fullScreen: true)
            case "capture.delay": capture.capture(delay: 5)
            case "capture.open": capture.openImage()
            case "capture.copy", "capture.export", "capture.pin", "capture.ocr", "capture.undo":
                guard capture.document.image != nil else { NoticeCenter.shared.success("请先截图或打开一张图片"); return }
                switch id { case "capture.copy": capture.copyImage(); case "capture.export": capture.exportImage(); case "capture.pin": capture.pin(); case "capture.ocr": capture.recognize(); default: capture.document.undo() }
            case "capture.stitch": capture.stitch()
            case "record.full": recorder.start()
            case "record.region": recorder.selectRegion()
            case "record.audio": recorder.start(audioOnly: true)
            case "record.pause": recorder.pauseResume()
            case "record.stop": recorder.stop()
            case "record.gif": recorder.convertGIF()
            case "record.trim": recorder.exportVideo(trim: true)
            case "record.compress": recorder.exportVideo(trim: false)
            default: break
            }; return
        }
        switch id {
        case "clipboard.snippets": showClipboard?(true)
        case "clipboard.next": clipboard.pasteNext()
        case "clipboard.record": clipboard.enabled.toggle()
        case "clipboard.import": navigate(.clipboard); clipboard.importHistory()
        case "clipboard.export": navigate(.clipboard); clipboard.exportHistory()
        case "clipboard.clear": navigate(.clipboard); clipboard.clear()
        case "monitor.toggle": monitor.enabled.toggle()
        case "files.choose": if filesEnabled { navigate(.files); files.choose() }
        case "files.template": if filesEnabled { navigate(.files); files.importTemplate() }
        case "files.stopScan": files.scanCancellation?.cancel()
        default: break
        }
    }
}
