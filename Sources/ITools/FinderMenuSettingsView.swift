import SwiftUI
import IToolsCore

final class FinderMenuPreferences: ObservableObject {
    @Published private(set) var layout: FinderMenuLayout
    @Published private(set) var saveError: String?
    private let persist: Bool
    init(persist: Bool = true) {
        self.persist = persist; layout = persist ? .load() : FinderMenuLayout()
    }
    func set(_ id: String, enabled: Bool) {
        guard FinderActions.action(id) != nil else { return }
        var next = layout
        if enabled { next.topLevelIDs.insert(id) } else { next.topLevelIDs.remove(id) }
        apply(next)
    }
    func apply(_ next: FinderMenuLayout) {
        layout = next
        saveError = persist && !layout.save() ? "暂未保存成功，请重试。" : nil
    }
}

struct FinderMenuSettingsButton: View {
    @ObservedObject var preferences: FinderMenuPreferences
    @State private var presented = false
    var body: some View {
        Button("自定义右键菜单…") { presented = true }
            .foregroundColor(.primary)
            .sheet(isPresented: $presented) { FinderMenuSettingsView(preferences: preferences) }
    }
}

struct FinderMenuSelectionSummary: View {
    @ObservedObject var preferences: FinderMenuPreferences
    var body: some View {
        Text("\(preferences.layout.topLevelActions.count) 项显示在一级菜单")
            .font(.system(size: 12)).foregroundColor(.secondary)
    }
}

struct FinderMenuSettingsView: View {
    @ObservedObject var preferences: FinderMenuPreferences
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    private var groups: [FinderActionGroup] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return FinderActions.groups.compactMap { group in
            let actions = group.actions.filter { query.isEmpty || group.title.localizedCaseInsensitiveContains(query) ||
                FinderMenuLayout.displayTitle($0).localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query) }
            return actions.isEmpty ? nil : FinderActionGroup(title: group.title, icon: group.icon, actions: actions)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Finder 右键菜单").font(.system(size: 21, weight: .semibold))
                Text("勾选的操作直接显示在一级菜单；未勾选的保留在“iTools 访达工具”子菜单。")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
            HStack(spacing: 10) {
                TextField("搜索操作，如 TXT、终端、压缩", text: $search).textFieldStyle(.roundedBorder)
                Button { preferences.apply(.common) } label: { Text("常用预设").foregroundColor(.primary) }
                    .help("新建 TXT、拷贝路径、进入终端")
                Menu("批量设置") {
                    Button("全部显示在一级") { preferences.apply(FinderMenuLayout(topLevelIDs: Set(FinderActions.all.map(\.id)))) }
                    Button("全部放回子菜单") { preferences.apply(FinderMenuLayout()) }
                }.fixedSize()
            }
            HStack(alignment: .top, spacing: 18) {
                GlassScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(groups, id: \.title) { group in
                            VStack(alignment: .leading, spacing: 10) {
                                Label(group.title, systemImage: group.icon).font(.system(size: 12, weight: .semibold)).foregroundColor(.secondary)
                                ForEach(group.actions, id: \.id) { action in
                                    Toggle(FinderMenuLayout.displayTitle(action), isOn: Binding(
                                        get: { preferences.layout.topLevelIDs.contains(action.id) },
                                        set: { preferences.set(action.id, enabled: $0) }))
                                        .toggleStyle(.checkbox).font(.system(size: 13)).frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                        if groups.isEmpty { Text("没有匹配的操作").foregroundColor(.secondary).padding(.vertical, 30) }
                    }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                }.instrumentSurface(radius: 12)
                VStack(alignment: .leading, spacing: 10) {
                    Text("一级菜单预览").font(.system(size: 13, weight: .semibold))
                    Text("已选 \(preferences.layout.topLevelActions.count) / \(FinderActions.all.count) 项").font(.system(size: 12)).foregroundColor(.secondary)
                    GlassScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if preferences.layout.topLevelActions.isEmpty {
                                Text("勾选左侧操作后，会直接出现在这里。").foregroundColor(.secondary).font(.system(size: 12))
                            }
                            ForEach(preferences.layout.topLevelActions, id: \.id) { action in
                                Text(action.id == "open-with" ? "iTools · 打开方式  ›" : FinderMenuLayout.topLevelTitle(action))
                                    .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                            }
                            if !preferences.layout.remainingGroups.isEmpty {
                                Divider()
                                HStack { Label("iTools 访达工具", systemImage: "folder.badge.gearshape"); Spacer(); Image(systemName: "chevron.right") }
                                    .font(.system(size: 12))
                                Text("其余 \(FinderActions.all.count - preferences.layout.topLevelActions.count) 项保留在子菜单")
                                    .font(.system(size: 11)).foregroundColor(.secondary)
                            }
                        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    }.instrumentSurface(radius: 12)
                    Text("“打开方式”移到一级后，仍展开系统关联应用列表。")
                        .font(.system(size: 11)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(width: 260)
            }
            HStack {
                if let error = preferences.saveError {
                    Text(error).foregroundColor(.red)
                    Button("重试保存") { preferences.apply(preferences.layout) }
                } else { Text("自动保存 · 下次打开右键菜单时生效").foregroundColor(.secondary) }
                Spacer()
                Button("完成") { dismiss() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }.font(.system(size: 12))
        }.padding(24).frame(width: 780, height: 660).background(FrostedBackground())
            .buttonStyle(ToolButtonStyle())
    }
}
