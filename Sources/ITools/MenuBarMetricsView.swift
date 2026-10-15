import AppKit
import IToolsCore

/// Hit regions inside one native status item. Internal dragging is consumed
/// before AppKit can start a native status-item drag amongst other applications.
final class MenuBarMetricsView: NSView {
    struct Column {
        let metric: MenuBarMetric?
        let x: CGFloat
        let width: CGFloat
        let tooltip: String
    }
    private struct Press {
        let metric: MenuBarMetric?
        let origin: NSPoint
        var dragging: Bool
        var target: MenuBarMetric?
    }
    var move: ((MenuBarMetric, MenuBarMetric) -> Void)?
    var click: ((Bool) -> Void)?
    private(set) var columns: [Column] = []
    private var press: Press?
    private var eventMonitor: Any?
    private weak var button: NSStatusBarButton?
    private var tracking: NSTrackingArea?
    var visibleMetrics: [MenuBarMetric] { columns.compactMap(\.metric) }
    init(button: NSStatusBarButton) {
        self.button = button
        super.init(frame: button.bounds)
        autoresizingMask = [.width, .height]
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .rightMouseUp]) { [weak self] event in
            guard let self, let window = self.button?.window, event.window === window else { return event }
            let point = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(point) || self.press != nil else { return event }
            self.handle(event)
            return nil
        }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(_ columns: [Column]) {
        self.columns = columns
        frame = button?.bounds ?? frame
        removeAllToolTips()
        for column in columns { addToolTip(rect(for: column), owner: column.tooltip as NSString, userData: nil) }
        needsDisplay = true
    }
    private func rect(for column: Column) -> NSRect {
        let origin = button?.cell?.imageRect(forBounds: button?.bounds ?? bounds).minX ?? 0
        return NSRect(x: origin + column.x, y: 0, width: column.width, height: bounds.height)
    }
    private func column(at point: NSPoint) -> Column? { columns.first { rect(for: $0).contains(point) } }
    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
        super.updateTrackingAreas()
    }
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if visibleMetrics.count > 1, column(at: point)?.metric != nil { NSCursor.openHand.set() }
        else { NSCursor.arrow.set() }
    }
    override func mouseExited(with event: NSEvent) { if press == nil { NSCursor.arrow.set() } }
    // Called by the local monitor for real input, and by the own-window smoke
    // fixture. No global input hook or additional accessibility permission.
    func handle(_ event: NSEvent, showCursor: Bool = true) {
        let point = convert(event.locationInWindow, from: nil)
        switch event.type {
        case .rightMouseDown:
            press = nil; needsDisplay = true
        case .leftMouseDown:
            guard let column = column(at: point) else { press = nil; return }
            press = Press(metric: column.metric, origin: point, dragging: false, target: column.metric)
        case .leftMouseDragged:
            guard var state = press, let metric = state.metric, visibleMetrics.count > 1 else { return }
            if hypot(point.x - state.origin.x, point.y - state.origin.y) >= 3 { state.dragging = true }
            if state.dragging {
                if showCursor { NSCursor.closedHand.set() }
                state.target = columns.filter { $0.metric != nil }.min { abs(rect(for: $0).midX - point.x) < abs(rect(for: $1).midX - point.x) }?.metric ?? metric
            }
            press = state; needsDisplay = true
        case .leftMouseUp:
            let state = press; press = nil; needsDisplay = true; if showCursor { NSCursor.arrow.set() }
            if let state, state.dragging, let metric = state.metric, let target = state.target { move?(metric, target) }
            else if state != nil, column(at: point) != nil { click?(event.modifierFlags.contains(.control)) }
        case .rightMouseUp:
            press = nil; needsDisplay = true
            if column(at: point) != nil { click?(true) }
        default: break
        }
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let state = press, state.dragging, let metric = state.metric, let target = state.target,
              let source = columns.first(where: { $0.metric == metric }), let destination = columns.first(where: { $0.metric == target }) else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.18).setFill()
        NSBezierPath(roundedRect: rect(for: source).insetBy(dx: 0, dy: 2), xRadius: 3, yRadius: 3).fill()
        let targetRect = rect(for: destination)
        let lineX = source.x < destination.x ? targetRect.maxX : targetRect.minX
        NSColor.controlAccentColor.setStroke()
        let path = NSBezierPath(); path.lineWidth = 2
        path.move(to: NSPoint(x: lineX, y: 3)); path.line(to: NSPoint(x: lineX, y: bounds.height - 3)); path.stroke()
    }
    func stop() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }; eventMonitor = nil
        press = nil; removeFromSuperview()
    }
    deinit { if let eventMonitor { NSEvent.removeMonitor(eventMonitor) } }
}
