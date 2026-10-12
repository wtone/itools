import XCTest
@testable import IToolsCore

final class VideoTrimTests: XCTestCase {
    func testValidRangeAndWhitespace() throws {
        XCTAssertEqual(try VideoTrimRange.validate(start: " 0 ", end: "12.5", duration: 12.5), 0..<12.5)
        XCTAssertEqual(try VideoTrimRange.validate(start: "1.25", end: "2.5", duration: 10), 1.25..<2.5)
    }
    func testInvalidUserInputAndUnavailableDuration() {
        for (start, end, duration) in [("abc", "2", 10.0), ("-1", "2", 10), ("2", "2", 10),
                                      ("3", "2", 10), ("0", "11", 10), ("nan", "2", 10),
                                      ("0", "inf", 10), ("0", "2", Double.nan), ("0", "2", 0)] {
            XCTAssertThrowsError(try VideoTrimRange.validate(start: start, end: end, duration: duration))
        }
    }
}
