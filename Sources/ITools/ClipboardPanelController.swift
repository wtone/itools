import AppKit
import SwiftUI
import Combine
import IToolsCore

final class FloatingToolPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    init(title: String) {
        super.init(contentRect: .zero, styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
        self.title = title; titleVisibility = .hidden; titlebarAppearsTransparent = true
        isReleasedWhenClosed = false; isFloatingPanel = true; level = .floating; hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; isMovableByWindowBackground = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true; standardWindowButton(.zoomButton)?.isHidden = true
    }
    func place(size: NSSize, anchor: NSPoint? = nil) {
        let point = anchor ?? NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1100, height: 800)
        setFrame(ClipboardPanelRules.panelFrame(size: size, visible: visible, anchor: point), display: true)
    }
}

final class ClipboardPanelState: ObservableObject {
    @Published var query = ""
    @Published var group = "全部"
    @Published var kind = "全部类型"
    @Published var snippets = false
    @Published var selectedID: UUID?
    @Published var searchFocused = false
    @Published var feedback = ""
    @Published var copiedID: UUID?
    let service: ClipboardService
    init(service: ClipboardService) { self.service = service }
    var items: [ClipEntry] {
        if snippets {
            return service.snippets.filter { (group == "全部" || $0.group == group) && (query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.body.localizedCaseInsensitiveContains(query)) }
                .map { snippet in
                    var entry = ClipEntry(kind: .text, text: snippet.body, source: snippet.title, payload: [])
                    entry.id = snippet.id; entry.group = snippet.group; return entry
                }
        }
        let filter: ClipKind? = kind == "文字" ? .text : kind == "图片" ? .image : kind == "文件" ? .files : nil
        return service.entries.filter { ClipboardPanelRules.matches($0, query: query, kind: filter, group: group) }
    }
    var groups: [String] {
        snippets ? ["全部"] + Set(service.snippets.map(\.group)).filter { $0 != "全部" }.sorted() : service.groups
    }
    func modeChanged() { group = "全部"; kind = "全部类型"; feedback = ""; copiedID = nil; selectedID = items.first?.id }
    var selected: ClipEntry? { items.first { $0.id == selectedID } ?? items.first }
    func reset(snippets: Bool) { self.snippets = snippets; query = ""; group = "全部"; kind = "全部类型"; selectedID = items.first?.id; searchFocused = false; feedback = ""; copiedID = nil }
    func reconcile() { if !items.contains(where: { $0.id == selectedID }) { selectedID = items.first?.id } }
    func selectFilter(_ title: String) {
        let nextKind = title == "收藏" || title == "全部" ? "全部类型" : title
        let nextGroup = title == "收藏" ? "收藏" : group == "收藏" ? "全部" : group
        guard kind != nextKind || group != nextGroup else { return }
        kind = nextKind; group = nextGroup; selectedID = items.first?.id
        feedback = ""; copiedID = nil
    }
    func move(_ delta: Int) {
        let list = items
        guard !list.isEmpty else { selectedID = nil; return }
        let index = list.firstIndex { $0.id == selected?.id } ?? 0
        selectedID = list[ClipboardPanelRules.movedIndex(index, delta: delta, count: list.count)].id
    }
}

