import AppKit
import IToolsCore

enum ScrollingCaptureSmokeChecks {
    private final class Feed {
        private let lock = NSLock()
        private var image: CGImage
        var delay: TimeInterval = 0
        init(offset: Int = 0) { image = ScrollingCaptureSmokeChecks.image(offset: offset) }
        func set(_ image: CGImage) { lock.lock(); self.image = image; lock.unlock() }
        func read() -> CGImage {
            lock.lock(); let image = image, delay = delay; lock.unlock()
            if delay > 0 { Thread.sleep(forTimeInterval: delay) }
            return image
        }
    }
    private static func image(offset: Int, blank: Bool = false) -> CGImage {
        let width = 320, height = 240
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height { for x in 0..<width {
            let source = y < 30 ? y : x < 90 ? y + 20_000 : offset + y - 30
            let p = (y * width + x) * 4
            for channel in 0..<3 { bytes[p+channel] = blank ? 20 : UInt8((source * (channel * 6 + 7) + x * (channel * 4 + 3)) % 220 + 16) }
        } }
        return ScrollingCaptureController.image(ScrollFrame(width: width, height: height, rgba: bytes))!
            .cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }
    private static func wait(_ condition: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(4)
        while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        guard condition() else { throw UserFacingError("Smoke: scrolling controller did not advance in time") }
    }
    static func run(destination: URL) throws {
        try checkNativeLayout(destination: destination)
        let feed = Feed()
        let controller = ScrollingCaptureController(frameProvider: { _, _ in feed.read() })
        defer { controller.cancel() }
        var output: ScrollingCaptureController.Output?
        controller.prepareSyntheticCheck(mode: .manual) { output = $0 }
        try wait { controller.count == 1 && !controller.processing }
        controller.begin(); feed.set(image(offset: 65))
        try wait { controller.count == 2 && !controller.processing }
        feed.set(image(offset: 130))
        controller.finish() // Finish before the next timer tick: the final image must still be sampled.
        try wait { output != nil }
        guard output?.frames == 3, output?.image.size.height == 370 else { throw UserFacingError("Smoke: finish discarded the last scrolled viewport") }
        try output!.image.png!.write(to: destination.appendingPathComponent("scroll-session-final.png"))
        print("PASS: real manual capture timer adds scrolled frames with fixed sidebar; finishing samples the latest viewport before export")

        let recovery = Feed()
        let automatic = ScrollingCaptureController(frameProvider: { _, _ in recovery.read() }, simulatedScroll: { recovery.set(image(offset: 0, blank: true)) })
        defer { automatic.cancel() }
        var recovered: ScrollingCaptureController.Output?
        automatic.prepareSyntheticCheck(mode: .automatic) { recovered = $0 }
        try wait { automatic.count == 1 && !automatic.processing }
        automatic.begin()
        try wait { automatic.mode == .manual }
        guard !automatic.paused, automatic.started, automatic.count == 1 else { throw UserFacingError("Smoke: failed alignment permanently paused capture") }
        recovery.set(image(offset: 65))
        try wait { automatic.count == 2 && !automatic.processing }
        automatic.finish()
        try wait { recovered != nil }
        guard recovered?.frames == 2, recovered?.image.size.height == 305 else { throw UserFacingError("Smoke: manual fallback did not recover") }
        print("PASS: automatic transient failures retry, then continue sampling in manual mode; returning to overlap recovers the long image")

        let delayed = Feed(); delayed.delay = 0.12
        let pending = ScrollingCaptureController(frameProvider: { _, _ in delayed.read() })
        defer { pending.cancel() }
        var final: ScrollingCaptureController.Output?
        pending.prepareSyntheticCheck(mode: .manual) { final = $0 }
        try wait { pending.count == 1 && !pending.processing }
        pending.begin()
        try wait { pending.processing }
        delayed.set(image(offset: 65)); pending.finish()
        try wait { final != nil }
        guard final?.frames == 2, final?.image.size.height == 305 else { throw UserFacingError("Smoke: finish during sampling used a stale frame") }
        print("PASS: finishing during an in-flight sample waits and captures a fresh final frame; no desktop or general pasteboard accessed")
    }

