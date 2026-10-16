import XCTest
@testable import IToolsCore

final class MenuBarDisplaySelectionTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() {
        suite = "itools.tests.displays." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    func testExistingUsersStillFollowPrimaryDisplay() {
        let selection = MenuBarPreferences(defaults: defaults).displaySelection
        XCTAssertEqual(selection, MenuBarDisplaySelection())
        XCTAssertEqual(selection.resolvedDisplayIDs(available: ["laptop", "external"], primary: "laptop"), ["laptop"])
        XCTAssertEqual(selection.resolvedDisplayIDs(available: ["external", "laptop"], primary: "external"), ["external"])
    }
    func testAllDisplaysAdaptsToHotPlugAndUnplug() {
        let selection = MenuBarDisplaySelection(mode: .all)
        XCTAssertEqual(selection.resolvedDisplayIDs(available: ["laptop"], primary: "laptop"), ["laptop"])
        XCTAssertEqual(selection.resolvedDisplayIDs(available: ["laptop", "external", "third"], primary: "laptop"), ["laptop", "external", "third"])
        XCTAssertEqual(selection.resolvedDisplayIDs(available: ["external"], primary: "external"), ["external"])
        XCTAssertEqual(selection.resolvedDisplayIDs(available: [], primary: nil), [])
    }
    func testMissingSelectedDisplayFallsBackAndReturnsWithoutRewritingPreference() {
        let settings = MenuBarPreferences(defaults: defaults)
        settings.selectDisplay(id: "external", name: "工作屏")
        let disconnected = settings.displaySelection
        XCTAssertEqual(disconnected.resolvedDisplayIDs(available: ["laptop"], primary: "laptop"), ["laptop"])
        let reloaded = MenuBarPreferences(defaults: defaults).displaySelection
        XCTAssertEqual(reloaded, disconnected)
        XCTAssertEqual(reloaded.resolvedDisplayIDs(available: ["laptop", "external"], primary: "laptop"), ["external"])
    }
    func testExplicitDisplaySurvivesReorderMainDisplayChangeAndClamshell() {
        let selected = MenuBarDisplaySelection(displayID: "external", displayName: "工作屏")
        XCTAssertEqual(selected.resolvedDisplayIDs(available: ["external", "laptop"], primary: "external"), ["external"])
        XCTAssertEqual(selected.resolvedDisplayIDs(available: ["laptop", "external"], primary: "laptop"), ["external"])
        XCTAssertEqual(selected.resolvedDisplayIDs(available: ["external"], primary: "external"), ["external"])
        XCTAssertEqual(selected.resolvedDisplayIDs(available: [], primary: nil), [])
    }
    func testModeSwitchRetainsTargetAndDoesNotChangeMetricsOrNativePosition() {
        let key = "NSStatusItem Preferred Position iTools.metrics"
        defaults.set(420, forKey: key); defaults.set(false, forKey: "monitor.enabled")
        let settings = MenuBarPreferences(defaults: defaults)
        settings.set(.memory, enabled: true); settings.move(.memory, to: .cpu)
        let metrics = settings.visibleMetrics
        settings.selectDisplay(id: "external", name: "工作屏")
        settings.setDisplayMode(.all)
        let reloaded = MenuBarPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.displaySelection, .init(mode: .all, displayID: "external", displayName: "工作屏"))
        reloaded.setDisplayMode(.single)
        XCTAssertEqual(reloaded.displaySelection.resolvedDisplayIDs(available: ["laptop", "external"], primary: "laptop"), ["external"])
        XCTAssertEqual(reloaded.visibleMetrics, metrics)
        XCTAssertFalse(defaults.bool(forKey: "monitor.enabled"))
        XCTAssertEqual(defaults.double(forKey: key), 420)
    }
    func testSelectingFollowPrimaryClearsOnlyThePinnedTarget() {
        let settings = MenuBarPreferences(defaults: defaults)
        settings.selectDisplay(id: "external", name: "工作屏")
        settings.selectDisplay(id: nil, name: nil)
        XCTAssertEqual(MenuBarPreferences(defaults: defaults).displaySelection, .init())
        XCTAssertNil(defaults.object(forKey: MenuBarPreferences.displayIDKey))
        XCTAssertNil(defaults.object(forKey: MenuBarPreferences.displayNameKey))
    }
    func testNonpersistingSmokePreferencesDoNotChangeRealSettings() {
        let settings = MenuBarPreferences(defaults: defaults, persistChanges: false)
        settings.selectDisplay(id: "external", name: "工作屏"); settings.setDisplayMode(.all)
        XCTAssertEqual(settings.displaySelection.mode, .all)
        XCTAssertEqual(MenuBarPreferences(defaults: defaults).displaySelection, .init())
    }
    func testCorruptModeAndEmptyTargetHaveSafeDefault() {
        defaults.set("futureMode", forKey: MenuBarPreferences.displayModeKey)
        defaults.set("", forKey: MenuBarPreferences.displayIDKey)
        XCTAssertEqual(MenuBarPreferences(defaults: defaults).displaySelection, .init())
    }
    func testUnknownTopologyDoesNotCreateDuplicateOrInvisibleTargets() {
        XCTAssertEqual(MenuBarDisplaySelection(mode: .all).resolvedDisplayIDs(available: ["", "same", "same"], primary: "missing"), ["same"])
        XCTAssertEqual(MenuBarDisplaySelection(displayID: "missing").resolvedDisplayIDs(available: ["external"], primary: nil), ["external"])
    }
}
