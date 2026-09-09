import AppKit

/// Standard file URLs also work with Finder's Copy / Paste / Move Item Here.
/// Never fall back to stale in-memory cut paths after the clipboard changes.
final class NativeFileClipboard {
    let pasteboard: NSPasteboard
    init(_ pasteboard: NSPasteboard = .general) { self.pasteboard = pasteboard }
    var files: [URL] {
        let items = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return items.filter { $0.isFileURL }.map(\.standardizedFileURL)
    }
    @discardableResult func write(_ files: [URL]) -> Bool {
        pasteboard.clearContents()
        return files.isEmpty || pasteboard.writeObjects(files.map { $0 as NSURL })
    }
    func didMove(_ moved: [URL], from original: [URL], changeCount: Int) {
        guard !moved.isEmpty, pasteboard.changeCount == changeCount else { return }
        let movedPaths = Set(moved.map { $0.standardizedFileURL.path })
        _ = write(original.filter { !movedPaths.contains($0.standardizedFileURL.path) })
    }
}