    private static func checkNativeLayout(destination: URL) throws {
        let page = NSImage(size: NSSize(width: 1000, height: 6000))
        page.lockFocus()
        NSColor.white.setFill(); CGRect(x: 0, y: 0, width: 1000, height: 6000).fill()
        for section in 0..<30 {
            let y = CGFloat(6000 - 120 - (section+1)*190)
            NSColor(calibratedWhite: 0.96, alpha: 1).setFill()
            NSBezierPath(roundedRect: CGRect(x: 280, y: y, width: 680, height: 172), xRadius: 10, yRadius: 10).fill()
            ("Section \(section+1) / unique value \(section*137+41)" as NSString).draw(at: CGPoint(x: 306, y: y+116), withAttributes: [.font: NSFont.systemFont(ofSize: 24, weight: .semibold), .foregroundColor: NSColor.systemBlue])
            ("Continuous content with a fixed navigation sidebar." as NSString).draw(at: CGPoint(x: 306, y: y+70), withAttributes: [.font: NSFont.systemFont(ofSize: 19), .foregroundColor: NSColor.black])
            ("原生字体页面 · 完整保留后续滚动内容 · checksum \(section*section+29)" as NSString).draw(at: CGPoint(x: 306, y: y+30), withAttributes: [.font: NSFont.systemFont(ofSize: 17), .foregroundColor: NSColor.darkGray])
        }
        page.unlockFocus()
        let pageCG = page.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let fixed = NSImage(size: NSSize(width: 1000, height: 700))
        fixed.lockFocus()
        NSColor.white.setFill(); CGRect(x: 0, y: 0, width: 1000, height: 700).fill()
        NSColor(calibratedWhite: 0.94, alpha: 1).setFill(); CGRect(x: 0, y: 632, width: 1000, height: 68).fill()
        ("Fixed header · Settings" as NSString).draw(at: CGPoint(x: 26, y: 653), withAttributes: [.font: NSFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: NSColor.black])
        for item in 0..<11 {
            ("Navigation \(item+1)" as NSString).draw(at: CGPoint(x: 22, y: CGFloat(580-item*48)), withAttributes: [.font: NSFont.systemFont(ofSize: 19), .foregroundColor: NSColor.darkGray])
        }
        fixed.unlockFocus()
        let chrome = ScrollingCaptureController.frame(fixed.cgImage(forProposedRect: nil, context: nil, hints: nil)!)!
        let scale = pageCG.width / 1000, viewportHeight = chrome.height, sidebar = 250 * scale, header = 68 * scale
        let maximum = pageCG.height - viewportHeight
        var offsets = Array(stride(from: 0, through: maximum, by: 200 * scale))
        if offsets.last != maximum { offsets.append(maximum) }
        let stitcher = ScrollingStitcher()
        for offset in offsets {
            let slice = ScrollingCaptureController.frame(pageCG.cropping(to: CGRect(x: 0, y: offset, width: pageCG.width, height: viewportHeight))!)!
            var rgba = slice.rgba
            for y in 0..<viewportHeight {
                let start = y * pageCG.width * 4, length = (y < header ? pageCG.width : sidebar) * 4
                rgba.replaceSubrange(start..<start+length, with: chrome.rgba[start..<start+length])
            }
            guard case .added = stitcher.append(ScrollFrame(width: pageCG.width, height: viewportHeight, rgba: rgba)) else {
                throw UserFacingError("Smoke: native fixed-sidebar layout rejected scroll offset \(offset)")
            }
        }
        let original = ScrollingCaptureController.frame(pageCG)!, output = stitcher.output!
        guard output.height == pageCG.height else { throw UserFacingError("Smoke: fixed-sidebar long image stayed at first viewport") }
        for y in stride(from: header, to: output.height, by: 7) {
            let start = (y * output.width + sidebar) * 4, end = (y * output.width + output.width) * 4
            guard output.rgba[start..<end] == original.rgba[start..<end] else {
                throw UserFacingError("Smoke: native scrolling content has missing/repeated pixels at row \(y)")
            }
        }
        try ScrollingCaptureController.image(output)!.png!.write(to: destination.appendingPathComponent("fixed-sidebar-native-long.png"))
        print("PASS: native typography with fixed sidebar/header stitches \(stitcher.count) viewports into \(output.height) px; moving content matches original document pixels")
    }
}
