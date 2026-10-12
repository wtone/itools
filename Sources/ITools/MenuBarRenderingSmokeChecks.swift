import AppKit
import IToolsCore

enum MenuBarRenderingSmokeChecks {
    static func run(destination: URL) throws {
        func firstInk(_ bitmap: NSBitmapImageRep, rows: Range<Int>) -> Int? {
            for x in 0..<bitmap.pixelsWide {
                if rows.contains(where: { (bitmap.colorAt(x: x, y: $0)?.alphaComponent ?? 0) > 0.3 }) { return x }
            }
            return nil
        }
        let centered = MenuBarMonitor.image(for: MenuBarReading(top: "↑ 0 B/s", bottom: "↓ 999 MB/s", tooltip: ""), width: MenuBarMonitor.imageWidth(for: .network), metric: .network, leftAligned: false)
        guard let cg = centered.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw UserFacingError("Smoke: centered comparison missing") }
        let comparison = NSBitmapImageRep(cgImage: cg)
        guard let a = firstInk(comparison, rows: 0..<(cg.height / 2)), let b = firstInk(comparison, rows: (cg.height / 2)..<cg.height), abs(a - b) > 1 else {
            throw UserFacingError("Smoke: pixel regression does not distinguish centered from left-aligned rows")
        }
        for (index, pair) in [("↑ 0 B/s", "↓ 999 MB/s"), ("↑ 7.1 KB/s", "↓ 18 KB/s"), ("↑ 999 GB/s", "↓ 1.0 KB/s")].enumerated() {
            let reading = MenuBarReading(top: pair.0, bottom: pair.1, tooltip: "")
            let image = MenuBarMonitor.image(for: reading, width: MenuBarMonitor.imageWidth(for: .network), metric: .network)
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw UserFacingError("Smoke: network render missing") }
            let bitmap = NSBitmapImageRep(cgImage: cg), middle = cg.height / 2
            guard let first = firstInk(bitmap, rows: 0..<middle), let second = firstInk(bitmap, rows: middle..<cg.height),
                  abs(first - second) <= 1, first <= 3 else {
                throw UserFacingError("Smoke: upload/download are not left aligned at a stable origin")
            }
            if index == 1, let png = bitmap.representation(using: .png, properties: [:]) {
                try png.write(to: destination.appendingPathComponent("network-left-aligned.png"))
            }
        }
        var snapshot = MonitorSnapshot(); snapshot.cpu = 13; snapshot.memoryAvailable = true
        snapshot.memoryUsed = 79; snapshot.memoryTotal = 100; snapshot.gpu = 2
        snapshot.diskFree = 82; snapshot.diskTotal = 100; snapshot.networkAvailable = true
        snapshot.upload = 7100; snapshot.download = 18000; snapshot.cpuTemperature = 48.7
        snapshot.cpuTemperatureIsCoreMaximum = true; snapshot.fan = 0; snapshot.fan2 = 0
        let metrics: [MenuBarMetric] = [.cpu, .memory, .gpu, .disk, .network]
        let width = 16 + metrics.reduce(CGFloat(0)) { $0 + MenuBarMonitor.metricGap + MenuBarMonitor.imageWidth(for: $1) }
        guard width + 16 <= 282 else { throw UserFacingError("Smoke: common menu-bar metrics exceed compact width budget") }
        let preview = NSImage(size: NSSize(width: width + 16, height: 34))
        preview.lockFocus(); NSColor.white.setFill(); NSRect(x: 0, y: 0, width: width + 16, height: 34).fill()
        NSImage(systemSymbolName: "square.stack.3d.up", accessibilityDescription: nil)?.draw(in: NSRect(x: 8, y: 9, width: 16, height: 16))
        var x: CGFloat = 8 + 16
        for metric in metrics {
            x += MenuBarMonitor.metricGap
            let image = MenuBarMonitor.image(for: .make(metric, snapshot: snapshot, running: true), width: MenuBarMonitor.imageWidth(for: metric), metric: metric)
            image.draw(in: NSRect(x: x, y: 6, width: image.size.width, height: 22)); x += image.size.width
        }
        preview.unlockFocus()
        guard let png = preview.png else { throw UserFacingError("Smoke: compact preview missing") }
        try png.write(to: destination.appendingPathComponent("menu-bar-compact.png"))
        guard MenuBarReading.make(.fan, snapshot: snapshot, running: true).top == "0",
              MenuBarReading.make(.temperature, snapshot: snapshot, running: true).top == "49°" else {
            throw UserFacingError("Smoke: real zero RPM or temperature incorrectly shown as unavailable")
        }
        print("PASS: native equal column gaps; network rows share a left origin across rate widths; real zero RPM and temperature rendered")
    }
}
