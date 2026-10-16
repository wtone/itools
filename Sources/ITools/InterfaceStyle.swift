import SwiftUI
import AppKit

/// Shared glass, neutral typography and category colors, using native macOS materials.
enum InterfaceStyle {
    static let canvas = adaptive(0xF4F5F7, 0x202123)
    static let surface = adaptive(0xFFFFFF, 0x38383A)
    static let raised = adaptive(0xFFFFFF, 0x454547)
    static let text = adaptive(0x302E32, 0xF5F3F6)
    static let secondary = adaptive(0x636369, 0xC2C2C7)
    static let border = adaptive(0xD8D8DE, 0x636369)
    static let cyan = adaptive(0x1BA9C0, 0x42BED2)
    static let violet = adaptive(0x9861D5, 0xAB7DDF)
    static let amber = adaptive(0xE8A032, 0xE8AE56)
    static let pink = Color(hex: 0xD652A5)
    static let green = Color(hex: 0x63B45E)
    static let graphite = Color(hex: 0x292729)
    static func color(for page: ToolPage) -> Color {
        switch page {
        case .overview: return cyan
        case .capture: return violet
        case .clipboard: return pink
        case .files: return amber
        case .monitor: return green
        case .utilities: return cyan
        case .settings: return accent
        }
    }
    static func sectionIcon(_ title: String) -> (String, Color) {
        switch title {
        case "启动设置": return ("power", amber)
        case "快捷键与操作指南": return ("command", amber)
        case "剪贴板独立面板", "添加快捷短语", "剪贴板保留规则": return ("doc.on.clipboard", pink)
        case "Finder 右键菜单", "iTools 访达工具", "新建文件", "常用文件夹": return ("folder", amber)
        case "顶部快捷面板", "菜单栏显示", "外观": return ("display", cyan)
        case "功能模块", "能力与实现情况": return ("slider.horizontal.3", violet)
        case "系统权限": return ("hand.raised.fill", pink)
        case "电池与运行时间", "保持唤醒": return ("bolt", green)
        case "此刻的 Mac", "硬件与存储", "磁盘扫描": return ("cpu", cyan)
        case "网络与交换空间", "清理链接": return ("network", cyan)
        case "窗口布局": return ("rectangle.3.offgrid", cyan)
        case "识别结果", "最近截图", "视频处理": return ("viewfinder", violet)
        case "临时便笺", "文字转二维码": return ("square.and.pencil", amber)
        default: return ("square.grid.2x2", cyan)
        }
    }
    static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((value >> 16) & 255) / 255,
                           green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, alpha: 1)
        })
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255,
                  green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

private struct WorkspaceSectionsKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var workspaceSections: Bool {
        get { self[WorkspaceSectionsKey.self] }
        set { self[WorkspaceSectionsKey.self] = newValue }
    }
}

struct InstrumentSurface: ViewModifier {
    var radius: CGFloat = 16
    var tint: Color? = nil
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme
    @Environment(\.workspaceSections) private var workspaceSections
    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    InterfaceStyle.surface.opacity(reduceTransparency ? 1 : (scheme == .dark ? 0.20 : 0.26))
                    if let tint = tint, !reduceTransparency { tint.opacity(0.06) }
                    if !reduceTransparency {
                        LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.03 : 0.07), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
            }
            .overlay {
                if !(workspaceSections && scheme == .dark) {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Color.white.opacity(tint == nil ? (scheme == .dark ? 0.12 : 0.38) : 0.42), lineWidth: 0.7)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

extension View {
    func instrumentSurface(radius: CGFloat = 16, tint: Color? = nil) -> some View {
        modifier(InstrumentSurface(radius: radius, tint: tint))
    }
}

struct InstrumentIcon: View {
    let name: String
    var color: Color = accent
    var size: CGFloat = 32
    var body: some View {
        Image(systemName: name).font(.system(size: size * 0.46, weight: .medium))
            .foregroundColor(.white).frame(width: size, height: size)
            .background(color)
            .overlay(RoundedRectangle(cornerRadius: size * 0.26).strokeBorder(Color.white.opacity(0.24), lineWidth: 0.6))
            .cornerRadius(size * 0.26)
    }
}

struct FrostedBackground: View {
    var tinted = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            if reduceTransparency { InterfaceStyle.canvas }
            else {
                FrostedMaterial()
                if tinted {
                    // A light wash unifies the hue without covering the native blur.
                    InterfaceStyle.canvas.opacity(scheme == .dark ? 0.07 : 0.04)
                    LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.015 : 0.04), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
        }.allowsHitTesting(false).ignoresSafeArea()
    }
}

struct FrostedMaterial: NSViewRepresentable {
    var appearance: NSAppearance.Name? = nil
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = WindowMaterial()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.identifier = NSUserInterfaceItemIdentifier("itools.window-glass")
        view.appearance = appearance.flatMap(NSAppearance.init(named:))
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.appearance = appearance.flatMap(NSAppearance.init(named:))
    }
    private final class WindowMaterial: NSVisualEffectView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // SwiftUI sheets and utility windows otherwise keep an opaque canvas.
            window?.isOpaque = false; window?.backgroundColor = .clear
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

/// A transparent drag strip; the system retains ownership of all three window buttons.
struct WindowDragStrip: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) {}
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) { window?.performDrag(with: event) }
    }
}

struct ActivityBadge: View {
    let title: String
    var active = true
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(active ? InterfaceStyle.cyan : InterfaceStyle.secondary).frame(width: 5, height: 5)
            Text(title).font(.system(size: 10, weight: .medium))
        }.foregroundColor(InterfaceStyle.secondary).padding(.horizontal, 9).padding(.vertical, 5)
            .background(InterfaceStyle.raised).clipShape(Capsule())
            .overlay(Capsule().strokeBorder(InterfaceStyle.border.opacity(0.7), lineWidth: 0.6))
    }
}

struct UsageTrack: View {
    let value: Double?
    var color: Color = accent
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(InterfaceStyle.border.opacity(0.4))
                if let value = value, value.isFinite {
                    Capsule().fill(LinearGradient(colors: [color.opacity(0.65), color], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geometry.size.width * min(1, max(0, value / 100)))
                }
            }
        }.frame(height: 4).accessibilityHidden(true)
    }
}
