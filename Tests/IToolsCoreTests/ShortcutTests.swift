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
    func testRemovedIntegrationBindingsReleaseKeysAndKeepOtherCustomizations() {
        let retired = ["page.应用集成", "companion.ishot", "companion.irightmouse", "companion.icopy", "companion.state"]
        let previous = ShortcutPreferences(actions: actions + retired.map { .init($0, $0, "应用集成") }, defaults: defaults)
        for (index, id) in retired.enumerated() { previous.set(.init(UInt32(index), 15), for: id) }
        previous.set(nil, for: "guide")
        previous.set(.init(17, 12), for: "clipboard")

        let upgraded = ShortcutPreferences(actions: actions, defaults: defaults)
        XCTAssertTrue(retired.allSatisfy { upgraded.bindings[$0] == nil })
        XCTAssertNil(upgraded.bindings["guide"])
        XCTAssertEqual(upgraded.bindings["clipboard"], .init(17, 12))
        // A retired app shortcut must no longer reserve its key or block a built-in action.
        for index in retired.indices { XCTAssertNil(upgraded.error(for: .init(UInt32(index), 15), action: "delete")) }
        upgraded.set(.init(0, 15), for: "delete")
        let restarted = ShortcutPreferences(actions: actions, defaults: defaults)
        XCTAssertEqual(restarted.bindings["delete"], .init(0, 15))
        XCTAssertEqual(restarted.bindings["clipboard"], .init(17, 12))
        XCTAssertTrue(retired.allSatisfy { restarted.bindings[$0] == nil })
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
    func testBottomPanelUsesAvailableScreenWidthAndClearsDock() {
        let visible = CGRect(x: 0, y: 78, width: 1440, height: 800)
        let panel = ClipboardPanelRules.bottomPanelFrame(visible: visible)
        XCTAssertEqual(panel.minX, 8); XCTAssertEqual(panel.maxX, 1432)
        XCTAssertEqual(panel.minY, 86)
        XCTAssertTrue(visible.contains(panel)); XCTAssertLessThanOrEqual(panel.height, 360)
    }
    func testBottomPanelFitsSmallAndOffsetDisplays() {
        for visible in [CGRect(x: -1920, y: -1080, width: 1920, height: 1040),
                        CGRect(x: 1440, y: 100, width: 800, height: 480),
                        CGRect(x: -500, y: -500, width: 600, height: 240)] {
            let panel = ClipboardPanelRules.bottomPanelFrame(visible: visible)
            XCTAssertTrue(visible.contains(panel)); XCTAssertEqual(panel.minY, visible.minY + 8)
            XCTAssertGreaterThan(panel.width, visible.width * 0.9); XCTAssertGreaterThan(panel.height, 0)
        }
    }
    func testNewPanelDefaultsToBottomAndKeepsExplicitVerticalChoice() {
        XCTAssertEqual(ClipboardPanelPreferences(defaults: defaults).layout, .horizontal)
        defaults.set(ClipboardLayout.vertical.rawValue, forKey: "clipboard.panel.layout")
        XCTAssertEqual(ClipboardPanelPreferences(defaults: defaults).layout, .vertical)
    }
}
