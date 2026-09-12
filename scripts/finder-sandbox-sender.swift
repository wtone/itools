// Compile alongside FinderLaunchEvent/FinderBridge/FinderActions and sign with
// the extension's sandbox entitlement. Only this sender is sandboxed; the test
// harness owns fixtures and verifies the worker's receipts outside the sandbox.
import AppKit

@main enum SandboxSender {
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 4 else { fatalError("sender worker.app output-directory request-url...") }
        _ = NSApplication.shared
        let worker = URL(fileURLWithPath: args[1])
        let output = URL(fileURLWithPath: args[2])
        // Prove the sender actually has filesystem sandbox restrictions, rather
        // than just inspecting its signature's entitlements.
        let denied = output.appendingPathComponent("sandbox-must-deny-" + UUID().uuidString)
        do {
            try Data("sandbox probe".utf8).write(to: denied)
            try? FileManager.default.removeItem(at: denied)
            fatalError("Sender is not sandboxed")
        } catch let error as NSError {
            guard error.domain == NSCocoaErrorDomain && error.code == NSFileWriteNoPermissionError else {
                fatalError("Unexpected sandbox check: \(error)")
            }
        }
        let urls = args.dropFirst(3).compactMap(URL.init(string:))
        guard urls.count == args.count - 3, let config = FinderLaunchEvent.configuration(for: urls) else {
            fatalError("Invalid test requests")
        }
        var done = false
        var result: [String: Any] = ["error": "Launch timed out"]
        NSWorkspace.shared.openApplication(at: worker, configuration: config) { app, error in
            DispatchQueue.main.async {
                result = ["pid": app?.processIdentifier ?? 0, "sandboxDeniedWrite": true,
                          "error": error.map { String(describing: $0) } ?? ""]
                done = true
            }
        }
        let deadline = Date().addingTimeInterval(20)
        while !done && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        let data = try! JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
        print(String(data: data, encoding: .utf8)!)
        exit(done && (result["pid"] as? Int32 ?? 0) != 0 ? 0 : 1)
    }
}
