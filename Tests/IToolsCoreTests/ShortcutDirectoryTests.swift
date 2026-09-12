import XCTest
@testable import IToolsCore

final class ShortcutDirectoryTests: XCTestCase {
    private let actions: [ShortcutAction] = [
        .init("quick.clipboard", "剪贴板历史面板", "快捷操作"),
        .init("clipboard.next", "粘贴队列下一项", "剪贴板"),
        .init("quick.screenshot", "区域截图", "快捷操作"),
        .init("mark.画笔", "标注 · 画笔", "截图与标注"),
        .init("record.stop", "停止并保存录制", "录屏与录音"),
        .init("file.new-txt", "文本文件 · TXT", "文件 · 新建文件"),
        .init("file.move", "移动文件到…", "文件 · 移动、复制与整理"),
        .init("quick.leftWindow", "左半屏", "快捷操作"),
        .init("metric.cpu", "菜单栏显示 / 隐藏 CPU", "系统监控"),
        .init("system.settings", "打开系统设置", "系统应用"),
        .init("future.action", "未来功能", "未知分类")
    ]
    func testEveryActionHasExactlyOneCategoryAndSectionIncludingFutureActions() {
        let sections = ShortcutDirectory.sections(actions: actions, category: nil)
        let ids = sections.flatMap(\.actions).map(\.id)
        XCTAssertEqual(Set(ids), Set(actions.map(\.id)))
        XCTAssertEqual(ids.count, actions.count)
        XCTAssertFalse(sections.contains { $0.actions.isEmpty })
        XCTAssertEqual(Set(sections.map(\.id)).count, sections.count)
        XCTAssertEqual(ShortcutDirectory.location(of: actions.last!).0, .general)
    }
    func testQuickActionsJoinTheirFeatureInsteadOfRemainingInCatchAllGroup() {
        XCTAssertEqual(ShortcutDirectory.sections(actions: actions, category: .clipboard).flatMap(\.actions).map(\.id), ["quick.clipboard", "clipboard.next"])
        XCTAssertEqual(ShortcutDirectory.sections(actions: actions, category: .files).map(\.title), ["新建文件", "移动、复制与整理"])
        XCTAssertEqual(ShortcutDirectory.location(of: actions[7]).0, .windows)
    }
    func testGlobalSearchKeepsHierarchyAndSearchesKeyAndMultipleWords() {
        let bindings = ["file.new-txt": KeyChord(17, 5)]
        let found = ShortcutDirectory.sections(actions: actions, category: nil, query: "访达 TXT", bindings: bindings)
        XCTAssertEqual(found.first?.category, .files)
        XCTAssertEqual(found.first?.title, "新建文件")
        XCTAssertEqual(found.flatMap(\.actions).map(\.id), ["file.new-txt"])
        XCTAssertEqual(ShortcutDirectory.sections(actions: actions, category: nil, query: "⌥⌘T", bindings: bindings).flatMap(\.actions).map(\.id), ["file.new-txt"])
        XCTAssertTrue(ShortcutDirectory.sections(actions: actions, category: .capture, query: "TXT", bindings: bindings).isEmpty)
    }
    func testAssignedFilterDropsEmptySectionsWithoutLosingSearchSemantics() {
        let bindings = ["quick.clipboard": KeyChord(9, 5), "file.new-txt": KeyChord(17, 5)]
        let found = ShortcutDirectory.sections(actions: actions, category: nil, query: "  ", assignedOnly: true, bindings: bindings)
        XCTAssertEqual(found.flatMap(\.actions).count, 2)
        XCTAssertFalse(found.contains { $0.actions.isEmpty })
        XCTAssertTrue(ShortcutDirectory.sections(actions: actions, category: .system, assignedOnly: true, bindings: bindings).isEmpty)
        XCTAssertTrue(ShortcutDirectory.sections(actions: actions, category: nil, query: "not-present", bindings: bindings).isEmpty)
    }
}
