import XCTest
@testable import IToolsCore

final class MenuPanelPlacementTests: XCTestCase {
    private let main = MenuPanelScreen(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                       visibleFrame: CGRect(x: 0, y: 64, width: 1440, height: 812))
    private func external(x: CGFloat, y: CGFloat, width: CGFloat = 1920, height: CGFloat = 1080) -> MenuPanelScreen {
        MenuPanelScreen(id: 2, frame: CGRect(x: x, y: y, width: width, height: height),
                        visibleFrame: CGRect(x: x, y: y, width: width, height: height - 24))
    }
    func testExternalClickWinsOverPrimaryStatusButtonReplica() throws {
        let other = external(x: 1440, y: 0)
        let placement = try XCTUnwrap(MenuPanelPlacement.resolve(pointer: CGPoint(x: 2400, y: 1070), screens: [main, other],
            buttonRect: CGRect(x: 1000, y: 876, width: 40, height: 24)))
        XCTAssertEqual(placement.screenID, 2)
        XCTAssertTrue(other.visibleFrame.contains(placement.frame))
        XCTAssertEqual(placement.frame.midX, 2400)
    }
    func testLeftAboveAndBelowDisplaysKeepTheirGlobalCoordinateOrigins() throws {
        for other in [external(x: -1920, y: 150), external(x: 50, y: 900), external(x: 0, y: -1080)] {
            let pointer = CGPoint(x: other.frame.midX, y: other.frame.maxY - 8)
            let placement = try XCTUnwrap(MenuPanelPlacement.resolve(pointer: pointer, screens: [main, other]))
            XCTAssertEqual(placement.screenID, 2)
            XCTAssertTrue(other.visibleFrame.contains(placement.frame))
            XCTAssertEqual(placement.frame.midX, pointer.x)
        }
    }
    func testBothMenuEdgesKeepPanelAndArrowInsideDisplay() throws {
        for x in [CGFloat(1), 1439] {
            let placement = try XCTUnwrap(MenuPanelPlacement.resolve(pointer: CGPoint(x: x, y: 888), screens: [main]))
            XCTAssertTrue(main.visibleFrame.contains(placement.frame))
            XCTAssertGreaterThanOrEqual(placement.arrowX, 24)
            XCTAssertLessThanOrEqual(placement.arrowX, placement.frame.width - 24)
        }
    }
    func testSmallDisplayFitsWithoutTheOldMinimumHeightOverflow() throws {
        let small = external(x: 1440, y: 0, width: 480, height: 360)
        let placement = try XCTUnwrap(MenuPanelPlacement.resolve(pointer: CGPoint(x: 1600, y: 350), screens: [main, small]))
        XCTAssertTrue(small.visibleFrame.contains(placement.frame))
        XCTAssertLessThan(placement.frame.height, 360)
        XCTAssertLessThan(placement.frame.width, 480)
    }
    func testShortcutUsesPointerDisplayAndFallbackHandlesMissingScreens() throws {
        let other = external(x: 1440, y: 0)
        let placement = try XCTUnwrap(MenuPanelPlacement.resolve(pointer: CGPoint(x: 2000, y: 400), screens: [main, other]))
        XCTAssertEqual(placement.screenID, 2)
        XCTAssertEqual(placement.frame.maxY, other.visibleFrame.maxY - 8)
        XCTAssertNil(MenuPanelPlacement.resolve(pointer: .zero, screens: []))
        let fallback = try XCTUnwrap(MenuPanelPlacement.resolve(pointer: CGPoint(x: -9999, y: -9999), screens: [main]))
        XCTAssertTrue(main.visibleFrame.contains(fallback.frame))
    }
    func testButtonResizingDoesNotChangeExternalPlacementSnapshot() throws {
        let other = external(x: 1440, y: 0), pointer = CGPoint(x: 2500, y: 1068)
        let expected = try XCTUnwrap(MenuPanelPlacement.resolve(pointer: pointer, screens: [main, other]))
        for width in [CGFloat(30), 42, 70, 90] {
            let actual = MenuPanelPlacement.resolve(pointer: pointer, screens: [main, other],
                buttonRect: CGRect(x: 1000, y: 876, width: width, height: 24))
            XCTAssertEqual(actual, expected)
        }
    }
}
