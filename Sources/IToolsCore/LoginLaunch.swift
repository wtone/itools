import AppKit
import Carbon

/// Shared by the app and its small login helper. No shell commands or saved absolute paths.
public enum LoginLaunch {
    public static let helperID = "app.itools.mac.login"
    public static let helperPath = "Contents/Library/LoginItems/iTools Login.app"

    public static func hostURL(for helperURL: URL) -> URL? {
        let helper = helperURL.resolvingSymlinksInPath().standardizedFileURL
        let host = helper.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        guard host.appendingPathComponent(helperPath).standardizedFileURL == helper,
              let bundle = Bundle(url: host), bundle.bundleIdentifier == "app.itools.mac",
              let executable = bundle.executableURL,
              FileManager.default.isExecutableFile(atPath: executable.path) else { return nil }
        return host
    }

    public static func isLoginEvent(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let event = event, event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEOpenApplication),
              let property = event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData)) else { return false }
        return (property.descriptorType == typeEnumerated || property.descriptorType == typeType)
            && property.typeCodeValue == keyAELaunchedAsLogInItem
    }

    public static func configuration() -> NSWorkspace.OpenConfiguration {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.promptsUserIfNeeded = false
        configuration.allowsRunningApplicationSubstitution = false
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAEOpenApplication), targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(NSAppleEventDescriptor(enumCode: OSType(keyAELaunchedAsLogInItem)), forKeyword: AEKeyword(keyAEPropData))
        configuration.appleEvent = event
        return configuration
    }
}
