import AppKit
import SwiftUI
import IToolsCore

/// Takes keyboard focus without activating the main app or changing its display / Space.
final class StatusQuickPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "iTools 系统状态与快捷操作"
        isReleasedWhenClosed = false; isFloatingPanel = true; hidesOnDeactivate = false
        isOpaque = false; backgroundColor = .clear; hasShadow = true
        level = .popUpMenu; animationBehavior = .none
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }
}

struct StatusPanelChrome<Content: View>: View {
    let placement: MenuPanelPlacement
    let content: Content
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        content.frame(width: placement.frame.width, height: placement.frame.height - MenuPanelPlacement.arrowHeight)
            .padding(.top, MenuPanelPlacement.arrowHeight)
            .background(FrostedBackground())
            .clipShape(StatusPanelOutline(arrowX: placement.arrowX))
            .overlay(StatusPanelOutline(arrowX: placement.arrowX).stroke(Color.white.opacity(scheme == .dark ? 0.16 : 0.48), lineWidth: 0.7))
    }
}

private struct StatusPanelOutline: Shape {
    let arrowX: CGFloat
    func path(in rect: CGRect) -> Path {
        let top = MenuPanelPlacement.arrowHeight, radius: CGFloat = min(12, rect.width / 4)
        return Path { p in
            p.move(to: CGPoint(x: radius, y: top))
            p.addLine(to: CGPoint(x: arrowX - 10, y: top))
            p.addLine(to: CGPoint(x: arrowX, y: 0))
            p.addLine(to: CGPoint(x: arrowX + 10, y: top))
            p.addLine(to: CGPoint(x: rect.maxX - radius, y: top))
            p.addQuadCurve(to: CGPoint(x: rect.maxX, y: top + radius), control: CGPoint(x: rect.maxX, y: top))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            p.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: radius, y: rect.maxY))
            p.addQuadCurve(to: CGPoint(x: 0, y: rect.maxY - radius), control: CGPoint(x: 0, y: rect.maxY))
            p.addLine(to: CGPoint(x: 0, y: top + radius))
            p.addQuadCurve(to: CGPoint(x: radius, y: top), control: CGPoint(x: 0, y: top))
            p.closeSubpath()
        }
    }
}
