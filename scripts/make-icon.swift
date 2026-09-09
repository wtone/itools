import AppKit
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
        let transform = NSAffineTransform(); transform.scale(by: CGFloat(pixels)/512); transform.concat()
        NSColor(calibratedRed: 0.13, green: 0.32, blue: 0.70, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 20, y: 20, width: 472, height: 472), xRadius: 106, yRadius: 106).fill()
        NSColor.white.setStroke()
        let handle = NSBezierPath(roundedRect: NSRect(x: 197, y: 301, width: 118, height: 64), xRadius: 18, yRadius: 18)
        handle.lineWidth = 20; handle.stroke()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: 104, y: 142, width: 304, height: 178), xRadius: 30, yRadius: 30).fill()
        NSColor(calibratedRed: 0.13, green: 0.32, blue: 0.70, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 104, y: 231, width: 304, height: 12)).fill()
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: 233, y: 213, width: 46, height: 45), xRadius: 9, yRadius: 9).fill()
        NSGraphicsContext.restoreGraphicsState()
        let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
    }
}
