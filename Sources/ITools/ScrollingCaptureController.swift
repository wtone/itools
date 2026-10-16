import AppKit
import SwiftUI
import IToolsCore

/// A single selection stays locked while the target application continues receiving scrolling.
final class ScrollingCaptureController: ObservableObject {
    enum Mode: String, CaseIterable { case automatic = "自动滚动", manual = "手动滚动" }
    struct Output { let image: NSImage; let frames: Int }
    @Published var mode: Mode = .automatic
    @Published private(set) var started = false
    @Published private(set) var paused = false
    @Published private(set) var processing = false
    @Published private(set) var finishing = false
    @Published private(set) var count = 0
    @Published private(set) var height = 0
    @Published private(set) var message = "框选一次，连续捕获整个滚动区域"
    @Published private(set) var preview: NSImage?
    @Published var slow = false
    private var toolbar: NSPanel?
    private var overlay: CaptureRegionOverlay?
    private var timer: Timer?
    private var globalKeyMonitor: Any?
    private var localKeyMonitor: Any?
    private var target: NSRunningApplication?
    private var targetWindows: [CaptureWindowTarget] = []
    private var displaySnapshot: [CaptureDisplayGeometry] = []
    private var screenObserver: NSObjectProtocol?
    private var selectionSession: UUID?
    private var captureRect = CGRect.zero
    private var stitcher = ScrollingStitcher()
    private var generation = 0
    private var idleFrames = 0
    private var missedFrames = 0
    private var finalSample = false
    private var pausedForOcclusion = false
    private var nextSampleAt = Date.distantPast
    private var startedAt = Date()
    private let queue = DispatchQueue(label: "app.itools.scrolling-capture", qos: .userInitiated)
    private let frameProvider: (CGRect, CGWindowID) -> CGImage?
    private let simulatedScroll: (() -> Void)?
    private let synthetic: Bool
    private var completion: ((Output?) -> Void)?

    init(frameProvider: ((CGRect, CGWindowID) -> CGImage?)? = nil, simulatedScroll: (() -> Void)? = nil) {
        self.synthetic = frameProvider != nil; self.simulatedScroll = simulatedScroll
        self.frameProvider = frameProvider ?? { rect, anchor in
            CGWindowListCreateImage(rect, .optionOnScreenBelowWindow, anchor, [.bestResolution, .boundsIgnoreFraming])
        }
    }

    /// Drive the real asynchronous sampling/timer/finalization path without showing windows or reading the desktop.
    func prepareSyntheticCheck(mode: Mode, completion: @escaping (Output?) -> Void) {
        precondition(synthetic && ProcessInfo.processInfo.arguments.contains("--smoke-test"))
        self.mode = mode; self.completion = completion
        displaySnapshot = NSScreen.screens.compactMap(\.captureGeometry)
        guard let display = displaySnapshot.first else { cancel(); return }
        let selection = CGRect(x: display.frame.minX + 16, y: display.frame.minY + 16, width: 160, height: 120)
        captureRect = CaptureDisplayGeometry.quartzRect(fromGlobal: selection, primaryTop: displaySnapshot[0].frame.maxY)
        overlay = CaptureRegionOverlay(displays: displaySnapshot, selectedDisplayID: display.id, selection: selection)
        sample()
    }

