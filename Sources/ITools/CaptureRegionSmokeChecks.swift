import AppKit
import IToolsCore

enum CaptureRegionSmokeChecks {
    /// Production views and windows with synthetic geometry. Never show a window or capture the desktop.
    static func run(destination: URL) throws {
        let displays = [
            CaptureDisplayGeometry(id: 11, frame: CGRect(x: 0, y: 0, width: 800, height: 600), scale: 2),
            CaptureDisplayGeometry(id: 22, frame: CGRect(x: -900, y: 80, width: 900, height: 700), scale: 1),
            CaptureDisplayGeometry(id: 33, frame: CGRect(x: 50, y: 600, width: 800, height: 600), scale: 2)
        ]
        let selection = CGRect(x: -800, y: 180, width: 600, height: 400)
        var selectedID: UInt32?
        let selectors = RegionSelector.makeWindows(displays: displays, prompt: "Synthetic selection") { display, _ in selectedID = display.id }
        defer { selectors.forEach { $0.close() } }
        guard selectors.count == 3 else { throw UserFacingError("Smoke: selection is confined to the application's display") }
        for (index, window) in selectors.enumerated() {
            guard window.frame == displays[index].frame, !window.isVisible, window.canBecomeKey,
                  window.collectionBehavior.contains(.canJoinAllSpaces), window.contentView is RegionView else {
                throw UserFacingError("Smoke: selection window loses extended-display geometry")
            }
            (window.contentView as! RegionView).complete?(CGRect(x: 10, y: 20, width: 200, height: 180))
            guard selectedID == displays[index].id else { throw UserFacingError("Smoke: selected display callback points at original display") }
        }
        print("PASS: selector creates a focusable window on every display and callbacks identify the actual chosen display")
        let overlay = CaptureRegionOverlay(displays: displays, selectedDisplayID: 22, selection: selection)
        defer { overlay.close() }
        guard overlay.windows.count == 3, overlay.captureAnchor === overlay.windows[1] else {
            throw UserFacingError("Smoke: multi-display overlay or selected capture anchor missing")
        }
        for (index, window) in overlay.windows.enumerated() {
            guard window.frame == displays[index].frame, window.ignoresMouseEvents, !window.canBecomeKey,
                  !window.canBecomeMain, !window.isOpaque, !window.isVisible, !window.hasShadow,
                  window.sharingType == .none, window.level == CaptureRegionOverlay.level,
                  window.collectionBehavior.contains(.canJoinAllSpaces), window.collectionBehavior.contains(.fullScreenAuxiliary),
                  let mask = window.contentView as? CaptureRegionMaskView else {
                throw UserFacingError("Smoke: overlay steals events or loses full-display geometry")
            }
            let expected: CGRect? = index == 1 ? CGRect(x: 100, y: 100, width: 600, height: 400) : nil
            guard mask.clearRegion == expected else { throw UserFacingError("Smoke: hole appears on wrong display") }
        }
        func bitmap(_ view: NSView) throws -> NSBitmapImageRep {
            guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width), pixelsHigh: Int(view.bounds.height),
                                            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
                  let context = NSGraphicsContext(bitmapImageRep: rep) else { throw UserFacingError("Smoke: mask bitmap allocation failed") }
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
            view.draw(view.bounds); NSGraphicsContext.restoreGraphicsState()
            return rep
        }
        let selectedMask = overlay.windows[1].contentView!
        let selectedBitmap = try bitmap(selectedMask)
        guard selectedBitmap.colorAt(x: 400, y: 350)!.alphaComponent < 0.01,
              abs(selectedBitmap.colorAt(x: 20, y: 350)!.alphaComponent - 0.36) < 0.02,
              abs(selectedBitmap.colorAt(x: 400, y: 20)!.alphaComponent - 0.36) < 0.02 else {
            throw UserFacingError("Smoke: selected area is dimmed or outside area is not translucent")
        }
        let otherBitmap = try bitmap(overlay.windows[0].contentView!)
        guard abs(otherBitmap.colorAt(x: 400, y: 300)!.alphaComponent - 0.36) < 0.02 else {
            throw UserFacingError("Smoke: other display is not dimmed")
        }
        try selectedBitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent("selected-display-mask.png"))
        try otherBitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent("other-display-mask.png"))
        print("PASS: three full-display masks preserve coordinates; selected hole transparent, other regions gray/translucent; all masks pass mouse events")

        let window = SelectionWindow(contentRect: CGRect(x: -900, y: 80, width: 360, height: 240), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let view = RegionView(frame: CGRect(x: 0, y: 0, width: 360, height: 240)); window.contentView = view
        var completed: CGRect?, cancelled = false
        view.complete = { rect in if let rect = rect { completed = rect } else { cancelled = true } }
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                               context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        view.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 310, y: 190)))
        view.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 45, y: 40)))
        guard completed == nil, view.clearRegion == CGRect(x: 45, y: 40, width: 265, height: 150),
              view.acceptsFirstMouse(for: nil) else { throw UserFacingError("Smoke: external-display selection requires second click or loses reverse drag") }
        view.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: -10, y: 20)))
        guard completed == CGRect(x: 0, y: 20, width: 310, height: 170) else { throw UserFacingError("Smoke: selected rect spills into neighbouring display") }
        view.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                           windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
                                           charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!)
        guard cancelled else { throw UserFacingError("Smoke: Esc does not cancel selector") }
        print("PASS: selection view accepts first click, reverse/outside drag clips correctly, and Esc cancels")

        let windows: [ScrollingCaptureController.CaptureWindowTarget] = [
            .init(pid: 77, bounds: CGRect(x: -800, y: 120, width: 600, height: 500)),
            .init(pid: 88, bounds: CGRect(x: -900, y: 100, width: 900, height: 700)),
            .init(pid: 99, bounds: CGRect(x: 0, y: 0, width: 800, height: 600))
        ]
        guard ScrollingCaptureController.targetPID(at: CGPoint(x: -500, y: 350), windows: windows) == 77,
              ScrollingCaptureController.targetPID(at: CGPoint(x: -850, y: 400), windows: windows) == 88,
              ScrollingCaptureController.targetPID(at: CGPoint(x: 400, y: 350), windows: windows) == 99 else {
            throw UserFacingError("Smoke: scrolling targets original screen's application rather than the selected window")
        }
        overlay.close()
        guard overlay.windows.isEmpty, overlay.captureAnchor == nil else { throw UserFacingError("Smoke: overlay survives completion/cancel") }
        print("PASS: scrolling target follows selected display's topmost window; overlay teardown releases every display")
    }
}
