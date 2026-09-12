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
    var includesBackground = true
    @State private var editing = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                InstrumentIcon(name: "square.stack.3d.up.fill", size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(editing ? "自定义快捷入口" : "iTools").font(.system(size: 16, weight: .semibold))
                    if !editing { Text("系统状态与快捷操作").font(.system(size: 10)).foregroundColor(InterfaceStyle.secondary) }
                }
                Spacer()
                if !editing {
                    Button("打开主窗口") { navigate(.overview) }.font(.system(size: 11))
                }
                Button(editing ? "完成" : "编辑") { editing.toggle() }.font(.system(size: 11, weight: .medium))
                Button(action: close) { Image(systemName: "xmark").font(.system(size: 11)) }.help("关闭")
            }.buttonStyle(.plain).padding(.horizontal, 18).padding(.vertical, 14)
            Rectangle().fill(InterfaceStyle.border.opacity(0.6)).frame(height: 0.5)
            GlassScrollView(softIndicators: true) {
                VStack(spacing: 12) {
                    if editing {
                        QuickPanelSettingsView(preferences: preferences)
                    } else {
                        if preferences.showMetrics { QuickStatusCards(monitor: monitor, navigate: navigate) }
                        HStack(spacing: 0) {
                            ForEach(SystemShortcut.allCases) { shortcut in
                                Button { openSystem(shortcut) } label: {
                                    VStack(spacing: 5) {
                                        if let url = shortcut.url {
                                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 28, height: 28)
                                        } else { Image(systemName: "app").frame(width: 28, height: 28) }
                                        Text(shortcut.title).font(.system(size: 10))
                                    }.frame(maxWidth: .infinity).padding(.vertical, 7).contentShape(Rectangle())
                                }.buttonStyle(.plain).help(shortcut.title)
                            }
                        }.padding(.horizontal, 4).instrumentSurface(radius: 12)
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
                            HStack {
                                Text("快捷操作").font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Text("\(preferences.actions.count) 项入口").font(.system(size: 10)).foregroundColor(InterfaceStyle.secondary)
                            }.padding(.horizontal, 2)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 5), spacing: 8) {
                                ForEach(preferences.actions) { action in
                                    QuickActionButton(action: action, active: isActive(action), enabled: isEnabled(action)) { run(action) }
                                }
                            }
                        }
                    }
                }.padding(12)
            }
            Rectangle().fill(InterfaceStyle.border.opacity(0.6)).frame(height: 0.5)
            HStack {
                Label("开机 " + uptime, systemImage: "clock").font(.system(size: 10)).foregroundColor(InterfaceStyle.secondary)
                Spacer()
                Button { close(); model.showShortcutSettings?(nil) } label: {
                    Label("快捷键与操作指南", systemImage: "keyboard")
                        .font(.system(size: 11, weight: .medium)).foregroundColor(accent)
                        .padding(.horizontal, 9).padding(.vertical, 6)
                        .background(accent.opacity(0.09)).cornerRadius(7)
                        .contentShape(Rectangle())
                }.help("查看功能分组、操作说明，并直接修改快捷键")
                    .accessibilityIdentifier("itools.quick-panel.shortcut-guide")
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
                } label: { Image(systemName: "ellipsis").frame(width: 28, height: 24).contentShape(Rectangle()) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28).help("更多操作")
            }.buttonStyle(.plain).padding(.horizontal, 18).padding(.vertical, 12)
        }.background(Group { if includesBackground { FrostedBackground() } })
            .foregroundColor(InterfaceStyle.text).accentColor(accent).buttonStyle(ToolButtonStyle())
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
    @Environment(\.colorScheme) private var scheme
    private var tint: Color {
        switch action {
        case .awake, .keepDisplay, .files: return InterfaceStyle.amber
        case .darkMode, .screenSaver, .menuBarAutoHide, .ocr: return InterfaceStyle.violet
        case .cleanScreen, .cleanKeyboard, .desktopCover: return InterfaceStyle.cyan
        case .screenshot, .clipboard, .colorPicker, .recording, .emptyTrash: return InterfaceStyle.pink
        default: return accent
        }
    }
    var body: some View {
        Button(action: run) {
            VStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 11).fill(Color.white.opacity(scheme == .dark ? 0.14 : 0.65))
                        RoundedRectangle(cornerRadius: 11).fill(tint.opacity(scheme == .dark ? 0.18 : 0.10))
                        if active {
                            RoundedRectangle(cornerRadius: 11).fill(LinearGradient(colors: [tint, tint.opacity(0.78)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                        Image(systemName: action.icon).font(.system(size: 17, weight: .medium))
                            .foregroundColor(active ? .white : tint)
                    }.frame(width: 36, height: 36)
                        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Color.white.opacity(scheme == .dark ? 0.20 : 0.65), lineWidth: 0.7))
                    if active {
                        Image(systemName: "checkmark").font(.system(size: 6.5, weight: .bold)).foregroundColor(tint)
                            .frame(width: 11, height: 11).background(Color.white).clipShape(Circle()).offset(x: 3, y: -3)
                    }
                }
                Text(action.title).font(.system(size: 10.5)).lineLimit(2).multilineTextAlignment(.center)
                    .frame(height: 23, alignment: .top).frame(maxWidth: .infinity)
            }.padding(.top, 5).padding(.horizontal, 2).padding(.bottom, 1)
                .background(active ? tint.opacity(0.09) : Color.white.opacity(hovering ? 0.18 : 0)).cornerRadius(10)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(active ? tint.opacity(0.22) : Color.white.opacity(hovering ? 0.3 : 0), lineWidth: 0.7))
                .contentShape(Rectangle()).opacity(enabled ? 1 : 0.4)
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
        VStack(spacing: 8) {
            HStack {
                ActivityBadge(title: monitor.enabled ? "实时监测" : "监控已暂停", active: monitor.enabled)
                Spacer()
                if monitor.enabled { Text("每 2 秒更新").font(.system(size: 10)).foregroundColor(InterfaceStyle.secondary) }
                else { Button("开启监控") { monitor.enabled = true }.font(.system(size: 11)) }
            }
            HStack(alignment: .top, spacing: 10) {
                statusCard("CPU", icon: "cpu", value: percentage(s.cpu), color: accent) {
                    HistoryChart(values: monitor.enabled ? monitor.cpuHistory : [], color: accent).frame(height: 28)
                    Text("用户 \(percentage(s.cpuUser))   系统 \(percentage(s.cpuSystem))")
                }
                statusCard("内存", icon: "memorychip", value: percentage(s.memoryAvailable ? s.memoryPercent : nil), color: InterfaceStyle.cyan) {
                    HistoryChart(values: monitor.enabled ? monitor.memoryHistory : [], color: InterfaceStyle.cyan).frame(height: 28)
                    Text(monitor.enabled && s.memoryAvailable ? "\(bytes(s.memoryUsed)) / \(bytes(s.memoryTotal))" : "等待可用读数")
                }
            }
            HStack(alignment: .top, spacing: 10) {
                statusCard("GPU", icon: "rectangle.3.offgrid", value: percentage(s.gpu), color: InterfaceStyle.violet) {
                    UsageTrack(value: monitor.enabled ? s.gpu : nil, color: InterfaceStyle.violet)
                    Text(monitor.enabled ? (s.gpuDevices.count > 1 ? "多显卡取最高使用率" : (s.gpuDevices.first ?? "驱动未提供读数")) : "已暂停").lineLimit(1)
                }
                statusCard("磁盘", icon: "internaldrive", value: percentage(MetricFormatting.diskPercent(free: s.diskFree, total: s.diskTotal)), color: InterfaceStyle.cyan) {
                    UsageTrack(value: monitor.enabled ? MetricFormatting.diskPercent(free: s.diskFree, total: s.diskTotal) : nil, color: InterfaceStyle.cyan)
                    Text(monitor.enabled && s.diskTotal > 0 ? "可用 \(bytes(s.diskFree)) / \(bytes(s.diskTotal))" : "等待可用读数").lineLimit(1)
                }
            }
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        InstrumentIcon(name: "network", color: InterfaceStyle.cyan, size: 24)
                        Text("网络").font(.system(size: 11, weight: .medium))
                        Spacer()
                    }
                    HStack(spacing: 12) {
                        rate(s.download, symbol: "arrow.down", color: InterfaceStyle.cyan)
                        rate(s.upload, symbol: "arrow.up", color: accent)
                    }
                    if monitor.enabled, let address = s.localAddresses.first {
                        Button(address) { copyText(address); NoticeCenter.shared.success("已复制本机 IP") }
                            .buttonStyle(.plain).font(.system(size: 10)).foregroundColor(accent).help("点击复制；物理接口 IP：\n" + s.localAddresses.joined(separator: "\n"))
                    } else { Text("暂无物理接口 IPv4").font(.system(size: 10)).foregroundColor(InterfaceStyle.secondary) }
                }.frame(maxWidth: .infinity, minHeight: 62, alignment: .topLeading).padding(10).instrumentSurface(tint: InterfaceStyle.cyan)
                statusCard("温度 / 风扇", icon: "fanblades", value: monitor.enabled ? s.cpuTemperature.map { String(format: "%.0f°C", $0) } ?? "—" : "—", color: InterfaceStyle.amber) {
                    HStack {
                        Image(systemName: "wind")
                        Text(monitor.enabled ? s.fan.map { String(format: "%.0f RPM", $0) } ?? "风扇读数不可用" : "已暂停")
                    }
                    Text("CPU 温度与风扇转速")
                }
            }
        }
    }
    private func rate(_ value: Double, symbol: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).foregroundColor(color)
            Text(MetricFormatting.rate(monitor.enabled && s.networkAvailable ? value : nil))
        }.font(.system(size: 13, weight: .medium)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
    }
    private func statusCard<C: View>(_ title: String, icon: String, value: String, color: Color, @ViewBuilder content: () -> C) -> some View {
        Button { navigate(.monitor) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    InstrumentIcon(name: icon, color: color, size: 24)
                    Text(title).font(.system(size: 11, weight: .medium))
                    Spacer(minLength: 1)
                    Text(value).font(.system(size: 22, weight: .medium)).monospacedDigit().minimumScaleFactor(0.8).lineLimit(1)
                }
                content().font(.system(size: 10)).foregroundColor(InterfaceStyle.secondary)
            }.frame(maxWidth: .infinity, alignment: .topLeading).padding(10)
                .instrumentSurface(tint: color).contentShape(Rectangle())
        }.buttonStyle(.plain).help("打开系统状态详情")
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