    func select(automatic: Bool, completion: @escaping (Output?) -> Void) {
        self.completion = completion
        mode = automatic && Permissions.accessibility ? .automatic : .manual
        NSApp.hide(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self, self.completion != nil else { return }
            self.targetWindows = Self.visibleTargetWindows()
            self.selectionSession = RegionSelector.shared.select(prompt: "在任意屏幕框选滚动内容 · Esc 取消", restoreWindows: false,
                                         cancelled: { [weak self] in self?.cancel() }) { [weak self] id, pixels in
                self?.selectionSession = nil
                self?.prepare(displayID: id, pixels: pixels)
            }
        }
    }
    private func prepare(displayID: CGDirectDisplayID, pixels: CGRect) {
        guard let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32) == displayID }) else { cancel(); return }
        guard let geometry = screen.captureGeometry, let selected = geometry.globalPoints(from: pixels) else { cancel(); return }
        guard selected.width >= 80, selected.height >= 100 else {
            NoticeCenter.shared.report(UserFacingError("请框选至少 80 × 100 点的滚动内容区域。")); cancel(); return
        }
        displaySnapshot = NSScreen.screens.compactMap(\.captureGeometry)
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        captureRect = CaptureDisplayGeometry.quartzRect(fromGlobal: selected, primaryTop: primaryTop)
        target = Self.targetPID(at: CGPoint(x: captureRect.midX, y: captureRect.midY), windows: targetWindows)
            .flatMap { NSRunningApplication(processIdentifier: $0) }
        if target == nil { mode = .manual }
        targetWindows.removeAll()
        let overlay = CaptureRegionOverlay(displays: displaySnapshot, selectedDisplayID: displayID, selection: selected)
        self.overlay = overlay; overlay.show()
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 440, height: 176), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: CaptureRegionOverlay.level.rawValue + 1)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false; panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; panel.sharingType = .none
        panel.contentView = NSHostingView(rootView: ScrollingCaptureHUD(controller: self))
        let visible = screen.visibleFrame
        let below = selected.minY - panel.frame.height - 12
        let above = selected.maxY + 12
        let y = below >= visible.minY ? below : above + panel.frame.height <= visible.maxY ? above : visible.minY + 12
        panel.setFrameOrigin(CGPoint(x: min(max(selected.midX - 220, visible.minX + 8), visible.maxX - 448), y: y))
        toolbar = panel
        target?.activate(options: [.activateIgnoringOtherApps])
        panel.orderFrontRegardless()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                                                 object: nil, queue: .main) { [weak self] _ in
            guard let self = self, self.displaySnapshot != NSScreen.screens.compactMap(\.captureGeometry) else { return }
            self.message = "显示器布局已变化，保留当前结果"; self.finish(captureFinalFrame: false)
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }; DispatchQueue.main.async { self?.cancel() }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { self?.cancel(); return nil }
            return event
        }
        sample()
    }
    func begin() {
        guard !started, !processing, stitcher.last != nil else { return }
        if mode == .automatic && target == nil && !synthetic { mode = .manual }
        if mode == .automatic && !synthetic && !Permissions.requireEventPosting(operation: "长截图自动滚动") { mode = .manual; return }
        started = true; startedAt = Date(); message = mode == .automatic ? "正在自动滚动 · 到底后自动完成" : "在选区内向下滚动 · 无需重新框选"
        target?.activate(options: [.activateIgnoringOtherApps])
        if mode == .automatic { scroll() }
        let timer = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.tick() }
        self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func tick() {
        guard started, !processing, !finishing else { return }
        guard Date().timeIntervalSince(startedAt) < 180 else { message = "已达到捕获时长限制，保留当前结果"; finish(); return }
        guard displaySnapshot == NSScreen.screens.compactMap(\.captureGeometry) else { finish(captureFinalFrame: false); return }
        // Scrolling an inactive window or using another display does not activate its application.
        // Only pause if another application's window actually covers the selected content.
        if let targetPID = target?.processIdentifier,
           let owner = Self.targetPID(at: CGPoint(x: captureRect.midX, y: captureRect.midY), windows: Self.visibleTargetWindows()),
           owner != targetPID {
            if !paused { paused = true; pausedForOcclusion = true; message = "选区被其他窗口遮挡 · 返回后自动继续" }
            return
        }
        if pausedForOcclusion { pausedForOcclusion = false; paused = false; message = "选区已恢复，继续捕获" }
        guard !paused, Date() >= nextSampleAt else { return }
        sample()
    }
    private func sample() {
        guard !processing, let anchor = overlay?.captureAnchor else { return }
        processing = true
        let rect = captureRect, windowID = CGWindowID(anchor.windowNumber), token = generation, stitcher = self.stitcher, provider = frameProvider
        queue.async { [weak self] in
            // The entire mask window and everything above it are excluded; only the original content is captured.
            let cg = provider(rect, windowID)
            let frame = cg.flatMap(Self.frame)
            let result = frame.map { stitcher.append($0) }
            let previewFrame: ScrollFrame?
            if case .added? = result { previewFrame = stitcher.output } else { previewFrame = nil }
            let thumbnail: NSImage? = previewFrame.flatMap { frame in
                Self.image(frame).map { image in
                    let preview = NSImage(size: NSSize(width: 80, height: 100))
                    preview.lockFocus()
                    let size = image.size, factor = min(80 / size.width, 100 / size.height)
                    image.draw(in: CGRect(x: (80-size.width*factor)/2, y: (100-size.height*factor)/2, width: size.width*factor, height: size.height*factor))
                    preview.unlockFocus(); return preview
                }
            }
            DispatchQueue.main.async {
                guard let self = self, token == self.generation else { return }
                self.processing = false
                guard let result = result else {
                    self.message = "无法读取选区，请检查屏幕录制权限"; self.paused = true
                    if self.finishing { self.completeOutput() }
                    return
                }
                self.count = stitcher.count; self.height = stitcher.height
                switch result {
                case .added:
                    self.idleFrames = 0; self.missedFrames = 0; self.preview = thumbnail
                    self.message = self.started ? (self.mode == .automatic ? "正在自动滚动 · 到底后自动完成" : "连续捕获中 · 在透明选区向下滚动") : "选区已锁定 · 点击开始捕获后，在透明区域滚动"
                case .unchanged: self.idleFrames += 1
                case .unmatched, .reversed:
                    self.missedFrames += 1; self.idleFrames = 0
                    self.message = result == .reversed ? "请向下滚动；当前结果已保留" : "滚动过快或内容变化 · 请回滚少许后缓慢向下"
                    if self.mode == .automatic && (self.missedFrames >= 3 || result == .reversed) {
                        self.mode = .manual; self.nextSampleAt = .distantPast
                        self.message = "已转为手动捕获 · 请回滚少许后缓慢向下，仍在持续捕获"
                    }
                case .limit:
                    self.message = "长图已达到大小限制，保留当前结果"; self.finishing = true; self.finalSample = true
                }
                if self.finishing {
                    if self.finalSample { self.completeOutput() } else { self.sampleFinalFrame() }
                    return
                }
                if self.started && !self.paused && self.mode == .automatic {
                    if self.idleFrames >= 4 {
                        if self.count <= 1 {
                            self.mode = .manual; self.nextSampleAt = .distantPast
                            self.message = "尚未追加滚动画面 · 已转手动捕获，请在透明选区内滚动"
                        } else { self.completeOutput() }
                        return
                    }
                    // Retry a transient/animating frame before sending another scroll event.
                    switch result { case .added, .unchanged: self.scroll(); default: self.nextSampleAt = Date().addingTimeInterval(0.12) }
                }
            }
        }
    }
    private func scroll() {
        if let simulatedScroll = simulatedScroll {
            nextSampleAt = Date().addingTimeInterval(0.45); simulatedScroll(); return
        }
        guard let target = target, !target.isTerminated else { paused = true; message = "目标应用已退出，请完成或取消"; return }
        let distance = min(400, Int(captureRect.height * (slow ? 0.20 : 0.38)))
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -Int32(max(12, distance)), wheel2: 0, wheel3: 0) else { return }
        event.location = CGPoint(x: captureRect.midX, y: captureRect.midY)
        nextSampleAt = Date().addingTimeInterval(0.45)
        event.postToPid(target.processIdentifier)
    }
    func togglePause() {
        guard started, !finishing else { return }
        if paused && mode == .automatic && !Permissions.requireEventPosting(operation: "长截图自动滚动") { return }
        paused.toggle(); pausedForOcclusion = false; idleFrames = 0; nextSampleAt = .distantPast
        if !paused { target?.activate(options: [.activateIgnoringOtherApps]); message = "继续捕获 · 保持在同一个滚动区域" }
    }
    func finish(captureFinalFrame: Bool = true) {
        guard completion != nil, !finishing else { return }
        finishing = true; finalSample = !captureFinalFrame
        timer?.invalidate(); timer = nil; message = "正在拼接最后一帧…"
        if processing { return }
        if captureFinalFrame { sampleFinalFrame() } else { completeOutput() }
    }
    private func sampleFinalFrame() {
        finalSample = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self = self, self.completion != nil, self.finishing else { return }
            if self.overlay?.captureAnchor == nil { self.completeOutput() } else { self.sample() }
        }
    }
    private func completeOutput() {
        let output = stitcher.output.flatMap(Self.image).map { Output(image: $0, frames: stitcher.count) }
        let callback = completion; completion = nil; close(); callback?(output)
    }
    func cancel() {
        let callback = completion; completion = nil; generation += 1
        let session = selectionSession; selectionSession = nil
        if let session = session { RegionSelector.shared.cancel(sessionID: session) }
        close(); callback?(nil)
    }
    private func close() {
        timer?.invalidate(); timer = nil
        if let monitor = globalKeyMonitor { NSEvent.removeMonitor(monitor) }; globalKeyMonitor = nil
        if let monitor = localKeyMonitor { NSEvent.removeMonitor(monitor) }; localKeyMonitor = nil
        if let observer = screenObserver { NotificationCenter.default.removeObserver(observer) }; screenObserver = nil
        toolbar?.close(); toolbar = nil; overlay?.close(); overlay = nil
        targetWindows.removeAll()
    }
    struct CaptureWindowTarget {
        let pid: pid_t
        let bounds: CGRect
    }
    static func targetPID(at point: CGPoint, windows: [CaptureWindowTarget]) -> pid_t? {
        windows.first { $0.bounds.contains(point) }?.pid
    }
    private static func visibleTargetWindows() -> [CaptureWindowTarget] {
        guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return windows.compactMap { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32, pid != ProcessInfo.processInfo.processIdentifier,
                  window[kCGWindowLayer as String] as? Int == 0,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let rawBounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: rawBounds) else { return nil }
            return CaptureWindowTarget(pid: pid, bounds: bounds)
        }
    }
    static func frame(_ image: CGImage) -> ScrollFrame? {
        guard image.width * image.height <= 80_000_000 else { return nil }
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let valid = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                          bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height)); return true
        }
        return valid ? ScrollFrame(width: image.width, height: image.height, rgba: bytes) : nil
    }
    static func image(_ frame: ScrollFrame) -> NSImage? {
        guard let provider = CGDataProvider(data: Data(frame.rgba) as CFData),
              let image = CGImage(width: frame.width, height: frame.height, bitsPerComponent: 8, bitsPerPixel: 32,
                                  bytesPerRow: frame.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider,
                                  decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: frame.width, height: frame.height))
    }
    deinit { close() }
}

