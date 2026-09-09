import SwiftUI
import AppKit
import IToolsCore

struct QuickPanelView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var monitor: MonitorService
    @ObservedObject var preferences: QuickPanelPreferences
    @ObservedObject var system: QuickSystemService
    @ObservedObject var awake: AwakeService
    @ObservedObject var recorder: RecordingService
    @ObservedObject var clipboard: ClipboardService
    let run: (QuickAction) -> Void
    let openSystem: (SystemShortcut) -> Void
    let navigate: (ToolPage) -> Void
    let close: () -> Void
    let quit: () -> Void
    let stopRecording: () -> Void
    @State private var editing = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "square.stack.3d.up.fill").foregroundColor(accent)
                Text(editing ? "自定义快捷入口" : "iTools").font(.system(size: 16, weight: .semibold))
                Spacer()
                Button { close(); model.showGuide?() } label: { Image(systemName: "keyboard") }.help("快捷键操作指南")
                if !editing {
                    Button("打开主窗口") { navigate(.overview) }.font(.system(size: 11))
                }
                Button(editing ? "完成" : "编辑") { editing.toggle() }.font(.system(size: 11, weight: .medium))
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 11)) }.help("关闭")
            }.buttonStyle(.plain).padding(.horizontal, 18).padding(.vertical, 14)
            Divider().opacity(0.55)
            ScrollView {
                VStack(spacing: 16) {
                    if editing {
                        QuickPanelSettingsView(preferences: preferences)
                    } else {
                        if preferences.showMetrics { QuickStatusCards(monitor: monitor, navigate: navigate) }
                        HStack {
                            ForEach(SystemShortcut.allCases) { shortcut in
                                Button { openSystem(shortcut) } label: {
                                    VStack(spacing: 5) {
                                        if let url = shortcut.url {
                                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 28, height: 28)
                                        } else { Image(systemName: "app").frame(width: 28, height: 28) }
                                        Text(shortcut.title).font(.system(size: 10))
                                    }.frame(maxWidth: .infinity)
                                }.buttonStyle(.plain).help(shortcut.title)
                            }
                        }.padding(.vertical, 2)
                        if recorder.isActive {
                            HStack {
                                Image(systemName: "record.circle.fill").foregroundColor(.red)
                                Text("录制进行中").font(.system(size: 12))
                                Spacer(); Button("停止并保存") { stopRecording() }
                            }.padding(10).background(Color.red.opacity(0.09)).cornerRadius(9)
                        }
                        if awake.active {
                            HStack(spacing: 5) {
                                Image(systemName: "cup.and.saucer.fill")
                                Text(awake.keepsDisplay ? "正在保持亮屏" : "正在防止自动休眠")
                                if let until = awake.until { Text("至 " + until.formatted(date: .omitted, time: .shortened)) }
                                Spacer()
                                Button("停止") { awake.stop() }
                            }.font(.system(size: 11)).foregroundColor(.green)
                        }
                        if preferences.actions.isEmpty {
                            Text("点击右上角「编辑」添加快捷操作").font(.system(size: 12)).foregroundColor(.secondary).padding(.vertical, 16)
                        } else {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5), spacing: 14) {
                                ForEach(preferences.actions) { action in
                                    QuickActionButton(action: action, active: isActive(action), enabled: isEnabled(action)) { run(action) }
                                }
                            }
                        }
                    }
                }.padding(16)
            }
            Divider().opacity(0.55)
            HStack {
                Text("开机 " + uptime).font(.system(size: 11)).foregroundColor(.secondary)
                Spacer()
                Button { navigate(.settings) } label: { Image(systemName: "gearshape") }.help("iTools 设置")
                Menu {
                    Toggle("显示状态卡片", isOn: $preferences.showMetrics)
                    Button(clipboard.enabled ? "暂停剪贴板记录" : "开启剪贴板记录") { clipboard.enabled.toggle() }
                    Button("粘贴队列下一项") { close(); DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { clipboard.pasteNext() } }
                    Divider()
                    Button("系统状态详情") { navigate(.monitor) }
                    Button("自定义快捷入口") { editing = true }
                    Divider()
                    Button("退出 iTools") { quit() }
                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 25).help("更多操作")
            }.buttonStyle(.plain).padding(.horizontal, 18).padding(.vertical, 12)
        }.background(PanelMaterial()).foregroundColor(.primary).accentColor(accent).buttonStyle(ToolButtonStyle())
    }
    private var uptime: String {
        let minutes = Int(ProcessInfo.processInfo.systemUptime / 60)
        return "\(minutes / 1440)天 \(minutes / 60 % 24)小时 \(minutes % 60)分钟"
    }
    private func isActive(_ action: QuickAction) -> Bool {
        switch action {
        case .awake: return awake.active
        case .keepDisplay: return awake.active && awake.keepsDisplay
        case .darkMode: return system.dark
        case .dockAutoHide: return system.dockHidden
        case .menuBarAutoHide: return system.menuHidden
        case .desktopCover: return system.desktopCovered
        case .recording: return recorder.isActive
        default: return false
        }
    }
    private func isEnabled(_ action: QuickAction) -> Bool {
        switch action {
        case .screenshot,.ocr,.colorPicker,.recording: return model.captureEnabled
        case .files: return model.filesEnabled
        default: return true
        }
    }
}
private struct QuickActionButton: View {
    let action: QuickAction
    let active: Bool
    let enabled: Bool
    let run: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: run) {
            VStack(spacing: 6) {
                ZStack(alignment: .topTrailing) {
                    Circle().fill(active ? accent.opacity(0.18) : Color.primary.opacity(hovering ? 0.13 : 0.065))
                        .frame(width: 44, height: 44)
                        .overlay(Image(systemName: action.icon).font(.system(size: 19, weight: .regular)).foregroundColor(active ? accent : .primary))
                    if active { Circle().fill(Color.green).frame(width: 7, height: 7).overlay(Circle().stroke(Color(NSColor.windowBackgroundColor), lineWidth: 1)) }
                }
                Text(action.title).font(.system(size: 10.5)).lineLimit(2).multilineTextAlignment(.center)
                    .frame(height: 26, alignment: .top).frame(maxWidth: .infinity)
            }.contentShape(Rectangle()).opacity(enabled ? 1 : 0.4)
        }.buttonStyle(.plain).disabled(!enabled).onHover { hovering = $0 }
            .help(enabled ? action.detail : "请先在设置中启用相关模块")
            .accessibilityLabel(action.title + (active ? "，已开启" : ""))
    }
}
private struct QuickStatusCards: View {
    @ObservedObject var monitor: MonitorService
    let navigate: (ToolPage) -> Void
    private var s: MonitorSnapshot { monitor.snapshot }
    private func percentage(_ value: Double?) -> String { MetricFormatting.percent(monitor.enabled ? value : nil) }
    var body: some View {
        VStack(spacing: 9) {
            if !monitor.enabled {
                HStack { Text("监控已暂停").font(.system(size: 11)).foregroundColor(.secondary); Spacer(); Button("开启监控") { monitor.enabled = true }.font(.system(size: 11)) }
            }
            HStack(spacing: 10) {
                statusCard("CPU", icon: "cpu", value: percentage(s.cpu)) {
                    HistoryChart(values: monitor.enabled ? monitor.cpuHistory : [], color: accent).frame(height: 30)
                    Text("用户 \(percentage(s.cpuUser))   系统 \(percentage(s.cpuSystem))").font(.system(size: 10)).foregroundColor(.secondary)
                }
                statusCard("内存", icon: "memorychip", value: percentage(s.memoryAvailable ? s.memoryPercent : nil)) {
                    HistoryChart(values: monitor.enabled ? monitor.memoryHistory : [], color: .teal).frame(height: 30)
                    Text(monitor.enabled && s.memoryAvailable ? "\(bytes(s.memoryUsed)) / \(bytes(s.memoryTotal))" : "等待可用读数").font(.system(size: 10)).foregroundColor(.secondary)
                }
            }
            HStack(spacing: 10) {
                statusCard("GPU", icon: "rectangle.3.offgrid", value: percentage(s.gpu)) {
                    Text(monitor.enabled ? (s.gpuDevices.count > 1 ? "多显卡取最高使用率" : (s.gpuDevices.first ?? "驱动未提供读数")) : "已暂停").font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                }
                statusCard("磁盘", icon: "internaldrive", value: percentage(MetricFormatting.diskPercent(free: s.diskFree, total: s.diskTotal))) {
                    Text(monitor.enabled && s.diskTotal > 0 ? "可用 \(bytes(s.diskFree)) / \(bytes(s.diskTotal))" : "等待可用读数").font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                }
            }
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("网络", systemImage: "network").font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                    HStack(spacing: 10) {
                        Text("↓ " + MetricFormatting.rate(monitor.enabled && s.networkAvailable ? s.download : nil))
                        Text("↑ " + MetricFormatting.rate(monitor.enabled && s.networkAvailable ? s.upload : nil))
                    }.font(.system(size: 12, weight: .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
                    if monitor.enabled, let address = s.localAddresses.first {
                        Button(address) { copyText(address); NoticeCenter.shared.success("已复制本机 IP") }
                            .buttonStyle(.plain).font(.system(size: 10)).foregroundColor(accent).help("点击复制；物理接口 IP：\n" + s.localAddresses.joined(separator: "\n"))
                    } else { Text("暂无物理接口 IPv4").font(.system(size: 10)).foregroundColor(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(11).background(cardColor).cornerRadius(12)
                statusCard("温度 / 风扇", icon: "fanblades", value: monitor.enabled ? s.cpuTemperature.map { String(format: "%.0f°C", $0) } ?? "—" : "—") {
                    Text(monitor.enabled ? s.fan.map { String(format: "%.0f RPM", $0) } ?? "风扇读数不可用" : "已暂停").font(.system(size: 10)).foregroundColor(.secondary)
                }
            }
        }
    }
    private var cardColor: Color { Color(NSColor.controlBackgroundColor).opacity(0.7) }
    private func statusCard<C: View>(_ title: String, icon: String, value: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: icon).font(.system(size: 11, weight: .medium)).foregroundColor(.secondary)
                Spacer()
                Text(value).font(.system(size: 18, weight: .semibold)).monospacedDigit()
            }
            content()
        }.frame(maxWidth: .infinity, alignment: .leading).padding(11).background(cardColor).cornerRadius(12)
            .contentShape(Rectangle()).onTapGesture { navigate(.monitor) }.help("打开系统状态详情")
            .accessibilityAddTraits(.isButton).accessibilityAction { navigate(.monitor) }
    }
}
struct QuickPanelSettingsView: View {
    @ObservedObject var preferences: QuickPanelPreferences
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("显示实时状态卡片", isOn: $preferences.showMetrics).toggleStyle(.switch).controlSize(.small)
            HStack { Text("快捷入口").font(.system(size: 14, weight: .semibold)); Spacer(); Button("恢复默认") { preferences.reset() }.font(.system(size: 11)) }
            Text("勾选立即显示；用箭头调整顺序，修改自动保存。").font(.system(size: 11)).foregroundColor(.secondary)
            ForEach(preferences.actions + QuickAction.allCases.filter { !preferences.actions.contains($0) }) { action in
                HStack(spacing: 10) {
                    Toggle(isOn: Binding(get: { preferences.actions.contains(action) }, set: { preferences.set(action, enabled: $0) })) {
                        Label(action.title, systemImage: action.icon).font(.system(size: 12))
                    }
                    Spacer()
                    if let index = preferences.actions.firstIndex(of: action) {
                        Button { preferences.move(action, by: -1) } label: { Image(systemName: "arrow.up") }.disabled(index == 0).help("向前移动")
                        Button { preferences.move(action, by: 1) } label: { Image(systemName: "arrow.down") }.disabled(index == preferences.actions.count-1).help("向后移动")
                    }
                }.help(action.detail)
            }
        }.buttonStyle(ToolButtonStyle())
    }
}
private struct PanelMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView(); view.material = .popover; view.blendingMode = .behindWindow; view.state = .active; return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
