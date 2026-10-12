import XCTest
@testable import IToolsCore

final class CaptureDisplayGeometryTests: XCTestCase {
    func testSameSelectionOnMixedDPIDisplaysKeepsPointSizeAndNativePixels() throws {
        let local = CGRect(x: 200, y: 150, width: 640, height: 300)
        let primary = CaptureDisplayGeometry(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
        let external = CaptureDisplayGeometry(id: 2, frame: CGRect(x: -1920, y: 0, width: 1920, height: 1080), scale: 1)
        XCTAssertEqual(primary.localPixels(from: local), CGRect(x: 400, y: 300, width: 1280, height: 600))
        XCTAssertEqual(external.localPixels(from: local), local)
        XCTAssertEqual(primary.globalPoints(from: try XCTUnwrap(primary.localPixels(from: local))), local)
        let other = try XCTUnwrap(external.globalPoints(from: local))
        XCTAssertEqual(other, CGRect(x: -1720, y: 150, width: 640, height: 300))
        XCTAssertEqual(CaptureDisplayGeometry.quartzRect(fromGlobal: other, primaryTop: 900),
                       CGRect(x: -1720, y: 450, width: 640, height: 300))
    }

    func testDisplaysAboveBelowRightAndOffsetLeftKeepQuartzOrigins() throws {
        let cases: [(CGRect, CGRect)] = [
            (CGRect(x: 50, y: 900, width: 1920, height: 1080), CGRect(x: 250, y: -450, width: 640, height: 300)),
            (CGRect(x: 0, y: -1080, width: 1920, height: 1080), CGRect(x: 200, y: 1530, width: 640, height: 300)),
            (CGRect(x: 1440, y: 50, width: 1920, height: 1080), CGRect(x: 1640, y: 400, width: 640, height: 300)),
            (CGRect(x: -1920, y: 150, width: 1920, height: 1080), CGRect(x: -1720, y: 300, width: 640, height: 300))
        ]
        for (frame, expected) in cases {
            for scale in [CGFloat(1), 2] {
                let display = CaptureDisplayGeometry(id: 2, frame: frame, scale: scale)
                let pixels = try XCTUnwrap(display.localPixels(from: CGRect(x: 200, y: 150, width: 640, height: 300)))
                let global = try XCTUnwrap(display.globalPoints(from: pixels))
                XCTAssertEqual(CaptureDisplayGeometry.quartzRect(fromGlobal: global, primaryTop: 900), expected)
                XCTAssertEqual(display.localPoints(fromGlobal: global), CGRect(x: 200, y: 150, width: 640, height: 300))
            }
        }
    }

    func testDragOutsideDisplayClipsToThatDisplayWithoutCapturingItsNeighbour() {
        let display = CaptureDisplayGeometry(id: 2, frame: CGRect(x: -900, y: 80, width: 900, height: 700), scale: 2)
        XCTAssertEqual(display.localPixels(from: CGRect(x: -12, y: -10, width: 80, height: 70)),
                       CGRect(x: 0, y: 0, width: 136, height: 120))
        XCTAssertEqual(display.localPixels(from: CGRect(x: 800, y: 600, width: 300, height: 200)),
                       CGRect(x: 1600, y: 1200, width: 200, height: 200))
        XCTAssertNil(display.localPixels(from: CGRect(x: 901, y: 0, width: 100, height: 100)))
    }

    func testFractionalRetinaEdgesExpandToWholePixelsWithoutLosingContent() throws {
        let display = CaptureDisplayGeometry(id: 1, frame: CGRect(x: 0, y: 0, width: 1440, height: 900), scale: 2)
        let points = CGRect(x: 10.25, y: 20.5, width: 100.25, height: 120.1)
        let pixels = try XCTUnwrap(display.localPixels(from: points))
        XCTAssertEqual(pixels, CGRect(x: 20, y: 41, width: 201, height: 241))
        XCTAssertTrue(try XCTUnwrap(display.globalPoints(from: pixels)).contains(points))
    }

    func testMaskHoleExistsOnlyOnSelectedDisplay() {
        let primary = CaptureDisplayGeometry(id: 1, frame: CGRect(x: 0, y: 0, width: 800, height: 600), scale: 2)
        let external = CaptureDisplayGeometry(id: 2, frame: CGRect(x: -900, y: 80, width: 900, height: 700), scale: 1)
        let selection = CGRect(x: -800, y: 180, width: 600, height: 400)
        XCTAssertNil(primary.localPoints(fromGlobal: selection))
        XCTAssertEqual(external.localPoints(fromGlobal: selection), CGRect(x: 100, y: 100, width: 600, height: 400))
    }

    func testCaptureRoundTripAlsoWorksWhenPrimaryDisplayHasNonzeroBottom() throws {
        // NSScreen's first screen owns the global top-left coordinate origin. Its height
        // cannot be substituted for maxY if a topology snapshot has a nonzero bottom.
        let display = CaptureDisplayGeometry(id: 4, frame: CGRect(x: -500, y: -200, width: 1000, height: 800), scale: 2)
        let global = try XCTUnwrap(display.globalPoints(from: CGRect(x: 100, y: 200, width: 400, height: 300)))
        XCTAssertEqual(CaptureDisplayGeometry.quartzRect(fromGlobal: global, primaryTop: 600),
                       CGRect(x: -450, y: 550, width: 200, height: 150))
    }

    func testEmptyOrInvalidSelectionsFailWithoutCreatingAnOverlay() {
        let frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        let display = CaptureDisplayGeometry(id: 1, frame: frame, scale: 1)
        XCTAssertNil(display.localPixels(from: .zero))
        XCTAssertNil(display.localPixels(from: .null))
        XCTAssertNil(display.globalPoints(from: .zero))
        XCTAssertNil(display.globalPoints(from: CGRect(x: 900, y: 0, width: 100, height: 100)))
        XCTAssertNil(CaptureDisplayGeometry(id: 1, frame: frame, scale: 0).localPixels(from: frame))
        XCTAssertNil(CaptureDisplayGeometry(id: 1, frame: frame, scale: .infinity).localPixels(from: frame))
    }
}
