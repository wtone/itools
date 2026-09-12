import SwiftUI
import AppKit
import IToolsCore

struct LoginItemSettingsView: View {
    @ObservedObject var controller: LoginItemController
    var minimumHeight: CGFloat = 0
    private var status: String {
        if controller.isUpdating { return "正在更新…" }
        switch controller.state {
        case .disabled: return "未开启"
        case .enabled: return "已开启"
        case .requiresApproval: return "等待系统允许"
        case .unavailable: return "暂时无法读取状态"
        }
    }
    var body: some View {
        SectionBlock(title: "启动设置", detail: "登录 Mac 后自动运行常用工具", minimumHeight: minimumHeight) {
            HStack {
                Toggle("开机自启动", isOn: Binding(get: { controller.state.isRegistered },
                                               set: { controller.setEnabled($0) }))
                    .toggleStyle(.switch).disabled(controller.isUpdating)
                    .accessibilityHint("登录 Mac 后在菜单栏运行 iTools，不弹出主窗口")
                Spacer()
                Text(status).font(.system(size: 12))
                    .foregroundColor(controller.state == .requiresApproval ? .orange : .secondary)
            }
            Text("开启后，登录 Mac 时在菜单栏运行 iTools，不弹出主窗口。退出 iTools 后，下次登录仍会自动启动；关闭此开关可取消。")
                .font(.system(size: 12)).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            if controller.state == .requiresApproval {
                Text("请在系统设置的「登录项」中允许 iTools 在后台运行，返回后会自动刷新状态。")
                    .font(.system(size: 12)).foregroundColor(.orange)
            }
            if let error = controller.errorMessage {
                Text(error).font(.system(size: 12)).foregroundColor(.red).textSelection(.enabled)
            }
            HStack {
                if #available(macOS 13.0, *) {
                    Button { SystemLoginItem.openSettings() } label: { Text("管理系统登录项…").foregroundColor(.primary) }
                } else {
                    Text("macOS 12 的自启动项目由此开关管理").font(.system(size: 11)).foregroundColor(.secondary)
                }
                Button { controller.refresh() } label: { Text("刷新状态").foregroundColor(.primary) }.disabled(controller.isUpdating)
            }
        }
        .onAppear { controller.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in controller.refresh() }
    }
}
