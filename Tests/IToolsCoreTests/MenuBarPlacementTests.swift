import XCTest
@testable import IToolsCore

final class MenuBarPlacementTests: XCTestCase {
    private let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
    private let right = CGRect(x: 956, y: 1085, width: 772, height: 32)
    func testReportedDragPositionIsRejectedButOrdinarySavedPositionIsKept() {
        XCTAssertFalse(MenuBarPlacement.isSavedPositionUsable(835, screen: screen, rightArea: right))
        for value in [0.0, 60, 190, 700] {
            XCTAssertTrue(MenuBarPlacement.isSavedPositionUsable(value, screen: screen, rightArea: right))
        }
        for value in [-1.0, .nan, .infinity, 772, 9000] {
            XCTAssertFalse(MenuBarPlacement.isSavedPositionUsable(value, screen: screen, rightArea: right))
        }
    }
    func testActualWindowMustFitEntirelyToRightOfNotch() {
        XCTAssertFalse(MenuBarPlacement.isFrameVisible(CGRect(x: 677, y: 1080, width: 272, height: 37), screen: screen, rightArea: right))
        XCTAssertFalse(MenuBarPlacement.isFrameVisible(CGRect(x: 200, y: 1080, width: 272, height: 37), screen: screen, rightArea: right))
        XCTAssertTrue(MenuBarPlacement.isFrameVisible(CGRect(x: 1265, y: 1080, width: 272, height: 37), screen: screen, rightArea: right))
        XCTAssertTrue(MenuBarPlacement.isFrameVisible(CGRect(x: 956, y: 1080, width: 772, height: 37), screen: screen, rightArea: right))
        XCTAssertFalse(MenuBarPlacement.isFrameVisible(CGRect(x: 956, y: 1080, width: 773, height: 37), screen: screen, rightArea: right))
        XCTAssertFalse(MenuBarPlacement.isFrameVisible(.zero, screen: screen, rightArea: right))
    }
    func testNonNotchedPrimaryAndNegativeScreenOrigins() {
        let external = CGRect(x: -1920, y: 30, width: 1920, height: 1080)
        XCTAssertTrue(MenuBarPlacement.isSavedPositionUsable(835, screen: external, rightArea: nil))
        XCTAssertTrue(MenuBarPlacement.isFrameVisible(CGRect(x: -1800, y: 1086, width: 272, height: 24), screen: external, rightArea: nil))
        XCTAssertFalse(MenuBarPlacement.isFrameVisible(CGRect(x: -2000, y: 1086, width: 272, height: 24), screen: external, rightArea: nil))
        XCTAssertFalse(MenuBarPlacement.isFrameVisible(CGRect(x: -100, y: 1086, width: 272, height: 24), screen: external, rightArea: nil))
    }
}
