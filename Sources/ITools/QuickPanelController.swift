import AppKit
import SwiftUI
import Combine
import IToolsCore

final class QuickPanelController {
    private let model: AppModel
    private let popover = NSPopover()
    private var errorSubscription: AnyCancellable?
    init(model: AppModel) {
        self.model = model
        popover.behavior = .transient; popover.animates = false
        errorSubscription = NoticeCenter.shared.$error.dropFirst().compactMap { $0 }
            .receive(on: RunLoop.main).sink { [weak self] _ in self?.close(); self?.model.showWindow?() }
    }
    var isShown: Bool { popover.isShown }
    func toggle(relativeTo button: NSStatusBarButton) {
        if popover.isShown { close(); return }
        model.quickSystem.refresh()
        let height = min(760, max(400, (button.window?.screen?.visibleFrame.height ?? 820) - 45))
        let controller = NSHostingController(rootView: view().frame(width: 540, height: height))
        popover.contentSize = NSSize(width: 540, height: height)
        controller.preferredContentSize = popover.contentSize; popover.contentViewController = controller
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        NSApp.activate(ignoringOtherApps: true)
    }
    func close() { popover.performClose(nil) }
    private func afterClosing(_ action: @escaping () -> Void) {
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: action)
    }
    private func navigate(_ page: ToolPage) { close(); model.navigate(page) }
    private func view() -> QuickPanelView {
        QuickPanelView(model: model, monitor: model.monitor, preferences: model.quickPanel, system: model.quickSystem,
                       awake: model.awake, recorder: model.recorder, clipboard: model.clipboard,
                       run: { [weak self] in self?.perform($0) },
                       openSystem: { [weak self] shortcut in self?.afterClosing { self?.model.quickSystem.open(shortcut) } },
                       navigate: { [weak self] in self?.navigate($0) }, close: { [weak self] in self?.close() },
                       quit: { [weak self] in self?.close(); NSApp.terminate(nil) },
                       stopRecording: { [weak self] in self?.afterClosing { self?.model.recorder.stop() } })
    }
    func perform(_ action: QuickAction) {
        if action == .awake {
            if model.awake.active { model.awake.stop() } else { model.awake.start(minutes: 30, keepDisplay: false) }; return
        }
        if action == .keepDisplay {
            if model.awake.active && model.awake.keepsDisplay { model.awake.stop() } else { model.awake.start(minutes: 30, keepDisplay: true) }; return
        }
        if action == .desktopCover { model.quickSystem.toggleDesktopCover(); return }
        afterClosing { [weak self] in
            guard let self = self else { return }
            let model = self.model
            switch action {
            case .darkMode: model.quickSystem.toggleDark()
            case .lockScreen: model.quickSystem.lockScreen()
            case .screenSaver: model.quickSystem.screenSaver()
            case .cleanScreen: model.cleaning.start(keyboardOnly: false)
            case .cleanKeyboard: model.cleaning.start(keyboardOnly: true)
            case .dockAutoHide: model.quickSystem.toggleDock()
            case .menuBarAutoHide: model.quickSystem.toggleMenuBar()
            case .screenshot: model.takeScreenshot()
            case .ocr: model.takeScreenshot(ocr: true)
            case .clipboard: model.showClipboard?(false)
            case .files: model.navigate(.files)
            case .displaySettings: model.quickSystem.openPreferences("com.apple.preference.displays")
            case .leftWindow: model.windows.apply(.left)
            case .rightWindow: model.windows.apply(.right)
            case .maximize: model.windows.apply(.maximize)
            case .restoreWindow: model.windows.restore()
            case .colorPicker: if model.captureEnabled { model.capture.pickColor() }
            case .recording: model.navigate(.capture)
            case .emptyTrash: model.quickSystem.emptyTrash()
            case .dockSettings: model.quickSystem.openPreferences("com.apple.preference.dock")
            case .awake, .keepDisplay, .desktopCover: break
            }
        }
    }
    /// Render only our own views; never executes a quick action or modifies system preferences.
    func verifyAndExport(button: NSStatusBarButton, destination: URL) throws {
        model.quickPanel.reset()
        toggle(relativeTo: button)
        guard isShown else { throw UserFacingError("Smoke: quick popover did not open") }
        close()
        guard !isShown else { throw UserFacingError("Smoke: quick popover did not close") }
        for (name, appearance) in [("quick-panel", NSAppearance.Name.aqua), ("quick-panel-dark", NSAppearance.Name.darkAqua)] {
            let host = NSHostingView(rootView: view().frame(width: 540, height: 760).environment(\.colorScheme, appearance == .darkAqua ? .dark : .light))
            try export(host, size: NSSize(width: 540, height: 760), appearance: appearance, name: name, destination: destination)
        }
        let settings = NSHostingView(rootView: ScrollView { QuickPanelSettingsView(preferences: model.quickPanel).padding(20) }.frame(width: 540, height: 920).background(Color(NSColor.windowBackgroundColor)).environment(\.colorScheme, .light))
        try export(settings, size: NSSize(width: 540, height: 920), appearance: .aqua, name: "quick-panel-settings", destination: destination)
        let cleaning = NSHostingView(rootView: CleaningView(service: model.cleaning).frame(width: 800, height: 500))
        try export(cleaning, size: NSSize(width: 800, height: 500), appearance: .darkAqua, name: "cleaning-preview", destination: destination)
        for source in [QuickSystemService.darkScript, QuickSystemService.dockScript, QuickSystemService.menuScript, "tell application \"Finder\" to empty the trash"] {
            var error: NSDictionary?
            guard NSAppleScript(source: source)?.compileAndReturnError(&error) == true else { throw UserFacingError("Smoke: system action script does not compile: \(error?.description ?? "")") }
        }
        let assertion = AwakeService()
        defer { assertion.stop() }
        assertion.start(minutes: 1, keepDisplay: true)
        guard assertion.active, assertion.keepsDisplay else { throw UserFacingError("Smoke: display awake assertion failed") }
        assertion.stop()
        guard !assertion.active, !assertion.keepsDisplay, assertion.until == nil else { throw UserFacingError("Smoke: awake assertion cleanup failed") }
        for shortcut in SystemShortcut.allCases {
            guard shortcut.url != nil else { throw UserFacingError("Smoke: system application unavailable: " + shortcut.title) }
        }
        print("PASS: awake/display assertion creation and release; system application targets resolve")
        print("PASS: quick popover open/close; light/dark/customization/cleaning views; system scripts compile without execution")
    }
    private func export(_ view: NSView, size: NSSize, appearance: NSAppearance.Name, name: String, destination: URL) throws {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: appearance)
        window.contentView = view; view.frame = NSRect(origin: .zero, size: size)
        // Give SwiftUI an explicit proposal and allow its appearance/layout transaction to settle.
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        view.frame = NSRect(origin: .zero, size: size)
        view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
        guard view.bounds.width >= size.width - 1, view.bounds.height >= size.height - 1 else { throw UserFacingError("Smoke: panel collapsed") }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw UserFacingError("Smoke: panel bitmap failed") }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw UserFacingError("Smoke: panel export failed") }
        try data.write(to: destination.appendingPathComponent(name + ".png")); window.close()
    }
}
