import XCTest
@testable import IToolsCore

final class FinderVisibilityTests: XCTestCase {
    func testGlobalDisplayActionsWorkWithoutSelectionAndRemainDistinctFromFileAttributes() throws {
        XCTAssertEqual(Set(FinderActions.all.filter { !$0.requiresPaths }.map(\.id)), [FinderActions.visibilityActionID])
        for id in [FinderActions.visibilityActionID] {
            let menu = try XCTUnwrap(FinderMenuRequests.makeURL(action: id, paths: []))
            let encoded = try XCTUnwrap(FinderDirectRequest.makeURL(from: menu))
            let decoded = try XCTUnwrap(FinderDirectRequest(encoded))
            XCTAssertEqual(decoded.action, id)
            XCTAssertTrue(decoded.paths.isEmpty)
        }
        for id in ["hide", "show", "extension", "delete"] {
            XCTAssertTrue(try XCTUnwrap(FinderActions.action(id)).requiresPaths)
            XCTAssertNil(FinderMenuRequests.makeURL(action: id, paths: []))
            let url = URL(string: "itools-finder-action://finder?action=\(id)&request=\(UUID().uuidString)")!
            XCTAssertNil(FinderDirectRequest(url))
        }
    }
}
