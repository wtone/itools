import SwiftUI
import AppKit
import IToolsCore

private enum ShortcutPalette {
    static let canvas = adaptive(0xF1F3F7, 0x242832)
    static let card = adaptive(0xFFFFFF, 0x303640)
    static let rail = adaptive(0x353A44, 0x20242B)
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255,
                           blue: Double(value & 255) / 255, alpha: 1)
        })
    }
    static func tint(_ category: ShortcutCategory) -> Color {
        switch category {
        case .general: return Color(red: 0.20, green: 0.48, blue: 0.90)
        case .clipboard: return Color(red: 0.83, green: 0.34, blue: 0.64)
        case .capture: return Color(red: 0.55, green: 0.40, blue: 0.84)
        case .recording: return Color(red: 0.88, green: 0.34, blue: 0.36)
        case .files: return Color(red: 0.87, green: 0.58, blue: 0.17)
        case .windows: return Color(red: 0.16, green: 0.61, blue: 0.66)
        case .system: return Color(red: 0.22, green: 0.58, blue: 0.83)
        }
    }
}

struct ShortcutGuideView: View {
    @ObservedObject var manager: ShortcutManager
    @ObservedObject var state: ShortcutWorkspaceState
    @ObservedObject var editor: ShortcutEditor
    @ObservedObject var clipboard: ClipboardPanelPreferences
    @FocusState private var searchFocused: Bool
    let close: () -> Void
    let run: (String) -> Void
    private var sections: [ShortcutSection] {
        ShortcutDirectory.sections(actions: manager.preferences.actions, category: state.isSearching ? nil : state.category,
                                   query: state.query, assignedOnly: state.assignedOnly, bindings: manager.preferences.bindings)
    }
    private var visibleCount: Int { sections.reduce(0) { $0 + $1.actions.count } }
    private func matchesHelp(_ text: String) -> Bool {
        state.query.split(whereSeparator: { $0.isWhitespace }).allSatisfy { text.localizedCaseInsensitiveContains(String($0)) }
    }
    private var showInteraction: Bool {
        state.isSearching ? matchesHelp("剪贴板 交互 显示 数字快捷键 1–9 修饰键 屏幕 底部 卡片 布局 横向 竖向 复制 粘贴 回车 双击") : state.category == .clipboard
    }
    private var showLocalGuide: Bool {
        state.isSearching ? matchesHelp("剪贴板 面板内按键 固定按键 数字 1–9 方向键 复制 纯文本 搜索 收藏 返回 Esc ⌘F ⌘C ⇧⌘C ⌘P " + clipboard.numberModifier.symbol) : state.category == .clipboard
    }
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                sidebar.frame(width: 196)
                VStack(spacing: 0) {
                    header
                    searchBar
                    GlassScrollView {
                        let columns = geometry.size.width - 196 >= 750 ? 2 : 1
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20, alignment: .top), count: columns), alignment: .leading, spacing: 22) {
                            ForEach(Array(sections.prefix(2))) { section in card(section) }
                            if showInteraction { interactionCard }
                            if showLocalGuide { localGuideCard }
                            ForEach(Array(sections.dropFirst(2))) { section in card(section) }
                        }.padding(.horizontal, 26).padding(.top, 8).padding(.bottom, 26)
                        if sections.isEmpty && !showInteraction && !showLocalGuide { emptyState }
                    }.id(state.category.rawValue + state.query + String(state.assignedOnly))
                    footer
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(ShortcutPalette.canvas)
            }
        }.foregroundColor(.primary).accentColor(accent).buttonStyle(ToolButtonStyle())
            .onChange(of: state.category) { _ in editor.cancel() }
            .onChange(of: state.query) { _ in editor.cancel() }
            .onChange(of: state.assignedOnly) { _ in editor.cancel() }
            .onChange(of: state.searchRequest) { _ in searchFocused = true }
            .onChange(of: searchFocused) { focused in if focused { editor.cancel() } }
            .onDisappear { editor.cancel() }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "keyboard").font(.system(size: 23)).foregroundColor(.white)
                    .frame(width: 42, height: 42).background(accent).cornerRadius(12)
                VStack(alignment: .leading, spacing: 3) {
                    Text("iTools").font(.system(size: 22, weight: .bold))
                    Text("快捷键与操作指南").font(.system(size: 10)).foregroundColor(.white.opacity(0.68))
                }
            }.padding(.horizontal, 19).padding(.top, 30).padding(.bottom, 29)
            GlassScrollView {
                VStack(spacing: 7) {
                    ForEach(ShortcutCategory.allCases) { category in
                        Button {
                            editor.cancel(); state.category = category; state.query = ""; searchFocused = false
                        } label: {
                            HStack(spacing: 10) {
                                categoryIcon(category, size: 28)
                                Text(category.title).font(.system(size: 12, weight: state.category == category ? .semibold : .regular))
                                Spacer(minLength: 0)
                                Text(String(manager.preferences.actions.filter { ShortcutDirectory.location(of: $0).0 == category }.count))
                                    .font(.system(size: 10)).foregroundColor(.white.opacity(0.6))
                            }.padding(.horizontal, 10).padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading)
                                .background(state.category == category && !state.isSearching ? Color.white.opacity(0.14) : .clear)
                                .cornerRadius(10).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel(category.title)
                    }
                }.padding(.horizontal, 10)
            }
            VStack(alignment: .leading, spacing: 13) {
                Divider().overlay(Color.white.opacity(0.1))
                HStack {
                    Text("随时呼出").font(.system(size: 11)).foregroundColor(.white.opacity(0.65))
                    Spacer()
                    Text(manager.display("app.guide")).font(.system(size: 12, weight: .medium, design: .monospaced))
                }
                Button {
                    editor.cancel()
                    if Panels.confirm("恢复默认快捷键？", detail: "你的自定义组合将被清除，常用按键恢复初始设置。", action: "恢复") { manager.reset() }
                } label: {
                    Label("恢复默认快捷键…", systemImage: "arrow.counterclockwise")
                        .font(.system(size: 11)).foregroundColor(.white.opacity(0.8))
                }.buttonStyle(.plain)
            }.padding(20)
        }.foregroundColor(.white).frame(maxHeight: .infinity).background(ShortcutPalette.rail)
    }
    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 7) {
                Text(state.isSearching ? "搜索结果" : state.category.title).font(.system(size: 26, weight: .semibold))
                Text(state.isSearching ? "跨分类查找功能，在结果中直接修改按键。" : state.category.subtitle)
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
            Spacer()
            Button(action: close) { Image(systemName: "xmark").font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
                    .frame(width: 30, height: 30).background(ShortcutPalette.card).clipShape(Circle()).contentShape(Circle())
            }.buttonStyle(.plain).accessibilityLabel("关闭快捷键面板").help("关闭 Esc")
        }.padding(.horizontal, 26).padding(.top, 28).padding(.bottom, 20)
    }
    private var searchBar: some View {
        HStack(spacing: 13) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("搜索全部功能或按键  ⌘F", text: $state.query).textFieldStyle(.plain).font(.system(size: 12)).focused($searchFocused)
                if !state.query.isEmpty {
                    Button { state.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }.buttonStyle(.plain).help("清除搜索")
                }
            }.padding(.horizontal, 12).padding(.vertical, 10).background(ShortcutPalette.card).cornerRadius(9)
            Toggle("仅已设置", isOn: $state.assignedOnly).font(.system(size: 11)).fixedSize()
        }.padding(.horizontal, 26).padding(.bottom, 18)
    }
    private func categoryIcon(_ category: ShortcutCategory, size: CGFloat = 27) -> some View {
        Image(systemName: category.icon).font(.system(size: size * 0.52, weight: .medium)).foregroundColor(.white)
            .frame(width: size, height: size).background(ShortcutPalette.tint(category)).cornerRadius(7)
    }
    private func card(_ section: ShortcutSection) -> some View {
        ShortcutCard(title: section.title, subtitle: state.isSearching ? section.category.title : section.detail,
                     icon: section.category.icon, tint: ShortcutPalette.tint(section.category)) {
            VStack(spacing: 0) {
                ForEach(Array(section.actions.enumerated()), id: \.element.id) { index, action in
                    if index > 0 { Divider().opacity(0.5) }
                    ShortcutActionRow(action: action, manager: manager, editor: editor, run: run)
                }
            }
        }
    }
    private var interactionCard: some View {
        ShortcutCard(title: "交互与显示", subtitle: "剪贴板与短语共用，修改立即保存", icon: "slider.horizontal.3", tint: ShortcutPalette.tint(.capture)) {
            VStack(spacing: 17) {
                Picker("数字快捷键", selection: $clipboard.numberModifier) {
                    ForEach(ClipboardNumberModifier.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Picker("数字 / 回车", selection: $clipboard.quickUse) {
                    ForEach(ClipboardQuickUse.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Text(ClipboardRecordInteraction.hint).font(.system(size: 11)).foregroundColor(.secondary)
                Divider().opacity(0.5)
                Picker("面板样式", selection: $clipboard.layout) {
                    ForEach(ClipboardLayout.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.radioGroup)
            }.font(.system(size: 12)).padding(.vertical, 7)
        }
    }
    private var localGuideCard: some View {
        ShortcutCard(title: "面板内按键", subtitle: "打开后用数字选择记录，⌘F 进入搜索", icon: "keyboard", tint: ShortcutPalette.tint(.system)) {
            VStack(spacing: 10) {
                localKey("使用前九项", clipboard.numberModifier.symbol + "1–9")
                localKey("选择内容", "↑ ↓ ← →")
                localKey("使用内容 / 纯文本", "↩ / ⇧↩")
                localKey("复制 / 纯文本复制", "⌘C / ⇧⌘C")
                localKey("搜索 / 收藏", "⌘F / ⌘P")
                localKey("退出搜索或返回", "Esc")
            }.padding(.vertical, 5)
        }
    }
    private func localKey(_ title: String, _ key: String) -> some View {
        HStack {
            Text(title).font(.system(size: 11)).foregroundColor(.secondary)
            Spacer()
            Text(key).font(.system(size: 11, weight: .medium, design: .monospaced))
                .padding(.horizontal, 7).padding(.vertical, 4).background(ShortcutPalette.canvas).cornerRadius(5)
        }
    }
    private var emptyState: some View {
        VStack(spacing: 13) {
            Image(systemName: "magnifyingglass").font(.system(size: 27)).foregroundColor(.secondary)
            Text(state.assignedOnly ? "没有符合条件的已设置项" : "没有找到匹配的功能").font(.system(size: 16, weight: .medium))
            Text("试试功能名称、分类或按键，也可以清除筛选条件。").font(.system(size: 12)).foregroundColor(.secondary)
            Button("清除筛选") { state.query = ""; state.assignedOnly = false }
        }.frame(maxWidth: .infinity).padding(36)
    }
    private var footer: some View {
        HStack(spacing: 10) {
            Text("\(visibleCount) 项全局功能").font(.system(size: 11, weight: .medium))
            Text(editor.message.isEmpty ? "点击按键框编辑；行菜单中可执行或清除。" : editor.message)
                .font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
            Spacer(minLength: 0)
            Text("已设置 \(manager.preferences.bindings.count) / \(manager.preferences.actions.count)").font(.system(size: 10)).foregroundColor(.secondary).fixedSize()
        }.padding(.horizontal, 26).padding(.vertical, 13).background(ShortcutPalette.card.opacity(0.65))
    }
}

private struct ShortcutCard<Content: View>: View {
    let title: String, subtitle: String, icon: String
    let tint: Color
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 9) {
                Image(systemName: icon).font(.system(size: 14, weight: .medium)).foregroundColor(.white)
                    .frame(width: 28, height: 28).background(tint).cornerRadius(7)
                Text(title).font(.system(size: 15, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 9) {
                if !subtitle.isEmpty { Text(subtitle).font(.system(size: 10)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true) }
                content()
            }.padding(.horizontal, 17).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
                .background(ShortcutPalette.card).cornerRadius(18)
        }.frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct ShortcutActionRow: View {
    let action: ShortcutAction
    @ObservedObject var manager: ShortcutManager
    @ObservedObject var editor: ShortcutEditor
    let run: (String) -> Void
    private var editing: Bool { editor.action?.id == action.id }
    private var detail: String {
        if action.id.hasPrefix("file.") || action.id.hasPrefix("mark.") || action.id.hasPrefix("clipSelection.") { return "" }
        return action.detail == action.title ? "" : action.detail
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Text(action.title).font(.system(size: 12, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 2)
                keyField
                Menu {
                    Button("打开 / 执行此功能") { editor.cancel(); run(action.id) }
                    Button("清除快捷键") { editor.clear(action) }.disabled(manager.preferences.bindings[action.id] == nil)
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
                        .frame(width: 30, height: 30).contentShape(Rectangle())
                }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 30, height: 30)
                    .help(action.title + "：执行或清除快捷键")
                    .accessibilityLabel(action.title + "的更多操作")
            }
            if editing {
                Text(editor.error.isEmpty ? "按下组合键，点击保存；Esc 取消。" : editor.error)
                    .font(.system(size: 11)).foregroundColor(editor.error.isEmpty ? .secondary : .red).fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("录入时暂停全局按键").font(.system(size: 10)).foregroundColor(.secondary)
                    Spacer(minLength: 0)
                    Button("取消") { editor.cancel() }.controlSize(.small)
                    Button("保存") { editor.save() }.controlSize(.small)
                        .disabled(editor.candidate == nil || !editor.error.isEmpty).buttonStyle(ToolButtonStyle())
                }
            } else if let failure = manager.failures[action.id] {
                Text(failure).font(.system(size: 11)).foregroundColor(.red).fixedSize(horizontal: false, vertical: true)
            } else if !detail.isEmpty {
                Text(detail).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(2).help(detail)
            }
        }.padding(.vertical, 10)
    }
    private var keyField: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7).fill(editing ? accent.opacity(0.09) : ShortcutPalette.canvas.opacity(0.7))
            if editing {
                Text(editor.candidate?.display ?? "请按组合键").font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(editor.error.isEmpty ? accent : .red)
                KeyRecordingView { editor.receive($0) }.id(action.id)
            } else {
                Button { editor.begin(action) } label: {
                    Text(manager.preferences.bindings[action.id]?.display ?? "录入快捷键")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(manager.failures[action.id] != nil ? .red : manager.preferences.bindings[action.id] == nil ? .secondary : accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("修改" + action.title + "的快捷键").help("点击后录入组合键")
            }
        }.frame(width: 112, height: 30)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(editing ? accent : Color.secondary.opacity(0.18), lineWidth: editing ? 1.5 : 0.7))
    }
}

