import SwiftUI
import IToolsCore

struct MenuBarSettingsView: View {
    @ObservedObject var preferences: MenuBarPreferences
    @ObservedObject var monitor: MonitorService
    var restorePosition: (() -> Void)? = nil
    var body: some View {
        SectionBlock(title: "菜单栏显示", detail: "仅主显示器 · ⌘ 拖动排序 · 自动保存") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 14) {
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
                Text("已隐藏全部指标，iTools 工具箱图标仍保留。").font(.system(size: 11)).foregroundColor(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: MenuBarMonitor.metricGap) {
                    Text("显示预览").font(.system(size: 11)).foregroundColor(.secondary).padding(.trailing, 8)
                    ForEach(MenuBarMetric.allCases.filter { preferences.isEnabled($0) }) { metric in
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
                    .help("重新放置主图标及指标，保留开关和排列顺序")
            }
            if !monitor.enabled {
                HStack {
                    Text("系统状态监控已暂停，顶部显示「—」。").font(.system(size: 11)).foregroundColor(.secondary)
                    Button("开启监控") { monitor.enabled = true }
                }
            }
            if !MenuBarDisplayScope.isSupported && NSScreen.screens.count > 1 {
                Text("当前 macOS 暂不支持限定主屏，菜单栏入口已隐藏。可从 Dock 打开 iTools，或使用快捷键打开快捷面板。")
                    .font(.system(size: 11)).foregroundColor(.secondary)
            }
            Text("主图标和每个指标都是独立菜单项：按住 ⌘ 拖动任意一项即可调整位置，也可以与其他应用的菜单项交错排列，位置自动保存。仅在主显示器显示，扩展屏不占位。网速上方上传、下方下载，悬停查看完整读数；点击打开快捷面板。拖入刘海遮挡区域后自动恢复可见位置。")
                .font(.system(size: 11)).foregroundColor(.secondary)
        }
    }
}
