import AppKit
import SwiftUI
import Combine
import IToolsCore

/// Region screenshots freeze every display before creating any mask or editing control.
/// The original pixels remain available until completion, so selection changes are lossless.
final class RegionCaptureController {
    private(set) static weak var active: RegionCaptureController?
    private(set) var windows: [SelectionWindow] = []
    private var completion: ((AnnotationDocument?) -> Void)?
    private var hiddenWindows: [NSWindow] = []
    private var previousApp: NSRunningApplication?
    private var screenObserver: NSObjectProtocol?
    private var keyMonitor: Any?
    private var pending: DispatchWorkItem?
    private var activeView: RegionCaptureWorkspace?

    func begin(delay: Int = 0, completion: @escaping (AnnotationDocument?) -> Void) {
        guard self.completion == nil, Self.active == nil, !RegionSelector.shared.isSelecting else { completion(nil); return }
        Self.active = self
        self.completion = completion
        let app = NSWorkspace.shared.frontmostApplication
        previousApp = app?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : app
        let contentWindows = NSApp.windows.filter { $0.canBecomeKey || $0.canBecomeMain }
        hiddenWindows = contentWindows.filter(\.isVisible)
        contentWindows.forEach { $0.orderOut(nil) }
        previousApp?.activate(options: [])
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, self.completion != nil else { return }
            self.pending = nil
            do {
                let displays = NSScreen.screens.compactMap(\.captureGeometry)
                guard !displays.isEmpty else { throw UserFacingError("没有可用显示器。") }
                // No overlay exists yet; capture native pixels, including Retina backing pixels.
                let snapshots = try displays.map { display -> CGImage in
                    guard let image = CGDisplayCreateImage(display.id) else {
                        throw UserFacingError("无法读取屏幕，请检查屏幕录制权限后重试。")
                    }
                    return image
                }
                self.install(displays: displays, snapshots: snapshots)
            } catch { self.finish(nil); NoticeCenter.shared.report(error) }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(max(0, delay)) + 0.25, execute: work)
    }

    private func install(displays: [CaptureDisplayGeometry], snapshots: [CGImage]) {
        // Window picking follows the same frozen desktop, rather than querying on every mouse move.
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let windowRects = (CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []).compactMap { info -> CGRect? in
            guard info[kCGWindowOwnerPID as String] as? Int32 != ProcessInfo.processInfo.processIdentifier,
                  info[kCGWindowLayer as String] as? Int == 0, (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return CGRect(x: rect.minX, y: primaryTop-rect.maxY, width: rect.width, height: rect.height)
        }
        windows = Self.makeWindows(displays: displays, snapshots: snapshots)
        for window in windows {
            guard let view = window.contentView as? RegionCaptureWorkspace else { continue }
            view.windowCandidates = windowRects.compactMap { view.display.localPoints(fromGlobal: $0) }
            view.onActivate = { [weak self, weak view] in
                guard let self = self, let view = view else { return }
                self.activeView = view
                for other in self.windows.compactMap({ $0.contentView as? RegionCaptureWorkspace }) {
                    other.isActive = other === view
                }
            }
            view.onComplete = { [weak self, weak view] in
                guard let self = self, let result = view?.selectedDocument() else { return }
                self.finish(result)
            }
            view.onCancel = { [weak self] in self?.cancel() }
        }
        windows.forEach { $0.orderFrontRegardless() }
        let focused = windows.first { $0.frame.contains(NSEvent.mouseLocation) } ?? windows.first
        NSApp.activate(ignoringOtherApps: true)
        focused?.makeKeyAndOrderFront(nil)
        if let view = focused?.contentView as? RegionCaptureWorkspace { focused?.makeFirstResponder(view) }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                object: nil, queue: .main) { [weak self] _ in self?.cancel() }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self = self else { return event }
            if event.type == .keyUp, event.keyCode == 49 {
                self.windows.compactMap { $0.contentView as? RegionCaptureWorkspace }.forEach { $0.spaceToMove = false }
                return event
            }
            guard self.windows.contains(where: { $0 === event.window }),
                  let view = event.window?.contentView as? RegionCaptureWorkspace else { return event }
            if event.type == .keyUp { return event }
            // Native text input owns composition, Return and Esc while it is editing.
            if view.document.editingTextID != nil { return event }
            if event.keyCode == 53 { self.cancel(); return nil }
            if event.keyCode == 36 || event.keyCode == 76 {
                if view.selection != nil { view.onComplete?() }
                return nil
            }
            if event.keyCode == 49,
               event.window?.firstResponder is CanvasView || event.window?.firstResponder === view {
                if view.selection == nil {
                    if !event.isARepeat { view.windowPickMode.toggle(); view.needsDisplay = true }
                }
                else { view.spaceToMove = true }
                return nil
            }
            return event
        }
    }

    static func makeWindows(displays: [CaptureDisplayGeometry], snapshots: [CGImage]) -> [SelectionWindow] {
        guard displays.count == snapshots.count else { return [] }
        return zip(displays, snapshots).map { display, snapshot in
            let window = SelectionWindow(contentRect: display.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver; window.isOpaque = false; window.backgroundColor = .clear
            window.hasShadow = false; window.isReleasedWhenClosed = false; window.sharingType = .none
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.acceptsMouseMovedEvents = true
            window.title = "区域截图工作区"
            let view = RegionCaptureWorkspace(display: display, snapshot: snapshot)
            window.contentView = view; window.makeFirstResponder(view)
            return window
        }
    }

    func cancel() { finish(nil) }
    private func finish(_ result: AnnotationDocument?) {
        guard let callback = completion else { return }
        completion = nil; pending?.cancel(); pending = nil
        if Self.active === self { Self.active = nil }
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }; keyMonitor = nil
        if let observer = screenObserver { NotificationCenter.default.removeObserver(observer) }; screenObserver = nil
        windows.forEach { ($0.contentView as? RegionCaptureWorkspace)?.document.commitTextEditing(); $0.close() }
        windows.removeAll(); activeView = nil
        hiddenWindows.forEach { $0.orderFront(nil) }
        if hiddenWindows.contains(where: \.canBecomeMain) { NSApp.activate(ignoringOtherApps: true) }
        else { previousApp?.activate(options: []) }
        hiddenWindows.removeAll(); previousApp = nil
        callback(result)
    }
    deinit {
        pending?.cancel()
        if let monitor = keyMonitor { NSEvent.removeMonitor(monitor) }
        if let observer = screenObserver { NotificationCenter.default.removeObserver(observer) }
        windows.forEach { $0.close() }
    }
}

