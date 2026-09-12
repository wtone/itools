import AppKit
import IToolsCore

enum WindowGlassChecks {
    /// Inspect and render our complete window, including the system-owned titlebar controls.
    static func verifyAndExport(_ window: NSWindow, destination: URL, name: String) throws {
        guard window.styleMask.contains(.fullSizeContentView), window.titlebarAppearsTransparent,
              window.titleVisibility == .hidden, window.titlebarSeparatorStyle == .none,
              !window.isOpaque, window.backgroundColor.alphaComponent == 0,
              let content = window.contentView, let frame = content.superview else {
            throw UserFacingError("Smoke: unified glass window chrome is not configured")
        }
        content.layoutSubtreeIfNeeded(); frame.layoutSubtreeIfNeeded()
        guard abs(content.bounds.height - frame.bounds.height) < 1 else {
            throw UserFacingError("Smoke: content does not extend through the titlebar")
        }
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            guard let button = window.standardWindowButton(type), !button.isHidden,
                  let parent = button.superview else { throw UserFacingError("Smoke: native window control missing") }
            let rect = parent.convert(button.frame, to: content)
            guard content.bounds.contains(rect), rect.minX < 218 else {
                throw UserFacingError("Smoke: window control is outside the sidebar glass")
            }
            let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: frame)
            guard let hit = frame.hitTest(point), hit === button || hit.isDescendant(of: button) else {
                throw UserFacingError("Smoke: glass drag strip intercepts a native window control")
            }
        }
        let effects = descendants(content).compactMap { $0 as? NSVisualEffectView }
            .filter { $0.identifier?.rawValue == "itools.window-glass" }
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            guard effects.contains(where: { $0.blendingMode == .behindWindow && $0.material == .hudWindow && $0.state == .active }) else {
                throw UserFacingError("Smoke: native behind-window frosted material missing")
            }
        }
        let scrolls = descendants(content).compactMap { $0 as? NSScrollView }
        guard scrolls.contains(where: { scroll in
            (scroll.verticalScroller as? GlassScroller)?.softIndicators == true &&
                !scroll.drawsBackground && !scroll.contentView.drawsBackground
        }) else { throw UserFacingError("Smoke: main window soft glass scrollbar missing") }
        frame.displayIfNeeded()
        guard let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { throw UserFacingError("Smoke: full-window bitmap unavailable") }
        frame.cacheDisplay(in: frame.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { throw UserFacingError("Smoke: full-window export failed") }
        try png.write(to: destination.appendingPathComponent(name + ".png"))
        print("PASS: \(name): full-size transparent titlebar, native traffic-light hit targets, behind-window glass, soft transparent scrollbar; complete frame exported")
    }
    private static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }

}
