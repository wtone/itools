import Foundation

/// AppKit uses global points with a bottom-left origin; recording uses display-local
/// backing pixels, while window capture and scroll events use global top-left points.
public struct CaptureDisplayGeometry: Equatable {
    public let id: UInt32
    public let frame: CGRect
    public let scale: CGFloat

    public init(id: UInt32, frame: CGRect, scale: CGFloat) {
        self.id = id; self.frame = frame; self.scale = scale
    }

    public func localPixels(from points: CGRect) -> CGRect? {
        guard isValid, Self.valid(points) else { return nil }
        let clipped = points.standardized.intersection(CGRect(origin: .zero, size: frame.size))
        guard !clipped.isNull, !clipped.isEmpty else { return nil }
        return CGRect(x: clipped.minX * scale, y: clipped.minY * scale,
                      width: clipped.width * scale, height: clipped.height * scale).integral
            .intersection(CGRect(x: 0, y: 0, width: frame.width * scale, height: frame.height * scale))
    }

    public func globalPoints(from pixels: CGRect) -> CGRect? {
        guard isValid, Self.valid(pixels) else { return nil }
        let clipped = pixels.standardized.intersection(CGRect(x: 0, y: 0, width: frame.width * scale, height: frame.height * scale))
        guard !clipped.isNull, !clipped.isEmpty else { return nil }
        return CGRect(x: frame.minX + clipped.minX / scale, y: frame.minY + clipped.minY / scale,
                      width: clipped.width / scale, height: clipped.height / scale)
    }

    /// The hole for a full-display mask, in that display's local point coordinates.
    public func localPoints(fromGlobal selection: CGRect) -> CGRect? {
        guard isValid, Self.valid(selection) else { return nil }
        let clipped = selection.intersection(frame)
        guard !clipped.isNull, !clipped.isEmpty else { return nil }
        return clipped.offsetBy(dx: -frame.minX, dy: -frame.minY)
    }

    public static func quartzRect(fromGlobal points: CGRect, primaryTop: CGFloat) -> CGRect {
        CGRect(x: points.minX, y: primaryTop - points.maxY, width: points.width, height: points.height)
    }

    private var isValid: Bool { Self.valid(frame) && !frame.isEmpty && scale.isFinite && scale > 0 }
    private static func valid(_ rect: CGRect) -> Bool {
        !rect.isNull && rect.origin.x.isFinite && rect.origin.y.isFinite && rect.width.isFinite && rect.height.isFinite
    }
}
