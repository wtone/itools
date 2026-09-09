import XCTest
import CoreGraphics
@testable import IToolsCore

final class ClipboardTests: XCTestCase {
    func entry(_ text: String, date: Date = Date()) -> ClipEntry {
        ClipEntry(kind: .text, text: text, source: "test", payload: [.init(type: "public.utf8-plain-text", data: Data(text.utf8))], date: date)
    }
    func testDedupPreservesPinGroupAndIdentity() {
        var old = entry("hello", date: Date().addingTimeInterval(-10)); old.pinned = true; old.group = "工作"
        let updated = HistoryPolicy().adding(entry("hello"), to: [old])
        XCTAssertEqual(updated.count, 1); XCTAssertEqual(updated[0].id, old.id)
        XCTAssertTrue(updated[0].pinned); XCTAssertEqual(updated[0].group, "工作")
        XCTAssertGreaterThan(updated[0].date, old.date)
    }
    func testRetentionKeepsPinnedItemsAndRejectsExpiredHistory() {
        let now = Date(); let oldDate = now.addingTimeInterval(-40 * 86400)
        var pin = entry("pin", date: oldDate); pin.pinned = true
        let result = HistoryPolicy(retentionDays: 30).prune([entry("old", date: oldDate), pin, entry("new", date: now)], now: now)
        XCTAssertEqual(Set(result.map(\.text)), ["pin", "new"])
    }
    func testQuotaIncludesPinnedStorage() {
        var pin = entry("12345"); pin.pinned = true
        let result = HistoryPolicy(maxCount: 2, maxBytes: 12).adding(entry("abcdef"), to: [pin])
        XCTAssertEqual(result.map(\.text), ["12345"])
    }
    func testPinSurvivesLoweredQuota() {
        var pin = entry("large"); pin.pinned = true
        XCTAssertEqual(HistoryPolicy(maxCount: 0, maxBytes: 0).prune([pin]).count, 1)
    }
    func testFingerprintsAreSensitiveToDataAndIndependentOfRepresentationOrder() {
        var a = entry("hello")
        a.payload.append(.init(type: "public.rtf", data: Data([1,2,3])))
        var b = a; b.payload.reverse()
        XCTAssertEqual(a.fingerprint, b.fingerprint)
        b.payload[0].data.append(4)
        XCTAssertNotEqual(a.fingerprint, b.fingerprint)
    }
    func testSnippetVariables() {
        let date = Date(timeIntervalSince1970: 0)
        let result = Snippet(title: "test", body: "{{date}} / {{time}} / {{clipboard}}").expanded(clipboard: "abc", date: date)
        XCTAssertFalse(result.contains("{{")); XCTAssertTrue(result.hasSuffix(" / abc"))
    }
    func testCodableRoundTripPreservesBinaryAndUnicode() throws {
        var item = entry("中文🙂"); item.payload.append(.init(type: "public.png", data: Data([0,255,128])))
        XCTAssertEqual(try JSONDecoder().decode(ClipEntry.self, from: JSONEncoder().encode(item)), item)
    }
}
final class FileTests: XCTestCase {
    var folder: URL!
    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("itools-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { if let folder = folder { try FileManager.default.removeItem(at: folder) } }
    func testRejectsTraversalAndInvalidNames() {
        for name in ["", " ", ".", "..", "../escape", "a/b", "a\\b", "a:b", "a\nb", String(repeating: "a", count: 256)] {
            XCTAssertThrowsError(try FileOperations.validateName(name), name)
        }
        XCTAssertNoThrow(try FileOperations.validateName("中文 file🙂.txt"))
    }
    func testCreateDoesNotOverwriteExistingFile() throws {
        let file = try FileOperations.create(in: folder, name: "a.txt", data: Data("original".utf8))
        XCTAssertThrowsError(try FileOperations.create(in: folder, name: "a.txt", data: Data("replacement".utf8)))
        XCTAssertEqual(try String(contentsOf: file), "original")
    }
    func testCopyConflictPreservesBothFiles() throws {
        let destination = folder.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let source = try FileOperations.create(in: folder, name: "a.txt", data: Data("source".utf8))
        let target = try FileOperations.create(in: destination, name: "a.txt", data: Data("target".utf8))
        XCTAssertThrowsError(try FileOperations.transfer(source, to: destination, move: true))
        XCTAssertEqual(try String(contentsOf: source), "source"); XCTAssertEqual(try String(contentsOf: target), "target")
    }
    func testCannotMoveDirectoryIntoItself() throws {
        let child = folder.appendingPathComponent("child")
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        XCTAssertThrowsError(try FileOperations.transfer(folder, to: child, move: true))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
    }
    func testCopyAndMoveFilesWithShellCharactersAreLiteral() throws {
        let source = try FileOperations.create(in: folder, name: "$(touch bad) 'quoted'.txt", data: Data("ok".utf8))
        let destination = folder.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let copied = try FileOperations.transfer(source, to: destination, move: false)
        XCTAssertEqual(try String(contentsOf: copied), "ok")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }
    func testRenameCanSwapNamesWithoutDataLoss() throws {
        let a = try FileOperations.create(in: folder, name: "a.txt", data: Data("A".utf8))
        let b = try FileOperations.create(in: folder, name: "b.txt", data: Data("B".utf8))
        try FileOperations.executeRename([(a,b),(b,a)])
        XCTAssertEqual(try String(contentsOf: a), "B"); XCTAssertEqual(try String(contentsOf: b), "A")
    }
    func testRenameConflictDoesNotPartiallyRename() throws {
        let a = try FileOperations.create(in: folder, name: "a.txt", data: Data("A".utf8))
        let b = try FileOperations.create(in: folder, name: "b.txt", data: Data("B".utf8))
        let c = try FileOperations.create(in: folder, name: "c.txt", data: Data("C".utf8))
        XCTAssertThrowsError(try FileOperations.executeRename([(a,folder.appendingPathComponent("d.txt")),(b,c)]))
        XCTAssertEqual(try String(contentsOf: a), "A"); XCTAssertEqual(try String(contentsOf: b), "B"); XCTAssertEqual(try String(contentsOf: c), "C")
    }
    func testRenameRollsBackIfStagingFails() throws {
        let a = try FileOperations.create(in: folder, name: "a.txt", data: Data("A".utf8))
        XCTAssertThrowsError(try FileOperations.executeRename([(a,folder.appendingPathComponent("renamed.txt")), (folder.appendingPathComponent("missing.txt"),folder.appendingPathComponent("other.txt"))]))
        XCTAssertEqual(try String(contentsOf: a), "A")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("renamed.txt").path))
    }
    func testHashKnownVector() throws {
        let file = try FileOperations.create(in: folder, name: "input", data: Data("abc".utf8))
        XCTAssertEqual(try FileOperations.sha256(file), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
    func testUniqueNameUsesSuffix() throws {
        _ = try FileOperations.create(in: folder, name: "note.md")
        XCTAssertEqual(try FileOperations.uniqueURL(in: folder, name: "note.md").lastPathComponent, "note 2.md")
    }
}
final class GeometryAndLinkTests: XCTestCase {
    func testNegativeOriginDisplayGeometry() {
        let screen = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        XCTAssertEqual(WindowLayout.left.frame(in: screen, gap: 0), CGRect(x: -1920,y: -200,width: 960,height: 1080))
        XCTAssertEqual(WindowLayout.bottomRight.frame(in: screen,gap: 0), CGRect(x: -960,y: 340,width: 960,height: 540))
    }
    func testEveryLayoutRemainsWithinScreen() {
        let screen = CGRect(x: -1440,y: 500,width: 1440,height: 900)
        for layout in WindowLayout.allCases { let frame = layout.frame(in: screen); XCTAssertTrue(screen.contains(frame)); XCTAssertGreaterThan(frame.width,0); XCTAssertGreaterThan(frame.height,0) }
    }
    func testCleansTrackingWithoutRemovingBusinessParametersOrFragment() {
        XCTAssertEqual(LinkTools.clean("https://example.com/a?utm_source=x&id=42&token=keep&fbclid=a#section"), "https://example.com/a?id=42&token=keep#section")
        XCTAssertEqual(LinkTools.clean("https://example.com?utm_source=x"), "https://example.com")
    }
    func testUntouchedSignedAndNonWebInputs() {
        for input in ["file:///tmp/a?utm_x=a", "hello world", "https://example.com?a=%2F&signature=abc"] { XCTAssertEqual(LinkTools.clean(input),input) }
    }
    func testTranslationEscapesSpecialCharacters() throws {
        let text = "中文 & # ? + %"
        let url = try XCTUnwrap(LinkTools.translationURL(text: text))
        XCTAssertEqual(URLComponents(url: url,resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "text" })?.value, text)
    }
}
