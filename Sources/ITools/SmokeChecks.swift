import AppKit
import Vision
import SwiftUI
import IToolsCore

enum SmokeChecks {
    // Default checks use synthetic content and do not capture the desktop or touch the general pasteboard.
    // The optional fixture check captures the dedicated synthetic window for live verification.
    static func run(model: AppModel, destination: URL) throws {
        try CaptureRegionSmokeChecks.run(destination: destination)
        try ScrollingCaptureSmokeChecks.run(destination: destination)
        if ProcessInfo.processInfo.arguments.contains("--scroll-fixture-check") { try ScrollingCaptureSmokeChecks.runLiveFixture(model: model) }
        try AnnotationInteractionSmokeChecks.run(destination: destination)
        try RegionCaptureSmokeChecks.run(destination: destination)
        let qrText = "https://example.com/测试?message=你好"
        let qr = try QRCodeRenderer.image(text: qrText)
        let barcode = VNDetectBarcodesRequest(); barcode.symbologies = [.qr]
        try VNImageRequestHandler(cgImage: qr.cgImage(forProposedRect: nil, context: nil, hints: nil)!).perform([barcode])
        guard barcode.results?.first?.payloadStringValue == qrText else { throw UserFacingError("Smoke: QR Unicode round trip failed") }
        try qr.png!.write(to: destination.appendingPathComponent("qr-unicode.png"))
        print("PASS: generated QR decodes original Unicode URL offline")
        let scrollPage = NSImage(size: NSSize(width: 700, height: 3000))
        scrollPage.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 700, height: 3000).fill()
        for section in 0..<25 {
            let y = CGFloat(3000 - (section+1)*120)
            NSColor(calibratedWhite: section % 2 == 0 ? 0.96 : 1, alpha: 1).setFill()
            NSRect(x: 0, y: y, width: 700, height: 120).fill()
            ("Section \(section+1) / unique value \(section*section)" as NSString).draw(at: CGPoint(x: 24,y: y+72), withAttributes: [.font: NSFont.systemFont(ofSize: 23, weight: .semibold), .foregroundColor: NSColor.systemBlue])
            ("Continuous scrolling screenshot, original editable content." as NSString).draw(at: CGPoint(x: 24,y: y+28), withAttributes: [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.black])
        }
        scrollPage.unlockFocus()
        let pageCG = scrollPage.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let scrolling = ScrollingStitcher()
        let viewHeight = min(1200, pageCG.height / 3), maxOffset = pageCG.height - viewHeight
        var offsets = Array(stride(from: 0, through: maxOffset, by: viewHeight / 3))
        if offsets.last != maxOffset { offsets.append(maxOffset) }
        for offset in offsets {
            let slice = pageCG.cropping(to: CGRect(x: 0, y: offset, width: pageCG.width, height: viewHeight))!
            guard case .added = scrolling.append(ScrollingCaptureController.frame(slice)!) else { throw UserFacingError("Smoke: typography scrolling frame failed at \(offset)") }
        }
        guard scrolling.height == pageCG.height else { throw UserFacingError("Smoke: scrolling screenshot has missing or repeated rows") }
        try ScrollingCaptureController.image(scrolling.output!)!.png!.write(to: destination.appendingPathComponent("continuous-scrolling.png"))
        print("PASS: continuous native typography frames merge without missing/repeated rows")
        let size = NSSize(width: 640, height: 340)
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 340,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { throw UserFacingError("Smoke: bitmap creation failed") }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        NSColor.white.setFill(); NSRect(origin: .zero, size: size).fill()
        ("ITools Intel Mac" as NSString).draw(at: NSPoint(x: 35, y: 235), withAttributes: [
            .font: NSFont.systemFont(ofSize: 38, weight: .semibold), .foregroundColor: NSColor.black])
        ("macOS 12 Monterey" as NSString).draw(at: NSPoint(x: 35, y: 172), withAttributes: [
            .font: NSFont.systemFont(ofSize: 25), .foregroundColor: NSColor.darkGray])
        ("Synthetic test image / no user data" as NSString).draw(at: NSPoint(x: 35, y: 38), withAttributes: [
            .font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.gray])
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size); image.addRepresentation(rep)
        let retina = NSImage(cgImage: rep.cgImage!, size: NSSize(width: 320, height: 170))
        let stitched = try CaptureService.stitchedImage([retina, image])
        guard let stitchedCG = stitched.cgImage(forProposedRect: nil, context: nil, hints: nil),
              stitchedCG.width == 640, stitchedCG.height == 680 else { throw UserFacingError("Smoke: stitching lost Retina pixel resolution") }
        try stitched.png!.write(to: destination.appendingPathComponent("stitched-retina.png"))
        let rows = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 300, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        for y in 0..<300 { for x in 0..<64 {
            rows.setColor(NSColor(deviceRed: CGFloat(y % 251) / 250, green: CGFloat(y / 251) / 2, blue: CGFloat(x) / 64, alpha: 1), atX: x, y: y)
        } }
        let original = rows.cgImage!
        let first = NSImage(cgImage: original.cropping(to: CGRect(x: 0, y: 0, width: 64, height: 200))!, size: NSSize(width: 64, height: 200))
        let second = NSImage(cgImage: original.cropping(to: CGRect(x: 0, y: 120, width: 64, height: 180))!, size: NSSize(width: 64, height: 180))
        let longImage = try CaptureService.stitchedImage([first, second], removeOverlap: true)
        guard longImage.size == NSSize(width: 64, height: 300) else { throw UserFacingError("Smoke: long capture overlap removal failed") }
        let reference = try CaptureService.stitchedImage([NSImage(cgImage: original, size: NSSize(width: 64, height: 300))], removeOverlap: true)
        let referencePixels = NSBitmapImageRep(data: reference.png!)!
        let mergedPixels = NSBitmapImageRep(data: longImage.png!)!
        for y in [0, 119, 120, 199, 299] {
            let expected = referencePixels.colorAt(x: 32, y: y)!.usingColorSpace(.sRGB)!
            let actual = mergedPixels.colorAt(x: 32, y: y)!.usingColorSpace(.sRGB)!
            guard abs(expected.redComponent - actual.redComponent) < 0.01,
                  abs(expected.greenComponent - actual.greenComponent) < 0.01,
                  abs(expected.blueComponent - actual.blueComponent) < 0.01 else { throw UserFacingError("Smoke: long capture reordered pixels") }
        }
        let duplicate = try CaptureService.stitchedImage([first, first], removeOverlap: true)
        guard duplicate.size == first.size else { throw UserFacingError("Smoke: duplicate long frame added rows") }
        try longImage.png!.write(to: destination.appendingPathComponent("long-capture.png"))
        print("PASS: overlapping long frames merge at native resolution; duplicate frame adds no rows")
        let captureBoard = NSPasteboard.withUniqueName()
        defer { captureBoard.releaseGlobally() }
        let captureService = CaptureService()
        guard captureService.acceptScreenshot(image, pasteboard: captureBoard),
              let copied = captureBoard.data(forType: .png), let copiedImage = NSImage(data: copied),
              AnnotationDocument(image: copiedImage).image?.size == size else { throw UserFacingError("Smoke: screenshot did not automatically copy PNG") }
        captureService.document.marks = [.init(tool: .redact, points: [CGPoint(x: 20, y: 20), CGPoint(x: 310, y: 70)], color: .black, width: 4)]
        guard captureService.copyImage(to: captureBoard),
              let editedData = captureBoard.data(forType: .png), editedData != copied else { throw UserFacingError("Smoke: final copy did not include annotations") }
        print("PASS: screenshot automatically copies native PNG; final copy includes annotations on isolated pasteboard")

        model.capture.recognizedText = "旧识别结果"
        let imported = destination.appendingPathComponent("stitch-import.png")
        try image.png!.write(to: imported)
        model.capture.openImage(imported)
        guard model.capture.recognizedText.isEmpty else { throw UserFacingError("Smoke: image replacement retained old OCR") }
        print("PASS: Retina stitch retains pixel resolution; image replacement clears OCR")
        let document = AnnotationDocument(image: image)
        document.marks = [.init(tool: .redact, points: [CGPoint(x: 20,y: 20), CGPoint(x: 310,y: 70)], color: .black, width: 4)]
        guard let rendered = document.render(), let cg = rendered.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw UserFacingError("Smoke: annotation render failed") }
        guard cg.width == 640, cg.height == 340 else { throw UserFacingError("Smoke: export resolution changed") }
        let pixels = NSBitmapImageRep(cgImage: cg)
        guard let color = pixels.colorAt(x: 100,y: 295)?.usingColorSpace(.deviceRGB),
              color.redComponent < 0.03, color.greenComponent < 0.03, color.blueComponent < 0.03 else {
            throw UserFacingError("Smoke: opaque redaction failed")
        }
        try rendered.png!.write(to: destination.appendingPathComponent("annotation-export.png"))
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: cg).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        guard text.lowercased().contains("intel"), text.lowercased().contains("monterey") else {
            throw UserFacingError("Smoke: offline OCR did not recognize the fixture: " + text)
        }
        try text.write(to: destination.appendingPathComponent("ocr-result.txt"), atomically: true, encoding: .utf8)
        document.crop(to: CGRect(x: 10,y: 100,width: 600,height: 220))
        guard document.image?.size == NSSize(width: 600,height: 220) else { throw UserFacingError("Smoke: crop dimensions failed") }
        try document.render()!.png!.write(to: destination.appendingPathComponent("cropped-export.png"))
        document.undo()
        guard document.image?.size == size, document.marks.count == 1 else { throw UserFacingError("Smoke: crop undo did not restore original and editable marks") }
        document.redo()
        guard document.image?.size == NSSize(width: 600, height: 220), document.marks.count == 1 else { throw UserFacingError("Smoke: crop redo flattened marks") }
        document.undo()
        let editable = Annotation(tool: .text, points: [CGPoint(x: 100, y: 120)], color: .systemBlue, width: 5, text: "Original")
        document.add(editable); document.editSelectedText("Edited")
        guard document.selected?.text == "Edited" else { throw UserFacingError("Smoke: text cannot be edited") }
        document.undo(); guard document.selected?.text == "Original" else { throw UserFacingError("Smoke: text edit undo failed") }
        document.redo(); guard document.selected?.text == "Edited" else { throw UserFacingError("Smoke: text edit redo failed") }
        let arrow = Annotation(tool: .arrow, points: [CGPoint(x: 350, y: 170), CGPoint(x: 500, y: 250)], color: .red, width: 5)
        document.add(arrow); document.tool = .select
        let canvas = CanvasView(document: document)
        let testWindow = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 640, height: 400), styleMask: .borderless, backing: .buffered, defer: true)
        testWindow.isReleasedWhenClosed = false; testWindow.contentView = canvas
        canvas.frame = CGRect(x: 0, y: 0, width: 640, height: 400)
        func mouse(_ type: NSEvent.EventType, at p: CGPoint) -> NSEvent {
            let rect = canvas.imageRect
            let position = CGPoint(x: rect.minX + p.x/640*rect.width, y: rect.minY+p.y/340*rect.height)
            return NSEvent.mouseEvent(with: type, location: position, modifierFlags: [], timestamp: 0, windowNumber: testWindow.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 425, y: 210)))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 435, y: 220)))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 435, y: 220)))
        guard abs(document.selected!.points[0].x-360) < 0.01 else { throw UserFacingError("Smoke: selected arrow did not move") }
        document.undo(); guard document.selected!.points[0] == arrow.points[0] else { throw UserFacingError("Smoke: object move undo failed") }
        canvas.mouseDown(with: mouse(.leftMouseDown, at: CGPoint(x: 500, y: 250)))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: 540, y: 270)))
        canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: 540, y: 270)))
        guard abs(document.selected!.points.last!.x-540) < 0.01 else { throw UserFacingError("Smoke: arrow handle resize failed") }
        document.undo(); guard document.selected!.points.last! == arrow.points.last! else { throw UserFacingError("Smoke: object resize undo failed") }
        document.deleteSelected(); document.undo()
        guard document.selected?.id == arrow.id else { throw UserFacingError("Smoke: deletion undo failed") }
        for tool in [MarkTool.rectangle, .ellipse, .fill, .pen, .line, .text] {
            let points = tool == .text ? [CGPoint(x: 100, y: 170)] : tool == .pen ? [CGPoint(x: 100,y: 170), CGPoint(x: 130,y: 200), CGPoint(x: 240,y: 260)] : [CGPoint(x: 100,y: 170), CGPoint(x: 240,y: 260)]
            let mark = Annotation(tool: tool, points: points, color: .systemBlue, width: 5, text: "Editable")
            document.add(mark); document.tool = .select
            let center = CGPoint(x: mark.bounds.midX, y: mark.bounds.midY)
            canvas.mouseDown(with: mouse(.leftMouseDown, at: center))
            canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: center.x+8, y: center.y+6)))
            canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: center.x+8, y: center.y+6)))
            guard abs(document.selected!.points[0].x - mark.points[0].x - 8) < 0.01 else { throw UserFacingError("Smoke: \(tool.rawValue) cannot move") }
            document.undo()
            let corner = CGPoint(x: mark.bounds.maxX, y: mark.bounds.maxY)
            canvas.mouseDown(with: mouse(.leftMouseDown, at: corner))
            canvas.mouseDragged(with: mouse(.leftMouseDragged, at: CGPoint(x: corner.x+30, y: corner.y+20)))
            canvas.mouseUp(with: mouse(.leftMouseUp, at: CGPoint(x: corner.x+30, y: corner.y+20)))
            guard document.selected!.bounds.width > mark.bounds.width else { throw UserFacingError("Smoke: \(tool.rawValue) cannot resize") }
            document.undo(); document.deleteSelected()
        }
        document.select(arrow.id)
        print("PASS: rectangle, ellipse, fill, pen, line and text move/resize through actual canvas event handlers")
        func exportEditorPreview<V: View>(_ root: V, name: String, width: CGFloat, height: CGFloat, appearance: NSAppearance.Name) throws {
            let dark = appearance == .darkAqua
            let host = NSHostingView(rootView: root.buttonStyle(.bordered).tint(accent)
                .environment(\.colorScheme, dark ? .dark : .light)
                .background(dark ? Color(white: 0.14) : Color(white: 0.96)))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: height), styleMask: .borderless, backing: .buffered, defer: true)
            window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: appearance)
            host.appearance = window.appearance
            host.frame = CGRect(x: 0, y: 0, width: width, height: height); window.contentView = host
            host.layoutSubtreeIfNeeded()
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw UserFacingError("Smoke: editor preview allocation failed") }
            host.cacheDisplay(in: host.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { throw UserFacingError("Smoke: editor preview encoding failed") }
            try png.write(to: destination.appendingPathComponent(name + ".png")); window.close()
        }
        try exportEditorPreview(EditorView(capture: captureService, document: document).padding(16), name: "editable-editor-light", width: 800, height: 650, appearance: .aqua)
        try exportEditorPreview(EditorView(capture: captureService, document: document).padding(16), name: "editable-editor-dark", width: 620, height: 650, appearance: .darkAqua)
        try exportEditorPreview(ScrollingCaptureHUD(controller: ScrollingCaptureController()), name: "scrolling-hud", width: 610, height: 132, appearance: .aqua)
        testWindow.close()
        print("PASS: editable objects move/resize using canvas events; text edit, crop, deletion undo/redo preserve objects")
        if ProcessInfo.processInfo.arguments.contains("--capture-editor-check") { return }

        model.capture.document = AnnotationDocument(image: image)
        model.capture.document.marks = [.init(tool: .arrow, points: [CGPoint(x: 420,y: 110), CGPoint(x: 275,y: 195)], color: .systemBlue, width: 5)]
        model.clipboard.entries = [
            ClipEntry(kind: .text, text: "自动测试样例：这里展示剪贴板条目的排版，并未读取你的剪贴板。", source: "iTools UI verification", payload: [.init(type: "public.utf8-plain-text", data: Data("fixture".utf8))])
        ]
        model.clipboard.entries[0].pinned = true
        model.clipboard.entries[0].group = "测试"
        model.files.selection = [destination.appendingPathComponent("annotation-export.png")]
        let pending = URL(string: "itools://finder?action=move&path=%2Ftmp%2Fitools-no-such-test-file")!
        let prior = model.files.selection
        model.files.receive(pending)
        guard model.files.pendingFinderAction == "move", !FileManager.default.fileExists(atPath: "/tmp/itools-no-such-test-file") else {
            throw UserFacingError("Smoke: Finder request staging failed")
        }
        model.files.pendingFinderAction = nil; model.files.selection = prior
        for action in FinderActions.all {
            var components = URLComponents()
            components.scheme = "itools"; components.host = "finder"
            components.queryItems = [.init(name: "action", value: action.id), .init(name: "path", value: prior[0].path)]
            model.files.receive(components.url!)
            guard model.files.pendingFinderAction == action.id, FileManager.default.fileExists(atPath: prior[0].path) else {
                throw UserFacingError("Smoke: Finder route was not safely staged: " + action.id)
            }
        }
        model.files.pendingFinderAction = nil
        let requests = FinderMenuRequests(); requests.beginMenu()
        let copiedItem = NSMenuItem(title: "拷贝路径", action: nil, keyEquivalent: "")
        copiedItem.tag = requests.insert(FinderMenuRequests.makeURL(action: "copy-path", paths: prior)!)
        guard copiedItem.representedObject == nil, let forwarded = requests.request(tag: copiedItem.tag),
              FinderHostLocation.isHost(Bundle.main.bundleURL) else { throw UserFacingError("Smoke: Finder tag-only route or containing app validation failed") }
        model.files.receive(forwarded)
        guard model.files.pendingFinderAction == "copy-path", model.files.selection == prior else { throw UserFacingError("Smoke: Finder request did not survive missing representedObject") }
        model.files.pendingFinderAction = nil
        print("PASS: Finder callback with no representedObject resolves tag and stages exact paths; app bundle validated")
        model.files.receive(URL(string: "itools://finder?action=arbitrary-command&path=%2Ftmp")!)
        guard model.files.pendingFinderAction == nil else { throw UserFacingError("Smoke: unsupported Finder action accepted") }
        let fixtures = destination.appendingPathComponent("file-fixtures-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: fixtures, withIntermediateDirectories: true)
        var fixture = try FileOperations.create(in: fixtures, name: "文件.txt", data: Data("fixture".utf8))
        var attributes = URLResourceValues(); attributes.hasHiddenExtension = true; try fixture.setResourceValues(attributes)
        guard try fixture.resourceValues(forKeys: [.hasHiddenExtensionKey]).hasHiddenExtension == true else { throw UserFacingError("Smoke: extension attribute failed") }
        guard NSWorkspace.shared.setIcon(NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil), forFile: fixture.path, options: []),
              NSWorkspace.shared.setIcon(nil, forFile: fixture.path, options: []) else { throw UserFacingError("Smoke: custom icon update/reset failed") }
        let bookmark = try fixture.bookmarkData(options: .suitableForBookmarkFile, includingResourceValuesForKeys: nil, relativeTo: nil)
        let alias = fixtures.appendingPathComponent("测试替身"); try URL.writeBookmarkData(bookmark, to: alias)
        guard try URL(resolvingAliasFileAt: alias).standardizedFileURL == fixture.standardizedFileURL else { throw UserFacingError("Smoke: Finder alias failed") }
        for format in ["zip", "7z"] {
            let archive = fixtures.appendingPathComponent("smoke." + format)
            try ArchiveEngine.create([fixture], at: archive, executable: model.files.archiveExecutable, options: .init(format: format, password: "synthetic-only"))
        }
        model.files.scanEntries = try DiskScanner.scan(fixtures, cancellation: ScanCancellation())
        model.files.scanSummary = "自检样例：测试文件、替身与已校验的加密压缩包"
        model.files.selection = prior; model.files.result = ""
        print("PASS: all Finder routes staged, unknown routes rejected, extension attribute, custom icon/reset, Finder alias, bundled ZIP/7z encryption")
        print("PASS: pixel resolution, opaque redaction, offline OCR, crop dimensions, Finder request staging")
        try NativeFileSmokeChecks.run(destination: destination)
    }
}
