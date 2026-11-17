import AppKit
import IToolsCore

enum RegionCaptureSmokeChecks {
    static func syntheticImage(width: Int, height: Int) throws -> CGImage {
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { throw UserFacingError("Smoke: region fixture allocation failed") }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        NSColor(calibratedWhite: 0.94, alpha: 1).setFill(); CGRect(x: 0, y: 0, width: width, height: height).fill()
        NSColor(calibratedWhite: 0.98, alpha: 1).setFill()
        NSBezierPath(roundedRect: CGRect(x: 80, y: 80, width: width-160, height: height-160), xRadius: 20, yRadius: 20).fill()
        let title = "区域截图 · 原位编辑" as NSString
        title.draw(at: CGPoint(x: 130, y: height-170), withAttributes: [.font: NSFont.systemFont(ofSize: 40, weight: .semibold), .foregroundColor: NSColor.labelColor])
        for row in 0..<8 {
            let y = CGFloat(height-260-row*95)
            guard y > 100 else { continue }
            NSColor(calibratedWhite: row % 2 == 0 ? 0.87 : 0.91, alpha: 1).setFill()
            NSBezierPath(roundedRect: CGRect(x: 130, y: y, width: CGFloat(width-260), height: 65), xRadius: 9, yRadius: 9).fill()
            ("内容 \(row+1)   Select · Resize · Annotate" as NSString).draw(at: CGPoint(x: 150, y: y+18),
                withAttributes: [.font: NSFont.systemFont(ofSize: 24), .foregroundColor: NSColor.darkGray])
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let image = rep.cgImage else { throw UserFacingError("Smoke: region fixture encoding failed") }
        return image
    }
    static func run(destination: URL) throws {
        let displays = [
            CaptureDisplayGeometry(id: 11, frame: CGRect(x: 0, y: 0, width: 800, height: 600), scale: 2),
            CaptureDisplayGeometry(id: 22, frame: CGRect(x: -900, y: 80, width: 900, height: 700), scale: 1),
            CaptureDisplayGeometry(id: 33, frame: CGRect(x: 50, y: 600, width: 800, height: 600), scale: 2)
        ]
        let images = try displays.map { try syntheticImage(width: Int($0.frame.width*$0.scale), height: Int($0.frame.height*$0.scale)) }
        let windows = RegionCaptureController.makeWindows(displays: displays, snapshots: images)
        defer { windows.forEach { $0.close() } }
        guard windows.count == 3 else { throw UserFacingError("Smoke: region screenshot does not cover every display") }
        for (index, window) in windows.enumerated() {
            guard window.frame == displays[index].frame, !window.isVisible, window.canBecomeKey,
                  window.sharingType == .none, window.level == .screenSaver,
                  window.contentView is RegionCaptureWorkspace else { throw UserFacingError("Smoke: region workspace loses multi-display isolation") }
        }
        let window = windows[0], view = window.contentView as! RegionCaptureWorkspace
        var completed = false, cancelled = false
        view.onComplete = { completed = true }; view.onCancel = { cancelled = true }
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint, clicks: Int = 1) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                               context: nil, eventNumber: 1, clickCount: clicks, pressure: 1)!
        }
        func preview(_ name: String, appearance: NSAppearance.Name = .aqua) throws {
            window.appearance = NSAppearance(named: appearance); view.refreshSelection(); view.layoutSubtreeIfNeeded()
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw UserFacingError("Smoke: region preview allocation failed") }
            view.cacheDisplay(in: view.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name + ".png"))
        }
        let external = windows[1].contentView as! RegionCaptureWorkspace
        external.windowCandidates = [CGRect(x: 20, y: 100, width: 400, height: 240), CGRect(x: 0, y: 0, width: 800, height: 600)]
        external.windowPickMode = true
        let externalClick = NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 220, y: 220), modifierFlags: [], timestamp: 0,
                                              windowNumber: windows[1].windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        external.mouseDown(with: externalClick)
        guard external.document.captureRegion == CGRect(x: 20, y: 100, width: 400, height: 240),
              !external.windowPickMode else { throw UserFacingError("Smoke: window picking loses topmost order or extended-display coordinates") }
        external.document.undo(); external.refreshSelection(); external.isActive = false
        guard external.selection == nil else { throw UserFacingError("Smoke: window selection cannot be undone") }
        print("PASS: window mode selects the topmost frozen candidate on an external display; selection remains adjustable and undoable")
        try preview("region-before-selection")
        view.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 600, y: 450)))
        view.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 100, y: 200)))
        view.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 100, y: 200)))
        let initial = CGRect(x: 200, y: 400, width: 1000, height: 500)
        guard view.document.captureRegion == initial, !completed, view.acceptsFirstMouse(for: nil), !view.canvas.isHidden else {
            throw UserFacingError("Smoke: releasing a region finishes capture rather than allowing adjustment")
        }
        print("PASS: frozen screenshot workspaces cover three displays; reverse selection leaves mask, canvas and toolbar open without completing")
        let tab = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                   windowNumber: window.windowNumber, context: nil, characters: "\t",
                                   charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48)!
        guard view.handleModeShortcut(tab), view.mode.scrolling else { throw UserFacingError("Smoke: Tab did not switch to scrolling mode") }
        try preview("region-scroll-tab")
        let localSelection = view.selection!
        let localToolbar = RegionCaptureWorkspace.toolbarFrame(selection: localSelection, bounds: view.bounds)
        for display in displays {
            let globalSelection = localSelection.offsetBy(dx: display.frame.minX, dy: display.frame.minY)
            let globalToolbar = RegionCaptureWorkspace.toolbarFrame(selection: globalSelection, bounds: display.frame)
            guard globalToolbar == localToolbar.offsetBy(dx: display.frame.minX, dy: display.frame.minY) else {
                throw UserFacingError("Smoke: capture toolbar moved when starting on an extended display")
            }
        }
        print("PASS: scrolling controls retain the selected toolbar position across multiple displays")
        var handoff: (CGDirectDisplayID, CGRect, Bool, Bool)?
        view.onScroll = { handoff = ($0, $1, $2, $3) }
        view.mode.automatic = false; view.mode.slow = true; view.startScrolling()
        guard let handoff = handoff, handoff.0 == displays[0].id, handoff.1 == initial, !handoff.2, handoff.3,
              view.handleModeShortcut(tab), !view.mode.scrolling, view.document.captureRegion == initial else {
            throw UserFacingError("Smoke: switching modes lost selection or scrolling options")
        }
        let ocr = RegionCaptureWorkspace(display: displays[0], snapshot: images[0], allowScrolling: false)
        ocr.document.captureRegion = initial
        guard !ocr.handleModeShortcut(tab), !ocr.mode.scrolling else { throw UserFacingError("Smoke: OCR switched into scrolling mode") }
        print("PASS: Tab switches capture modes, hands off selected display and native pixels, preserves selection, and leaves OCR unchanged")


        view.canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 350, y: 320)))
        view.canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 390, y: 350)))
        view.canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 390, y: 350)))
        guard view.document.captureRegion == initial.offsetBy(dx: 80, dy: 60) else { throw UserFacingError("Smoke: empty selection cannot be dragged directly") }
        view.document.undo(); view.refreshSelection()
        guard view.document.captureRegion == initial else { throw UserFacingError("Smoke: selection move undo failed") }
        let handles: [(CGPoint, CGPoint)] = [
            (.init(x:100,y:200), .init(x:80,y:180)), (.init(x:350,y:200), .init(x:350,y:180)),
            (.init(x:600,y:200), .init(x:620,y:180)), (.init(x:600,y:325), .init(x:620,y:325)),
            (.init(x:600,y:450), .init(x:620,y:470)), (.init(x:350,y:450), .init(x:350,y:470)),
            (.init(x:100,y:450), .init(x:80,y:470)), (.init(x:100,y:325), .init(x:80,y:325))
        ]
        for (start, end) in handles {
            guard view.hitTest(start) === view else { throw UserFacingError("Smoke: annotation canvas intercepts selection resize handles") }
            view.mouseDown(with: mouse(.leftMouseDown, start)); view.mouseDragged(with: mouse(.leftMouseDragged, end))
            view.mouseUp(with: mouse(.leftMouseUp, end))
            guard let region = view.document.captureRegion, region.width > initial.width || region.height > initial.height else {
                throw UserFacingError("Smoke: one of the eight selection handles cannot resize")
            }
            view.document.undo(); view.refreshSelection()
            guard view.document.captureRegion == initial else { throw UserFacingError("Smoke: resizing selection cannot be undone") }
        }
        view.document.tool = .arrow; view.spaceToMove = true
        view.canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 350, y: 320)))
        view.canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: -400, y: -200)))
        guard view.selection!.minX == 0, view.selection!.minY == 0,
              view.selection!.width == 500, view.selection!.height == 250 else { throw UserFacingError("Smoke: moving selection spills outside its display") }
        view.spaceToMove = false; view.document.undo(); view.refreshSelection()
        print("PASS: empty-area drag, eight resize handles, Space panning and display-edge clipping preserve native pixels; each adjustment is one undoable change")

        view.document.tool = .arrow
        view.canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 220, y: 270)))
        view.canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 370, y: 340)))
        view.canvas.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 370, y: 340)))
        guard view.document.marks.count == 1, hypot(view.document.marks[0].points[0].x-440, view.document.marks[0].points[0].y-540) < 0.01 else {
            throw UserFacingError("Smoke: annotations use cropped coordinates instead of frozen-screen pixels; points=\(view.document.marks.map(\.points)) frame=\(view.canvas.frame) imageRect=\(view.canvas.imageRect) size=\(view.document.image!.size)")
        }
        view.document.tool = .text
        view.canvas.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 410, y: 400)))
        guard let editor = view.canvas.subviews.compactMap({ $0 as? InlineAnnotationTextView }).first,
              window.firstResponder === editor else { throw UserFacingError("Smoke: overlay text requires a separate modal editor") }
        editor.insertText("图片内编辑\nNative inline text", replacementRange: NSRange(location: 0, length: 0))
        window.makeFirstResponder(view.canvas)
        guard view.document.marks.count == 2, view.document.marks[1].text.hasPrefix("图片内编辑") else { throw UserFacingError("Smoke: overlay text did not commit on focus loss") }
        try preview("region-edit-light")
        try preview("region-edit-dark", appearance: .darkAqua)
        view.document.undo(); view.refreshSelection()
        guard view.document.marks.count == 1 else { throw UserFacingError("Smoke: overlay text edit does not share annotation undo history") }
        view.document.redo(); view.refreshSelection()
        let regionBefore = view.document.captureRegion
        view.reselect(); guard view.selection == nil else { throw UserFacingError("Smoke: reselect does not restore full-screen mask") }
        view.document.undo(); view.refreshSelection()
        guard view.document.captureRegion == regionBefore, view.document.marks.count == 2 else { throw UserFacingError("Smoke: undo reselect loses annotations") }
        print("PASS: clipped overlay canvas uses full-resolution coordinates; native multiline text edits in place; annotation and selection undo share history without flattening")

        let textBounds = view.document.marks[1].bounds
        let textPoint = CGPoint(x: textBounds.midX/2, y: textBounds.midY/2)
        view.canvas.mouseDown(with: mouse(.leftMouseDown, textPoint, clicks: 2))
        guard let composed = view.canvas.subviews.compactMap({ $0 as? InlineAnnotationTextView }).first else {
            throw UserFacingError("Smoke: cannot reopen overlay text for input-method composition")
        }
        composed.setMarkedText("图片内编辑", selectedRange: NSRange(location: 0, length: 0),
                               replacementRange: NSRange(location: 0, length: composed.string.utf16.count))
        guard let result = view.selectedDocument(), let rendered = result.render(), let data = rendered.png,
              rendered.size == NSSize(width: 1000, height: 500), result.marks.count == 2,
              result.marks[1].text == "图片内编辑", view.document.editingTextID == nil,
              hypot(result.marks[0].points[0].x-240, result.marks[0].points[0].y-140) < 0.01 else { throw UserFacingError("Smoke: final screenshot loses crop resolution or editable object positions") }
        let expected = images[0].cropping(to: CGRect(x: initial.minX, y: CGFloat(images[0].height)-initial.maxY, width: initial.width, height: initial.height))!
        let source = NSBitmapImageRep(cgImage: expected), actual = NSBitmapImageRep(data: data)!
        for p in [CGPoint(x:20,y:20), CGPoint(x:950,y:450), CGPoint(x:20,y:450)] {
            let a = source.colorAt(x: Int(p.x), y: Int(p.y))!.usingColorSpace(.deviceRGB)!
            let b = actual.colorAt(x: Int(p.x), y: Int(p.y))!.usingColorSpace(.deviceRGB)!
            guard abs(a.redComponent-b.redComponent) < 0.02, abs(a.greenComponent-b.greenComponent) < 0.02 else {
                throw UserFacingError("Smoke: mask or toolbar leaked into the saved screenshot")
            }
        }
        try data.write(to: destination.appendingPathComponent("region-final.png"))
        let isolated = NSPasteboard.withUniqueName(); defer { isolated.releaseGlobally() }
        let service = CaptureService(); try service.acceptRegionCapture(result, pasteboard: isolated)
        guard isolated.data(forType: .png) == data, service.document === result, service.document.marks.count == 2, !service.recent.isEmpty else {
            throw UserFacingError("Smoke: region completion does not save/copy the final annotations or preserve editable objects")
        }
        print("PASS: final crop saves/copies annotated native PNG to an isolated pasteboard; mask, border and toolbar are excluded; editable objects survive completion")
        view.keyDown(with: NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                           windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
                                           charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!)
        guard cancelled, !completed, windows.allSatisfy({ !$0.isVisible }) else { throw UserFacingError("Smoke: cancel loses workspace isolation") }
        print("PASS: Esc cancels the workspace; checks never show display windows, capture the desktop or write the general pasteboard")
    }
}
