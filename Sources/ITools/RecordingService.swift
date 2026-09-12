import AppKit
import AVFoundation
import Combine
import ImageIO
import UniformTypeIdentifiers

final class RecordingService: NSObject, ObservableObject, AVCaptureFileOutputRecordingDelegate {
    enum State: String { case idle = "未录制", preparing = "准备中", recording = "录制中", paused = "已暂停", stopping = "正在保存" }
    @Published var state: State = .idle
    @Published var elapsed: TimeInterval = 0
    @Published var microphone = false
    @Published var deviceID = ""
    @Published var fps = 30
    @Published var showCursor = true
    @Published var latest: URL?
    @Published var converting = false
    private let queue = DispatchQueue(label: "itools.recording", qos: .userInitiated)
    private var session: AVCaptureSession?
    private var output: AVCaptureFileOutput?
    private var ticker: Timer?
    private var started: Date?
    private var pausedAt: Date?
    private var pausedDuration: TimeInterval = 0
    private var currentURL: URL?
    private var observer: NSObjectProtocol?
    var audioDevices: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInMicrophone, .externalUnknown], mediaType: .audio, position: .unspecified).devices
    }
    var isActive: Bool { state != .idle }
    func start(audioOnly: Bool = false, region: CGRect? = nil, displayID: CGDirectDisplayID = CGMainDisplayID()) {
        guard state == .idle else { return }
        guard audioOnly || Permissions.requireScreen() else { return }
        guard let destination = Panels.save(name: "iTools-" + CaptureService.timestamp() + (audioOnly ? ".m4a" : ".mov"), types: [audioOnly ? "m4a" : "mov"]) else { return }
        // AVCapture outputs require an absent destination. NSSavePanel has already confirmed any replacement;
        // record to a unique sibling, then replace the chosen file only after a successful recording.
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".itools-recording-" + UUID().uuidString + (audioOnly ? ".m4a" : ".mov"))
        state = .preparing
        let useAudio = audioOnly || microphone
        let prepare = { [weak self] in
            guard let self = self else { return }
            let selected = self.deviceID, fps = self.fps, cursor = self.showCursor
            self.currentURL = destination
            self.queue.async {
                do {
                    let session = AVCaptureSession(); session.beginConfiguration()
                    if !audioOnly {
                        guard let screen = AVCaptureScreenInput(displayID: displayID) else { throw UserFacingError("所选显示器不可录制。") }
                        screen.minFrameDuration = CMTime(value: 1, timescale: Int32(fps))
                        screen.capturesCursor = cursor; screen.capturesMouseClicks = cursor
                        if let region = region { screen.cropRect = region }
                        guard session.canAddInput(screen) else { throw UserFacingError("无法配置屏幕录制输入。") }
                        session.addInput(screen)
                        if session.canSetSessionPreset(.high) { session.sessionPreset = .high }
                    }
                    if useAudio {
                        let device = self.audioDevices.first { $0.uniqueID == selected } ?? AVCaptureDevice.default(for: .audio)
                        guard let device = device else { throw UserFacingError("未找到音频输入设备。请连接麦克风或虚拟音频设备。") }
                        let input = try AVCaptureDeviceInput(device: device)
                        guard session.canAddInput(input) else { throw UserFacingError("所选音频设备无法录制。") }
                        session.addInput(input)
                    }
                    let fileOutput: AVCaptureFileOutput = audioOnly ? AVCaptureAudioFileOutput() : AVCaptureMovieFileOutput()
                    guard session.canAddOutput(fileOutput) else { throw UserFacingError("无法创建录制文件。") }
                    session.addOutput(fileOutput); session.commitConfiguration()
                    self.session = session; self.output = fileOutput
                    self.observer = NotificationCenter.default.addObserver(forName: .AVCaptureSessionRuntimeError, object: session, queue: .main) { [weak self] note in
                        if let error = note.userInfo?[AVCaptureSessionErrorKey] as? Error { NoticeCenter.shared.report(error) }
                        self?.stop()
                    }
                    session.startRunning()
                    if let audio = fileOutput as? AVCaptureAudioFileOutput {
                        audio.startRecording(to: temporary, outputFileType: .m4a, recordingDelegate: self)
                    } else if let movie = fileOutput as? AVCaptureMovieFileOutput {
                        movie.startRecording(to: temporary, recordingDelegate: self)
                    }
                } catch {
                    self.cleanup()
                    DispatchQueue.main.async { self.state = .idle; NoticeCenter.shared.report(error) }
                }
            }
        }
        if useAudio {
            AVCaptureDevice.requestAccess(for: .audio) { allowed in
                DispatchQueue.main.async {
                    if allowed { prepare() }
                    else { self.state = .idle; PermissionCenter.shared.show(.microphone, operation: "录音") }
                }
            }
        } else { prepare() }
    }
    func selectRegion() {
        guard state == .idle, Permissions.requireScreen() else { return }
        RegionSelector.shared.select { [weak self] id, rect in self?.start(region: rect, displayID: id) }
    }
    func pauseResume() {
        guard state == .recording || state == .paused else { return }
        if state == .recording {
            state = .paused; pausedAt = Date(); queue.async { self.output?.pauseRecording() }
        } else {
            if let pause = pausedAt { pausedDuration += Date().timeIntervalSince(pause) }
            pausedAt = nil; state = .recording; queue.async { self.output?.resumeRecording() }
        }
    }
    func stop() {
        guard state == .recording || state == .paused else { return }
        state = .stopping; ticker?.invalidate(); ticker = nil
        queue.async { self.output?.stopRecording() }
    }
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        DispatchQueue.main.async {
            self.state = .recording; self.started = Date(); self.pausedDuration = 0; self.elapsed = 0
            self.ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self = self, self.state == .recording, let start = self.started else { return }
                self.elapsed = Date().timeIntervalSince(start) - self.pausedDuration
            }
        }
    }
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        let successful = error == nil || (error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true
        queue.async {
            self.cleanup()
            DispatchQueue.main.async {
                self.ticker?.invalidate(); self.ticker = nil; self.state = .idle
                if successful, let destination = self.currentURL {
                    do {
                        if FileManager.default.fileExists(atPath: destination.path) {
                            _ = try FileManager.default.replaceItemAt(destination, withItemAt: outputFileURL)
                        } else { try FileManager.default.moveItem(at: outputFileURL, to: destination) }
                        self.latest = destination; NoticeCenter.shared.success("录制已保存：" + destination.lastPathComponent)
                    } catch { self.latest = outputFileURL; NoticeCenter.shared.report(UserFacingError("录制已保留于 \(outputFileURL.path)，但移动到目标位置失败：\(error.localizedDescription)")) }
                } else {
                    // Keep partial output available for recovery instead of deleting potentially valuable content.
                    self.latest = FileManager.default.fileExists(atPath: outputFileURL.path) ? outputFileURL : nil
                    NoticeCenter.shared.report(error ?? UserFacingError("录制失败，请检查磁盘空间与权限。"))
                }
            }
        }
    }
    private func cleanup() {
        session?.stopRunning(); session = nil; output = nil
        if let observer = observer { NotificationCenter.default.removeObserver(observer); self.observer = nil }
    }
    func convertGIF() {
        guard !converting, let input = Panels.chooseFiles(types: ["mov", "mp4", "m4v"], multiple: false).first,
              let url = Panels.save(name: input.deletingPathExtension().lastPathComponent + ".gif", types: ["gif"]) else { return }
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".itools-gif-" + UUID().uuidString + ".gif")
        converting = true
        queue.async {
            do {
                let asset = AVURLAsset(url: input); let duration = CMTimeGetSeconds(asset.duration)
                guard duration.isFinite, duration > 0, duration <= 30 else { throw UserFacingError("GIF 转换支持 30 秒以内的视频，请先裁剪。") }
                let generator = AVAssetImageGenerator(asset: asset); generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 720, height: 720)
                let frameCount = max(1, Int(ceil(duration * 10)))
                guard let destination = CGImageDestinationCreateWithURL(temporary as CFURL, UTType.gif.identifier as CFString, frameCount, nil) else { throw UserFacingError("无法创建 GIF 文件。") }
                CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
                for index in 0..<frameCount {
                    let image = try generator.copyCGImage(at: CMTime(seconds: Double(index)/10, preferredTimescale: 600), actualTime: nil)
                    CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary)
                }
                guard CGImageDestinationFinalize(destination) else { throw UserFacingError("GIF 编码失败，请检查存储空间。") }
                if FileManager.default.fileExists(atPath: url.path) { _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary) }
                else { try FileManager.default.moveItem(at: temporary, to: url) }
                DispatchQueue.main.async { self.converting = false; self.latest = url; NoticeCenter.shared.success("GIF 已导出（10 fps，最长边 720px）") }
            } catch { try? FileManager.default.removeItem(at: temporary); DispatchQueue.main.async { self.converting = false }; NoticeCenter.shared.report(error) }
        }
    }
    func exportVideo(trim: Bool) {
        guard !converting, let input = Panels.chooseFiles(types: ["mov", "mp4", "m4v"], multiple: false).first else { return }
        let asset = AVURLAsset(url: input)
        var range: CMTimeRange?
        if trim {
            guard let from = Panels.text("开始秒数", initial: "0"), let start = Double(from),
                  let to = Panels.text("结束秒数", initial: String(format: "%.1f", CMTimeGetSeconds(asset.duration))), let end = Double(to),
                  start.isFinite, end.isFinite, start >= 0, end > start, end <= CMTimeGetSeconds(asset.duration) else { return }
            range = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 600), duration: CMTime(seconds: end-start, preferredTimescale: 600))
        }
        guard let destination = Panels.save(name: "Export-" + CaptureService.timestamp() + ".mp4", types: ["mp4"]),
              let exporter = AVAssetExportSession(asset: asset, presetName: trim ? AVAssetExportPresetHighestQuality : AVAssetExportPreset1280x720) else { return }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".itools-export-" + UUID().uuidString + ".mp4")
        exporter.outputURL = temporary; exporter.outputFileType = .mp4; exporter.shouldOptimizeForNetworkUse = true
        if let range = range { exporter.timeRange = range }
        converting = true
        exporter.exportAsynchronously {
            DispatchQueue.main.async {
                self.converting = false
                if exporter.status == .completed {
                    NoticeCenter.shared.perform {
                        if FileManager.default.fileExists(atPath: destination.path) { _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary) }
                        else { try FileManager.default.moveItem(at: temporary, to: destination) }
                        self.latest = destination; NoticeCenter.shared.success("视频已导出")
                    }
                } else { NoticeCenter.shared.report(exporter.error ?? UserFacingError("视频导出失败。")); try? FileManager.default.removeItem(at: temporary) }
            }
        }
    }
}
final class RegionSelector {
    static let shared = RegionSelector()
    private var window: NSWindow?
    func select(completion: @escaping (CGDirectDisplayID, CGRect) -> Void) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main,
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 else { return }
        let hidden = NSApp.windows.filter { $0.isVisible }
        hidden.forEach { $0.orderOut(nil) }
        let window = SelectionWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .screenSaver; window.isOpaque = false; window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        let view = RegionView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.complete = { [weak self] rect in
            self?.window?.close(); self?.window = nil
            hidden.forEach { $0.orderFront(nil) }; NSApp.activate(ignoringOtherApps: true)
            guard let rect = rect, rect.width > 4, rect.height > 4 else { return }
            let factor = screen.backingScaleFactor
            completion(id, CGRect(x: rect.minX*factor, y: rect.minY*factor, width: rect.width*factor, height: rect.height*factor).integral)
        }
        window.contentView = view; self.window = window
        window.makeKeyAndOrderFront(nil); window.makeFirstResponder(view); NSApp.activate(ignoringOtherApps: true)
    }
}
final class SelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
final class RegionView: NSView {
    var complete: ((CGRect?) -> Void)?
    private var start: CGPoint?
    private var end: CGPoint?
    override var acceptsFirstResponder: Bool { true }
    private var selection: CGRect? {
        guard let a = start, let b = end else { return nil }
        return CGRect(x: min(a.x,b.x), y: min(a.y,b.y), width: abs(a.x-b.x), height: abs(a.y-b.y))
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.3).setFill(); bounds.fill()
        if let rect = selection { NSColor.systemBlue.setStroke(); let path = NSBezierPath(rect: rect); path.lineWidth = 2; path.stroke() }
        ("拖动选择录制区域 · Esc 取消" as NSString).draw(at: CGPoint(x: 30, y: bounds.height-60), withAttributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 22, weight: .semibold)])
    }
    override func mouseDown(with event: NSEvent) { start = convert(event.locationInWindow, from: nil); end = start; needsDisplay = true }
    override func mouseDragged(with event: NSEvent) { end = convert(event.locationInWindow, from: nil); needsDisplay = true }
    override func mouseUp(with event: NSEvent) { end = convert(event.locationInWindow, from: nil); complete?(selection?.intersection(bounds)) }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { complete?(nil) } }
}
