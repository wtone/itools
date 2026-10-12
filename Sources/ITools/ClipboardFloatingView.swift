import SwiftUI
import AppKit
import IToolsCore

struct ClipboardFloatingView: View {
    @ObservedObject var state: ClipboardPanelState
    @ObservedObject var service: ClipboardService
    @ObservedObject var preferences: ClipboardPanelPreferences
    let use: (ClipEntry, Bool, Bool) -> Void
    let clickRecord: (ClipEntry, Bool) -> Void
    let close: () -> Void, manage: () -> Void, guide: () -> Void
    @Environment(\.colorScheme) private var scheme
    private var horizontal: Bool { preferences.layout == .horizontal }
    var body: some View {
        Group {
            if horizontal { bottomContent } else { verticalContent }
        }.foregroundColor(ClipboardPanelPalette.text).accentColor(accent).buttonStyle(ToolButtonStyle())
            .background(ClipboardPanelBackdrop()).clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(scheme == .dark ? 0.18 : 0.5), lineWidth: 0.8))
            .onChange(of: state.query) { _ in state.reconcile() }
            .onChange(of: state.kind) { _ in state.reconcile() }
            .onChange(of: state.group) { _ in state.reconcile() }
            .onChange(of: state.snippets) { _ in state.modeChanged() }
            .onChange(of: service.entries.map(\.id)) { _ in state.reconcile() }
    }
    private var verticalContent: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                ClipboardSearchField(text: $state.query, focused: $state.searchFocused, placeholder: "搜索内容、来源或短语  ⌘F", fontSize: 13)
                    .frame(maxWidth: .infinity, minHeight: 20, maxHeight: 20)
                if !state.query.isEmpty { Button { state.query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
                if !state.snippets {
                    Picker("类型", selection: $state.kind) { ForEach(["全部类型","文字","图片","文件"], id: \.self) { Text($0) } }.labelsHidden().frame(width: 90)
                }
                Picker("分组", selection: $state.group) { ForEach(state.groups, id: \.self) { Text($0) } }.labelsHidden().frame(width: 86)
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
        }
    }
    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.on.clipboard.fill").foregroundColor(accent)
            Picker("面板", selection: $state.snippets) { Text("剪贴板").tag(false); Text("快捷短语").tag(true) }.pickerStyle(.segmented).labelsHidden().frame(width: 178)
            Spacer(minLength: 0)
            settingsMenu
            Button(action: close) { Image(systemName: "xmark").font(.system(size: 12)) }.buttonStyle(.plain).help("关闭 Esc")
        }.padding(.horizontal, 18).padding(.vertical, 15)
    }
    private var settingsMenu: some View {
        Menu {
                Picker("排列方式", selection: $preferences.layout) { ForEach(ClipboardLayout.allCases, id: \.self) { Text($0.title).tag($0) } }
                Picker("数字 / 回车", selection: $preferences.quickUse) { ForEach(ClipboardQuickUse.allCases, id: \.self) { Text($0.rawValue) } }
                Picker("数字快捷键", selection: $preferences.numberModifier) { ForEach(ClipboardNumberModifier.allCases, id: \.self) { Text($0.rawValue) } }
                Divider(); Toggle("记录剪贴板", isOn: $service.enabled)
                Button("管理历史与短语", action: manage); Button("快捷键与操作指南", action: guide)
        } label: { Image(systemName: "gearshape").frame(width: 28, height: 28).contentShape(Rectangle()) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28, height: 28)
            .help("布局和按键设置").accessibilityLabel("剪贴板面板设置")
    }
    private var bottomContent: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                bottomToolbar(wide: geometry.size.width >= 1000)
                if state.items.isEmpty { bottomEmpty }
                else { bottomEntries }
                if !state.feedback.isEmpty {
                    Text(state.feedback).font(.system(size: 11)).foregroundColor(.orange)
                        .padding(.horizontal, 16).padding(.bottom, 5).frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 8) {
                    Circle().fill(service.enabled ? Color.green : Color.secondary).frame(width: 5, height: 5)
                    Text(state.snippets ? "\(state.items.count) 条短语" : "\(state.items.count) 条记录 · " + (service.enabled ? "记录中" : "已暂停"))
                    Spacer(minLength: 0)
                    Text(state.copiedID == state.selected?.id && state.copiedID != nil ? "已复制 · 双击粘贴" : "单击复制 · 双击粘贴")
                    if geometry.size.width >= 1000 { Text(state.searchFocused ? "  ·  直接输入搜索  ·  ↓ 浏览记录  ·  ↩ \(preferences.quickUse.rawValue)" : "  ·  \(preferences.numberModifier.symbol)1–9 / ↩：\(preferences.quickUse.rawValue)  ·  方向键选择  ·  ⌘F 搜索") }
                    Spacer(minLength: 0)
                    Text(state.searchFocused ? "Esc 返回列表" : "Esc 关闭")
                }.font(.system(size: 10)).foregroundColor(ClipboardPanelPalette.secondary).lineLimit(1)
                    .padding(.horizontal, 16).padding(.bottom, 8).padding(.top, 2)
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }.foregroundColor(ClipboardPanelPalette.text)
    }
    private func bottomToolbar(wide: Bool) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Picker("面板", selection: $state.snippets) { Text("剪贴板").tag(false); Text("快捷短语").tag(true) }
                    .pickerStyle(.segmented).labelsHidden().frame(width: 150)
                if wide { Spacer(minLength: 0) }
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    ClipboardSearchField(text: $state.query, focused: $state.searchFocused, placeholder: "搜索  ⌘F")
                        .frame(maxWidth: .infinity, minHeight: 20, maxHeight: 20)
                    if !state.query.isEmpty {
                        Button { state.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }
                            .buttonStyle(.plain).help("清除搜索")
                    }
                }.font(.system(size: 11)).padding(.horizontal, 9).frame(height: 28)
                    .frame(maxWidth: wide ? 220 : .infinity)
                    .background(Color.white.opacity(scheme == .dark ? 0.12 : 0.5)).cornerRadius(8)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(state.searchFocused ? accent.opacity(0.7) : Color.white.opacity(0.22), lineWidth: 1))
                if wide { filterBar; Spacer(minLength: 0); groupMenu }
                settingsMenu
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .medium))
                        .frame(width: 26, height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).help("关闭 Esc").accessibilityLabel("关闭剪贴板")
            }
            if !wide { HStack { filterBar; Spacer(minLength: 0); groupMenu } }
        }.padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 5)
    }
    private var filterBar: some View {
        HStack(spacing: 5) {
            if state.snippets { Text("常用回复，随手取用").font(.system(size: 11)).foregroundColor(.secondary) }
            else {
                ForEach(["全部", "文字", "图片", "文件", "收藏"], id: \.self) { title in
                    let active = title == "收藏" ? state.group == "收藏" : state.group != "收藏" && state.kind == (title == "全部" ? "全部类型" : title)
                    let color = ClipboardPanelPalette.filter(title)
                    Button { state.selectFilter(title) } label: {
                        Text(title).font(.system(size: 11, weight: active ? .semibold : .regular))
                            .foregroundColor(active || scheme == .light ? ClipboardPanelPalette.headerInk : color)
                            .frame(width: 42, height: 26)
                            .background(color.opacity(active ? 1 : scheme == .dark ? 0.22 : 0.38)).cornerRadius(6)
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(color.opacity(active ? 0.95 : 0.45), lineWidth: 0.8))
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(title + (active ? "，已选择" : ""))
                        .onHover { inside in if inside { state.selectFilter(title) } }
                        .help("悬停或点击筛选" + title)
                }
            }
        }.fixedSize()
    }
    @ViewBuilder private var groupMenu: some View {
        Group {
            Menu {
                Picker("分组", selection: $state.group) { ForEach(state.groups, id: \.self) { Text($0).tag($0) } }
            } label: {
                Label(state.group == "全部" || state.group == "收藏" ? "分组" : state.group, systemImage: "folder")
                    .font(.system(size: 11)).lineLimit(1).frame(maxWidth: 90).padding(.horizontal, 4)
            }.menuStyle(.borderlessButton).fixedSize().help("按分组筛选")
        }
    }
    private var bottomEntries: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                GlassScrollView(.horizontal, softIndicators: true, horizontalWheel: true) {
                    LazyHStack(spacing: 12) {
                        ForEach(Array(state.items.enumerated()), id: \.element.id) { index, entry in
                            ClipboardHistoryCard(entry: entry, index: index, selected: state.selected?.id == entry.id,
                                snippets: state.snippets, numberModifier: preferences.numberModifier,
                                use: { paste, plain in use(entry, paste, plain) },
                                clickRecord: { paste in clickRecord(entry, paste) })
                                .frame(width: 264, height: max(100, geometry.size.height - 20)).id(entry.id)
                                .contextMenu {
                                    Button("复制") { use(entry, false, false) }; Button("粘贴") { use(entry, true, false) }
                                    if entry.kind == .text { Button("复制为纯文本") { use(entry, false, true) }; Button("粘贴为纯文本") { use(entry, true, true) } }
                                    if !state.snippets {
                                        Divider(); Button(entry.pinned ? "取消收藏" : "收藏") { service.pin(entry) }
                                        Button("加入粘贴队列") { service.enqueue(entry) }; Button("删除记录") { service.delete(entry) }
                                    }
                                }
                        }
                    }.padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 14)
                }
                .onChange(of: state.selectedID) { id in if let id = id { proxy.scrollTo(id, anchor: .center) } }
                .onChange(of: state.kind) { _ in if let first = state.items.first { proxy.scrollTo(first.id, anchor: .leading) } }
                .onChange(of: state.group) { _ in if let first = state.items.first { proxy.scrollTo(first.id, anchor: .leading) } }
            }
        }
    }
    private var bottomEmpty: some View {
        VStack(spacing: 9) {
            Image(systemName: "doc.on.clipboard").font(.system(size: 25, weight: .light)).foregroundColor(accent)
            Text(state.snippets ? "还没有匹配的快捷短语" : service.enabled ? "还没有匹配的记录" : "开启记录，收好每次复制的内容")
                .font(.system(size: 14, weight: .medium))
            Text(state.snippets ? "添加常用回复后，即可在这里快速使用。" : "复制的文字、图片和文件会显示在这里。")
                .font(.system(size: 11)).foregroundColor(.secondary)
            HStack {
                if !service.enabled && !state.snippets { Button("开启记录") { service.enabled = true } }
                if !state.query.isEmpty || state.kind != "全部类型" || state.group != "全部" {
                    Button("清除筛选") { state.query = ""; state.kind = "全部类型"; state.group = "全部" }
                }
                Button(state.snippets ? "管理快捷短语" : "管理历史", action: manage)
            }.controlSize(.small)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(12)
    }
    private var entries: some View {
        ScrollViewReader { proxy in
            GlassScrollView(.vertical, softIndicators: true) {
                LazyVStack(spacing: 7) {
                    ForEach(Array(state.items.enumerated()), id: \.element.id) { index, item in row(item, index: index).id(item.id) }
                }.padding(12)
            }
            .onChange(of: state.selectedID) { id in if let id = id { withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) } } }
        }
    }
    private func row(_ entry: ClipEntry, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: entry.kind == .image ? "photo" : entry.kind == .files ? "folder" : "text.alignleft")
                Text(state.snippets ? entry.source : entry.kind == .image ? "图片" : entry.kind == .files ? "文件" : "文字").font(.system(size: 11, weight: .medium)).lineLimit(1)
                if entry.pinned { Image(systemName: "pin.fill").font(.system(size: 10)) }
                Spacer(minLength: 2)
                if index < 9 { Text(preferences.numberModifier.symbol + String(index + 1)).font(.system(size: 11, weight: .medium, design: .monospaced)).padding(.horizontal, 6).padding(.vertical, 2).background(Color.white.opacity(0.3)).cornerRadius(4) }
            }.foregroundColor(ClipboardPanelPalette.headerInk).padding(.horizontal, 12).padding(.vertical, 8)
                .background(ClipboardPanelPalette.category(entry.kind, snippets: state.snippets))
            if entry.kind == .image, let data = entry.payload.first?.data, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity).frame(height: 76)
            } else {
                Text(String(entry.text.prefix(1200))).font(.system(size: 13)).lineLimit(2).frame(maxWidth: .infinity, alignment: .topLeading).padding(.horizontal, 12)
            }
            HStack(spacing: 6) {
                Text(state.snippets ? entry.group : entry.source.components(separatedBy: ".").last ?? entry.source).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
                if !state.snippets { Text(entry.date, style: .time) }
            }.font(.system(size: 10)).foregroundColor(ClipboardPanelPalette.secondary).padding(.horizontal, 12).padding(.bottom, 10)
        }.frame(maxWidth: .infinity, alignment: .leading)
            .background(ClipboardPanelPalette.cardFill.opacity(0.82))
            .cornerRadius(9).overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(ClipboardPanelPalette.category(entry.kind, snippets: state.snippets).opacity(state.selected?.id == entry.id ? 1 : 0.3), lineWidth: state.selected?.id == entry.id ? 2 : 1))
            .clipboardRecordActions(copy: { clickRecord(entry, false) }, paste: { clickRecord(entry, true) })
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
            Text(state.copiedID == state.selected?.id && state.copiedID != nil ? "已复制 · 可继续选择或双击粘贴" : ClipboardRecordInteraction.hint)
                .font(.system(size: 11)).foregroundColor(accent)
            Text(state.searchFocused ? "直接输入搜索 · ↓ 浏览记录 · 回车使用 · Esc 返回列表" : "\(preferences.numberModifier.symbol)1–9 / ↩：\(preferences.quickUse.rawValue)  ·  方向键选择  ·  ⌘F 搜索")
                .font(.system(size: 10)).foregroundColor(.secondary).lineLimit(2)
        }.padding(.horizontal, 18).padding(.vertical, 12)
    }
}
