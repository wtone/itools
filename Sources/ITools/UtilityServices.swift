import AppKit
import SwiftUI
import IOKit.pwr_mgt
import IToolsCore

final class WindowService {
    private var history: [(AXUIElement, CGRect)] = []
    private func check(_ result: AXError, fallback: String) throws {
        guard result != .success else { return }
        if result == .apiDisabled {
            PermissionCenter.shared.show(.accessibility, operation: "窗口布局")
            throw WindowPermissionPending()
        }
        if result == .cannotComplete { throw UserFacingError("目标应用暂时没有响应窗口控制。请关闭它的对话框、点选目标窗口后再试。") }
        throw UserFacingError(fallback + "（系统代码 \(result.rawValue)）")
    }
    private struct WindowPermissionPending: Error {}
    private func current() throws -> AXUIElement {
        guard let app = AppFocus.shared.captureFrontmost(), !app.isTerminated, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { throw UserFacingError("请先选中要调整的应用窗口，再从菜单栏或快捷键操作。") }
        let appElement = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appElement, 1)
        var value: CFTypeRef?
        var result = AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &value)
        if result == .noValue || result == .attributeUnsupported {
            result = AXUIElementCopyAttributeValue(appElement, kAXMainWindowAttribute as CFString, &value)
        }
        try check(result, fallback: "当前应用没有可调整的窗口")
        guard let value = value, CFGetTypeID(value) == AXUIElementGetTypeID() else { throw UserFacingError("请先在目标应用中打开一个窗口。") }
        let window = unsafeBitCast(value, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(window, 1)
        var fullScreen: CFTypeRef?
        if AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullScreen) == .success, (fullScreen as? Bool) == true {
            throw UserFacingError("目标窗口处于系统全屏模式。请先退出全屏，再使用窗口布局。")
        }
        return window
    }
    private func frame(_ window: AXUIElement) throws -> CGRect {
        var p: CFTypeRef?; var s: CFTypeRef?
        try check(AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString, &p), fallback: "无法读取窗口位置")
        try check(AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &s), fallback: "无法读取窗口尺寸")
        guard let p = p, let s = s, CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { throw UserFacingError("窗口不支持标准尺寸属性。") }
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
        let finalSize = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, dimensions)
        try check(p, fallback: "该窗口不支持调整位置")
        try check(finalSize == .success ? finalSize : s, fallback: "该窗口不支持调整尺寸，可能有固定大小限制")
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
    }
    func apply(_ layout: WindowLayout) {
        guard Permissions.requireAccessibility() else { return }
        do {
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
        } catch is WindowPermissionPending {} catch { NoticeCenter.shared.report(error) }
    }
    func restore() {
        guard let last = history.last else { NoticeCenter.shared.success("还没有可还原的窗口布局"); return }
        guard Permissions.requireAccessibility() else { return }
        do { try set(last.0, frame: last.1); history.removeLast() }
        catch is WindowPermissionPending {} catch { NoticeCenter.shared.report(error) }
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
