import Foundation

public enum MenuBarDisplayMode: String, CaseIterable, Identifiable {
    case single, all
    public var id: String { rawValue }
    public var title: String { self == .all ? "所有屏幕" : "仅一个屏幕" }
}

/// A persisted preference, independent of the current display topology.
/// A missing target falls back temporarily; never replace the saved UUID.
public struct MenuBarDisplaySelection: Equatable {
    public let mode: MenuBarDisplayMode
    public let displayID: String?
    public let displayName: String?

    public init(mode: MenuBarDisplayMode = .single, displayID: String? = nil, displayName: String? = nil) {
        self.mode = mode
        self.displayID = displayID?.isEmpty == false ? displayID : nil
        self.displayName = self.displayID == nil ? nil : displayName
    }

    public func resolvedDisplayIDs(available: [String], primary: String?) -> [String] {
        var seen: Set<String> = []
        let connected = available.filter { !$0.isEmpty && seen.insert($0).inserted }
        if mode == .all { return connected }
        if let displayID, connected.contains(displayID) { return [displayID] }
        if let primary, connected.contains(primary) { return [primary] }
        return Array(connected.prefix(1))
    }
}
