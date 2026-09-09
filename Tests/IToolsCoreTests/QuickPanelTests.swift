import XCTest
@testable import IToolsCore

final class QuickPanelTests: XCTestCase {
    var defaults: UserDefaults!
    var suite: String!
    override func setUp() {
        suite = "itools-quick-test-" + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }
    func testFreshDefaultsAndExplicitEmptyPersist() {
        let prefs = QuickPanelPreferences(defaults: defaults)
        XCTAssertEqual(prefs.actions, QuickAction.defaults)
        for action in QuickAction.defaults { prefs.set(action, enabled: false) }
        XCTAssertTrue(QuickPanelPreferences(defaults: defaults).actions.isEmpty)
    }
    func testReorderingAndVisibilitySurviveRelaunch() {
        let prefs = QuickPanelPreferences(defaults: defaults)
        prefs.set(.emptyTrash, enabled: true)
        prefs.move(.emptyTrash, by: -1)
        prefs.set(.lockScreen, enabled: false)
        prefs.showMetrics = false
        let next = QuickPanelPreferences(defaults: defaults)
        XCTAssertEqual(prefs.actions, next.actions); XCTAssertFalse(next.showMetrics)
        XCTAssertFalse(next.actions.contains(.lockScreen))
        XCTAssertEqual(next.actions[next.actions.count-2], .emptyTrash)
    }
    func testUnknownAndDuplicateActionsDoNotResetChoice() {
        defaults.set(["future","ocr","ocr","files"], forKey: QuickPanelPreferences.key)
        let prefs = QuickPanelPreferences(defaults: defaults)
        XCTAssertEqual(prefs.actions, [.ocr,.files])
        prefs.move(.ocr, by: -1); prefs.move(.files, by: 1)
        XCTAssertEqual(prefs.actions, [.ocr,.files])
    }
    func testSmokePreferencesNeverWriteUsersSettings() {
        defaults.set(["files"], forKey: QuickPanelPreferences.key)
        let prefs = QuickPanelPreferences(defaults: defaults, persist: false)
        prefs.reset(); prefs.showMetrics = false; prefs.move(.awake, by: 1)
        XCTAssertEqual(defaults.stringArray(forKey: QuickPanelPreferences.key), ["files"])
        XCTAssertNil(defaults.object(forKey: "quickPanel.showMetrics"))
    }
    func testCleaningTimeoutIndependentOfKeyboardInput() {
        var policy = CleaningEscapePolicy(now: 10)
        policy.key(code: 0, down: true, now: 20)
        XCTAssertFalse(policy.shouldExit(now: 69.9))
        XCTAssertTrue(policy.shouldExit(now: 70))
    }
    func testEscapeHoldIgnoresAutorepeatAndRequiresContinuousHold() {
        var policy = CleaningEscapePolicy(now: 0)
        policy.key(code: 53, down: true, now: 5)
        policy.key(code: 53, down: true, now: 6) // autorepeat must not extend the timer
        XCTAssertFalse(policy.shouldExit(now: 6.9))
        XCTAssertTrue(policy.shouldExit(now: 7))
        policy.key(code: 53, down: false, now: 7.1)
        XCTAssertFalse(policy.shouldExit(now: 8))
        policy.key(code: 53, down: true, now: 9)
        policy.key(code: 53, down: false, now: 9.5)
        policy.key(code: 53, down: true, now: 10)
        XCTAssertFalse(policy.shouldExit(now: 11)); XCTAssertTrue(policy.shouldExit(now: 12))
    }
}
