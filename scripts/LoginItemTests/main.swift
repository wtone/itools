// Explicit integration check: no clipboard sampling; temporary registration is removed before completion.
import AppKit
import Carbon

guard CommandLine.arguments.count == 3 else { fatalError("Usage: test-login-item /path/iTools.app /path/output") }
let appURL = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
guard NSRunningApplication.runningApplications(withBundleIdentifier: "app.itools.mac").isEmpty else {
    fatalError("Close iTools normally before running this test")
}
var running: NSRunningApplication?
func waitFor(_ predicate: () -> Bool, seconds: TimeInterval = 15) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if predicate() { return true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
    }
    return predicate()
}
func quit() {
    guard let app = running, !app.isTerminated else { return }
    app.terminate()
    guard waitFor({ app.isTerminated }, seconds: 8) else { fatalError("Test app refused normal termination") }
}
func check(_ condition: Bool, _ message: String) {
    if !condition { quit(); print("FAIL: " + message); exit(1) }
}
func receipt(_ name: String) -> [String: Any]? {
    guard let data = try? Data(contentsOf: output.appendingPathComponent(name)),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    return json
}
func launch(_ configuration: NSWorkspace.OpenConfiguration, target: URL? = nil) -> NSRunningApplication? {
    var done = false, result: NSRunningApplication?, failure: Error?
    NSWorkspace.shared.openApplication(at: target ?? appURL, configuration: configuration) { app, error in
        DispatchQueue.main.async { result = app; failure = error; done = true }
    }
    check(waitFor { done }, "launch callback timeout")
    check(failure == nil, "launch failed: \(String(describing: failure))")
    return result
}
func config(mode: String = "lifecycle") -> NSWorkspace.OpenConfiguration {
    let config = LoginLaunch.configuration()
    config.arguments = ["--login-item-test"]
    config.environment = ["ITOOLS_LOGIN_TEST_OUTPUT": output.path, "ITOOLS_LOGIN_TEST_MODE": mode]
    return config
}

try? FileManager.default.removeItem(at: output.appendingPathComponent("launch.json"))
running = launch(config())
check(waitFor { receipt("launch.json") != nil }, "cold launch receipt missing")
let cold = receipt("launch.json")!
check(cold["login"] as? Bool == true && cold["windowVisible"] as? Bool == false
      && cold["accessory"] as? Bool == true && cold["statusItem"] as? Bool == true, "login launch displayed a window or lost menu bar")
check(cold["bundle"] as? String == appURL.path, "launched another installation")
print("PASS: cold login event starts in menu bar without a main window or Dock icon")

let helperURL = appURL.appendingPathComponent(LoginLaunch.helperPath)
check(LoginLaunch.hostURL(for: helperURL) == appURL, "helper did not resolve its containing installed app")
check(LoginLaunch.hostURL(for: appURL.appendingPathComponent("Contents/Helpers/iTools Login.app")) == nil, "invalid helper location accepted")
let helperConfig = NSWorkspace.OpenConfiguration(); helperConfig.activates = false
let helper = launch(helperConfig, target: helperURL)
check(waitFor { helper?.isTerminated != false }, "helper remained running")
check(NSRunningApplication.runningApplications(withBundleIdentifier: "app.itools.mac").count == 1,
      "helper launched a duplicate main process")
print("PASS: real embedded helper resolves installed bundle, exits, and leaves existing main process alone")

try? FileManager.default.removeItem(at: output.appendingPathComponent("launch.json"))
_ = launch(LoginLaunch.configuration())
check(waitFor { receipt("launch.json") != nil }, "warm login receipt missing")
let warm = receipt("launch.json")!
check(warm["windowVisible"] as? Bool == false && warm["pid"] as? Int == cold["pid"] as? Int, "warm login activated UI or duplicated process")

try? FileManager.default.removeItem(at: output.appendingPathComponent("launch.json"))
let manual = NSWorkspace.OpenConfiguration()
manual.activates = true
manual.appleEvent = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass),
    eventID: AEEventID(kAEReopenApplication), targetDescriptor: nil,
    returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
_ = launch(manual)
check(waitFor { receipt("launch.json")?["windowVisible"] as? Bool == true }, "manual reopen failed to show main window")
check(receipt("launch.json")?["accessory"] as? Bool == false, "manual reopen did not restore regular app policy")
print("PASS: repeat login keeps window hidden; manual reopen shows main window and reuses same process")
quit(); running = nil

try? FileManager.default.removeItem(at: output.appendingPathComponent("registration.json"))
running = launch(config(mode: "registration"))
check(waitFor({ running?.isTerminated == true }, seconds: 30), "registration test did not finish")
if let result = receipt("registration.json") {
    print("System registration receipt: \(result)")
    check(result["final"] as? String == "disabled", "temporary registration was not removed")
    check(result["enableError"] as? String == "" && result["disableError"] as? String == "", "system registration returned error")
    check(["enabled", "requiresApproval"].contains(result["registered"] as? String ?? ""), "registration not recorded by system")
    print("PASS: real ServiceManagement registration/unregistration; final self-start state is disabled")
} else {
    print("SKIP: an existing or unavailable system registration was preserved; inspect launch.json")
}
// A new process must read the OS state rather than a checkbox saved in memory.
running = launch(config())
check(waitFor { receipt("launch.json")?["pid"] as? Int == running.map { Int($0.processIdentifier) } }, "restart receipt missing")
check(receipt("launch.json")?["registration"] as? String == cold["registration"] as? String, "registration state changed across process restart")
quit()
print("PASS: fresh process reads original system status; test processes closed normally")
