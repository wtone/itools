import SwiftUI
import IToolsCore

struct MenuBarSettingsView: View {
    @ObservedObject var preferences: MenuBarPreferences
    @ObservedObject var monitor: MonitorService
    @State private var screens = MenuBarDisplayScope.availableScreens
    var restorePosition: (() -> Void)? = nil
    private let metricColumns = [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]
    var body: some View {
        SectionBlock(title: "菜单栏显示", detail: "连续指标区 · 内部排序 · 自动保存") {
            VStack(alignment: .leading, spacing: 10) {
                LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Text("显示范围").fixedSize()
                        Picker("显示范围", selection: Binding(get: { preferences.displaySelection.mode }, set: { preferences.setDisplayMode($0) })) {
                            ForEach(MenuBarDisplayMode.allCases) { mode in Text(mode.title).tag(mode) }
                        }.labelsHidden().pickerStyle(.segmented).frame(maxWidth: 240)
                        Spacer(minLength: 0)
                    }.padding(.trailing, 10)
                    if preferences.displaySelection.mode == .single {
                        HStack(spacing: 8) {
                            Text("显示屏幕").fixedSize()
                            Picker("显示屏幕", selection: Binding(
                                get: { preferences.displaySelection.displayID ?? "primary" },
                                set: { id in preferences.selectDisplay(id: id == "primary" ? nil : id, name: screens.first { $0.id == id }?.name) }
                            )) {
                                Text("跟随系统主显示器").tag("primary")
                                ForEach(screens) { screen in Text(screen.name).tag(screen.id) }
                                if let id = preferences.displaySelection.displayID, !screens.contains(where: { $0.id == id }) {
                                    Text((preferences.displaySelection.displayName ?? "已选屏幕") + "（未连接）").tag(id)
                                }
                            }.labelsHidden()
                        }.padding(.trailing, 10)
                    }
                }
                if preferences.displaySelection.mode == .single {
                    if let id = preferences.displaySelection.displayID, !screens.contains(where: { $0.id == id }) {
                        Text("选定屏幕未连接，当前临时显示在主屏；重新接入后自动恢复。")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    } else {
                        Text("仅在所选屏幕显示，其他屏幕不占位；断开时回退主屏，重新接入后恢复。")
                            .font(.system(size: 11)).foregroundColor(.secondary)
                    }
                } else {
                    Text("在所有具有系统菜单栏的屏幕显示；新增或移除屏幕时自动适配。")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
            }.onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in
                screens = MenuBarDisplayScope.availableScreens
            }
            LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 14) {
                ForEach(MenuBarMetric.allCases) { metric in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(metric.title).font(.system(size: 13, weight: .medium))
                            Text(metric.detail).font(.system(size: 11)).foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                        Toggle(metric.title, isOn: Binding(
                            get: { preferences.isEnabled(metric) },
                            set: { preferences.set(metric, enabled: $0) }
                        )).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }.padding(.trailing, 10)
                }
            }
            if preferences.enabledMetrics.isEmpty {
                Text("全部指标已关闭，菜单栏显示 iTools 工具箱图标。").font(.system(size: 11)).foregroundColor(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MenuBarMonitor.metricGap) {
                    Text("显示预览").font(.system(size: 11)).foregroundColor(.secondary).padding(.trailing, 8)
                    ForEach(preferences.visibleMetrics) { metric in
                        let reading = MenuBarReading.make(metric, snapshot: monitor.snapshot, running: monitor.enabled)
                        Image(nsImage: MenuBarMonitor.image(for: reading, width: MenuBarMonitor.imageWidth(for: metric), metric: metric))
                            .renderingMode(.template).foregroundColor(.primary)
                            .frame(width: MenuBarMonitor.imageWidth(for: metric), height: 22)
                            .accessibilityLabel(metric.title).accessibilityValue(reading.top + ", " + reading.bottom).help(reading.tooltip)
                    }
                    Spacer(minLength: 0)
                }.padding(12)
                }.background(InterfaceStyle.raised.opacity(0.48)).cornerRadius(9)
            }
            HStack {
                Text("默认显示在状态图标区最左侧，自动避开刘海。").font(.system(size: 11)).foregroundColor(.secondary)
                Spacer()
                Button("恢复可见位置") { restorePosition?() }.disabled(restorePosition == nil)
                    .help("重新放置整个指标区，保留开关和内部顺序")
            }
            if !monitor.enabled {
                HStack {
                    Text("系统状态监控已暂停，顶部显示「—」。").font(.system(size: 11)).foregroundColor(.secondary)
                    Button("开启监控") { monitor.enabled = true }
                }
            }
            if !MenuBarDisplayScope.isSupported && screens.count > 1 && preferences.displaySelection.mode == .single {
                Text("当前 macOS 暂不支持限定屏幕，菜单栏入口已隐藏。可切换为所有屏幕，或从 Dock / 快捷键打开 iTools。")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            Text("开启任意指标时隐藏主图标，全部关闭时显示工具箱图标。指标始终相邻，可直接拖动或按住 ⌘ 拖动调整内部顺序；开关和重启保留排序。显示范围和目标屏幕自动保存，热插拔不改变指标选择。网速两行左对齐，点击打开快捷面板，右键打开菜单。指标区宽度随开关变化，邻近应用图标只随原生布局平移，排列顺序保持不变。")
                .font(.system(size: 11)).foregroundColor(.secondary)
        }
    }
}
