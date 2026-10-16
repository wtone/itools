import AppKit
import Carbon

/// Launch Services checks URL associations for sandboxed callers even when an
/// explicit application is supplied. Use an application-open event with a private
/// parameter instead; this needs neither a public URL handler nor Automation access.
public enum FinderLaunchEvent {
    public static let eventClass = AEEventClass(kCoreEventClass)
    public static let eventID = AEEventID(kAEOpenApplication)
    public static let requestsKey = AEKeyword(0x69547271) // iTrq
    public static let hostActionArgument = "--finder-visibility-action"

    public static func configuration(for urls: [URL]) -> NSWorkspace.OpenConfiguration? {
        guard !urls.isEmpty, urls.count <= 20, urls.allSatisfy({ FinderDirectRequest($0) != nil }) else { return nil }
        let event = NSAppleEventDescriptor(eventClass: eventClass, eventID: eventID,
                                           targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
                                           transactionID: AETransactionID(kAnyTransactionID))
        let list = NSAppleEventDescriptor.list()
        for (index, url) in urls.enumerated() { list.insert(NSAppleEventDescriptor(string: url.absoluteString), at: index + 1) }
        event.setParam(list, forKeyword: requestsKey)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.promptsUserIfNeeded = false
        configuration.allowsRunningApplicationSubstitution = false
        configuration.appleEvent = event
        if urls.allSatisfy({ FinderDirectRequest($0)?.action == FinderActions.visibilityActionID }) {
            configuration.arguments = [hostActionArgument]
        }
        return configuration
    }

    /// nil means malformed input; an ordinary launch without a request is empty.
    public static func requests(in event: NSAppleEventDescriptor) -> [URL]? {
        guard event.eventClass == eventClass, event.eventID == eventID else { return nil }
        guard let list = event.paramDescriptor(forKeyword: requestsKey) else { return [] }
        guard list.descriptorType == typeAEList, (1...20).contains(list.numberOfItems) else { return nil }
        var result: [URL] = []
        for index in 1...list.numberOfItems {
            guard let item = list.atIndex(index), item.descriptorType == typeUnicodeText,
                  let value = item.stringValue, value.utf8.count < 32768,
                  let url = URL(string: value), FinderDirectRequest(url) != nil else { return nil }
            result.append(url)
        }
        return result
    }
}
