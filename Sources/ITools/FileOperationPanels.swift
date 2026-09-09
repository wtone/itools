import AppKit
import IToolsCore

/// A single input-and-preview panel is the fallback where Finder exposes no
/// public API for opening its own rename editor with an explicit file list.
final class FileRenamePanel: NSObject, NSTextFieldDelegate {
    private let files: [URL]
    private let repair: Bool
    private let alert = NSAlert()
    private let name = NSTextField(string: "")
    private let start = NSTextField(string: "1")
    private let encoding = NSPopUpButton()
    private let preview = NSTextView()
    private var plan: [(URL, URL)]?
    init(files: [URL], repair: Bool = false) {
        self.files = files; self.repair = repair
        super.init()
        alert.messageText = repair ? "修复乱码文件名" : (files.count == 1 ? "重命名" : "批量重命名")
        alert.informativeText = repair ? "选择编码并查看新名称，确认后应用。没有候选名称的项目保持不变。" : "修改名称并查看预览；不会覆盖同名文件。"
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        if repair {
            encoding.addItems(withTitles: FilenameRepair.allCases.map(\.title))
            encoding.target = self; encoding.action = #selector(updatePreview)
            encoding.widthAnchor.constraint(equalToConstant: 470).isActive = true
            stack.addArrangedSubview(encoding)
        } else {
            name.stringValue = files.count == 1 ? files[0].lastPathComponent : "文件-"
            name.placeholderString = files.count == 1 ? "文件名" : "名称前缀"
            name.delegate = self; name.widthAnchor.constraint(equalToConstant: 470).isActive = true
            stack.addArrangedSubview(name)
            if files.count > 1 {
                start.delegate = self; start.widthAnchor.constraint(equalToConstant: 90).isActive = true
                let row = NSStackView(views: [NSTextField(labelWithString: "起始编号"), start, NSTextField(labelWithString: "保留扩展名")])
                row.spacing = 10; stack.addArrangedSubview(row)
            }
        }
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 470, height: 180))
        scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder
        scroll.widthAnchor.constraint(equalToConstant: 470).isActive = true
        scroll.heightAnchor.constraint(equalToConstant: 180).isActive = true
        preview.frame = scroll.bounds; preview.isEditable = false; preview.isSelectable = true
        preview.font = .systemFont(ofSize: 13); preview.textContainerInset = NSSize(width: 8, height: 8)
        preview.isVerticallyResizable = true; preview.autoresizingMask = [.width]; preview.textContainer?.widthTracksTextView = true
        scroll.documentView = preview; stack.addArrangedSubview(scroll)
        stack.frame = NSRect(x: 0, y: 0, width: 470, height: files.count > 1 && !repair ? 258 : 224)
        alert.accessoryView = stack; alert.addButton(withTitle: repair ? "应用修复" : "重命名"); alert.addButton(withTitle: "取消")
        if !repair { alert.window.initialFirstResponder = name }
        updatePreview()
    }
    func controlTextDidChange(_ obj: Notification) { updatePreview() }
    @objc private func updatePreview() {
        do {
            let proposed: [(URL, URL)]
            if repair {
                let mode = FilenameRepair.allCases[encoding.indexOfSelectedItem]
                proposed = files.compactMap { file in
                    guard let repaired = mode.repair(file.lastPathComponent), repaired != file.lastPathComponent else { return nil }
                    return (file, file.deletingLastPathComponent().appendingPathComponent(repaired))
                }
            } else if files.count == 1 {
                try FileOperations.validateName(name.stringValue)
                proposed = [(files[0], files[0].deletingLastPathComponent().appendingPathComponent(name.stringValue))]
            } else {
                guard let number = Int(start.stringValue), number >= 0, number <= Int.max - files.count else {
                    throw UserFacingError("请输入有效的起始编号。")
                }
                proposed = try FileOperations.renamePlan(files, prefix: name.stringValue, start: number)
            }
            guard !proposed.isEmpty else { throw UserFacingError("当前编码没有可修复的名称，请选择其他编码。") }
            plan = proposed
            preview.string = proposed.prefix(100).map { $0.0.lastPathComponent + " → " + $0.1.lastPathComponent }.joined(separator: "\n")
            if proposed.count > 100 { preview.string += "\n…共 \(proposed.count) 项" }
        } catch { plan = nil; preview.string = error.localizedDescription }
        alert.buttons.first?.isEnabled = plan != nil
    }
    func run() -> [(URL, URL)]? {
        Panels.activateIfNeeded()
        return alert.runModal() == .alertFirstButtonReturn ? plan : nil
    }
    func renderPreview() -> NSView { alert.layout(); return alert.window.contentView! }
}

final class FileDeletionConfirmation: NSObject, NSTextFieldDelegate {
    private let alert = NSAlert()
    private let field = NSTextField(string: "")
    init(files: [URL]) {
        super.init()
        alert.messageText = "彻底删除 \(files.count) 项？"
        alert.informativeText = "删除后无法从废纸篓恢复。输入「彻底删除」以确认。\n" + files.prefix(12).map(\.path).joined(separator: "\n") + (files.count > 12 ? "\n…共 \(files.count) 项" : "")
        field.frame = NSRect(x: 0, y: 0, width: 420, height: 26); field.placeholderString = "彻底删除"; field.delegate = self
        alert.accessoryView = field; alert.addButton(withTitle: "彻底删除"); alert.addButton(withTitle: "取消")
        alert.buttons.first?.isEnabled = false; alert.window.initialFirstResponder = field
    }
    func controlTextDidChange(_ obj: Notification) { alert.buttons.first?.isEnabled = field.stringValue == "彻底删除" }
    func run() -> Bool { Panels.activateIfNeeded(); return alert.runModal() == .alertFirstButtonReturn && field.stringValue == "彻底删除" }
}
