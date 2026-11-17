import AppKit
import Combine
import Vision
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import IToolsCore

final class CaptureService: ObservableObject {
    @Published var document = AnnotationDocument()
    @Published var recognizedText = ""
    @Published var busy = false
    @Published var recent: [URL] = []
    @Published var pickedColor = ""
    private var scrollingController: ScrollingCaptureController?
    private var regionController: RegionCaptureController?
    private var process: Process?
    private var pins: [NSWindow] = []
    var onShow: (() -> Void)?
    var folder: URL { Storage.url("Captures") }
    init() { refreshRecent() }
    func refreshRecent() {
        recent = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? [])
            .filter { ["png", "jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }
    func capture(fullScreen: Bool = false, delay: Int = 0, ocr: Bool = false) {
        guard !busy, Permissions.requireScreen() else { return }
        guard !RegionSelector.shared.isSelecting else { NoticeCenter.shared.success("请先完成当前区域选择"); return }
        let restoreWindow = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
        busy = true
        if !fullScreen {
            let controller = RegionCaptureController(); regionController = controller
            controller.begin(delay: delay, allowScrolling: !ocr) { [weak self] result in
                guard let self = self else { return }
                self.regionController = nil
                guard let result = result else { self.busy = false; NoticeCenter.shared.success("已取消截图，原图片和剪贴板保留"); return }
                if case let .scrolling(displayID, pixels, automatic, slow, targetPID, releaseSelection) = result {
                    self.startLongCapture(displayID: displayID, pixels: pixels, automatic: automatic, slow: slow, targetPID: targetPID, releaseSelection: releaseSelection)
                    return
                }
                guard case let .region(document) = result else { return }
                self.busy = false
                do {
                    try self.acceptRegionCapture(document)
                    if restoreWindow || ocr { self.onShow?() }
                    if ocr { self.recognize() }
                } catch { self.document = document; self.onShow?(); NoticeCenter.shared.report(error) }
            }
            return
        }
        NSApp.hide(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(max(0, delay)) + 0.3) { [weak self] in
            guard let self = self else { return }
            do {
                try FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true)
                let url = self.folder.appendingPathComponent("Shot-" + Self.timestamp() + ".png")
                let task = Process(); self.process = task
                task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                task.arguments = (fullScreen ? ["-x", "-m"] : ["-x", "-i"]) + [url.path]
                task.standardError = FileHandle.nullDevice
                task.terminationHandler = { [weak self] process in
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        self.process = nil; self.busy = false
                        if FileManager.default.fileExists(atPath: url.path), let image = NSImage(contentsOf: url) {
                            guard self.acceptScreenshot(image) else { self.onShow?(); return }
                            self.refreshRecent(); self.onShow?()
                            if ocr { self.recognize() }
                            NoticeCenter.shared.success("截图已自动复制，可直接粘贴或继续标注")
                        } else if process.terminationStatus != 0 && process.terminationStatus != 1 {
                            self.onShow?(); NoticeCenter.shared.report(UserFacingError("截图失败，请检查屏幕录制权限后重试。"))
                        } else { if restoreWindow { self.onShow?() }; NoticeCenter.shared.success("已取消截图") }
                    }
                }
                try task.run()
            } catch { self.process = nil; self.busy = false; self.onShow?(); NoticeCenter.shared.report(error) }
        }
    }
    /// Preserve editable objects after finishing the overlay; only the saved/clipboard PNG is flattened.
    func acceptRegionCapture(_ result: AnnotationDocument, pasteboard: NSPasteboard = .general) throws {
        guard let image = result.render(), let data = image.png else { throw UserFacingError("无法生成截图，请重试。") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try data.write(to: folder.appendingPathComponent("Shot-" + Self.timestamp() + ".png"), options: .atomic)
        document = result; recognizedText = ""; refreshRecent()
        guard copyImage(to: pasteboard) else { throw UserFacingError("截图已保存，但复制失败；可在编辑器重新复制。") }
        NoticeCenter.shared.success("截图已保存并复制，标注仍可编辑")
    }
    func cancelRegionCapture() { regionController?.cancel() }
    @discardableResult
    func acceptScreenshot(_ image: NSImage, pasteboard: NSPasteboard = .general) -> Bool {
        document = AnnotationDocument(image: image); recognizedText = ""
        return copyImage(to: pasteboard)
    }
    private func startLongCapture(displayID: CGDirectDisplayID? = nil, pixels: CGRect? = nil, automatic: Bool = true, slow: Bool = false, targetPID: pid_t? = nil, releaseSelection: (() -> Void)? = nil) {
        let controller = ScrollingCaptureController(); scrollingController = controller
        let completion: (ScrollingCaptureController.Output?) -> Void = { [weak self] result in
            guard let self = self else { return }
            self.busy = false; self.scrollingController = nil
            guard let result = result else { self.onShow?(); NoticeCenter.shared.success("已取消长截图，原图片和剪贴板保留"); return }
            let image = result.image
            guard self.acceptScreenshot(image) else { self.onShow?(); return }
            do {
                try FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true)
                guard let data = image.png else { throw UserFacingError("长图编码失败，可在编辑器重试导出。") }
                try data.write(to: self.folder.appendingPathComponent((result.frames > 1 ? "Long-" : "Shot-") + Self.timestamp() + ".png"), options: .atomic)
                self.refreshRecent()
                NoticeCenter.shared.success(result.frames > 1 ? "长截图已保存并复制（\(result.frames) 段），可直接粘贴或继续标注" : "已保存并复制当前区域；尚未追加滚动画面")
            } catch { NoticeCenter.shared.report(error) }
            self.onShow?()
        }
        if let displayID = displayID, let pixels = pixels {
            controller.selectExisting(displayID: displayID, pixels: pixels, automatic: automatic, slow: slow, preferredTargetPID: targetPID, releaseSelection: releaseSelection, completion: completion)
        } else {
            controller.select(automatic: automatic, completion: completion)
        }
    }
    func cancelLongCapture() { scrollingController?.cancel() }
    func openImage(_ url: URL? = nil) {
        guard !busy else { return }
        guard let file = url ?? Panels.chooseFiles(types: ["png", "jpg", "jpeg", "tiff", "heic", "gif"], multiple: false).first else { return }
        guard let image = NSImage(contentsOf: file), image.isValid else { NoticeCenter.shared.report(UserFacingError("无法打开这张图片。")); return }
        document = AnnotationDocument(image: image); recognizedText = ""; onShow?()
    }
    @discardableResult
    func copyImage(to pasteboard: NSPasteboard = .general) -> Bool {
        guard let image = document.render(), let data = image.png else { NoticeCenter.shared.report(UserFacingError("无法生成图片，请重试。")); return false }
        pasteboard.clearContents()
        guard pasteboard.setData(data, forType: .png) else { NoticeCenter.shared.report(UserFacingError("未能复制图片，请重试。")); return false }
        NoticeCenter.shared.success("已复制图片"); return true
    }
    func exportImage() {
        guard let image = document.render(), let url = Panels.save(name: "iTools-" + Self.timestamp() + ".png", types: ["png", "jpg"]) else { return }
        NoticeCenter.shared.perform {
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw UserFacingError("图片无法导出。") }
            let rep = NSBitmapImageRep(cgImage: cg)
            let data = rep.representation(using: url.pathExtension.lowercased() == "jpg" ? .jpeg : .png, properties: [.compressionFactor: 0.92])
            guard let data = data else { throw UserFacingError("图片编码失败。") }
            try data.write(to: url, options: .atomic); NoticeCenter.shared.success("图片已导出")
        }
    }
    func pin() {
        guard let image = document.render() else { return }
        let size = image.size; let scale = min(1, 700 / max(size.width, size.height))
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: max(160, size.width * scale), height: max(100, size.height * scale)),
                             styleMask: [.titled, .closable, .resizable, .utilityWindow], backing: .buffered, defer: false)
        window.title = "iTools 贴图"; window.level = .floating; window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false; window.isMovableByWindowBackground = true
        let view = NSImageView(); view.image = image; view.imageScaling = .scaleProportionallyUpOrDown
        window.contentView = view; window.center(); window.makeKeyAndOrderFront(nil)
        pins.removeAll { !$0.isVisible }; pins.append(window)
    }
    func recognize() {
        guard !busy, let image = document.render()?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
                request.recognitionLanguages = ["zh-Hans", "zh-Hant", "en-US"]; request.usesLanguageCorrection = true
                let barcode = VNDetectBarcodesRequest(); barcode.symbologies = [.qr]
                try VNImageRequestHandler(cgImage: image).perform([request, barcode])
                let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                let codes = (barcode.results ?? []).compactMap(\.payloadStringValue)
                DispatchQueue.main.async {
                    self.busy = false; self.recognizedText = ([text] + codes).filter { !$0.isEmpty }.joined(separator: "\n\n")
                    NoticeCenter.shared.success(self.recognizedText.isEmpty ? "未识别到文字或二维码，试试更清晰的图片" : "文字识别完成，内容仅在本机处理")
                }
            } catch { DispatchQueue.main.async { self.busy = false }; NoticeCenter.shared.report(error) }
        }
    }
    func pickColor() {
        NSColorSampler().show { color in
            guard let color = color?.usingColorSpace(.sRGB) else { return }
            let text = String(format: "#%02X%02X%02X", Int(round(color.redComponent * 255)), Int(round(color.greenComponent * 255)), Int(round(color.blueComponent * 255)))
            self.pickedColor = text; copyText(text); NoticeCenter.shared.success("已复制颜色 " + text)
        }
    }
    func stitch() {
        guard !busy else { return }
        let urls = Panels.chooseFiles(types: ["png", "jpg", "jpeg"])
        guard urls.count >= 2 else { return }
        let images = urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }.compactMap { NSImage(contentsOf: $0) }
        guard images.count == urls.count else { NoticeCenter.shared.report(UserFacingError("有图片无法打开。")); return }
        NoticeCenter.shared.perform {
            let image = try Self.stitchedImage(images)
                document = AnnotationDocument(image: image); recognizedText = ""; onShow?()
            NoticeCenter.shared.success("已按文件名顺序纵向拼接，可继续标注或导出")
        }
    }
    static func stitchedImage(_ sources: [NSImage], removeOverlap: Bool = false) throws -> NSImage {
        let images = sources.compactMap { AnnotationDocument(image: $0).image }
        guard images.count == sources.count, images.count >= (removeOverlap ? 1 : 2) else { throw UserFacingError("请至少选择两张有效图片。") }
        guard images.count <= 50, images.reduce(CGFloat(0), { $0 + $1.size.width * $1.size.height }) <= 80_000_000 else {
            throw UserFacingError("长图过大，请完成当前长截图后分批截取。")
        }
        var overlaps = Array(repeating: 0, count: images.count)
        if removeOverlap, images.count > 1 {
            for index in 1..<images.count {
                overlaps[index] = matchingOverlap(images[index - 1], images[index])
            }
        }
        let width = images.map { $0.size.width }.max() ?? 0
        let height = images.enumerated().reduce(CGFloat(0)) { $0 + $1.element.size.height - CGFloat(overlaps[$1.offset]) }
        guard width.isFinite, height.isFinite, width > 0, height > 0, width * height <= 80_000_000 else {
            throw UserFacingError("拼接后的图片过大，请减少图片数量。")
        }
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { throw UserFacingError("无法创建拼接图片，请检查可用内存。") }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSColor.clear.setFill(); NSRect(x: 0, y: 0, width: width, height: height).fill(using: .copy)
        var y = height
        for (index, image) in images.enumerated() {
            let visibleHeight = image.size.height - CGFloat(overlaps[index])
            guard visibleHeight > 0 else { continue }
            y -= visibleHeight
            image.draw(in: NSRect(x: 0, y: y, width: image.size.width, height: visibleHeight),
                       from: NSRect(x: 0, y: 0, width: image.size.width, height: visibleHeight), operation: .sourceOver, fraction: 1)
        }
        let image = NSImage(size: NSSize(width: width, height: height)); image.addRepresentation(rep)
        return image
    }
    /// Match exact screen pixels; ambiguous or changing content is kept rather than discarded.
    private static func matchingOverlap(_ previous: NSImage, _ next: NSImage) -> Int {
        guard let a = previous.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let b = next.cgImage(forProposedRect: nil, context: nil, hints: nil), a.width == b.width else { return 0 }
        func pixels(_ image: CGImage) -> [UInt8]? {
            var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
            let ok = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                              bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                              space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
                context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height)); return true
            }
            return ok ? bytes : nil
        }
        guard let left = pixels(a), let right = pixels(b) else { return 0 }
        let row = a.width * 4
        for overlap in stride(from: min(a.height, b.height), through: 32, by: -1) {
            let start = (a.height - overlap) * row
            // First/last rows cheaply reject non-matches; full comparison prevents false deduplication.
            guard left[start..<start + row].elementsEqual(right[0..<row]),
                  left[(a.height - 1) * row..<a.height * row].elementsEqual(right[(overlap - 1) * row..<overlap * row]) else { continue }
            if left[start..<a.height * row].elementsEqual(right[0..<overlap * row]) { return overlap }
        }
        return 0
    }
    static func timestamp() -> String { let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss-SSS"; return f.string(from: Date()) }
}
extension NSImage {
    var png: Data? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }
}