private struct KeyRecordingView: NSViewRepresentable {
    let receive: (KeyChord) -> Void
    func makeNSView(context: Context) -> RecorderView { let view = RecorderView(); view.receive = receive; return view }
    func updateNSView(_ view: RecorderView, context: Context) { view.receive = receive }
    final class RecorderView: NSView {
        var receive: ((KeyChord) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            DispatchQueue.main.async { [weak self] in guard let self = self else { return }; self.window?.makeFirstResponder(self) }
        }
        override func keyDown(with event: NSEvent) { if !event.isARepeat { receive?(KeyChord(event: event)) } }
        override func performKeyEquivalent(with event: NSEvent) -> Bool { keyDown(with: event); return true }
        override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    }
}

final class ShortcutGuideController: NSObject, NSWindowDelegate {
    let model: AppModel
    let state = ShortcutWorkspaceState()
    let editor: ShortcutEditor
    let panel = FloatingToolPanel(title: "iTools 快捷键与操作指南")
    private var monitor: Any?
    private var target: NSRunningApplication?
    init(model: AppModel) { self.model = model; editor = ShortcutEditor(manager: model.shortcuts); super.init(); panel.delegate = self }
    func show(toggle: Bool = false, category: ShortcutCategory? = nil) {
        if toggle && panel.isVisible { close(); return }
        if let category = category { editor.cancel(); state.category = category; state.query = "" }
        if !panel.isVisible {
            let front = NSWorkspace.shared.frontmostApplication
            target = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? AppFocus.shared.previous : front
            panel.contentView = NSHostingView(rootView: content())
            panel.place(size: NSSize(width: 1080, height: 760))
        }
        panel.makeKeyAndOrderFront(nil)
        if editor.action == nil { panel.makeFirstResponder(nil) }
        if monitor == nil { monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in self?.handle(event) ?? event } }
    }
    func handle(_ event: NSEvent) -> NSEvent? {
        guard panel.isKeyWindow, panel.attachedSheet == nil, editor.action == nil,
              (panel.firstResponder as? NSTextView)?.hasMarkedText() != true else { return event }
        if event.keyCode == 3 && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command { state.searchRequest += 1; return nil }
        if event.keyCode == 53 {
            if !state.query.isEmpty { state.query = "" } else { close() }
            return nil
        }
        return event
    }
    func content() -> ShortcutGuideView {
        ShortcutGuideView(manager: model.shortcuts, state: state, editor: editor, clipboard: model.clipboardPanel,
                          close: { [weak self] in self?.close() }, run: { [weak self] id in
            self?.close(returnFocus: false); DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self?.model.performCommand(id) }
        })
    }
    func close(returnFocus: Bool = true) {
        editor.cancel(); let visible = panel.isVisible; panel.orderOut(nil)
        if let monitor = monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        if returnFocus && visible, let target = target, !target.isTerminated { target.activate(options: .activateIgnoringOtherApps) }
    }
    func windowDidResignKey(_ notification: Notification) { editor.cancel() }
    func windowWillClose(_ notification: Notification) { close() }
    deinit { if let monitor = monitor { NSEvent.removeMonitor(monitor) } }
}
