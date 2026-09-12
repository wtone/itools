import XCTest
@testable import IToolsCore
final class PasteReadinessTests: XCTestCase {
    func testWaitsForTargetAndReleasedShortcutRatherThanFixedDelay() {
        XCTAssertEqual(PasteReadiness.evaluate(targetAlive: true, clipboardUnchanged: true, foreground: false, modifiersReleased: true, timedOut: false), .waiting)
        XCTAssertEqual(PasteReadiness.evaluate(targetAlive: true, clipboardUnchanged: true, foreground: true, modifiersReleased: false, timedOut: false), .waiting)
        XCTAssertEqual(PasteReadiness.evaluate(targetAlive: true, clipboardUnchanged: true, foreground: true, modifiersReleased: true, timedOut: false), .ready)
    }
    func testNeverPastesIntoClosedTargetOrOverwritesNewClipboard() {
        XCTAssertEqual(PasteReadiness.evaluate(targetAlive: false, clipboardUnchanged: true, foreground: true, modifiersReleased: true, timedOut: false), .targetClosed)
        XCTAssertEqual(PasteReadiness.evaluate(targetAlive: true, clipboardUnchanged: false, foreground: true, modifiersReleased: true, timedOut: false), .clipboardChanged)
    }
    func testTimeoutCannotSendToBackgroundOrWithHeldModifiers() {
        XCTAssertEqual(PasteReadiness.evaluate(targetAlive: true, clipboardUnchanged: true, foreground: true, modifiersReleased: true, timedOut: true), .timedOut)
        XCTAssertEqual(PasteReadiness.evaluate(targetAlive: true, clipboardUnchanged: true, foreground: false, modifiersReleased: true, timedOut: true), .timedOut)
        XCTAssertEqual(PasteReadiness.evaluate(targetAlive: true, clipboardUnchanged: true, foreground: true, modifiersReleased: false, timedOut: true), .timedOut)
    }
}