/// Full-display frozen background, adjustable boundary and an annotation canvas clipped to it.
final class RegionCaptureWorkspace: NSView {
    let display: CaptureDisplayGeometry
    let document: AnnotationDocument
    let snapshot: CGImage
    let canvas: RegionAnnotationCanvas
    var onActivate: (() -> Void)?
    var onComplete: (() -> Void)?
    var onCancel: (() -> Void)?
    var isActive = true { didSet { refreshSelection() } }
    var spaceToMove = false
    var windowPickMode = false
    var windowCandidates: [CGRect] = []
    private var hoveredWindow: CGRect?
    private let chrome = RegionCaptureChrome(frame: .zero)
    private var toolbar: NSView!
    private var subscription: AnyCancellable?
    private var tracking: NSTrackingArea?
    private var dragStart: CGPoint?
    private var initialSelection: CGRect?
    private var resizeHandle: Int?
    private var drawingSelection = false
    private var selectionChanged = false

    var selection: CGRect? {
        document.captureRegion.map { CGRect(x: $0.minX / pixelScaleX, y: $0.minY / pixelScaleY,
                                            width: $0.width / pixelScaleX, height: $0.height / pixelScaleY) }
    }
    private var pixelScaleX: CGFloat { CGFloat(snapshot.width) / display.frame.width }
    private var pixelScaleY: CGFloat { CGFloat(snapshot.height) / display.frame.height }
    private func pixels(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX * pixelScaleX, y: rect.minY * pixelScaleY,
               width: rect.width * pixelScaleX, height: rect.height * pixelScaleY)
    }

    init(display: CaptureDisplayGeometry, snapshot: CGImage) {
        self.display = display; self.snapshot = snapshot
        let image = NSImage(cgImage: snapshot, size: NSSize(width: snapshot.width, height: snapshot.height))
        let document = AnnotationDocument(image: image)
        let captureScale = CGFloat(snapshot.width) / display.frame.width
        document.tool = .select; document.lineWidth = Double(captureScale * 3)
        self.document = document; canvas = RegionAnnotationCanvas(document: document)
        super.init(frame: CGRect(origin: .zero, size: display.frame.size))
        setAccessibilityRole(.group); setAccessibilityLabel("区域截图工作区")
        canvas.workspace = self; canvas.wantsLayer = true; canvas.layer?.masksToBounds = true
        canvas.setAccessibilityLabel("选区内标注编辑"); canvas.isHidden = true; addSubview(canvas)
        chrome.workspace = self; chrome.frame = bounds; chrome.autoresizingMask = [.width, .height]; addSubview(chrome)
        let glass = NSVisualEffectView()
        glass.material = .hudWindow; glass.blendingMode = .withinWindow; glass.state = .active
        glass.wantsLayer = true; glass.layer?.cornerRadius = 12; glass.layer?.masksToBounds = true
        let host = NSHostingView(rootView: RegionCaptureToolbar(document: document, pixelScale: captureScale,
                                                              reselect: { [weak self] in self?.reselect() },
                                                              complete: { [weak self] in self?.onComplete?() },
                                                              cancel: { [weak self] in self?.onCancel?() }))
        glass.addSubview(host); host.autoresizingMask = [.width, .height]
        toolbar = glass; toolbar.isHidden = true; addSubview(toolbar)
        subscription = document.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in self?.refreshSelection() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking = tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self)
        tracking = area; addTrackingArea(area)
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        guard bounds.contains(p) else { return nil }
        if !toolbar.isHidden, toolbar.frame.contains(p) { return super.hitTest(point) }
        if isActive, let rect = selection, handle(at: p, in: rect) != nil { return self }
        return super.hitTest(point)
    }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
        if isActive, let rect = selection {
            for (index, point) in handles(rect).enumerated() {
                addCursorRect(CGRect(x: point.x-6, y: point.y-6, width: 12, height: 12),
                              cursor: index == 1 || index == 5 ? .resizeUpDown : index == 3 || index == 7 ? .resizeLeftRight : .crosshair)
            }
        }
    }
    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if windowPickMode, selection == nil {
            hoveredWindow = windowRect(at: p); needsDisplay = true; NSCursor.crosshair.set(); return
        }
        if let rect = selection, let index = handle(at: p, in: rect) {
            (index == 1 || index == 5 ? NSCursor.resizeUpDown : index == 3 || index == 7 ? .resizeLeftRight : .crosshair).set()
        } else { NSCursor.crosshair.set() }
    }
    override func cursorUpdate(with event: NSEvent) { mouseMoved(with: event) }

    func refreshSelection() {
        let rect = isActive ? selection : nil
        canvas.isHidden = rect == nil || rect!.width < 4 || rect!.height < 4
        toolbar.isHidden = canvas.isHidden || drawingSelection
        if let rect = rect, !canvas.isHidden {
            canvas.imageRectOverride = CGRect(x: -rect.minX, y: -rect.minY, width: bounds.width, height: bounds.height)
            canvas.frame = rect; canvas.update(document: document)
            let width = min(610, bounds.width-24), height: CGFloat = 104
            let x = min(bounds.maxX-width-12, max(12, rect.maxX-width))
            let y: CGFloat
            if rect.minY >= height+20 { y = rect.minY-height-12 }
            else if bounds.maxY-rect.maxY >= height+20 { y = rect.maxY+12 }
            else { y = min(bounds.maxY-height-12, max(12, rect.minY+12)) }
            toolbar.frame = CGRect(x: x, y: y, width: width, height: height)
            toolbar.subviews.first?.frame = toolbar.bounds
        }
        window?.invalidateCursorRects(for: self)
        needsDisplay = true; chrome.needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let image = document.image else { return }
        image.draw(in: bounds)
        let rect = isActive ? (selection ?? (windowPickMode ? hoveredWindow : nil)) : nil
        let mask = NSBezierPath(rect: bounds); mask.windingRule = .evenOdd
        if let rect = rect { mask.appendRect(rect) }
        NSColor(calibratedWhite: 0.08, alpha: 0.36).setFill(); mask.fill()
        if rect == nil {
            let text = "拖动框选截图区域 · 空格切换窗口选择 · Esc 取消"
            let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 14, weight: .medium)]
            let size = (text as NSString).size(withAttributes: attrs)
            let pill = CGRect(x: max(12, (bounds.width-size.width-32)/2), y: bounds.height-68, width: size.width+32, height: 38)
            NSColor.black.withAlphaComponent(0.5).setFill()
            NSBezierPath(roundedRect: pill, xRadius: 10, yRadius: 10).fill()
            (text as NSString).draw(at: CGPoint(x: pill.minX+16, y: pill.minY+11), withAttributes: attrs)
        }
    }
    fileprivate func drawChrome() {
        if isActive, let rect = selection {
            NSColor.controlAccentColor.setStroke()
            let border = NSBezierPath(rect: rect); border.lineWidth = 1.5; border.stroke()
            for point in handles(rect) {
                let handle = NSBezierPath(roundedRect: CGRect(x: point.x-3, y: point.y-3, width: 6, height: 6), xRadius: 1, yRadius: 1)
                NSColor.white.setFill(); handle.fill(); NSColor.controlAccentColor.setStroke(); handle.stroke()
            }
            let text = "\(Int((document.captureRegion?.width ?? 0).rounded())) × \(Int((document.captureRegion?.height ?? 0).rounded())) px"
            let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.white, .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)]
            let size = (text as NSString).size(withAttributes: attrs)
            let y = rect.maxY+26 <= bounds.height ? rect.maxY+8 : max(8, rect.minY-26)
            let pill = CGRect(x: max(8, min(bounds.width-size.width-24, rect.minX)), y: y, width: size.width+16, height: 21)
            NSColor.black.withAlphaComponent(0.7).setFill()
            NSBezierPath(roundedRect: pill, xRadius: 5, yRadius: 5).fill()
            (text as NSString).draw(at: CGPoint(x: pill.minX+8, y: pill.minY+4), withAttributes: attrs)
        }
    }
    private func handles(_ rect: CGRect) -> [CGPoint] {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
         CGPoint(x: rect.maxX, y: rect.midY), CGPoint(x: rect.maxX, y: rect.maxY), CGPoint(x: rect.midX, y: rect.maxY),
         CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.midY)]
    }
    private func handle(at p: CGPoint, in rect: CGRect) -> Int? {
        if let index = handles(rect).firstIndex(where: { hypot($0.x-p.x, $0.y-p.y) <= 7 }) { return index }
        guard rect.insetBy(dx: -5, dy: -5).contains(p) else { return nil }
        if abs(p.x-rect.minX) <= 5 { return 7 }; if abs(p.x-rect.maxX) <= 5 { return 3 }
        if abs(p.y-rect.minY) <= 5 { return 1 }; if abs(p.y-rect.maxY) <= 5 { return 5 }
        return nil
    }
    override func mouseDown(with event: NSEvent) {
        onActivate?(); isActive = true; window?.makeKey(); window?.makeFirstResponder(self)
        document.commitTextEditing()
        let p = convert(event.locationInWindow, from: nil)
        if windowPickMode, selection == nil, let rect = windowRect(at: p) {
            document.beginEditing(); document.captureRegion = pixels(rect).integral
            document.endEditing(changed: true); windowPickMode = false; hoveredWindow = nil
            refreshSelection(); window?.makeFirstResponder(canvas); return
        }
        document.beginEditing(); dragStart = p; initialSelection = selection; selectionChanged = false
        if let rect = selection, let index = handle(at: p, in: rect) {
            resizeHandle = index; drawingSelection = false
        } else if let rect = selection, rect.contains(p) {
            resizeHandle = nil; drawingSelection = false; NSCursor.closedHand.set()
        } else {
            resizeHandle = nil; drawingSelection = true; document.select(nil); document.tool = .select
            document.captureRegion = nil
        }
        refreshSelection()
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        let raw = convert(event.locationInWindow, from: nil)
        let p = CGPoint(x: min(bounds.maxX, max(0, raw.x)), y: min(bounds.maxY, max(0, raw.y)))
        var rect: CGRect
        if drawingSelection {
            rect = CGRect(x: min(start.x,p.x), y: min(start.y,p.y), width: abs(start.x-p.x), height: abs(start.y-p.y)).intersection(bounds)
        } else if let initial = initialSelection, let index = resizeHandle {
            var left = initial.minX, right = initial.maxX, bottom = initial.minY, top = initial.maxY
            if [0,6,7].contains(index) { left = min(p.x,right-8) }
            if [2,3,4].contains(index) { right = max(p.x,left+8) }
            if [0,1,2].contains(index) { bottom = min(p.y,top-8) }
            if [4,5,6].contains(index) { top = max(p.y,bottom+8) }
            rect = CGRect(x: left, y: bottom, width: right-left, height: top-bottom)
        } else if let initial = initialSelection {
            rect = CGRect(x: min(bounds.width-initial.width, max(0, initial.minX+raw.x-start.x)),
                          y: min(bounds.height-initial.height, max(0, initial.minY+raw.y-start.y)), width: initial.width, height: initial.height)
        } else { return }
        guard !rect.isNull else { return }
        document.captureRegion = pixels(rect); selectionChanged = document.captureRegion != initialSelection.map(pixels)
        refreshSelection()
    }
    override func mouseUp(with event: NSEvent) {
        guard dragStart != nil else { return }
        mouseDragged(with: event)
        if let rect = document.captureRegion, rect.width >= 8, rect.height >= 8 {
            document.captureRegion = rect.integral.intersection(CGRect(x: 0, y: 0, width: snapshot.width, height: snapshot.height))
            document.endEditing(changed: selectionChanged)
        } else { document.cancelEditing() }
        dragStart = nil; resizeHandle = nil; drawingSelection = false
        refreshSelection()
        if selection != nil { window?.makeFirstResponder(canvas) }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?(); return }
        if event.keyCode == 36 || event.keyCode == 76 { if selection != nil { onComplete?() }; return }
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" {
            if event.modifierFlags.contains(.shift) { document.redo() } else { document.undo() }
            refreshSelection(); return
        }
        super.keyDown(with: event)
    }
    func reselect() {
        document.commitTextEditing(); document.beginEditing(); document.captureRegion = nil; document.select(nil)
        document.tool = .select; document.endEditing(changed: true); refreshSelection()
        window?.makeFirstResponder(self)
    }
    private func windowRect(at point: CGPoint) -> CGRect? {
        windowCandidates.first { $0.contains(point) }
    }
    func selectedDocument() -> AnnotationDocument? {
        canvas.commitInlineTextEditing()
        document.commitTextEditing()
        guard let region = document.captureRegion?.integral, region.width >= 8, region.height >= 8,
              let cropped = snapshot.cropping(to: CGRect(x: region.minX, y: CGFloat(snapshot.height)-region.maxY,
                                                        width: region.width, height: region.height)) else { return nil }
        let result = AnnotationDocument(image: NSImage(cgImage: cropped, size: NSSize(width: cropped.width, height: cropped.height)))
        result.marks = document.marks.map { mark in
            var moved = mark; moved.points = mark.points.map { CGPoint(x: $0.x-region.minX, y: $0.y-region.minY) }; return moved
        }
        result.tool = document.tool; result.color = document.color; result.lineWidth = document.lineWidth
        return result
    }
}

