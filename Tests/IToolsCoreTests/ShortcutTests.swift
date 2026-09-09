import XCTest
@testable import IToolsCore

final class ShortcutTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    let actions = [ShortcutAction("guide", "指南", "常用", "", .init(44,5)), ShortcutAction("clipboard", "剪贴板", "常用", "", .init(9,5)), ShortcutAction("delete", "删除", "文件")]
    override func setUp() { suite = "itools.shortcut-tests." + UUID().uuidString; defaults = UserDefaults(suiteName: suite)! }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }
    func testRejectTypingAndReservedEditingKeys() {
        XCTAssertNotNil(KeyChord(8,1).validationError); XCTAssertNotNil(KeyChord(1,0).validationError)
        XCTAssertNotNil(KeyChord(21,2).validationError); XCTAssertNotNil(KeyChord(53,12).validationError)
        XCTAssertNotNil(KeyChord(999,5).validationError); XCTAssertNil(KeyChord(9,5).validationError)
        XCTAssertEqual(KeyChord(9,7).display, "⌥⇧⌘V")
    }
    func testCollisionDoesNotChangeBinding() {
        let prefs = ShortcutPreferences(actions: actions, defaults: defaults)
        XCTAssertNotNil(prefs.error(for: .init(44,5), action: "clipboard"))
        prefs.set(.init(44,5), for: "clipboard")
        XCTAssertEqual(prefs.bindings["clipboard"], .init(9,5))
    }
    func testClearAndReassignSurvivesRestart() {
        let prefs = ShortcutPreferences(actions: actions, defaults: defaults)
        prefs.set(nil, for: "guide"); prefs.set(.init(44,5), for: "clipboard")
        let relaunched = ShortcutPreferences(actions: actions, defaults: defaults)
        XCTAssertNil(relaunched.bindings["guide"]); XCTAssertEqual(relaunched.bindings["clipboard"], .init(44,5))
        relaunched.reset(); XCTAssertEqual(relaunched.bindings["guide"], .init(44,5))
        XCTAssertEqual(relaunched.bindings["clipboard"], .init(9,5)); XCTAssertNil(relaunched.bindings["delete"])
    }
    func testUserAssignmentWinsOverNewDefaultOnUpgrade() {
        let prefs = ShortcutPreferences(actions: actions, defaults: defaults)
        prefs.set(.init(3,12), for: "delete")
        let upgraded = ShortcutPreferences(actions: actions + [.init("new", "新功能", "常用", "", .init(3,12))], defaults: defaults)
        XCTAssertEqual(upgraded.bindings["delete"], .init(3,12)); XCTAssertNil(upgraded.bindings["new"])
    }
    func testUnknownFutureAssignmentIsPreserved() {
        let extended = actions + [.init("future", "未来功能", "常用")]
        ShortcutPreferences(actions: extended, defaults: defaults).set(.init(3,12), for: "future")
        ShortcutPreferences(actions: actions, defaults: defaults).set(nil, for: "guide")
        XCTAssertEqual(ShortcutPreferences(actions: extended, defaults: defaults).bindings["future"], .init(3,12))
    }
    func testSmokeDoesNotPersistBindingsOrPanelSettings() {
        let prefs = ShortcutPreferences(actions: actions, defaults: defaults, persist: false)
        prefs.set(nil, for: "guide"); prefs.reset()
        let panel = ClipboardPanelPreferences(defaults: defaults, persist: false)
        panel.layout = .horizontal; panel.quickUse = .copy; panel.numberModifier = .command
        XCTAssertNil(defaults.data(forKey: "shortcuts.v1")); XCTAssertNil(defaults.string(forKey: "clipboard.panel.layout"))
    }
    func testPanelPreferencesSurviveRestart() {
        let panel = ClipboardPanelPreferences(defaults: defaults)
        panel.layout = .horizontal; panel.quickUse = .copy; panel.numberModifier = .command
        let restored = ClipboardPanelPreferences(defaults: defaults)
        XCTAssertEqual(restored.layout, .horizontal); XCTAssertEqual(restored.quickUse, .copy); XCTAssertEqual(restored.numberModifier, .command)
    }
    func testBareNumberDoesNotInterceptSearchOrIME() {
        XCTAssertNil(ClipboardPanelRules.numberIndex(key: 18, modifiers: 0, configured: .none, editing: true, composing: false))
        XCTAssertNil(ClipboardPanelRules.numberIndex(key: 18, modifiers: 1, configured: .command, editing: true, composing: true))
        XCTAssertEqual(ClipboardPanelRules.numberIndex(key: 18, modifiers: 1, configured: .command, editing: true, composing: false), 0)
        XCTAssertNil(ClipboardPanelRules.numberIndex(key: 18, modifiers: 2, configured: .shift, editing: true, composing: false))
    }
    func testDigitsKeypadAndModifierMustMatch() {
        for (index, key) in [18,19,20,21,23,22,26,28,25].enumerated() {
            XCTAssertEqual(ClipboardPanelRules.numberIndex(key: UInt32(key), modifiers: 0, configured: .none, editing: false, composing: false), index)
        }
        XCTAssertEqual(ClipboardPanelRules.numberIndex(key: 92, modifiers: 4, configured: .option, editing: false, composing: false), 8)
        XCTAssertNil(ClipboardPanelRules.numberIndex(key: 18, modifiers: 4, configured: .none, editing: false, composing: false))
        XCTAssertNil(ClipboardPanelRules.numberIndex(key: 29, modifiers: 0, configured: .none, editing: false, composing: false))
    }
    func testFilteringMatchesTypeGroupContentAndSource() {
        var entry = ClipEntry(kind: .text, text: "订单 2026", source: "com.example.Mail", payload: [])
        entry.pinned = true; entry.group = "工作"
        XCTAssertTrue(ClipboardPanelRules.matches(entry, query: "mail", kind: .text, group: "收藏"))
        XCTAssertTrue(ClipboardPanelRules.matches(entry, query: "2026", kind: nil, group: "工作"))
        XCTAssertFalse(ClipboardPanelRules.matches(entry, query: "", kind: .image, group: "全部"))
        XCTAssertFalse(ClipboardPanelRules.matches(entry, query: "", kind: nil, group: "其他"))
    }
    func testSelectionClampsAfterDeletionAndAtEnds() {
        XCTAssertEqual(ClipboardPanelRules.movedIndex(0, delta: -1, count: 5), 0)
        XCTAssertEqual(ClipboardPanelRules.movedIndex(4, delta: 1, count: 5), 4)
        XCTAssertEqual(ClipboardPanelRules.movedIndex(8, delta: 1, count: 2), 1)
        XCTAssertEqual(ClipboardPanelRules.movedIndex(8, delta: -1, count: 0), 0)
    }
    func testFloatingPanelFitsNegativeOriginAndSmallScreens() {
        for visible in [CGRect(x: -1440, y: -400, width: 1440, height: 878), CGRect(x: 0, y: 0, width: 800, height: 500)] {
            let panel = ClipboardPanelRules.panelFrame(size: CGSize(width: 1020, height: 670), visible: visible, anchor: CGPoint(x: visible.minX, y: visible.maxY))
            XCTAssertTrue(visible.contains(panel)); XCTAssertGreaterThan(panel.width, 0); XCTAssertGreaterThan(panel.height, 0)
        }
    }
}