final class ClipboardPanelController: NSObject, NSWindowDelegate {
    let model: AppModel
    let state: ClipboardPanelState
    let panel = FloatingToolPanel(title: "iTools 剪贴板历史")
    private var target: NSRunningApplication?
    private var eventMonitor: Any?
    private var observations = Set<AnyCancellable>()
    private var showing = false
    private var closing = false
    private var presentationScreenID: NSNumber?
    private let selectionHandler: ((ClipEntry, Bool, Bool) -> Void)?
    init(model: AppModel, selectionHandler: ((ClipEntry, Bool, Bool) -> Void)? = nil) {
        self.selectionHandler = selectionHandler
        self.model = model; state = ClipboardPanelState(service: model.clipboard)
        super.init(); panel.delegate = self
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true; panel.titlebarSeparatorStyle = .none
        model.clipboardPanel.$layout.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self = self, self.showing else { return }; self.resize()
        }.store(in: &observations)
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main).sink { [weak self] _ in
                guard let self = self, self.showing else { return }; self.resize()
            }.store(in: &observations)
    }
    var isShown: Bool { showing }
    func toggle(snippets: Bool = false) {
        if showing && state.snippets == snippets { close(returnFocus: true); return }
        if !showing {
            target = AppFocus.shared.captureFrontmost()
            presentationScreenID = currentScreen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        }
        state.reset(snippets: snippets); showing = true
        panel.contentView = NSHostingView(rootView: content())
        resize(); panel.makeKeyAndOrderFront(nil)
        // Start with record shortcuts; search is entered by clicking its field or pressing Command-F.
        panel.makeFirstResponder(nil); state.searchFocused = false
        // A nonactivating panel can accept keys over full-screen apps without switching Spaces.
        if eventMonitor == nil { eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in self?.handle(event) ?? event } }
    }
    private var currentScreen: NSScreen? {
        NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens.first
    }
    private func resize() {
        let horizontal = model.clipboardPanel.layout == .horizontal
        panel.isMovableByWindowBackground = !horizontal
        if horizontal {
            let screen = NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber) == presentationScreenID }
                ?? currentScreen
            presentationScreenID = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1100, height: 800)
            panel.setFrame(ClipboardPanelRules.bottomPanelFrame(visible: visible), display: true)
        } else {
            let anchor = showing && panel.isVisible ? NSPoint(x: panel.frame.midX, y: panel.frame.midY) : NSEvent.mouseLocation
            panel.place(size: NSSize(width: 530, height: 670), anchor: anchor)
        }
    }
    func content() -> ClipboardFloatingView {
        ClipboardFloatingView(state: state, service: model.clipboard, preferences: model.clipboardPanel,
                              use: { [weak self] entry, paste, plain in self?.use(entry, paste: paste, plain: plain) },
                              clickRecord: { [weak self] entry, paste in self?.clickRecord(entry, paste: paste) },
                              close: { [weak self] in self?.close(returnFocus: true) },
                              manage: { [weak self] in self?.close(); self?.model.navigate(.clipboard) },
                              guide: { [weak self] in self?.close(); self?.model.showShortcutSettings?(.clipboard) })
    }
    func close(returnFocus: Bool = false) {
        guard !closing else { return }; closing = true; showing = false
        if let monitor = eventMonitor { NSEvent.removeMonitor(monitor); eventMonitor = nil }
        state.searchFocused = false; panel.orderOut(nil)
        if returnFocus, let target = target, !target.isTerminated { target.activate(options: .activateIgnoringOtherApps) }
        closing = false
    }
    func windowDidResignKey(_ notification: Notification) { if showing && !closing { close() } }
    func windowWillClose(_ notification: Notification) { close() }
    func performSelection(_ action: String) {
        guard showing else { toggle(); return }
        guard let entry = state.selected else { return }
        switch action {
        case "copy": use(entry, paste: false)
        case "paste": use(entry, paste: true)
        case "plainCopy": use(entry, paste: false, plain: true)
        case "plainPaste": use(entry, paste: true, plain: true)
        case "pin": if !state.snippets { model.clipboard.pin(entry) }
        case "queue": if !state.snippets { model.clipboard.enqueue(entry) }
        case "delete": if !state.snippets { model.clipboard.delete(entry); state.reconcile() }
        case "group": if !state.snippets { close(); model.navigate(.clipboard); model.clipboard.assignGroup(entry) }
        default: break
        }
    }
    func clickRecord(_ entry: ClipEntry, paste: Bool) {
        state.searchFocused = false; panel.makeFirstResponder(nil); state.selectedID = entry.id
        use(entry, paste: paste, keepOpen: !paste)
    }
    func use(_ entry: ClipEntry, paste: Bool, plain: Bool = false, keepOpen: Bool = false) {
        if let selectionHandler = selectionHandler { selectionHandler(entry, paste, plain); return }
        if paste && !Permissions.requireEventPosting() {
            state.feedback = "直接粘贴需要辅助功能权限；也可点「复制」后在目标应用按 ⌘V。"
            return
        }
        if paste && (target == nil || target?.isTerminated == true || target?.processIdentifier == ProcessInfo.processInfo.processIdentifier) {
            state.feedback = "请先切到目标输入框，再用快捷键打开面板；当前仍可复制。"; return
        }
        let snippet = state.snippets ? model.clipboard.snippets.first(where: { $0.id == entry.id }) : nil
        let prepare = {
            if let snippet = snippet { return self.model.clipboard.useSnippet(snippet, paste: false) }
            return self.model.clipboard.copy(entry, plain: plain)
        }
        let destination = target
        if paste { close(); AppFocus.shared.paste(to: destination, prepare: prepare) }
        else if prepare() {
            if keepOpen { state.feedback = ""; state.copiedID = entry.id }
            else { close(returnFocus: true) }
        }
    }
    func handle(_ event: NSEvent) -> NSEvent? {
        guard showing, panel.isKeyWindow, event.window == nil || event.window == panel, panel.attachedSheet == nil else { return event }
        let editor = panel.firstResponder as? NSTextView
        let editing = editor?.isEditable == true
        let composing = editor?.hasMarkedText() == true
        let chord = KeyChord(event: event)
        if event.isARepeat { return event }
        if composing { return event }
        if chord.key == 53 {
            if editing { state.searchFocused = false; panel.makeFirstResponder(nil) }
            else { close(returnFocus: true) }; return nil
        }
        if chord.key == 3 && chord.modifiers == 1 { state.searchFocused = true; return nil }
        if editing && [125, 126].contains(chord.key) && chord.modifiers == 0 {
            state.searchFocused = false; panel.makeFirstResponder(nil); return nil
        }
        if let index = ClipboardPanelRules.numberIndex(key: chord.key, modifiers: chord.modifiers, configured: model.clipboardPanel.numberModifier, editing: editing, composing: composing) {
            let items = state.items
            if items.indices.contains(index) { use(items[index], paste: model.clipboardPanel.quickUse == .paste) }
            return nil
        }
        if chord.key == 36 && (chord.modifiers == 0 || chord.modifiers == 2) {
            if let selected = state.selected { use(selected, paste: model.clipboardPanel.quickUse == .paste, plain: chord.modifiers == 2) }; return nil
        }
        if !editing {
            if [123,124,125,126].contains(chord.key) && chord.modifiers == 0 { state.move(chord.key == 123 || chord.key == 126 ? -1 : 1); return nil }
            if chord.key == 8 && (chord.modifiers == 1 || chord.modifiers == 3) {
                if let selected = state.selected { use(selected, paste: false, plain: chord.modifiers == 3) }; return nil
            }
            if chord.key == 35 && chord.modifiers == 1, let selected = state.selected, !state.snippets { model.clipboard.pin(selected); return nil }
        }
        return event
    }
    deinit { if let monitor = eventMonitor { NSEvent.removeMonitor(monitor) } }
}
