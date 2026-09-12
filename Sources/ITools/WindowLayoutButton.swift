import SwiftUI
import IToolsCore

struct WindowLayoutButton: View {
    let layout: WindowLayout?
    let action: () -> Void
    @State private var hovering = false
    private var title: String { layout?.title ?? "还原上一步" }
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                WindowLayoutGlyph(layout: layout).frame(width: 34, height: 25)
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
            }.foregroundColor(InterfaceStyle.text).padding(.horizontal, 12).padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(InterfaceStyle.raised.opacity(hovering ? 0.78 : 0.43))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(hovering ? InterfaceStyle.cyan.opacity(0.75) : Color.white.opacity(0.18), lineWidth: 0.8))
                .cornerRadius(10).contentShape(Rectangle())
        }.buttonStyle(.plain).onHover { hovering = $0 }
            .help(layout == nil ? "还原之前的窗口位置与大小" : "将之前的应用窗口排列为「\(title)」")
            .accessibilityLabel(title)
    }
}

/// Share the actual layout geometry, including its top-left origin, with the visual preview.
private struct WindowLayoutGlyph: View {
    let layout: WindowLayout?
    var body: some View {
        GeometryReader { geometry in
            let bounds = CGRect(origin: .zero, size: geometry.size).insetBy(dx: 2, dy: 2)
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 3).fill(InterfaceStyle.text.opacity(0.045))
                if let layout = layout {
                    let region = layout.frame(in: bounds, gap: 0).insetBy(dx: 1, dy: 1)
                    RoundedRectangle(cornerRadius: 1.4).fill(InterfaceStyle.cyan.opacity(0.9))
                        .frame(width: region.width, height: region.height)
                        .offset(x: region.minX, y: region.minY)
                    Path { path in
                        let thirds = [WindowLayout.firstThird, .middleThird, .lastThird].contains(layout)
                        if thirds {
                            for fraction in [CGFloat(1) / 3, CGFloat(2) / 3] {
                                let x = bounds.minX + bounds.width * fraction
                                path.move(to: CGPoint(x: x, y: bounds.minY)); path.addLine(to: CGPoint(x: x, y: bounds.maxY))
                            }
                        } else if ![WindowLayout.maximize, .center].contains(layout) {
                            path.move(to: CGPoint(x: bounds.midX, y: bounds.minY)); path.addLine(to: CGPoint(x: bounds.midX, y: bounds.maxY))
                            if ![WindowLayout.left, .right].contains(layout) {
                                path.move(to: CGPoint(x: bounds.minX, y: bounds.midY)); path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.midY))
                            }
                        }
                    }.stroke(InterfaceStyle.text.opacity(0.22), lineWidth: 0.65)
                } else {
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 16, weight: .medium))
                        .foregroundColor(InterfaceStyle.cyan).frame(width: geometry.size.width, height: geometry.size.height)
                }
                RoundedRectangle(cornerRadius: 3).strokeBorder(InterfaceStyle.text.opacity(0.55), lineWidth: 1)
            }
        }.accessibilityHidden(true)
    }
}
