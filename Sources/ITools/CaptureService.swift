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
        busy = true; NSApp.hide(nil)
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
                            self.document = AnnotationDocument(image: image); self.refreshRecent(); self.onShow?()
                            if ocr { self.recognize() }
                            NoticeCenter.shared.success("截图已保存，可继续标注、贴图或复制")
                        } else if process.terminationStatus != 0 && process.terminationStatus != 1 {
                            self.onShow?(); NoticeCenter.shared.report(UserFacingError("截图失败，请检查屏幕录制权限后重试。"))
                        } else { NoticeCenter.shared.success("已取消截图") }
                    }
                }
                try task.run()
            } catch { self.busy = false; NoticeCenter.shared.report(error) }
        }
    }
    func openImage(_ url: URL? = nil) {
        guard let file = url ?? Panels.chooseFiles(types: ["png", "jpg", "jpeg", "tiff", "heic", "gif"], multiple: false).first else { return }
        guard let image = NSImage(contentsOf: file), image.isValid else { NoticeCenter.shared.report(UserFacingError("无法打开这张图片。")); return }
        document = AnnotationDocument(image: image); recognizedText = ""; onShow?()
    }
    func copyImage() {
        guard let image = document.render(), let data = image.png else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setData(data, forType: .png)
        NoticeCenter.shared.success("已复制图片")
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
        let urls = Panels.chooseFiles(types: ["png", "jpg", "jpeg"])
        guard urls.count >= 2 else { return }
        let images = urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }.compactMap { NSImage(contentsOf: $0) }
        guard images.count == urls.count else { NoticeCenter.shared.report(UserFacingError("有图片无法打开。")); return }
        let width = images.map { $0.size.width }.max() ?? 0
        let height = images.reduce(CGFloat(0)) { $0 + $1.size.height }
        guard width > 0, height > 0, width * height <= 80_000_000 else { NoticeCenter.shared.report(UserFacingError("拼接后的图片过大，请减少图片数量。")); return }
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width), pixelsHigh: Int(height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        var y = height
        for image in images { y -= image.size.height; image.draw(in: NSRect(x: 0, y: y, width: image.size.width, height: image.size.height)) }
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: width, height: height)); image.addRepresentation(rep)
        document = AnnotationDocument(image: image); onShow?()
        NoticeCenter.shared.success("已按文件名顺序纵向拼接，可继续标注或导出")
    }
    static func timestamp() -> String { let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss-SSS"; return f.string(from: Date()) }
}
extension NSImage {
    var png: Data? {
        guard let cg = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
    }
}