struct ScrollingCaptureHUD: View {
    @ObservedObject var controller: ScrollingCaptureController
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 5) {
                if let image = controller.preview { Image(nsImage: image).resizable().scaledToFit().frame(width: 66, height: 100) }
                else { Image(systemName: "rectangle.dashed").font(.system(size: 28)).frame(width: 66, height: 100) }
                Text("\(controller.height) px").font(.system(size: 10)).monospacedDigit().foregroundColor(.secondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("滚动长截图", systemImage: "rectangle.expand.vertical").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(controller.count > 1 ? "已拼接 \(controller.count) 段" : controller.count == 1 ? "仅首帧 · 待滚动" : "准备中")
                        .font(.system(size: 10)).foregroundColor(controller.count == 1 && controller.started ? .orange : .secondary)
                }
                Picker("滚动方式", selection: $controller.mode) {
                    ForEach(ScrollingCaptureController.Mode.allCases, id: \.self) { mode in Text(mode.rawValue).tag(mode) }
                }.pickerStyle(.segmented).disabled(controller.started && !controller.paused)
                Text(controller.message).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(2).frame(height: 30, alignment: .leading)
                HStack(spacing: 8) {
                    Button("取消") { controller.cancel() }.help("Esc 取消，保留原剪贴板")
                    if controller.started {
                        Button(controller.paused ? "继续" : "暂停") { controller.togglePause() }
                        Spacer()
                        Button(controller.count > 1 ? "完成" : "保存当前区域") { controller.finish() }
                            .buttonStyle(.borderedProminent).disabled(controller.finishing)
                    } else {
                        Toggle("慢速", isOn: $controller.slow).toggleStyle(.checkbox).font(.system(size: 11))
                        Spacer()
                        Button("开始捕获") { controller.begin() }.buttonStyle(.borderedProminent).disabled(controller.processing || controller.count == 0)
                    }
                }.controlSize(.small)
            }
        }.padding(16).frame(width: 440, height: 176)
            .background(FrostedBackground()).cornerRadius(14)
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.08)))
    }
}
