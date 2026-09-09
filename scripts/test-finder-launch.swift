// Run against a built or installed bundle. Only stages synthetic requests; never executes file operations.
import AppKit

let args = CommandLine.arguments
 guard args.count == 3 else { fatalError("Usage: test-finder-launch.swift /path/iTools.app /path/output") }
let appURL = URL(fileURLWithPath: args[1]).standardizedFileURL
let output = URL(fileURLWithPath: args[2], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
guard NSRunningApplication.runningApplications(withBundleIdentifier: "app.itools.mac").isEmpty else {
    print("FAIL: close iTools normally before running this cold-start test"); exit(2)
}
let receipt = output.appendingPathComponent("receipt.json")
let first = output.appendingPathComponent("中文 空格 &action=delete.txt")
let second = output.appendingPathComponent("second-file.txt")
try "synthetic launch test".write(to: first, atomically: true, encoding: .utf8)
try "synthetic warm test".write(to: second, atomically: true, encoding: .utf8)
var launched: NSRunningApplication?
func finish(_ message: String, status: Int32) -> Never {
    if let app = launched, !app.isTerminated {
        app.terminate()
        let deadline = Date().addingTimeInterval(8)
        while !app.isTerminated && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        if !app.isTerminated { print("FAIL: test app refused normal termination"); exit(3) }
    }
    print(message); exit(status)
}
func request(action: String, file: URL, cold: Bool) -> [String: Any] {
    try? FileManager.default.removeItem(at: receipt)
    var components = URLComponents(); components.scheme = "itools"; components.host = "finder"
    components.queryItems = [.init(name: "action",value: action), .init(name: "path",value: file.path)]
    let config = NSWorkspace.OpenConfiguration(); config.activates = true
    if cold {
        config.arguments = ["--finder-launch-test", "-files.enabled", "YES"]
        config.environment = ["ITOOLS_FINDER_TEST_OUTPUT": output.path]
    }
    var finished = false; var failure: Error?
    NSWorkspace.shared.open([components.url!], withApplicationAt: appURL, configuration: config) { app, error in
        DispatchQueue.main.async { launched = app ?? launched; failure = error; finished = true }
    }
    let deadline = Date().addingTimeInterval(20)
    while Date() < deadline && (!finished || !FileManager.default.fileExists(atPath: receipt.path)) {
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        if failure != nil { break }
    }
    guard failure == nil, let data = try? Data(contentsOf: receipt), let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          result["action"] as? String == action, result["paths"] as? [String] == [file.path],
          result["page"] as? String == "访达与文件", result["windowVisible"] as? Bool == true,
          result["bundle"] as? String == appURL.path else {
        finish("FAIL: \(cold ? "cold" : "warm") delivery: \(failure?.localizedDescription ?? "missing or invalid receipt")", status: 4)
    }
    return result
}
let cold = request(action: "copy-path", file: first, cold: true)
let warm = request(action: "hash", file: second, cold: false)
guard cold["pid"] as? Int == warm["pid"] as? Int else { finish("FAIL: warm request launched a duplicate process", status: 5) }
guard (try String(contentsOf: first)) == "synthetic launch test", (try String(contentsOf: second)) == "synthetic warm test" else { finish("FAIL: test files changed", status: 6) }
finish("PASS: exact app path \(appURL.path); cold and warm URL delivery; correct action and special-character file path staged; main window visible; same process reused; files unchanged", status: 0)
