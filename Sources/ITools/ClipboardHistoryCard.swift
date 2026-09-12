import SwiftUI
import AppKit
import ImageIO
import IToolsCore

struct ClipboardHistoryCard: View {
    let entry: ClipEntry
    let index: Int
    let selected: Bool
    let snippets: Bool
    let numberModifier: ClipboardNumberModifier
    let use: (Bool, Bool) -> Void
    let clickRecord: (Bool) -> Void
    @State private var hovering = false
    private var title: String {
        if snippets { return "快捷短语" }
        switch entry.kind {
            case .image: return "图片"
            case .files: return "文件"
            case .text: return entry.payload.contains { [NSPasteboard.PasteboardType.rtf.rawValue, NSPasteboard.PasteboardType.html.rawValue].contains($0.type) } ? "富文本" : "纯文本"
        }
    }
    private var headerColor: Color {
        ClipboardPanelPalette.category(entry.kind, snippets: snippets)
    }
    private var source: ClipboardCardAssets.Source {
        snippets ? .init(name: entry.source, icon: nil) : ClipboardCardAssets.shared.source(entry.source)
    }
    private var detail: String {
        switch entry.kind {
            case .text: return "\(entry.text.count) 个字符"
            case .image: return bytes(UInt64(entry.payload.reduce(0) { $0 + $1.data.count }))
            case .files: return "\(max(1, entry.text.split(separator: "\n").count)) 个文件"
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(title).font(.system(size: 12, weight: .semibold))
                    if entry.pinned { Image(systemName: "star.fill").font(.system(size: 9)).help("已收藏") }
                    Spacer(minLength: 0)
                    if let icon = source.icon { Image(nsImage: icon).resizable().frame(width: 19, height: 19) }
                    else { Image(systemName: snippets ? "text.bubble" : "app").font(.system(size: 16)) }
                }
                HStack(spacing: 6) {
                    Text(snippets ? entry.group : ClipboardCardAssets.timestamp(entry.date))
                    Spacer(minLength: 0)
                    Text(source.name).lineLimit(1).truncationMode(.middle)
                }.font(.system(size: 10)).foregroundColor(ClipboardPanelPalette.headerInk.opacity(0.82))
            }.foregroundColor(ClipboardPanelPalette.headerInk)
                .padding(.horizontal, 11).padding(.vertical, 8).background(headerColor)
            .clipboardRecordActions(copy: { clickRecord(false) }, paste: { clickRecord(true) })
            GeometryReader { geometry in
                Group {
                    if entry.kind == .image, let image = ClipboardCardAssets.shared.thumbnail(entry) {
                        ClipboardImagePreview(image: image).allowsHitTesting(false).padding(7)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    } else if entry.kind == .files {
                        VStack(alignment: .leading, spacing: 9) {
                            Image(systemName: "doc.on.doc").font(.system(size: 24, weight: .light)).foregroundColor(accent)
                            Text(entry.text).font(.system(size: 12)).lineLimit(5)
                            Spacer(minLength: 0)
                        }.padding(11).frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                    } else {
                        Text(String(entry.text.prefix(1600))).font(.system(size: 13)).lineSpacing(3)
                        .frame(width: max(1, geometry.size.width - 22), alignment: .topLeading)
                        .fixedSize(horizontal: false, vertical: true).padding(11)
                        .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                    }
                }.clipped()
            }
            .clipboardRecordActions(copy: { clickRecord(false) }, paste: { clickRecord(true) })
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text((index < 9 ? numberModifier.symbol : "") + String(index + 1))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(index < 9 ? accent : .secondary)
                    .padding(.horizontal, 5).padding(.vertical, 3)
                    .background(index < 9 ? accent.opacity(0.1) : .clear).cornerRadius(4)
                    Text(detail).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                    Spacer(minLength: 0)
                }.clipboardRecordActions(copy: { clickRecord(false) }, paste: { clickRecord(true) })
                Button { use(false, false) } label: { Text("复制").frame(height: 22).contentShape(Rectangle()) }
                .buttonStyle(.plain).help("复制这条内容").accessibilityLabel("复制第 \(index + 1) 条内容")
                Button { use(true, false) } label: { Text("粘贴").frame(height: 22).contentShape(Rectangle()) }
                .buttonStyle(.plain).help("粘贴到之前的应用").accessibilityLabel("粘贴第 \(index + 1) 条内容")
            }.font(.system(size: 11)).foregroundColor(accent).padding(.horizontal, 9).padding(.vertical, 5)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ClipboardPanelPalette.cardFill.opacity(0.82)).clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(headerColor.opacity(selected ? 1 : hovering ? 0.72 : 0.3), lineWidth: selected ? 2.5 : 1))
        .foregroundColor(ClipboardPanelPalette.text)
        .onHover { hovering = $0 }
        .help(ClipboardRecordInteraction.hint)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("第 \(index + 1) 条，\(title)，来自\(source.name)" + (selected ? "，已选择" : ""))
    }
}

