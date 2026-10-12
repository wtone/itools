import Foundation

/// Native status items belong to the right-hand menu bar. On a notched display,
/// the auxiliary area's horizontal range is authoritative; its height can be
/// smaller than the native status window, so do not compare vertical containment.
public enum MenuBarPlacement {
    public static func isSavedPositionUsable(_ position: Double, screen: CGRect, rightArea: CGRect?) -> Bool {
        let width = rightArea?.width ?? screen.width
        return position.isFinite && position >= 0 && position < Double(width)
    }
    public static func isFrameVisible(_ frame: CGRect, screen: CGRect, rightArea: CGRect?) -> Bool {
        guard !frame.isEmpty, frame.minX.isFinite, frame.maxX.isFinite else { return false }
        let minX = rightArea?.minX ?? screen.minX
        return frame.minX >= minX - 0.5 && frame.maxX <= screen.maxX + 0.5
    }
}
