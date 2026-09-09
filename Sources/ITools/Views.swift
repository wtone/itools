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
            .foregroundColor(.primary)
            .padding(.horizontal, 10).padding(.vertical, size == .small ? 4 : 5)
            .background(configuration.isPressed ? accent.opacity(0.12) : Color(NSColor.controlBackgroundColor))
            .cornerRadius(5)
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.28), lineWidth: 0.7))
            .opacity(enabled ? 1 : 0.4)
    }
}
struct RootView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var notices = NoticeCenter.shared
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Image(systemName: "square.stack.3d.up.fill").font(.system(size: 25)).foregroundColor(accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("iTools").font(.system(size: 24, weight: .bold))
                        Text("为你的 Mac 多做一点").font(.system(size: 10)).foregroundColor(.secondary)
                    }
                }.padding(.horizontal, 16).padding(.top, 27).padding(.bottom, 29)
                ForEach(ToolPage.allCases) { page in
                    Button { model.page = page } label: {
                        HStack(spacing: 11) {
                            Image(systemName: page.icon).font(.system(size: 15)).frame(width: 21)
                            Text(page.rawValue).font(.system(size: 13, weight: model.page == page ? .semibold : .regular))
                            Spacer()
                        }.padding(.horizontal, 12).padding(.vertical, 10)
                            .foregroundColor(model.page == page ? accent : .primary)
                            .background(model.page == page ? accent.opacity(0.10) : .clear).cornerRadius(7)
                    }.buttonStyle(.plain).padding(.horizontal, 9).accessibilityLabel(page.rawValue)
                }
                Spacer()
                Button { model.showGuide?() } label: { Label("快捷键操作指南", systemImage: "keyboard") }.padding(.horizontal, 19).padding(.bottom, 8)
                Divider().padding(.horizontal, 16)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Intel 原生支持").font(.system(size: 11, weight: .medium))
                    Text("macOS 12+  ·  v" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版")).font(.system(size: 10)).foregroundColor(.secondary)
                }.padding(18)
            }.frame(width: 208).background(Color(NSColor.windowBackgroundColor))
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(model.page.rawValue).font(.system(size: 28, weight: .bold))
                    Text(model.page.subtitle).font(.system(size: 13)).foregroundColor(.secondary)
                }.padding(.horizontal, 30).padding(.top, 28).padding(.bottom, 23)
                Divider().padding(.horizontal, 30)
                ScrollViewReader { proxy in
                ScrollView {
                    Group {
                        switch model.page {
                        case .overview: OverviewView(model: model, monitor: model.monitor, clipboard: model.clipboard)
                        case .capture:
                            if model.captureEnabled { CapturePage(capture: model.capture, recorder: model.recorder) }
                            else { DisabledView(title: "截图模块已关闭") }
                        case .clipboard: ClipboardPage(service: model.clipboard, shortcuts: model.shortcuts, showPanel: { model.showClipboard?(false) })
                        case .files:
                            if model.filesEnabled { FilesPage(service: model.files) }
                            else { DisabledView(title: "访达模块已关闭") }
                        case .monitor: MonitorPage(service: model.monitor)
                        case .utilities: UtilitiesPage(model: model, awake: model.awake)
                        case .companions: CompanionsPage(registry: model.companions)
                        case .settings: SettingsPage(model: model, clipboard: model.clipboard, monitor: model.monitor)
                        }
                    }.padding(30).frame(maxWidth: .infinity, alignment: .leading)
                }.onChange(of: model.utilityAnchor) { anchor in DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { proxy.scrollTo(anchor, anchor: .top) } }
                    .onChange(of: model.page) { page in if page == .utilities { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { proxy.scrollTo(model.utilityAnchor, anchor: .top) } } }
                }
                Divider()
                HStack(spacing: 7) {
                    Image(systemName: "info.circle").foregroundColor(.secondary)
                    Text(notices.message).lineLimit(1).font(.system(size: 11)).foregroundColor(.secondary)
                    Spacer()
                    Text("本机运行").font(.system(size: 10)).foregroundColor(.secondary)
                }.padding(.horizontal, 20).padding(.vertical, 10)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(NSColor.controlBackgroundColor))
        }.frame(minWidth: 970, minHeight: 680).accentColor(accent).buttonStyle(ToolButtonStyle())
            .alert("操作未完成", isPresented: Binding(get: { notices.error != nil }, set: { if !$0 { notices.error = nil } })) {
                Button("知道了", role: .cancel) { notices.error = nil }
            } message: { Text(notices.error ?? "") }
    }
}
struct SectionBlock<Content: View>: View {
    let title: String
    var detail: String = ""
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 17, weight: .semibold)); Spacer()
                if !detail.isEmpty { Text(detail).font(.system(size: 11)).foregroundColor(.secondary) }
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
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon).font(.system(size: 25, weight: .light)).foregroundColor(accent)
                Text(title).font(.system(size: 15, weight: .semibold)).foregroundColor(.primary)
                Text(detail).font(.system(size: 11)).foregroundColor(.secondary)
            }.frame(maxWidth: .infinity, minHeight: 104, alignment: .leading).padding(17)
                .background(Color(NSColor.windowBackgroundColor)).cornerRadius(10)
        }.buttonStyle(.plain)
    }
}
struct OverviewView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var monitor: MonitorService
    @ObservedObject var clipboard: ClipboardService
    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("熟悉的 Mac，更多可能。").font(.system(size: 23, weight: .medium))
                    Text("从一个动作开始。工具随用随开，工作保持连贯。").font(.system(size: 12)).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "laptopcomputer").font(.system(size: 52, weight: .ultraLight)).foregroundColor(accent.opacity(0.75))
            }.padding(.vertical, 4)
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
            Divider()
            SectionBlock(title: "按自己的习惯使用") {
                InfoRow(icon: "doc.on.clipboard", title: clipboard.enabled ? "剪贴板历史已开启" : "剪贴板历史默认关闭", detail: clipboard.enabled ? "已保存 \(clipboard.entries.count) 项内容；可随时暂停或清空。" : "开启后记录文本、图片和文件。保密标记的内容会跳过。")
                InfoRow(icon: "lock.shield", title: "权限在需要时申请", detail: "截图需屏幕录制权限，窗口控制与直接粘贴需辅助功能权限。")
                InfoRow(icon: "app.connected.to.app.below.fill", title: "也能与你已有的工具一起用", detail: "连接 iShot、iRightMouse、iCopy 和 State，保留原版的完整能力。")
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
