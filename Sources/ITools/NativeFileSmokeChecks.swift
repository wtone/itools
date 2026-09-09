import AppKit
import IToolsCore

enum NativeFileSmokeChecks {
    /// The CLI cannot read the protected system Trash without Full Disk Access.
    /// Isolate repeatable recycling tests to their own fixture tree instead.
    static func recycleFixtures(_ sources: [URL], in root: URL, completion: ([URL: URL], Error?) -> Void) {
        var moved: [URL: URL] = [:]
        do {
            let base = root.standardizedFileURL.appendingPathComponent("RecycleFixtures", isDirectory: true)
            guard sources.allSatisfy({ $0.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/") }) else {
                throw UserFacingError("Test recycle rejected a non-fixture path")
            }
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            for source in sources {
                let destination = base.appendingPathComponent(UUID().uuidString + "-" + source.lastPathComponent)
                try FileManager.default.moveItem(at: source, to: destination); moved[source] = destination
            }
            completion(moved, nil)
        } catch { completion(moved, error) }
    }
    static func run(destination: URL) throws {
        let board = NSPasteboard(name: .init("itools-native-smoke-" + UUID().uuidString))
        defer { board.releaseGlobally() }
        let generalBefore = NSPasteboard.general.changeCount
        let clipboard = NativeFileClipboard(board)
        let a = destination.appendingPathComponent("原始 文件.txt"), b = destination.appendingPathComponent("另一个文件.md")
        guard clipboard.write([a, b]), clipboard.files == [a, b] else { throw UserFacingError("Native smoke: file URL pasteboard round trip failed") }
        let beforeMove = board.changeCount
        clipboard.didMove([a], from: [a, b], changeCount: beforeMove)
        guard clipboard.files == [b] else { throw UserFacingError("Native smoke: partial move lost remaining files") }
        let beforeExternalCopy = board.changeCount
        board.clearContents(); board.setString("new external clipboard", forType: .string)
        clipboard.didMove([b], from: [b], changeCount: beforeExternalCopy)
        guard board.string(forType: .string) == "new external clipboard", clipboard.files.isEmpty else {
            throw UserFacingError("Native smoke: stale cut overwrote a newer clipboard")
        }
        // A file copied by Finder has no iTools marker or cut session.
        board.clearContents(); board.writeObjects([b as NSURL])
        guard clipboard.files == [b] else { throw UserFacingError("Native smoke: external file copy was not accepted") }
        guard NSPasteboard.general.changeCount == generalBefore else { throw UserFacingError("Native smoke: user's clipboard changed") }
        for (name, panel) in [("rename-single", FileRenamePanel(files: [a])), ("rename-batch", FileRenamePanel(files: [a,b])),
                              ("rename-repair", FileRenamePanel(files: [a,b], repair: true))] {
            let view = panel.renderPreview()
            guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw UserFacingError("Native smoke: rename preview cannot render") }
            view.cacheDisplay(in: view.bounds, to: bitmap)
            try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name + ".png"))
        }
        print("PASS: native file pasteboard round trip, partial move, external Finder-style copy, stale-cut invalidation; user's clipboard untouched; single-panel rename/repair renders")
    }
}
