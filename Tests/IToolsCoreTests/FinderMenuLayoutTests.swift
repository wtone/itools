import XCTest
@testable import IToolsCore

final class FinderMenuLayoutTests: XCTestCase {
    func testSeparateVisibilityItemsBecomeOneWithoutLosingTopLevelPlacement() {
        for previous in [["show-hidden-files"], ["hide-hidden-files"], ["show-hidden-files", "hide-hidden-files"]] {
            let layout = FinderMenuLayout.decode(previous + ["terminal", "future-operation"])
            XCTAssertEqual(layout.topLevelIDs, [FinderActions.visibilityActionID, "terminal", "future-operation"])
            XCTAssertEqual(layout.topLevelActions.filter { $0.id == FinderActions.visibilityActionID }.count, 1)
            XCTAssertFalse(layout.remainingGroups.flatMap(\.actions).contains { $0.id == FinderActions.visibilityActionID })
        }
    }
    func testNewInstallKeepsAllActionsInSubmenu() {
        let layout = FinderMenuLayout.decode(nil)
        XCTAssertTrue(layout.topLevelActions.isEmpty)
        XCTAssertEqual(layout.remainingGroups.flatMap(\.actions).map(\.id), FinderActions.all.map(\.id))
    }
    func testSelectedActionsArePromotedWithoutLossOrDuplicates() {
        let ids: Set<String> = ["terminal", "new-txt", "open-with", "fast-zip", "delete"]
        let layout = FinderMenuLayout(topLevelIDs: ids)
        let top = layout.topLevelActions.map(\.id)
        let nested = layout.remainingGroups.flatMap(\.actions).map(\.id)
        XCTAssertEqual(top, FinderActions.all.filter { ids.contains($0.id) }.map(\.id))
        XCTAssertEqual(Set(top), ids)
        XCTAssertTrue(Set(top).isDisjoint(with: nested))
        XCTAssertEqual(top.count + nested.count, FinderActions.all.count)
        XCTAssertEqual(Set(top + nested), Set(FinderActions.all.map(\.id)))
    }
    func testEmptyGroupsAndEntireSubmenuDisappear() {
        let first = FinderActions.groups[0]
        let layout = FinderMenuLayout(topLevelIDs: Set(first.actions.map(\.id)))
        XCTAssertFalse(layout.remainingGroups.contains { $0.title == first.title })
        XCTAssertFalse(layout.remainingGroups.contains { $0.actions.isEmpty })
        let all = FinderMenuLayout(topLevelIDs: Set(FinderActions.all.map(\.id)))
        XCTAssertTrue(all.remainingGroups.isEmpty)
        XCTAssertEqual(all.topLevelActions.count, FinderActions.all.count)
    }
    func testUnknownFutureIDsArePreservedButNeverRendered() {
        let layout = FinderMenuLayout.decode(["new-txt", "new-txt", "future-operation"])
        XCTAssertEqual(layout.topLevelIDs, ["new-txt", "future-operation"])
        XCTAssertEqual(layout.topLevelActions.map(\.id), ["new-txt"])
        XCTAssertEqual(layout.remainingGroups.flatMap(\.actions).count, FinderActions.all.count - 1)
    }
    func testMalformedPreferencesFallBackWithoutRemovingActions() {
        for value: Any in ["terminal", ["terminal": true], [1, 2], true] {
            XCTAssertTrue(FinderMenuLayout.decode(value).topLevelIDs.isEmpty)
            XCTAssertEqual(FinderMenuLayout.decode(value).remainingGroups.flatMap(\.actions).count, FinderActions.all.count)
        }
    }
}
