import AppKit
import Vision
import IToolsCore

enum SmokeChecks {
    // Entirely synthetic content. These checks never capture the desktop or touch the general pasteboard.
    static func run(model: AppModel, destination: URL) throws {
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
