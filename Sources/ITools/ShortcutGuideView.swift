import SwiftUI
import AppKit
import IToolsCore

struct ShortcutGuideView: View {
    @ObservedObject var manager: ShortcutManager
    @State var settings: Bool
    @State private var query = ""
    @State private var group = "全部功能"
    @State private var assignedOnly = false
    @State private var recording: ShortcutAction?
    let close: () -> Void
    let run: (String) -> Void
    private var actions: [ShortcutAction] {
        manager.preferences.actions.filter {
            (group == "全部功能" || group == $0.group) && (!assignedOnly || manager.preferences.bindings[$0.id] != nil) &&
            (query.isEmpty || ($0.title + $0.group + $0.detail + manager.display($0.id)).localizedCaseInsensitiveContains(query))
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "keyboard").font(.system(size: 23, weight: .light)).foregroundColor(accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("iTools 快捷键").font(.system(size: 19, weight: .semibold))
                    Text("随时呼出指南  " + manager.display("app.guide")).font(.system(size: 11)).foregroundColor(.secondary)
                }
                Spacer()
                Picker("模式", selection: $settings) { Text("操作指南").tag(false); Text("快捷键设置").tag(true) }.pickerStyle(.segmented).labelsHidden().frame(width: 210)
                Button(action: close) { Image(systemName: "xmark") }.buttonStyle(.plain).help("关闭 Esc")
            }.padding(20)
            Divider()
            if !settings { localGuide.padding(.horizontal, 20).padding(.vertical, 13); Divider() }
            HStack(spacing: 12) {
                TextField("搜索功能或按键", text: $query).textFieldStyle(.roundedBorder)
                Picker("分类", selection: $group) {
                    Text("全部功能").tag("全部功能")
                    ForEach(Array(Set(manager.preferences.actions.map(\.group))).sorted(), id: \.self) { Text($0).tag($0) }
                }.labelsHidden().frame(width: 172)
                Toggle("仅已设置", isOn: $assignedOnly).font(.system(size: 11))
            }.padding(.horizontal, 20).padding(.vertical, 12)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(actions) { action in
                        HStack(spacing: 15) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) { Text(action.title).font(.system(size: 13, weight: .medium)); Text(action.group).font(.system(size: 10)).foregroundColor(.secondary) }
                                Text(manager.failures[action.id] ?? (action.detail.isEmpty ? "可自定义全局快捷键" : action.detail))
                                    .font(.system(size: 11)).foregroundColor(manager.failures[action.id] == nil ? .secondary : .red).lineLimit(2)
                            }
                            Spacer(minLength: 4)
                            if settings {
                                Button { recording = action } label: { Text(manager.display(action.id)).font(.system(size: 12, design: .monospaced)).frame(minWidth: 76) }.help("点击后按下新的组合键")
                                Button { _ = manager.set(nil, for: action.id) } label: { Image(systemName: "xmark.circle") }.disabled(manager.preferences.bindings[action.id] == nil).help("清除快捷键")
                            } else {
                                Text(manager.display(action.id)).font(.system(size: 12, design: .monospaced)).foregroundColor(manager.failures[action.id] == nil ? accent : .red).frame(width: 95, alignment: .trailing)
                                Button("打开 / 执行") { run(action.id) }.controlSize(.small)
                            }
                        }.padding(.vertical, 11)
                        Divider().opacity(0.6)
                    }
                    if actions.isEmpty { Text("没有匹配的功能，试试其他关键词。").foregroundColor(.secondary).padding(30) }
                }.padding(.horizontal, 20)
            }
            Divider()
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(manager.preferences.actions.count) 项功能 · \(manager.preferences.bindings.count) 组全局快捷键").font(.system(size: 11))
                    Text(settings ? "点击按键录入；立即生效并保存。未设置项仍可从指南打开。" : "以上是 iTools 自身操作。剪贴板面板内的按键仅在面板聚焦时生效。")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                }
                Spacer()
                if settings {
                    Button("恢复默认…") {
                        if Panels.confirm("恢复默认快捷键？", detail: "你的自定义组合将被清除，常用按键恢复初始设置。", action: "恢复") { manager.reset() }
                    }
                }
            }.padding(.horizontal, 20).padding(.vertical, 13)
        }.background(Color(NSColor.windowBackgroundColor)).foregroundColor(.primary).accentColor(accent).buttonStyle(ToolButtonStyle())
            .sheet(item: $recording) { action in
                ShortcutRecordingSheet(action: action, manager: manager) { recording = nil }
            }
    }
    private var localGuide: some View {
        HStack(alignment: .top, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("剪贴板面板内").font(.system(size: 12, weight: .semibold))
                Text("1–9  选择前九项（可设置修饰键）\n方向键  选择内容    ·    ⌘F  搜索\n回车 / 双击  使用内容（复制或粘贴）").font(.system(size: 11)).lineSpacing(5)
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                Text("复制与返回").font(.system(size: 12, weight: .semibold))
                Text("⌘C  复制    ·    ⇧⌘C  纯文本复制\n⇧回车  按设定使用纯文本    ·    ⌘P  收藏\nEsc  退出搜索 / 关闭面板并返回").font(.system(size: 11)).lineSpacing(5)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.foregroundColor(.secondary)
    }
}

