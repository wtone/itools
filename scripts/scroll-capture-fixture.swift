import AppKit

final class ScrollFixtureDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let screen = NSScreen.main else { NSApp.terminate(nil); return }
        let visible = screen.visibleFrame
        let width = min(1000, visible.width - 100), height = min(700, visible.height - 100)
        let frame = NSRect(x: visible.midX - width / 2, y: visible.midY - height / 2, width: width, height: height)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "iTools 长截图合成测试页面"; window.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: NSRect(origin: .zero, size: frame.size))
        scroll.autoresizingMask = [.width, .height]; scroll.hasVerticalScroller = true
        let text = NSTextView(frame: NSRect(x: 0, y: 0, width: width - 20, height: 8000))
        text.isEditable = false; text.font = NSFont.systemFont(ofSize: 24)
        text.string = (1...100).map { "Section \($0): iTools scrolling fixture, reference \($0 * 137).\n\nSynthetic scrolling content.\n\n" }.joined()
        text.isVerticallyResizable = true
        text.textContainer?.containerSize = NSSize(width: width - 20, height: .greatestFiniteMagnitude)
        text.textContainer?.widthTracksTextView = true
        scroll.documentView = text; window.contentView = scroll
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let app = NSApplication.shared
let delegate = ScrollFixtureDelegate()
app.delegate = delegate; app.setActivationPolicy(.regular); app.run()
