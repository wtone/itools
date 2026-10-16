import XCTest
import AppKit
import Carbon
@testable import IToolsCore

final class FinderLaunchEventTests: XCTestCase {
    func testVisibilityToggleUsesQuietHostLaunchAndPreservesRequestIdentity() throws {
        let menu = try XCTUnwrap(FinderMenuRequests.makeURL(action: FinderActions.visibilityActionID, paths: []))
        let url = try XCTUnwrap(FinderDirectRequest.makeURL(from: menu))
        let config = try XCTUnwrap(FinderLaunchEvent.configuration(for: [url]))
        XCTAssertEqual(config.arguments, [FinderLaunchEvent.hostActionArgument])
        XCTAssertFalse(config.activates)
        XCTAssertEqual(FinderLaunchEvent.requests(in: try XCTUnwrap(config.appleEvent)), [url])
        XCTAssertTrue(try XCTUnwrap(FinderLaunchEvent.configuration(for: [request()])).arguments.isEmpty)
    }
    private func request(_ action: String = "new-txt") -> URL {
        FinderDirectRequest.makeURL(from: FinderMenuRequests.makeURL(action: action,
            paths: [URL(fileURLWithPath: "/tmp/中文 & 空格 #?.txt")])!)!
    }
    func testRoundTripOrderedRequestsAndNonactivatingLaunch() {
        let urls = [request(), request("terminal")]
        let config = FinderLaunchEvent.configuration(for: urls)!
        XCTAssertEqual(FinderLaunchEvent.requests(in: config.appleEvent!), urls)
        XCTAssertFalse(config.activates); XCTAssertFalse(config.addsToRecentItems)
        XCTAssertFalse(config.promptsUserIfNeeded); XCTAssertFalse(config.allowsRunningApplicationSubstitution)
        XCTAssertTrue(config.arguments.isEmpty)
    }
    func testRejectsPublicURLsAndOversizedBatches() {
        XCTAssertNil(FinderLaunchEvent.configuration(for: []))
        XCTAssertNil(FinderLaunchEvent.configuration(for: [URL(string: "itools://finder?action=delete&path=/tmp")!]))
        XCTAssertNil(FinderLaunchEvent.configuration(for: Array(repeating: request(), count: 21)))
    }
    func testOrdinaryLaunchDoesNothing() {
        let event = FinderLaunchEvent.configuration(for: [request()])!.appleEvent!
        event.removeParamDescriptor(withKeyword: FinderLaunchEvent.requestsKey)
        XCTAssertEqual(FinderLaunchEvent.requests(in: event), [])
    }
    func testMalformedListRejectsEntireBatchWithoutPartialExecution() {
        let event = FinderLaunchEvent.configuration(for: [request()])!.appleEvent!
        let list = event.paramDescriptor(forKeyword: FinderLaunchEvent.requestsKey)!
        list.insert(NSAppleEventDescriptor(string: "itools-finder-action://finder?action=unknown"), at: 2)
        event.setParam(list, forKeyword: FinderLaunchEvent.requestsKey)
        XCTAssertNil(FinderLaunchEvent.requests(in: event))
        event.setParam(NSAppleEventDescriptor(string: request().absoluteString), forKeyword: FinderLaunchEvent.requestsKey)
        XCTAssertNil(FinderLaunchEvent.requests(in: event))
        event.setParam(NSAppleEventDescriptor.list(), forKeyword: FinderLaunchEvent.requestsKey)
        XCTAssertNil(FinderLaunchEvent.requests(in: event))
    }
    func testRejectsOtherEventTypesAndNonTextItems() {
        let unrelated = NSAppleEventDescriptor(eventClass: AEEventClass(kInternetEventClass), eventID: AEEventID(kAEGetURL),
            targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        XCTAssertNil(FinderLaunchEvent.requests(in: unrelated))
        let event = FinderLaunchEvent.configuration(for: [request()])!.appleEvent!
        let list = NSAppleEventDescriptor.list(); list.insert(NSAppleEventDescriptor(int32: 1), at: 1)
        event.setParam(list, forKeyword: FinderLaunchEvent.requestsKey)
        XCTAssertNil(FinderLaunchEvent.requests(in: event))
    }
}