private final class RegionCaptureChrome: NSView {
    weak var workspace: RegionCaptureWorkspace?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func draw(_ dirtyRect: NSRect) { workspace?.drawChrome() }
}

final class RegionAnnotationCanvas: CanvasView {
    weak var workspace: RegionCaptureWorkspace?
    private var movingBoundary = false
    override func mouseDown(with event: NSEvent) {
        if workspace?.spaceToMove == true || (document.tool == .select && !hitsAnnotation(with: event)) {
            if event.clickCount == 2 { workspace?.onComplete?(); return }
            movingBoundary = true; workspace?.mouseDown(with: event); return
        }
        super.mouseDown(with: event)
    }
    override func mouseDragged(with event: NSEvent) {
        if movingBoundary { workspace?.mouseDragged(with: event) } else { super.mouseDragged(with: event) }
    }
    override func mouseUp(with event: NSEvent) {
        if movingBoundary { movingBoundary = false; workspace?.mouseUp(with: event) } else { super.mouseUp(with: event) }
    }
    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        if workspace?.spaceToMove == true || (document.tool == .select && !hitsAnnotation(with: event)) { NSCursor.openHand.set() }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { workspace?.onCancel?(); return }
        if event.keyCode == 36 || event.keyCode == 76 { workspace?.onComplete?(); return }
        super.keyDown(with: event)
    }
}

