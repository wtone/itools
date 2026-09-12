import SwiftUI
import AppKit
import IToolsCore
import FinderSync
import AVFoundation

let accent = Color(NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        ? NSColor(srgbRed: 0.43, green: 0.64, blue: 1, alpha: 1)
        : NSColor(srgbRed: 0.15, green: 0.36, blue: 0.80, alpha: 1)
})
struct ToolButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.controlSize) private var size
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size == .small ? 11 : 12))
            .foregroundColor(InterfaceStyle.text)
            .padding(.horizontal, 11).padding(.vertical, size == .small ? 4 : 6)
            .background(configuration.isPressed ? accent.opacity(0.14) : InterfaceStyle.raised.opacity(0.78))
            .cornerRadius(7)
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(InterfaceStyle.border.opacity(0.5), lineWidth: 0.6))
            .shadow(color: .black.opacity(configuration.isPressed ? 0 : 0.025), radius: 1, y: 1)
            .opacity(enabled ? 1 : 0.4)
    }
}
struct RootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var notices = NoticeCenter.shared
    var body: some View {
        HStack(spacing: 0) {
            MainSidebar(model: model)
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(model.page.rawValue).font(.system(size: 24, weight: .semibold))
                    Text(model.page.subtitle).font(.system(size: 12)).foregroundColor(InterfaceStyle.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 30).padding(.top, 48).padding(.bottom, 22)
                ScrollViewReader { proxy in
                GlassScrollView(softIndicators: true) {
                    Group {
                        switch model.page {
                        case .overview: OverviewView(model: model, monitor: model.monitor, clipboard: model.clipboard)
                        case .capture:
                            if model.captureEnabled { CapturePage(capture: model.capture, recorder: model.recorder) }
                            else { DisabledView(title: "截图模块已关闭") }
                        case .clipboard: ClipboardPage(service: model.clipboard, shortcuts: model.shortcuts, showPanel: { model.showClipboard?(false) })
                        case .files:
                            if model.filesEnabled { FilesPage(service: model.files, menuPreferences: model.finderMenu) }
                            else { DisabledView(title: "访达模块已关闭") }
                        case .monitor: MonitorPage(service: model.monitor, menuPreferences: model.menuBar)
                        case .utilities: UtilitiesPage(model: model, awake: model.awake)
                        case .settings: SettingsPage(model: model, clipboard: model.clipboard, monitor: model.monitor)
                        }
                    }.padding(.horizontal, 30).padding(.top, 8).padding(.bottom, 26).frame(maxWidth: .infinity, alignment: .leading).environment(\.workspaceSections, true)
                }.onChange(of: model.utilityAnchor) { anchor in DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { proxy.scrollTo(anchor, anchor: .top) } }
                    .onChange(of: model.page) { page in if page == .utilities { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { proxy.scrollTo(model.utilityAnchor, anchor: .top) } } }
                }
                Rectangle().fill(Color.white.opacity(0.12)).frame(height: 0.5)
                HStack(spacing: 7) {
                    Image(systemName: "info.circle").foregroundColor(InterfaceStyle.cyan)
                    Text(notices.message).lineLimit(1).font(.system(size: 11)).foregroundColor(InterfaceStyle.secondary)
                    Spacer()
                    Image(systemName: "lock.shield").font(.system(size: 11)).foregroundColor(InterfaceStyle.secondary)
                }.padding(.horizontal, 22).padding(.vertical, 10).background(InterfaceStyle.surface.opacity(0.16))
            }.frame(maxWidth: .infinity, maxHeight: .infinity).foregroundColor(InterfaceStyle.text)
        }.background(FrostedBackground())
            .overlay(alignment: .top) { WindowDragStrip().frame(height: 30) }
            .ignoresSafeArea()
            .frame(minWidth: 970, minHeight: 680).accentColor(accent).buttonStyle(ToolButtonStyle())
            .alert("操作未完成", isPresented: Binding(get: { notices.error != nil }, set: { if !$0 { notices.error = nil } })) {
                Button("知道了", role: .cancel) { notices.error = nil }
            } message: { Text(notices.error ?? "") }
    }
}
private struct MainSidebar: View {
    @ObservedObject var model: AppModel
    var body: some View {
        VStack(spacing: 4) {
            VStack(spacing: 9) {
                Image(systemName: "square.stack.3d.up.fill").font(.system(size: 34, weight: .medium))
                    .foregroundColor(InterfaceStyle.cyan).frame(width: 66, height: 66)
                    .background(Color.white.opacity(0.95)).cornerRadius(17)
                Text("iTools").font(.system(size: 21, weight: .semibold)).foregroundColor(.white)
                Text("v" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"))
                    .font(.system(size: 11)).foregroundColor(.white.opacity(0.62))
            }.frame(maxWidth: .infinity).padding(.top, 48).padding(.bottom, 28)
            ForEach(ToolPage.allCases) { page in
                Button { model.page = page } label: {
                    HStack(spacing: 12) {
                        InstrumentIcon(name: page.icon, color: InterfaceStyle.color(for: page), size: 25)
                        Text(page.rawValue).font(.system(size: 13, weight: model.page == page ? .semibold : .medium))
                        Spacer(minLength: 0)
                    }.foregroundColor(.white.opacity(model.page == page ? 1 : 0.82))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(model.page == page ? Color.white.opacity(0.19) : .clear).cornerRadius(10)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.horizontal, 13).accessibilityLabel(page.rawValue)
            }
            Spacer(minLength: 15)
            Button { model.showShortcutSettings?(nil) } label: {
                Label("快捷键与操作指南", systemImage: "keyboard").font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.86)).frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(Color.white.opacity(0.08)).cornerRadius(9).contentShape(Rectangle())
            }.buttonStyle(.plain).padding(.horizontal, 17)
            Text("Intel Mac · macOS 12+").font(.system(size: 10)).foregroundColor(.white.opacity(0.48))
                .padding(.top, 9).padding(.bottom, 18)
        }.frame(width: 218).background(InterfaceStyle.graphite.opacity(0.86))
    }
}

