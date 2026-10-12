// Integration through real Launch Services. File mutations use fresh fixtures.
// Sandbox mode first checks unmodified production cold/warm TXT + Finder reveal.
// The 29-request session then uses scoped reveal/app/recycle hooks and a private clipboard.
import AppKit
import Carbon

let args = CommandLine.arguments
guard (3...4).contains(args.count) else { fatalError("Usage: test-finder-direct.swift /path/iTools.app /path/new-output [sandbox-sender-executable]") }
let sandboxSender = args.count == 4 ? URL(fileURLWithPath: args[3]) : nil
let host = URL(fileURLWithPath: args[1])
let worker = host.appendingPathComponent("Contents/Helpers/iTools Finder Actions.app")
let output = URL(fileURLWithPath: args[2], isDirectory: true)
let fm = FileManager.default
guard !fm.fileExists(atPath: output.path) else { fatalError("Use a fresh output directory") }
try fm.createDirectory(at: output, withIntermediateDirectories: true)
let originalMainPIDs = Set(NSRunningApplication.runningApplications(withBundleIdentifier: "app.itools.mac").map(\.processIdentifier))
guard NSRunningApplication.runningApplications(withBundleIdentifier: "app.itools.mac.finder-actions").isEmpty else {
    fatalError("Close the idle Finder Actions worker normally before cold-start testing")
}
var launched: NSRunningApplication?
var firstPID: Int?
var count = 0
var reportedDiscovery = false
func pump(_ seconds: TimeInterval) { RunLoop.main.run(until: Date().addingTimeInterval(seconds)) }
func finish(_ message: String, _ code: Int32) -> Never {
    if let app = launched, !app.isTerminated {
        app.terminate(); let deadline = Date().addingTimeInterval(8)
        while !app.isTerminated && Date() < deadline { pump(0.05) }
        if !app.isTerminated { print("FAIL: test worker busy; not force-quitting"); exit(3) }
    }
    print(message); exit(code)
}
func check(_ valid: Bool, _ message: String) { if !valid { finish("FAIL: " + message, 2) } }
func requestURL(_ action: String, _ paths: [URL], id: UUID = UUID(), application: String? = nil) -> URL {
    var c = URLComponents(); c.scheme = "itools-finder-action"; c.host = "finder"
    c.queryItems = [.init(name: "action", value: action), .init(name: "request", value: id.uuidString)] + paths.map { .init(name: "path", value: $0.path) }
    if let application = application { c.queryItems?.append(.init(name: "application", value: application)) }
    return c.url!
}
func deliver(_ urls: [URL]) {
    if let sender = sandboxSender {
        let process = Process(); process.executableURL = sender
        process.arguments = [worker.path, output.path] + urls.map(\.absoluteString)
        let pipe = Pipe(); process.standardOutput = pipe
        do { try process.run() } catch { finish("FAIL: sandbox sender: \(error)", 2) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0,
              let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              result["sandboxDeniedWrite"] as? Bool == true,
              result["discoveredWorker"] as? String == worker.path,
              let pid = result["pid"] as? Int32, pid != 0,
              let app = NSRunningApplication(processIdentifier: pid) else {
            finish("FAIL: sandbox delivery: " + String(decoding: data, as: UTF8.self), 2)
        }
        launched = app
        if !reportedDiscovery {
            let hostReadable = result["hostReadable"] ?? "unknown"
            let workerReadable = result["workerReadable"] ?? "unknown"
            print("PASS: production host discovery in sandbox; legacy host/worker readable = \(hostReadable) / \(workerReadable)")
            reportedDiscovery = true
        }
        return
    }
    let config = NSWorkspace.OpenConfiguration(); config.activates = false; config.addsToRecentItems = false
    config.promptsUserIfNeeded = false; config.allowsRunningApplicationSubstitution = false
    let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenApplication),
        targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
    let list = NSAppleEventDescriptor.list()
    for (index, url) in urls.enumerated() { list.insert(NSAppleEventDescriptor(string: url.absoluteString), at: index + 1) }
    event.setParam(list, forKeyword: AEKeyword(0x69547271))
    config.appleEvent = event
    if launched == nil {
        config.arguments = ["--finder-direct-test"]
        config.environment = ["ITOOLS_FINDER_TEST_OUTPUT": output.path]
    }
    var done = false; var failure: Error?
    NSWorkspace.shared.openApplication(at: worker, configuration: config) { app, error in
        DispatchQueue.main.async { launched = app ?? launched; failure = error; done = true }
    }
    let deadline = Date().addingTimeInterval(20)
    while !done && Date() < deadline { pump(0.05) }
    check(done && failure == nil, "Launch Services: " + (failure?.localizedDescription ?? "timeout"))
}
func receipt(_ id: UUID, action: String, expectError: Bool = false) -> [String: Any] {
    let file = output.appendingPathComponent(id.uuidString + ".json")
    let deadline = Date().addingTimeInterval(30)
    while !fm.fileExists(atPath: file.path) && Date() < deadline { pump(0.05) }
    guard let data = try? Data(contentsOf: file), let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        finish("FAIL: no receipt for " + action, 2)
    }
    check(value["action"] as? String == action, "wrong action")
    check(value["visibleWindows"] as? Int == 0 && value["policy"] as? Int == 1, "worker opened a window or Dock app")
    let errors = value["errors"] as? [String] ?? []
    check(expectError ? !errors.isEmpty : errors.isEmpty, "unexpected errors: \(errors)")
    if let recycled = value["recycled"] as? [String: String] {
        // Restore only this test's fixtures from its isolated recycling backend.
        for (original, trashPath) in recycled {
            check(original.hasPrefix(output.path + "/") && !fm.fileExists(atPath: original), "unsafe fixture restore path")
            do { try fm.moveItem(atPath: trashPath, toPath: original) }
            catch { finish("FAIL: could not restore own recycled fixture: \(error)", 2) }
        }
    }
    if firstPID == nil { firstPID = value["pid"] as? Int }
    check(value["pid"] as? Int == firstPID, "warm request did not reuse worker")
    check(Set(NSRunningApplication.runningApplications(withBundleIdentifier: "app.itools.mac").map(\.processIdentifier)) == originalMainPIDs, "main app was launched")
    count += 1; print("PASS \(count): \(action), no main app/window, same accessory process")
    return value
}
@discardableResult func run(_ action: String, _ files: [URL], expectError: Bool = false) -> [String: Any] {
    let id = UUID(); deliver([requestURL(action, files, id: id)])
    return receipt(id, action: action, expectError: expectError)
}
let directory = output.appendingPathComponent("中文 空格 &action=delete #?", isDirectory: true)
let destination = output.appendingPathComponent("paste destination", isDirectory: true)
try fm.createDirectory(at: directory, withIntermediateDirectories: true)
try fm.createDirectory(at: destination, withIntermediateDirectories: true)
if sandboxSender != nil {
    // Launch Services strips sandbox callers' launch arguments and environment.
    // Test a real production cold start first, without any worker test hooks.
    let coldDirectory = output.appendingPathComponent("cold startup 中文 & #", isDirectory: true)
    try fm.createDirectory(at: coldDirectory, withIntermediateDirectories: true)
    deliver([requestURL("new-txt", [coldDirectory])])
    let coldFile = coldDirectory.appendingPathComponent("未命名.txt")
    let deadline = Date().addingTimeInterval(20)
    while !fm.fileExists(atPath: coldFile.path) && Date() < deadline { pump(0.05) }
    check(fm.fileExists(atPath: coldFile.path), "sandbox production cold start did not create TXT")
    check(try Data(contentsOf: coldFile).isEmpty, "cold TXT is not an empty file")
    check(Set(NSRunningApplication.runningApplications(withBundleIdentifier: "app.itools.mac").map(\.processIdentifier)) == originalMainPIDs,
          "sandbox cold start launched the main app")
    check(launched?.isActive == false, "sandbox cold start activated worker")
    // A second fresh menu click proves a running production worker receives oapp
    // as well, and that new files do not replace an existing file.
    try "preserve cold original".write(to: coldFile, atomically: true, encoding: .utf8)
    deliver([requestURL("new-txt", [coldDirectory])])
    let second = coldDirectory.appendingPathComponent("未命名 2.txt")
    let warmDeadline = Date().addingTimeInterval(20)
    while !fm.fileExists(atPath: second.path) && Date() < warmDeadline { pump(0.05) }
    let preserved = try String(contentsOf: coldFile)
    check(fm.fileExists(atPath: second.path) && preserved == "preserve cold original", "production warm request lost or overwrote original")
    print("PASS: sandbox production cold/warm TXT, actual files and Finder reveal, main app unchanged")
    pump(0.5)
    check(launched?.terminate() == true, "production worker refused graceful test exit")
    let quitDeadline = Date().addingTimeInterval(8)
    while launched?.isTerminated == false && Date() < quitDeadline { pump(0.05) }
    check(launched?.isTerminated == true, "production worker still busy; not force-quitting")
    launched = nil

    // Start the isolated test session from this ordinary harness, then send all
    // action requests from the sandbox. This keeps real Clipboard/Trash untouched.
    let config = NSWorkspace.OpenConfiguration()
    config.activates = false; config.addsToRecentItems = false; config.promptsUserIfNeeded = false
    config.allowsRunningApplicationSubstitution = false
    config.arguments = ["--finder-direct-test"]
    config.environment = ["ITOOLS_FINDER_TEST_OUTPUT": output.path]
    var ready = false; var failure: Error?
    NSWorkspace.shared.openApplication(at: worker, configuration: config) { app, error in
        DispatchQueue.main.async { launched = app; failure = error; ready = true }
    }
    let startDeadline = Date().addingTimeInterval(20)
    while !ready && Date() < startDeadline { pump(0.05) }
    check(ready && launched != nil && failure == nil, "test session launch failed: \(String(describing: failure))")
}
let plain = directory.appendingPathComponent("未命名.txt")
let first = run("new-txt", [directory])
check(fm.fileExists(atPath: plain.path) && (first["dialogs"] as? [String]) == [], "TXT did not execute directly")
try "keep this original".write(to: plain, atomically: true, encoding: .utf8)
run("new-txt", [directory])
check(fm.fileExists(atPath: directory.appendingPathComponent("未命名 2.txt").path), "duplicate filename not numbered")
check(try String(contentsOf: plain) == "keep this original", "original overwritten")
for ext in ["md", "rtf", "json", "html", "csv", "xml"] {
    run("new-" + ext, [directory])
    check(fm.fileExists(atPath: directory.appendingPathComponent("未命名." + ext).path), "missing " + ext)
}
let terminal = run("terminal", [plain])
check(terminal["terminalDirectory"] as? String == directory.path, "Terminal file parent mismatch")
let terminalFolder = run("terminal", [destination])
check(terminalFolder["terminalDirectory"] as? String == destination.path, "Terminal selected folder mismatch")
run("hide", [plain]); check(try plain.resourceValues(forKeys: [.isHiddenKey]).isHidden == true, "hide did not execute")
run("show", [plain]); check(try plain.resourceValues(forKeys: [.isHiddenKey]).isHidden == false, "show did not execute")
run("cut", [plain]); run("paste", [destination])
let moved = destination.appendingPathComponent(plain.lastPathComponent)
check(!fm.fileExists(atPath: plain.path) && fm.fileExists(atPath: moved.path), "cut/paste lost session or directory")
run("hash", [moved]); run("scan", [destination])
run("fast-zip", [moved]); run("fast-7z", [moved])
check(fm.fileExists(atPath: moved.path + ".zip") && fm.fileExists(atPath: moved.path + ".7z"), "preset did not archive alongside file")
let validation = run("archive-test", [URL(fileURLWithPath: moved.path + ".zip")])
check((validation["dialogs"] as? [String]) == ["校验压缩包…"], "plain archive requested extra password/input dialog")
let trash = run("trash", [moved])
check((trash["dialogs"] as? [String]) == [], "system Trash added confirmation")
check((trash["recycled"] as? [String: String])?[moved.path] != nil, "recycle callback lost the file mapping")
run("zip-trash", [moved])
let toDissolve = destination.appendingPathComponent("解散 fixture", isDirectory: true)
try fm.createDirectory(at: toDissolve, withIntermediateDirectories: true)
try "nested".write(to: toDissolve.appendingPathComponent("nested.txt"), atomically: true, encoding: .utf8)
run("dissolve", [toDissolve])
check(!fm.fileExists(atPath: toDissolve.path) && fm.fileExists(atPath: destination.appendingPathComponent("nested.txt").path), "dissolve did not execute directly")
try fm.setAttributes([.posixPermissions: 0o400], ofItemAtPath: moved.path)
run("writable", [moved])
let permissions = (try fm.attributesOfItem(atPath: moved.path)[.posixPermissions] as? NSNumber)?.intValue ?? 0
check(permissions & 0o200 != 0, "owner-write did not execute directly")
for application in ["system-default", NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit")!.path] {
    let id = UUID(); deliver([requestURL("open-with", [moved], id: id, application: application)])
    let opened = receipt(id, action: "open-with")
    check(!(opened["applications"] as? [String] ?? []).isEmpty && (opened["dialogs"] as? [String]) == [], "application choice added another picker")
}
run("new-txt", [directory.appendingPathComponent("missing")], expectError: true)
// Multiple delivered events must keep their own selections, including async work.
let a = UUID(), b = UUID(), c = UUID()
deliver([requestURL("hash", [moved], id: a), requestURL("new-txt", [directory], id: b), requestURL("new-txt", [destination], id: c)])
_ = receipt(a, action: "hash"); _ = receipt(b, action: "new-txt"); _ = receipt(c, action: "new-txt")
let before = try fm.contentsOfDirectory(atPath: destination.path)
deliver([requestURL("new-txt", [destination], id: c)]); pump(0.5)
check(try fm.contentsOfDirectory(atPath: destination.path) == before, "duplicate delivery executed twice")
check(NSWorkspace.shared.urlForApplication(toOpen: requestURL("new-txt", [directory])) == nil, "internal scheme registered globally")
finish("PASS: \(count) direct actions; sender=\(sandboxSender == nil ? "ordinary" : "sandboxed (write denial checked)"); cold/warm/queued/idempotent delivery; real fixture mutations; no main app or windows; app/Terminal URLs and recycle callbacks verified through isolated hooks; public internal-scheme lookup has no handler", 0)
