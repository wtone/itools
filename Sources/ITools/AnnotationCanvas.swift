import AppKit
import SwiftUI

enum MarkTool: String, CaseIterable, Identifiable {
    case pen = "画笔", rectangle = "矩形", arrow = "箭头", text = "文字", redact = "遮盖", crop = "裁剪"
    var id: String { rawValue }
    var icon: String {
        switch self { case .pen: return "pencil.tip"; case .rectangle: return "rectangle"; case .arrow: return "arrow.up.right"
        case .text: return "textformat"; case .redact: return "rectangle.fill"; case .crop: return "crop" }
    }
}
struct Annotation {
    var tool: MarkTool; var points: [CGPoint]; var color: NSColor; var width: CGFloat; var text: String = ""
}
final class AnnotationDocument: ObservableObject {
    @Published var image: NSImage?
    @Published var marks: [Annotation] = []
    @Published var tool: MarkTool = .arrow
    @Published var color = Color.red
    @Published var lineWidth: Double = 5
    init(image: NSImage? = nil) {
        if let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            self.image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        } else { self.image = image }
    }
    func undo() { if !marks.isEmpty { marks.removeLast() } }
    func draw(in rect: CGRect) {
        guard let image = image else { return }
        image.draw(in: rect)
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform(); transform.translateX(by: rect.minX, yBy: rect.minY)
        transform.scaleX(by: rect.width / image.size.width, yBy: rect.height / image.size.height); transform.concat()
        for mark in marks { Self.draw(mark) }
        NSGraphicsContext.restoreGraphicsState()
    }
    static func draw(_ mark: Annotation) {
        guard let first = mark.points.first, let last = mark.points.last else { return }
        mark.color.setStroke(); mark.color.setFill()
        let path = NSBezierPath(); path.lineWidth = mark.width; path.lineCapStyle = .round; path.lineJoinStyle = .round
        let rect = CGRect(x: min(first.x, last.x), y: min(first.y, last.y), width: abs(first.x-last.x), height: abs(first.y-last.y))
        switch mark.tool {
        case .pen: path.move(to: first); mark.points.dropFirst().forEach { path.line(to: $0) }; path.stroke()
        case .rectangle: path.appendRect(rect); path.stroke()
        case .redact: NSColor.black.setFill(); NSBezierPath(rect: rect).fill()
        case .arrow:
            path.move(to: first); path.line(to: last); path.stroke()
            let angle = atan2(last.y-first.y, last.x-first.x), length = max(18, mark.width * 4)
            path.move(to: CGPoint(x: last.x-length*cos(angle-0.5), y: last.y-length*sin(angle-0.5)))
            path.line(to: last); path.line(to: CGPoint(x: last.x-length*cos(angle+0.5), y: last.y-length*sin(angle+0.5))); path.stroke()
        case .text:
            (mark.text as NSString).draw(at: first, withAttributes: [.foregroundColor: mark.color, .font: NSFont.systemFont(ofSize: max(18, mark.width * 5), weight: .semibold)])
        case .crop:
            path.appendRect(rect); path.setLineDash([8, 6], count: 2, phase: 0); NSColor.systemBlue.setStroke(); path.stroke()
        }
    }
    func render() -> NSImage? {
        guard let image = image, image.size.width > 0, image.size.height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(image.size.width), pixelsHigh: Int(image.size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        draw(in: CGRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        let output = NSImage(size: image.size); output.addRepresentation(rep); return output
    }
    func crop(to rect: CGRect) {
        guard let rendered = render(), let cg = rendered.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let bounded = rect.intersection(CGRect(origin: .zero, size: rendered.size)).integral
        guard bounded.width >= 2, bounded.height >= 2,
              let cropped = cg.cropping(to: CGRect(x: bounded.minX, y: rendered.size.height-bounded.maxY, width: bounded.width, height: bounded.height)) else { return }
        image = NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height)); marks = []
        NoticeCenter.shared.success("已裁剪并合并标注；原截图文件保持不变")
    }
}
struct AnnotationCanvas: NSViewRepresentable {
    @ObservedObject var document: AnnotationDocument
    func makeNSView(context: Context) -> CanvasView { CanvasView(document: document) }
    func updateNSView(_ view: CanvasView, context: Context) { view.document = document; view.needsDisplay = true }
}
final class CanvasView: NSView {
    var document: AnnotationDocument
    private var active: Annotation?
    init(document: AnnotationDocument) { self.document = document; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var acceptsFirstResponder: Bool { true }
    var imageRect: CGRect {
        guard let size = document.image?.size, size.width > 0, size.height > 0 else { return .zero }
        let factor = min((bounds.width-28)/size.width, (bounds.height-28)/size.height)
        return CGRect(x: (bounds.width-size.width*factor)/2, y: (bounds.height-size.height*factor)/2, width: size.width*factor, height: size.height*factor)
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill(); bounds.fill()
        let rect = imageRect
        guard rect.width > 0 else { return }
        document.draw(in: rect)
        if let active = active, let image = document.image {
            NSGraphicsContext.saveGraphicsState()
            let transform = NSAffineTransform(); transform.translateX(by: rect.minX, yBy: rect.minY)
            transform.scaleX(by: rect.width/image.size.width, yBy: rect.height/image.size.height); transform.concat()
            AnnotationDocument.draw(active); NSGraphicsContext.restoreGraphicsState()
        }
    }
    private func point(_ event: NSEvent) -> CGPoint? {
        let p = convert(event.locationInWindow, from: nil); let rect = imageRect
        guard rect.width > 0, rect.contains(p), let size = document.image?.size else { return nil }
        return CGPoint(x: (p.x-rect.minX)/rect.width*size.width, y: (p.y-rect.minY)/rect.height*size.height)
    }
    override func mouseDown(with event: NSEvent) {
        guard let p = point(event) else { return }
        if document.tool == .text {
            if let text = Panels.text("标注文字"), !text.isEmpty {
                document.marks.append(Annotation(tool: .text, points: [p], color: NSColor(document.color), width: document.lineWidth, text: text))
            }
            needsDisplay = true; return
        }
        active = Annotation(tool: document.tool, points: [p], color: NSColor(document.color), width: document.lineWidth)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let p = point(event), active != nil else { return }
        if active?.tool == .pen { active?.points.append(p) }
        else if let first = active?.points.first { active?.points = [first, p] }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard let mark = active else { return }; active = nil
        if mark.tool == .crop, let start = mark.points.first, let end = mark.points.last {
            document.crop(to: CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(start.x-end.x), height: abs(start.y-end.y)))
        } else if mark.points.count > 1 { document.marks.append(mark) }
        needsDisplay = true
    }
}