private struct ShortcutRecordingSheet: View {
    let action: ShortcutAction
    @ObservedObject var manager: ShortcutManager
    let done: () -> Void
    @State private var candidate: KeyChord?
    @State private var error = ""
    var body: some View {
        VStack(spacing: 17) {
            Text(action.title).font(.system(size: 18, weight: .semibold))
            Text("请直接按下组合键").foregroundColor(.secondary)
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(accent.opacity(0.08))
                Text(candidate?.display ?? "⌘ / ⌥ / ⌃ + 按键").font(.system(size: 25, weight: .medium, design: .monospaced))
                KeyRecordingView { chord in
                    if chord.key == 53 { done() }
                    else { candidate = chord; error = manager.preferences.error(for: chord, action: action.id) ?? "" }
                }
            }.frame(height: 82)
            Text(error.isEmpty ? "录入期间暂时停用 iTools 全局快捷键；Esc 取消。\n按键名称按标准键盘位置显示。" : error)
                .font(.system(size: 12)).foregroundColor(error.isEmpty ? .secondary : .red).multilineTextAlignment(.center).frame(minHeight: 38)
            HStack {
                Button("取消", action: done)
                Spacer()
                Button("保存快捷键") {
                    guard let candidate = candidate else { return }
                    manager.suspend(false)
                    if let failure = manager.set(candidate, for: action.id) { error = failure; manager.suspend(true) }
                    else { done() }
                }.disabled(candidate == nil || candidate?.validationError != nil || !error.isEmpty)
            }
        }.padding(25).frame(width: 420).buttonStyle(ToolButtonStyle())
            .onAppear { manager.suspend(true) }.onDisappear { manager.suspend(false) }
    }
}
private struct KeyRecordingView: NSViewRepresentable {
    let receive: (KeyChord) -> Void
    func makeNSView(context: Context) -> RecorderView { let view = RecorderView(); view.receive = receive; return view }
    func updateNSView(_ view: RecorderView, context: Context) { view.receive = receive }
    final class RecorderView: NSView {
        var receive: ((KeyChord) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); DispatchQueue.main.async { [weak self] in guard let self = self else { return }; self.window?.makeFirstResponder(self) } }
        override func keyDown(with event: NSEvent) { if !event.isARepeat { receive?(KeyChord(event: event)) } }
        override func performKeyEquivalent(with event: NSEvent) -> Bool { keyDown(with: event); return true }
        override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    }
}

final class ShortcutGuideController: NSObject, NSWindowDelegate {
    let model: AppModel
    let panel = FloatingToolPanel(title: "iTools 快捷键指南")
    private var monitor: Any?
    private var target: NSRunningApplication?
    private var settings = false
    init(model: AppModel) { self.model = model; super.init(); panel.delegate = self }
    func show(settings: Bool = false) {
        if panel.isVisible && self.settings == settings { close(); return }
        let front = NSWorkspace.shared.frontmostApplication
        target = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? AppFocus.shared.previous : front
        self.settings = settings
        panel.contentView = NSHostingView(rootView: content(settings: settings))
        panel.place(size: NSSize(width: 810, height: 700)); panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(nil)
        if monitor == nil { monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, self.panel.isKeyWindow, self.panel.attachedSheet == nil, event.keyCode == 53, (self.panel.firstResponder as? NSTextView)?.hasMarkedText() != true else { return event }
            self.close(); return nil
        } }
    }
    func content(settings: Bool) -> ShortcutGuideView {
        ShortcutGuideView(manager: model.shortcuts, settings: settings, close: { [weak self] in self?.close() }, run: { [weak self] id in
            self?.close(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self?.model.performCommand(id) }
        })
    }
    func close() { let visible = panel.isVisible; panel.orderOut(nil); if let monitor = monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }; if visible, let target = target, !target.isTerminated { target.activate(options: .activateIgnoringOtherApps) } }
    func windowWillClose(_ notification: Notification) { close() }
    deinit { if let monitor = monitor { NSEvent.removeMonitor(monitor) } }
}