enum ClipboardPanelPalette {
    static let text = adaptive(0x202631, 0xEEF1F6)
    static let secondary = adaptive(0x626975, 0xD0D4DC)
    static let cardFill = adaptive(0xFFFFFF, 0x535B65)
    static let headerInk = adaptive(0x24332D, 0x24332D)
    static let all = adaptive(0xE982C8, 0xEFA0D6)
    static let textCategory = adaptive(0x61D575, 0x6CDA86)
    static let imageCategory = adaptive(0xF7CA62, 0xF7D077)
    static let fileCategory = adaptive(0x79CCF0, 0x8CD5F3)
    static let favoriteCategory = adaptive(0xBE9AF0, 0xC8ACF4)
    static func category(_ kind: ClipKind, snippets: Bool = false) -> Color {
        if snippets { return favoriteCategory }
        switch kind { case .text: return textCategory; case .image: return imageCategory; case .files: return fileCategory }
    }
    static func filter(_ title: String) -> Color {
        switch title {
        case "文字": return textCategory; case "图片": return imageCategory
        case "文件": return fileCategory; case "收藏": return favoriteCategory
        default: return all
        }
    }
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255,
            blue: Double(value & 255) / 255, alpha: 1)
        })
    }
}

/// The effect is behind the content, so vibrancy does not alter text or image preview colors.
struct ClipboardPanelBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        FrostedBackground(tinted: false)
            .overlay(Color.white.opacity(scheme == .dark ? 0.06 : 0.12))
            .allowsHitTesting(false)
    }
}

/// Draw immutable pixels without template tinting or vibrancy from the surrounding panel.
private struct ClipboardImagePreview: NSViewRepresentable {
    let image: CGImage
    func makeNSView(context: Context) -> Preview { Preview() }
    func updateNSView(_ view: Preview, context: Context) { view.image = image; view.needsDisplay = true }
    final class Preview: NSView {
        var image: CGImage?
        override var allowsVibrancy: Bool { false }
        override func draw(_ dirtyRect: NSRect) {
            guard let image = image, let context = NSGraphicsContext.current?.cgContext else { return }
            let ratio = min(bounds.width / CGFloat(image.width), bounds.height / CGFloat(image.height))
            let size = CGSize(width: CGFloat(image.width) * ratio, height: CGFloat(image.height) * ratio)
            let rect = CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
            context.saveGState(); context.clear(bounds); context.setBlendMode(.normal); context.interpolationQuality = .high
            context.draw(image, in: rect); context.restoreGState()
        }
    }
}

/// Reuse small previews while scrolling; never repeatedly decode full-resolution clipboard images.
private final class ClipboardCardAssets {
    struct Source { let name: String; let icon: NSImage? }
    static let shared = ClipboardCardAssets()
    private let thumbnails = NSCache<NSString, CGImage>()
    private var sources: [String: Source] = [:]
    private init() { thumbnails.countLimit = 80; thumbnails.totalCostLimit = 32 * 1024 * 1024 }
    func source(_ identifier: String) -> Source {
        if let cached = sources[identifier] { return cached }
        let url = identifier == "iTools" ? Bundle.main.bundleURL : NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
        let result: Source
        if let url = url {
            let bundle = Bundle(url: url)
            let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent
            result = Source(name: name, icon: NSWorkspace.shared.icon(forFile: url.path))
        } else { result = Source(name: identifier.components(separatedBy: ".").last ?? identifier, icon: nil) }
        sources[identifier] = result; return result
    }
    func thumbnail(_ entry: ClipEntry) -> CGImage? {
        let key = entry.id.uuidString as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        guard let data = entry.payload.first?.data,
        let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
        let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: 600
        ] as CFDictionary) else { return nil }
        thumbnails.setObject(cgImage, forKey: key, cost: cgImage.bytesPerRow * cgImage.height)
        return cgImage
    }
    static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "HH:mm"
        if Calendar.current.isDateInToday(date) { return "今天 " + formatter.string(from: date) }
        if Calendar.current.isDateInYesterday(date) { return "昨天 " + formatter.string(from: date) }
        formatter.dateFormat = "MM/dd HH:mm"; return formatter.string(from: date)
    }
}
