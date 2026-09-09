import SwiftUI
import AppKit
import IToolsCore

struct ClipboardFloatingView: View {
    @ObservedObject var state: ClipboardPanelState
    @ObservedObject var service: ClipboardService
    @ObservedObject var preferences: ClipboardPanelPreferences
    let use: (ClipEntry, Bool, Bool) -> Void
    let close: () -> Void, manage: () -> Void, guide: () -> Void
    @FocusState private var searchFocus: Bool
    private var horizontal: Bool { preferences.layout == .horizontal }
    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("搜索内容、来源或短语  ⌘F", text: $state.query).textFieldStyle(.plain).focused($searchFocus)
                if !state.query.isEmpty { Button { state.query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
                if !state.snippets {
                    Picker("类型", selection: $state.kind) { ForEach(["全部类型","文字","图片","文件"], id: \.self) { Text($0) } }.labelsHidden().frame(width: 90)
                    Picker("分组", selection: $state.group) { ForEach(service.groups, id: \.self) { Text($0) } }.labelsHidden().frame(width: 86)
                }
            }.padding(.horizontal, 18).padding(.vertical, 11)
            Divider()
            if state.items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 32, weight: .light)).foregroundColor(accent)
                    Text(state.snippets ? "还没有匹配的快捷短语" : service.enabled ? "还没有匹配的历史记录" : "按需开启剪贴板记录").font(.system(size: 16, weight: .medium))
                    Text(state.snippets ? "在主窗口添加常用回复，再通过面板快速使用。" : "支持文字、图片和文件。开启后开始记录新的复制内容。")
                        .font(.system(size: 12)).foregroundColor(.secondary).multilineTextAlignment(.center)
                    if !service.enabled && !state.snippets { Button("开启记录") { service.enabled = true } }
                    Button("打开管理页面", action: manage)
                }.padding(22).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else { entries }
            if !state.feedback.isEmpty { Text(state.feedback).font(.system(size: 11)).foregroundColor(.orange).padding(10).frame(maxWidth: .infinity, alignment: .leading) }
            Divider()
            footer
        }.background(Color(NSColor.windowBackgroundColor)).foregroundColor(.primary).accentColor(accent).buttonStyle(ToolButtonStyle())
            .onChange(of: state.searchFocused) { searchFocus = $0 }
            .onChange(of: searchFocus) { state.searchFocused = $0 }
            .onChange(of: state.query) { _ in state.reconcile() }
            .onChange(of: state.kind) { _ in state.reconcile() }
            .onChange(of: state.group) { _ in state.reconcile() }
            .onChange(of: state.snippets) { _ in state.reconcile() }
            .onChange(of: service.entries.map(\.id)) { _ in state.reconcile() }
    }
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard.fill").foregroundColor(accent)
            Picker("面板", selection: $state.snippets) { Text("剪贴板").tag(false); Text("快捷短语").tag(true) }.pickerStyle(.segmented).labelsHidden().frame(width: 178)
            Spacer(minLength: 0)
            Menu {
                Picker("排列方式", selection: $preferences.layout) { ForEach(ClipboardLayout.allCases, id: \.self) { Text($0.rawValue) } }
                Picker("数字 / 回车 / 双击", selection: $preferences.quickUse) { ForEach(ClipboardQuickUse.allCases, id: \.self) { Text($0.rawValue) } }
                Picker("数字快捷键", selection: $preferences.numberModifier) { ForEach(ClipboardNumberModifier.allCases, id: \.self) { Text($0.rawValue) } }
                Divider(); Toggle("记录剪贴板", isOn: $service.enabled)
                Button("管理历史与短语", action: manage); Button("快捷键操作指南", action: guide)
            } label: { Image(systemName: horizontal ? "rectangle.split.3x1" : "rectangle.split.1x2") }.menuStyle(.borderlessButton).frame(width: 28).help("布局和按键设置")
            Button(action: close) { Image(systemName: "xmark").font(.system(size: 12)) }.buttonStyle(.plain).help("关闭 Esc")
        }.padding(.horizontal, 18).padding(.vertical, 15)
    }
    private var entries: some View {
        ScrollViewReader { proxy in
            ScrollView(horizontal ? .horizontal : .vertical) {
                if horizontal {
                    LazyHStack(spacing: 12) {
                        ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in row(item, index: index).frame(width: 225).id(item.id) }
                    }.padding(14)
                } else {
                    LazyVStack(spacing: 7) {
                        ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in row(item, index: index).id(item.id) }
                    }.padding(12)
                }
            }
            .onChange(of: state.selectedID) { id in if let id = id { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id, anchor: horizontal ? .center : nil) } } }
        }
    }
    private func row(_ entry: ClipEntry, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: entry.kind == .image ? "photo" : entry.kind == .files ? "folder" : "text.alignleft").foregroundColor(accent)
                Text(state.snippets ? entry.source : entry.kind == .image ? "图片" : entry.kind == .files ? "文件" : "文字").font(.system(size: 11, weight: .medium)).lineLimit(1)
                if entry.pinned { Image(systemName: "pin.fill").foregroundColor(accent).font(.system(size: 10)) }
                Spacer(minLength: 2)
                if index < 9 { Text(preferences.numberModifier.symbol + String(index + 1)).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundColor(accent).padding(.horizontal, 6).padding(.vertical, 2).background(accent.opacity(0.1)).cornerRadius(4) }
            }
            if entry.kind == .image, let data = entry.payload.first?.data, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: horizontal ? 99 : 76)
            } else {
                Text(String(entry.text.prefix(1200))).font(.system(size: 13)).lineLimit(horizontal ? 5 : 2).frame(maxWidth: .infinity, alignment: .topLeading)
                    .frame(height: horizontal ? 99 : nil, alignment: .topLeading)
            }
            HStack(spacing: 6) {
                Text(state.snippets ? entry.group : entry.source.components(separatedBy: ".").last ?? entry.source).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                if !state.snippets { Text(entry.date, style: .time) }
            }.font(.system(size: 10)).foregroundColor(.secondary)
            if horizontal {
                HStack { Button("复制") { use(entry, false, false) }; Spacer(); Button("粘贴") { use(entry, true, false) } }.controlSize(.small)
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(state.selected?.id == entry.id ? accent.opacity(0.08) : Color(NSColor.controlBackgroundColor))
            .cornerRadius(9).overlay(RoundedRectangle(cornerRadius: 9).stroke(state.selected?.id == entry.id ? accent.opacity(0.65) : Color.secondary.opacity(0.12), lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { use(entry, preferences.quickUse == .paste, false) }
            .onTapGesture { state.searchFocused = false; state.selectedID = entry.id }
            .contextMenu {
                Button("复制") { use(entry, false, false) }; Button("粘贴") { use(entry, true, false) }
                if entry.kind == .text { Button("复制为纯文本") { use(entry, false, true) }; Button("粘贴为纯文本") { use(entry, true, true) } }
                if !state.snippets { Divider(); Button(entry.pinned ? "取消收藏" : "收藏") { service.pin(entry) }; Button("加入粘贴队列") { service.enqueue(entry) }; Button("删除记录") { service.delete(entry) } }
            }
    }
    private var footer: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("\(state.items.count) 项" + (!service.enabled && !state.snippets ? " · 记录已暂停" : "")).font(.system(size: 11)).foregroundColor(.secondary)
                Spacer()
                Button("复制 ⌘C") { if let selected = state.selected { use(selected, false, false) } }.disabled(state.selected == nil)
                Button("粘贴") { if let selected = state.selected { use(selected, true, false) } }.disabled(state.selected == nil)
            }
            Text("\(preferences.numberModifier.symbol)1–9 / ↩ / 双击：\(preferences.quickUse.rawValue)  ·  方向键选择  ·  Esc 返回")
                .font(.system(size: 10)).foregroundColor(.secondary).lineLimit(2)
        }.padding(.horizontal, 18).padding(.vertical, 12)
    }
}
