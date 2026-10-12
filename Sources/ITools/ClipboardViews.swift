import SwiftUI
import AppKit
import IToolsCore

struct ClipboardPage: View {
    @ObservedObject var service: ClipboardService
    @ObservedObject var shortcuts: ShortcutManager
    let showPanel: () -> Void
    @State private var tab = 0
    @State private var snippetTitle = ""
    @State private var snippetBody = ""
    @State private var snippetGroup = "常用"
    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack {
                Picker("内容", selection: $tab) { Text("剪贴板历史").tag(0); Text("快捷短语").tag(1) }.pickerStyle(.segmented).frame(width: 300)
                Spacer()
                Button("浮动面板 " + shortcuts.display("quick.clipboard"), action: showPanel)
                Toggle("记录剪贴板", isOn: $service.enabled).toggleStyle(.switch).controlSize(.small)
            }
            Text(ClipboardRecordInteraction.hint).font(.system(size: 11)).foregroundColor(.secondary)
            if tab == 0 {
                HStack {
                    TextField("搜索内容或来源应用", text: $service.filter).textFieldStyle(.roundedBorder)
                    Picker("分组", selection: $service.group) { ForEach(service.groups, id: \.self) { Text($0).tag($0) } }.frame(width: 170)
                    Menu { Button("导出历史…") { service.exportHistory() }; Button("导入历史…") { service.importHistory() }; Divider(); Button("清空所有记录…") { service.clear() } } label: { Image(systemName: "ellipsis").frame(width: 28, height: 26).contentShape(Rectangle()) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28).help("历史记录管理")
                }.padding(12).instrumentSurface(radius: 10)
                if service.stackCount > 0 {
                    HStack { Text("连续粘贴队列：\(service.stackCount) 项"); Spacer(); Button("粘贴下一项  " + shortcuts.display("clipboard.next")) { service.pasteNext() } }
                    .font(.system(size: 12)).padding(12).background(accent.opacity(0.08)).cornerRadius(7)
                }
                if service.visible.isEmpty {
                    EmptyState(icon: "doc.on.clipboard", title: service.enabled ? "还没有匹配的记录" : "需要时，再开启记录", detail: service.enabled ? "复制一段文字、一张图片或文件，它会出现在这里。也可调整搜索词和分组。" : "打开右上角开关后，开始记录新的复制内容。历史仅保存在这台 Mac 上。")
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(service.visible) { entry in
                            ClipRow(entry: entry, service: service)
                        }
                    }
                }
                Text("保留 \(service.retentionDays) 天，最多 \(service.maxCount) 项，容量 100 MB；收藏不自动清除。单项上限 10 MB。")
                .font(.system(size: 11)).foregroundColor(.secondary)
            } else {
                SectionBlock(title: "添加快捷短语") {
                    HStack {
                        TextField("短语名称", text: $snippetTitle).textFieldStyle(.roundedBorder)
                        TextField("分组", text: $snippetGroup).textFieldStyle(.roundedBorder).frame(width: 130)
                    }
                    TextEditor(text: $snippetBody).frame(height: 94).border(Color.secondary.opacity(0.2))
                    HStack {
                        Text("变量：{{date}}、{{time}}、{{clipboard}}").font(.system(size: 11)).foregroundColor(.secondary)
                        Spacer()
                        Button("添加短语") {
                            if service.saveSnippet(title: snippetTitle, body: snippetBody, group: snippetGroup) {
                                snippetTitle = ""; snippetBody = ""
                            }
                        }.disabled(snippetTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || snippetBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                if service.snippets.isEmpty { EmptyState(icon: "text.quote", title: "常用回复，少打一遍", detail: "保存地址、邮件签名或重复使用的文字。选择短语可复制，或直接粘贴到之前的应用。") }
                ForEach(service.snippets) { snippet in
                    HStack(alignment: .top) {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(snippet.title).font(.system(size: 14, weight: .semibold))
                                Text(snippet.body).lineLimit(3).font(.system(size: 12)).foregroundColor(.secondary)
                                Text(snippet.group).font(.system(size: 10)).foregroundColor(.secondary)
                            }
                            Spacer(minLength: 8)
                        }.padding(16)
                        .clipboardRecordActions(copy: { service.useSnippet(snippet, paste: false) },
                        paste: { service.useSnippet(snippet, paste: true) })
                        HStack {
                            Button("复制") { service.useSnippet(snippet, paste: false) }
                            Button("粘贴") { service.useSnippet(snippet, paste: true) }
                            Button { service.removeSnippet(snippet.id) } label: { Image(systemName: "trash") }.help("删除短语")
                        }.padding(.vertical, 16).padding(.trailing, 16)
                    }.instrumentSurface(radius: 12).help(ClipboardRecordInteraction.hint)
                }
            }
        }
    }
}
struct ClipRow: View {
    let entry: ClipEntry
    @ObservedObject var service: ClipboardService
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Group {
                    if entry.kind == .image, let data = entry.payload.first?.data, let image = NSImage(data: data) {
                        Image(nsImage: image).resizable().scaledToFit().frame(width: 56, height: 48)
                    } else {
                        InstrumentIcon(name: entry.kind == .files ? "doc.on.doc" : "text.alignleft", size: 38)
                    }
                }
                VStack(alignment: .leading, spacing: 7) {
                    Text(String(entry.text.prefix(2000))).font(.system(size: 13)).lineLimit(4)
                    HStack(spacing: 8) {
                        if entry.pinned { Image(systemName: "pin.fill").foregroundColor(accent) }
                        Text(entry.source)
                        Text(entry.date, style: .relative)
                        if !entry.group.isEmpty { Text(entry.group) }
                    }.font(.system(size: 10)).foregroundColor(.secondary)
                }
                Spacer(minLength: 8)
            }.padding(15)
            .clipboardRecordActions(copy: { service.copy(entry) }, paste: { service.copy(entry, paste: true) })
            VStack(spacing: 7) {
                Button("复制") { service.copy(entry) }
                Button("粘贴") { service.copy(entry, paste: true) }
            }.controlSize(.small).padding(.vertical, 15)
            Menu {
                Button(entry.pinned ? "取消收藏" : "收藏") { service.pin(entry) }
                Button("设置分组…") { service.assignGroup(entry) }
                Button("加入连续粘贴队列") { service.enqueue(entry) }
                if entry.kind == .text { Button("粘贴为纯文本") { service.copy(entry, plain: true, paste: true) } }
                Divider(); Button("删除记录") { service.delete(entry) }
            } label: { Image(systemName: "ellipsis").frame(width: 28, height: 26).contentShape(Rectangle()) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28).help("记录操作")
            .padding(.leading, 12).padding(.trailing, 15).padding(.top, 15)
        }.instrumentSurface(radius: 12).help(ClipboardRecordInteraction.hint)
    }
}
