import AppKit
import SwiftUI
import AVFoundation
import ApplicationServices

// Check the current process each time; a switch for an older binary is not proof of access.
enum PermissionKind: String, Identifiable {
    case accessibility, screen, microphone, automation
    var id: String { rawValue }
    var title: String {
        switch self { case .accessibility: return "辅助功能"; case .screen: return "屏幕录制"
        case .microphone: return "麦克风"; case .automation: return "自动化" }
    }
    var pane: String {
        switch self { case .accessibility: return "Privacy_Accessibility"; case .screen: return "Privacy_ScreenCapture"
        case .microphone: return "Privacy_Microphone"; case .automation: return "Privacy_Automation" }
    }
}
private final class PermissionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
final class PermissionCenter: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = PermissionCenter()
    @Published private(set) var accessibility = false
    @Published private(set) var eventPosting = false
    @Published private(set) var screen = false
    @Published private(set) var microphone = AVAuthorizationStatus.notDetermined
    @Published private(set) var kind = PermissionKind.accessibility
    @Published private(set) var operation = ""
    @Published private(set) var feedback = ""
    private(set) var visitingSettings = false
    private var panel: NSPanel?
    private var observer: NSObjectProtocol?
    private var timer: Timer?
    var preparePresentation: (() -> Void)?
    var relaunch: (() -> Void)?
    // Replaced only by the own-window smoke check; it never asks the OS for access.
    var readStatus: () -> (Bool, Bool, Bool, AVAuthorizationStatus) = {
        (AXIsProcessTrusted(), CGPreflightPostEventAccess(), CGPreflightScreenCaptureAccess(), AVCaptureDevice.authorizationStatus(for: .audio))
    }
    override init() {
        super.init()
        refresh()
        observer = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }; self.refresh(); self.visitingSettings = false
            if self.panel?.isVisible == true { self.panel?.makeKeyAndOrderFront(nil) }
        }
    }
    func refresh() {
        let status = readStatus()
        accessibility = status.0; eventPosting = status.1; screen = status.2; microphone = status.3
    }
    var allowed: Bool {
        switch kind { case .accessibility: return accessibility && (!["直接粘贴", "锁屏", "显示/不显示隐藏文件"].contains(operation) || eventPosting)
        case .screen: return screen; case .microphone: return microphone == .authorized; case .automation: return false }
    }
    func show(_ kind: PermissionKind, operation: String = "") {
        self.kind = kind; self.operation = operation; feedback = ""; refresh()
        preparePresentation?()
        if panel == nil {
            let window = PermissionPanel(contentRect: NSRect(x: 0, y: 0, width: 560, height: 460), styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "iTools · 权限与运行状态"; window.isReleasedWhenClosed = false
            window.isOpaque = false; window.backgroundColor = .clear
            window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true; window.titlebarSeparatorStyle = .none
            window.level = .modalPanel; window.hidesOnDeactivate = true
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.delegate = self
            window.contentView = NSHostingView(rootView: PermissionHelpView(center: self))
            panel = window
        }
        if panel?.isVisible != true { panel?.center() }
        NSApp.activate(ignoringOtherApps: true); panel?.makeKeyAndOrderFront(nil)
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.refresh() }
    }
    func close() { panel?.orderOut(nil); timer?.invalidate(); timer = nil }
    func report(_ message: String) { feedback = message; panel?.makeKeyAndOrderFront(nil) }
    func windowWillClose(_ notification: Notification) { timer?.invalidate(); timer = nil }
    func openSettings(_ kind: PermissionKind) {
        visitingSettings = true; feedback = ""; preparePresentation?(); panel?.orderOut(nil)
        timer?.invalidate(); timer = nil
        // Do not combine an asynchronous AX system prompt with our own alert.
        // Accessibility can be enabled by selecting this app with the system's + button.
        if kind == .screen && !screen { _ = CGRequestScreenCaptureAccess(); refresh() }
        if kind == .microphone && microphone == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in DispatchQueue.main.async { self?.refresh() } }
            return
        }
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + kind.pane)!
        if !NSWorkspace.shared.open(url) {
            feedback = "未能打开系统设置。请手动进入「隐私与安全性 → \(kind.title)」。"
            NSApp.activate(ignoringOtherApps: true); panel?.makeKeyAndOrderFront(nil)
        }
    }
    func revealApplication() {
        visitingSettings = true; panel?.orderOut(nil); timer?.invalidate(); timer = nil
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }
    var windowForChecks: NSWindow? { panel }
    deinit { timer?.invalidate(); if let observer = observer { NotificationCenter.default.removeObserver(observer) } }
}
private struct PermissionHelpView: View {
    @ObservedObject var center: PermissionCenter
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(center.kind.title + (center.kind == .automation ? "授权说明" : center.allowed ? "已生效" : "需要授权"), systemImage: center.allowed ? "checkmark.shield.fill" : "hand.raised.fill")
                .font(.system(size: 23, weight: .semibold)).foregroundColor(center.allowed ? .green : accent)
            Text(center.operation.isEmpty ? "管理当前运行的 iTools 所需权限。" : "「\(center.operation)」需要这项权限。")
            Text(center.allowed ? "当前运行的 iTools 已通过系统检测。请回到目标应用，再主动执行刚才的操作。" : instructions)
                .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            if center.kind == .accessibility {
                Text("窗口控制：\(center.accessibility ? "已授权" : "未生效") · 模拟键盘输入：\(center.eventPosting ? "已授权" : "未生效")")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("当前应用 · v" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"))
                Text(Bundle.main.bundleURL.path).textSelection(.enabled).font(.system(size: 11, design: .monospaced)).lineLimit(2)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.primary.opacity(0.04)).cornerRadius(10)
            if !center.feedback.isEmpty { Text(center.feedback).font(.system(size: 12)).foregroundColor(.red) }
            HStack {
                Button("在访达中显示此应用") { center.revealApplication() }
                Button("重新检测") { center.refresh() }
                if center.relaunch != nil { Button("重新打开 iTools") { center.relaunch?() } }
            }
            Spacer(minLength: 0)
            HStack {
                Text("权限只由你在 macOS 中授予。不会自动重试粘贴或录制。")
                    .font(.system(size: 11)).foregroundColor(.secondary)
                Spacer()
                Button("关闭") { center.close() }
                Button("打开系统设置") { center.openSettings(center.kind) }.keyboardShortcut(.defaultAction)
            }
        }.padding(24).frame(width: 560, height: 460)
            .background(FrostedBackground()).buttonStyle(ToolButtonStyle())
    }
    private var instructions: String {
        switch center.kind {
        case .accessibility:
            return "在系统设置中允许 iTools。若开关已开启却仍未生效，请移除旧的 iTools 条目，点击「＋」重新添加下方路径的应用并开启，再重新打开 iTools。旧版临时签名或不同安装位置的授权可能不适用于当前版本。"
        case .screen:
            return "允许当前 iTools 录制屏幕。macOS 可能要求退出并重新打开应用才能生效；若已开启仍不可用，请检查是否授权了下方路径中的应用。"
        case .microphone:
            return "允许 iTools 使用麦克风；只录制画面时也可以关闭录制选项中的音频输入。若系统限制修改，请联系此 Mac 的管理员。"
        case .automation:
            return "在「自动化 → iTools」下允许本次操作涉及的 System Events 或 Finder。此权限由首次执行对应系统操作时申请，与「辅助功能」分别管理。"
        }
    }
}

enum Permissions {
    static var screen: Bool { PermissionCenter.shared.refresh(); return PermissionCenter.shared.screen }
    static var accessibility: Bool { PermissionCenter.shared.refresh(); return PermissionCenter.shared.accessibility }
    static func requireScreen() -> Bool {
        if screen { return true }; PermissionCenter.shared.show(.screen, operation: "截图与录制"); return false
    }
    static func requireAccessibility(operation: String = "窗口控制") -> Bool {
        if accessibility { return true }; PermissionCenter.shared.show(.accessibility, operation: operation); return false
    }
    static func requireEventPosting(operation: String = "直接粘贴") -> Bool {
        let center = PermissionCenter.shared; center.refresh()
        if center.accessibility && center.eventPosting { return true }
        center.show(.accessibility, operation: operation); return false
    }
    static func open(_ pane: String) {
        guard let kind = [PermissionKind.accessibility, .screen, .microphone, .automation].first(where: { $0.pane == pane }) else { return }
        PermissionCenter.shared.show(kind)
    }
}
