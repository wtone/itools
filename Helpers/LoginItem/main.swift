import AppKit
import OSLog

final class LoginDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Always resolve the containing bundle: moving or updating iTools keeps the login item valid.
        guard let host = LoginLaunch.hostURL(for: Bundle.main.bundleURL) else {
            Logger(subsystem: LoginLaunch.helperID, category: "launch").error("Containing iTools app is unavailable")
            NSApp.terminate(nil); return
        }
        if NSWorkspace.shared.runningApplications.contains(where: {
            $0.bundleURL?.resolvingSymlinksInPath().standardizedFileURL == host && !$0.isTerminated
        }) {
            NSApp.terminate(nil); return
        }
        NSWorkspace.shared.openApplication(at: host, configuration: LoginLaunch.configuration()) { _, error in
            if let error = error {
                Logger(subsystem: LoginLaunch.helperID, category: "launch").error("Login launch failed: \(error.localizedDescription, privacy: .public)")
            }
            // A successful exit prevents an unwanted restart loop, including after the user quits iTools.
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = LoginDelegate()
app.delegate = delegate
app.run()
