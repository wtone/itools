import AppKit
import SwiftUI
import Carbon
import IToolsCore

enum ShortcutSmokeChecks {
    static func run(model: AppModel, destination: URL) throws {
        func require(_ condition: Bool, _ message: String) throws { if !condition { throw UserFacingError("Smoke: " + message) } }
        let catalog = AppCommands.catalog
        try require(Set(catalog.map(\.id)).count == catalog.count, "duplicate action IDs")
        for action in FinderActions.all { try require(catalog.contains { $0.id == "file." + action.id }, "missing file shortcut " + action.id) }
        for action in QuickAction.allCases { try require(catalog.contains { $0.id == "quick." + action.rawValue }, "missing quick action") }
        let defaults = catalog.compactMap(\.initial)
        try require(Set(defaults).count == defaults.count && defaults.allSatisfy { $0.validationError == nil }, "invalid default shortcuts")
        try catalog.map { "\($0.group)\t\($0.title)\t\($0.initial?.display ?? "未设置")\t\($0.id)" }.joined(separator: "\n")
            .write(to: destination.appendingPathComponent("shortcut-catalog.tsv"), atomically: true, encoding: .utf8)
        let originalEntries = model.clipboard.entries, originalSnippets = model.clipboard.snippets
        let originalLayout = model.clipboardPanel.layout, originalUse = model.clipboardPanel.quickUse, originalNumbers = model.clipboardPanel.numberModifier
        defer {
            model.clipboard.entries = originalEntries; model.clipboard.snippets = originalSnippets
            model.clipboardPanel.layout = originalLayout; model.clipboardPanel.quickUse = originalUse; model.clipboardPanel.numberModifier = originalNumbers
        }
        let samples = ["下周一上午 10:00，项目进度讨论。记得带上新的设计方案。", "把常用内容收好，需要时一键找回。", "https://example.com/design/notes", "会议纪要：横向卡片和竖向列表都支持键盘选择。", "订单号 20260909001", "Hello, Intel Mac!", "你好，附件已经整理好了，请查收。", "sudo 是示例文字，不会自动作为命令执行。", "第九条：使用数字键快速选择", "更多历史可以继续向下浏览"]
        model.clipboard.entries = samples.enumerated().map { index, text in
            var entry = ClipEntry(kind: .text, text: text, source: ["com.apple.Notes","com.apple.Safari","com.apple.mail"][index % 3], payload: [.init(type: NSPasteboard.PasteboardType.string.rawValue, data: Data(text.utf8))])
            entry.pinned = index == 0; entry.group = index == 0 ? "工作" : ""; return entry
        }
        if let image = model.capture.document.image?.png {
            model.clipboard.entries.insert(ClipEntry(kind: .image, text: "图片 · 设计样例", source: "iTools", payload: [.init(type: NSPasteboard.PasteboardType.png.rawValue, data: image)]), at: 2)
        }
        model.clipboard.snippets = [.init(title: "收到回复", body: "你好，已经收到你的消息，我会尽快回复。", group: "常用"), .init(title: "日期模板", body: "今天是 {{date}}，当前时间 {{time}}。", group: "工作")]
        model.clipboardPanel.layout = .vertical; model.clipboardPanel.quickUse = .paste; model.clipboardPanel.numberModifier = .none
        var uses: [(UUID, Bool, Bool)] = []
        let clipboard = ClipboardPanelController(model: model) { entry, paste, plain in uses.append((entry.id, paste, plain)) }
        defer { clipboard.close() }
        clipboard.toggle(); RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        try require(clipboard.isShown && clipboard.panel.isKeyWindow, "floating clipboard cannot receive keyboard input")
        func event(_ key: UInt16, _ modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: clipboard.panel.windowNumber, context: nil, characters: "x", charactersIgnoringModifiers: "x", isARepeat: false, keyCode: key)!
        }
        _ = clipboard.handle(event(125))
        try require(clipboard.state.selected?.id == model.clipboard.entries[1].id, "arrow selection")
        _ = clipboard.handle(event(20))
        try require(uses.last?.0 == model.clipboard.entries[2].id && uses.last?.1 == true, "digit quick paste route")
        _ = clipboard.handle(event(8, [.command,.shift]))
        try require(uses.last?.0 == model.clipboard.entries[1].id && uses.last?.1 == false && uses.last?.2 == true, "plain copy route")
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 100, height: 24)); editor.isEditable = true
        clipboard.panel.contentView?.addSubview(editor); clipboard.panel.makeFirstResponder(editor)
        let count = uses.count
        try require(clipboard.handle(event(18)) != nil && uses.count == count, "search consumed numeric input")
        editor.setMarkedText("zhong", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        try require(clipboard.handle(event(36)) != nil && uses.count == count, "IME Enter caused a paste")
        editor.unmarkText(); editor.removeFromSuperview(); clipboard.panel.makeFirstResponder(nil)
        model.clipboardPanel.quickUse = .copy; _ = clipboard.handle(event(18))
        try require(uses.last?.1 == false, "copy-only preference ignored")
        _ = clipboard.handle(event(53)); try require(!clipboard.isShown, "Escape did not dismiss")
        clipboard.toggle(); clipboard.toggle(); try require(!clipboard.isShown, "repeat shortcut did not toggle panel")
        clipboard.state.reset(snippets: false)
        try export(clipboard.content(), size: NSSize(width: 530,height: 670), name: "clipboard-vertical", destination: destination)
        try export(clipboard.content(), size: NSSize(width: 530,height: 670), name: "clipboard-vertical-dark", destination: destination, dark: true)
        model.clipboardPanel.layout = .horizontal
        try export(clipboard.content(), size: NSSize(width: 1020,height: 420), name: "clipboard-horizontal", destination: destination)
        clipboard.state.reset(snippets: true)
        try export(clipboard.content(), size: NSSize(width: 1020,height: 420), name: "clipboard-snippets", destination: destination)
        let privateBoard = NSPasteboard(name: .init("itools-shortcuts-smoke-" + UUID().uuidString))
        defer { privateBoard.releaseGlobally() }
        let generalCount = NSPasteboard.general.changeCount
        let text = model.clipboard.entries[0]
        try require(model.clipboard.copy(text, to: privateBoard) && privateBoard.string(forType: .string) == text.text, "private clipboard text write")
        var rich = text; rich.payload.append(.init(type: NSPasteboard.PasteboardType.rtf.rawValue, data: Data("{\\rtf1 Hello}".utf8)))
        try require(model.clipboard.copy(rich, to: privateBoard) && privateBoard.data(forType: .rtf) != nil, "rich text formats lost")
        try require(model.clipboard.copy(rich, plain: true, to: privateBoard) && privateBoard.data(forType: .rtf) == nil, "plain copy kept formatting")
        let imageEntry = model.clipboard.entries[2]
        try require(model.clipboard.copy(imageEntry, to: privateBoard) && privateBoard.data(forType: .png) == imageEntry.payload.first?.data, "image payload lost")
        let file = destination.appendingPathComponent("annotation-export.png")
        let fileEntry = ClipEntry(kind: .files, text: file.lastPathComponent, source: "test", payload: [.init(type: "com.itools.file-list", data: try JSONEncoder().encode([file.absoluteString]))])
        try require(model.clipboard.copy(fileEntry, to: privateBoard), "file clipboard write")
        try require((privateBoard.readObjects(forClasses: [NSURL.self]) as? [URL])?.first == file, "file URL not restored")
        try require(NSPasteboard.general.changeCount == generalCount, "smoke changed user's clipboard")
        let guide = ShortcutGuideController(model: model)
        guide.show(); try require(guide.panel.isVisible, "guide did not open"); guide.close()
        try export(guide.content(settings: false), size: NSSize(width: 810,height: 700), name: "shortcut-guide", destination: destination)
        try export(guide.content(settings: true), size: NSSize(width: 810,height: 700), name: "shortcut-settings", destination: destination)
        try export(guide.content(settings: false), size: NSSize(width: 810,height: 700), name: "shortcut-guide-dark", destination: destination, dark: true)
        print("PASS: \(catalog.count) shortcut actions; clipboard panel focus, arrows/digits/copy-only/IME/Escape/toggle; private pasteboard text/RTF/plain/image/files; light/dark/horizontal/vertical/snippets/guide/settings rendering")
    }
    static func verifyHotKeyDispatch(completion: @escaping (Error?) -> Void) {
        let center = HotKeyCenter.shared
        var fired = 0
        let modifiers = UInt32(cmdKey | controlKey | optionKey | shiftKey)
        func finish(_ message: String? = nil) { center.stop(); completion(message.map { UserFacingError("Smoke: " + $0) }) }
        func send(_ id: UInt32) -> Bool {
            var event: EventRef?
            guard CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, EventAttributes(0), &event) == noErr, let event = event else { return false }
            defer { ReleaseEvent(event) }
            var identifier = EventHotKeyID(signature: 0x49544F4C, id: id)
            guard SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &identifier) == noErr else { return false }
            return SendEventToEventTarget(event, GetApplicationEventTarget()) == noErr
        }
        guard center.register(8800, key: 103, modifiers: modifiers, action: { fired += 1 }) == noErr else { finish("test hotkey registration failed"); return }
        guard send(8800) else { finish("Carbon event dispatch failed"); return }
        // Leave the enclosing main-queue block before checking its asynchronously dispatched action.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard fired == 1 else { finish("registered shortcut was not dispatched"); return }
            guard center.register(8800, key: 111, modifiers: modifiers, action: { fired += 2 }) == noErr else { finish("hotkey replacement failed"); return }
            guard send(8800) else { finish("replacement event dispatch failed"); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard fired == 3 else { finish("replacement action was not used"); return }
                center.unregister(8800)
                guard send(8800) else { finish("unregister event dispatch failed"); return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    guard fired == 3 else { finish("unregistered shortcut still fired"); return }
                    print("PASS: real Carbon registration, event dispatch, replacement and unregister (no global keystrokes emitted)")
                    finish()
                }
            }
        }
    }
    private static func export<V: View>(_ content: V, size: NSSize, name: String, destination: URL, dark: Bool = false) throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero,size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let view = NSHostingView(rootView: content.frame(width: size.width,height: size.height).environment(\.colorScheme, dark ? .dark : .light))
        window.contentView = view; view.frame = NSRect(origin: .zero,size: size)
        RunLoop.main.run(until: Date().addingTimeInterval(0.15)); view.frame = NSRect(origin: .zero,size: size)
        view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw UserFacingError("Smoke: shortcut bitmap unavailable") }
        view.cacheDisplay(in: view.bounds,to: rep)
        guard let data = rep.representation(using: .png,properties: [:]) else { throw UserFacingError("Smoke: shortcut PNG unavailable") }
        try data.write(to: destination.appendingPathComponent(name + ".png")); window.close()
    }
}
