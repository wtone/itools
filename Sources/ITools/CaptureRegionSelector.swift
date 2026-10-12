import AppKit
import IToolsCore

extension NSScreen {
    var captureGeometry: CaptureDisplayGeometry? {
        guard let id = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return nil }
        return CaptureDisplayGeometry(id: id, frame: frame, scale: backingScaleFactor)
    }
}

final class RegionSelector {
    static let shared = RegionSelector()
    private var windows: [SelectionWindow] = []
    private var finish: ((CaptureDisplayGeometry?, CGRect?) -> Void)?
    private var sessionID: UUID?
    private var screenObserver: NSObjectProtocol?
    var isSelecting: Bool { finish != nil }

    @discardableResult
    func select(prompt: String = "在任意屏幕拖动选择录制区域 · Esc 取消", restoreWindows: Bool = true,
                cancelled: (() -> Void)? = nil, completion: @escaping (CGDirectDisplayID, CGRect) -> Void) -> UUID? {
        // Recording and scrolling capture share the selector. Never replace a live session's callbacks.
        guard finish == nil, RegionCaptureController.active == nil else { cancelled?(); return nil }
        let displays = NSScreen.screens.compactMap(\.captureGeometry)
        guard !displays.isEmpty else { cancelled?(); return nil }
        let session = UUID(); sessionID = session
        let applicationWindows = NSApp.windows.filter { $0.canBecomeKey || $0.canBecomeMain }
        let hidden = applicationWindows.filter { $0.isVisible }
        // A hidden application's windows can report invisible but reappear on activation.
        // Explicitly order out content windows before activating the all-display selector.
        applicationWindows.forEach { $0.orderOut(nil) }
        finish = { [weak self] display, rect in
            guard let self = self, self.sessionID == session else { return }
            self.finish = nil; self.sessionID = nil
            self.windows.forEach { $0.close() }; self.windows.removeAll()
            if let observer = self.screenObserver { NotificationCenter.default.removeObserver(observer) }
            self.screenObserver = nil
            if restoreWindows { hidden.forEach { $0.orderFront(nil) }; NSApp.activate(ignoringOtherApps: true) }
            guard let display = display, let rect = rect, rect.width > 4, rect.height > 4,
                  let pixels = display.localPixels(from: rect) else { cancelled?(); return }
            completion(display.id, pixels)
        }
        windows = Self.makeWindows(displays: displays, prompt: prompt) { [weak self] display, rect in self?.finish?(display, rect) }
        windows.forEach { $0.orderFrontRegardless() }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                 object: nil, queue: .main) { [weak self] _ in self?.cancel() }
        let focused = windows.first { $0.frame.contains(NSEvent.mouseLocation) } ?? windows[0]
        NSApp.activate(ignoringOtherApps: true)
        focused.makeKeyAndOrderFront(nil)
        return session
    }

    static func makeWindows(displays: [CaptureDisplayGeometry], prompt: String,
                            complete: @escaping (CaptureDisplayGeometry, CGRect?) -> Void) -> [SelectionWindow] {
        displays.map { display in
            let window = SelectionWindow(contentRect: display.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.level = .screenSaver; window.isOpaque = false; window.backgroundColor = .clear
            window.hasShadow = false; window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.sharingType = .none
            let view = RegionView(frame: CGRect(origin: .zero, size: display.frame.size))
            view.prompt = prompt
            view.complete = { rect in complete(display, rect) }
            window.contentView = view; window.makeFirstResponder(view)
            return window
        }
    }

    func cancel() { finish?(nil, nil) }
    func cancel(sessionID: UUID) { if self.sessionID == sessionID { cancel() } }
}

final class SelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// A genuinely transparent hole rather than a border drawn over a uniformly dimmed screen.
class CaptureRegionMaskView: NSView {
    var clearRegion: CGRect? { didSet { needsDisplay = true } }
    override var isOpaque: Bool { false }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); bounds.fill(using: .copy)
        let mask = NSBezierPath(rect: bounds)
        mask.windingRule = .evenOdd
        let hole = clearRegion?.intersection(bounds)
        if let hole = hole, !hole.isNull, !hole.isEmpty { mask.appendRect(hole) }
        NSColor(calibratedWhite: 0.08, alpha: 0.36).setFill(); mask.fill()
        if let hole = hole, !hole.isNull, !hole.isEmpty {
            NSColor.systemBlue.setStroke()
            let border = NSBezierPath(rect: hole.insetBy(dx: -1, dy: -1))
            border.lineWidth = 2; border.stroke()
        }
    }
}

/// Keep one click-through mask on every display for the whole scrolling session.
/// The selected display's mask is also the capture anchor: its dimming and everything
/// above it, including the HUD, are excluded from CGWindowListCreateImage.
final class CaptureRegionOverlay {
    private(set) var windows: [NSWindow] = []
    private(set) var captureAnchor: NSWindow?
    static let level = NSWindow.Level.screenSaver

    init(displays: [CaptureDisplayGeometry], selectedDisplayID: UInt32, selection: CGRect) {
        for display in displays {
            let window = CaptureMaskWindow(contentRect: display.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.level = Self.level; window.isOpaque = false; window.backgroundColor = .clear
            window.hasShadow = false; window.ignoresMouseEvents = true; window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; window.sharingType = .none
            let view = CaptureRegionMaskView(frame: CGRect(origin: .zero, size: display.frame.size))
            if display.id == selectedDisplayID { view.clearRegion = display.localPoints(fromGlobal: selection); captureAnchor = window }
            window.contentView = view; windows.append(window)
        }
    }
    func show() {
        windows.forEach { $0.orderFrontRegardless() }
        captureAnchor?.orderFrontRegardless()
    }
    func close() { windows.forEach { $0.close() }; windows.removeAll(); captureAnchor = nil }
    deinit { close() }
}

private final class CaptureMaskWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

final class RegionView: CaptureRegionMaskView {
    var complete: ((CGRect?) -> Void)?
    var prompt = "在任意屏幕拖动选择区域 · Esc 取消"
    private var start: CGPoint?
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let attributes: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.white,
            .font: NSFont.systemFont(ofSize: 16, weight: .medium)]
        let size = (prompt as NSString).size(withAttributes: attributes)
        let pill = CGRect(x: max(12, (bounds.width - size.width - 32) / 2), y: bounds.height - 70,
                          width: min(size.width + 32, bounds.width - 24), height: 42)
        NSColor.black.withAlphaComponent(0.45).setFill()
        NSBezierPath(roundedRect: pill, xRadius: 12, yRadius: 12).fill()
        (prompt as NSString).draw(in: pill.insetBy(dx: 16, dy: 11), withAttributes: attributes)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey(); window?.makeFirstResponder(self)
        start = convert(event.locationInWindow, from: nil); updateSelection(event)
    }
    override func mouseDragged(with event: NSEvent) { updateSelection(event) }
    override func mouseUp(with event: NSEvent) { updateSelection(event); complete?(clearRegion) }
    private func updateSelection(_ event: NSEvent) {
        guard let a = start else { return }
        let b = convert(event.locationInWindow, from: nil)
        let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)).intersection(bounds)
        clearRegion = rect.isNull ? nil : rect
    }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { complete?(nil) } }
}
