import AppKit
import SwiftUI

/// A SwiftUI scroll view whose native scroller track lets the surrounding surface show through.
struct GlassScrollView<Content: View>: View {
    private let axes: Axis.Set
    private let showsIndicators: Bool
    private let softIndicators: Bool
    private let horizontalWheel: Bool
    private let content: Content

    init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, softIndicators: Bool = false, horizontalWheel: Bool = false, @ViewBuilder content: () -> Content) {
        self.axes = axes; self.showsIndicators = showsIndicators; self.softIndicators = softIndicators
        self.horizontalWheel = horizontalWheel && axes == .horizontal; self.content = content()
    }

    var body: some View {
        ScrollView(axes, showsIndicators: showsIndicators) {
            content.background(GlassScrollConfiguration(softIndicators: softIndicators, horizontalWheel: horizontalWheel))
        }
    }
}

/// AppKit retains tracking and fading. The optional soft knob changes drawing, never its hit area.
final class GlassScroller: NSScroller {
    var softIndicators = false { didSet { if softIndicators != oldValue { needsDisplay = true } } }
    override class var isCompatibleWithOverlayScrollers: Bool { true }
    override var isOpaque: Bool { false }
    override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}
    override func drawKnob() {
        guard softIndicators else { super.drawKnob(); return }
        var rect = rect(for: .knob)
        guard rect.width > 0, rect.height > 0, knobProportion < 1 else { return }
        if bounds.height > bounds.width { rect = rect.insetBy(dx: max(0, (rect.width - 5) / 2), dy: 0) }
        else { rect = rect.insetBy(dx: 0, dy: max(0, (rect.height - 5) / 2)) }
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let alpha: CGFloat = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast ? 0.65 : (dark ? 0.32 : 0.20)
        NSColor(calibratedWhite: dark ? 1 : 0.32, alpha: alpha).setFill()
        let shape = NSBezierPath(roundedRect: rect, xRadius: 2.5, yRadius: 2.5)
        shape.fill()
        NSColor.white.withAlphaComponent(dark ? 0.15 : 0.35).setStroke()
        shape.lineWidth = 0.5; shape.stroke()
    }
}

private struct GlassScrollConfiguration: NSViewRepresentable {
    let softIndicators: Bool
    let horizontalWheel: Bool
    func makeNSView(context: Context) -> Marker { Marker() }
    func updateNSView(_ view: Marker, context: Context) {
        view.softIndicators = softIndicators; view.horizontalWheel = horizontalWheel; view.configureWhenAttached()
    }

    final class Marker: NSView {
        var softIndicators = false
        var horizontalWheel = false
        private var wheelMonitor: Any?
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); configureWhenAttached() }
        override func viewDidMoveToSuperview() { super.viewDidMoveToSuperview(); configureWhenAttached() }
        override func layout() { super.layout(); configure() }

        func configureWhenAttached() {
            configure()
            // SwiftUI may insert this content marker before it attaches the enclosing scroll view.
            DispatchQueue.main.async { [weak self] in self?.configure() }
        }
        private func configure() {
            if !horizontalWheel || window == nil {
                if let monitor = wheelMonitor { NSEvent.removeMonitor(monitor); wheelMonitor = nil }
            } else if wheelMonitor == nil {
                wheelMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                    guard let self = self, self.horizontalWheel, let scroll = self.enclosingScrollView,
                          let window = scroll.window, window.isVisible, event.window === window,
                          !scroll.isHiddenOrHasHiddenAncestor,
                          scroll.visibleRect.contains(scroll.convert(event.locationInWindow, from: nil)),
                          HorizontalScrollWheel.scroll(event, in: scroll) else { return event }
                    return nil
                }
            }
            guard let scroll = enclosingScrollView else { return }
            if scroll.drawsBackground { scroll.drawsBackground = false }
            if scroll.contentView.drawsBackground { scroll.contentView.drawsBackground = false }
            if let original = scroll.verticalScroller, !(original is GlassScroller) {
                scroll.verticalScroller = replacement(for: original)
            }
            if let original = scroll.horizontalScroller, !(original is GlassScroller) {
                scroll.horizontalScroller = replacement(for: original)
            }
            (scroll.verticalScroller as? GlassScroller)?.softIndicators = softIndicators
            (scroll.horizontalScroller as? GlassScroller)?.softIndicators = softIndicators
        }
        private func replacement(for original: NSScroller) -> GlassScroller {
            let scroller = GlassScroller(frame: original.frame)
            scroller.controlSize = original.controlSize; scroller.scrollerStyle = original.scrollerStyle
            scroller.knobStyle = original.knobStyle; scroller.knobProportion = original.knobProportion
            scroller.doubleValue = original.doubleValue; scroller.isEnabled = original.isEnabled
            scroller.target = original.target; scroller.action = original.action
            return scroller
        }
        deinit { if let monitor = wheelMonitor { NSEvent.removeMonitor(monitor) } }
    }
}

enum HorizontalScrollWheel {
    /// Native event deltas already include the user's direction and acceleration preferences.
    @discardableResult static func scroll(_ event: NSEvent, in scroll: NSScrollView) -> Bool {
        guard event.type == .scrollWheel, !event.modifierFlags.contains(.shift),
              abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) else { return false }
        let clip = scroll.contentView
        var bounds = clip.bounds
        let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : scroll.horizontalLineScroll
        bounds.origin.x -= event.scrollingDeltaY * scale
        clip.scroll(to: clip.constrainBoundsRect(bounds).origin)
        scroll.reflectScrolledClipView(clip)
        scroll.flashScrollers()
        return true
    }
}