struct SectionBlock<Content: View>: View {
    let title: String
    var detail: String = ""
    var minimumHeight: CGFloat = 0
    @ViewBuilder var content: () -> Content
    @Environment(\.workspaceSections) private var card
    var body: some View {
        Group {
            if card {
                VStack(alignment: .leading, spacing: 13) {
                    HStack(spacing: 10) {
                        InstrumentIcon(name: InterfaceStyle.sectionIcon(title).0, color: InterfaceStyle.sectionIcon(title).1, size: 27)
                        Text(title).font(.system(size: 15, weight: .semibold))
                    }.padding(.leading, 2)
                    VStack(alignment: .leading, spacing: 15) {
                        content()
                        if !detail.isEmpty { Text(detail).font(.system(size: 11)).foregroundColor(InterfaceStyle.secondary).fixedSize(horizontal: false, vertical: true) }
                    }.padding(21).frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .topLeading).instrumentSurface()
                }
            }
            else { section }
        }
    }
    private var section: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                Text(title).font(.system(size: card ? 15 : 17, weight: .semibold)).fixedSize(horizontal: true, vertical: false); Spacer(minLength: 0)
                if !detail.isEmpty { Text(detail).font(.system(size: 11)).foregroundColor(InterfaceStyle.secondary).multilineTextAlignment(.trailing).fixedSize(horizontal: false, vertical: true) }
            }
            content()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
struct EmptyState: View {
    let icon: String; let title: String; let detail: String
    var body: some View {
        VStack(spacing: 11) {
            Image(systemName: icon).font(.system(size: 32, weight: .light)).foregroundColor(accent.opacity(0.75))
            Text(title).font(.system(size: 16, weight: .medium))
            Text(detail).font(.system(size: 12)).foregroundColor(.secondary).multilineTextAlignment(.center).frame(maxWidth: 410)
        }.frame(maxWidth: .infinity).padding(.vertical, 45)
    }
}
struct DisabledView: View {
    let title: String
    var body: some View { EmptyState(icon: "power", title: title, detail: "前往设置重新启用，即可使用此模块。") }
}
struct ActionTile: View {
    let icon: String; let title: String; let detail: String; let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                InstrumentIcon(name: icon, color: title == "找回复制" ? InterfaceStyle.pink : (title == "整理文件" ? InterfaceStyle.amber : InterfaceStyle.cyan), size: 34)
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundColor(.primary)
                Text(detail).font(.system(size: 11)).foregroundColor(.secondary)
            }.frame(maxWidth: .infinity, minHeight: 104, alignment: .leading).padding(16)
                .instrumentSurface(tint: hovering ? accent : nil).contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovering = $0 }
    }
}
struct OverviewView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var monitor: MonitorService
    @ObservedObject var clipboard: ClipboardService
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                InstrumentIcon(name: "square.grid.2x2", color: InterfaceStyle.cyan, size: 27)
                Text("常用工具").font(.system(size: 15, weight: .semibold))
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ActionTile(icon: "viewfinder", title: "截取屏幕", detail: "⌥ ⇧ 4") { model.takeScreenshot() }
                ActionTile(icon: "doc.on.clipboard", title: "找回复制", detail: "⌥ ⌘ V") { model.navigate(.clipboard) }
                ActionTile(icon: "folder.badge.plus", title: "整理文件", detail: "模板与右键工具") { model.navigate(.files) }
                ActionTile(icon: "rectangle.split.2x1", title: "安排窗口", detail: "分屏与专注工具") { model.navigate(.utilities) }
            }
            SectionBlock(title: "此刻的 Mac", detail: monitor.enabled ? "每 2 秒更新" : "监控已暂停") {
                HStack(spacing: 25) {
                    MetricView(title: "CPU 使用率", value: monitor.snapshot.cpu.map { String(format: "%.0f%%", $0) } ?? "—", detail: "所有核心平均")
                    Divider().frame(height: 58)
                    MetricView(title: "内存使用", value: monitor.snapshot.memoryTotal == 0 ? "—" : String(format: "%.0f%%", monitor.snapshot.memoryPercent), detail: bytes(monitor.snapshot.memoryUsed))
                    Divider().frame(height: 58)
                    MetricView(title: "磁盘可用", value: monitor.snapshot.diskTotal == 0 ? "—" : bytes(monitor.snapshot.diskFree), detail: "用户所在卷")
                }.padding(.vertical, 8)
            }
            SectionBlock(title: "按自己的习惯使用") {
                InfoRow(icon: "doc.on.clipboard", title: clipboard.enabled ? "剪贴板历史已开启" : "剪贴板历史默认关闭", detail: clipboard.enabled ? "已保存 \(clipboard.entries.count) 项内容；可随时暂停或清空。" : "开启后记录文本、图片和文件。保密标记的内容会跳过。")
                InfoRow(icon: "lock.shield", title: "权限在需要时申请", detail: "截图需屏幕录制权限，窗口控制与直接粘贴需辅助功能权限。")
            }
        }
    }
}
struct InfoRow: View {
    let icon: String; let title: String; let detail: String
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.system(size: 16)).foregroundColor(accent).frame(width: 23).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 12)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 3)
    }
}
struct MetricView: View {
    let title: String; let value: String; let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 12)).foregroundColor(.secondary)
            Text(value).font(.system(size: 27, weight: .medium)).monospacedDigit()
            Text(detail).font(.system(size: 11)).foregroundColor(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
