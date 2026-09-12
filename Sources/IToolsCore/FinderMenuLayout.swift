import Foundation

public struct FinderMenuLayout: Equatable {
    public static let preferenceDomain = "app.itools.mac.finder-menu"
    public static let preferenceKey = "topLevelActionIDs"
    public static let common = FinderMenuLayout(topLevelIDs: ["new-txt", "copy-path", "terminal"])
    public var topLevelIDs: Set<String>
    public init(topLevelIDs: Set<String> = []) { self.topLevelIDs = topLevelIDs }
    public var topLevelActions: [FinderAction] { FinderActions.all.filter { topLevelIDs.contains($0.id) } }
    public var remainingGroups: [FinderActionGroup] {
        FinderActions.groups.compactMap { group in
            let remaining = group.actions.filter { !topLevelIDs.contains($0.id) }
            return remaining.isEmpty ? nil : FinderActionGroup(title: group.title, icon: group.icon, actions: remaining)
        }
    }
    public static func displayTitle(_ action: FinderAction) -> String {
        action.id.hasPrefix("new-") && action.id != "new-template" ? "新建" + action.title : action.title
    }
    public static func topLevelTitle(_ action: FinderAction) -> String { "iTools · " + displayTitle(action) }
    public static func decode(_ value: Any?) -> FinderMenuLayout {
        FinderMenuLayout(topLevelIDs: Set(value as? [String] ?? []))
    }
    public static func load(key: String = preferenceKey) -> FinderMenuLayout {
        // Refresh on each menu opening, including when this extension was running
        // before the host changed the layout. The extension has read-only access
        // to this dedicated domain, which contains no other app settings.
        CFPreferencesAppSynchronize(preferenceDomain as CFString)
        return decode(CFPreferencesCopyAppValue(key as CFString, preferenceDomain as CFString))
    }
    @discardableResult public func save(key: String = preferenceKey) -> Bool {
        CFPreferencesSetAppValue(key as CFString, topLevelIDs.sorted() as CFArray, Self.preferenceDomain as CFString)
        return CFPreferencesAppSynchronize(Self.preferenceDomain as CFString)
    }
}
