import Foundation

/// Finder sends a reconstructed NSMenuItem back across process boundaries. Keep
/// the payload in the extension and route using the integer tag, not representedObject.
public final class FinderMenuRequests {
    private var nextTag = 1
    private var menus: [[Int: URL]] = []
    public init() {}
    public func beginMenu() {
        menus.append([:])
        // Keep the previous menu while Finder finishes delivering an in-flight click.
        if menus.count > 4 { menus.removeFirst(menus.count - 4) }
    }
    public func insert(_ url: URL) -> Int {
        if menus.isEmpty { beginMenu() }
        let tag = nextTag; nextTag += 1
        menus[menus.count - 1][tag] = url
        return tag
    }
    public func request(tag: Int) -> URL? { menus.reversed().compactMap { $0[tag] }.first }
    public static func makeURL(action: String, paths: [URL], application: String? = nil) -> URL? {
        guard FinderActions.action(action) != nil, !paths.isEmpty, paths.count <= 200,
              paths.allSatisfy({ $0.isFileURL && !$0.path.contains("\0") }) else { return nil }
        var components = URLComponents(); components.scheme = "itools"; components.host = "finder"
        components.queryItems = [.init(name: "action", value: action)] + paths.map { .init(name: "path", value: $0.path) }
        if let application = application {
            guard action == "open-with", FinderDirectRequest.validApplication(application) else { return nil }
            components.queryItems?.append(.init(name: "application", value: application))
        }
        guard let url = components.url, url.absoluteString.utf8.count < 32768 else { return nil }
        return url
    }
}

public enum FinderHostLocation {
    public static let bundleID = "app.itools.mac"
    public static let workerBundleID = "app.itools.mac.finder-actions"
    public static func worker(in host: URL) -> URL { host.appendingPathComponent("Contents/Helpers/iTools Finder Actions.app", isDirectory: true) }
    public static func isWorker(_ url: URL) -> Bool {
        guard let bundle = Bundle(url: url), bundle.bundleIdentifier == workerBundleID,
              let executable = bundle.executableURL else { return false }
        return FileManager.default.isExecutableFile(atPath: executable.path)
    }
    public static func containingApplication(extensionURL: URL) -> URL? {
        guard extensionURL.isFileURL, extensionURL.pathExtension == "appex" else { return nil }
        let plugins = extensionURL.deletingLastPathComponent()
        let contents = plugins.deletingLastPathComponent()
        let app = contents.deletingLastPathComponent()
        guard plugins.lastPathComponent == "PlugIns", contents.lastPathComponent == "Contents", app.pathExtension == "app" else { return nil }
        return app.standardizedFileURL
    }
    public static func resolve(extensionURL: URL, fallbacks: [URL], valid: (URL) -> Bool) -> URL? {
        let candidates = containingApplication(extensionURL: extensionURL).map { [$0] } ?? []
        var visited = Set<URL>()
        return (candidates + fallbacks).map(\.standardizedFileURL).first { visited.insert($0).inserted && valid($0) }
    }
    public static func isHost(_ url: URL) -> Bool {
        guard url.isFileURL, url.pathExtension == "app", let bundle = Bundle(url: url), bundle.bundleIdentifier == bundleID,
              let executable = bundle.executableURL else { return false }
        return FileManager.default.isExecutableFile(atPath: executable.path)
    }
}

/// This scheme is intentionally NOT registered with Launch Services. Only an
/// application-open event carries it as data to the accessory worker. Do not
/// pass it to NSWorkspace.open(urls:): sandboxed callers require a URL association.
/// The public itools:// route remains a review-only import in the main app.
public struct FinderDirectRequest {
    public static let scheme = "itools-finder-action"
    public let id: UUID
    public let action: String
    public let paths: [URL]
    public let application: String?
    public static func validApplication(_ value: String) -> Bool {
        value == "system-default" || (value.hasPrefix("/") && !value.contains("\0") && URL(fileURLWithPath: value).pathExtension == "app")
    }
    public static func makeURL(from menuURL: URL, id: UUID = UUID()) -> URL? {
        guard var c = URLComponents(url: menuURL, resolvingAgainstBaseURL: false) else { return nil }
        c.scheme = scheme
        c.queryItems = (c.queryItems ?? []) + [.init(name: "request", value: id.uuidString)]
        guard let url = c.url, FinderDirectRequest(url) != nil else { return nil }
        return url
    }
    public init?(_ url: URL) {
        guard url.absoluteString.utf8.count < 32768,
              let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.scheme == Self.scheme, c.host == "finder", c.user == nil, c.password == nil,
              c.port == nil, c.path.isEmpty, c.fragment == nil else { return nil }
        let items = c.queryItems ?? []
        guard items.allSatisfy({ ["action", "path", "request", "application"].contains($0.name) && $0.value != nil }),
              items.filter({ $0.name == "action" }).count == 1,
              let action = items.first(where: { $0.name == "action" })?.value, FinderActions.action(action) != nil,
              items.filter({ $0.name == "request" }).count == 1,
              let token = items.first(where: { $0.name == "request" })?.value, let id = UUID(uuidString: token) else { return nil }
        let paths = items.filter { $0.name == "path" }.compactMap(\.value)
        let applications = items.filter { $0.name == "application" }.compactMap(\.value)
        guard applications.count <= 1, applications.allSatisfy({ action == "open-with" && Self.validApplication($0) }) else { return nil }
        guard !paths.isEmpty, paths.count <= 200,
              paths.allSatisfy({ $0.hasPrefix("/") && !$0.contains("\0") }) else { return nil }
        self.id = id; self.action = action
        self.paths = paths.map { URL(fileURLWithPath: $0).standardizedFileURL }
        self.application = applications.first
    }
}

public enum FinderApplications {
    /// Preserve Launch Services preference order; multi-selection must be supported by every app.
    public static func common(for paths: [URL], lookup: (URL) -> [URL]) -> [URL] {
        guard let first = paths.first else { return [] }
        var seen = Set<URL>()
        var candidates = lookup(first).map(\.standardizedFileURL).filter { seen.insert($0).inserted }
        for path in paths.dropFirst() {
            let supported = Set(lookup(path).map(\.standardizedFileURL))
            candidates.removeAll { !supported.contains($0) }
            if candidates.isEmpty { break }
        }
        return candidates
    }
}
