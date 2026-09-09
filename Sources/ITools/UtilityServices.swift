import AppKit
import SwiftUI
import IOKit.pwr_mgt
import IToolsCore

final class WindowService {
    private var history: [(AXUIElement, CGRect)] = []
    private func current() throws -> AXUIElement {
        guard let app = AppFocus.shared.previous, !app.isTerminated, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { throw UserFacingError("请先选中要调整的应用窗口，再从菜单栏或快捷键操作。") }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value = value, CFGetTypeID(value) == AXUIElementGetTypeID() else { throw UserFacingError("当前应用没有可调整的窗口。") }
        return unsafeBitCast(value, to: AXUIElement.self)
    }
    private func frame(_ window: AXUIElement) throws -> CGRect {
        var p: CFTypeRef?; var s: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &s) == .success,
              let p = p, let s = s, CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { throw UserFacingError("无法读取窗口位置。") }
        var point = CGPoint.zero; var size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(p, to: AXValue.self), .cgPoint, &point), AXValueGetValue(unsafeBitCast(s, to: AXValue.self), .cgSize, &size) else { throw UserFacingError("窗口不支持标准尺寸属性。") }
        return CGRect(origin: point, size: size)
    }
    private func set(_ window: AXUIElement, frame: CGRect) throws {
        var point = frame.origin; var size = frame.size
        guard let position = AXValueCreate(.cgPoint, &point), let dimensions = AXValueCreate(.cgSize, &size) else { return }
        // Size first permits moving a previously maximized window to a smaller display.
        let s = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions)
        let p = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        _ = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions)
        guard p == .success, s == .success else { throw UserFacingError("该窗口拒绝调整，可能有固定尺寸、全屏或辅助功能限制。") }
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }
    func apply(_ layout: WindowLayout) {
        guard Permissions.requireAccessibility() else { return }
        NoticeCenter.shared.perform {
            let window = try current(), old = try frame(window)
            let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
            let screen = NSScreen.screens.max { a, b in
                func area(_ screen: NSScreen) -> CGFloat {
                    let f = screen.frame
                    let intersection = CGRect(x: f.minX, y: primaryHeight-f.maxY, width: f.width, height: f.height).intersection(old)
                    return intersection.isNull ? 0 : intersection.width * intersection.height
                }
                return area(a) < area(b)
            }
            guard let screen = screen else { return }
            let f = screen.visibleFrame
            let usable = CGRect(x: f.minX, y: primaryHeight-f.maxY, width: f.width, height: f.height)
            try set(window, frame: layout.frame(in: usable)); history.append((window, old)); history = Array(history.suffix(20))
            NoticeCenter.shared.success("窗口已调整为" + layout.title)
        }
    }
    func restore() {
        guard Permissions.requireAccessibility(), let last = history.last else { return }
        NoticeCenter.shared.perform { try set(last.0, frame: last.1); history.removeLast() }
    }
}
final class AwakeService: ObservableObject {
    @Published var active = false
    @Published var until: Date?
    @Published private(set) var keepsDisplay = false
    private var assertion: IOPMAssertionID = 0
    private var displayAssertion: IOPMAssertionID = 0
    private var timer: Timer?
    func start(minutes: Int, keepDisplay: Bool) {
        stop()
        let type = kIOPMAssertionTypePreventUserIdleSystemSleep
        let code = IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "iTools 用户启动的防休眠会话" as CFString, &assertion)
        guard code == kIOReturnSuccess else { NoticeCenter.shared.report(UserFacingError("无法启动防休眠，系统返回 \(code)。")); return }
        if keepDisplay {
            let displayCode = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn), "iTools 保持亮屏" as CFString, &displayAssertion)
            guard displayCode == kIOReturnSuccess else { stop(); NoticeCenter.shared.report(UserFacingError("无法保持亮屏，系统返回 \(displayCode)。")); return }
        }
        keepsDisplay = keepDisplay
        active = true; until = minutes > 0 ? Date().addingTimeInterval(Double(minutes)*60) : nil
        if minutes > 0 {
            let expiry = Timer(timeInterval: Double(minutes)*60, repeats: false) { [weak self] _ in self?.stop() }
            timer = expiry; RunLoop.main.add(expiry, forMode: .common)
        }
    }
    func stop() { timer?.invalidate(); timer = nil; if assertion != 0 { IOPMAssertionRelease(assertion); assertion = 0 }; if displayAssertion != 0 { IOPMAssertionRelease(displayAssertion); displayAssertion = 0 }; active = false; until = nil; keepsDisplay = false }
    deinit { if assertion != 0 { IOPMAssertionRelease(assertion) }; if displayAssertion != 0 { IOPMAssertionRelease(displayAssertion) } }
}
struct Companion: Identifiable {
    let id: String; let name: String; let detail: String; let website: String; let candidates: [String]
}
final class CompanionRegistry: ObservableObject {
    let apps: [Companion] = [
        .init(id: "ishot", name: "iShot", detail: "完整截图、滚动长截图、带壳截图、翻译与视频工具", website: "https://www.better365.cn/ishot.html", candidates: ["iShot", "iShot Pro"]),
        .init(id: "irightmouse", name: "iRightMouse", detail: "完整超级右键菜单、文件模板与原版扩展", website: "https://www.aodo365.com/irightmouse.html", candidates: ["iRightMouse", "iRightMouse Pro", "超级右键", "超级右键专业版"]),
        .init(id: "icopy", name: "iCopy", detail: "原版剪贴板、快捷回复、同步与自定义面板", website: "https://www.aodo365.com/icopy.html", candidates: ["iCopy"]),
        .init(id: "state", name: "State", detail: "原版硬件监控、菜单栏组件与移动端关联", website: "https://www.better365.cn/state.html", candidates: ["State"])
    ]
    @Published var locations: [String: URL] = [:]
    init() { refresh() }
    func refresh() {
        for app in apps {
            if let path = UserDefaults.standard.string(forKey: "companion." + app.id), FileManager.default.fileExists(atPath: path) {
                locations[app.id] = URL(fileURLWithPath: path); continue
            }
            locations.removeValue(forKey: app.id)
            let roots = [URL(fileURLWithPath: "/Applications"), FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")]
            let matches = roots.flatMap { root in app.candidates.map { root.appendingPathComponent($0 + ".app") } }
            if let location = matches.first(where: { FileManager.default.fileExists(atPath: $0.path) }) { locations[app.id] = location }
        }
    }
    func connect(_ app: Companion) {
        guard let url = Panels.chooseFiles(types: ["app"], multiple: false).first else { return }
        guard let bundle = Bundle(url: url), bundle.executableURL != nil else { NoticeCenter.shared.report(UserFacingError("所选文件不是有效的 macOS 应用。")); return }
        UserDefaults.standard.set(url.path, forKey: "companion." + app.id); locations[app.id] = url
    }
    func open(_ app: Companion, files: [URL] = []) {
        guard let url = locations[app.id] else { connect(app); return }
        let completion: (NSRunningApplication?, Error?) -> Void = { _, error in if let error = error { NoticeCenter.shared.report(error) } }
        if files.isEmpty { NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: completion) }
        else { NSWorkspace.shared.open(files, withApplicationAt: url, configuration: .init(), completionHandler: completion) }
    }
}