private struct RegionCaptureToolbar: View {
    @ObservedObject var document: AnnotationDocument
    let pixelScale: CGFloat
    let reselect: () -> Void
    let complete: () -> Void
    let cancel: () -> Void
    private let tools: [MarkTool] = [.select, .rectangle, .ellipse, .arrow, .line, .pen, .text, .fill, .redact]
    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 5) {
                ForEach(tools) { tool in
                    Button { document.tool = tool; document.select(nil) } label: {
                        Group {
                            if tool == .text { Text("T").font(.system(size: 16, weight: .semibold, design: .serif)) }
                            else { Image(systemName: tool.icon) }
                        }.frame(width: 23, height: 22)
                            .foregroundColor(document.interactionTool == tool ? .accentColor : .primary)
                    }.help(tool == .select ? "移动选区；悬停标注移动或缩放" : tool.rawValue).accessibilityLabel(tool.rawValue)
                }
                Divider().frame(height: 22)
                Button { document.undo() } label: { Image(systemName: "arrow.uturn.backward").frame(width: 18) }
                    .help("撤销 ⌘Z").disabled(!document.canUndo)
                    .accessibilityLabel("撤销")
                Button { document.redo() } label: { Image(systemName: "arrow.uturn.forward").frame(width: 18) }
                    .help("重做 ⇧⌘Z").disabled(!document.canRedo)
                    .accessibilityLabel("重做")
                Spacer(minLength: 0)
                Button("取消", action: cancel)
                Button("完成并复制", action: complete).buttonStyle(RegionCaptureCompleteStyle())
            }
            HStack(spacing: 8) {
                ForEach(Array([NSColor.systemRed, .systemYellow, .systemGreen, .systemBlue, .white, .black].enumerated()), id: \.offset) { index, color in
                    Button {
                        document.color = Color(color); document.applyStyle()
                    } label: {
                        Circle().fill(Color(color)).frame(width: 15, height: 15)
                            .overlay(Circle().stroke(Color.primary.opacity(0.3), lineWidth: 1))
                            .padding(3)
                    }.buttonStyle(.plain).accessibilityLabel(["红色","黄色","绿色","蓝色","白色","黑色"][index])
                }
                Text(document.selected?.tool == .text || document.tool == .text ? "字号" : "粗细")
                    .font(.system(size: 10)).foregroundColor(.secondary)
                Slider(value: Binding(get: { document.lineWidth / pixelScale }, set: { document.lineWidth = $0 * pixelScale }),
                       in: 1...12, onEditingChanged: { editing in if !editing { document.applyStyle() } }).frame(width: 74)
                    .accessibilityLabel("标注大小")
                Spacer(minLength: 0)
                Button("重新框选", action: reselect).controlSize(.small)
            }
            Text(document.editingTextID != nil ? "双击文字原位编辑 · 点击其他位置保存 · Esc 取消编辑" :
                 "拖动边缘或控制点调整选区 · 空格拖动移动选区 · 悬停标注可修改 · Enter 完成")
                .font(.system(size: 10)).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }.padding(10).buttonStyle(.bordered).controlSize(.small)
    }
}

private struct RegionCaptureCompleteStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .background(Color.accentColor.opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
