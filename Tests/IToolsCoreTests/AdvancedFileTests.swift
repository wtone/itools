import XCTest
import Darwin
@testable import IToolsCore

final class AdvancedFileTests: XCTestCase {
    var root: URL!
    var engine: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Vendor/7zip/7zz") }
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("itools-advanced-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }
    func folder(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false); return url
    }
    func file(_ name: String, in directory: URL? = nil, text: String = "synthetic") throws -> URL {
        try FileOperations.create(in: directory ?? root, name: name, data: Data(text.utf8))
    }
    func testNamedFoldersKeepSourcesAndRefuseConflicts() throws {
        let a = try file("报告.txt")
        let plan = try AdvancedFiles.namedFolderPlan([a]); try AdvancedFiles.createFolders(plan)
        XCTAssertEqual(try String(contentsOf: a), "synthetic")
        XCTAssertTrue(AdvancedFiles.exists(root.appendingPathComponent("报告")))
        XCTAssertThrowsError(try AdvancedFiles.namedFolderPlan([a]))
    }
    func testDissolveMovesHiddenChildrenWithoutLosingData() throws {
        let parent = try folder("a")
        _ = try file(".hidden", in: parent); _ = try file("b.txt", in: parent, text: "payload")
        let plan = try AdvancedFiles.dissolvePlan([parent])
        XCTAssertTrue(try AdvancedFiles.dissolve([parent], expected: plan).isEmpty)
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("b.txt")), "payload")
        XCTAssertTrue(AdvancedFiles.exists(root.appendingPathComponent(".hidden")))
        XCTAssertFalse(AdvancedFiles.exists(parent))
    }
    func testDissolveRejectsCrossFolderConflictsBeforeMoving() throws {
        let a = try folder("a"); let b = try folder("b")
        let af = try file("same", in: a); let bf = try file("same", in: b)
        XCTAssertThrowsError(try AdvancedFiles.dissolvePlan([a,b]))
        XCTAssertTrue(AdvancedFiles.exists(af)); XCTAssertTrue(AdvancedFiles.exists(bf))
    }
    func testDissolveRefusesChangedPreviewAndSymlinkFolders() throws {
        let a = try folder("a"); _ = try file("one", in: a)
        let plan = try AdvancedFiles.dissolvePlan([a]); _ = try file("two", in: a)
        XCTAssertThrowsError(try AdvancedFiles.dissolve([a], expected: plan))
        let link = root.appendingPathComponent("link"); try FileManager.default.createSymbolicLink(at: link, withDestinationURL: a)
        XCTAssertThrowsError(try AdvancedFiles.dissolvePlan([link]))
    }
    func testDanglingSymlinkCountsAsConflict() throws {
        let a = try folder("a"); _ = try file("child", in: a)
        let link = root.appendingPathComponent("child")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: root.appendingPathComponent("absent"))
        XCTAssertTrue(AdvancedFiles.exists(link))
        XCTAssertThrowsError(try AdvancedFiles.dissolvePlan([a]))
    }
    func testGrantWriteKeepsOtherBitsAndRefusesSymlink() throws {
        let source = try file("readonly"); try FileManager.default.setAttributes([.posixPermissions: 0o440], ofItemAtPath: source.path)
        try AdvancedFiles.grantOwnerWrite(source)
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: source.path)[.posixPermissions] as? NSNumber)?.intValue, 0o640)
        let link = root.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: source)
        XCTAssertThrowsError(try AdvancedFiles.grantOwnerWrite(link))
    }
    func testDeletionRefusesProtectedDirectoriesAndNestedSelection() throws {
        XCTAssertThrowsError(try AdvancedFiles.validateDeletion([URL(fileURLWithPath: "/")]))
        XCTAssertThrowsError(try AdvancedFiles.validateDeletion([FileManager.default.homeDirectoryForCurrentUser]))
        let a = try folder("a"); let f = try file("f", in: a)
        XCTAssertThrowsError(try AdvancedFiles.validateDeletion([a,f]))
        XCTAssertNoThrow(try AdvancedFiles.validateDeletion([f]))
    }
    func testFilenameRepairIsLosslessAndDoesNotGuessNormalNames() throws {
        let broken = String(data: Data("中文 café.txt".utf8), encoding: .isoLatin1)!
        XCTAssertEqual(FilenameRepair.latin1UTF8.repair(broken), "中文 café.txt")
        XCTAssertNil(FilenameRepair.latin1UTF8.repair("normal.txt"))
        XCTAssertNil(FilenameRepair.latin1UTF8.repair("中文.txt"))
    }
    func testScannerIncludesHiddenFilesAndDoesNotFollowLinks() throws {
        let a = try folder("a"); _ = try file("one", in: a, text: "12345"); _ = try file(".hidden", in: a, text: "123")
        try FileManager.default.createSymbolicLink(at: a.appendingPathComponent("loop"), withDestinationURL: root)
        let result = try DiskScanner.scan(root, cancellation: ScanCancellation())
        XCTAssertEqual(result.count, 1); XCTAssertEqual(result[0].bytes, 8); XCTAssertEqual(result[0].files, 2)
        let cancelled = ScanCancellation(); cancelled.cancel()
        XCTAssertTrue(try DiskScanner.scan(root, cancellation: cancelled).isEmpty)
    }
    func testSnapshotDetectsModifiedAndAddedFiles() throws {
        let a = try folder("a"); let f = try file("file", in: a)
        let old = try FileSnapshot.capture([a]); try Data("changed!".utf8).write(to: f)
        XCTAssertNotEqual(old, try FileSnapshot.capture([a]))
        let updated = try FileSnapshot.capture([a]); _ = try file(".new", in: a)
        XCTAssertNotEqual(updated, try FileSnapshot.capture([a]))
    }
    func testArchiveZIPAnd7zRoundTripWithLiteralFilenames() throws {
        for format in ["zip", "7z"] {
            let source = try folder(format)
            let f = try file("-@ 中文 [*] $(literal).txt", in: source, text: "exact data")
            let archive = root.appendingPathComponent("result." + format)
            try ArchiveEngine.create([f], at: archive, executable: engine, options: .init(format: format, level: 0))
            let output = try folder(format + "-out")
            try ArchiveEngine.run(executable: engine, arguments: ["x", "-o" + output.path, "--", archive.path], directory: nil, password: nil)
            XCTAssertEqual(try String(contentsOf: output.appendingPathComponent(f.lastPathComponent)), "exact data")
            XCTAssertTrue(AdvancedFiles.exists(f))
        }
    }
    func testArchiveAcrossDirectoriesPreservesRelativeTreeAndHiddenFiles() throws {
        let a = try folder("a"); let b = try folder("b")
        let af = try file(".same", in: a, text: "first")
        let bf = try file(".same", in: b, text: "second")
        for format in ["zip", "7z"] {
            let archive = root.appendingPathComponent("multiple." + format)
            try ArchiveEngine.create([af, bf], at: archive, executable: engine, options: .init(format: format))
            let output = try folder("extracted-" + format)
            try ArchiveEngine.run(executable: engine, arguments: ["x", "-o" + output.path, "--", archive.path], directory: nil, password: nil)
            XCTAssertEqual(try String(contentsOf: output.appendingPathComponent("a/.same")), "first")
            XCTAssertEqual(try String(contentsOf: output.appendingPathComponent("b/.same")), "second")
        }
    }
    func testEncryptedArchivesAcceptCorrectPasswordRejectWrongPassword() throws {
        let f = try file("private.txt")
        for format in ["zip", "7z"] {
            let archive = root.appendingPathComponent("encrypted." + format)
            let password = format == "zip" ? "synthetic-$-123" : "synthetic-中文-$-123"
            try ArchiveEngine.create([f], at: archive, executable: engine, options: .init(format: format, password: password))
            XCTAssertNoThrow(try ArchiveEngine.validate(archive, executable: engine, password: password))
            XCTAssertThrowsError(try ArchiveEngine.validate(archive, executable: engine, password: "wrong")) { XCTAssertTrue($0 is ArchivePasswordRequired) }
            XCTAssertThrowsError(try ArchiveEngine.validate(archive, executable: engine, password: nil)) { XCTAssertTrue($0 is ArchivePasswordRequired) }
        }
    }
    func testCorruptArchiveDoesNotRequestPassword() throws {
        let archive = try file("broken.zip", text: "this is not an archive")
        XCTAssertThrowsError(try ArchiveEngine.validate(archive, executable: engine, password: nil)) { XCTAssertFalse($0 is ArchivePasswordRequired) }
    }
    func testArchiveRefusesOverwriteSelfNestedOutputAndControlPassword() throws {
        let source = try folder("source"); _ = try file("data", in: source)
        let existing = try file("existing.zip", text: "original")
        XCTAssertThrowsError(try ArchiveEngine.create([source], at: existing, executable: engine, options: .init()))
        XCTAssertEqual(try String(contentsOf: existing), "original")
        XCTAssertThrowsError(try ArchiveEngine.create([source], at: source.appendingPathComponent("recursive.zip"), executable: engine, options: .init()))
        XCTAssertThrowsError(try ArchiveEngine.create([source], at: root.appendingPathComponent("invalid.zip"), executable: engine, options: .init(password: "a\nb")))
    }
    func testZIPRejectsUnsupportedUnicodePasswordBeforeWriting() throws {
        let source = try file("data"); let output = root.appendingPathComponent("output.zip")
        XCTAssertThrowsError(try ArchiveEngine.create([source], at: output, executable: engine, options: .init(password: "中文")))
        XCTAssertFalse(AdvancedFiles.exists(output))
    }
    func testArchiveFailureCleansPartialAndPreservesSource() throws {
        let source = try file("data")
        let destination = root.appendingPathComponent("fail.zip")
        XCTAssertThrowsError(try ArchiveEngine.create([source], at: destination, executable: URL(fileURLWithPath: "/usr/bin/false"), options: .init()))
        XCTAssertFalse(AdvancedFiles.exists(destination)); XCTAssertTrue(AdvancedFiles.exists(source))
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: root.path).contains { $0.hasPrefix(".itools-archive-") })
    }
    func testSharedMenuHasUniqueSupportedRoutes() {
        XCTAssertEqual(FinderActions.all.count, Set(FinderActions.all.map(\.id)).count)
        XCTAssertNil(FinderActions.action("arbitrary-command"))
    }
}
