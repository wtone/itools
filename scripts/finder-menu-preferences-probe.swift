import Foundation

@main enum PreferencesProbe {
    static func main() {
        let args = CommandLine.arguments
        guard args.count >= 3 else { fatalError("probe read|write|remove test-key [action-ids]") }
        let key = args[2]
        guard key.hasPrefix("test.finder-menu.") else { fatalError("Only isolated test keys may be used") }
        switch args[1] {
        case "write":
            guard FinderMenuLayout(topLevelIDs: Set(args.dropFirst(3))).save(key: key) else { fatalError("Test preference save failed") }
        case "remove":
            CFPreferencesSetAppValue(key as CFString, nil, FinderMenuLayout.preferenceDomain as CFString)
            guard CFPreferencesAppSynchronize(FinderMenuLayout.preferenceDomain as CFString) else { fatalError("Test preference cleanup failed") }
        case "read":
            guard args.count == 4 else { fatalError("Supply test directory for sandbox write-denial check") }
            let denied = URL(fileURLWithPath: args[3]).appendingPathComponent("sandbox-denied-" + UUID().uuidString)
            do {
                try Data("sandbox check".utf8).write(to: denied)
                try? FileManager.default.removeItem(at: denied)
                fatalError("Reader was not sandboxed")
            } catch let error as NSError {
                guard error.domain == NSCocoaErrorDomain && error.code == NSFileWriteNoPermissionError else { fatalError("Unexpected sandbox error: \(error)") }
            }
            while readLine() != nil {
                let layout = FinderMenuLayout.load(key: key)
                let data = try! JSONSerialization.data(withJSONObject: layout.topLevelIDs.sorted())
                print(String(data: data, encoding: .utf8)!); fflush(stdout)
            }
        default: fatalError("Unknown mode")
        }
    }
}
