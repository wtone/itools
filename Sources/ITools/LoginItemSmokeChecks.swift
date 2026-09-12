import AppKit
import SwiftUI
import IToolsCore

enum LoginItemSmokeChecks {
    private struct PreviewBackend: LoginItemManaging {
        let state: LoginItemState
        func readState() -> LoginItemState { state }
        func setEnabled(_ enabled: Bool) throws { throw UserFacingError("Preview is read-only") }
    }
    static func render(destination: URL) throws {
        for (name, state, dark) in [("login-settings", LoginItemState.disabled, false),
                                    ("login-settings-approval", .requiresApproval, true)] {
            let host = NSHostingView(rootView: LoginItemSettingsView(controller:
                LoginItemController(backend: PreviewBackend(state: state)))
                .padding(28).frame(width: 760, height: 300, alignment: .topLeading)
                .background(Color(NSColor.windowBackgroundColor))
                .environment(\.colorScheme, dark ? .dark : .light))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 300),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host
            window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
            host.appearance = window.appearance
            defer { window.close() }
            host.frame = NSRect(x: 0, y: 0, width: 760, height: 300)
            RunLoop.main.run(until: Date().addingTimeInterval(0.15))
            host.layoutSubtreeIfNeeded()
            guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw UserFacingError("Login settings bitmap failed") }
            host.cacheDisplay(in: host.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name + ".png"))
        }
        print("PASS: login settings off/light and approval/dark previews; no system registration changed")
    }

    /// Explicit integration mode only: normal startup and the general smoke test never register a service.
    static func registration(controller: LoginItemController, destination: URL) {
        guard controller.state == .disabled else {
            print("SKIP: existing login registration preserved (\(controller.state))"); NSApp.terminate(nil); return
        }
        controller.setEnabled(true) {
            let enabledState = controller.state, enableError = controller.errorMessage
            // Always undo the temporary registration before reporting a failure.
            controller.setEnabled(false) {
                let result: [String: Any] = ["initial": "disabled", "registered": String(describing: enabledState),
                    "enableError": enableError ?? "", "final": String(describing: controller.state),
                    "disableError": controller.errorMessage ?? ""]
                do {
                    try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                        .write(to: destination.appendingPathComponent("registration.json"), options: .atomic)
                } catch { print("FAIL: registration receipt: \(error)") }
                print("Login registration test: \(result)")
                NSApp.terminate(nil)
            }
        }
    }
}
