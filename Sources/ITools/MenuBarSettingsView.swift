import SwiftUI
import IToolsCore

struct MenuBarSettingsView: View {
    @ObservedObject var preferences: MenuBarPreferences
    @ObservedObject var monitor: MonitorService
    var body: some View {
        SectionBlock(title: "菜单栏显示", detail: "独立开关 · 立即生效 · 自动保存") {
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
                HStack(spacing: 16) {
                    Text("显示预览").font(.system(size: 11)).foregroundColor(.secondary)
                    ForEach(MenuBarMetric.allCases.filter { preferences.isEnabled($0) }) { metric in
                        let reading = MenuBarReading.make(metric, snapshot: monitor.snapshot, running: monitor.enabled)
                        VStack(spacing: 1) {
                            Text(reading.top).font(.system(size: 11, weight: .medium)).monospacedDigit()
                            Text(reading.bottom).font(.system(size: 10)).monospacedDigit()
                        }.frame(minWidth: 36).help(reading.tooltip)
                    }
                    Spacer(minLength: 0)
                }.padding(12).background(Color(NSColor.windowBackgroundColor)).cornerRadius(7)
            }
            if !monitor.enabled {
                HStack {
                    Text("系统状态监控已暂停，顶部显示「—」。").font(.system(size: 11)).foregroundColor(.secondary)
                    Button("开启监控") { monitor.enabled = true }
                }
            }
            Text("点击顶部指标可打开快捷面板；按住 ⌘ 拖动可调整位置。菜单栏空间有限，可关闭不常看的指标。")
                .font(.system(size: 11)).foregroundColor(.secondary)
        }
    }
}
