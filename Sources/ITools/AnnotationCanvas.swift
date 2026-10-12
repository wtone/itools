import AppKit
import SwiftUI
import Combine

enum MarkTool: String, CaseIterable, Identifiable {
    case select = "选择与移动", pen = "画笔", line = "线条", rectangle = "矩形", ellipse = "椭圆", arrow = "箭头", text = "文字", fill = "填充色块", redact = "遮盖", crop = "裁剪"
    var id: String { rawValue }
    var icon: String {
        switch self { case .select: return "cursorarrow"; case .pen: return "pencil.tip"; case .line: return "line.diagonal"
        case .rectangle: return "rectangle"; case .ellipse: return "oval"; case .arrow: return "arrow.up.right"
        case .text: return "textformat"; case .fill: return "square.fill"; case .redact: return "eye.slash"; case .crop: return "crop" }
    }
}
struct Annotation: Identifiable, Equatable {
    var id = UUID()
    var tool: MarkTool; var points: [CGPoint]; var color: NSColor; var width: CGFloat; var text: String = ""
    var font: NSFont { .systemFont(ofSize: max(18, width * 5), weight: .semibold) }
    var arrowHead: [CGPoint] {
        guard tool == .arrow, let first = points.first, let last = points.last else { return [] }
        let angle = atan2(last.y-first.y, last.x-first.x), length = max(18, width * 4)
        return [CGPoint(x: last.x-length*cos(angle-0.5), y: last.y-length*sin(angle-0.5)), last,
                CGPoint(x: last.x-length*cos(angle+0.5), y: last.y-length*sin(angle+0.5))]
    }
    var bounds: CGRect {
        guard let first = points.first else { return .zero }
        if tool == .text {
            let size = (text as NSString).boundingRect(with: NSSize(width: 100_000, height: 100_000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font]).size
            return CGRect(origin: first, size: NSSize(width: max(1, ceil(size.width)), height: max(ceil(NSLayoutManager().defaultLineHeight(for: font)), ceil(size.height))))
        }
        let xs = points.map(\.x), ys = points.map(\.y)
        return CGRect(x: xs.min()!, y: ys.min()!, width: max(1, xs.max()! - xs.min()!), height: max(1, ys.max()! - ys.min()!))
    }
}
final class AnnotationDocument: ObservableObject {
    @Published var image: NSImage?
    @Published var marks: [Annotation] = []
    @Published var tool: MarkTool = .arrow { didSet { if tool != oldValue { commitTextEditing(); hoveredID = nil } } }
    @Published var color = Color.red
    @Published var lineWidth: Double = 5
    @Published var selectedID: UUID?
    // A non-destructive screenshot boundary; annotations stay in full-image coordinates.
    @Published var captureRegion: CGRect?
    @Published var hoveredID: UUID?
    @Published private(set) var editingTextID: UUID?
    @Published private(set) var historyRevision = 0
    private struct State { let image: NSImage?; let marks: [Annotation]; let selectedID: UUID?; let captureRegion: CGRect? }
    private var undoStates: [State] = [], redoStates: [State] = []
    private var transaction: State?
    private var textBefore: Annotation?
    var canUndo: Bool { !undoStates.isEmpty }
    var canRedo: Bool { !redoStates.isEmpty }
    var selected: Annotation? { marks.first { $0.id == selectedID } }
    var interactionTool: MarkTool { hoveredID != nil && editingTextID == nil ? .select : tool }
    init(image: NSImage? = nil) {
        if let cg = image?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            self.image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        } else { self.image = image }
    }
    private var state: State { State(image: image, marks: marks, selectedID: selectedID, captureRegion: captureRegion) }
    private func restore(_ state: State) { image = state.image; marks = state.marks; selectedID = state.selectedID; captureRegion = state.captureRegion; hoveredID = nil; if let selected = selected { color = Color(selected.color); lineWidth = selected.width }; historyRevision += 1 }
    private func checkpoint(_ before: State? = nil) {
        undoStates.append(before ?? state); if undoStates.count > 60 { undoStates.removeFirst() }
        redoStates.removeAll(); historyRevision += 1
    }
    func beginEditing() { if transaction == nil { transaction = state } }
    func endEditing(changed: Bool) { if let before = transaction, changed { checkpoint(before) }; transaction = nil }
    func cancelEditing() { if let before = transaction { restore(before) }; transaction = nil }
    func add(_ mark: Annotation) { commitTextEditing(); checkpoint(); marks.append(mark); select(mark.id) }
    func select(_ id: UUID?) {
        selectedID = id
        if let selected = selected { color = Color(selected.color); lineWidth = selected.width }
    }
    func replace(_ mark: Annotation) { if let index = marks.firstIndex(where: { $0.id == mark.id }) { marks[index] = mark } }
    func deleteSelected() {
        commitTextEditing()
        guard let id = selectedID, marks.contains(where: { $0.id == id }) else { return }
        checkpoint(); marks.removeAll { $0.id == id }; selectedID = nil
    }
    func editSelectedText(_ text: String) {
        commitTextEditing()
        guard var mark = selected, mark.tool == .text, !text.isEmpty, mark.text != text else { return }
        checkpoint(); mark.text = text; replace(mark)
    }
    func applyStyle() {
        guard var mark = selected else { return }
        let nextColor = NSColor(color), nextWidth = CGFloat(lineWidth)
        guard !mark.color.isEqual(nextColor) || mark.width != nextWidth else { return }
        if editingTextID == nil { checkpoint() }; mark.color = nextColor; mark.width = nextWidth; replace(mark)
    }
    func beginTextEditing(id: UUID? = nil, at point: CGPoint = .zero) {
        commitTextEditing(); beginEditing()
        if let id = id, let mark = marks.first(where: { $0.id == id && $0.tool == .text }) {
            textBefore = mark; editingTextID = id; select(id)
        } else {
            var mark = Annotation(tool: .text, points: [point], color: NSColor(color), width: lineWidth)
            mark.points[0].y -= mark.bounds.height
            textBefore = nil; marks.append(mark); editingTextID = mark.id; select(mark.id)
        }
        hoveredID = nil
    }
    func commitTextEditing(cancelled: Bool = false) {
        guard let id = editingTextID else { return }
        editingTextID = nil
        if cancelled { cancelEditing(); textBefore = nil; return }
        let mark = marks.first { $0.id == id }
        if mark?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            marks.removeAll { $0.id == id }; if selectedID == id { selectedID = nil }
            endEditing(changed: textBefore != nil)
        } else { endEditing(changed: mark != textBefore) }
        textBefore = nil
    }
    func undo() { commitTextEditing(); guard let before = undoStates.popLast() else { return }; redoStates.append(state); restore(before) }
    func redo() { commitTextEditing(); guard let after = redoStates.popLast() else { return }; undoStates.append(state); restore(after) }
    func draw(in rect: CGRect, excludingTextID: UUID? = nil) {
        guard let image = image else { return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        image.draw(in: rect)
        let transform = NSAffineTransform(); transform.translateX(by: rect.minX, yBy: rect.minY)
        transform.scaleX(by: rect.width / image.size.width, yBy: rect.height / image.size.height); transform.concat()
        for mark in marks where mark.id != excludingTextID { Self.draw(mark) }
        NSGraphicsContext.restoreGraphicsState()
    }
    static func draw(_ mark: Annotation) {
        guard let first = mark.points.first, let last = mark.points.last else { return }
        mark.color.setStroke(); mark.color.setFill()
        let path = NSBezierPath(); path.lineWidth = mark.width; path.lineCapStyle = .round; path.lineJoinStyle = .round
        let rect = CGRect(x: min(first.x, last.x), y: min(first.y, last.y), width: abs(first.x-last.x), height: abs(first.y-last.y))
        switch mark.tool {
        case .select: break
        case .pen: path.move(to: first); mark.points.dropFirst().forEach { path.line(to: $0) }; path.stroke()
        case .line: path.move(to: first); path.line(to: last); path.stroke()
        case .rectangle: path.appendRect(rect); path.stroke()
        case .ellipse: path.appendOval(in: rect); path.stroke()
        case .fill: NSBezierPath(rect: rect).fill()
        case .redact: NSColor.black.setFill(); NSBezierPath(rect: rect).fill()
        case .arrow:
            path.move(to: first); path.line(to: last); path.stroke()
            let head = mark.arrowHead
            path.move(to: head[0]); path.line(to: head[1]); path.line(to: head[2]); path.stroke()
        case .text:
            (mark.text as NSString).draw(with: mark.bounds, options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.foregroundColor: mark.color, .font: mark.font])
        case .crop:
            path.appendRect(rect); path.setLineDash([8, 6], count: 2, phase: 0); NSColor.systemBlue.setStroke(); path.stroke()
        }
    }
    func render() -> NSImage? {
        commitTextEditing()
        guard let image = image, image.size.width > 0, image.size.height > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(image.size.width), pixelsHigh: Int(image.size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        draw(in: CGRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        let output = NSImage(size: image.size); output.addRepresentation(rep); return output
    }
    func crop(to rect: CGRect) {
        commitTextEditing()
        guard let image = image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let bounded = rect.intersection(CGRect(origin: .zero, size: image.size)).integral
        guard !bounded.isNull, bounded.width >= 2, bounded.height >= 2,
              let cropped = cg.cropping(to: CGRect(x: bounded.minX, y: image.size.height-bounded.maxY, width: bounded.width, height: bounded.height)) else { return }
        checkpoint()
        self.image = NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height))
        marks = marks.map { mark in
            var translated = mark; translated.points = mark.points.map { CGPoint(x: $0.x-bounded.minX, y: $0.y-bounded.minY) }; return translated
        }
        selectedID = nil; tool = .select
        NoticeCenter.shared.success("已裁剪；标注仍可编辑，⌘Z 可恢复")
    }
}
struct AnnotationCanvas: NSViewRepresentable {
    @ObservedObject var document: AnnotationDocument
    func makeNSView(context: Context) -> CanvasView { CanvasView(document: document) }
    func updateNSView(_ view: CanvasView, context: Context) { view.update(document: document) }
}
class CanvasView: NSView, NSTextViewDelegate {
    private(set) var document: AnnotationDocument
    private var active: Annotation?
    private var dragStart: CGPoint?
    private var original: Annotation?
    private var handle: Int?
    private var changed = false
    private var tracking: NSTrackingArea?
    private var subscription: AnyCancellable?
    private var textEditor: InlineAnnotationTextView?
    private var editorID: UUID?
    private var textTop: CGFloat = 0
    private var finishingText = false
    private var outsideClickMonitor: Any?
    private var focusObserver: NSObjectProtocol?
    var imageRectOverride: CGRect? { didSet { layoutTextEditor(); needsDisplay = true } }
    init(document: AnnotationDocument) { self.document = document; super.init(frame: .zero); observeDocument() }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var acceptsFirstResponder: Bool { true }
    func update(document: AnnotationDocument) {
        if self.document !== document {
            finishTextEditing(); self.document = document; observeDocument()
        }
        synchronizeTextEditor(); needsDisplay = true
    }
    private func observeDocument() {
        subscription = document.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.synchronizeTextEditor(); self?.needsDisplay = true
        }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking = tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self)
        tracking = area; addTrackingArea(area)
    }
    override func mouseMoved(with event: NSEvent) { updateHover(event) }
    override func mouseEntered(with event: NSEvent) { updateHover(event) }
    override func mouseExited(with event: NSEvent) { document.hoveredID = nil; NSCursor.arrow.set(); needsDisplay = true }
    override func cursorUpdate(with event: NSEvent) { updateHover(event) }
    private var highlighted: Annotation? { document.marks.first { $0.id == document.hoveredID } ?? document.selected }
    private func updateHover(_ event: NSEvent) {
        guard textEditor == nil, active == nil, original == nil else { return }
        guard document.tool != .crop, !event.modifierFlags.contains(.option), let p = point(event) else {
            document.hoveredID = nil; (document.tool == .select ? NSCursor.arrow : .crosshair).set(); needsDisplay = true; return
        }
        let nearHandle = highlighted.flatMap { mark -> Annotation? in
            handles(mark).contains { hypot($0.x-p.x, $0.y-p.y) <= 9/scale } ? mark : nil
        }
        let hovered = nearHandle ?? document.marks.reversed().first { hit($0, at: p) }
        if document.hoveredID != hovered?.id { document.hoveredID = hovered?.id; needsDisplay = true }
        (nearHandle != nil ? NSCursor.crosshair : hovered != nil ? .openHand : document.tool == .select ? .arrow : .crosshair).set()
    }
    var imageRect: CGRect {
        if let rect = imageRectOverride { return rect }
        guard let size = document.image?.size, size.width > 0, size.height > 0 else { return .zero }
        let factor = min((bounds.width-28)/size.width, (bounds.height-28)/size.height)
        return CGRect(x: (bounds.width-size.width*factor)/2, y: (bounds.height-size.height*factor)/2, width: size.width*factor, height: size.height*factor)
    }
    private var scale: CGFloat { imageRect.width / max(1, document.image?.size.width ?? 1) }
    private func handles(_ mark: Annotation) -> [CGPoint] {
        if mark.tool == .arrow || mark.tool == .line { return [mark.points.first!, mark.points.last!] }
        let b = mark.bounds
        return [CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY), CGPoint(x: b.maxX, y: b.maxY), CGPoint(x: b.minX, y: b.maxY)]
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill(); bounds.fill()
        let rect = imageRect
        guard rect.width > 0, let image = document.image else { return }
        document.draw(in: rect, excludingTextID: document.editingTextID)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()
        let transform = NSAffineTransform(); transform.translateX(by: rect.minX, yBy: rect.minY)
        transform.scaleX(by: rect.width/image.size.width, yBy: rect.height/image.size.height); transform.concat()
        if let active = active { AnnotationDocument.draw(active) }
        if textEditor == nil, let selected = highlighted {
            NSColor.controlAccentColor.setStroke()
            let path = NSBezierPath(rect: selected.bounds.insetBy(dx: -3/scale, dy: -3/scale)); path.lineWidth = 1/scale; path.setLineDash([4/scale, 3/scale], count: 2, phase: 0); path.stroke()
            for point in handles(selected) {
                let rect = CGRect(x: point.x-4/scale, y: point.y-4/scale, width: 8/scale, height: 8/scale)
                NSColor.white.setFill(); NSBezierPath(roundedRect: rect, xRadius: 1/scale, yRadius: 1/scale).fill()
                NSColor.controlAccentColor.setStroke(); let handle = NSBezierPath(rect: rect); handle.lineWidth = 1/scale; handle.stroke()
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    private func point(_ event: NSEvent, clamp: Bool = false) -> CGPoint? {
        let p = convert(event.locationInWindow, from: nil); let rect = imageRect
        guard rect.width > 0, clamp || rect.insetBy(dx: -8, dy: -8).contains(p), let size = document.image?.size else { return nil }
        return CGPoint(x: min(size.width, max(0, (p.x-rect.minX)/rect.width*size.width)), y: min(size.height, max(0, (p.y-rect.minY)/rect.height*size.height)))
    }
    private func hit(_ mark: Annotation, at p: CGPoint) -> Bool {
        let tolerance = max(mark.width / 2 + 3/scale, 6/scale)
        let b = mark.bounds
        var hitBounds = b
        for point in mark.arrowHead { hitBounds = hitBounds.union(CGRect(origin: point, size: NSSize(width: 1, height: 1))) }
        guard hitBounds.insetBy(dx: -tolerance, dy: -tolerance).contains(p) else { return false }
        switch mark.tool {
        case .rectangle: return true
        case .ellipse: return pow((p.x-b.midX)/max(1,b.width/2+tolerance), 2) + pow((p.y-b.midY)/max(1,b.height/2+tolerance), 2) <= 1
        case .pen, .line, .arrow:
            let segments = Array(zip(mark.points, mark.points.dropFirst())) + Array(zip(mark.arrowHead, mark.arrowHead.dropFirst()))
            return segments.contains { a, b in
                let dx = b.x-a.x, dy = b.y-a.y, length = dx*dx+dy*dy
                let t = length > 0 ? min(1, max(0, ((p.x-a.x)*dx+(p.y-a.y)*dy)/length)) : 0
                return hypot(p.x-(a.x+t*dx), p.y-(a.y+t*dy)) <= tolerance
            }
        default: return true
        }
    }
    func hitsAnnotation(with event: NSEvent) -> Bool {
        guard let p = point(event) else { return false }
        return highlighted.map { handles($0).contains { hypot($0.x-p.x, $0.y-p.y) <= 9/scale } } == true
            || document.marks.reversed().contains { hit($0, at: p) }
    }
    private func editText() {
        guard let selected = document.selected, selected.tool == .text else { return }
        document.beginTextEditing(id: selected.id); synchronizeTextEditor()
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let p = point(event) else { return }
        changed = false
        if document.tool != .crop, !event.modifierFlags.contains(.option), event.clickCount == 2,
           let mark = document.marks.reversed().first(where: { $0.tool == .text && hit($0, at: p) }) {
            document.beginTextEditing(id: mark.id); synchronizeTextEditor()
            if let editor = textEditor {
                let insertion = editor.characterIndexForInsertion(at: editor.convert(event.locationInWindow, from: nil))
                editor.setSelectedRange(NSRange(location: insertion, length: 0))
            }
            return
        }
        if document.tool != .crop, !event.modifierFlags.contains(.option), let selected = highlighted, let index = handles(selected).firstIndex(where: { hypot($0.x-p.x, $0.y-p.y) <= 9/scale }) {
            document.select(selected.id)
            original = selected; dragStart = p; handle = index; document.beginEditing(); return
        }
        if document.tool == .select, let selected = document.selected, selected.bounds.contains(p) {
            if event.clickCount == 2 && selected.tool == .text { editText(); needsDisplay = true; return }
            original = selected; dragStart = p; handle = nil; document.beginEditing(); return
        }
        if document.tool != .crop && !event.modifierFlags.contains(.option),
           let mark = document.marks.reversed().first(where: { hit($0, at: p) }) {
            document.select(mark.id)
            if event.clickCount == 2 && mark.tool == .text { editText(); needsDisplay = true; return }
            original = mark; dragStart = p; handle = nil; document.beginEditing(); needsDisplay = true; return
        }
        document.select(nil)
        guard document.tool != .select else { needsDisplay = true; return }
        if document.tool == .text {
            document.beginTextEditing(at: p); synchronizeTextEditor()
            needsDisplay = true; return
        }
        active = Annotation(tool: document.tool, points: [p], color: NSColor(document.color), width: document.lineWidth)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let p = point(event, clamp: true) else { return }
        if let original = original, let start = dragStart {
            var mark = original
            if let handle = handle {
                if mark.tool == .arrow || mark.tool == .line { mark.points[handle == 0 ? 0 : mark.points.count-1] = p }
                else {
                    let b = original.bounds, opposite = handles(original)[(handle + 2) % 4]
                    let target = CGRect(x: min(p.x, opposite.x), y: min(p.y, opposite.y), width: max(4, abs(p.x-opposite.x)), height: max(4, abs(p.y-opposite.y)))
                    if mark.tool == .text {
                        let factor = max(0.2, min(8, max(target.width/max(1,b.width), target.height/max(1,b.height))))
                        mark.width = max(3.6, original.width * factor); mark.points = [target.origin]
                    } else {
                        mark.points = original.points.map { CGPoint(x: target.minX+($0.x-b.minX)/max(1,b.width)*target.width, y: target.minY+($0.y-b.minY)/max(1,b.height)*target.height) }
                    }
                }
            } else { mark.points = original.points.map { CGPoint(x: $0.x+p.x-start.x, y: $0.y+p.y-start.y) } }
            document.replace(mark); changed = true; needsDisplay = true; return
        }
        guard active != nil else { return }
        if active?.tool == .pen { active?.points.append(p) }
        else if let first = active?.points.first { active?.points = [first, p] }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if original != nil {
            document.endEditing(changed: changed); original = nil; dragStart = nil; handle = nil
            if let selected = document.selected { document.lineWidth = selected.width }
        }
        if let mark = active {
            active = nil
            if mark.tool == .crop, let start = mark.points.first, let end = mark.points.last {
                document.crop(to: CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(start.x-end.x), height: abs(start.y-end.y)))
            } else if mark.points.count > 1 { document.add(mark) }
        }
        needsDisplay = true
        updateHover(event)
    }
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" {
            if event.modifierFlags.contains(.shift) { document.redo() } else { document.undo() }; needsDisplay = true; return
        }
        switch event.keyCode {
        case 51, 117: document.deleteSelected()
        case 53: document.cancelEditing(); active = nil; original = nil; dragStart = nil; document.select(nil)
        case 36: editText()
        case 123, 124, 125, 126:
            if var mark = document.selected {
                let delta: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
                let dx: CGFloat = event.keyCode == 123 ? -delta : event.keyCode == 124 ? delta : 0
                let dy: CGFloat = event.keyCode == 125 ? -delta : event.keyCode == 126 ? delta : 0
                document.beginEditing(); mark.points = mark.points.map { CGPoint(x: $0.x+dx, y: $0.y+dy) }; document.replace(mark); document.endEditing(changed: true)
            }
        default: super.keyDown(with: event)
        }
        needsDisplay = true
    }

    private func synchronizeTextEditor() {
        guard !finishingText else { return }
        guard let id = document.editingTextID, let mark = document.marks.first(where: { $0.id == id }) else {
            if textEditor != nil { finishTextEditing() }; return
        }
        if editorID != id {
            if textEditor != nil { finishTextEditing() }
            let editor = InlineAnnotationTextView(frame: .zero)
            textEditor = editor; editorID = id; textTop = mark.bounds.maxY
            editor.isRichText = false; editor.importsGraphics = false; editor.allowsUndo = true
            editor.isAutomaticQuoteSubstitutionEnabled = false; editor.isAutomaticDashSubstitutionEnabled = false
            editor.isAutomaticSpellingCorrectionEnabled = false; editor.isContinuousSpellCheckingEnabled = false
            editor.textContainerInset = NSSize(width: 2, height: 2); editor.textContainer?.lineFragmentPadding = 0
            editor.isHorizontallyResizable = false; editor.isVerticallyResizable = false
            editor.textContainer?.widthTracksTextView = false; editor.textContainer?.containerSize = NSSize(width: 100_000, height: 100_000)
            editor.drawsBackground = true; editor.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.92)
            editor.wantsLayer = true; editor.layer?.borderWidth = 1; editor.layer?.borderColor = NSColor.controlAccentColor.cgColor; editor.layer?.cornerRadius = 3
            editor.string = mark.text; editor.delegate = self
            editor.setAccessibilityLabel("图片中的标注文字")
            editor.onFinish = { [weak self] cancelled in self?.finishTextEditing(cancelled: cancelled) }
            addSubview(editor); layoutTextEditor()
            window?.makeFirstResponder(editor); editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
            outsideClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak editor] event in
                guard let self = self, let editor = editor else { return event }
                if event.window !== self.window || !editor.bounds.contains(editor.convert(event.locationInWindow, from: nil)) { self.finishTextEditing() }
                return event
            }
            focusObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in self?.finishTextEditing() }
        } else { layoutTextEditor() }
    }

    private func layoutTextEditor() {
        guard let editor = textEditor, let id = editorID, let mark = document.marks.first(where: { $0.id == id }), scale > 0 else { return }
        let rect = imageRect, b = mark.bounds
        let font = NSFont.systemFont(ofSize: mark.font.pointSize * scale, weight: .semibold)
        if editor.font != font { editor.font = font }; editor.textColor = mark.color
        editor.frame = CGRect(x: rect.minX+b.minX*scale-2, y: rect.minY+b.minY*scale-2, width: max(100, b.width*scale+5), height: b.height*scale+4)
    }

    func textDidChange(_ notification: Notification) {
        updateEditedText()
    }
    private func updateEditedText() {
        guard let editor = textEditor, let id = editorID, document.editingTextID == id,
              var mark = document.marks.first(where: { $0.id == id }) else { return }
        mark.text = editor.string; mark.points[0].y = textTop-mark.bounds.height
        document.replace(mark); layoutTextEditor(); needsDisplay = true
    }
    func commitInlineTextEditing() { finishTextEditing() }

    private func finishTextEditing(cancelled: Bool = false) {
        guard let editor = textEditor, !finishingText else { return }
        finishingText = true
        // Resign while the delegate is still connected, allowing native input methods
        // to finalize marked text before the document's editing transaction is saved.
        editor.onFinish = nil
        if window?.firstResponder === editor { window?.makeFirstResponder(self) }
        updateEditedText()
        if document.editingTextID == editorID { document.commitTextEditing(cancelled: cancelled) }
        editor.delegate = nil
        editor.removeFromSuperview(); textEditor = nil; editorID = nil
        if let monitor = outsideClickMonitor { NSEvent.removeMonitor(monitor) }; outsideClickMonitor = nil
        if let observer = focusObserver { NotificationCenter.default.removeObserver(observer) }; focusObserver = nil
        finishingText = false; needsDisplay = true
    }

    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); layoutTextEditor() }
    override func viewWillMove(toWindow newWindow: NSWindow?) { if newWindow == nil { finishTextEditing() }; super.viewWillMove(toWindow: newWindow) }
    deinit {
        if let monitor = outsideClickMonitor { NSEvent.removeMonitor(monitor) }
        if let observer = focusObserver { NotificationCenter.default.removeObserver(observer) }
    }
}


final class InlineAnnotationTextView: NSTextView {
    var onFinish: ((Bool) -> Void)?
    private let editUndo = UndoManager()
    override var undoManager: UndoManager? { editUndo }
    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result { onFinish?(false) }; return result
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onFinish?(true); return }
        if event.keyCode == 36 && event.modifierFlags.contains(.command) { onFinish?(false); return }
        super.keyDown(with: event)
    }
}
