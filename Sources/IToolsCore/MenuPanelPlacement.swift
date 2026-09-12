import Foundation

public struct MenuPanelScreen: Equatable {
    public let id: UInt32
    public let frame: CGRect
    public let visibleFrame: CGRect
    public init(id: UInt32, frame: CGRect, visibleFrame: CGRect) {
        self.id = id; self.frame = frame; self.visibleFrame = visibleFrame
    }
}

/// A presentation is a snapshot of the clicked display, never a live status-button attachment.
public struct MenuPanelPlacement: Equatable {
    public static let arrowHeight: CGFloat = 10
    public let screenID: UInt32
    public let frame: CGRect
    public let arrowX: CGFloat

    public static func resolve(pointer: CGPoint, screens: [MenuPanelScreen], buttonRect: CGRect? = nil) -> Self? {
        guard let screen = screens.first(where: { $0.frame.contains(pointer) })
            ?? screens.first(where: { screen in buttonRect?.intersects(screen.frame) == true })
            ?? screens.first else { return nil }
        let visible = screen.visibleFrame.intersection(screen.frame)
        guard !visible.isNull, visible.width > 0, visible.height > 0 else { return nil }
        let margin = min(8, min(visible.width, visible.height) / 8)
        let available = visible.insetBy(dx: margin, dy: margin)
        let size = CGSize(width: min(540, available.width), height: min(770, available.height))
        // The NSStatusBarButton can describe the primary-screen replica even for an external-screen click.
        let anchor = buttonRect.flatMap { rect -> CGRect? in
            rect.insetBy(dx: -2, dy: -2).contains(pointer) && rect.intersects(screen.frame) ? rect : nil
        }
        let x = anchor?.midX ?? pointer.x
        let top = min(available.maxY, anchor?.minY ?? available.maxY)
        let origin = CGPoint(x: max(available.minX, min(x - size.width / 2, available.maxX - size.width)),
                             y: max(available.minY, top - size.height))
        let inset = min(24, size.width / 2)
        return Self(screenID: screen.id, frame: CGRect(origin: origin, size: size),
                    arrowX: max(inset, min(x - origin.x, size.width - inset)))
    }
}
